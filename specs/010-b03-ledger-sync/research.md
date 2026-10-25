# Research: Economy Ledger, Bootstrap and Sync (B03)

Decisions for [plan.md](./plan.md). Each one: the decision, why, and what was rejected. R-numbers are
cited from the plan, the data model and the contracts.

## R1. Two apps: `economy` and `progress`

**Decision.** `apps/economy` holds `Wallet`, `LedgerEntry`, `ProcessedOp`, `Inventory`,
`PlayerFlag`, `DayCounter`, `GrantRecord`, `WalletAdjustment`, the sync engine and the operation
handlers. `apps/progress` holds `TripProgress`, `TripRun`, `TripSession`, `Ownership`, `StoryState`,
`DailyState` and the unlock rules. `progress` imports nothing from `economy`; the handlers in
`economy` import `progress`. `accounts` gets `NameFilterEntry`, `content` gets `PackRulesIndex`.

**Why.** Backend §5 names both apps with exactly this content, and the one-way import keeps
`progress` testable without a wallet. The name filter belongs with `display_name` in `accounts`,
and the rules document belongs with the pack index in `content`.

**Rejected.** One `economy` app for everything: it would be about twenty models and a 3,000-line
`services/`, against the "many small files" rule. Putting `Wallet` on `accounts.Player`: B02's
`Player` is written by the auth paths, and the wallet row is the lock every batch takes, so it must
be its own narrow row.

## R2. Content versions: B04's index, extended, and the support window

**Decision.**

- **Reuse B04's lookups** (`apps/content/services/lookups.py`): `catalog_price(version, kind, id)` and
  `trip_definition(version, trip_id)` already answer "price and trip in the pack of version N" from
  `PackPriceIndex` and `PackTripIndex`. B03 calls them as they are.
- **Add `PackRulesIndex`**: one row per indexed version, with a compact JSON document of what the
  validators need and the trip index lacks: each line's `unlock` rule and its trips in order, each
  vehicle's `starter` flag, the chapters (order, goal, `completion_bonat`, scenes' ids), the rooms
  (`chapter_id`, `completion_bonat`), the items (`room_id`, variant ids) and the family requests
  (`item_id`, `variant_id`, `reward_bonat`). It is written by `index_pack` with the other rows, so
  publishing and promoting keep it current.
- **Keep more versions.** B04 kept the last 5 published versions. The setting
  `CONTENT_INDEX_KEEP` replaces the constant, default 10. Rows are small (the trip index is the
  largest, about 140 trips per version), so 10 versions are cheap, and with a publish every few
  days they cover the 45-day window of the clarification.
- **A version is supported** when it is indexed and (it is the current version, or its
  `published_at` is within `SYNC_CONTENT_MAX_AGE_DAYS`, default 45). Not indexed because it was
  never published (no `ContentPack` row with that number): `unknown_content_version`. Published but
  retired from the index or older than the window: `content_version_unsupported`.
- **A rebuild command.** `content_index --rebuild` (idempotent, runs in the worker) writes the rules
  rows for every published pack inside the window from the stored pack files, because packs
  published before B03 have none. It is a deploy step (quickstart B1).

**Why.** The index already exists for this purpose (B04 FR-035: "for B03's sync validators"), so
building another would split one idea in two. The document form for the rules avoids six more
tables for read-only data that is only ever read whole.

**Spec refinement.** The 2026-10-25 clarification said "the current version, the production floor
version, and anything within 45 days". The production floor (the `CONTENT_VERSION_FLOOR_URL` of
B04) only keeps staging's numbers above production's; it is never a version a phone plays. It is
dropped, and the spec text is updated.

**Rejected.** Reading the pack file from disk per request: the API role doesn't mount the packs
directory (only the worker does, per CLAUDE.md), and parsing a 400 KB gzip per batch is slow.
Indexing every version forever: the price check against a version older than the window is exactly
the exploit the clarification closes.

## R3. The game day

**Decision.** A game day is the calendar day in `Africa/Cairo` (`SYNC_GAME_TIMEZONE`, default that
value). `economy/services/gameday.py` has `game_date(instant) -> date` using `zoneinfo`. Daily
counters are keyed by that date. The image carries `tzdata` (added to the dependencies if the
slim base lacks it, which `docker/Dockerfile`'s check settles at implementation).

**Why.** Backend §22.2 proposes it, and the spec resolves it. A zone name rather than an offset
follows Egypt's daylight saving without a release. Every counter (overdrafts, `fuel_refill`,
trips per day) uses the date of the **operation's effective time** (R7), so a batch played over
three offline days is counted per day, as the phone would have.

**Rejected.** UTC days: the reset would land mid-afternoon in Cairo. A per-player timezone: not
needed for the MVP's markets, and it would let a player move their reset.

## R4. One writer of a balance

**Decision.** `economy/services/ledger.py` exposes `apply_entry(batch_or_wallet, currency, delta,
reason, ref_type, ref_id, op_id, source)`. It is the only code that changes `Wallet.jenehat` or
`Wallet.bonat`.

- **Preconditions.** The wallet must be the instance obtained from `lock_wallet(player)`, which does
  `select_for_update`, and the call must be inside an atomic block. The function checks both and
  raises a programming error otherwise.
- **Effect.** It computes `balance_after = balance + delta`, refuses a result below 0
  (`InsufficientFunds` for handlers to turn into the reason), and appends a `LedgerEntry`. During a
  batch, `apply_entry(batch, ...)` changes the in-memory wallet and queues the entry on the batch.
  **The write is also in `ledger.py`**: `ledger.flush_entries(wallet, entries)` bulk-inserts the
  `LedgerEntry` rows and saves `jenehat` and `bonat` (`update_fields`) in one call, and
  `BatchState.flush()` only calls it. Nothing outside `ledger.py` constructs a `LedgerEntry` or saves
  a balance column; the wallet's other columns (`fuel`, `fuel_updated_at`, `state_version`, activity
  times) are saved by the batch in a separate `save(update_fields=...)` that names none of the two
  balance columns.
- **The scan.** `test_balance_writers.py` parses every `.py` under `backend/apps` with `ast` and
  fails on: an assignment or augmented assignment to an attribute named `jenehat` or `bonat` on
  anything but a local named in `ledger.py`; a `.update(` call with a `jenehat=` or `bonat=` keyword;
  a `save(update_fields=[...])` or `bulk_update(..., fields=[...])` naming `"jenehat"` or `"bonat"`;
  a `LedgerEntry(` construction or `LedgerEntry.objects.bulk_create(` call outside `ledger.py` and
  migrations;
  a `Wallet(` construction with a balance keyword outside `ledger.py` and migrations; and a raw SQL
  string touching `economy_wallet`. Migrations and tests are exempt, and the exemption list is a
  literal in the test.
- **Database guard.** `CHECK (jenehat >= 0)`, `CHECK (bonat >= 0)` on `Wallet`. `LedgerEntry.save()`
  refuses updates, and its queryset refuses `update()` and `delete()` (the pattern of
  `ContentAuditRecord`). B09's anonymization will use an explicit, named escape.
- **Fuel is not in the ledger** (spec Assumptions): it is recounted state, kept on the wallet and
  written only by `fuel.py`'s functions through the batch. The scan doesn't cover it; the fuel
  fixtures do.
- **The invariant.** `economy/invariants.py` registers `economy.wallet_equals_ledger` from the
  app's `ready()`. It runs one SQL aggregate (a grouped `SUM` of the ledger per player and currency
  against the wallet), reports the number of players that differ, and passes when it is 0.

**Why.** Constitution IV names exactly this. A scan plus a database check plus the invariant is
three layers, each cheap.

**Rejected.** A database trigger forbidding updates of `LedgerEntry`: B09's anonymization has to
change those rows, and a trigger would need an exemption switch that is a hole in itself. The
model guard and the scan carry the rule until B09 decides.

## R5. The batch: in-memory state, one flush

**Decision.** `process_batch(player, base_state_version, ops)` in `sync.py`:

1. **Parse.** The serializer validates the envelope of every operation (a UUIDv7
   `client_txn_id`, an `op_type` string, an ISO-8601 UTC `occurred_at`, an object `payload`) and
   the limits (≤ 100 operations, ≤ 256 KB). A bad envelope refuses the whole request with
   `validation_error` or `batch_too_large`: it can't be attributed to an operation.
2. **Lock.** `atomic()`, create the wallet if missing (insert, ignore conflicts), then
   `select_for_update` on it. Nothing else is locked.
3. **Load.** One query for the `ProcessedOp` rows of the batch's ids. Then a `BatchState` is
   built lazily: the wallet, the inventory, ownership, trip progress, the trip session, the day
   counters, the story state and the grant records, each loaded on first use and cached.
4. **Each operation, in array order.**
   - Its id was processed: return the stored result. If its type or payload hash differs, raise a
     `txn_payload_mismatch` flag (nothing applied).
   - Its id appears earlier in this batch: the same.
   - Its id is older than the retention (R11): reject `op_expired`.
   - Otherwise the handler for `op_type` validates the payload and applies its effects **to the
     `BatchState` only**, or raises `Rejected(reason)`. A rejected handler has changed nothing,
     because handlers validate first and mutate last.
   - The outcome is queued as a `ProcessedOp`.
5. **Flush.** Bulk-insert the ledger entries and the `ProcessedOp`, `TripRun` and flag rows,
   `bulk_update` or upsert the changed inventory, ownership, progress, session, counters, story
   and grant rows, call `ledger.flush_entries` (R4: it writes the entries and the two balances),
   save the wallet's other columns, and bump `state_version` if anything changed.
6. **Answer.** The results in order, the wallet, `state_version` and `state_stale`.

Handlers are plain functions of `(state, payload, ctx)`, registered in a dict by `op_type`. An
unknown type is rejected `unknown_op_type`. `claim_daily_reward` and `claim_task` are not
registered (clarification Q1).

**Dependency rule (refines backend §7.3 rule 4).** `dependency_rejected` is for payloads that name
an earlier operation: `trip_result` (`trip_start_txn`), a revive, an in-trip ad and a booster use
(`ref`). Looking the reference up in this batch's outcomes or in `ProcessedOp`, a *rejected* status
gives `dependency_rejected`; an unknown id gives `no_trip_start`. A booster use has no link to its
purchase, so a rejected purchase leaves an empty stock and `none_left` (the spec is updated).

**Why in memory.** It makes "a rejected operation leaves no trace" true by construction, with no
savepoint per operation (two extra queries each), and it turns 100 operations into a handful of
queries plus bulk writes (R20). The cost is that a handler must read through `BatchState` and never
the ORM, which a lint-style test enforces (R21).

**Rejected.** A savepoint per operation with ORM reads and writes: simple, but 500 or more queries a
batch. A queue worker applying batches asynchronously: the app needs the answer to roll back, and
constitution VI wants one transaction per batch.

**Concurrency.** The wallet lock serializes a player's batches. The same batch sent twice at once
runs twice in turn, and the second finds every id in `ProcessedOp`. The unique constraint on
`(player, client_txn_id)` is the backstop and, if it ever fires, the request fails with a 500 and
the app retries into the stored results.

## R6. Unlock and completion rules (`progress/services/unlocks.py`)

These rules turn the pack's data into the checks FR-020 and FR-028 need. They are read from the
rules document (R2) and the player's state, and each is permissive where a mistake could only let a
player do something harmless, strict where it protects value (constitution V: false rejections hurt
honest players).

- **Vehicle owned**: `Ownership(kind=vehicle)` or the vehicle's `starter` flag.
- **Line unlocked**: `unlock.kind` is `start`; or `vehicle` and that vehicle owned; or
  `line_complete` and that line complete.
- **Line complete**: every `regular` trip of the line has `best_stars ≥ 1`.
- **Trip unlocked** (`trip_start`): its line unlocked, its `vehicle_id` owned, and, for a `regular`
  trip, the trip before it in the line (ordered by `trip_id`) has `best_stars ≥ 1` (the first trip
  of a line has none). A `story` trip needs only its chapter unlocked.
- **Chapter unlocked**: the first chapter always; chapter *n* when chapter *n−1* is complete.
- **Chapter complete**: its goal is met: `complete_line` (that line complete), `own_vehicle`
  (owned), `purchase` (`Ownership(kind=chapter)` for it) or `complete_room` (that room complete).
- **Room complete**: the player owns every item of the room.
- **Item purchasable**: its room's chapter is unlocked.
- **Scene recorded** (`story_progress`): the chapter is unlocked and the scene is one of its
  scenes. The scene need not be unlocked by completion; it is a record of what was seen.

**Completion rewards.** After an accepted `spend_jenehat`, `trip_result` or `story_progress`, the
handler asks
`unlocks.newly_completed(state)` for rooms and chapters that are now complete and have no
`GrantRecord`. Each yields a `story_reward` ledger entry for the pack's `completion_bonat` and a
`GrantRecord(kind=room|chapter)`. Several in one batch are all granted, in room-then-chapter order.

**Open to M10.** The chapter and room rules above are the server's reading of the pack and the
product spec ("completing the room opens the scene and pays BONAT"). M10 must show the same
unlocks. If M10's design needs a different rule, it is changed here with its tests first.

**Rejected.** Checking "trip is the next one" with a stored cursor: a derived rule can't drift from
`TripProgress`. Rejecting a story trip until the chapter is complete: the product spec puts the
story trip at the end, but a player who bought the goal early should not be blocked by ordering.

## R7. Fuel along the operations' own timeline

**Decision.** The rules are M05's, in integer milliseconds, in `economy/services/fuel.py`
(contracts/fuel.md): `regenerate`, `spend_one`, `fill_to_max`, `extend_unlimited`. The wallet holds
`fuel` (liters), `fuel_updated_at` (M05's `countedFrom`, the countdown anchor) and
`fuel_unlimited_until`, plus `timeline_at`, the effective time of the last operation applied.

For each operation in a batch, `t = clamp(occurred_at, timeline_at, now)`, then `timeline_at = t`.
Every instant here (`occurred_at`, `now`, the fuel times, `timeline_at`) is truncated to whole
milliseconds first, as M05 counts, so a stored time and the timeline never differ by microseconds.
So time never goes backward, and a phone can never claim more regeneration than the real time that
passed on the server since the previous operation. The tank's size and the regeneration time are
read at `t` from the settings (and the `fuel_max_bonus` flag from the entitlements seam).

- **Overdraft.** A `trip_start` in `fuel` mode with no liters (after the recount) is accepted with the
  tank at 0, raises `fuel_overdraft`, and increments the day counter for `game_date(t)`. The third
  in a game day is `cap_reached`. The counter increments only when the start is accepted.
- **`unlimited` mode** needs `t < fuel_unlimited_until`, else `not_eligible`. `challenge` mode is
  `not_eligible` until B08.
- **Refills.** `fuel_refill` (ad) and `spend_bonat` `fuel/refuel_full` use `fill_to_max`, `tank_full`
  when full. `fuel_refill` also checks the daily cap (`ads_fuel_refill_daily_cap`, 3) with the day
  counter. `fuel_unlimited_1h` adds 3,600,000 ms from `max(t, current end)`.
- **Order inside a refusal.** A refusal changes no fuel (handlers validate first, R5).

**Why.** The phone recounts offline with its trusted clock (M05 R9). The server can't see that
clock, so it replays the same rules on the times the phone reports, bounded by its own. A late sync
gives the same liters the phone had, and a skewed or lying phone gains nothing beyond real elapsed
time. The first operation of a batch is clamped up to `timeline_at`, so a batch resent from an old
snapshot can't move the timeline back.

**Rejected.** Regenerating to the server's `now` at each start (backend §7.5 as written): a phone
that played five trips offline over two hours and syncs at once would have its liters recounted to
`now`, not to when it played, and honest players would get overdraft flags. Rejecting a backward
or future time: punishes a clock fault that the clamps already neutralize.

## R8. Hard bounds, soft flags and their numbers

**Hard (rejected).** From backend §7.4 and M05:

- `trip_result`: a matching accepted `trip_start` (`no_trip_start`, `dependency_rejected`); one result
  per start (`result_exists`); `trip_id` equal to the start's (`trip_mismatch`); `stars` 0–3 and 0
  for a failed or abandoned outcome (`stars_out_of_bounds`); `0 ≤ earnings_jenehat ≤
  max_earnings_jenehat` of the start's pack trip, and 0 for a failed or abandoned outcome
  (`earnings_out_of_bounds`); for a `finished` outcome, `duration_ms ≥ 0.85 × last_station_at_s ×
  1000` (`duration_out_of_bounds`).

**Soft (accepted, flagged).** Thresholds are settings (contracts/environment.md):

| Flag | When | Default | Why that number |
| --- | --- | --- | --- |
| `fuel_overdraft` | a start with an empty tank (R7) | the first two a game day | backend §7.5 |
| `fast_three_star` | 3 stars and `duration_ms < SYNC_FAST_RUN_PERCENT % of the last station time` | 95 | between the hard bound (0.85) and the scheduled time; to be tuned from the closed test, or replaced by B05's par time |
| `trip_rate` | accepted `trip_start` count in a game day above `SYNC_TRIPS_PER_DAY_FLAG` | 400 | a trip lasts more than a minute, so 400 is over six hours of non-stop play, then rare and worth a look |
| `txn_payload_mismatch` | a processed id came with another type or payload hash | always | a client bug or tampering (R5) |
| `clock_clamped` | an `occurred_at` was moved by more than 10 minutes by the clamps (R7) | 10 min | rare; shows a phone with a bad clock |

A flag row holds the kind, a small details object (ids and numbers, no payload), and the game
date. One flag per kind per player per game day (a counter in `details.count` beyond that), so a
bad phone can't write millions of rows.

**Rejected.** Hard-rejecting a fast 3-star run: the solver's idealized player is not a bound on
humans, and a rejection erases a trip an honest player played.

## R9. The three grant operations

**Decision.** Payloads and checks are in contracts/operations.md.

- **`tutorial_gift`** `{}`: fills the tank (`fill_to_max`, no `tank_full` refusal: a full tank is
  accepted and changes nothing, since the gift is promised, not purchased) once per player
  (`GrantRecord(tutorial, "")`, else `already_granted`). It writes no ledger entry.
- **`comeback_gift`** `{}`: needs `Wallet.comeback_return_at` set (R13), else `not_eligible`; and
  the last `GrantRecord(comeback)` older than `SYNC_COMEBACK_COOLDOWN_DAYS` (30), else
  `not_eligible`. Grants the fill and one `change_bag` (inventory + 1) and records
  `GrantRecord(comeback, <return_at iso>)`. A repeat of the same return: `already_granted`. The
  checks run in the order: no return, already granted, cooldown (contracts/operations.md).
- **Why the return stays after a claim (implementation).** Clearing it would make "claimed" and
  "never offered" look alike, and a bootstrap racing the claim could offer the same return again.
  The grant record keyed by the return's time says it was claimed; `comeback.claimable` is "a
  return, no grant for it, and the cooldown passed" (`services/comeback.py`).
- **`claim_request`** `{"request_id", "content_version"}`: the request is in the rules document of
  that version (`unknown_sku`), no `GrantRecord(request, id)` (`already_granted`), its item (and
  variant when given) is owned (`not_eligible`), in that order. It grants `reward_bonat` with reason
  `request_reward`, `ref_type=request`, source `system`.

**Why a claim for requests but not rooms.** The design has a «خد» button on each request (HANDOFF
`Requests`), so the player decides when; rooms and chapters pay out when the thing happens
(clarification Q2).

**Rejected.** `tutorial_gift` refused on a full tank: M07 sends it at a fixed point, so a refusal
could only look like a bug to the player.

## R10. `settings_update` and the name filter

**Decision.** Payload `{"display_name"?: str, "settings"?: object}`.

- **Name:** 2–20 characters after trimming and collapsing inner whitespace (Unicode NFKC), no
  control, bidi or zero-width characters, not all digits. Checked against `NameFilterEntry` rows
  after normalizing both sides: Arabic letter variants folded (alef forms to a bare alef, alef
  maqsura to ya, ta marbuta to ha), diacritics and tatweel removed, repeated letters collapsed,
  Latin letters lowercased, and a short table of look-alike digits (Western and Arabic-Indic: 2, 3,
  5, 6, 7, 8, 9) mapped to the Arabic letters they stand for in common spellings. Latin letters are
  not transliterated, so a term is entered in each script it should block. A match anywhere in the name rejects it
  (`validation_error`, with `details.field = "display_name"`).
- **Settings object:** known keys only: `digits` (`arabic`|`western`), `sound`, `music`, `haptics`
  (booleans), `pre_trip_card_mode` (`always`|`new_only`), `notif_daily`, `notif_story`,
  `notif_comeback`, `notif_league` (booleans). Merged into the stored object, which stays ≤ 2 KB.
  Stored in `Player.settings` (a JSON column added to `accounts.Player`, expand-only, default
  `{}`).
- **Seed list.** A data migration inserts a short starting list. The owner reviews it
  (owner action). `NameFilterEntry` has `term`, `normalized`, `added_by`.

**Why.** Option A of clarification Q5. The normalizer is shared by the check and by the admin's
"normalized" display, so staff see what is matched.

**Rejected.** A third-party profanity package: none handles Egyptian Arabic spellings well, and it
would be a dependency to audit.

## R11. `ProcessedOp` retention and replay safety

**Decision.** `ProcessedOp` rows are kept `SYNC_OP_RETENTION_DAYS` (180) plus one day from
`processed_at`, then pruned daily. An operation whose `client_txn_id` (UUIDv7: the first 48 bits are
Unix milliseconds) is older than the retention, or more than one day in the future, is rejected
`op_expired` before anything else, so a pruned id can never apply twice. The extra day covers an id
dated a day ahead: it stays acceptable until a day after the retention, so its row must stay as long
(security review, L1).

**Why.** A replay needs the same id. An old id is refused by its own embedded time, which the
client cannot change without making a new id, and a new id is a new intent validated against
today's state. The M05 client generates its ids at the moment of the intent.

**Sizing.** A row is the key (two UUIDs), a type, a status and a reason, a payload hash (32 bytes)
and a small result: about 150 bytes with indexes. At 10k DAU and 20 operations a player-day:
200k rows a day, 36M at 180 days, about 5 GB. At 100k DAU that is 50 GB, which is when
partitioning by `processed_at` is needed (noted for the ops runbook). The result stores only the
status, reason and a few grant amounts; the wallet snapshot is built from the live wallet, never
from the stored result.

**Rejected.** Keeping rows forever: the 50 GB boot volume of the Always Free VM. Retention by the
client's `occurred_at`: untrusted.

## R12. `TripRun` is a plain table with a daily prune

**Decision.** `TripRun` is an ordinary table, indexed on `created_at` and `(player, created_at)`,
with a UUIDv7 key; the daily task deletes rows older than 90 days in chunks of 10,000.

**Why.** Backend §12 says range-partitioned by month. PostgreSQL requires the partition key in
every unique key, so a UUIDv7 primary key (B01's `common.E001`) and partitioning don't combine
without a composite key. At 10k DAU the table holds about 13M rows at 90 days, which a chunked
delete handles. At 100k DAU the plan is the same as for `ProcessedOp`: partition then, by
`created_at`, with a composite key.

**Rejected.** Partitioning now with raw SQL migrations: complexity with no volume to justify it.

## R13. Sessions and the comeback return

**Decision.** `Wallet.last_active_at` is set by every bootstrap, state and sync request that
reaches B03's services. At **bootstrap** only, if `now − last_active_at ≥ SYNC_SESSION_GAP_MINUTES`
(30), a new session starts. If also `now − last_active_at ≥ SYNC_COMEBACK_AWAY_DAYS` (7 days, by
Cairo calendar days) and the cooldown has passed (R9), `comeback_return_at = now`. A shorter gap
leaves it unchanged, so a player who got a return and has not claimed yet keeps it claimable.
`comeback_return_at` stays after a claim (its `GrantRecord` marks it claimed, R9) and is replaced by
a later return. "7 days" counts game days by the calendar in `SYNC_GAME_TIMEZONE`: back on the 20th
after last playing on the 13th is 7, whatever the hours.

**Why.** "Away for 7 days" has to be measured against the last time the app was in use, not the last
bootstrap (an app resumed from the background calls bootstrap again). Setting the return only at
bootstrap gives the app its answer at launch, as the `Returning` screen needs (HANDOFF).

**Rejected.** Using `Player.last_seen_at`: B02 sets it only when tokens are issued or renewed, which
is not "used the game".

## R14. Settings, and the tunables parity check

**Decision.** The economy's server values are Django settings read from the environment through
`env.economy()` (contracts/environment.md), with defaults equal to the app's. A pytest
(`test_tunables_parity.py`) reads `apps/mobile/assets/config/tunables.json` and fails when
`fuel_max`, `fuel_max_subscriber`, `fuel_regen_minutes` or `ads_fuel_refill_daily_cap` differ from
the settings' defaults. Server-only numbers (overdraft limit, comeback gaps, thresholds,
retention, windows) are not in the app's file and are not compared. They have no Remote Config key
and no `LiveSetting` copy until B10; that is the tracked deviation in the plan's Complexity Tracking
(constitution VIII), listed in mobile §14.3 as server-only.

**Why.** Constitution VIII wants one source for each balancing number; until B10's `LiveSetting`
exists, the bundled file is it and the check keeps the copies from drifting. The same approach as
`tools/solver`'s `sync --check`.

**Rejected.** Reading `tunables.json` at runtime: the file isn't in the API image, and a server
setting must not depend on an app asset.

## R15. Shared fuel fixtures

**Decision.** `fixtures/economy/fuel.json` holds cases `{name, settings, initial, steps[], expected}`
where a step is `{op, t_ms, ...}` and `expected` is the liters, `fuel_updated_at` and unlimited end
after each step. It starts with M05's worked examples
(`specs/007-m05-local-economy/contracts/fuel-and-time.md`) and adds the server's clamp and
overdraft cases. `test_fuel_fixtures.py` replays it through `fuel.py`. One Dart test in
`apps/mobile/test/core/economy/fuel_fixtures_test.dart` replays the same file through M05's fuel
functions for the cases that don't involve server-only rules (the cases carry a `scope` field:
`both` or `server`). SC-005 is this file.

**Why.** Two implementations of one rule are the case constitution III exists for, even though fuel
is not in the engine. A shared file is cheaper than prose that drifts.

## R16. Bootstrap, state, the neutral blocks and the summary

**Decision.** Shapes are in contracts/api.md. Bootstrap's `entitlements`, `daily` and `client`
blocks have fixed neutral values until their features arrive: `entitlements` from the
`entitlements.py` seam (all false, empty); `daily` `{game_date, challenge_available: false,
reward_claimable: false}`; `client` from `CLIENT_MIN_VERSION` and `CLIENT_LATEST_VERSION` (both
`1.0.0`), with `force_update = parsed(X-Client-Version) < min`. A new `comeback` block carries
`{claimable}`. `accounts/services/summary.py` reads `driver_level` from the player, `bonat` from
the wallet, and `chapter_id` as the highest unlocked chapter that isn't complete (else the last
complete one, else the first).

**Why.** The shapes are fixed now so M06 and later features don't change them. The summary is the
B02 seam.

**Rejected.** Omitting the neutral blocks: M06 would code against a shape that changes in B06.

## R17. Documents updated in the same PR

- Backend §6.2: `batch_too_large`. §6.4: bootstrap's `comeback` block, `fuel_updated_at` meaning,
  `GET /v1/state`. §7.2: the reasons `request_reward`, `story_reward`. §7.3: rule 4 (dependency),
  the `op_expired` rule, the effective-time clamp. §7.4: the three grants, `fuel_refill` without
  a `ref`, `claim_daily_reward`/`claim_task` marked B08/M13. §7.5: the timeline rule (R7). §12:
  `LedgerEntry.op` as a plain id, `TripRun` unpartitioned, the new models. §22.2: resolved.
- Mobile §12: the three new operations. `docs/delivery-plan.md`: the B03 progress line and the
  handed-over list. `docs/owner-actions.md`: the B03 section. `docs/runbooks/economy.md`: new
  (flags, adjustments, thresholds, the 100k-DAU partition note). `CLAUDE.md`: the B03 line, the
  `content_index` command and the thorough run.
- `specs/010-b03-ledger-sync/spec.md`: the support window wording (R2) and the dependency wording
  (R5), done.

## R18. Limits and the throttle

**Decision.** `SyncThrottle`, scope `sync`, key `player_id`, rate `THROTTLE_SYNC_RATE` (default
`60/min`), on `POST /v1/sync` only; bootstrap and state use the player default (120/min). The body
is capped at 256 KB by the serializer's size check on the raw body and at 512 KB by the edge. A
`result` object inside a `trip_result` is capped at 8 KB. The throttle fails open like the others.

**Why.** Backend §6.5 lists it as "later: sync 60/min/player". A queue of 5,000 offline operations
is 50 batches, which fits in a minute, and the app can pace itself.

## R19. Admin and audit

**Decision.** Pages are in contracts/admin.md.

- **Wallet, ledger, flags:** read-only inlines on the existing `PlayerAdmin` (B02), plus a flag
  list with filters and a "review" action (a form with the resolution).
- **Adjustment:** an admin action on the player page ("Adjust balance") needing the custom
  permission `economy.adjust_wallet`. It calls `adjustments.adjust(player, currency, delta,
  reason, actor)`, which locks the wallet, calls `apply_entry(source=admin)` and writes an
  append-only `WalletAdjustment(actor, player, currency, delta, reason, ledger_entry, at)`.
- **Name filter:** a normal `ModelAdmin`; Django's own `LogEntry` is the audit for those edits.
- **What "the audit log" means (FR-042, SC-011).** For adjustments it is `WalletAdjustment`
  (append-only: actor, player, currency, delta, reason, ledger entry, time). For a flag review it is
  the flag's `reviewed_by`, `reviewed_at` and `resolution`, which the review action sets once and
  the admin then refuses to change. Neither writes a `LogEntry`, so there is one place to look per
  kind, and the records can't be edited from the admin.
- **Groups:** `player_support` gains view on wallet, ledger, flags and change on flags;
  `economy_ops` is new, with the adjustment and the name filter. Created by migration like B02's.

**Why.** The audit log requirement (backend §13) for wallet adjustments gets a dedicated,
append-only table because a ledger entry alone doesn't say who or why; the name filter uses the
admin's built-in log.

## R20. Cost of a batch

**Decision.** The query budget for a batch of 100 mixed operations is about 12 reads (wallet lock,
`ProcessedOp` ids, inventory, ownership, progress, session, counters, story, grants, the player's
name check if present, the pack's rules and prices through the index, loaded per distinct version)
and 8 bulk writes. A test counts queries (`django_assert_max_num_queries`) for the 100-operation
fixture batch and fails above 40. The pack lookups for each distinct `content_version` are loaded
once per batch into the context (the trips and prices a batch touches, by one `IN` query).

**Why.** SC-008 asks for a 1 s p95 on a 1 OCPU VM, and a per-operation query pattern would not meet
it.

## R21. Testing

- **Unit, tests first:** `ledger.py`, `fuel.py`, `gameday.py`, every handler (one file per family,
  one case per reason in contracts/operations.md), `unlocks.py`, the name normalizer.
- **Property (hypothesis):** a stateful machine generates random valid-ish operation sequences with
  random times, splits them into batches, applies some twice, and after every batch asserts:
  wallet equals ledger per currency, no balance below 0, `state_version` monotonic, no ledger entry
  with a positive BONAT delta except a server grant reason, no pair of one op with BONAT down and
  JENEHAT up, and re-applying the batch changes nothing.
- **Concurrency:** threads against a real database: the same batch twice, two different batches of
  one player, 200 concurrent in total (SC-004).
- **Scan and parity tests:** the balance writers (R4), tunables (R14), fuel fixtures (R15), the
  handlers' no-ORM rule (a test imports each handler module and fails if it references `objects`),
  floats (no `float`, `Decimal` or true division in `economy` and `progress`, outside tests).
- **Contract:** schemathesis over the three endpoints with the player auth hook; the committed
  OpenAPI file; one test per documented answer and reason.
- **Privacy:** the B02 scan, extended: no payload, balance or name in logs after a run of every
  operation.
- **Simulation:** 30 game days of generated honest play with skewed clocks (SC-006), run with
  `time-machine`.

## Handed to later features

- **M06 (spec 011):**
  - Send pending operations in `seq` order in batches of 100 with `base_state_version`; apply each
    answer; on `state_stale` fetch `GET /v1/state` and `replaceBase`.
  - Replace the wallet with the answer's wallet, including `fuel_updated_at` as M05's `countedFrom`.
  - Treat `op_expired`, `content_version_unsupported` and `unknown_content_version` as rejections
    that roll the operation back and say nothing alarming; M15 reports them.
  - Anchor trusted time on `server_time`.
  - Call `comeback_gift` only when bootstrap says `comeback.claimable`, and not again while one is
    in the outbox: bootstrap keeps saying claimable until the claim is synced (found by the
    simulation, `test_simulation.py`).
- **M07:** `tutorial_gift` and `settings_update` (the name). A refused name shows `Name`'s error
  state.
- **M10:** `story_progress` and `claim_request`. The unlock and completion rules of R6. The room
  and chapter BONAT arrives with the next sync (clarification Q2).
- **M11, B07:** `ad_reward` for the four client placements; the SSV grant for `morning_piggy` calls
  `apply_entry`.
- **B06, B12:** fill `entitlements.py` (`fuel_max_bonus`); grant through `apply_entry`.
- **B08, M13:** register `claim_daily_reward`, `claim_task` and the `challenge` fuel mode; fill
  `DailyState` and the longest streak; resolve HANDOFF §9.3 #6.
- **B09:** the anonymization path of `LedgerEntry` and the cleanup of every table here on deletion.
- **B10:** move the settings to `LiveSetting`; `426 client_outdated`; the maintenance end time.
- **Phase 3 (B13):** leagues exclude players with open flags.
