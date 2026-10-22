# Contract: The Economy API

How every feature changes or reads balances, fuel, boosters, ownership and trip progress. The
interface lives in `lib/core/economy/economy.dart`, and the domain types it uses live in
`lib/core/economy/domain/` (data-model.md). This is the only way to change those parts of the
database (FR-013).

## Interface

```dart
abstract interface class Economy {
  /// The current view. Synchronous after startup.
  EconomyView get view;

  /// A new view after every operation, every liter that arrives while the app
  /// is in the foreground, and every tunable change (research R17).
  Stream<EconomyView> get views;

  /// A fresh UUIDv7 for one player intent. Hold it, and send it again on a
  /// retry or a double tap (research R10).
  TxnId newRequestId();

  // Trips (research R12).
  Future<OpOutcome> startTrip(TxnId id, {required String tripId});
  Future<OpOutcome> recordResult(TxnId id, {required TxnId start, required TripResult result});
  Future<OpOutcome> useBooster(TxnId id, {required BoosterId booster});

  // Purchases (research R13). `variantId` is required for an item, and
  // must be null otherwise. A revive applies to the unfinished trip.
  Future<OpOutcome> buy(TxnId id, {required SkuKind kind, required String skuId, String? variantId});

  // Rewarded ads, applied after the ad's reward callback (M11).
  Future<OpOutcome> applyAdReward(TxnId id, {required AdPlacement placement});

  // Sync (M06). Tested in M05, called by M06.
  Future<List<LedgerOp>> pendingOps({int limit = 100});
  Future<void> markAccepted(Iterable<TxnId> ids);
  Future<void> markRejected(Map<TxnId, String> reasons);
  Future<void> replaceBase(EconomyState snapshot, {required int afterSeq, int? stateVersion});
}
```

- `TripResult`, `TripOutcome`: `package:trip_engine`.
- `BoosterId`, `SkuKind`: `package:content_models` (generated).
- `AdPlacement`: a domain enum with glossary §3.4's wire names.
- `LedgerOp`: a stored operation as M06 sends it (data-model.md `Op`, plus `seq` and
  `sync_status`).

## Outcomes

```dart
sealed class OpOutcome {}
final class OpApplied extends OpOutcome { final LedgerOp op; final EconomyView view; final bool repeated; }
final class OpRefused extends OpOutcome { final EconomyRefusal code; }
final class OpWriteFailed extends OpOutcome { }   // disk full or another write error (research R11)
```

The `Op` prefix keeps them apart from `trip_engine`'s own `Applied` and `Rejected`, which M02
imports next to these.

- **`OpApplied`.** The operation is stored and its effects are in `view`. `repeated` is true when
  the id was already stored; then nothing new was written (FR-016).
- **`OpRefused`.** Nothing was stored or changed (FR-019). The code tells the screen what to show.
- **`OpWriteFailed`.** Nothing changed. The screen shows a neutral retry message. M15 reports it.
- No method throws for a refusal or a write error. A programming error, such as an id that isn't
  UUIDv7, throws `ArgumentError`.

## Refusal codes

| Code | When | Typical screen reaction |
| --- | --- | --- |
| `unknown_trip` | the trip isn't in the active pack | none expected (M08 lists only pack trips) |
| `trip_unfinished` | a trip is already unfinished | M02 resumes or abandons it |
| `no_fuel` | empty tank and no window | open the fuel sheet (M12) |
| `result_exists` | the start is the latest result's start: its result is already recorded (checked first) | none (a retry with a new id after success) |
| `no_trip_start` | otherwise, the result's start isn't the unfinished one | bug report |
| `trip_mismatch` | the result's `trip_id` isn't the start's | bug report |
| `stars_out_of_bounds`, `earnings_out_of_bounds` | outside 0–3, or outside 0 to the trip's `max_earnings_jenehat`, or above 0 for a failed or abandoned trip | bug report |
| `no_trip` | a booster use, a revive or an in-trip ad with no unfinished trip | none |
| `none_left` | no booster of that kind | offer to buy it |
| `already_revived` | the trip was revived once | hide the revive |
| `cap_reached` | a second traffic-jam ad in the same trip | hide the ad option |
| `no_result`, `not_doublable`, `already_doubled` | ×2 with no result, on a failed, abandoned or unpaid trip, or twice | hide ×2 |
| `tank_full` | a refill on a full tank | hide the refill |
| `not_for_sale` | no catalog price | none expected |
| `catalog_mismatch` | the catalog prices the kind in the wrong currency, or below 0 (content error) | M15 reports it |
| `unknown_sku`, `unknown_variant` | not a known SKU, or not one of the item's variants | bug report |
| `already_owned` | an item, vehicle or chapter goal already owned | show it as owned |
| `insufficient_funds` | the balance is below the price | «ناقصك …» (ux-spec) |
| `server_only` | `morning_piggy`, which only the server grants | none (M11 polls B07) |

Codes are stable wire names (lowercase snake case), with no content or personal data (FR-019).

## The view

```dart
final class EconomyView {
  final int jenehat, bonat;
  final FuelView fuel;           // domain/fuel.dart: liters, max, nextLiterAtMs?, fullAtMs?, unlimitedUntilMs?
  final Map<BoosterId, int> inventory;
  final Map<String, TripProgress> progress;
  final UnfinishedTrip? unfinished;
  final LastResult? lastResult;
  bool owns(SkuKind kind, String skuId);
  String? variantOf(String itemId);
}
```

`fuel` is regenerated to trusted now with the current tunables each time `view` is read.

`progress` and the ownership map may name ids the active pack lacks. Readers look entries up by
the ids they get from the content source, so those entries are skipped, never read as errors
(FR-034).

## Providers (Riverpod, keep-alive)

Built in this order, which breaks the anchor's circle: creating the database needs the first
anchor, and the clock reads the stored one.

| # | Provider | Type | Notes |
| --- | --- | --- | --- |
| 1 | `uptimeSnapshotProvider` | `Future<BootSnapshot?>` | one `UptimeSource.snapshot()`, before any database |
| 2 | `appDatabaseProvider` | `Future<AppDatabase>` | opens the file (contracts/storage.md). On a first open, `onCreate` builds the first state from `Tunable.fuelMax`, and the first anchor from the snapshot and the device clock. Disposed with the scope. |
| 3 | `economyStoreProvider` | `Future<DriftEconomyStore>` | the store over the database, the only writer |
| 4 | `trustedClockProvider` | `Future<TrustedClock>` | reads the stored anchor through the store, then applies the restart check to the same snapshot (contracts/fuel-and-time.md) |
| 5 | `economyProvider` | `Future<EconomyService>` | waits for the above, and reads the tunables and the active content once, without watching them, so a switch at Home or a tunables reload keeps the same service; joins `appStartupProvider`. The service implements `Economy`, plus `refresh` and `handleLifecycle`, which `WassalApp` calls |
| 6 | `economyViewProvider` | `EconomyView` | synchronous after startup; follows `views` |

`retryAppStartup` also invalidates providers 1 to 5. Two seams sit under them: `uptimeSourceProvider`
(the `wassal/clock` channel) and `databaseOpenerProvider` (the file's connection).

## Rules for callers

- **Hold one id per intent.** Ask `newRequestId()` once when the intent starts, and reuse it until
  the outcome is `OpApplied` or `OpRefused`. After `OpWriteFailed`, a retry may reuse it.
- **M02 (trip screen):**
  - Call `startTrip` before the engine starts the trip, and start the engine only on `OpApplied`.
  - Call `recordResult` with the engine's `TripResult` when the trip ends: finished, failed with no
    revive taken, or abandoned.
  - Call `useBooster` only after the engine accepted `UseBooster`.
  - Buy a booster that's out with `buy(kind: booster)`, then `useBooster`.
  - A restart is `recordResult` (abandoned or failed), then `startTrip`.
  - At launch, if `view.unfinished` is set, rebuild that trip from its replay record, or record it
    abandoned if the record is gone.
- **M08–M10:** check unlock order, then `buy`. Read prices from the content source only for display;
  the economy reads them again when it applies.
- **M11:** call `applyAdReward` after the reward callback. The daily caps are M11's.
- **M12:** apply a purchase under 50 BONAT only after its 3-second undo window (ux-spec «الشرا»).
- **Countdowns:** compute from `view.fuel.nextLiterAtMs` and `trustedClock.nowMs()`, never from
  `DateTime.now()`.

## Test seams

- Widget tests override `uptimeSourceProvider` with a `FakeUptimeSource` and
  `databaseOpenerProvider` with `NativeDatabase.memory()` (`economyTestOverrides()` in
  `test/helpers/economy.dart`, which `pumpWassalApp` applies by default). Everything above them is
  the real code.
- Service tests use `testEconomy()`: a real `EconomyService` over SQLite in memory or on a temp
  file, with fake uptime, device clock and tunables, the sample pack, and optional rules, a first
  state, a wrapped executor or a kill-point hook.
- `economyViewProvider` can be overridden with a fixed `EconomyView` for screen tests and goldens.
- `DriftEconomyStore` takes an `onKillPoint` hook and any `QueryExecutor` (research R11).
