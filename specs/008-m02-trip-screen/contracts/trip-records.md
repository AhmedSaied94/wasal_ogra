# Contract: Trip Records on Disk

How the trip's replay record and its pending economy calls are stored, so a killed trip comes back
exactly (FR-006, FR-014 to FR-016). Tables are in [data-model.md](../data-model.md); the reasons are
research R6 to R8.

## The interface

```dart
abstract interface class TripRecords {
  /// Writes a new record with no commands, t_ms = 0.
  Future<void> create(TripRecordHeader header);

  /// Appends one accepted command and moves the record's t_ms to its time, in one transaction.
  Future<void> appendCommand(TxnId start, LoggedCommand command);

  /// Appends a UseBooster command and its pending economy call, in one transaction.
  Future<void> appendBoosterUse(TxnId start, LoggedCommand command, TripIntent intent);

  /// Saves the clock at a pause.
  Future<void> saveClock(TxnId start, int tMs);

  Future<void> deleteIntent(TxnId request);

  /// The full record (header, commands in order, t_ms) and its pending intents, or null.
  Future<StoredTrip?> load(TxnId start);

  /// Deletes one record with its commands and intents.
  Future<void> delete(TxnId start);

  /// Deletes every record except [keep] (null: all). Run at launch.
  Future<void> deleteAllExcept(TxnId? keep);
}
```

`StoredTrip.toReplayRecord()` gives M01's `ReplayRecord {definition, seed, params, command_log, t_ms}`.

## Writes

- Writes are queued and run one after the other, on drift's background isolate. The controller never
  awaits one before applying the next command; it awaits only where order with the economy matters
  (the record before `startTrip`, the booster use before `useBooster`).
- A write that fails (a full disk) is retried with the next write. The trip continues; a kill before
  a write succeeds loses only the commands since the last one that did.
- `appendCommand` rows get `seq` = the number of rows already in the record, so the order is the
  acceptance order.
- `DriftTripRecords` takes an optional `onKillPoint` callback and calls it with a `TripKillPoint`
  (`lib/features/trip/data/trip_kill_point.dart`) after each write step, so tests can stop there
  (trip-controller.md, "Test seams").

## Rebuild

1. `load(unfinished.startTxn)`.
2. `TripEngine.rebuild(stored.toReplayRecord())`. Any `RebuildRefused` (bad JSON, out-of-order
   commands, a command rejected on replay) ends the trip as abandoned (trip-controller.md, "Ending
   without a record").
3. Send the stored intents with their own ids.

## Launch cleanup

Before the boot hand-off: `deleteAllExcept(economy.view.unfinished?.startTxn)`. This removes records
whose start was refused, whose result was recorded before the record was deleted, and intents left
behind with them.

## Schema

- `AppDatabase.schemaVersion` becomes 2. `upgradeSteps[2]` creates the three tables. `make-migrations`
  exports `drift_schemas/app/drift_schema_v2.json` and writes the v1 → v2 migration test.
- Columns are `INTEGER` or `TEXT` only (the REAL guard).
- `app_database_test.dart`'s table list grows from 8 to 11.

## Guards

- `test/repo/economy_writes_test.dart`:
  - the files that may import `app_database.dart` gain `lib/features/trip/data/drift_trip_records.dart`
    and `lib/features/trip/trip_providers.dart`;
  - a new rule: only `drift_trip_records.dart` (and `lib/core/storage/`) may write `trip_record`,
    `trip_record_command` or `trip_intent`;
  - the economy's tables stay as they are: the trip store never writes them.
- `test/repo/domain_imports_test.dart` lists `lib/features/trip/domain` with its allowed imports:
  `dart:core`, `dart:collection`, `dart:math`, `package:content_models/`, `package:trip_engine/`,
  `package:wassal/core/content/domain/`, `package:wassal/features/trip/domain/` and the glossary's
  `package:wassal/core/glossary/ids.dart` (pure Dart, for research R23's `LineId` conversion).

## Tests

- Append and load round-trip; `seq` order; the clock.
- Rebuild equality: for each sample trip, kill after every write, rebuild, and compare
  `TripState.toJson()` with the live engine's state at the record's saved clock (SC-006).
- Intents: a kill between the booster's write and `useBooster`, then the rebuild sends it with the
  same id, and the economy charges once.
- Cleanup: stale records, orphan intents.
- The v1 → v2 upgrade keeps every economy row (drift's generated test, plus data).
