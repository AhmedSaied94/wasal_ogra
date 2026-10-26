"""A payload edited on the phone changes nothing (B03 tasks.md T047, SC-007).

For every operation type, a valid operation in a state where it applies is corrupted one field at
a time: missing, an extra key, a float, a boolean or a string for an integer, a negative number,
an unknown id, a price off by one, a wrong reference. Every corrupted copy is rejected and the
player's state is unchanged; then the valid one is accepted, which shows the state was right.
"""

from __future__ import annotations

import uuid
from collections.abc import Callable, Iterator
from typing import Any

import pytest
from django.utils import timezone

from apps.accounts.models import Player
from apps.economy.models import Currency, GrantRecord, Inventory, LedgerEntry, Wallet
from apps.economy.services import sync
from apps.economy.services.payloads import INT, OBJECT, STR, UUID
from apps.economy.tests.helpers import (
    give,
    grant,
    op,
    ready_for_the_salon,
    reasons,
    result_of,
    run,
    spend,
    trip_start,
    txn_of,
    wallet_of,
)
from apps.progress.models import Ownership, StoryState, TripProgress, TripSession

pytestmark = pytest.mark.django_db

Setup = Callable[[Player, int], dict[str, Any]]


def opened(player: Player, version: int) -> dict[str, Any]:
    start = trip_start("line_hay.01", version)
    assert reasons(run(player, start)) == ["accepted"]
    return start


def _trip_result(player: Player, version: int) -> dict[str, Any]:
    start = opened(player, version)
    return {"trip_start_txn": txn_of(start), "result": result_of("line_hay.01")}


def _use_booster(player: Player, version: int) -> dict[str, Any]:
    assert reasons(run(player, spend("booster", "wake_all", 8, version))) == ["accepted"]
    return {"booster_id": "wake_all", "ref": txn_of(opened(player, version))}


def _comeback_gift(player: Player, version: int) -> dict[str, Any]:
    Wallet.objects.filter(player=player).update(comeback_return_at=timezone.now())
    return {}


def _claim_request(player: Player, version: int) -> dict[str, Any]:
    give(player, ("item", "salon.nish"), variant="crystal")
    return {"request_id": "req_nish_crystal", "content_version": version}


SETUPS: dict[str, Setup] = {
    "trip_start": lambda p, v: {
        "trip_id": "line_hay.01",
        "content_version": v,
        "fuel_mode": "fuel",
    },
    "trip_result": _trip_result,
    "spend_jenehat": lambda p, v: {
        "sku_kind": "item",
        "sku_id": "salon.nish",
        "variant": "classic",
        "price": 400,
        "content_version": v,
    },
    "spend_bonat": lambda p, v: {
        "sku_kind": "booster",
        "sku_id": "change_bag",
        "price": 10,
        "content_version": v,
    },
    "use_booster": _use_booster,
    "ad_reward": lambda p, v: {"ad_placement": "trip_revive", "ref": txn_of(opened(p, v))},
    "story_progress": lambda p, v: {
        "chapter_id": "ch1_first_job",
        "scene_id": "the_stand",
        "content_version": v,
    },
    "settings_update": lambda p, v: {"display_name": "Hamada", "settings": {"digits": "western"}},
    "tutorial_gift": lambda p, v: {},
    "comeback_gift": _comeback_gift,
    "claim_request": _claim_request,
}


def test_every_operation_type_has_a_case() -> None:
    assert set(sync.registered()) <= set(SETUPS)


def corruptions(op_type: str, payload: dict[str, Any]) -> Iterator[tuple[str, dict[str, Any]]]:
    spec = sync.registered()[op_type].payload
    yield "extra key", {**payload, "extra": 1}
    for key, value in payload.items():
        field = spec[key]
        if field.required:
            yield f"no {key}", {k: v for k, v in payload.items() if k != key}
        if field.kind == INT:
            for label, bad in (
                ("float", float(value)),
                ("boolean", True),
                ("string", str(value)),
                ("negative", -1),
                ("plus one", value + 1),
                ("minus one", value - 1),
            ):
                yield f"{key} {label}", {**payload, key: bad}
        elif field.kind == STR:
            # A name is free text, so its "unknown" value is one the name rules refuse.
            unknown = "z" if key == "display_name" else "zzz"
            for label, bad in (("unknown", unknown), ("integer", 7), ("empty", "")):
                yield f"{key} {label}", {**payload, key: bad}
        elif field.kind == UUID:
            for label, bad in (("another id", str(uuid.uuid4())), ("not an id", "x")):
                yield f"{key} {label}", {**payload, key: bad}
        elif field.kind == OBJECT and key == "result":
            yield from (
                (f"result {label}", {**payload, "result": bad})
                for label, bad in result_corruptions(value)
            )
        elif field.kind == OBJECT and key == "settings":
            for label, bad in (
                ("unknown key", {"theme": "dark"}),
                ("bad value", {"digits": "roman"}),
                ("not an object", ["digits"]),
            ):
                yield f"settings {label}", {**payload, "settings": bad}


def result_corruptions(result: dict[str, Any]) -> Iterator[tuple[str, dict[str, Any]]]:
    for key in ("trip_id", "rev", "outcome", "stars", "earnings_jenehat", "duration_ms", "revived"):
        yield f"no {key}", {k: v for k, v in result.items() if k != key}
    yield "another trip", {**result, "trip_id": "line_hay.03"}
    yield "an unknown outcome", {**result, "outcome": "won"}
    yield "four stars", {**result, "stars": 4}
    yield "float stars", {**result, "stars": 3.0}
    yield "boolean stars", {**result, "stars": True}
    yield "too much earned", {**result, "earnings_jenehat": 100_000}
    yield "negative earnings", {**result, "earnings_jenehat": -1}
    yield "float earnings", {**result, "earnings_jenehat": 10.0}
    yield "too fast", {**result, "duration_ms": 1}
    yield "failed with stars", {**result, "outcome": "failed"}
    yield "mistakes not a list", {**result, "mistakes": 0}
    yield "over 8 KB", {**result, "padding": "x" * 9000}


def state_of(player: Player) -> tuple[Any, ...]:
    wallet = wallet_of(player)
    session = TripSession.objects.filter(player=player).values().first()
    return (
        wallet.jenehat,
        wallet.bonat,
        wallet.fuel,
        wallet.fuel_unlimited_until,
        wallet.state_version,
        LedgerEntry.objects.filter(player=player).count(),
        sorted(Inventory.objects.filter(player=player).values_list("booster_id", "count")),
        Ownership.objects.filter(player=player).count(),
        TripProgress.objects.filter(player=player).count(),
        None if session is None else {k: v for k, v in session.items() if k != "updated_at"},
        sorted(StoryState.objects.filter(player=player).values_list("chapter_id", "scenes_seen")),
        GrantRecord.objects.filter(player=player).count(),
        wallet.comeback_return_at,
        Player.objects.values_list("display_name", "settings").get(pk=player.pk),
    )


@pytest.mark.parametrize("op_type", sorted(SETUPS))
def test_each_corrupted_field_is_rejected_and_changes_nothing(
    player: Player, published_pack: int, op_type: str
) -> None:
    grant(player, Currency.JENEHAT, 10_000)
    grant(player, Currency.BONAT, 1_000)
    ready_for_the_salon(player)
    payload = SETUPS[op_type](player, published_pack)
    before = state_of(player)
    cases = list(corruptions(op_type, payload))
    result = run(player, *(op(op_type, bad) for _, bad in cases))
    accepted = [
        label
        for (label, _), r in zip(cases, result.results, strict=True)
        if r.outcome.status == "accepted"
    ]
    assert accepted == []
    assert state_of(player) == before
    assert reasons(run(player, op(op_type, payload))) == ["accepted"]
