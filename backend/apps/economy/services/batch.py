"""The batch's in-memory state and its one flush (B03 research R5, data-model.md "The batch's
in-memory state").

A `BatchState` is built for one batch, under the wallet's row lock. It loads each part of the
player's state the first time a handler asks for it, and handlers read and change only it, never
the ORM. Nothing is written until `flush`, so a rejected operation leaves no trace, and a batch of
100 operations costs a handful of queries plus one bulk write per table (research R20).

Every change goes through a method here, which counts it. A handler validates first and changes
last; the engine refuses a handler that changed something and then rejected.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterable, Mapping
from dataclasses import dataclass, field, replace
from datetime import date, datetime
from typing import Any

from apps.accounts.models import NameFilterEntry, Player
from apps.content.services import lookups
from apps.content.services.lookups import Price, TripBounds
from apps.economy.models import (
    DayCounter,
    GrantRecord,
    Inventory,
    LedgerEntry,
    PlayerFlag,
    ProcessedOp,
    Wallet,
)
from apps.economy.services import entitlements, fuel, ledger, wallets
from apps.economy.services.gameday import game_date
from apps.economy.services.settings import EconomySettings
from apps.economy.services.timeline import from_ms, to_ms
from apps.progress.models import Ownership, StoryState, TripProgress, TripRun, TripSession
from apps.progress.services.unlocks import PlayerView

Source = LedgerEntry.Source
DETAIL_MAX = 64


@dataclass
class ProgressRow:
    best_stars: int = 0
    best_time_ms: int | None = None
    plays: int = 0
    first_completed_at: datetime | None = None


@dataclass
class SessionRow:
    """The open trip and the last result (progress.TripSession)."""

    open_start: uuid.UUID | None = None
    open_trip_id: str = ""
    open_rev: int = 0
    open_content_version: int = 0
    open_max_earnings: int = 0
    open_last_station_ms: int = 0
    open_started_at: datetime | None = None
    open_revived: bool = False
    open_traffic_jam_ads: int = 0
    last_start: uuid.UUID | None = None
    last_outcome: str = ""
    last_earnings: int = 0
    last_doubled: bool = False


SESSION_FIELDS = tuple(SessionRow.__dataclass_fields__)


@dataclass
class StoryRow:
    status: str = StoryState.Status.OPEN
    scenes_seen: list[str] = field(default_factory=list)
    completed_at: datetime | None = None


@dataclass(frozen=True)
class OwnershipRow:
    variant: str
    acquired_at: datetime
    acquired_by: uuid.UUID | None


@dataclass(frozen=True)
class Run:
    """A `TripRun` to write."""

    trip_id: str
    rev: int
    start_op: uuid.UUID
    outcome: str
    content_version: int
    stars: int = 0
    fights: int = 0
    mistakes_count: int = 0
    earnings_jenehat: int = 0
    duration_ms: int = 0
    revived: bool = False
    boosters_used: tuple[str, ...] = ()
    command_log_hash: str = ""


@dataclass(frozen=True)
class PackView:
    """One pack version as the validators read it, loaded once per batch."""

    version: int
    rules: Mapping[str, Any]
    prices: Mapping[tuple[str, str], Price]
    trips: Mapping[str, TripBounds]


@dataclass(frozen=True)
class Outcome:
    """One operation's answer, as `POST /v1/sync` returns it and `ProcessedOp` stores it."""

    status: str
    reason: str = ""
    granted: tuple[dict[str, Any], ...] = ()
    details: Mapping[str, Any] | None = None


@dataclass(frozen=True)
class Recorded:
    """An outcome already known for an id: stored earlier, or earlier in this batch."""

    op_type: str
    payload_hash: str
    outcome: Outcome


class BatchState:
    def __init__(
        self,
        player: Player,
        wallet: Wallet,
        *,
        now: datetime,
        settings: EconomySettings,
        processed: Iterable[ProcessedOp] = (),
        referenced: Iterable[uuid.UUID] = (),
        client_version: str = "",
    ) -> None:
        self.player = player
        self.now = now
        self.now_ms = to_ms(now)
        self.settings = settings
        self.client_version = client_version
        self.mutations = 0
        self.op_id: uuid.UUID | None = None
        self._wallet = wallet
        self._entries: list[LedgerEntry] = []
        self._recorded: dict[uuid.UUID, Recorded] = {
            p.client_txn_id: Recorded(p.op_type, p.payload_hash, outcome_of(p)) for p in processed
        }
        self._new_ops: list[ProcessedOp] = []
        self._referenced = set(referenced)
        self._known_runs: set[uuid.UUID] | None = None
        self._runs: list[Run] = []
        self._inventory: dict[str, int] | None = None
        self._inventory_dirty: set[str] = set()
        self._ownership: dict[tuple[str, str], OwnershipRow] | None = None
        self._ownership_new: list[tuple[str, str]] = []
        self._progress: dict[str, ProgressRow] | None = None
        self._progress_dirty: set[str] = set()
        self._session: SessionRow | None = None
        self._session_dirty = False
        self._counters: dict[tuple[date, str], int] | None = None
        self._counters_dirty: set[tuple[date, str]] = set()
        self._story: dict[str, StoryRow] | None = None
        self._story_dirty: set[str] = set()
        self._grants: dict[tuple[str, str], datetime] | None = None
        self._grants_new: list[tuple[str, str, uuid.UUID | None]] = []
        self._flags: dict[tuple[str, date], dict[str, Any]] = {}
        self._profile: dict[str, Any] = {}
        self._name_filter: list[str] | None = None
        self._support: dict[int, str] = {}
        self._packs: dict[int, PackView] = {}

    # -- outcomes ---------------------------------------------------------------------------------

    def recorded(self, client_txn_id: uuid.UUID) -> Recorded | None:
        return self._recorded.get(client_txn_id)

    def status_of(self, client_txn_id: uuid.UUID) -> str | None:
        """`accepted`, `rejected`, or None for an id never seen (the dependency rule, R5)."""
        known = self._recorded.get(client_txn_id)
        return None if known is None else known.outcome.status

    def record(
        self, client_txn_id: uuid.UUID, op_type: str, payload_hash: str, outcome: Outcome
    ) -> None:
        self._recorded[client_txn_id] = Recorded(op_type, payload_hash, outcome)
        self._new_ops.append(
            ProcessedOp(
                player_id=self.player.pk,
                client_txn_id=client_txn_id,
                op_type=op_type[:40],
                payload_hash=payload_hash,
                status=outcome.status,
                reason=outcome.reason,
                result=stored_result(outcome),
                processed_at=self.now,
            )
        )

    def begin(self, client_txn_id: uuid.UUID) -> None:
        self.op_id = client_txn_id

    def _touch(self) -> None:
        self.mutations += 1

    # -- the pack ---------------------------------------------------------------------------------

    def version_status(self, version: int) -> str:
        if version not in self._support:
            self._support[version] = lookups.supported(version, now=self.now)
        return self._support[version]

    def pack(self, version: int) -> PackView:
        """A supported version's rules, prices and trip bounds (`version_status` first)."""
        if version not in self._packs:
            self._packs[version] = PackView(
                version=version,
                rules=lookups.rules(version) or {},
                prices=lookups.catalog_prices(version),
                trips=lookups.trip_bounds(version),
            )
        return self._packs[version]

    # -- currencies -------------------------------------------------------------------------------

    @property
    def jenehat(self) -> int:
        return self._wallet.jenehat

    @property
    def bonat(self) -> int:
        return self._wallet.bonat

    def credit(
        self,
        currency: str,
        amount: int,
        reason: str,
        *,
        ref_type: str = "",
        ref_id: str = "",
        source: str = Source.CLIENT_OP,
    ) -> None:
        self._entry(currency, amount, reason, ref_type, ref_id, source)

    def debit(
        self, currency: str, amount: int, reason: str, *, ref_type: str = "", ref_id: str = ""
    ) -> None:
        """Raises `ledger.InsufficientFunds`, changing nothing; handlers check the balance first."""
        self._entry(currency, -amount, reason, ref_type, ref_id, Source.CLIENT_OP)

    def _entry(
        self, currency: str, delta: int, reason: str, ref_type: str, ref_id: str, source: str
    ) -> None:
        if delta == 0:
            return  # a free thing moves no balance, and the ledger refuses a zero entry
        ledger.apply_entry(
            self._wallet,
            self._entries,
            currency=currency,
            delta=delta,
            reason=reason,
            source=source,
            ref_type=ref_type,
            ref_id=ref_id[:80],
            op_id=self.op_id,
        )
        self._touch()

    # -- fuel and the timeline --------------------------------------------------------------------

    @property
    def timeline_at(self) -> datetime:
        return self._wallet.timeline_at

    def advance_timeline(self, t: datetime) -> None:
        """After an accepted operation. Not a change of the player's state by itself."""
        self._wallet.timeline_at = t

    def fuel_state(self) -> fuel.FuelState:
        return wallets.fuel_state(self._wallet)

    def set_fuel(self, state: fuel.FuelState) -> None:
        if state == self.fuel_state():
            return
        self._wallet.fuel = state.liters
        self._wallet.fuel_updated_at = from_ms(state.counted_from_ms)
        until = state.unlimited_until_ms
        self._wallet.fuel_unlimited_until = None if until is None else from_ms(until)
        self._touch()

    def tank_size(self, at: datetime) -> int:
        return entitlements.tank_size(self.player, at, self.settings)

    @property
    def regen_ms(self) -> int:
        return fuel.regen_ms_of(self.settings.fuel_regen_minutes)

    # -- the comeback return ----------------------------------------------------------------------

    @property
    def comeback_return_at(self) -> datetime | None:
        return self._wallet.comeback_return_at

    # -- inventory --------------------------------------------------------------------------------

    def _inventory_rows(self) -> dict[str, int]:
        if self._inventory is None:
            self._inventory = dict(
                Inventory.objects.filter(player=self.player).values_list("booster_id", "count")
            )
        return self._inventory

    def inventory(self, booster_id: str) -> int:
        return self._inventory_rows().get(booster_id, 0)

    def add_inventory(self, booster_id: str, delta: int) -> None:
        rows = self._inventory_rows()
        count = rows.get(booster_id, 0) + delta
        if count < 0:
            raise ValueError("inventory can't go below 0")
        rows[booster_id] = count
        self._inventory_dirty.add(booster_id)
        self._touch()

    # -- ownership --------------------------------------------------------------------------------

    def _ownership_rows(self) -> dict[tuple[str, str], OwnershipRow]:
        if self._ownership is None:
            rows = Ownership.objects.filter(player=self.player).values_list(
                "kind", "sku_id", "variant", "acquired_at", "acquired_by"
            )
            self._ownership = {
                (kind, sku): OwnershipRow(variant, at, by) for kind, sku, variant, at, by in rows
            }
        return self._ownership

    def owns(self, kind: str, sku_id: str) -> bool:
        return (kind, sku_id) in self._ownership_rows()

    def owned_variant(self, kind: str, sku_id: str) -> str | None:
        row = self._ownership_rows().get((kind, sku_id))
        return None if row is None else row.variant

    def add_ownership(self, kind: str, sku_id: str, variant: str, at: datetime) -> None:
        rows = self._ownership_rows()
        if (kind, sku_id) in rows:
            raise ValueError("already owned")
        rows[(kind, sku_id)] = OwnershipRow(variant, at, self.op_id)
        self._ownership_new.append((kind, sku_id))
        self._touch()

    # -- trip progress, runs and the session ------------------------------------------------------

    def _progress_rows(self) -> dict[str, ProgressRow]:
        if self._progress is None:
            rows = TripProgress.objects.filter(player=self.player).values_list(
                "trip_id", "best_stars", "best_time_ms", "plays", "first_completed_at"
            )
            self._progress = {
                trip: ProgressRow(stars, time, plays, first)
                for trip, stars, time, plays, first in rows
            }
        return self._progress

    def progress(self, trip_id: str) -> ProgressRow:
        """A copy: change it through `set_progress`."""
        return replace(self._progress_rows().get(trip_id) or ProgressRow())

    def set_progress(self, trip_id: str, row: ProgressRow) -> None:
        self._progress_rows()[trip_id] = row
        self._progress_dirty.add(trip_id)
        self._touch()

    def session(self) -> SessionRow:
        """A copy: change it through `set_session`."""
        if self._session is None:
            stored = TripSession.objects.filter(player=self.player).values(*SESSION_FIELDS).first()
            self._session = SessionRow(**stored) if stored else SessionRow()
        return replace(self._session)

    def set_session(self, row: SessionRow) -> None:
        if row == self.session():
            return
        self._session = replace(row)
        self._session_dirty = True
        self._touch()

    def run_exists(self, start_op: uuid.UUID) -> bool:
        """A result (or the abandoned run of a later start) was recorded for this start."""
        if self._known_runs is None:
            self._known_runs = set(
                TripRun.objects.filter(
                    player=self.player, start_op__in=self._referenced
                ).values_list("start_op", flat=True)
            )
        return start_op in self._known_runs or any(r.start_op == start_op for r in self._runs)

    def add_run(self, run: Run) -> None:
        self._runs.append(run)
        self._touch()

    # -- day counters -----------------------------------------------------------------------------

    def _counter_rows(self) -> dict[tuple[date, str], int]:
        if self._counters is None:
            rows = DayCounter.objects.filter(player=self.player).values_list(
                "game_date", "kind", "count"
            )
            self._counters = {(day, kind): count for day, kind, count in rows}
        return self._counters

    def counter(self, kind: str, at: datetime) -> int:
        return self._counter_rows().get((game_date(at), kind), 0)

    def bump_counter(self, kind: str, at: datetime) -> int:
        key = (game_date(at), kind)
        rows = self._counter_rows()
        rows[key] = rows.get(key, 0) + 1
        self._counters_dirty.add(key)
        self._touch()
        return rows[key]

    # -- story and grants -------------------------------------------------------------------------

    def _story_rows(self) -> dict[str, StoryRow]:
        if self._story is None:
            rows = StoryState.objects.filter(player=self.player).values_list(
                "chapter_id", "status", "scenes_seen", "completed_at"
            )
            self._story = {
                chapter: StoryRow(status, list(scenes), completed)
                for chapter, status, scenes, completed in rows
            }
        return self._story

    def story(self, chapter_id: str) -> StoryRow:
        row = self._story_rows().get(chapter_id) or StoryRow()
        return StoryRow(row.status, list(row.scenes_seen), row.completed_at)

    def set_story(self, chapter_id: str, row: StoryRow) -> None:
        self._story_rows()[chapter_id] = row
        self._story_dirty.add(chapter_id)
        self._touch()

    def _grant_rows(self) -> dict[tuple[str, str], datetime]:
        if self._grants is None:
            rows = GrantRecord.objects.filter(player=self.player).values_list(
                "kind", "key", "granted_at"
            )
            self._grants = {(kind, key): at for kind, key, at in rows}
        return self._grants

    def granted(self, kind: str, key: str) -> bool:
        return (kind, key) in self._grant_rows()

    def granted_keys(self) -> frozenset[tuple[str, str]]:
        return frozenset(self._grant_rows())

    def last_grant(self, kind: str) -> datetime | None:
        times = [at for (k, _), at in self._grant_rows().items() if k == kind]
        return max(times) if times else None

    def add_grant(self, kind: str, key: str, at: datetime) -> None:
        rows = self._grant_rows()
        if (kind, key) in rows:
            raise ValueError("already granted")
        rows[(kind, key)] = at
        self._grants_new.append((kind, key, self.op_id))
        self._touch()

    # -- the unlock rules' view of the player -----------------------------------------------------

    def player_view(self) -> PlayerView:
        stars = {trip: row.best_stars for trip, row in self._progress_rows().items()}
        return PlayerView(best_stars=stars, owned=frozenset(self._ownership_rows()))

    # -- the profile ------------------------------------------------------------------------------

    def name_filter(self) -> list[str]:
        """The normalized entries of the name filter, loaded once (research R10)."""
        if self._name_filter is None:
            self._name_filter = list(NameFilterEntry.objects.values_list("normalized", flat=True))
        return self._name_filter

    @property
    def settings_stored(self) -> dict[str, Any]:
        stored = self._profile.get("settings", self.player.settings)
        return dict(stored) if isinstance(stored, dict) else {}

    def set_profile(self, *, display_name: str | None, settings: dict[str, Any] | None) -> None:
        if display_name is not None:
            self._profile["display_name"] = display_name
        if settings is not None:
            self._profile["settings"] = settings
        self._touch()

    # -- flags ------------------------------------------------------------------------------------

    def add_flag(self, kind: str, at: datetime, details: Mapping[str, Any]) -> None:
        """One occurrence. Merged into one row per kind and game day at the flush (research R8).
        Not a change of the player's state."""
        key = (kind, game_date(at))
        pending = self._flags.setdefault(key, {"count": 0})
        pending.update(details)
        pending["count"] += 1

    # -- the answer -------------------------------------------------------------------------------

    @property
    def state_version(self) -> int:
        return self._wallet.state_version

    def wallet_answer(self) -> dict[str, Any]:
        return wallets.answer(self._wallet, self.player, self.now, self.settings)

    # -- the flush --------------------------------------------------------------------------------

    def flush(self) -> bool:
        """Write everything, in the caller's transaction. True if the player's state changed,
        which moves `state_version` by one (FR-015)."""
        changed = self.mutations > 0
        wallet = self._wallet
        if changed:
            wallet.state_version += 1
        ledger.flush_entries(wallet, self._entries)
        wallet.last_active_at = self.now
        wallet.save(
            update_fields=[
                "fuel",
                "fuel_updated_at",
                "fuel_unlimited_until",
                "timeline_at",
                "state_version",
                "last_active_at",
                "updated_at",
            ]
        )
        ProcessedOp.objects.bulk_create(self._new_ops)
        self._flush_inventory()
        self._flush_ownership()
        self._flush_progress()
        self._flush_session()
        self._flush_counters()
        self._flush_story()
        self._flush_grants()
        self._flush_runs()
        self._flush_flags()
        self._flush_profile()
        return changed

    def _flush_inventory(self) -> None:
        if not self._inventory_dirty or self._inventory is None:
            return
        rows = [
            Inventory(player=self.player, booster_id=b, count=self._inventory[b])
            for b in sorted(self._inventory_dirty)
        ]
        Inventory.objects.bulk_create(
            rows,
            update_conflicts=True,
            unique_fields=["player", "booster_id"],
            update_fields=["count", "updated_at"],
        )

    def _flush_ownership(self) -> None:
        if not self._ownership_new or self._ownership is None:
            return
        rows = []
        for kind, sku in self._ownership_new:
            row = self._ownership[(kind, sku)]
            rows.append(
                Ownership(
                    player=self.player,
                    kind=kind,
                    sku_id=sku,
                    variant=row.variant,
                    acquired_at=row.acquired_at,
                    acquired_by=row.acquired_by,
                )
            )
        Ownership.objects.bulk_create(rows)

    def _flush_progress(self) -> None:
        if not self._progress_dirty or self._progress is None:
            return
        rows = []
        for trip in sorted(self._progress_dirty):
            row = self._progress[trip]
            rows.append(
                TripProgress(
                    player=self.player,
                    trip_id=trip,
                    best_stars=row.best_stars,
                    best_time_ms=row.best_time_ms,
                    plays=row.plays,
                    first_completed_at=row.first_completed_at,
                )
            )
        TripProgress.objects.bulk_create(
            rows,
            update_conflicts=True,
            unique_fields=["player", "trip_id"],
            update_fields=[
                "best_stars",
                "best_time_ms",
                "plays",
                "first_completed_at",
                "updated_at",
            ],
        )

    def _flush_session(self) -> None:
        if not self._session_dirty or self._session is None:
            return
        values = {name: getattr(self._session, name) for name in SESSION_FIELDS}
        TripSession.objects.bulk_create(
            [TripSession(player=self.player, **values)],
            update_conflicts=True,
            unique_fields=["player"],
            update_fields=[*SESSION_FIELDS, "updated_at"],
        )

    def _flush_counters(self) -> None:
        if not self._counters_dirty or self._counters is None:
            return
        rows = [
            DayCounter(
                player=self.player, game_date=day, kind=kind, count=self._counters[(day, kind)]
            )
            for day, kind in sorted(self._counters_dirty)
        ]
        DayCounter.objects.bulk_create(
            rows,
            update_conflicts=True,
            unique_fields=["player", "game_date", "kind"],
            update_fields=["count", "updated_at"],
        )

    def _flush_story(self) -> None:
        if not self._story_dirty or self._story is None:
            return
        rows = []
        for chapter in sorted(self._story_dirty):
            row = self._story[chapter]
            rows.append(
                StoryState(
                    player=self.player,
                    chapter_id=chapter,
                    status=row.status,
                    scenes_seen=row.scenes_seen,
                    completed_at=row.completed_at,
                )
            )
        StoryState.objects.bulk_create(
            rows,
            update_conflicts=True,
            unique_fields=["player", "chapter_id"],
            update_fields=["status", "scenes_seen", "completed_at", "updated_at"],
        )

    def _flush_grants(self) -> None:
        if not self._grants_new or self._grants is None:
            return
        GrantRecord.objects.bulk_create(
            GrantRecord(
                player=self.player,
                kind=kind,
                key=key,
                op_id=op_id,
                granted_at=self._grants[(kind, key)],
            )
            for kind, key, op_id in self._grants_new
        )

    def _flush_runs(self) -> None:
        if not self._runs:
            return
        TripRun.objects.bulk_create(
            TripRun(
                player=self.player,
                trip_id=run.trip_id,
                rev=run.rev,
                start_op=run.start_op,
                outcome=run.outcome,
                stars=run.stars,
                fights=run.fights,
                mistakes_count=run.mistakes_count,
                earnings_jenehat=run.earnings_jenehat,
                duration_ms=run.duration_ms,
                revived=run.revived,
                boosters_used=list(run.boosters_used),
                command_log_hash=run.command_log_hash,
                content_version=run.content_version,
                client_version=self.client_version[:32],
            )
            for run in self._runs
        )

    def _flush_flags(self) -> None:
        if not self._flags:
            return
        kinds = {kind for kind, _ in self._flags}
        days = {day for _, day in self._flags}
        existing = {
            (kind, day): details
            for kind, day, details in PlayerFlag.objects.filter(
                player=self.player, kind__in=kinds, game_date__in=days
            ).values_list("kind", "game_date", "details")
        }
        rows = []
        for (kind, day), pending in sorted(self._flags.items()):
            before = existing.get((kind, day)) or {}
            count = int(before.get("count", 0)) + pending["count"]
            rows.append(
                PlayerFlag(
                    player=self.player,
                    kind=kind,
                    game_date=day,
                    details={**before, **pending, "count": count},
                )
            )
        PlayerFlag.objects.bulk_create(
            rows,
            update_conflicts=True,
            unique_fields=["player", "kind", "game_date"],
            update_fields=["details", "updated_at"],
        )

    def _flush_profile(self) -> None:
        if not self._profile:
            return
        for name, value in self._profile.items():
            setattr(self.player, name, value)
        self.player.save(update_fields=[*sorted(self._profile), "updated_at"])


def outcome_of(stored: ProcessedOp) -> Outcome:
    result = stored.result if isinstance(stored.result, dict) else {}
    return Outcome(
        status=stored.status,
        reason=stored.reason,
        granted=tuple(result.get("granted", ())),
        details=result.get("details"),
    )


def stored_result(outcome: Outcome) -> dict[str, Any]:
    """What `ProcessedOp.result` keeps: the grants and details to answer a repeat with, never
    the wallet (research R11)."""
    result: dict[str, Any] = {}
    if outcome.granted:
        result["granted"] = list(outcome.granted)
    if outcome.details:
        # Server-chosen words only; capped all the same, so a stored answer stays small.
        result["details"] = {
            key: value[:DETAIL_MAX] if isinstance(value, str) else value
            for key, value in outcome.details.items()
        }
    return result
