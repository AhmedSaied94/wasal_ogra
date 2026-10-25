---

description: "Task list for B03 Economy Ledger, Bootstrap and Sync"
---

# Tasks: Economy Ledger, Bootstrap and Sync (B03)

**Input**: Design documents from `specs/010-b03-ledger-sync/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**:

- **Mandatory, and first.** Tests are required (constitution XIII). Every phase writes its tests
  first, and they must fail before its implementation tasks start. The constitution requires it
  for ledger and sync validators (spec FR-009, FR-013, SC-001–SC-004, SC-007).
- **Real services.** Backend tests run against real PostgreSQL and Valkey, never mocks. Pack data
  comes from B04's real publish path (the sample pack, built and published by the helpers the
  content tests already use), not from hand-made rows. Time moves with `time-machine`.
- **Coverage.** At least 80% for the backend (CI gate), and 100% of lines in
  `apps/economy/services/ledger.py` and `apps/economy/services/fuel.py`.

**Organization**:

- **Paths** are from the repository root. Run `uv` commands in `backend/`.
- **One PR** (plan "Delivery"). Phases 3–9 follow the spec's user stories in priority order.
  Story 7's flag sites and Story 6's settings operation sit where the plan's research puts them
  (R6, R8, R10), noted in each phase.
- **Owner tasks** need the owner's hosts. An agent can't do them alone.
- **Constraints are quoted** from `data-model.md` and the contracts. Do not loosen them.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story the task belongs to (US1–US7 from spec.md)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: The timezone data, the settings placeholders, the two new apps and the test profiles
(plan "Technical Context", research R3, R14).

- [X] T001 Confirm the image can resolve `Africa/Cairo` (research R3):
  - run `python -c "import zoneinfo; zoneinfo.ZoneInfo('Africa/Cairo')"` in the built backend image
    (`backend/docker/Dockerfile`);
  - if it fails, add `"tzdata"` to `[project] dependencies` in `backend/pyproject.toml`, run
    `uv lock` and `uv sync`, and commit `backend/uv.lock`. If it passes, add nothing.
- [X] T002 [P] Add B03's variables to `backend/.env.example`, under a comment block that points at
  `specs/010-b03-ledger-sync/contracts/environment.md`, each with its default from that file's
  tables: `ECONOMY_FUEL_MAX=5`, `ECONOMY_FUEL_MAX_SUBSCRIBER=7`, `ECONOMY_FUEL_REGEN_MINUTES=20`,
  `ECONOMY_FUEL_REFILL_DAILY_CAP=3`, `ECONOMY_FUEL_OVERDRAFT_PER_DAY=2`,
  `ECONOMY_TRAFFIC_JAM_ADS_PER_TRIP=1`, `ECONOMY_NAME_MIN_LENGTH=2`, `ECONOMY_NAME_MAX_LENGTH=20`,
  `SYNC_GAME_TIMEZONE=Africa/Cairo`, `SYNC_OP_RETENTION_DAYS=180`, `SYNC_CONTENT_MAX_AGE_DAYS=45`,
  `SYNC_MIN_DURATION_PERCENT=85`, `SYNC_FAST_RUN_PERCENT=95`, `SYNC_TRIPS_PER_DAY_FLAG=400`,
  `SYNC_CLOCK_CLAMP_FLAG_MINUTES=10`, `SYNC_SESSION_GAP_MINUTES=30`, `SYNC_COMEBACK_AWAY_DAYS=7`,
  `SYNC_COMEBACK_COOLDOWN_DAYS=30`, `THROTTLE_SYNC_RATE=60/min`, `CLIENT_MIN_VERSION=1.0.0`,
  `CLIENT_LATEST_VERSION=1.0.0`, `CONTENT_INDEX_KEEP=10`.
- [X] T003 [P] Create the two app packages, empty but importable (plan "Source Code"):
  - `backend/apps/economy/{__init__.py,apps.py,models.py}` with `EconomyConfig` (`name =
    "apps.economy"`), and `services/__init__.py`, `api/__init__.py`, `tests/__init__.py`;
  - `backend/apps/progress/{__init__.py,apps.py,models.py}` with `ProgressConfig`, and
    `services/__init__.py`, `tests/__init__.py`;
  - add `"apps.progress"` and `"apps.economy"` to `INSTALLED_APPS` in
    `backend/config/settings/base.py`, after `apps.content` and in that order (`economy` imports
    `progress`, never the reverse).
- [X] T004 [P] Extend the `no_throttle` fixture in `backend/conftest.py` to also set
  `THROTTLE_SYNC_RATE` to `None`. B02's `ci` and `thorough` hypothesis profiles stay as they are.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: What every story needs:

- the settings and their startup checks;
- the test helpers;
- the game day, the integer fuel rules, the ledger function and the flag writer;
- the economy and progress models;
- the unlock rules;
- B04's index extended with the rules document;
- the batch engine, with an empty operation registry;
- the invariant, the writer scan and the tunables check.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Tests (write first, they must fail)

- [X] T005 [P] Write the shared helpers in `backend/apps/economy/tests/conftest.py` and
  `backend/apps/economy/tests/helpers.py` (no tests of their own):
  - a `published_pack` fixture that builds and publishes the sample pack through
    `apps.content.tests.test_build.built` and `apps.content.tests.test_publish.published` (as
    `apps/content/tests/test_lookups.py` does), returning its version, and a `published_packs(n)`
    factory for several versions;
  - a `player` fixture (a real `Player` from `apps.accounts.services.players`) and an `api` fixture
    that signs in through `POST /v1/auth/anonymous` and returns a test client with the bearer token
    and the two client headers;
  - `op(op_type, payload, *, at=None, txn=None)` building one envelope with a new UUIDv7
    `client_txn_id` and an ISO-8601 UTC `occurred_at`, and `batch(*ops, base=0)`;
  - `wallet_of(player)` and `ledger_sum(player, currency)` helpers.
- [X] T006 [P] Extend `backend/tests/test_settings_guards.py` and `backend/tests/test_env.py` for the
  economy settings (contracts/environment.md "Checks"), in the existing subprocess pattern:
  - **Refused, naming the variable:** each integer outside the range in the tables; a non-integer;
    `ECONOMY_FUEL_MAX_SUBSCRIBER` below `ECONOMY_FUEL_MAX`; `SYNC_FAST_RUN_PERCENT` below
    `SYNC_MIN_DURATION_PERCENT`; `CLIENT_MIN_VERSION` above `CLIENT_LATEST_VERSION` or not
    `MAJOR.MINOR.PATCH`; a `SYNC_GAME_TIMEZONE` that is not an IANA zone; `THROTTLE_SYNC_RATE` that
    fails B01's `RATE_PATTERN`; `CONTENT_INDEX_KEEP` outside 5–50.
  - **Accepted:** the defaults in every environment (none of these is a secret, so no
    `change-me` refusal applies).
- [X] T007 [P] Write `backend/apps/economy/tests/test_gameday.py` (research R3):
  - `game_date` of `2026-10-17T21:59:59Z` and `22:00:00Z` differs in `Africa/Cairo` in summer time
    (UTC+3) and in winter time (UTC+2), around a daylight-saving change;
  - the zone comes from `SYNC_GAME_TIMEZONE` (override with `settings`).
- [X] T008 [P] Write `backend/apps/economy/tests/test_fuel.py` and
  `backend/apps/economy/tests/test_fuel_fixtures.py` (contracts/fuel.md, research R7, R15):
  - **Create `fixtures/economy/fuel.json`** with every worked example of
    `specs/007-m05-local-economy/contracts/fuel-and-time.md` as `scope: "both"` cases, in the format
    of contracts/fuel.md "Shared fixtures" (the case "start from a full tank counts from the start"
    is the first). Server-scope cases are added in T062.
  - `test_fuel_fixtures.py` replays every case through `economy.services.fuel` and compares the
    liters, `counted_from`, `unlimited_until` and `accepted`/`reason` after each step.
  - `test_fuel.py`: `regenerate`, `spend_one`, `fill_to_max` (`tank_full`), `extend_unlimited` and
    `is_unlimited` against hand-computed values; integer arithmetic only (a test that the module
    source has no `float(`, `Decimal` or `/` outside comments and strings).
- [X] T009 [P] Write `backend/apps/economy/tests/test_ledger.py` (research R4, spec FR-005–FR-007):
  - `apply_entry` appends one entry and moves the balance, with `balance_after` equal to the new
    balance;
  - a delta that would take a balance **below 0** raises `InsufficientFunds` and writes nothing;
  - a delta of 0 is refused (`CHECK (delta <> 0)`);
  - calling it with a wallet that was not obtained from `lock_wallet`, or outside an atomic block,
    raises a programming error;
  - `LedgerEntry.save()` on an existing row raises, and `LedgerEntry.objects.update()` and
    `delete()` raise;
  - `Wallet` `CHECK (jenehat >= 0)`, `CHECK (bonat >= 0)` and `CHECK (fuel >= 0)` hold at the
    database (raw `UPDATE` raises `IntegrityError`).
- [X] T010 [P] Write `backend/apps/economy/tests/test_models.py` (data-model.md "economy"):
  - `ProcessedOp`: a second row with the same `(player, client_txn_id)` raises `IntegrityError`;
  - `Inventory`: unique `(player, booster_id)`;
  - `PlayerFlag`: unique `(player, kind, game_date)`;
  - `DayCounter`: unique `(player, game_date, kind)`;
  - `GrantRecord`: unique `(player, kind, key)`;
  - `WalletAdjustment`: `save()` on an existing row raises, and deletes raise;
  - every primary key is a UUIDv7 (`common.E001` passes), and `LedgerEntry.op_id` is a plain UUID
    column, not a foreign key.
- [X] T011 [P] Write `backend/apps/progress/tests/test_models.py` (data-model.md "progress"):
  - `TripProgress` unique `(player, trip_id)` and `CHECK (best_stars BETWEEN 0 AND 3)`;
  - `TripRun` unique `(player, start_op)` and the two indexes;
  - `Ownership` unique `(player, kind, sku_id)`; `StoryState` unique `(player, chapter_id)`;
  - `TripSession`, `DailyState` are one row per player (the player is the primary key).
- [X] T012 [P] Write `backend/apps/progress/tests/test_unlocks.py` (research R6) over the published
  sample pack's rules document and hand-built player states:
  - vehicle owned by `starter` flag or `Ownership`; line unlocked for `start`, `vehicle` and
    `line_complete`; line complete when every `regular` trip has `best_stars ≥ 1`;
  - trip unlocked: first trip of a line free; a later one needs the previous (ordered by `trip_id`)
    with `best_stars ≥ 1`; its vehicle owned; a `story` trip needs only its chapter unlocked;
  - chapter unlocked: the first always, chapter *n* when *n−1* is complete; chapter complete for
    each goal kind (`complete_line`, `own_vehicle`, `purchase`, `complete_room`);
  - room complete when every item of the room is owned; item purchasable when its room's chapter is
    unlocked;
  - `newly_completed(state)` returns rooms before chapters, in `order`, and skips any with a
    `GrantRecord`.
- [X] T013 [P] Write `backend/apps/content/tests/test_lookups_rules.py` and update
  `backend/apps/content/tests/test_lookups.py` (research R2):
  - `index_pack` writes one `PackRulesIndex` row per version, equal to the shape in data-model.md
    "PackRulesIndex" and to the pack file (lines with `unlock` and ordered trips, vehicles'
    `starter`, chapters, rooms with `items`, items with `variants`, requests);
  - `lookups.rules(version)` returns it or `None`;
  - `lookups.supported(version)` is true for the current version and for a version published within
    `SYNC_CONTENT_MAX_AGE_DAYS`, false for an older one (use `time-machine`) and for a version
    without index rows; it distinguishes "never published" from "not supported" (two outcomes);
  - `CONTENT_INDEX_KEEP` replaces the constant 5: with the setting at 5 the existing test's
    expectations (six versions, the last five indexed) still hold, and at 10 the sixth is kept.
    Update `test_lookups.py` to override the setting to 5 where it assumes five.
  - `content_index --rebuild` writes rules rows for published packs inside the window from their
    stored files, is idempotent (a second run changes nothing), and prints each version's counts.
- [X] T014 [P] Extend `backend/apps/common/tests/test_errors.py` and
  `backend/apps/common/tests/test_throttles.py` (contracts/api.md, research R18):
  - `batch_too_large` renders as `400` with the message `Batch too large` and `details.max`;
  - `SyncThrottle` limits `POST /v1/sync` to `THROTTLE_SYNC_RATE` per **player** (two players on
    one address do not share it), fails open when the cache is down, and bootstrap and state use
    only the player default.
- [X] T015 [P] Write `backend/apps/economy/tests/test_batch_engine.py` (research R5) with a fake
  operation registered in the test (two handlers: one that credits JENEHAT, one that always raises
  `Rejected("insufficient_funds")`), calling `process_batch` directly:
  - operations run **in array order**; a rejected one does not stop the batch and leaves no trace
    (no ledger, no `ProcessedOp` side effect other than its own stored rejection);
  - **idempotency:** a stored id returns the stored outcome and applies nothing; the same id twice
    in one batch returns the first outcome for the second; a changed type or payload under a stored
    id returns the stored outcome and raises a `txn_payload_mismatch` flag;
  - `op_expired` for an id whose UUIDv7 time is older than `SYNC_OP_RETENTION_DAYS` or more than a
    day ahead; `unknown_op_type` for an unregistered type; `validation_error` for a payload with a
    float, a boolean where an integer belongs, or an unlisted key (per operation, stored);
  - **atomicity:** if the flush raises, nothing of the batch is stored (wallet, ledger and
    `ProcessedOp` unchanged);
  - `state_version` goes up by exactly 1 for a batch that changed anything and stays for one that
    did not; `state_stale` is true exactly when `base_state_version` differs;
  - the wallet is created on first use with `fuel = ECONOMY_FUEL_MAX`, 0 JENEHAT, 0 BONAT,
    `state_version` 0 (FR-011).
- [X] T016 [P] Write `backend/apps/economy/tests/test_balance_writers.py` (research R4, FR-009): parse
  every `.py` under `backend/apps` with `ast` and fail on any of:
  - an assignment or augmented assignment to an attribute named `jenehat` or `bonat` outside
    `apps/economy/services/ledger.py`;
  - a `.update(` call with a `jenehat=` or `bonat=` keyword, or a `Wallet(` construction with a
    balance keyword, outside `ledger.py` and `migrations/`;
  - a `save(update_fields=[...])` or `bulk_update(..., fields=[...])` naming `"jenehat"` or
    `"bonat"`, and a `LedgerEntry(` construction or `LedgerEntry.objects.bulk_create(` call, outside
    `ledger.py` and `migrations/` (the batch flush must go through `ledger.flush_entries`);
  - a string constant containing `economy_wallet` next to `UPDATE` (raw SQL).
  The exemption list is a literal in the test. Add a negative test that feeds the scanner a
  snippet with a violation and expects a failure.
- [X] T017 [P] Write `backend/apps/economy/tests/test_tunables_parity.py` (research R14): read
  `apps/mobile/assets/config/tunables.json` and assert `fuel_max`, `fuel_max_subscriber`,
  `fuel_regen_minutes` and `ads_fuel_refill_daily_cap` equal `ECONOMY_FUEL_MAX`,
  `ECONOMY_FUEL_MAX_SUBSCRIBER`, `ECONOMY_FUEL_REGEN_MINUTES` and `ECONOMY_FUEL_REFILL_DAILY_CAP`
  **defaults** (read from `env.economy()` with an empty environment, not from the running settings).
- [X] T018 [P] Write `backend/apps/economy/tests/test_invariant.py` (spec FR-010):
  - `economy.wallet_equals_ledger` is registered after Django starts, and
    `backend/apps/common/tests/test_invariants.py`'s expected set gains it;
  - it passes for players with consistent data and fails, reporting the number of differing players,
    when a test corrupts a wallet with raw SQL;
  - `manage.py economy_check` prints the same result and exits 1 on a mismatch.

### Implementation

- [X] T019 Add the economy reader to `backend/config/env.py` (`env.economy()` returning a frozen
  dataclass) and the settings to `backend/config/settings/base.py` and `test.py`, exactly the
  variables, defaults and ranges of contracts/environment.md (integers only: percentages are integer
  percents). Add `THROTTLE_SYNC_RATE` to `DEFAULT_THROTTLE_RATES` as `sync`, and
  `CONTENT_INDEX_KEEP`. Validate in `check_environment` (T006 passes).
- [X] T020 [P] Add `batch_too_large` to `ErrorCode`, `MESSAGES` (`Batch too large`) and `STATUSES`
  (400) in `backend/apps/common/errors.py`, and `SyncThrottle` (scope `sync`, key `player_id`,
  rate setting `THROTTLE_SYNC_RATE`) in `backend/apps/common/throttles.py` (T014 passes).
- [X] T021 [P] Write `backend/apps/economy/services/gameday.py` (`game_date(instant) -> date` with
  `zoneinfo`, zone from `settings.SYNC_GAME_TIMEZONE`) and `backend/apps/economy/services/settings.py`
  (a frozen dataclass of the economy settings, built from `django.conf.settings`) (T007 passes).
- [X] T022 [P] Write `backend/apps/economy/services/fuel.py` (T008 passes): `FuelState` (frozen
  dataclass of `liters`, `counted_from_ms`, `unlimited_until_ms`), and `regenerate`, `spend_one`,
  `fill_to_max`, `extend_unlimited`, `is_unlimited` exactly as contracts/fuel.md, in integer
  milliseconds and integer floor division. No `float`, `Decimal` or `/`.
- [X] T023 Write the economy models in `backend/apps/economy/models.py` and generate
  `backend/apps/economy/migrations/0001_economy.py` with `uv run manage.py makemigrations economy`
  (T009, T010 pass). Fields, constraints and indexes are data-model.md's, quoted:
  - `Wallet`: `player` OneToOne primary key `PROTECT`; `jenehat`, `bonat` `PositiveBigInteger`
    default 0; `fuel` `PositiveSmallInteger`; `fuel_updated_at`, `fuel_unlimited_until` (null),
    `timeline_at`, `last_active_at`, `session_started_at`, `comeback_return_at` (null);
    `state_version` `PositiveInteger` default 0; `CHECK (jenehat >= 0)`, `CHECK (bonat >= 0)`,
    `CHECK (fuel >= 0)`.
  - `LedgerEntry`: `player` FK `PROTECT`; `currency` (`JENEHAT`, `BONAT`); `delta` `BigInteger`;
    `balance_after` `PositiveBigInteger`; `reason` (backend §7.2's set plus `request_reward`,
    `story_reward`); `ref_type` varchar(16) blank; `ref_id` varchar(80) blank; **`op_id` UUID null,
    not a foreign key**; `source` (`client_op`, `purchase`, `ssv`, `system`, `admin`);
    `CHECK (delta <> 0)`; indexes `(player, created_at)` and `(player, currency)`; a manager and
    `save()` that refuse updates and deletes.
  - `ProcessedOp`: `player` FK; `client_txn_id` UUID; `op_type` varchar(40); `payload_hash`
    char(64); `status` (`accepted`, `rejected`); `reason` varchar(40) blank; `result` JSON;
    `processed_at`; unique `(player, client_txn_id)`; index on `processed_at`.
  - `Inventory` (unique `(player, booster_id)`), `PlayerFlag` (kinds `fuel_overdraft`,
    `fast_three_star`, `trip_rate`, `txn_payload_mismatch`, `clock_clamped`; `game_date`; `details`
    JSON; `reviewed_by` FK `accounts.User` null `PROTECT`; `reviewed_at` null; `resolution`
    varchar(200) blank; unique `(player, kind, game_date)`; a partial index on `reviewed_at IS
    NULL`), `DayCounter` (kinds `overdraft`, `fuel_refill_ad`, `trips_started`; unique `(player,
    game_date, kind)`), `GrantRecord` (kinds `tutorial`, `comeback`, `request`, `room`, `chapter`;
    `key` varchar(80); unique `(player, kind, key)`), `WalletAdjustment` (append-only; `reason`
    varchar(200)).
  - Add the custom permission `adjust_wallet` to `Wallet.Meta.permissions`.
- [X] T024 Write the progress models in `backend/apps/progress/models.py` and generate
  `backend/apps/progress/migrations/0001_progress.py` (T011 passes), data-model.md's fields: 
  `TripProgress` (`CHECK (best_stars BETWEEN 0 AND 3)`), `TripRun` (outcome `finished`, `failed`,
  `abandoned`; unique `(player, start_op)`; indexes `(created_at)`, `(player, created_at)`),
  `TripSession` (player primary key; the `open_*` and `last_*` columns), `Ownership` (kinds
  `vehicle`, `upgrade`, `cosmetic`, `item`, `chapter`; unique `(player, kind, sku_id)`),
  `StoryState` (status `open`, `completed`; `scenes_seen` an `ArrayField` of varchar; unique
  `(player, chapter_id)`), `DailyState` (player primary key; `streak`, `longest_streak`,
  `last_claim_game_date`, `task_counters` JSON, `tasks_game_date`).
- [X] T025 Add `PackRulesIndex` to `backend/apps/content/models/packs.py` and its migration, and
  extend `backend/apps/content/services/lookups.py` (T013 passes): `index_pack` also writes the
  rules document; `rules(version)`, `supported(version)` returning one of `supported`,
  `unknown` (no `ContentPack` row for the number) or `unsupported`; `retire_beyond_five` becomes
  `retire_beyond_keep` reading `settings.CONTENT_INDEX_KEEP` (and its callers in
  `publish.py` and `promote.py` change), also deleting the retired version's rules row.
- [X] T026 Write `backend/apps/content/management/commands/content_index.py` with `--rebuild`
  (T013 passes; needs `index_pack` and `PackRulesIndex` from T025, so it runs after T025): for each published pack inside the support window, read its stored pack file in the
  worker and write the missing trip, price and rules rows; idempotent; print the counts per version.
- [X] T027 Write `backend/apps/economy/services/ledger.py` (T009 passes): `lock_wallet(player)`
  (insert-or-ignore, then `select_for_update`, atomic required) and `apply_entry(...)` as in research
  R4, the **only** code that changes `Wallet.jenehat` or `Wallet.bonat`, and the only code that
  constructs or inserts a `LedgerEntry`. `apply_entry(batch, ...)` changes the in-memory wallet and
  queues the entry; `flush_entries(wallet, entries)` bulk-inserts the entries and saves the two
  balance columns (`update_fields=["jenehat", "bonat"]`), and T030's `BatchState.flush()` calls it
  and nothing else for balances. It also exposes `InsufficientFunds`. 100% line coverage.
- [X] T028 Write (after T030, which defines `BatchState`) `backend/apps/economy/services/flags.py` (`raise_flag(batch, kind, details)`:
  one row per `(player, kind, game_date)` with `details.count` incremented, appended to the batch's
  writes) and `backend/apps/economy/services/entitlements.py` (the seam: `flags_for(player, at)`
  returns `{"no_interstitials": False, "fuel_max_bonus": 0}` until B06/B12).
- [X] T029 Write `backend/apps/progress/services/unlocks.py` (T012 passes): the rules of research R6
  as pure functions over a rules document and a read-only player-state view (no ORM inside).
- [X] T030 Write the batch engine: `backend/apps/economy/services/batch.py` (`BatchState` loading
  lazily the wallet, inventory, ownership, trip progress, trip session, day counters, story rows and
  grant records, caching the pack lookups per version, and collecting ledger entries, processed
  operations, trip runs and flags; `flush()` bulk-writes them, calls `ledger.flush_entries` for the
  entries and the two balance columns (T027; `batch.py` never saves `jenehat` or `bonat` itself, which
  T016 checks), saves the wallet's other columns, and bumps `state_version` once) and
  `backend/apps/economy/services/sync.py` (`process_batch`, the `Rejected` exception, the handler
  registry `register(op_type)`, the order of checks in contracts/operations.md "Order of checks
  common to every operation"). Handlers never touch the ORM (T015 passes).
- [X] T031 Register the invariant: `backend/apps/economy/invariants.py` with
  `@register("economy.wallet_equals_ledger")` running one grouped-`SUM` SQL aggregate with
  parameterized queries, `EconomyConfig.ready()` importing it, and
  `backend/apps/economy/management/commands/economy_check.py` (T016, T017, T018 pass). Update the
  expected set in `backend/apps/common/tests/test_invariants.py`.

**Checkpoint**: the engine runs an empty registry, the ledger and fuel rules are proven, and the
guards are green.

---

## Phase 3: User Story 1 - Trips played offline reach the server once and in order (Priority: P1) 🎯 MVP

**Goal**: `POST /v1/sync` applies `trip_start` and `trip_result` in order, idempotently, and answers
with the authoritative wallet.

**Independent Test**: send a batch of `trip_start` + `trip_result`, then the same batch again, then
once more with one extra operation: the wallet moves once, then once more for the new operation
(quickstart A4).

### Tests for User Story 1 (write first, they must fail)

- [X] T032 [P] [US1] Write `backend/apps/economy/tests/test_op_trip_start.py` (operations.md
  `trip_start`), one case per reason in order: `unknown_trip`; `not_eligible` for `unlimited`
  outside a window and for `challenge`; `not_unlocked` (line locked, vehicle not owned, previous
  trip not at 1 star; a `story` trip needs only its chapter); accepted: fuel −1, `trips_started`
  counter +1, the open trip stores `max_earnings_jenehat` and the last station time of the **declared
  version's** trip; a start while another is open closes the older one as abandoned (a `TripRun` with
  outcome `abandoned`, 0 stars, 0 earnings, `plays` + 1).
- [X] T033 [P] [US1] Write `backend/apps/economy/tests/test_op_trip_result.py` (operations.md
  `trip_result`), one case per reason in order: `dependency_rejected`, `result_exists` (including
  the abandoned run of a later start), `no_trip_start`, `trip_mismatch`, `stars_out_of_bounds`
  (stars 0–3, and 0 unless `finished`), `earnings_out_of_bounds` (`0 ≤ earnings ≤ max_earnings_jenehat`
  of the **start's** pack trip, 0 unless `finished`), `duration_out_of_bounds` (`finished` below
  `SYNC_MIN_DURATION_PERCENT` % of the last station time). Accepted: JENEHAT + earnings with reason
  `trip_earnings`, `TripProgress` (`plays` + 1; `best_stars` the maximum and `best_time_ms` the
  minimum over runs with ≥ 1 star; `first_completed_at` once), a `TripRun`, the trip closed and the
  last result set. A `result` over 8 KB is `validation_error`; unknown keys inside `result` are
  ignored.
- [X] T034 [P] [US1] Write `backend/apps/economy/tests/test_sync_api.py` (contracts/api.md "POST
  /v1/sync", spec US1 scenarios 1–8): the answer shape, an empty `ops` list answering 200 with the
  current wallet, a batch of 100 accepted and 101 refused with `batch_too_large` and `details.max`,
  a body over 256 KB refused (`payload_too_large`), malformed envelope (`ops[3].client_txn_id`
  named in `details`), non-JSON `415`, no token / expired / deleted player (B02 codes, nothing
  applied), a missing client header, and `429` after 60 batches a minute with `Retry-After`.
- [X] T035 [P] [US1] Write `backend/apps/economy/tests/test_sync_idempotency.py` (SC-001): the same
  batch sent twice and three times gives identical `results` and wallet and one set of rows; a
  batch of 20 trips played "offline" is sent in 3 batches with every fifth answer "lost" (the
  request is repeated) and ends with the same state as one clean run (compare wallet, progress, ledger).
- [X] T036 [P] [US1] Write `backend/apps/economy/tests/test_sync_concurrency.py` (SC-004, FR-012): with
  real threads, (a) the same batch sent twice at once is applied once and both answers carry the same
  results; (b) two different batches of one player at once are applied one after the other with no
  lost update and no negative balance.
- [X] T037 [P] [US1] Write `backend/apps/economy/tests/test_batch_cost.py` (research R20): a fixture batch
  of 100 `trip_start`/`trip_result` pairs runs in at most 40 queries (`django_assert_max_num_queries`).
- [X] T038 [P] [US1] Write `backend/apps/economy/tests/test_properties.py` (SC-002, spec FR-006,
  FR-013): a hypothesis stateful machine over `trip_start`/`trip_result` with random times and random
  batching, applying some batches twice; after every batch assert `wallet == sum(ledger)` for both
  currencies, no balance below 0, `state_version` never decreasing, and that re-applying a batch
  changes nothing. Later phases add rules to the same machine. Profiles `ci` (300) and `thorough`
  (10,000) from B02's conftest.

### Implementation for User Story 1

- [X] T039 [US1] Write `backend/apps/economy/services/ops/trips.py` with the `trip_start` and
  `trip_result` handlers (T032, T033 pass), using `progress.services.unlocks` and the pack lookups
  of the declared version; register both in `sync.py`'s registry. Fuel moves through `fuel.py` at the
  operation's effective time (clamps are Phase 7; until then the effective time is `occurred_at`
  bounded by now). JENEHAT moves only through `ledger.apply_entry`.
- [X] T040 [P] [US1] Write the sync API: `backend/apps/economy/api/serializers.py` (strict envelope
  with `ListField(max_length=100)` and a closed payload per operation; integers only, rejecting a
  boolean or a float; raw body limit 256 KB checked before parsing), `api/views.py` (`SyncView`
  thin: calls `process_batch`; throttles `PlayerRateThrottle` + `SyncThrottle`; `ClientHeaders`),
  `api/messages.py`, and the route `POST /v1/sync` in `backend/config/urls.py` (T034 passes).
- [X] T041 [US1] Regenerate `contracts/openapi.yaml` (`uv run manage.py spectacular --file
  ../contracts/openapi.yaml --validate --fail-on-warn`) with the sync path, the batch and result
  schemas and every reason documented (operations.md "Reasons"); `backend/tests/test_openapi_drift.py`
  passes.
- [X] T042 [US1] Run T035–T038 against the implementation and fix what they find, in
  `ops/trips.py`, `batch.py` or `sync.py` (not in the tests). Confirm coverage of those modules.

**Checkpoint**: US1 works on its own: offline trips reach the server once and in order. This is the
MVP slice for M06.

---

## Phase 4: User Story 2 - BONAT and JENEHAT can't be made up on the phone (Priority: P1)

**Goal**: purchases, boosters and in-trip ads are checked against the pack, the catalog and the
server's own balance.

**Independent Test**: for every operation type, send it with each field wrong in turn: each is
rejected and the ledger does not change (SC-007).

### Tests for User Story 2 (write first, they must fail)

- [X] T043 [P] [US2] Write `backend/apps/economy/tests/test_op_spend_jenehat.py` (operations.md
  `spend_jenehat`), one case per reason in the table's order: `unknown_sku`, `not_for_sale`,
  `price_mismatch` (price off by 1, and a BONAT-priced sku), `unknown_variant`, `already_owned`,
  `not_unlocked` (an item whose chapter is locked, a chapter whose predecessor is incomplete),
  `insufficient_funds` last (a purchase that cannot apply is never reported as unaffordable); accepted
  for each of `item` (variant required, refused otherwise), `vehicle`, `chapter`, `upgrade` with
  the reasons `item_purchase`, `vehicle_purchase`, `chapter_purchase`, `upgrade_purchase` and an
  `Ownership` row.
- [X] T044 [P] [US2] Write `backend/apps/economy/tests/test_op_spend_bonat.py` (operations.md
  `spend_bonat`): the table of kinds (`booster` ×4 → inventory + 1, `fuel/refuel_full`,
  `fuel_unlimited/fuel_unlimited_1h`, `revive/revive`, `cosmetic`), the common order `unknown_sku`,
  `not_for_sale`, `price_mismatch`, the row's own checks (`tank_full`; a revive's `dependency_rejected`,
  `no_trip`, `already_revived`; `already_owned`), then `insufficient_funds` against the **server's**
  balance; after a rejected purchase a `use_booster` for it is `none_left`.
- [X] T045 [P] [US2] Write `backend/apps/economy/tests/test_op_use_booster.py` and
  `backend/apps/economy/tests/test_op_ad_reward.py` (operations.md `use_booster`, `ad_reward`):
  `dependency_rejected`, `no_trip`, `unknown_sku`, `none_left`; `result_double` (`no_result`,
  `not_doublable`, `already_doubled`; JENEHAT + `last_earnings`, reason `ad_result_double`),
  `trip_revive` (`already_revived`), `traffic_jam` (`cap_reached` at
  `ECONOMY_TRAFFIC_JAM_ADS_PER_TRIP`), `morning_piggy` always `server_only`, an unknown placement
  `unknown_sku`. (`fuel_refill` is tested in Phase 7.)
- [X] T046 [P] [US2] Write `backend/apps/economy/tests/test_content_versions.py` (spec US2 scenario 8,
  FR-014): every operation that reads the pack answers `unknown_content_version` for a number never
  published and `content_version_unsupported` for one older than `SYNC_CONTENT_MAX_AGE_DAYS` or no
  longer indexed, and applies nothing; an honest offline player on the previous version is accepted
  at **that version's** prices (publish two versions with different prices).
- [X] T047 [P] [US2] Write `backend/apps/economy/tests/test_corruption.py` (SC-007): for every
  operation type, take a valid payload and corrupt each field in turn (price ±1, an unknown sku, the
  currency, a wrong ref, a missing key, a float, a boolean, an extra key, a negative number); every
  corrupted case is rejected and the ledger and wallet are unchanged.
- [X] T048 [P] [US2] Extend `backend/apps/economy/tests/test_properties.py` (SC-003): add the
  purchase, booster and ad operations to the machine, and assert after every batch that no
  accepted phone-sendable operation increased BONAT, and that none lowered one currency while
  raising the other (the direction rule, operations.md).

### Implementation for User Story 2

- [X] T049 [US2] Write `backend/apps/economy/services/ops/spending.py` (`spend_jenehat`,
  `spend_bonat`, `use_booster`) and `backend/apps/economy/services/ops/ads.py` (`ad_reward` for
  `result_double`, `trip_revive`, `traffic_jam`, `morning_piggy`; `fuel_refill` is added in T064),
  registering them (T043–T045, T047 pass). Prices come from `lookups.catalog_price`, ownership and
  inventory from the batch state; JENEHAT and BONAT move only through `ledger.apply_entry`; the
  reasons are operations.md's.
- [X] T050 [US2] Add the content-version gate to `sync.py`: for the operations that declare
  `content_version`, call `lookups.supported` once per distinct version in the batch and reject with
  `unknown_content_version` / `content_version_unsupported` (T046 passes).
- [X] T051 [US2] Regenerate `contracts/openapi.yaml`; run T048 and fix what it finds in the handlers.

**Checkpoint**: money is server-checked. US1 and US2 together are the first safe slice of sync.

---

## Phase 5: User Story 3 - The app starts a session knowing where it stands (Priority: P2)

**Goal**: `GET /v1/bootstrap` answers the session snapshot and creates the wallet.

**Independent Test**: create a player with B02, call bootstrap, then sync a trip and call it again:
the version and the wallet moved (quickstart A4).

### Tests for User Story 3 (write first, they must fail)

- [X] T052 [P] [US3] Write `backend/apps/economy/tests/test_bootstrap.py` (contracts/api.md
  "GET /v1/bootstrap", spec US3 scenarios 1–6): a new player gets a full tank, 0/0, `state_version`
  0 and the server's time, and a second call creates nothing new; a player with progress shows name,
  level, country, providers, wallet and version; `content` names the current version and
  `/v1/content/manifest`; the neutral `entitlements`, `daily` and `comeback` blocks; `wallet.fuel`
  is recounted to now (`time-machine`) and `fuel_updated_at` is M05's `countedFrom`;
  `client.force_update` is true for an `X-Client-Version` below `CLIENT_MIN_VERSION` and the answer
  is still 200; `last_active_at` is set, and a call within `SYNC_SESSION_GAP_MINUTES` does not start
  a new session.
- [X] T053 [P] [US3] Extend `backend/apps/accounts/tests/test_conflicts.py` (B02) for the filled
  summary (spec FR-038, research R16): `driver_level` from the player, `bonat` from the wallet,
  `chapter_id` the highest unlocked chapter that is not complete (else the last complete, else the
  first), and a player with no wallet yet shows the starting values.

### Implementation for User Story 3

- [X] T054 [US3] Write `backend/apps/economy/services/bootstrap.py` and the `BootstrapView` +
  route `GET /v1/bootstrap` in `economy/api/` (T052 passes): lock-free read except the session
  marker update (a short `select_for_update` on the wallet row to set `last_active_at` and start a
  session), wallet recounted without writing, the `client` block from `CLIENT_MIN_VERSION`,
  `CLIENT_LATEST_VERSION` and the parsed `X-Client-Version`, the neutral blocks from
  `entitlements.py`. `comeback.claimable` is `false` until Phase 8.
- [X] T055 [US3] Fill `backend/apps/accounts/services/summary.py` from the wallet and the story
  rules (T053 passes), removing the "stand-in" docstring.
- [X] T056 [US3] Regenerate `contracts/openapi.yaml` with the bootstrap path and schemas.

**Checkpoint**: M06 can start a session.

---

## Phase 6: User Story 4 - A second phone, or a stale phone, catches up (Priority: P2)

**Goal**: `GET /v1/state` returns a full, consistent snapshot, and a stale batch is flagged
`state_stale`.

**Independent Test**: sync from "phone A", then from "phone B" with the old `base_state_version`: B's
operations are validated against A's results, B gets `state_stale: true`, and the snapshot contains
both (quickstart A4).

### Tests for User Story 4 (write first, they must fail)

- [X] T057 [P] [US4] Write `backend/apps/economy/tests/test_state.py` (contracts/api.md "GET
  /v1/state", spec US4 scenarios 1–4): the answer holds everything listed there (wallet, inventory,
  ownership with variants, trips, `open_trip` and `last_result` or `null`, story, requests claimed,
  grants, stats, comeback); `stats.trips_played` counts accepted results including abandoned,
  `stars_total` is the sum of `best_stars`, `longest_streak` is 0; a trip started on one phone shows
  as `open_trip` to the other; the snapshot is **consistent** (a concurrent batch cannot appear half
  applied: run the read against a thread applying batches and compare with the version);
  nothing of other players, no token, install id or provider data.
- [X] T058 [P] [US4] Write `backend/apps/economy/tests/test_stale_state.py` (FR-015): the two-phones
  scenario above; a stale batch's operations are validated against the server's current state (a
  purchase the other phone already made is `already_owned`); `occurred_at` does not decide validity
  beyond the fuel clamps; a snapshot followed by the same operations replayed on top gives the
  server's state (the `replaceBase` contract).

### Implementation for User Story 4

- [X] T059 [US4] Write `backend/apps/economy/services/state.py` and the `StateView` + route
  `GET /v1/state` (T057, T058 pass): create the wallet if missing, then take a shared
  lock on its row with a parameterized `SELECT 1 FROM economy_wallet WHERE player_id = %s FOR SHARE`
  through a cursor (Django has no `FOR SHARE`), so no batch applies in the middle, then read the
  other tables in the same transaction; the stats as
  specified. The `ownership` and `trips` lists may name ids the active pack lacks.
- [X] T060 [US4] Regenerate `contracts/openapi.yaml` with the state path and schema.

**Checkpoint**: M06 can converge a stale phone.

---

## Phase 7: User Story 5 - Fuel agrees with the server's clock, and offline play is tolerated (Priority: P2)

**Goal**: the server recounts fuel along each operation's own time, accepts a bounded overdraft and
enforces refill rules and caps.

**Independent Test**: replay M05's worked examples as operations with `occurred_at` times: the
server's liters, countdown and window equal the app's after every step (SC-005).

### Tests for User Story 5 (write first, they must fail)

- [X] T061 [P] [US5] Write `backend/apps/economy/tests/test_fuel_timeline.py` (research R7,
  contracts/fuel.md "The effective time"): `t = clamp(occurred_at, timeline_at, server_now)` within
  and across batches; a backward `occurred_at` and a future one are clamped, not rejected; a late sync
  of five trips played over two hours gives the liters the phone had and no overdraft flag; a
  clamp over `SYNC_CLOCK_CLAMP_FLAG_MINUTES` raises `clock_clamped` (once a game day, with `count`).
- [X] T062 [P] [US5] Add the server-scope cases to `fixtures/economy/fuel.json` and extend
  `test_fuel_fixtures.py` to run them (contracts/fuel.md "Shared fixtures"): a start after a long
  gap; a backward and a future `occurred_at` (cases give `server_now` and `timeline_at`); three
  overdrafts in a day; a refill on a full tank; a window extended while running; a lowered maximum.
- [X] T063 [P] [US5] Write `backend/apps/economy/tests/test_fuel_ops.py` (spec US5 scenarios 1–8,
  operations.md): an empty tank with no window is **accepted** with the tank at 0, flag
  `fuel_overdraft` and the day counter +1; the **third** overdraft of a game day is `cap_reached` and
  its result `dependency_rejected`; `unlimited` mode inside a window costs no liter and outside is
  `not_eligible`; `ad_reward fuel_refill` fills the tank, is `tank_full` on a full tank, `cap_reached`
  at `ECONOMY_FUEL_REFILL_DAILY_CAP` per game day (counted per **effective** game day, so three offline
  days of three ads each are all accepted); `spend_bonat` `fuel` and `fuel_unlimited_1h` (60 minutes
  from the end of a running window or from now); a lowered `fuel_max` keeps the liters and
  nothing regenerates until below; the subscriber tank of 7 when `entitlements.flags_for` returns
  `fuel_max_bonus` (monkeypatched); every start costs a liter, replays included.
- [X] T064 [P] [US5] Write `apps/mobile/test/core/economy/fuel_fixtures_test.dart` (research R15):
  replay the `scope: "both"` cases of `fixtures/economy/fuel.json` through M05's fuel functions
  (`apps/mobile/lib/core/economy/domain/fuel.dart`) and compare liters, `counted_from`,
  `unlimited_until` and the refusal after each step. It fails now only if the fixture and M05
  disagree; if it does, fix the fixture or report the M05 bug, never loosen the case.

### Implementation for User Story 5

- [X] T065 [US5] Add the effective-time clamp and the day counters to `batch.py`/`sync.py` (T061
  passes): `timeline_at` persisted on the wallet, `server_now` read once per batch, `clock_clamped`
  through `flags.py`.
- [X] T066 [US5] Complete the fuel behavior in the handlers (T063 passes): overdraft and its cap in
  `ops/trips.py` (`trip_start` modes), `fuel_refill` in `ops/ads.py`, the fuel kinds in
  `ops/spending.py`, and the tank size through `entitlements.flags_for(player, t)`. Fuel changes only
  through `fuel.py`.
- [X] T067 [US5] Run T062 and T064 (`fvm flutter test test/core/economy/fuel_fixtures_test.dart` in
  `apps/mobile`) and reconcile any difference at its source.

**Checkpoint**: fuel agrees with M05 on the shared cases, and honest offline play is not punished.

---

## Phase 8: User Story 6 - Gifts and rewards the game promises are granted by the server (Priority: P3)

**Goal**: the tutorial gift, the comeback gift, family-request rewards and room and chapter rewards,
plus the profile operations the first-day flow needs.

**Independent Test**: claim each once and again: the first grants what the content or settings say,
the second answers `already_granted`; without the condition, `not_eligible`.

### Tests for User Story 6 (write first, they must fail)

- [X] T068 [P] [US6] Write `backend/apps/economy/tests/test_op_grants.py` (operations.md
  `tutorial_gift`, `comeback_gift`, `claim_request`): `tutorial_gift` fills the tank once
  (`already_granted` after; a full tank is accepted and unchanged; no ledger entry); `claim_request`
  in the order `unknown_sku`, `already_granted`, `not_eligible` (item not owned, and the variant when
  the request names one), accepted grants `reward_bonat` with reason `request_reward`, `ref_type`
  `request`, and a `GrantRecord`; the reward comes from the pack of the declared version.
- [X] T069 [P] [US6] Write `backend/apps/economy/tests/test_comeback.py` (research R13, spec US6
  scenario 2): a bootstrap after a gap of `SYNC_COMEBACK_AWAY_DAYS` days of **inactivity** sets
  `comeback_return_at` and `comeback.claimable` (use `time-machine`); a bootstrap within
  `SYNC_SESSION_GAP_MINUTES` does not; a shorter gap leaves an unclaimed return as it was; a claim
  fills the tank, adds one `change_bag`, records `GrantRecord(comeback, <return_at>)` and clears it;
  a second claim for that return is `already_granted`; a claim with no return is `not_eligible`; a
  new return inside `SYNC_COMEBACK_COOLDOWN_DAYS` of the last gift does not offer another.
- [X] T070 [P] [US6] Write `backend/apps/economy/tests/test_completion_rewards.py` (operations.md
  "Completion rewards", spec FR-028, clarification Q2): a `spend_jenehat` that buys the last item of a
  room pays that room's `completion_bonat` once, with reason `story_reward`, in the same batch, and
  the operation's answer lists it in `granted`; a chapter whose goal is met pays once, with its
  `StoryState` marked `completed`; several in one batch pay in room-then-chapter order; a repeat
  pays nothing; completing through a `trip_result` (a `complete_line` goal) pays too.
- [X] T071 [P] [US6] Write `backend/apps/economy/tests/test_op_story_progress.py` and
  `backend/apps/economy/tests/test_op_settings_update.py`: `story_progress` (`unknown_sku` for an
  unknown chapter or scene, `not_unlocked`, a repeat accepted with no change); `settings_update`
  (name length `ECONOMY_NAME_MIN_LENGTH`–`ECONOMY_NAME_MAX_LENGTH` after trimming and NFKC, no
  control, bidi or zero-width characters, not all digits; a matching `NameFilterEntry` rejected as
  `validation_error` with `details.field = "display_name"`; `settings` with known keys only, bounded
  values, at most 2 KB; neither key present is `validation_error`).
- [X] T072 [P] [US6] Write `backend/apps/accounts/tests/test_name_normalizer.py` (research R10):
  alef forms folded, alef maqsura to ya, ta marbuta to ha, diacritics and tatweel removed, repeated
  letters collapsed, Latin lowercased, the look-alike table applied; the same function is used by the
  check and by `NameFilterEntry.save()`; a seed entry blocks its spelling variants.

### Implementation for User Story 6

- [X] T073 [US6] Add `Player.settings` (`JSONField(default=dict)`) and `NameFilterEntry` (`term`
  varchar(40), `normalized` varchar(40) unique, `added_by` FK `accounts.User` null, `created_at`) to
  `backend/apps/accounts/models.py`, with a migration and a data migration inserting the seed list
  (a short list; the owner reviews it).
- [X] T074 [P] [US6] Write `backend/apps/accounts/services/names.py` (`normalize(text)` and
  `validate_display_name(text)`) (T072 passes).
- [X] T075 [US6] Write `backend/apps/economy/services/ops/grants.py` (`tutorial_gift`, `comeback_gift`,
  `claim_request`), `ops/story.py` (`story_progress` and the completion-rewards pass called after
  `spend_jenehat` and `trip_result`, using `unlocks.newly_completed`) and `ops/profile.py`
  (`settings_update`), registering them (T068, T070, T071 pass). BONAT moves only through
  `ledger.apply_entry` with reasons `request_reward` and `story_reward`.
- [X] T076 [US6] Extend `bootstrap.py` with the session and comeback logic of research R13
  (T069 passes): on a new session, set `comeback_return_at` when the idle gap and the cooldown allow,
  and report `comeback.claimable`.
- [X] T077 [US6] Regenerate `contracts/openapi.yaml`; extend the property machine of
  `test_properties.py` with the grants and completion rewards (a grant is applied at most once; BONAT
  only increases through the server reasons).

**Checkpoint**: the first-day flow (tutorial, name, comeback, requests, room rewards) is covered.

---

## Phase 9: User Story 7 - Suspicious play is noted, and staff can look and correct (Priority: P3)

**Goal**: soft anomalies become flags, and staff review flags, read wallets and correct balances.

**Independent Test**: sync a 3-star run faster than the plausibility threshold but above the hard
bound, and one below the hard bound: the first is accepted with a flag, the second rejected.

### Tests for User Story 7 (write first, they must fail)

- [X] T078 [P] [US7] Write `backend/apps/economy/tests/test_flags.py` (research R8, spec FR-040): a
  3-star `finished` result with `duration_ms` below `SYNC_FAST_RUN_PERCENT` % of the last station
  time and above `SYNC_MIN_DURATION_PERCENT` % is accepted with `fast_three_star`; below the hard
  bound it is rejected (`duration_out_of_bounds`); more than `SYNC_TRIPS_PER_DAY_FLAG` accepted starts
  in a game day raise `trip_rate`; a flag is one row per `(player, kind, game_date)` with
  `details.count`; `details` holds ids and numbers, never a payload; a flagged player's play is
  otherwise unchanged.
- [X] T079 [P] [US7] Write `backend/apps/economy/tests/test_admin_economy.py` (contracts/admin.md
  "Tests"): the permission matrix (`player_support` sees wallet, ledger, operations (no payload),
  ownership, progress, flags and can review; `economy_ops` can also adjust and edit the name filter;
  a staff user with neither is refused); the review action (a required resolution of at most 200
  characters, records reviewer and time, a reviewed flag cannot be changed again, flags cannot be
  added or deleted); the **adjustment** (one `admin_adjustment` ledger entry with source `admin`, one
  `WalletAdjustment` with actor, player, currency, delta, reason and the ledger entry, `state_version`
  bumped, a result below 0 refused, no path between currencies); **the audit records** (SC-011): a
  reviewed flag holds `reviewed_by`, `reviewed_at` and `resolution`, a second review is refused, and
  neither a `WalletAdjustment` nor a reviewed flag can be changed or deleted through the admin; no page contains a token, an install id, a payload or a provider subject.
- [X] T080 [P] [US7] Write `backend/apps/economy/tests/test_groups.py`: the migration creates
  `economy_ops` with the permissions in contracts/admin.md and adds the view/change permissions to
  `player_support`; `create_staff --group economy_ops` works.

### Implementation for User Story 7

- [X] T081 [US7] Add the flag sites (T078 passes): `fast_three_star` in `ops/trips.py` `trip_result`,
  `trip_rate` in `trip_start` through the `trips_started` counter. (`fuel_overdraft`,
  `clock_clamped` and `txn_payload_mismatch` exist from earlier phases.)
- [X] T082 [US7] Write `backend/apps/economy/services/adjustments.py` (`adjust(player, currency,
  delta, reason, actor)`: lock the wallet, `apply_entry(source="admin", reason="admin_adjustment")`,
  one `WalletAdjustment`, bump `state_version`, all in one transaction; refuses a result below 0).
- [X] T083 [US7] Write `backend/apps/economy/admin.py` and extend `backend/apps/accounts/admin.py`
  (T079 passes), contracts/admin.md: the read-only wallet, recent ledger (last 50), inventory,
  ownership, progress, story, grants, open flags and recent operations (type, status, reason; never
  the payload) blocks on `PlayerAdmin`; `PlayerFlagAdmin` with its filters and the "Mark reviewed"
  action; the "Adjust balance…" action with the `economy.adjust_wallet` permission, the before/after
  display and the confirmation; `NameFilterEntryAdmin` showing the normalized form.
- [X] T084 [US7] Write `backend/apps/economy/migrations/0002_groups.py` (T080 passes), the pattern of
  `accounts/migrations/0003_player_support_group.py`: create the permissions, the `economy_ops`
  group, and extend `player_support`. Update the docs line in `create_staff`'s help if it lists
  groups.

**Checkpoint**: all seven stories work.

---

## Phase 10: Polish & Cross-Cutting Concerns

**Purpose**: retention, the privacy scan, the contract test, the simulation, the docs, the review
and the live checks.

- [X] T085 [P] Write `backend/apps/economy/tests/test_prune.py` and `backend/apps/economy/tasks.py`
  (spec FR-043, research R11, R12): a `bind=True` task with retries that deletes `ProcessedOp` older
  than `SYNC_OP_RETENTION_DAYS`, `TripRun` older than 90 days (chunks of 10,000) and `DayCounter`
  older than 40 days; ledger entries, progress, ownership and inventory are never deleted; an
  operation whose id is older than the retention is `op_expired` after the prune. Add
  `backend/apps/economy/migrations/0003_prune_schedule.py` (the pattern of B02's
  `0004_prune_sessions_schedule.py`).
- [X] T086 [P] Write `backend/apps/economy/tests/test_privacy_scan.py` (spec FR-044, B02's scan
  extended): run every operation type through the API with `caplog` at DEBUG, then assert that no
  log record or captured error report contains a payload, a balance or a display name, and that no
  table other than `Player` stores a name.
- [X] T087 [P] Extend `backend/tests/test_contract.py` (SC-010, B02's auth hook): the three endpoints
  conform to `contracts/openapi.yaml`, including their documented 400, 401, 403, 413, 415 and 429
  answers; add one test per documented operation reason.
- [X] T088 [P] Write `backend/apps/economy/tests/test_simulation.py` (SC-006, SC-004):
  - 30 game days of generated honest play (a realistic mix of trips, purchases, ads and gifts) on
    phones with skewed clocks, synced in irregular batches under `time-machine`: **zero** hard
    rejections, and only the flags the soft rules define;
  - 200 concurrent batches across 20 players (some players with two phones): no lost update, no
    operation twice, no negative balance, `wallet == sum(ledger)` afterwards.
- [X] T089 [P] Write `backend/tools/sync_load.py` (quickstart B4): create N anonymous players against
  a base URL, then time bootstrap, state and batches of 100 operations, printing p50/p95 per call. It
  never runs in CI.
- [X] T090 [P] Update `docs/architecture-backend.md` (research R17): §6.2 `batch_too_large`; §6.4
  bootstrap's `comeback` block, `fuel_updated_at` meaning and `GET /v1/state`; §7.2 the reasons
  `request_reward` and `story_reward`; §7.3 rule 4 (dependency), the `op_expired` rule and the
  effective-time clamp; §7.4 the three grant operations, `fuel_refill` without a `ref`,
  `claim_daily_reward` and `claim_task` marked B08/M13, `content_version` in the payloads; §7.5 the
  timeline rule; §12 `LedgerEntry.op` as a plain id, `TripRun` unpartitioned (with the 100k-DAU
  note), the new models and `Player.settings`; §22.2 resolved (`Africa/Cairo`). Add the new code to
  `specs/002-b01-backend-skeleton/contracts/api.md`'s error table too.
- [X] T091 [P] Update `docs/architecture-mobile.md` §12 with the three new operations and the
  `content_version` payload field, and §14.3 with a "Server-only numbers (no Remote Config key until
  B10)" note listing `ECONOMY_FUEL_OVERDRAFT_PER_DAY`, `ECONOMY_TRAFFIC_JAM_ADS_PER_TRIP`,
  `SYNC_COMEBACK_AWAY_DAYS`, `SYNC_COMEBACK_COOLDOWN_DAYS`, `SYNC_MIN_DURATION_PERCENT`,
  `SYNC_FAST_RUN_PERCENT` and `SYNC_TRIPS_PER_DAY_FLAG` with their defaults (plan, Complexity
  Tracking, constitution VIII). In `docs/delivery-plan.md`'s B10 entry, add that B10 moves each into
  `liveops.LiveSetting`. Also in `docs/delivery-plan.md`: tick the B03 line in Progress, record
  that backend §22.2 and the HANDOFF §9.3 #8 grants are resolved here, and add M06's hand-over list
  from research "Handed to later features".
- [X] T092 [P] Write `docs/runbooks/economy.md` (new) and link it from `docs/runbooks/README.md`:
  reading flags and what each means, adjusting a balance, tuning `SYNC_FAST_RUN_PERCENT` and
  `SYNC_TRIPS_PER_DAY_FLAG`, `content_index --rebuild`, `economy_check`, what to do on a ledger
  mismatch, and the note that `ProcessedOp` and `TripRun` need partitioning around 100k DAU.
- [X] T093 [P] Update `CLAUDE.md`: the B03 overview line in "Project status"; the commands
  `content_index --rebuild`, `economy_check` and the thorough economy property run in the backend
  table; the `SYNC_*`/`ECONOMY_*` variables line; the rule "every balance change goes through
  `economy.services.ledger.apply_entry`".
- [X] T094 Add B03's section to `docs/owner-actions.md` (the "After merge" items of plan "Owner
  actions") and keep the "Open now" table current.
- [X] T095 Run the full gates in `backend/`: `uv run ruff check . && uv run ruff format --check .`,
  `uv run mypy .`, `uv run manage.py makemigrations --check --dry-run`, `uv run pytest -n 4 --cov
  --cov-fail-under=80`, the OpenAPI drift check, and confirm 100% line coverage of `ledger.py` and
  `fuel.py`. In `apps/mobile`, run `fvm flutter test test/core/economy` and `fvm flutter analyze
  --fatal-infos`. Fix what fails.
- [X] T096 Run the thorough property pass once (quickstart A1):
  `HYPOTHESIS_PROFILE=thorough uv run pytest apps/economy/tests/test_properties.py`, and record the
  result in the PR.
- [X] T097 Security review (plan "Delivery"): run the **security-reviewer** agent over
  `apps/economy`, `apps/progress`, the `accounts` and `content` changes and the admin pages. Fix every
  CRITICAL and HIGH finding. Cover at least: balance writers, replay and id handling, the per-player
  lock, integer-only input, admin permissions, and log content.
- [X] T098 Walk quickstart Part A (A1–A5) end to end on a clean stack and fix any step that does not
  match the document, in the document or the code.
- [ ] T099 **Owner, after merge.** Run quickstart Part B on staging, then on production where it
  applies: B1 (`content_index --rebuild`), B2 (a live flow), B3 (`economy_check`), B4 (the load
  script, SC-008), B5 (flags). Report the results; tick the items in `docs/owner-actions.md`.
- [ ] T100 **Owner, after merge.** Review the name filter's seed list in the admin, create the
  `economy_ops` members (`create_staff <name> --group economy_ops`), and, after the closed test
  starts, read the first flags and tune the two thresholds in the env file if honest players are
  flagged (`docs/runbooks/economy.md`).

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (Phase 1)** has no dependencies.
- **Foundational (Phase 2)** depends on Setup, and blocks every story.
- **US1 (Phase 3)** depends on Phase 2. It is the MVP.
- **US2 (Phase 4)** depends on US1 (the endpoint, the trip handlers and an open trip for revives and
  boosters) and on Phase 2.
- **US3 (Phase 5)** depends only on Phase 2. It can run in parallel with US1 and US2.
- **US4 (Phase 6)** depends on US1 (to have state to read) and US3's wallet creation.
- **US5 (Phase 7)** depends on US1 (`trip_start`) and US2 (`spend_bonat` fuel kinds, `ad_reward`).
- **US6 (Phase 8)** depends on US2 (purchases that complete rooms) and US3 (bootstrap's session logic).
- **US7 (Phase 9)** depends on US1 (flag sites), US5 (overdraft flag) and Phase 2's models.
- **Polish (Phase 10)** depends on all stories. T099 and T100 follow the merge.

### Within phases

- Tests first, and they must fail. Then models, then services, then handlers, then views and
  routes, then the OpenAPI regeneration.
- `backend/apps/economy/services/ops/trips.py` is edited by T039, T066 and T081, in that order.
- `backend/apps/economy/services/ops/spending.py` and `ops/ads.py`: T049, then T066.
- `backend/apps/economy/services/bootstrap.py`: T054, then T076.
- `backend/apps/economy/tests/test_properties.py`: T038, then T048, then T077.
- `backend/apps/economy/services/sync.py` and `batch.py`: T030, then T050, then T065.
- `fixtures/economy/fuel.json`: T008, then T062.
- `contracts/openapi.yaml` is regenerated after each endpoint change (T041, T051, T056, T060, T077)
  and last in T095.

### Parallel opportunities

- **Phase 1:** T002, T003 and T004.
- **Phase 2:** the tests T005–T018 together (T005 first if the others use its helpers), then T020,
  T021 and T022 together, after T019. T026 follows T025. T028 is written after T030 (it uses
  `BatchState`), before T031.
- **Phase 3:** T032–T038 together. T040 alongside T039.
- **Phase 4:** T043–T048 together.
- **Phase 5:** T052 and T053 together; **Phase 5 as a whole** can run in parallel with Phases 3–4.
- **Phase 7:** T061–T064 together.
- **Phase 8:** T068–T072 together; T074 alongside T073.
- **Phase 9:** T078–T080 together.
- **Phase 10:** T085–T093 together.

---

## Parallel Example: Foundational tests

```bash
Task: "Write economy test helpers in backend/apps/economy/tests/conftest.py and helpers.py (T005)"
Task: "Extend settings guard tests for the economy settings (T006)"
Task: "Write backend/apps/economy/tests/test_gameday.py (T007)"
Task: "Write test_fuel.py and test_fuel_fixtures.py and fixtures/economy/fuel.json (T008)"
Task: "Write backend/apps/economy/tests/test_ledger.py (T009)"
Task: "Write backend/apps/economy/tests/test_batch_engine.py (T015)"
Task: "Write backend/apps/economy/tests/test_balance_writers.py (T016)"
```

## Parallel Example: User Story 1 tests

```bash
Task: "Write test_op_trip_start.py (T032)"
Task: "Write test_op_trip_result.py (T033)"
Task: "Write test_sync_api.py (T034)"
Task: "Write test_sync_idempotency.py (T035)"
Task: "Write test_sync_concurrency.py (T036)"
Task: "Write test_batch_cost.py (T037)"
Task: "Write test_properties.py (T038)"
```

---

## Implementation Strategy

### MVP first (User Story 1)

1. Phases 1 and 2: the settings, models, ledger, fuel rules, unlock rules, index and the engine.
2. Phase 3: `POST /v1/sync` with `trip_start` and `trip_result`.
3. **Stop and validate:** T032–T038 pass, and quickstart A4's sync calls work. A phone's offline
   trips reach the server once, which is what M06 builds on.

### Incremental delivery (still one PR)

1. US2: purchases, boosters and ads are server-checked. Needed before any real BONAT depends on it.
2. US3 and US4: the session snapshot and the stale-state path, which M06 needs.
3. US5: fuel matches M05, including the offline tolerance.
4. US6 and US7: the grants, the flags and the admin.
5. Phase 10: retention, the scans, the docs, the review, the thorough run and the live checks.

The PR merges only with all of it, because staging deploys from `master` and this feature changes
money and anti-cheat.

---

## Notes

- `[P]` tasks touch different files and depend on no unfinished task.
- Every task names the spec FR, contract or research section it serves. Read that section before
  starting.
- Never write a balance outside `economy/services/ledger.py`, never read the ORM from a handler,
  and never use a float for money, fuel or time (spec FR-005, FR-009; research R4, R5).
- Never log or store a payload, a balance, a token or a provider id (FR-044).
