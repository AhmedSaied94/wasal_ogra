# Implementation Plan: Economy Ledger, Bootstrap and Sync (B03)

**Branch**: `010-b03-ledger-sync` | **Date**: 2026-10-25 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/010-b03-ledger-sync/spec.md`

## Summary

B03 gives the server the player's money and progress: one ledger function that is the only writer of
a balance, three endpoints that start a session, replace a stale phone's state and apply what the
phone did offline, and the checks that keep honest offline play whole and dishonest play out.

- **The ledger.** `LedgerEntry` rows are append-only, `Wallet` is their materialized sum, and one
  function (`economy.services.ledger.apply_entry`) writes both. A scan test fails CI on any other
  writer of a balance, and the restore drill checks `wallet == sum(ledger)`.
- **The sync engine.** `POST /v1/sync` takes up to 100 operations, locks the player's wallet row,
  and applies them in order against an in-memory copy of the player's state. Nothing is written
  until the batch ends, so a rejected operation never leaves a trace, and the writes go out
  together. Each outcome is stored by `client_txn_id`, which makes a repeat harmless (R5).
- **Validators.** One handler per operation type checks the pack of the declared `content_version`
  (trips, prices, unlock rules, rewards from B04's index, R2), the player's state, and the caps.
  Hard violations are rejected. Soft anomalies are accepted and flagged (R8).
- **Fuel.** The server recounts fuel along the operations' own times, clamped between the previous
  operation and its own clock (R7). It follows M05's contract exactly, and a shared fixture file
  proves the two agree.
- **Grants.** Three new operations (`tutorial_gift`, `comeback_gift`, `claim_request`) and automatic
  room and chapter rewards are decided by the server from the pack and the settings (R6, R13).
- **Reading.** `GET /v1/bootstrap` starts a session (and creates the wallet), and `GET /v1/state`
  returns a full snapshot at one `state_version`.
- **Around it:** a sync throttle, a flag queue and wallet pages in the admin, a staff-audited
  balance adjustment, an editable name filter, the conflict summary filled in, and the daily prune.

Decisions and alternatives: [research.md](./research.md).

## Technical Context

**Language/Version**: Python 3.13 with uv (backend). One small mobile test (the fuel fixtures, R15);
no other mobile code.

**Primary Dependencies**:

- No new runtime package, except `tzdata` (the Cairo game day, R3) if the image doesn't carry it.
- B01 and B02's stack: Django 5.2, DRF, drf-spectacular, simplejwt, Celery and beat, hypothesis,
  schemathesis, time-machine.

**Storage**:

- PostgreSQL 17, two new apps: `economy` (`Wallet`, `LedgerEntry`, `ProcessedOp`, `Inventory`,
  `PlayerFlag`, `DayCounter`, `GrantRecord`, `WalletAdjustment`) and `progress` (`TripProgress`,
  `TripRun`, `TripSession`, `Ownership`, `StoryState`, `DailyState`). Also `accounts.NameFilterEntry`
  and `content.PackRulesIndex` (data-model.md).
- Valkey: throttle counters only. No economy state lives in the cache.

**Testing**:

- pytest-django on real PostgreSQL and Valkey, tests first for the ledger, the engine and every
  validator (constitution XIII).
- hypothesis: a stateful machine over random operation sequences (invariant, idempotency, BONAT
  never created by a phone) at 300 examples in CI and 10,000 in the `thorough` profile.
- Concurrency tests with real threads against the lock (two phones, one batch twice).
- Shared fuel fixtures read by pytest and by one Dart test (R15).
- schemathesis against `contracts/openapi.yaml`, extended to the three endpoints.
- The repo guards: the balance-writer scan, the tunables parity check, the privacy scan.
- Coverage at least 80%, and the ledger and fuel modules at 100% of lines.

**Target Platform**: B01's API and admin roles on the two ARM64 Always Free VMs.

**Project Type**: A backend feature: two new Django apps, additions to `accounts`, `content` and
`common`, and the committed OpenAPI contract.

**Performance Goals** (spec SC-008):

- Bootstrap p95 ≤ 200 ms, state p95 ≤ 400 ms, a batch of 100 operations p95 ≤ 1 s on staging.
- A batch costs a fixed number of queries plus one bulk write per table, not a query per operation
  (R5, R20).

**Constraints**:

- Constitution IV and VI: server authority for BONAT, append-only ledger, one transaction per batch
  under a per-player row lock, stored results, no float anywhere.
- Offline-first (V): only hard violations are rejected.
- Expand-only migrations: this feature adds tables and a few settings and changes none.
- No personal data beyond the display name; the logs carry no payload or balance (FR-044).

**Scale/Scope**:

- About 10k DAU at launch and 100k DAU as the design point. At 100k DAU, about 15 trips and 3
  other operations per player-day: 2 million operations a day, 20 batches a second at peak.
- Per row sizes and the 180-day `ProcessedOp` retention are sized in R11; `TripRun` has 90 days.

## Constitution Check

*GATE: passed before Phase 0, and re-checked after Phase 1 below.*

| # | Principle | Applies | How B03 satisfies it |
| --- | --- | --- | --- |
| I | Engine purity | No | No trip rule changes. The server reads the solver's definitions and bounds, it doesn't re-implement rules. |
| II | Integer money | Yes | Every amount is an integer, in the payload (a float or a boolean is refused), the models (`PositiveBigInteger`) and the arithmetic. The ledger and fuel code have no `float`, `Decimal` or `/`. A test greps the economy apps for them. |
| III | Parity | Lightly | No engine change, no fixtures of `fixtures/parity`. The fuel rules are a client/server pair, not engine rules, so they get their own shared fixture file (R15). |
| IV | Server authority | Yes | The core of this feature. BONAT changes only through server grants and BONAT-spend ops checked against the server balance. JENEHAT is bounded by the trip, the catalog and unlock order. Direct balance writes are scanned for. BONAT never becomes JENEHAT (a test checks every op's effects). |
| V | Offline-first | Yes | Soft anomalies are accepted and flagged (R8). Time clamps never reject (R7). A long-offline queue is accepted up to the 180-day id window, in batches of 100. A refused or failed sync never blocks play. |
| VI | Idempotent everything | Yes | `ProcessedOp` stores each result by `(player, client_txn_id)`. One transaction per batch, serialized by a row lock on the wallet. A hypothesis test proves "the same batch twice gives the same state". Server time is the only clock for caps, game days and fuel. |
| VII | Content, not code | Yes | Prices, rewards, unlocks and requests come from the published pack. The only player-visible text is the display name. Reasons are codes. |
| VIII | Tunable numbers | Partly (one tracked deviation) | The four numbers the app also holds (the tank, the subscriber tank, regeneration, the daily refill ad cap) are in `tunables.json` and §14.3, and a CI parity check keeps the server's defaults equal to them (R14). The server-only numbers (overdraft limit, comeback gaps, the two anti-cheat thresholds, windows, retention) have **no Remote Config key and no `liveops.LiveSetting` copy yet**, because `liveops` is B10's. They are env settings with defaults and are listed in §14.3 as server-only. This is the one entry in Complexity Tracking and needs the owner's approval. |
| IX | No ads in a trip | Lightly | The server records ad rewards and caps. It calls no ad SDK. An in-trip ad needs an open trip, which the validator checks. |
| X | RTL and Arabic first | No | No screens. Reason codes are English snake case. |
| XI | Accessible minimums | No | No screens. |
| XII | No runtime LLM | No | — |
| XIII | Small, testable features | Yes | Tests first for the ledger, validators and fuel. Real PostgreSQL and Valkey. hypothesis for the invariants, schemathesis for the endpoints. One feature, one folder, one PR. |

**Architecture boundaries.**

- **Business logic** is in `apps/economy/services/` and `apps/progress/services/`. Views and
  serializers validate shape and call services. Handlers never touch HTTP.
- **Errors** use B01's envelope. `batch_too_large` is the one new HTTP code; it is added to backend
  §6.2 first. Per-operation reasons are not HTTP codes and live in contracts/operations.md.
- **Keys and migrations:** UUIDv7 keys (`common.E001`), expand-only, with the new tables empty
  until used.
- **Stateless:** no per-process state. The only cache is request-local.
- **External calls:** none. Everything the batch needs is in PostgreSQL (B04's index), so there is
  no network call inside the transaction.
- **Locks:** one row lock per batch (the wallet), taken first. Nothing else locks, so there is no
  order to get wrong.

**Security & privacy.**

- **Authority:** the three endpoints use the default `PlayerAuthentication`, the two client headers
  and the per-player throttle (B02). A player can only touch their own rows; no endpoint takes a
  player id.
- **Input:** strict serializers (UUIDv7 ids, closed enums, integer-only payloads, key whitelists,
  bounded sizes: 100 ops, 256 KB, `result` 8 KB). No raw SQL.
- **Replay and tampering:** `client_txn_id` with `ProcessedOp`; a payload mismatch is flagged; ids
  older than the retention are refused (R11).
- **Admin:** wallet adjustments need their own permission, a reason, and leave an append-only
  record. Staff are on the 2FA admin over WireGuard (B01).
- **Logs:** no payload, balance or provider id; the privacy scan from B02 is extended (FR-044).
- **A security review** is required before merge (this changes money and anti-cheat).

**Post-design re-check (after Phase 1).** It passes with one Complexity Tracking entry (VIII,
below, pending the owner's approval). The design changes these documented details, each updated in the same PR (R17):

- **`LedgerEntry.op` is a plain UUID, not a foreign key** (backend §12): the processed-operation row
  is pruned after 180 days and the ledger is append-only forever.
- **`TripRun` is not range-partitioned** (backend §12): a daily chunked delete is enough for the
  volume and keeps a UUID key (R12).
- **`dependency_rejected` applies where the payload links** (backend §7.3 rule 4, R5).
- **B04's index keeps 10 versions, not 5, and gains a rules document** (R2).
- **New reasons and codes:** `request_reward`, `story_reward` (ledger); `batch_too_large` (HTTP);
  the operation reasons of contracts/operations.md.
- **Spec clarification refined:** the "production floor version" clause is dropped (R2).

## Complexity Tracking

| Deviation | Why needed | Simpler alternative rejected because |
| --- | --- | --- |
| **Constitution VIII:** the server-only balancing numbers (`ECONOMY_FUEL_OVERDRAFT_PER_DAY`, `SYNC_COMEBACK_AWAY_DAYS`, `SYNC_COMEBACK_COOLDOWN_DAYS`, `SYNC_FAST_RUN_PERCENT`, `SYNC_MIN_DURATION_PERCENT`, `SYNC_TRIPS_PER_DAY_FLAG`, `ECONOMY_TRAFFIC_JAM_ADS_PER_TRIP`) have no Remote Config key and no `liveops.LiveSetting` copy. They are env settings with defaults (contracts/environment.md). | The phone never reads them: the server alone decides (principle IV), so a Remote Config key would have no consumer. `liveops` does not exist before B10 (the backend has `accounts`, `common` and `content`), and creating it here would pull B10's model, admin and cache into a ledger feature. | Adding the keys to `tunables.json` now: M05's tunables registry and its guard would have to change for numbers the app does not use, and the two files would drift. Hard-coding the numbers: forbidden by VIII. |

**Conditions.** (1) `docs/architecture-mobile.md` §14.3 lists these settings as "server-only (no
Remote Config key)", in this change (T091). (2) B10's spec must move each into `LiveSetting` and
read it from there; T091 records that in `docs/delivery-plan.md`. (3) The owner approves this row
before `/speckit-implement` (the constitution requires it for any deviation that is not I, II, III,
IV or VI).

## Project Structure

### Documentation (this feature)

```text
specs/010-b03-ledger-sync/
├── plan.md              # This file
├── research.md          # R1–R21 and the hand-over list
├── data-model.md        # economy, progress, accounts and content additions; states; migrations
├── quickstart.md        # Local checks and the live checks on staging
├── contracts/
│   ├── api.md           # bootstrap, state and sync: payloads, answers, errors
│   ├── operations.md    # every operation: payload, checks in order, effects, reasons
│   ├── fuel.md          # the server's fuel rules and the shared fixture format
│   ├── environment.md   # new settings and where they go
│   └── admin.md         # the economy pages, the adjustment, the name filter, the groups
├── checklists/requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
backend/
├── pyproject.toml, uv.lock                  # + tzdata only if the image lacks it
├── .env.example                             # + SYNC_*, ECONOMY_*, CLIENT_*, THROTTLE_SYNC_RATE
├── config/
│   ├── env.py                               # + economy() reader and its checks (contracts/environment.md)
│   └── settings/base.py, test.py            # + apps, settings, the sync throttle
│   └── urls.py                              # + /v1/bootstrap, /v1/state, /v1/sync
├── apps/common/
│   ├── errors.py                            # + batch_too_large
│   ├── throttles.py                         # + SyncThrottle
│   └── services/invariants.py               # unchanged: economy registers from its AppConfig
├── apps/accounts/
│   ├── models.py                            # + NameFilterEntry
│   ├── services/summary.py                  # filled from the wallet and story tables
│   └── admin.py                             # + the name filter page
├── apps/content/
│   ├── models/packs.py                      # + PackRulesIndex
│   ├── services/lookups.py                  # + rules(version), supported(version), index keeps N
│   └── management/commands/content_index.py # rebuild the indexes of published packs (idempotent)
├── apps/economy/
│   ├── models.py                            # Wallet, LedgerEntry, ProcessedOp, Inventory, PlayerFlag,
│   │                                        # DayCounter, GrantRecord, WalletAdjustment
│   ├── services/
│   │   ├── ledger.py                        # apply_entry: the only balance writer (R4)
│   │   ├── gameday.py                       # Cairo game day (R3)
│   │   ├── fuel.py                          # integer fuel rules (contracts/fuel.md)
│   │   ├── settings.py                      # the economy settings, typed
│   │   ├── batch.py                         # BatchState and the unit of work (R5)
│   │   ├── sync.py                          # process_batch: lock, idempotency, dispatch, flush
│   │   ├── ops/                             # one module per operation family
│   │   │   ├── trips.py                     # trip_start, trip_result
│   │   │   ├── spending.py                  # spend_jenehat, spend_bonat, use_booster
│   │   │   ├── ads.py                       # ad_reward
│   │   │   ├── grants.py                    # tutorial_gift, comeback_gift, claim_request
│   │   │   ├── story.py                     # story_progress, room and chapter completion
│   │   │   └── profile.py                   # settings_update
│   │   ├── flags.py                         # raise_flag, thresholds
│   │   ├── bootstrap.py, state.py           # the two read paths
│   │   ├── entitlements.py                  # the seam B06 fills (flags: none until then)
│   │   └── adjustments.py                   # the staff adjustment
│   ├── api/{serializers.py,views.py,messages.py}
│   ├── admin.py                             # wallet, ledger, flags, adjustment (contracts/admin.md)
│   ├── tasks.py                             # prune (bind=True, retries)
│   ├── invariants.py                        # economy.wallet_equals_ledger
│   ├── management/commands/economy_check.py   # runs the wallet-equals-ledger check on the live database
│   ├── migrations/                          # 0001_economy, 0002_groups, 0003_prune_schedule
│   └── tests/                               # see Testing; test_properties, test_concurrency,
│                                            # test_fuel_fixtures, test_balance_writers (scan),
│                                            # test_tunables_parity, test_privacy_scan, one file per op
├── apps/progress/
│   ├── models.py                            # TripProgress, TripRun, TripSession, Ownership,
│   │                                        # StoryState, DailyState
│   ├── services/unlocks.py                  # line, trip, chapter, room rules over the rules index (R6)
│   ├── migrations/
│   └── tests/
└── tests/
    ├── test_contract.py                     # + the three endpoints, with an auth hook
    └── test_settings_guards.py              # + the economy settings refusals
backend/tools/sync_load.py                    # a small load script for staging (quickstart B4)
contracts/openapi.yaml                       # + three paths, schemas, every reason
fixtures/economy/fuel.json                   # shared fuel cases, read by pytest and one Dart test
apps/mobile/test/core/economy/fuel_fixtures_test.dart   # replays fixtures/economy/fuel.json (R15)
docs/                                        # backend §6.2–6.4, §7.2–7.5, §12, §22.2; mobile §12 note;
                                             # runbooks/economy.md (new); owner-actions.md; delivery-plan.md
CLAUDE.md                                    # B03 overview line; content_index and the thorough economy run
```

**Structure decision.** Backend §5 already names `economy` (wallet, ledger, inventory, sync engine,
operation validators) and `progress` (trip progress, runs, ownership, story, daily state), so the
feature uses them as written. The split is also a dependency direction: `progress` holds data and
unlock rules and imports nothing from `economy`; the operation handlers in `economy` import
`progress`. The name filter belongs with the display name in `accounts`, and the rules document
belongs with the pack index in `content`.

## Delivery

One PR. It merges when:

- CI is green, including the 80% coverage gate, the OpenAPI drift check, the balance-writer scan and
  the tunables parity check;
- the thorough property run has passed once (quickstart A1);
- the security review is done;
- `content_index` has been run on staging and production after the deploy (quickstart B1), so the
  rules documents exist for the published packs. Until it has, sync answers
  `content_version_unsupported` for those versions, by design.

Quickstart Part B runs on staging after the merge deploys it. It unblocks M06 (spec 011).

## Owner actions (added to `docs/owner-actions.md` by `/speckit-implement`)

**Before implementing:**

- Approve (or refuse) the Complexity Tracking row for constitution VIII: the server-only numbers are
  env settings until B10 (see above).

**After merge** (nothing blocks the merge itself):

- Run `content_index --rebuild` in the worker container on staging, then on production (a minute
  each; quickstart B1).
- Create the `economy_ops` group's first members with `create_staff` (the owner), and add the
  starting entries of the name filter in the admin (the seed list ships in the migration, and the
  owner reviews it).
- Read the first flags in the admin after the closed test starts, and tune the two thresholds in
  the env file if honest players are being flagged (R8, `docs/runbooks/economy.md`).
