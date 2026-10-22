# Research: Trip Screen (M02)

Decisions for M02's plan. Each entry gives the decision, why, and what was rejected. Versions were
checked on pub.dev on 2026-10-22, and the Rive, Flame and audio findings were verified in a scratch
Flutter 3.47.7 project on Linux (Rive and Flame goldens, an arm64 debug APK). What could not be
verified on the Galaxy A06 is marked, and it becomes an owner action.

## Versions

| Package | Version | Kind | Why |
| --- | --- | --- | --- |
| `flame` | `^1.38.2` | runtime | The trip scene (constitution, locked stack). Needs Flutter ≥ 3.41. |
| `flame_rive` | `^1.11.2` | runtime | Draws a Rive artboard as a Flame component. Needs `rive ^0.14.6`, so it keeps us on 0.14 (R1). |
| `rive` | `^0.14.11` | runtime | The character runtime (R1). Brings `rive_native 0.1.11`. |
| `flame_audio` | `^2.12.2` | runtime | Sound effects through audioplayers' low-latency mode (R18). Already in mobile §2. |
| `flame_test` | `^2.3.1` | dev | Flame goldens and headless game tests ("Adapt to Flutter 3.47"). |

All five are MIT. No other dependency is added. `flutter_soloud` was rejected (R18).

## R1. The character runtime and its license (resolves mobile §24.6)

**Decision.**

- **Runtime:** `rive 0.14.11` with `rive_native 0.1.11`, drawn inside the Flame scene by
  `flame_rive 1.11.2`'s `RiveComponent`, with **`Factory.flutter`** (the Flutter-canvas renderer).
- **Why `Factory.flutter`:** `RiveComponent` renders through `Renderer.make(canvas)`, and the Rive
  Renderer's factory rejects a canvas renderer, so `Factory.rive` can't be used in Flame (flame issue
  #3619 is open, with no plan). It is also the only factory that runs in Linux `flutter test`:
  `Factory.rive` aborts the test process there. The factory is injected, so tests and the app use the
  same one.
- **States through data binding.** Rive 0.14 deprecates state-machine inputs
  (`NumberInput`/`BooleanInput`/`TriggerInput`) in favor of data binding. The character contract
  ([contracts/rive-character.md](./contracts/rive-character.md)) therefore names view-model
  properties: `mood`, `talking`, `asleep`, `headphones`, `alight`, `shirt` and `accessory`. Mobile §8's
  "state machine inputs" become view-model properties in this PR.
- **One file, many instances.** The `.riv` file is decoded once and cached in a keep-alive provider.
  Each passenger gets its own `ArtboardInstance`, `StateMachine` and `ViewModelInstance`
  (`file.artboard(name)` returns a new instance on every call), disposed with its component.
- **Pinned to 0.14.** `rive 0.15.0-dev` changes the data-binding API (`dataBind` goes away) and
  `flame_rive` excludes it. Moving to 0.15 is a later change behind the same character interface.
- **License.**
  - The runtimes (`rive`, `rive_native`, `flame_rive`) are MIT. Their notices ship through Flutter's
    license registry. There is no runtime fee, royalty or revenue share (rive.app/pricing, checked
    2026-10-22; Rive's blog, 2025-10-20: "No runtime fee. Your exports keep working forever").
  - The editor: Rive's terms (updated 2026-05-20) give the owner of a file its ownership, with no
    attribution or commercial-use restriction. Community files are CC BY 4.0 and need attribution if
    reused, so the project's file must be made, not remixed.
  - **Exporting** a `.riv` file without a splash screen needs a paid editor seat (Cadet, $9 per seat
    per month billed yearly). The free plan's export carries a Rive splash screen. Rive's docs and its
    pricing page disagree on whether the free plan exports at all, and the splash screen's runtime
    behavior couldn't be verified. **Owner action:** export the shipped file from a Cadet seat (the
    owner's own, or the artist's), and record which plan exported it.

**Why.** It is the architecture's choice (mobile §25), its runtime is MIT and free of fees, it runs in
Flame today, and it renders real pixels in headless Linux goldens.

**Rejected.**

- `Factory.rive` with `RivePanel`, which needs Rive widgets outside Flame. The passengers would leave
  the scene, and money tokens couldn't pass between them in one canvas.
- Passengers as Flutter `RiveWidget`s over the Flame scene: the scene's depth (rows overlapping each
  other and the cabin, the shake, the walk in and out) belongs in one canvas with one camera, and the
  locked stack puts the scene in Flame.
- Deprecated state-machine inputs: they still work, but 0.14 marks them for removal.
- Lottie or sprite sheets: not the locked stack, and a state machine with several inputs per character
  is what Rive is for.

**Risks.**

- No published numbers exist for 10 or more `RiveComponent`s on the Flutter canvas. Each one
  tessellates its vectors and advances its state machine every frame. The A06 measurement (SC-003)
  runs early in implementation with the real file in every seat. If it fails, the mitigations, in
  order: advance calm passengers' state machines at 30 Hz, cache static parts of the cabin into a
  picture, and simplify the character's vector count with the artist.
- `rive_native` applies the Kotlin Gradle Plugin, and Flutter 3.47.7 warns that future Flutter versions
  will refuse such plugins. It builds today; a Flutter upgrade must check it.

## R2. The native library in builds and CI

**Decision.**

- **Android builds.** `rive_native`'s Gradle task runs `dart run rive_native:setup -p android` before
  `preBuild` and downloads a 13 MB, sha512-checked zip once. With FVM, `dart` on Gradle's `PATH` may
  not be FVM's, so the quickstart runs `fvm dart run rive_native:setup --platform android` first. The
  `build-android` CI job gets `dart` from `flutter-action`.
- **Tests on Linux.** Setup doesn't run by itself for `flutter test`. CI's `app` job (and the quickstart)
  runs `dart run rive_native:setup --verbose --clean --platform linux` before `flutter test`. `--clean`
  is required: without it, a restored pub cache makes setup return early without copying the library
  into `build/rive_native/`, and every Rive test fails to load it.
- **APK size.** `librive_native.so` adds 7.7 MB per ABI. Play delivers one ABI per device from the app
  bundle, so the download grows by about 8 MB. The download budget (< 80 MB) is checked by the owner
  on the first release bundle (quickstart).

**Rejected.** Caching `build/rive_native/` across CI runs: it saves a 33 MB download but adds a cache
key to keep in step with the package version. Revisit if CI time grows.

## R3. The scene, its coordinates and Flame's role

**Decision.**

- **Flame draws; Flutter handles touch and text.** A `TripGame` (`FlameGame`) draws the cabin, the
  windows and their street, the passengers, the driver's hand and the effects (shake, glints).
  Everything the player touches (passenger hit areas, dropped money, choice answers, the dashboard)
  and every text (bubbles, «آخر كلام», labels, banners, and the amount on every money token) is a
  Flutter widget in a `Stack` over or around the `GameWidget`. This is the constitution's boundary
  (text never in the canvas), and it gives every touch target semantics, finders for tests, and a 44 pt
  hit area that doesn't depend on the drawing.
- **Money tokens are Flutter widgets moved by a `Flow`.** Each token is a small widget (its paper,
  color and amount), built once when the token appears. A `Flow` delegate repositions all of them
  every frame from `TripView` and the interpolation `alpha`, without rebuilding them, so a dozen moving
  amounts cost a transform each. Dropped notes use the same layer, with a 44 pt tap target.
- **Scene coordinates are screen points.** The `GameWidget` fills the scene rectangle, and the camera
  has no fixed resolution: one world unit is one logical point. One pure function, `SceneLayout`,
  computes every seat's rectangle, face size, token anchor, bubble anchor and the hand's rest position
  from the vehicle's seats and the scene's size. Both the Flame components and the Flutter overlays
  read it, so they line up by construction, and the minimum sizes are tested on its output in points.
  Mobile §8's "logical size 390×470, scaled to fit" is replaced: a fixed resolution letterboxes, and a
  scaled one makes every minimum size depend on the scale factor ([contracts/scene-layout.md](./contracts/scene-layout.md)).
- **Our own `Stack`, not Flame's `overlayBuilderMap`.** Both render above the game; a plain `Stack`
  keeps the overlays as ordinary Riverpod widgets, independent of the game's lifecycle.

**Rejected.** `CameraComponent.withFixedResolution` (black bars on most phones);
`WidgetComponent` (not in flame 1.38.2); Flame `TapCallbacks` on passengers (no semantics, and a hit
area tied to the drawing).

## R4. The game loop: fixed steps under a variable frame rate

**Decision.**

- `TripGame.update(dt)` hands the frame's time to the controller. The controller keeps an accumulator
  and calls `engine.step()` once per whole 33 ms, as engine-api.md asks.
- **Catch-up cap.** At most 10 steps (330 ms) per frame. Time beyond that is dropped, so a long hitch
  (a GC pause, a slow frame) slows the trip clock for that moment instead of jumping it. The outcome is
  unchanged: the engine only ever sees whole steps, and the log records the step times.
- **Interpolation.** Token positions interpolate between steps with
  `alpha = accumulator / 33 ms`, applied to `progressPermille`, so money moves smoothly at 60 fps while
  the logic runs at 30 Hz.
- **The first frame's `dt` is 0**, and Flame pauses its loop when the app is backgrounded
  (`pauseWhenBackgrounded`). The trip is paused through the lifecycle anyway (R9), so the accumulator
  is cleared on every pause.
- **Tests drive time directly.** The controller's `advance(Duration)` is what `update` calls, so tests
  advance it by exact amounts without frames (contracts/trip-controller.md).

**Rejected.** A Flutter `Ticker` separate from Flame's loop: two clocks to keep in step. Stepping at
the frame rate: the engine's step is fixed at 33 ms (constitution I).

## R5. Controller, view and cues

**Decision.**

- **`TripController`** (application layer, `features/trip/application/`) owns the one `TripEngine`, the
  trip session, the screen's phase (R9), the economy calls (R7) and the record writes (R6). It is the
  only object that calls `engine.apply`, `step`, `pause` and `resume`. Widgets call its intent methods
  (`pick`, `send`, `tap`, …) and nothing else (constitution I).
- **`TripView`** (domain, `features/trip/domain/`) is an immutable projection of `TripState` plus the
  presentation memory (bubbles, «آخر كلام», hints, warnings). A pure function builds it after each
  step or command. It carries only what the screen may show (R10).
- **`TripCue`s** are one-shot presentation effects mapped from engine events by a pure function: a
  sound, a vibration, a shake, a bubble, a log line, a banner, a highlight. The table in
  [contracts/trip-view.md](./contracts/trip-view.md) gives each key event at least two channels
  besides sound (constitution XI).
- **Rebuild scope.** The scene reads `TripView` every frame without rebuilding widgets. Flutter widgets
  watch narrow slices (the hand, the drawer, the strip, the open choices, the bubbles) through Riverpod
  `select`, so a step that only moves tokens rebuilds no widget.

**Rejected.** Exposing `TripState` to widgets (who has paid would leak, R10); a BLoC (the locked stack
is Riverpod); one big `setState` per step (30 full rebuilds a second on the A06).

## R6. The trip's record on disk

**Decision.**

- **Three drift tables in the app database**, written only by `DriftTripRecords`
  ([contracts/trip-records.md](./contracts/trip-records.md)):
  - `trip_record`: one row per trip start, keyed by the economy's start id, with the trip id, the
    content version, the canonical definition, the seed, the params and the last saved clock;
  - `trip_record_command`: the accepted commands, append-only, in order;
  - `trip_intent`: economy calls that must survive a kill (R7), keyed by their request id.
- **Append, don't rewrite.** Each accepted command inserts one row and updates the record's clock in
  one transaction. A pause updates the clock. A record is at most 1,201 command rows of under 50 bytes,
  so a write is small and constant. Writes go through drift's background isolate in order, so the UI
  thread never waits.
- **The record is written before the start.** The controller asks the economy for a request id,
  writes the record under that id, then calls `startTrip` with it, and starts the engine only when the
  start applies (M05's caller rules). A refused start deletes the record. A kill in between leaves
  either a record with a matching unfinished start (resumed at 0 ms) or a stale record (deleted at the
  next launch). So "the record is missing" can only mean a corrupt database.
- **The record goes when the result is recorded.** It is deleted after `recordResult` applies. A kill in
  between leaves a stale record, deleted at the next launch because the economy no longer reports that
  start as unfinished.
- **Schema v2.** The three tables arrive as `AppDatabase` v2 with one `upgradeSteps` entry,
  `make-migrations`' schema export and its generated tests. Columns are `INTEGER` or `TEXT` only.
- **Guards.** The database-import guard (`economy_writes_test.dart`) allows the trip store and its
  provider file. A new rule there keeps the trip tables' writes inside the trip store, the way M05 does
  for the economy's tables.

**Why.** The replay record is the checkpoint (M01 R10). Appending keeps every write the same small
size, and keying by the economy's start id ties the two stores together without a shared transaction.

**Rejected.**

- One JSON blob rewritten on every command: up to 60 KB per tap.
- A file per trip next to the database: a second storage format with its own crash semantics, and the
  constitution keeps structured local data in drift.
- Putting the record in the economy's `trip_session` row: the economy store is the only writer of its
  tables, and the record isn't economy state.

## R7. Economy calls and the order of operations

**Decision.** Each intent holds one request id until it is applied or refused (FR-008). The exact
sequences are in [contracts/trip-controller.md](./contracts/trip-controller.md). In short:

- **Start:** request id → record written → `startTrip` → engine starts on `OpApplied`.
- **Finish:** `TripFinished` → `recordResult` → record deleted → result route.
- **Leave from the pause card:** engine `Abandon` → `recordResult(abandoned)` → record deleted → Home.
- **Leave from the failure card:** `recordResult(failed)` with the engine's result at failure (no
  `Abandon`, so the result stays `failed`) → record deleted → Home.
- **Restart:** the leave sequence, then the start sequence for the same trip. Disabled when the tank
  is empty and no unlimited window runs.
- **Use a booster (engine first, as M05's caller rules say).** The controller checks what the engine
  would accept (status, the traffic-jam count), applies `UseBooster`, and writes the command row and a
  `trip_intent` row in one transaction. Then it calls `useBooster` with the intent's id, and deletes the
  intent when that applies. A kill after the write leaves the intent, which the next rebuild sends
  again with the same id, so the inventory and the engine always agree. A kill before the write loses
  both, which is also consistent.
- **Buy a booster that's out:** pause → purchase card → `buy(kind: booster)` → on `OpApplied`, the use
  sequence above. A kill between leaves the booster in the inventory, which is honest.
- **Revive (economy first, as M05's caller rules say).** The controller checks
  `state.revivable`, `state.commandsAccepted < 1,200`, the economy's `unfinished.revived` and the
  balance against the catalog price, then calls `buy(kind: revive)`, and on `OpApplied` applies
  `Revive`. On a rebuild of a failed trip, if the economy says it was revived and the engine says it
  wasn't, the controller applies `Revive` without charging again. No intent row is needed.
- **Write failures** (`OpWriteFailed`) show a neutral retry; the retry reuses the id. A record write
  that fails is retried with the next write; nothing is shown, since the trip itself continues.

**Rejected.** Economy-first booster uses: a kill would cost the player a booster with no effect, and
M05's caller rules say engine first. An intent row for revives: the economy's `revived` flag already
says whether one was paid for.

## R8. Resuming at launch (the UI side of mobile §24.4)

**Decision.**

- **Where:** `BootScreen`'s hand-off. When startup completes, it reads `economyView.unfinished`. If a
  trip is unfinished it goes to `/trip/<tripId>`, otherwise to `/home` as today. Home is skipped for
  that launch (Clarifications).
- **The trip screen decides start or resume**, wherever it is opened from: if the economy's unfinished
  trip is this trip, it resumes it; if it is another trip, it goes to that trip's route; if none, it
  starts this one. So a deep link or a stale placeholder link can never open a second trip.
- **Resuming** loads the record by the unfinished start id and calls `TripEngine.rebuild`. The trip
  comes back paused, and the pause card shows. A failed trip shows the failure card, and a finished one
  records its result and goes to the result route (FR-016). Pending booster intents are sent (R7), and a
  paid revive is applied (R7).
- **Cleanup at launch.** Records whose start isn't the unfinished one are deleted, with their commands
  and intents.
- **No record, or `RebuildRefused`.** The controller records an abandoned result so the player isn't
  blocked (FR-015). It builds that result with the engine: `TripEngine.start` with the active pack's
  definition, then `Abandon`. If the active pack no longer has the trip, it builds the abandoned result
  from `TripResult.fromJson` with zero counters and the hash of an empty log, which is exactly what the
  engine gives for an immediate abandon (a test checks the two agree).

**Rejected.** A «كمّل مشوارك» card on Home, or a question at launch (owner's answer); a router-level
redirect (it would need the economy before the router exists, and a `refreshListenable`).

## R9. The screen's phases and pausing

**Decision.** The controller's phase is one of `opening`, `noFuel`, `running`, `paused`,
`disputeOpen`, `boosterCard`, `failed`, `ending` and `ended`, with the transitions in
[data-model.md](./data-model.md). The engine runs only in `running`.

- **What pauses** (FR-012): the app leaving the foreground (`AppLifecycleListener`: `inactive`,
  `hidden` or `paused`), the pause button, the phone's back button, the dispute window, the booster
  purchase card, and the debug panel. Each pause calls `engine.pause()`, clears the accumulator and
  saves the record's clock.
- **What resumes:** only the player. Returning to the app shows the pause card; closing a card or
  answering the dispute resumes the engine.
- **The pause card** replaces M03's `TripPauseOverlay` with the full card: «كمّل المشوار»,
  «عيد المشوار» with "−١ بنزين", «ارجع الموقف», and the sound and vibration switches. It stays a
  dialog with no URL, opened by `TripBackGuard`, as M03's route contract says.
- **Immersive mode.** The trip hides the system bars (`immersiveSticky`) while it is on screen and
  restores them when it leaves, so the scene keeps its height on phones with button navigation.

## R10. Who has paid stays hidden

**Decision.**

- `TripView` has no field for a passenger's fare, balance, payment or debt. The projection reads those
  only to fill four allowed things: the ledger-peek badge («دافع» or «لسه», only while
  `state.ledgerPeekActive`), the near-stop pulse (passengers in the last `StationWarning.owed` who are
  still owed), the `always` hint's target, and the passenger's mood (impatience).
- **Impatience is allowed, and the spec now says so.** The engine's patience runs only while a passenger
  is owed, so a frown shows that they are waiting for change. The ux-spec shows it on purpose («صبره
  بيخلص»), so FR-033 lists it with the other exceptions (spec updated in this plan).
- Money tokens show their kind's color as they move (fare forward, change back), as the ux-spec says.
- **Speaker labels don't reveal hidden behavior.** «آخر كلام» names a speaker by their look (the skin's
  family, such as «الأفندي» or «الطالب»), never by archetype, so a false claimer is labelled like anyone
  dressed the same. A group payer is «الشلة», since group payment is visible.
- **Tests.** A test plays every fixture and, at every step, checks the view: no badge outside a peek, a
  pulse only for a warned passenger who is still owed, and labels that never depend on the archetype.

## R11. Choices on screen

**Decision** (Clarifications):

- A claim shows «ماشي» and «لأ، ما دفعتش!» under the passenger while the trip runs. A change request
  shows «فكّله» and «معلش» next to the passenger while the trip runs. Several can be open at once; each
  stays by its passenger, inside the scene, above the dashboard.
- A `DisputeRaised` event puts the controller in `disputeOpen`: the engine pauses at that step and a
  card asks «مين اللي دفع؟» with both faces. The answer is applied while paused, which the engine
  accepts, and the trip resumes. Two disputes from the same step are asked one after the other.
- **Rebuilds stay exact.** Every command the engine accepts while paused (`ResolveDispute`,
  `ResolveClaim`, `ResolveChangeRequest`, `UseBooster`) it also accepts while running, and a paused
  trip doesn't step, so a rebuild applies them at the same clock with the same result.
- **What the scripted-player test can reproduce.** 58 of the 60 parity fixtures can be played through
  the screen's controls. The two that can't involve a payment dispute the screen would pause on:
  `event__payment_dispute` answers it about a second after it opens (5016 → 6006 ms), and
  `solver__line_hay_02` never answers it. `sample__line_hay_02_three_stars` answers in the step that
  raises it (70026 ms), so the screen reproduces it exactly (corrected during implementation; the
  plan first counted it out). SC-002 covers the other 58, plus the dispute played the screen's way in
  a test trip.

## R12. Help: the drawer, breaks, undo and boosters

**Decision.**

- **Drawer and hand.** A tap on a slot sends `PickFromTray`, the hand sends `ReturnHand`, a tap or a
  drag from the hand to a passenger's hit area sends `SendHand`. «رجّع» shows while
  `state.undoAvailableUntilMs` is ahead of the clock and sends `UndoLastSend`.
- **«حد معاه فكة؟».** The button shows `state.breaksLeft` and enters a pick mode: the slots the engine
  would accept glow (notes of at least `trip_break_min_piasters` that are in the drawer), and a pick
  sends `RequestBreak`. A rejection (`break_limit`, `cannot_make_change`) shows its line (R22).
- **Boosters.** Each slot shows the inventory count, or the catalog BONAT price when it is 0
  (`ContentSource.price(SkuKind.booster, …)`). `traffic_jam` is disabled once
  `boosters_used` counts `booster_traffic_jam_max_per_trip` of it. The ledger peek shows badges for as
  long as the engine's peek lasts, so the tunable (10 s) wins over the ux-spec's 5 s.
- **The highlight before a throw is visual only.** The command is sent on the tap; the half-second
  highlight and the hand's throw play while the first hop starts, so they change no timing.

## R13. Speech, bubbles and «آخر كلام»

**Decision.**

- **The line.** `PassengerSpeaks{speech_key, variant}` picks
  `pool.lines[variant % pool.lines.length]` from `ContentSource.speechPool(speech_key)`, in the
  `ar-EG` text, with `{amount}` formatted by `NumberFormatter.piasters` in the player's digit style and
  `{station}` replaced by the station's name from the trip's line. A missing pool shows no bubble (M04's
  build check V-T10 makes it impossible in a shipped pack).
- **The bubble queue** (pure, in the domain) runs on the trip's clock, so a pause freezes bubbles and a
  rebuild needs nothing restored:
  - at most 2 bubbles show; the rest wait in order;
  - each shows for at least `trip_bubble_min_ms_<line_id>`;
  - a line that has waited more than twice that is dropped from the queue (it is already in
    «آخر كلام»), so a busy moment never shows a line long after it was said.
- **«آخر كلام»** keeps the last two lines as they happen: each passenger line («الشلة: خد ٥٠ عن تلاتة»),
  and the money lines the ux-spec shows («وصلك ٥٠ من الشلة») for `MoneyArrivedAtDriver`,
  `BreakCompleted` and `DroppedLost`. The table is in contracts/trip-view.md.
- **Bubble style by slot:** warning (`stop_near`, `wants_change`, `short_change`, `impatient`), fight
  (`fight`, `accused`, `dispute`), thanks (`thanks`, `tip`, `returns_excess`), plain otherwise. The three
  new bubble colors become theme tokens (R17).

## R14. Hints by line

**Decision.**

- `trip_hints_mode_<line_id>` is read when the trip starts, like the bubble minimum.
- **`always`:** on `StationWarning` with a non-empty `owed`, بلية points at the first owed passenger
  with one line, until the station is reached or that passenger is no longer owed.
- **`first_time`:** بلية explains a passenger type the first time the player meets it, then never again
  on this device. The trigger is the type's first *visible* sign, so a hint never reveals hidden
  behavior: a sleeper or headphones on boarding; the false claimer at the first `ClaimRaised` (worded
  about claims in general, never pointing at him); the honest passenger at the first `ExcessReturned`;
  the regular customer at the first tip. The full table is in contracts/trip-view.md.
- **`off`:** nothing.
- **Memory.** The types already explained are kept in the settings store under
  `pref.trip_hints_seen`, a device preference like the digit style. Hints show one at a time, for the
  bubble minimum.

## R15. Layout, screen sizes and text scale

**Decision** ([contracts/scene-layout.md](./contracts/scene-layout.md)).

- **Fixed bands.** The top bar is 110 pt and the dashboard 230 pt, overlapping the scene by 16 pt; the
  scene takes the rest. Neither band shrinks, so touch targets and text keep their sizes on every
  screen.
- **The scene's minimum.** At a scene height of 420 pt or more, `SceneLayout` guarantees every face,
  token and bubble minimum. That needs a screen at least **744 pt tall** in immersive mode (110 + 420 +
  230 − 16). Phones of 360×800 and up, including the Galaxy A06, meet it.
- **Shorter screens** (M03's 360×640 test surface): the scene shrinks below 420 pt and faces scale with
  it below their minimums, while the bands keep theirs. The spec's edge case is updated to say this,
  instead of "the whole layout scales down", which would shrink touch targets below 44 pt.
- **Text scale** is clamped to 1.3 inside the trip, the largest scale M03's goldens test.
- **Goldens and size checks** run on 390×844 (reference), 360×800 (the A06) and 360×744 (the smallest
  compliant), and M03's existing matrix (reference and 360×640, scales 1.0 and 1.3) keeps checking
  touch targets and text.

## R16. The station strip

**Decision.**

- **Slots by stop order.** The trip's stations, in order, take `ColorTokens.stations[0..3]`. Each shows
  its letter, أ ب ج د by stop order, from the ARB file (no Arabic in code), so the letter is the same
  wherever the color appears.
- **Countdown** to the next station: `nextStation.atMs − tMs`, in whole seconds rounded up, in the
  player's digits. It turns orange, grows and pulses from `trip_station_warning_ms`.
- **Prices** are each station's `fare_piasters + fare_increase_piasters`, formatted with
  `NumberFormatter.piasters`; `FareIncreased` animates the change. The student icon shows when the
  trip's `rules.student_discount_pct` is above 0.
- **The vehicle marker** moves between the depot and each station by the clock and the shifted
  `at_ms`, so traffic and the open road show on the strip as they do on the countdown.

## R17. Stand-in art, skins and tokens

**Decision.**

- **Stand-ins** (Clarifications): the cabin, the windows and their street, the seats, money, coins and
  notes, the driver's hand, the glints and بلية's head are drawn in code with theme tokens, in the
  sticker style (thick ink outlines, hard shadows). They live behind small interfaces, so final art
  replaces them without touching behavior.
- **Passengers** use the owner's one Rive character for every skin, with the skin's shirt color and
  accessory set through data binding. Until the file is committed, and in every golden, a stand-in
  passenger painter takes its place behind the same `PassengerArt` interface. The Rive file has its own
  contract test and goldens.
- **Skins** are app data, since art ships in the app: a table maps each skin (`effendi_suit`,
  `effendi_tie`, `student_cap`, `worker_blue`, `hajja_black`, `young_cap`, …) to a shirt token, an
  accessory, and the label family for «آخر كلام». An unknown skin falls back to a look by archetype
  with the neutral label «راكب».
- **New color tokens**, added to `colors.dart`, to `contracts/design-tokens.md`'s table and to
  `palette_test.dart` in the same change, as that test's header asks:
  - `fare` (the green of a fare in transit), ink text at ≥ 4.5:1, and ΔL* ≥ 18 from `primary`, the
    change color, so the two differ in lightness, not only in hue;
  - `bubbleWarn`, `bubbleFight`, `bubbleThanks`, each with its text at ≥ 4.5:1;
  - shirt colors for the skins, which need no text contrast but must differ from each other by ΔL* ≥ 18
    when they sit side by side in the stand-ins' table.

## R18. Sound and vibration

**Decision.**

- **Sound:** `flame_audio 2.12.2` over audioplayers 6.8.1, with one `AudioPool` per effect created by
  `AudioPool.create(…, playerMode: PlayerMode.lowLatency)` (Android SoundPool).
  `FlameAudio.createPool` isn't used: it doesn't pass the low-latency mode. It sits behind an
  `SfxPlayer` interface in `core/audio_haptics/`, with a no-op fake in tests (audioplayers throws
  `MissingPluginException` under `flutter test`).
- **Stand-in effects** are short mono WAV files (22.05 kHz, 16-bit, under 0.6 s each, about 300 KB in
  all) made by a script in the repo, `apps/mobile/tool/sfx/generate.py`, from sine and noise. They are
  ours, so they need no license. The list is in contracts/trip-view.md.
- **Vibration:** Flutter's `HapticFeedback.lightImpact()` and `heavyImpact()`, behind a `Haptics`
  interface. They need no permission or plugin, and they respect the phone's own touch-feedback
  setting.
- **Switches.** Sound and vibration have their own switches on the pause card, kept as
  `pref.trip_sound` and `pref.trip_haptics` (both on by default). The settings screen gets them in
  M14.

**Rejected.** `flutter_soloud 5.2.1`: its build hook compiles C++ on every `flutter build` and every
`flutter test`, and by default downloads codec libraries from an unpinned "latest" tag, which failed
the scratch test run offline. Keep it as the fallback if the A06's measured latency is too high.

## R19. Reduced motion and accessibility

**Decision.**

- Reduced motion is `MediaQuery.disableAnimationsOf(context)` (Android's «إزالة الرسوم المتحركة»), or
  `accessibilityFeatures.reduceMotion` for iOS later. When set: no shake and no bubble pop. Money still
  moves, since it carries the game.
- **Semantics.** Every control has a label from the ARB file. A passenger's hit area says their seat
  and station letter («راكب، محطة ب»), and never whether they have paid. Bubbles are live regions, so a
  screen reader reads new lines.

## R20. No ads, and the place for them

**Decision.** M02 adds no ad SDK and no ad call. `TripAdOffers` is a small interface the failure card and
the `traffic_jam` slot ask whether an ad is offered. Its default, `NoTripAdOffers`, never offers one,
so no ad button shows until M11 provides a real implementation behind `AdsGateway`. The interface's
contract says it may only be called while the engine is paused or failed, and a controller test fails
if it is called while the engine is running (constitution IX).

## R21. Playtest tools and the result placeholder

**Decision.**

- **Trip list.** On dev and staging (`flavorProvider`), Home's placeholder gets a list of every trip in
  the active pack, by line, through `PlaceholderScreen`'s `extra`. Each opens the trip route. Prod
  doesn't build it.
- **Debug panel.** On dev and staging, a small icon in the top bar opens a panel that pauses the trip and
  shows the trip id, revision, seed, the engine's clock and status, reputation, counters, and a button
  that copies the replay record JSON to the clipboard.
- **Result placeholder.** The trip passes its `TripResult` to the result route as go_router's `extra`.
  The placeholder shows the outcome, the stars with their three conditions and the pay. Without an
  `extra` (the route opened another way), it shows the economy's `lastResult`. M08 replaces it.

## R22. Player text

**Decision.**

- Every new string goes in `app_ar.arb`, about 90 keys, grouped by prefix: `trip*` (top bar, strip,
  dashboard, choices, cards), `tripRejection*` (one per engine rejection code that needs a line),
  `tripRefusal*` (the economy codes the trip can meet), `tripHint*`, `tripLook*` (speaker labels),
  `tripCause*` (failure causes, with ICU plurals) and `tripStationLetter1..4`.
- Numbers reach the strings already formatted (M03's placeholder rule); counts only select a plural.
- **Rejections the player should understand** get a short line in «آخر كلام»'s place for a moment:
  `cannot_make_change`, `break_limit`, `booster_limit`, `command_limit`. The others (`tray_empty`,
  `hand_empty`, `no_effect`, `not_aboard`, `wrong_status`, …) give only the control's own feedback (a
  short shake of the slot), since the screen already shows why.

## R23. Tunables and the two `LineId`s

**Decision.**

- **No new tunable.** M02 reads the existing per-line keys (`trip_bubble_min_ms_<line_id>`,
  `trip_hints_mode_<line_id>`) and builds `TripParams` from a flat map of every registered tunable read
  through `ConfigSource`, so dev overrides apply. Presentation values (the half-second highlight, the
  meter's orange below 40%, animation lengths, the 2-line log, the catch-up cap) change no outcome and
  live as named constants in `features/trip/presentation/trip_motion.dart`.
- **The two `LineId` enums.** `content_models`' `LineId` (used by content and `TripParams`) and the
  glossary's (used by `Tunable`'s per-line helpers) have the same value names. M02 converts between them
  by name in one helper, imports the glossary with a prefix where both are needed, and a test keeps the
  names equal. Retiring the glossary enums is left to the feature that next touches them.

## R24. Testing

**Decision** (FR-053 to FR-055, constitution XIII).

| Level | What | Where |
| --- | --- | --- |
| Domain unit | projection, who-paid rule, bubble queue, log, hints, station strip, failure summary, scene layout and its minimum sizes, skin table, cue mapping | `test/features/trip/domain/` |
| Controller | every phase transition; every economy sequence with `OpApplied`, `OpRefused`, `OpWriteFailed`; the outbox; resume, cleanup, missing record; no ad call while running | `test/features/trip/application/` with M05's in-memory economy |
| Records | append, rebuild, kill points, cleanup, v1 → v2 upgrade | `test/features/trip/data/`, `test/drift/` |
| Scripted player | the 58 reproducible parity fixtures played through the widgets with exact time, each matching its `expected_result`; plus a dispute trip played the screen's way | `test/features/trip/scripted_player_test.dart` |
| Kill and rebuild | 50 random kill points across the sample trips on a real database file | `test/features/trip/kill_rebuild_test.dart` |
| Widgets and goldens | the FR-054 list, RTL, both digit styles, on the three trip surfaces, with stand-in art; plus the Rive character's states with `Factory.flutter` | `test/goldens/trip/`, `test/features/trip/presentation/` |
| Minimum sizes | measured on `SceneLayout`'s output and on the rendered goldens | `test/a11y/trip_minimum_sizes_test.dart` |
| Integration (device) | a sample trip offline from start to finish; a relaunch mid-trip; the A06 frame and memory run | `integration_test/trip_*` |
| Guards | `features/trip/domain` imports; trip-table writes; no ad import in `features/trip/`; no Arabic, raw colors or float money (existing guards, now covering `features/trip/`) | `test/repo/` |

Coverage stays at ≥ 80% for the app. The Flame components are covered by `flame_test` goldens and the
controller tests.

## R25. Performance

**Decision.**

- Budgets: 60 fps target, never below 45 fps, under 300 MB during a trip, on the A06 (SC-003, SC-004).
- **How:** the scene draws from `TripView` without widget rebuilds (R5); one decoded Rive file; static
  cabin layers drawn once into a cached picture; tokens and bubbles are few (at most a dozen tokens and
  2 bubbles).
- **Measuring.** `integration_test/trip_perf_test.dart` plays the busiest sample trip (`line_gamaa.02`,
  old microbus) with the real character in every seat under `watchPerformance`, and writes the frame
  summary. The owner runs it on the A06 with `tool/perf/trip_fps.sh` (quickstart). Frame build and
  raster times are read against 16.7 ms (60 fps) and 22.2 ms (45 fps).
- **Order of work.** The A06 run comes right after the scene draws real passengers, before the
  remaining stories, so a Rive problem shows up while there is time to apply R1's mitigations.

## Documents updated in this PR

- **docs/architecture-mobile.md:** §8 (scene coordinates in points, Flame draws while Flutter handles
  touch and text, view-model properties instead of state-machine inputs, `Factory.flutter`); §10
  (`TripController`, the trip record tables and the intent outbox); §24.6 resolved (R1), §24.4's UI side
  (R8); §2's dependency list (`flame_rive`, `flame_test`).
- **docs/delivery-plan.md:** M05 merged in #8; M02's progress entry at merge.
- **specs/001-m03-app-shell/contracts/design-tokens.md:** the new tokens (R17).
- **CLAUDE.md:** the `rive_native` setup commands, the stand-in sound script, the trip perf tool, and
  the Rive file's place.
- **docs/owner-actions.md:** M02's section, at `/speckit-implement`.
- **The spec** (in this plan): FR-033 lists impatience; the short-screen edge case, FR-017 and SC-002
  follow R15 and R11; FR-020 names the letters.

## Handed to later features

- **M07:** reuse the hint bubble and pointer for the tutorial; the tutorial's dimming and the gift refill
  are yours.
- **M08:** the result screen replaces R21's placeholder and reads the `TripResult` from the route's
  `extra` (or the economy's `lastResult`); the pre-trip card's «اطلع» opens the trip route, which charges
  the liter; Home replaces the playtest list.
- **M11:** implement `TripAdOffers` for `traffic_jam` and `trip_revive` with `AdsGateway`, calling it
  only while the trip is paused or failed; after a revive ad, apply `Revive` the way R7 does after a BONAT
  revive.
- **M14:** the sound and vibration switches on the settings screen (`pref.trip_sound`,
  `pref.trip_haptics`).
- **M15:** report `trip_start`, `trip_end` and `change_given` from the controller's events, and the
  economy and engine refusal codes.
- **Story content (M10 or the content pipeline):** the story character's comments need a speech slot and
  a character, in the engine's capabilities and the schemas.
- **The art pass:** final characters (one per skin family), the cabin and the sound set, behind the same
  interfaces and the Rive contract.
