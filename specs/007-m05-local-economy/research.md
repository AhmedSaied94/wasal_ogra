# Research: Local Economy (M05)

Phase 0 of [plan.md](./plan.md). Each entry records a decision, why it was made, and what was
rejected. The spec's three clarifications (fuel for replays, the clock before server time, device
backup) are owner decisions, recorded in [spec.md](./spec.md#clarifications). Entries below
implement them and cite them where they apply.

Versions were read from pub.dev on 2026-10-22.

## R1. Dependencies

**Decision.**

| Package | Version | Kind | Why |
| --- | --- | --- | --- |
| `drift` | `^2.35.2` | runtime | The locked stack's database (constitution). Typed tables, transactions, watch streams, step-by-step migrations. |
| `sqlite3` | `^3.7.1` | runtime (direct) | drift's engine. 3.x bundles SQLite through Dart build hooks, so no `sqlite3_flutter_libs` (M03 research R1). A direct dependency pins the hook's version. |
| `uuid` | `^4.6.0` | runtime (direct; already transitive) | UUIDv7 `client_txn_id`s (constitution VI, R10). |
| `trip_engine` | path `../../packages/trip_engine` | runtime | `TripResult` and `TripOutcome`, which the economy records (FR-032). Pure Dart; M02 needs it too. |
| `drift_dev` | `^2.35.1` | dev | drift's code generator, run by the existing `build_runner`, and its schema dump and migration-test tools (R3). |

- **No `drift_flutter`.** Its 0.3.1 still depends on the end-of-life `sqlite3_flutter_libs` and
  `sqlcipher_flutter_libs` stubs. Its one convenience, `driftDatabase(name:)`, is a few lines over
  `NativeDatabase.createInBackground` and `path_provider`, which the app already has (R2).
- **No property-testing package.** `glados` hasn't been released since 2023 and predates Dart 3.
  The property tests use seeded `dart:math` `Random` generators written for this feature (R19).
- **The SQLite binary.** By default the `sqlite3` hook downloads a prebuilt SQLite for the target
  from the package's GitHub release and checks it against the sha256 published with the package.
  CI and a fresh dev machine therefore need to reach GitHub once per `sqlite3` version. The binary
  is upstream SQLite, public domain, compiled with `SQLITE_DQS=0` and the other options listed in
  the package's `doc/hook.md`. No `hooks: user_defines` entry is needed.

**Alternatives rejected.**

- `sqlite3_flutter_libs`: end-of-life (M03 R1).
- SQLCipher or SQLite3MultipleCiphers (`source: sqlcipher`): encryption at rest doesn't protect a
  balance the server recomputes anyway (constitution IV), and it adds a key to manage and a
  licence to review. A rooted player who edits the database gains nothing that survives sync
  (spec Assumptions, "The server is the authority").
- `isar`, `hive`, `shared_preferences`: rejected by the constitution's locked stack (mobile §25).

## R2. Opening the database

**Decision.**

- **One file:** `<getApplicationSupportDirectory()>/db/wassal.sqlite`, next to M04's `content/`.
  On Android that is the app's private `files/` directory, which the OS never evicts (FR-001,
  M04 research R5).
- **Off the UI isolate.** `NativeDatabase.createInBackground(file, setup: …)` runs SQLite on its
  own isolate. Queries and commits never block a frame (FR-005).
- **Pragmas** set in `setup` on every open:
  - `journal_mode = WAL`, so readers don't wait for the writer;
  - `synchronous = FULL`, so a committed operation survives a power cut, not only a process kill.
    Each commit costs one fsync, a few milliseconds on the reference device, within SC-006;
  - `foreign_keys = ON`.
- **Opened during startup.** `economyProvider` (contracts/economy-api.md) joins
  `appStartupProvider`'s wait list next to the settings store, tunables and content. Any failure to
  open, migrate or read fails startup, and the boot screen shows M03's failure state with a retry,
  whose `retryAppStartup` also invalidates the economy providers (FR-003, FR-004).
- **Never deleted.** No code path deletes, renames or recreates the database file. A file that
  doesn't open stays as it is for the next retry and for support.

**Alternatives rejected.**

- `getApplicationDocumentsDirectory()`: on iOS it is visible in the Files app.
- `journal_mode = DELETE` (the default): readers block during commits.
- `synchronous = NORMAL` with WAL: survives a process kill but can lose the last commit on power
  loss. A lost earnings commit is exactly what SC-007 forbids.

## R3. Migrations and the newer-database refusal

**Decision.**

- **Schema version 1** is this feature's. Each later feature that adds tables (M06 sync queue, M10
  story, M13 daily, M06 entitlements) raises `schemaVersion` by one and adds a step.
- **Step by step.** `MigrationStrategy.onUpgrade` runs one step per version, from
  `AppDatabase.upgradeSteps`, each calling the step drift's `make-migrations` generates for it.
  Every step runs inside one transaction together with the `PRAGMA user_version` bump, so a kill
  or failure mid-upgrade leaves the previous version intact (FR-003). The plan's tests kill an
  upgrade half way (R19). (As built: drift runs migrations without a transaction of its own, so
  the code opens one per step.)
- **Exported schemas.** `apps/mobile/drift_schemas/app/drift_schema_v1.json` is committed, written
  by `dart run drift_dev make-migrations`, which also generates the schema-verification tests
  under `test/drift/` once there are two versions. Until then v1's helpers come from
  `drift_dev schema generate`, and `test/drift/app/schema_v1_test.dart` checks v1. Every later
  version adds its JSON, and CI fails if the exported schema doesn't match the code.
- **A newer database is refused.** When the file's `user_version` is above the app's
  `schemaVersion` (an older build installed over a newer one, possible only in dev), `onUpgrade`
  throws `DatabaseFromNewerApp` before touching anything. Startup fails, and the boot screen shows
  its failure state (FR-004).
- **A failed open never resets.** drift's `onCreate` runs only on a file with `user_version = 0`
  and no tables. A file that can't be read raises, and is left alone (R2).

**Alternatives rejected.**

- Hand-written `ALTER TABLE` with version `if`s: drift's generated steps are typed and testable.
- Destructive fallback (drop and recreate): forbidden by FR-004, and it would wipe offline savings
  the server has never seen.

## R4. The ledger: one row per operation

**Decision.** `ledger_ops` holds one row per applied operation (data-model.md):

- the UUIDv7 `txn_id`, unique (R10);
- the `op_type` and the wire `payload` as canonical JSON, exactly what `POST /v1/sync` will carry
  (backend §7.3, §7.4), so M06 sends it unchanged (FR-044);
- the effect on each currency as three integer columns, `jenehat_delta`, `bonat_delta` and
  `fuel_delta`, plus the `reason` (backend §7.2) of the JENEHAT or BONAT effect;
- `ref` (the trip start the op belongs to), the trusted `occurred_at_ms`, the `content_version`,
  the fuel tunables in force (`fuel_max`, `fuel_regen_minutes`), and for a `trip_start` the trip's
  `max_earnings_jenehat`;
- `sync_status` (`pending`, `accepted`, `rejected`) and `sync_reason`. Only these two columns ever
  change (FR-015).

`seq`, an `INTEGER PRIMARY KEY AUTOINCREMENT`, is the order operations were applied in, and the
order M06 sends them in (FR-017, FR-045).

**Why three delta columns, not mobile §11's `currency, delta`.** No local operation moves two
currencies today, but `trip_start` moves fuel and `trip_result` moves JENEHAT, and a later op may
move both (M13's daily reward). One row per operation keeps the operation, its id and its sync
status in one place, which is what sync and idempotency key on. Mobile §11 is updated (R21).

**Why store the fuel tunables.** Fuel isn't a sum: it regenerates between operations (R8). Each
row records the `fuel_max` and `fuel_regen_minutes` it was applied with, so replaying the
operations (R5) gives the same fuel even after Remote Config (M15) changes them.

**Alternatives rejected.**

- Only materialized balances, no operation log: nothing for M06 to send, and nothing to roll back.
- Event sourcing with no materialized tables: every read would fold the whole log (R18).

## R5. The projection: applied step by step, rebuilt by a fold

**Decision.**

- **State.** `EconomyState` (data-model.md) is everything the operations produce: balances, fuel
  state, inventory, ownership, trip progress, the unfinished trip and the latest result. It is an
  immutable pure-Dart value in `lib/core/economy/domain/`.
- **Rules.** One pure function per operation, `apply(state, op) → state`, used both ways:
  - **Step by step.** A new operation is validated against the current state (R6, R12, R13), then
    applied. Its row and the changed materialized rows (`wallet`, `inventory`, `ownership`,
    `trip_progress`, `trip_session`) are written in one transaction (R11).
  - **Rebuild.** `fold(base, ops)` applies, in `seq` order, every non-rejected operation after the
    base. It runs when a rejection or a new base arrives (R6, FR-046, FR-047), and in tests.
- **The base** is the `projection_base` row: an `EconomyState` and `after_seq`, the last `seq` it
  already includes. Until M06 it is the new player's state (FR-010) with `after_seq = 0`. M06
  replaces it with the server's snapshot, setting `after_seq` to the last op the server has answered
  (FR-047).
- **The invariant** (FR-018): the materialized tables always equal `fold(base, ops)`. The property
  test checks it after every step (SC-001). A debug-build check at startup compares them, and the
  release build trusts the transactions.

**Alternatives rejected.**

- Recomputing balances at every read: R18's 50,000-operation budget rules it out.
- Compensating "reversal" operations for rejections: the server never sees them, so the log would
  disagree with the server's.

## R6. Rejections and the operations that depend on them

**Decision.** A rejection is applied the way the server applies a batch (backend §7.3, rule 4):
`markRejected` sets the row's `sync_status`, then the economy rebuilds. During the rebuild, each
later operation is validated again against the rebuilt state, and one that no longer validates is
left out of the projection. Its row stays (append-only) and its status stays `pending`, so M06
expects the server to reject it too, with `dependency_rejected` or `insufficient_funds`
(FR-046).

| Re-validated in the fold | Left out when |
| --- | --- |
| `spend_jenehat`, `spend_bonat` | the balance would go below 0, or the SKU is already owned |
| `use_booster` | none of that booster is left |
| `trip_result` | its start was left out, or already has a result |
| `ad_reward` `result_double` | its result was left out or already doubled |
| `ad_reward` `trip_revive` / `traffic_jam`, revive purchase | their trip's start was left out |

**Lenient, as the server is.** A `trip_start` on an empty tank stays in the fold, with fuel held
at 0, because the server accepts a fuel overdraft as a soft anomaly (backend §7.5). A full refill
on a tank that is full in the fold stays too, adding nothing. Prices and catalog checks aren't
re-run: the row recorded the price it was charged.

**Alternatives rejected.** An explicit `depends_on` list per operation: the server doesn't use one,
and re-validation catches every case without anyone having to declare dependencies.

## R7. The operation vocabulary and its reasons

**Decision.** The economy applies six of backend §7.4's operation types. contracts/operations.md
gives each one's payload, effects and refusals.

| Operation | `op_type` | Reason (backend §7.2) |
| --- | --- | --- |
| Trip start | `trip_start` | none (fuel only) |
| Trip result | `trip_result` | `trip_earnings` |
| ×2 earnings (ad) | `ad_reward` `result_double` | `ad_result_double` |
| Rewarded refill | `ad_reward` `fuel_refill` | none (fuel only) |
| Rewarded revive, traffic jam | `ad_reward` `trip_revive`, `traffic_jam` | none (no balance effect) |
| Item, vehicle, chapter goal | `spend_jenehat` | `item_purchase`, `vehicle_purchase`, **`chapter_purchase`** |
| Booster, refill, revive, unlimited fuel | `spend_bonat` | `booster_purchase`, `fuel_purchase`, `revive_purchase`, **`fuel_unlimited_purchase`** |
| Booster use | `use_booster` | none (inventory only) |

- **Two new reasons**, in bold, fill the gaps the spec handed to the plan. Backend §7.2 gets both
  in this PR (R21), and B03 adopts them.
- **`morning_piggy`** is refused on the device (`server_only`): it grants BONAT, which only SSV may
  do (constitution IV, FR-011).
- **The kind decides the currency.** `item`, `vehicle` and `chapter` cost JENEHAT; `booster`,
  `fuel`, `revive` and `fuel_unlimited` cost BONAT. A catalog price in the other currency is
  refused as `catalog_mismatch`, so no content error can open a BONAT-for-apartment path
  (constitution IV, product-spec «مبادئ التوازن»).
- **No operation takes BONAT and gives JENEHAT** (FR-012). A test enumerates every operation type
  and placement and checks that their effects never pair a BONAT decrease with a JENEHAT increase,
  and that no effect raises BONAT.
- **Revive's reference.** Backend §7.4's `spend_bonat` payload has no `ref`. A revive belongs to
  one trip, so its payload adds `ref`, the trip start, which B03 needs to cap one revive per trip.
  This is a hand-over to B03 (R21).
- **Ownership of a chapter goal.** Backend §12's `Ownership.kind` has no `chapter`, though
  §7.4's `spend_jenehat` accepts `chapter`. The app records `chapter` ownership. Hand-over to B03.

## R8. Fuel

**Decision.** The fuel state is `liters`, `counted_from_ms` and `unlimited_until_ms` (null when no
window). `counted_from` is always set. Below the maximum it is when the current countdown started;
at or above it, the moment the tank last became full. That is backend §7.5's `fuel_updated_at`. With
`max` = `fuel_max` and `regen` = `fuel_regen_minutes` × 60,000 ms, all integers:

- **Regenerate to time `t`.** At or above the maximum nothing regenerates (FR-024). Below it,
  `n = (t − counted_from) ~/ regen`. If `liters + n` reaches the maximum, `liters = max` and
  `counted_from` becomes the moment it filled, `counted_from + (max − liters) × regen`. Otherwise
  `liters += n` and `counted_from += n × regen`, which keeps the time already counted toward the
  next liter (FR-021).
- **Every operation regenerates to its own `occurred_at` first**, with the tunables it records
  (R4). Reads regenerate from the last operation to trusted now with the current tunables. So a
  tunable change applies to the time since the last operation, and what any operation recorded
  never changes (FR-027).
- **Spend one liter** (a `trip_start` in `fuel` mode at `t`, needing `liters ≥ 1`):
  `liters − 1`. If that brings the tank below the maximum from at or above it, `counted_from = t`;
  otherwise `counted_from` is kept (US1 scenario 4).
- **Fill to the maximum** (`refuel_full`, `fuel_refill`), refused when `liters ≥ max`:
  `liters = max`, `counted_from = t`.
- **A raised maximum** (M17's subscriber tank, or a tunable): counting resumes from the moment the
  tank last filled, for the time since the last operation. No write is needed to start it, which is
  why `counted_from` is never null.
- **Unlimited fuel** (`fuel_unlimited_1h` at `t`):
  `unlimited_until = max(unlimited_until ?? t, t) + 60 min`, so a second purchase extends the window
  from its end (US3 scenario 7). A `trip_start` with `t < unlimited_until` is `fuel_mode:
  unlimited` and leaves the liters alone. Regeneration goes on during the window.
- **What the view shows**: below the maximum, `nextLiterAt = counted_from + regen` and
  `fullAt = counted_from + (max − liters) × regen`; at or above it, both null (FR-023).
- **The window's 60 minutes** are the definition of the product `fuel_unlimited_1h` (glossary §3.3),
  not a balancing number. A different duration would be a different product id (the starter pack's
  two hours, phase 2, is a server grant), so it isn't a tunable (constitution VIII).
- **The fuel delta** recorded on a row is what that operation changed (−1, or the liters a refill
  added), for M06 and for reading the log. The fold recomputes fuel from the times, not from the
  deltas.
- **A new player** starts at `liters = fuel_max`, `counted_from` = the first open (FR-010).

B03 must agree with these rules (spec Assumptions). Backend §7.5 gets the countdown rule, the kept
liters above the maximum, the refused full refill and the window extension in this PR (R21).

**Alternatives rejected.**

- Restarting the countdown at every spend: a player who starts trips back to back would lose up to
  20 minutes of counted time per trip.
- `min(fuel_max, fuel + n)` applied to a tank above the maximum (backend §7.5 as written): it takes
  away liters the player had.

## R9. Trusted time

**Decision.** Implements the second clarification (FR-025, FR-026).

- **What is read.** A small Android method channel, `wassal/clock`, next to M03's
  `wassal/launch` in `MainActivity`. It returns one snapshot:
  - `elapsed_realtime_ms`: `SystemClock.elapsedRealtime()`, milliseconds since boot. It counts
    deep sleep and no clock change affects it;
  - `boot_count`: `Settings.Global.BOOT_COUNT` (API 24, the app's `minSdk`), or null if the
    device doesn't provide it.
- **Between snapshots**, a Dart `Stopwatch` extends `elapsed_realtime_ms`. A `Stopwatch` stops
  while the CPU sleeps, so the clock takes a fresh snapshot at startup and on every return to the
  foreground. While the app is in the foreground the screen is on, so the `Stopwatch` and the
  phone's counter agree.
- **The anchor** (`clock_anchor`, data-model.md) is `anchor_ms`, the `anchor_elapsed_ms` it was
  taken at, the `boot_count`, its `source` (`device` until M06, then `server`) and
  `latest_trusted_ms`.
- **Trusted now** = `anchor_ms + (elapsed_now − anchor_elapsed_ms)`, while the phone hasn't
  restarted.
- **A restart** is detected when `boot_count` differs from the anchor's. If either is null, a
  restart is detected when `elapsed_now < anchor_elapsed_ms`. After a restart, the anchor is
  retaken at `max(device clock now, latest_trusted_ms)`. So trusted time never goes back, and the
  time the phone was off counts only if the clock says it passed (FR-026).
- **`latest_trusted_ms`** is written with every operation (same transaction) and when the app goes
  to the background. The anchor is read and written only through `DriftEconomyStore`
  (`loadAnchor`, `saveAnchor`), the single writer of the database (R16).
- **Before the first anchor** (a new install), the anchor is taken on the device clock at the first
  startup.
- **M06** calls `anchorOnServer(serverTime, elapsedAtResponse)` after each bootstrap. The source
  becomes `server`, and the same formula applies. That is mobile §13's
  `device_monotonic + server_time_offset`, kept across app restarts.
- **No channel** (iOS until phase 3, `flutter test`): the clock falls back to the device clock,
  never below `latest_trusted_ms`. Tests inject a fake `UptimeSource`.
- **UTC milliseconds** everywhere. Time zones never enter the economy.

**Why it meets constitution VI.** Constitution 1.3.0 amended VI's time clause for this design
(analysis finding C1): trusted time is an anchor advanced by the phone's uptime, the device clock
only takes a new anchor (first open, or a restart while offline) and never moves time back, a clock
change while the phone stays on does nothing, and the server never takes device time as authority.
The server recomputes fuel from its own clock on every `trip_start` (backend §7.5), and its wallet
replaces the device's (M06). No exception is needed.

**What it costs a cheater.** Moving the clock while the phone stays on gains nothing. Moving it
forward and restarting refills the tank on the device until the next sync, where the server flags
each overdraft and rejects them beyond its daily tolerance (backend §7.5).

**Alternatives rejected.**

- `dart:ffi` `clock_gettime(CLOCK_BOOTTIME)`: synchronous, but it still needs the boot count from
  Java, so the app would carry two mechanisms instead of one.
- Detecting a restart from `device clock − uptime`: a clock change moves that estimate exactly like
  a restart does, so the trick would work again.
- `/proc/sys/kernel/random/boot_id`: SELinux may deny it to apps on some Android versions.
- An NTP request: needs the network, and gives nothing the bootstrap won't.

## R10. Request ids and idempotency

**Decision.**

- **The caller holds the id.** A screen asks `economy.newRequestId()` when the player's intent
  starts (a sheet opens, the trip's start button is tapped, the result screen offers ×2). Every
  retry or double tap of that intent sends the same id (FR-016).
- **UUIDv7** from `uuid`'s `v7`, given the trusted time, so ids sort roughly in the order they were
  made.
- **A repeated id** returns the stored outcome of the first operation and writes nothing, as the
  server's `ProcessedOp` does. A refused request isn't stored (FR-019), so retrying it with the
  same id is evaluated again. In debug builds, a repeated id whose request differs from the stored
  one fails an assertion.

**Alternative rejected.** Ids made inside the economy for each call: a double tap would make two
ids and charge twice.

## R11. One writer, atomic steps, kill points and a full disk

**Decision.**

- **One writer.** `EconomyService` runs requests one at a time through a Future chain, so two
  requests can't validate against the same state (FR-017, US4 scenario 6).
- **One transaction per operation.** The `ledger_ops` row, every materialized row it changes and
  `clock_anchor.latest_trusted_ms` are written in one drift `transaction`. The in-memory state and
  the view stream change only after the commit returns (FR-002).
- **Kill points.** As in M04's `PackStore`, the store takes an optional `onKillPoint` hook called
  after each write inside the transaction and right after the commit. Tests throw from it, which
  SQLite rolls back, then reopen the same file and check the state (SC-002). The after-commit
  point checks that a commit the process never "saw" is still there after reopening.
- **A full disk** (`SQLITE_FULL`) or any other write error rolls the transaction back. The request
  returns `write_failed`, and nothing in memory changes (US4 scenario 3). Tests inject the error
  through a wrapping `QueryExecutor`.

## R12. Trips

**Decision.**

- **Start** (`startTrip(id, tripId)`). The economy reads the trip from the active `ContentSource`
  itself, never from the caller. The start is refused when the trip isn't in the pack
  (`unknown_trip`), when a trip is unfinished (`trip_unfinished`), or when the tank is empty and no
  window runs (`no_fuel`). The `trip_session` row records the unfinished start: id, trip id, pack
  version, `max_earnings_jenehat`, trusted start time, and whether it was revived or got its traffic
  jam ad (FR-028, FR-031).
- **Replays cost a liter** like any start (spec Clarifications, resolving mobile §24.5). Nothing in
  the start depends on progress.
- **Result** (`recordResult(id, start, result)`). It is refused with `result_exists` when `start`
  is the latest result's start, and then with `no_trip_start` unless `start` is the unfinished
  start. It is refused with `trip_mismatch` unless `result.tripId` matches that start. It is also refused unless the stars are 0 to 3 with 0 for a failed or
  abandoned trip (`stars_out_of_bounds`), and unless the earnings are 0 to the recorded
  `max_earnings_jenehat`, with 0 for a failed or abandoned trip (`earnings_out_of_bounds`).
  Otherwise one transaction adds the earnings, updates `trip_progress` and clears the unfinished
  start. The result becomes the latest result.
- **Progress.** Every result raises `plays`. A finished result can raise `best_stars`, lower
  `best_time_ms`, and set `first_completed_at_ms` once (FR-033).
- **Restart** («عيد المشوار») is two requests from M02: the current result (abandoned or failed),
  then a new start. A kill between them leaves no unfinished trip and an unspent liter, which is
  safe.
- **Resume and revive** make no start (FR-030). A revive, by ad (`ad_reward trip_revive`) or with
  BONAT (`spend_bonat revive`), needs the unfinished trip and is refused when it was already
  revived (`already_revived`), matching the engine's single revive (M01 FR-053).
- **Per-trip ad caps** that the economy can see are enforced here: one `traffic_jam` ad per trip
  (`cap_reached`), and one ×2 per result (`already_doubled`). Daily caps are M11's (FR-037).
- **×2** applies only to the latest result, when it finished and paid more than 0 (`no_result`,
  `not_doublable`). It adds that result's earnings and references its start (FR-035).
- **Booster use** needs the unfinished trip (`no_trip`) and one of that booster (`none_left`).
  M02 calls it after the engine accepts `UseBooster` (spec hand-over).

## R13. Purchases

**Decision.**

- **The price** comes from `ContentSource.price(kind, skuId)` at the moment the purchase applies.
  No price is `not_for_sale`, and a price in the wrong currency for its kind is `catalog_mismatch`
  (R7). The row records the price and the active version (FR-038).
- **SKUs are checked against the pack and the glossary.**
  - An item must exist (`ContentSource.item`) and the request must name one of its variants
    (`unknown_variant`).
  - A vehicle or chapter must exist.
  - A booster must be one of the four in-trip boosters: `change_bag`, `wake_all`, `ledger_peek`,
    `traffic_jam`.
  - `fuel` is `refuel_full`, `fuel_unlimited` is `fuel_unlimited_1h`, and `revive` is `revive`.
  - Anything else is `unknown_sku`.
- **Owned once.** An item, vehicle or chapter already owned is `already_owned`. Ownership records
  the variant, the time and the operation (FR-039).
- **Balances never go below 0** (`insufficient_funds`). BONAT is checked against the local balance,
  the last one known (constitution IV).
- **Unlock order isn't checked here** (spec Assumptions): M08–M10 check it before they call.

## R14. Device backup (resolves the spec's third clarification)

**Decision.**

- **Android 12 and later:** `android:dataExtractionRules="@xml/data_extraction_rules"`, which
  excludes `<exclude domain="file" path="db/"/>` in both `<cloud-backup>` and `<device-transfer>`.
- **Android 11 and earlier:** `android:fullBackupContent="@xml/backup_rules"` with the same
  exclusion.
- The `-wal` and `-shm` files live in the same `db/` directory, so they are excluded with it.
- Nothing else changes: M04's `content/` and M03's preferences are still backed up, as before.
- **A repo guard** (`test/repo/backup_rules_test.dart`) checks that the manifest names both files
  and that each excludes `db/` in every section (FR-006).
- **iOS** (phase 3) sets `NSURLIsExcludedFromBackupKey` on the `db/` directory. Recorded as a
  hand-over.

**Alternative rejected.** `android:allowBackup="false"`: it would also drop the device preferences
and the downloaded packs, which are harmless to restore.

## R15. M04's pack record stays a file

**Decision.** `state.json` stays where M04 put it, and mobile §11's `content_cache` row is updated
to say so.

**Why.** The record describes files on disk, and M04 already makes its writes atomic with the files
they list (M04 research R5). A database row can't commit together with a file rename, so moving it
would trade a proven design for a new crash window and a migration, and gain nothing.

**Alternative rejected.** Moving it into drift as M04's hand-over allowed.

## R16. Layers, folders and guards

**Decision.**

- **`lib/core/economy/domain/`**, pure Dart (FR-043): `EconomyState`, the request and operation
  types, `EconomyRefusal`, the per-operation rules (validate, apply), `fold`, the fuel rules and the
  trusted-time arithmetic. It may import `dart:core`, `dart:collection`, `content_models`,
  `trip_engine`, `package:wassal/core/content/domain/`, and files of its own folder.
- **`lib/core/economy/`**: `EconomyService` (the writer queue and view), `DriftEconomyStore`
  (the only code that writes economy tables), `TrustedClock`, and the providers.
- **`lib/core/storage/`**: the drift database, its tables and the connection (R2, R3).
  `drift_schemas/` holds the exported schemas.
- **`lib/core/platform/uptime.dart`**: the `UptimeSource` interface and its `wassal/clock`
  implementation.
- **Guards** in `test/repo/`:
  - `domain_imports_test.dart` grows a table of domain folders, each with its allowed imports. The
    economy's is the list above. Relative imports inside the same folder are allowed;
  - `economy_writes_test.dart` (new) checks that only `drift_economy_store.dart` writes to the
    economy tables, `clock_anchor` included. It also checks that only `lib/core/storage/`, that
    store and `economy_providers.dart` import the database, the last to construct it and nothing
    more (FR-013). `TrustedClock` reads and writes its anchor through the store;
  - `integer_money_test.dart` also forbids `real()` columns and `RealColumn` under
    `lib/core/storage/` (FR-008);
  - `backup_rules_test.dart` (new, R14).

**Alternative rejected.** A separate `packages/economy`: the rules need the app's `ContentSource`
interface and nothing outside the app uses them. The domain folder and its guard give the same
purity.

## R17. How screens read the economy

**Decision.**

- **`economyViewProvider`** gives an `EconomyView`: balances, the fuel view, inventory, ownership,
  progress, the unfinished trip and the latest result. It changes after every operation (FR-042).
- **Fuel ticks.** While the app is in the foreground, `EconomyService` arms one `Timer` for the next
  liter's arrival and emits a new view when it fires. It re-arms after every operation, after a
  tunable change and on return to the foreground (after the clock's fresh snapshot, R9). It is
  cancelled when the app leaves the foreground (`paused`, `hidden`), because a Dart timer can still
  fire in a backgrounded app. No periodic timer runs, and nothing runs in the background
  (constitution budgets).
- **Countdowns** on screens are `nextLiterAt − trustedClock.now()`, never the device clock. M08
  and M12 tick their own text once a second.
- **Reads are synchronous** after startup (`requireValue`), like the content source.

## R18. Performance

**Decision.**

- **Startup reads only the materialized tables**: one `wallet` row, one `trip_session` row, one
  `projection_base` row, `inventory` (at most 4 rows), `ownership` (tens) and `trip_progress` (at
  most a few hundred). It never reads `ledger_ops`, so its cost doesn't grow with play (SC-005).
- **An operation** costs one transaction of 3 to 6 statements and one fsync (R2), well inside the
  100 ms of SC-006.
- **A rebuild** reads every operation after the base. It runs only on a rejection or a new base
  (M06), and in debug startup. At 50,000 operations it is measured, not budgeted to the player.
- **Indexes:** the unique `txn_id`, `(sync_status, seq)` for M06's pending reads, and `ref`.
- **Measured**:
  - in CI by `test/core/economy/perf/startup_budget_test.dart`: a temp-file database with 50,000
    operations opens and reads within 150 ms on the runner;
  - on the Galaxy A06 by `integration_test/economy_perf_test.dart`: a 200 ms startup budget and a
    100 ms operation budget (owner action, quickstart scenario 5).

## R19. Tests

**Decision.**

- **Domain unit tests** (`test/core/economy/domain/`): every operation's accept and refuse cases,
  fuel arithmetic to the millisecond, trusted time with a fake uptime source (clock changes with and
  without a restart, missing boot count), and the BONAT/JENEHAT direction check (FR-012).
- **The property test** (`fold_property_test.dart`): 1,000 seeded random sequences of up to 200
  requests, rejections and base replacements. After each step, the incremental state equals the
  fold, and JENEHAT and BONAT equal the base plus the non-rejected deltas (SC-001). A failure
  prints its seed.
- **Store tests** (`test/core/economy/`), on real SQLite (temp files, and `NativeDatabase.memory()`
  where reopening isn't needed): every kill point of every operation type (SC-002), idempotency at
  100 repeats (SC-004), a full disk, reopening after commit, a newer database, a failed upgrade, and
  the debug fold check.
- **Migrations** (`test/drift/`): drift's generated schema-verification tests, starting at v1.
- **Seven simulated days** (`fuel_week_test.dart`): starts, refills, purchases and clock changes,
  checked against the rules every simulated minute (SC-003).
- **The integration test** (`integration_test/economy_offline_test.dart`), on a device in airplane
  mode: spend a liter, earn, buy, restart the app, check everything (SC-007).
- **Repo guards** (R16).
- **Coverage** ≥ 80% for the app, as now (constitution XIII).

## R20. Fuel for replays (resolves mobile §24.5)

**Decision.** Every trip start costs one liter, including a replay of a completed trip and a
restart. Only a revive, a resume after a kill and (M13) the first daily-challenge attempt are free
(spec Clarifications, owner decision 2026-10-22). It matches product-spec «الاقتصاد», the ux-spec's
"−١ بنزين" badges, and backend §7.4's `trip_start`, which charges every start. B03 keeps it.

## R21. Documents to update in this PR

- **docs/architecture-mobile.md:**
  - §11: the tables M05 creates (with `ledger_ops`' columns as in R4), `clock_anchor`,
    `projection_base` and `trip_session`; `content_cache` stays M04's file (R15); the backup
    exclusion (R14);
  - §13: trusted time (R9), the fold (R5), and the fuel rules (R8);
  - §24.5: resolved (R20).
- **docs/architecture-backend.md:**
  - §7.2: the reasons `chapter_purchase` and `fuel_unlimited_purchase` (R7);
  - §7.4: the revive's `ref`; `fuel_refill` carries no `ref`, since it belongs to no trip; and
    `morning_piggy` is never sent as a client op;
  - §7.5: the fuel rules B03 must agree with (R8);
  - §12: `Ownership.kind` gains `chapter`.

  None of these is in the Shared Contract Glossary (§3), so the two §3 copies stay identical.
- **docs/delivery-plan.md:** M04 merged in #7; §24.5 resolved in M05; M05's progress entry at
  merge.
- **CLAUDE.md:** the drift commands (`make-migrations`, the schema tests), the first `sqlite3`
  hook download, and the database's place in the app.
- **docs/owner-actions.md:** M05's section, at `/speckit-implement`.

## Handed to later features

- **M02:**
  - Start trips, record results, buy and use boosters and revive through the economy, holding one
    request id per player intent (contracts/economy-api.md).
  - Charge a revive only when the engine reports the trip revivable and below the command cap
    (M01 research R9).
  - On a launch with an unfinished start, rebuild that trip from its replay record, or record it
    abandoned if the record is gone.
- **M06:**
  - Send pending operations in `seq` order (`pendingOps`), and apply each answer
    (`markAccepted`, `markRejected`).
  - Replace the base with the server's snapshot (`replaceBase`).
  - Anchor trusted time on the server's (`anchorOnServer`).
  - Revisit the backup exclusion with backend §22.6.
- **M07:** the tutorial's gift refill needs an operation type that B03 accepts.
- **M08, M12:** countdowns from `nextLiterAt` and `trustedClock.now()`. M12 applies a small BONAT
  purchase only after its 3-second undo window (ux-spec «الشرا»).
- **M09, M10:** check unlock order before calling `buy`.
- **M11:** the daily ad caps, and the ad calls.
- **M13:** `fuel_mode: challenge` for the first daily-challenge attempt.
- **M14 and phase 3:** iOS backup exclusion (`NSURLIsExcludedFromBackupKey`) and an iOS
  `UptimeSource`.
- **M15:** report refusal codes and `write_failed`.
- **M17:** the subscriber's larger tank (`fuel_max_subscriber`), through the cached entitlements.
- **B03:**
  - the fuel rules (R8);
  - the two new reasons (R7);
  - the revive's `ref`;
  - `chapter` ownership;
  - fuel for replays (R20).
