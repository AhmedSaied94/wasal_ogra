# Contract: The Trip Controller

The application layer of the trip screen: `lib/features/trip/application/`. It owns the engine, the
session, the phase, the economy calls and the record writes. Widgets and the Flame scene talk only to
it. Types are in [data-model.md](../data-model.md); the engine's API is M01's
[engine-api.md](../../004-m01-trip-engine/contracts/engine-api.md); the economy's is M05's
[economy-api.md](../../007-m05-local-economy/contracts/economy-api.md).

## Interface

```dart
final class TripController {
  // State, for widgets (select slices) and the scene (read every frame).
  TripPhase get phase;
  TripView get view;
  Stream<TripCue> get cues;                 // one-shot effects, in order
  double get alpha;                         // accumulator / 33 ms, for interpolation

  // Opening and time.
  Future<void> open(String tripId);         // start or resume (see "Opening")
  void advance(Duration frameTime);         // called by TripGame.update; steps the engine in 33 ms steps

  // Player intents. Each one is ignored outside the phases listed.
  void pick(int denomination);              // running
  void returnHand();                        // running
  void send(String passengerId);            // running (tap or drag)
  void undo();                              // running
  void tap(String passengerId);             // running
  void answerClaim(String passengerId, {required bool insist});        // running
  void answerChangeRequest(String passengerId, {required bool agree}); // running
  void answerDispute(String paidPassengerId);                          // disputeOpen
  void startBreak(); void pickBreak(int denomination); void cancelBreak(); // running
  void collect(int tokenId);                // running
  Future<void> useBooster(BoosterId booster);       // running; opens the card when none is left
  Future<void> buyBooster();                        // boosterCard
  void closeBoosterCard();                          // boosterCard
  Future<void> revive();                            // failed
  void pause(PauseReason reason);                   // running
  void resume();                                    // paused
  Future<void> leave();                             // paused, failed: «ارجع الموقف»
  Future<void> restart();                           // paused, failed: «عيد المشوار»
  Future<void> retry();                             // opening, ending, failed (revive) or boosterCard, after OpWriteFailed

  // Internal builds' debug panel (research R21): read-only.
  ({TripState state, ReplayRecord record})? get debugSnapshot;
}

enum PauseReason { button, back, lifecycle, debugPanel }
```

- Commands are applied synchronously at the current clock. A `Rejected` outcome changes nothing and
  produces at most a `FeedbackCue` ([trip-view.md](./trip-view.md), "Rejections").
- Every accepted command appends its record row before the next command is applied (writes are queued
  in order; the engine never waits for disk).
- `advance` does nothing outside `running`. It adds the frame time to the accumulator (capped at 10
  steps, 330 ms), steps the engine once per 33 ms, folds the events into the presentation memory,
  rebuilds the view and emits the cues. Pausing clears the accumulator.

## Providers

| Provider | Type | Lifetime | Notes |
| --- | --- | --- | --- |
| `tripControllerProvider(tripId)` | `TripController` | auto-dispose, one per trip route | Builds the controller and calls `open`. Disposed when the trip route leaves. The route keys `TripScreen` by `tripId`, so another trip in the same page is another screen and controller. |
| `tripRecordsProvider` | `TripRecords` | keep-alive | `DriftTripRecords` over the app database (only `trip_providers.dart` may build it). |
| `passengerArtProvider` | `PassengerArtFactory` | keep-alive | Rive when `assets/rive/passenger.riv` loads, else the stand-in; tests override it with the stand-in. |
| `sfxPlayerProvider`, `hapticsProvider` | `SfxPlayer`, `Haptics` | keep-alive | `core/audio_haptics/`; no-op fakes in tests. |
| `tripSettingsProvider` | `TripSettings` | keep-alive | Sound, vibration and hints memory from the settings store. |
| `tripAdOffersProvider` | `TripAdOffers` | keep-alive | `NoTripAdOffers` until M11. |

## Opening

`open(tripId)`:

1. Read `economy.view.unfinished`.
2. **Another trip is unfinished** → the phase becomes `ended` with a redirect to that trip's route.
3. **This trip is unfinished** → resume:
   1. Load the record for `unfinished.startTxn`.
   2. If it exists, `TripEngine.rebuild(record)`. On `RebuildRefused`, or if there is no record, go to
      "Ending without a record".
   3. Send each pending `trip_intent` of the record (`useBooster` with its stored id), deleting each
      one when it applies.
   4. If the engine is `failed`, `unfinished.revived` is true and `state.revived` is false, apply
      `Revive` (already paid) and save the command.
   5. Phase: `paused` with the pause card (a running trip comes back paused), `failed` with the
      failure card, or `ending` for a finished trip. Disputes still open in the rebuilt state are
      queued, and «كمّل المشوار» asks them (phase `disputeOpen`) before the engine resumes.
4. **Nothing is unfinished** → start:
   1. Read the trip from the active pack (`ContentSource.trip`). Missing → `ended` to Home.
   2. Build `TripParams.fromTunables(flatTunables, lineId)`, read `trip_bubble_min_ms_<line_id>` and
      `trip_hints_mode_<line_id>`.
   3. `id = economy.newRequestId()`. Write the record under `id` with `t_ms = 0`.
   4. `economy.startTrip(id, tripId: tripId)`:
      - `OpApplied` → `TripEngine.start(definition, params)`, phase `running`;
      - `OpRefused(no_fuel)` → delete the record, phase `noFuel` (with the next liter's time);
      - `OpRefused(trip_unfinished)` → delete the record, go to step 1 (a race with another open);
        a second race in a row ends to Home, and one after a start retry opens from step 1;
      - `OpRefused(unknown_trip)` → delete the record, `ended` to Home;
      - `OpWriteFailed` → keep the record; the phase stays `opening` with a neutral retry message,
        and `retry()` calls `startTrip` again with the same id.

### Ending without a record

When the economy reports an unfinished trip but its record is missing or refused:

- Build an abandoned `TripResult`: `TripEngine.start` with the active pack's definition of
  `unfinished.tripId`, then `Abandon`. If the pack no longer has the trip, `TripResult.fromJson` with
  outcome `abandoned`, zero counters, `duration_ms` 0 and the hash of the log `[[0, "Abandon"]]`, which
  is what the engine's abandoned result hashes. A test checks both give the same JSON.
- `recordResult(newRequestId(), start: unfinished.startTxn, result)`, then delete any record, then
  `ended` to Home.

## Sequences

Each intent holds one request id until `OpApplied` or `OpRefused`; `OpWriteFailed` keeps the id for a
retry.

### Finish

1. `TripFinished{result}` from a step → phase `ending`.
2. Charge every booster use not charged yet (see Booster use): the economy takes no `useBooster`
   after the result. If one still gets `OpWriteFailed`, nothing is recorded: the retry message
   shows, and `retry()` starts again from this step.
3. `recordResult(id, start: startTxn, result)`.
4. On `OpApplied` (or `OpRefused(result_exists)`, which means a previous attempt applied): delete the
   record, phase `ended` → `pushReplacement('/trip/<tripId>/result', extra: result)`.

### Leave («ارجع الموقف»)

- From `paused`: apply `Abandon` (accepted in any status but finished), save it, then as Finish with the
  `TripAbandoned` result, and go to `/home`.
- From `failed`: no `Abandon`; record `engine.result` (outcome `failed`), delete the record, go to
  `/home`.

### Restart («عيد المشوار»)

- Enabled only when `economy.view.fuel.liters > 0` or an unlimited window runs at trusted now.
- The Leave sequence without navigating, then Opening (from step 1) for the same trip.

### Booster use

1. `useBooster(b)` with none left → pause, phase `boosterCard` (see Purchase). What is left is
   `inventory[b]` less this trip's uses of `b` not charged yet (in flight, or whose charge failed
   to write), and the slot shows that count: a second tap before the first use is charged never
   gets a use the economy will refuse.
2. Check what the engine would accept: status `running` or `paused`, and for `traffic_jam`,
   `boostersUsed` count of it below `booster_traffic_jam_max_per_trip`. Otherwise return.
3. `id = newRequestId()`. Apply `UseBooster(b)` → `Accepted`.
4. In one transaction: append the command row and insert `trip_intent{id, use_booster, b}`.
5. Once that transaction is done, `economy.useBooster(id, booster: b)`. On `OpApplied` or `OpRefused`,
   delete the intent (a refusal is reported to M15 later; the engine's use stands). On
   `OpWriteFailed`, keep it; the next booster use, the result (Finish step 2) or the next rebuild
   sends it again, one charge in flight per id.

### Booster purchase

1. Phase `boosterCard`: the card reads the catalog price
   (`ContentSource.price(SkuKind.booster, wire(b))`) and `economy.view.bonat`.
2. `buyBooster()`: `economy.buy(id, kind: booster, skuId: wire(b))`.
   - `OpApplied` → close the card, resume, then the Booster use sequence. A second tap's answer to
     the same purchase id finds the card closed and does nothing.
   - `OpRefused(insufficient_funds)` → the card shows the missing amount; nothing else is offered.
   - `OpRefused(not_for_sale)` → the slot is disabled for this trip.
   - `OpWriteFailed` → the card stays with a neutral retry message; the next tap calls `buy` again
     with the same id, so the economy charges at most once.
3. `closeBoosterCard()` resumes without buying.

### Revive

1. Offered when `state.revivable`, `state.commandsAccepted < 1200`, `!unfinished.revived`, and the
   catalog has a revive price. Shown as unaffordable when `view.bonat` is below it.
2. `economy.buy(id, kind: revive, skuId: 'revive')`.
3. `OpApplied` → apply `Revive` → `Accepted`, save the command, phase `running`.
   `OpRefused(already_revived)` → apply `Revive` if the engine still allows it (a previous attempt was
   paid), else hide the offer. `OpWriteFailed` → nothing is applied; the card stays with a neutral
   retry message, and the next tap calls `buy` again with the same id.

### Pausing and lifecycle

- The trip screen holds an `AppLifecycleListener`. `inactive`, `hidden` and `paused` call
  `pause(PauseReason.lifecycle)`. Coming back shows the pause card; nothing resumes by itself.
- Every pause saves the record's `t_ms`, so a trip killed after leaving the foreground rebuilds at
  that exact moment. A kill with no pause first (a crash, or a force-stop in the foreground)
  rebuilds at the last accepted command's `t_ms` (FR-006, SC-006).
- `TripBackGuard` (M03) calls `pause(PauseReason.back)` and shows the pause card.
- While the trip route is on screen the system bars are hidden (`immersiveSticky`), and restored when
  it leaves.

### Disputes

- A step that emits `DisputeRaised` ends in phase `disputeOpen`: the engine is paused right after that
  step, and the disputes it raised are queued in event order.
- `answerDispute(paid)` applies `ResolveDispute(id, paid)` while paused and saves it. If more are
  queued, the next is asked; otherwise the engine resumes (or the phase becomes `failed` if the answer
  failed the trip).

## Launch

`BootScreen`'s hand-off, after `appStartupProvider` completes:

```dart
final unfinished = ref.read(economyViewProvider).unfinished;
context.go(unfinished == null ? '/home' : '/trip/${unfinished.tripId}');
```

Before it, the launch deletes stale records (`TripRecords.deleteAllExcept(unfinished?.startTxn)`).

## Ads (M11)

```dart
abstract interface class TripAdOffers {
  /// Whether an ad can be offered now for [placement] (`traffic_jam`, `trip_revive`).
  /// Must only be called while the engine is paused or failed.
  bool isOffered(AdPlacement placement);

  /// Shows the ad. Returns true when its reward was earned. Same precondition.
  Future<bool> show(AdPlacement placement);
}
```

`NoTripAdOffers.isOffered` is always false. A controller test wraps it in a spy that fails the test if
either method is called while `engine.status == running` (constitution IX).

## Test seams

- `advance` is the only clock; tests call it with exact durations.
- `TripRecords`, `Economy`, `ContentSource`, `ConfigSource`, `PassengerArtFactory`, `SfxPlayer`,
  `Haptics`, `TripSettings` and `TripAdOffers` are injected through providers.
- `TripController.forDefinition(definition, params, seed)` (test-only constructor) opens a trip from a
  fixture's definition with a fake economy, for the scripted player.
- A kill hook lets tests stop after any write step. `TripKillPoint` is an enum in
  `lib/features/trip/data/trip_kill_point.dart`, so the store and the controller can share it.
  Both take an optional `void Function(TripKillPoint)? onKillPoint`, as M05's `EconomyKillPoint`
  does. The store's points fall between its writes. The controller's fall between an economy call
  and the engine command that follows it (the revive), and between the booster's transaction and
  `useBooster`.
