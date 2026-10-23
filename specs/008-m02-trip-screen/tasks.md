---

description: "Task list for M02 Trip Screen"
---

# Tasks: Trip Screen (M02)

**Input**: Design documents from `specs/008-m02-trip-screen/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**:

- **Mandatory, and first.** Constitution XIII requires tests. Every phase writes its tests first, and
  they must fail before its implementation tasks start. Tests come first in particular for the
  projection (who has paid), the record store and its rebuild, and every economy sequence.
- **Real engine, real database.** Controller and store tests use the real `TripEngine`, a real drift
  database (`NativeDatabase.memory()`, or a temp file when a test reopens it) and M05's in-memory
  `EconomyService` (`test/helpers/economy.dart`'s `testEconomy`). Only the platform edges are faked:
  sound, vibration, the passenger art (the stand-in), the ad seam, and the frame clock (tests call
  `TripController.advance` with exact durations).
- **Coverage.** At least 80% of lines in `apps/mobile` (`tool/check_coverage.dart --min 80`).

**Organization**:

- **Paths** are from the repository root. Dart commands run with `fvm` in `apps/mobile/`.
- **Codegen.** After adding or changing a `@riverpod` provider or a drift table, run
  `fvm dart run build_runner build -d` in `apps/mobile`. After changing a table, also run
  `fvm dart run drift_dev make-migrations`. Before any Rive test, run
  `fvm dart run rive_native:setup --verbose --clean --platform linux`.
- **Exactness.** Every number in a task comes from the contracts (the 33 ms step, the 10-step cap, the
  744 pt screen, the minimum sizes, the 1,200-command cap, the 58 fixtures). Name each one as a
  constant in `lib/`, never a bare literal; presentation constants go in
  `lib/features/trip/presentation/trip_motion.dart`. Wire names are spelled exactly as the contracts
  give them.
- **Text.** Every player-visible string is an ARB key in `apps/mobile/lib/l10n/app_ar.arb`, written
  in colloquial Egyptian Arabic, with an `@key` description in English. No Arabic in `lib/` code.
  Numbers reach strings already formatted; a count may only select a plural.
- **Shared files** grow story by story, so tasks that touch them are sequential across stories:
  - `lib/features/trip/application/trip_controller.dart`;
  - `lib/features/trip/domain/projection.dart` and `cues.dart`;
  - `lib/features/trip/presentation/trip_screen.dart`;
  - `apps/mobile/lib/l10n/app_ar.arb`.
- **One PR.** This feature merges as one PR.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story the task belongs to (US1–US7 from spec.md)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Dependencies, the native Rive library, the stand-in sounds (research R1, R2, R18).

- [X] T001 Update `apps/mobile/pubspec.yaml` (plan "Primary Dependencies"):
  - dependencies `flame: ^1.38.2`, `flame_rive: ^1.11.2`, `rive: ^0.14.11`, `flame_audio: ^2.12.2`;
  - dev dependency `flame_test: ^2.3.1`;
  - assets `assets/rive/` and `assets/audio/sfx/` (all flavors);
  - no `flutter_soloud`.

  Run `fvm flutter pub get`, then `fvm dart run rive_native:setup --verbose --clean --platform linux`
  and `fvm dart run rive_native:setup --platform android`, then `fvm flutter build apk --flavor dev
  --debug` once to confirm the Android libraries download. Commit `pubspec.lock`.
- [X] T002 [P] Update `.github/workflows/mobile.yml` (contracts/ci-checks.md "Workflow changes"):
  - in the `app` job, after `flutter pub get` and before `flutter test`, add a step
    `dart run rive_native:setup --verbose --clean --platform linux` with `working-directory:
    apps/mobile`;
  - add the same step to the `update-goldens` job before `flutter test --update-goldens`;
  - in the `app` job, add a step `python3 tool/sfx/generate.py && git diff --exit-code
    assets/audio/sfx` in `apps/mobile`.
- [X] T003 [P] Create `apps/mobile/tool/sfx/generate.py` (research R18, contracts/trip-view.md
  "Stand-in effects"): Python 3 standard library only (`wave`, `math`, `struct`, `random` with a fixed
  seed). It writes `apps/mobile/assets/audio/sfx/{coin,note_pass,call,horn,fight,thanks,wrong,bump,alert}.wav`,
  each mono, 22,050 Hz, 16-bit, at most 0.6 s, from sines and noise with short fades:
  - `coin`: two bright pings (2,600 Hz then 3,400 Hz, 80 ms each);
  - `note_pass`: 120 ms of filtered noise, a paper rustle;
  - `call`: two rising tones (660 Hz → 880 Hz, 150 ms each);
  - `horn`: 400 ms of 340 Hz + 420 Hz square-ish tone;
  - `fight`: 350 ms of low buzz (110 Hz with noise);
  - `thanks`: a soft rising chime (880 Hz → 1,320 Hz, 300 ms);
  - `wrong`: 250 ms falling tone (440 Hz → 220 Hz);
  - `bump`: 200 ms low thud (60 Hz decaying with noise);
  - `alert`: three short 1,000 Hz beeps (60 ms each, 60 ms apart).

  Running it twice gives byte-identical files. Run it and commit the WAV files (about 300 KB in all).
  Add `apps/mobile/assets/audio/sfx/README.md` in English: the files are generated stand-ins, owned by
  the project, regenerated only by the script.
- [X] T004 [P] Create `apps/mobile/assets/rive/README.md` in English: `passenger.riv` is the owner's
  character file; it must match `specs/008-m02-trip-screen/contracts/rive-character.md`; it is exported
  from a paid Rive plan (Cadet or above); nothing else goes in this folder.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: What every story uses: the guards, the tokens, the trip tables and their store, the view
types, the layout, the skins, the station strip, sound and vibration, the trip settings, and the test
helpers.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Test helpers

- [X] T005 Create `apps/mobile/test/helpers/trip.dart`:
  - `FakeSfxPlayer implements SfxPlayer` recording every `play(Sfx)` in order;
  - `FakeHaptics implements Haptics` recording `light` and `heavy`;
  - `MemoryTripSettings` (sound, vibration, hints seen) over `MemorySettingsStore`;
  - `SpyTripAdOffers implements TripAdOffers` that never offers and records calls, with a
    `engineStatus` callback so a test can assert no call happened while the engine was `running`;
  - `loadFixture(String name)` reading `fixtures/parity/<name>.json` into `ParityFixture`, and
    `allFixtureNames()` listing the 60 files (excluding `README.md`);
  - `tripTestOverrides({Economy? economy, ContentSource? content, …})`: the stand-in passenger art,
    the fakes above, `NoTripAdOffers`, and an in-memory `TripRecords` over the test database;
  - `pumpTrip(WidgetTester tester, {required String tripId, Surface surface, DigitStyle digits,
    double textScale = 1.0, …})` that pumps `WassalApp` at `/trip/<tripId>` with the overrides,
    and `controllerOf(tester)`.

  Add `apps/mobile/test/helpers/surfaces.dart` entries for the trip surfaces as a separate
  `enum TripSurface { reference(390, 844), a06(360, 800), compact(360, 744) }` with the same
  `applySurface` semantics (DPR 1), leaving M03's `Surface` enum unchanged.

### Guards: tests first

- [X] T006 [P] Extend `apps/mobile/test/repo/domain_imports_test.dart` (contracts/trip-records.md
  "Guards"): add `lib/features/trip/domain` with allowed imports `dart:core`, `dart:collection`,
  `dart:math`, `package:content_models/`, `package:trip_engine/`,
  `package:wassal/core/content/domain/` and `package:wassal/features/trip/domain/`, plus same-folder
  relative files. Self-tests: `package:flutter/widgets.dart`, `package:flame/game.dart` and
  `package:drift/drift.dart` fail there. Fails until T020 creates the folder.
- [X] T007 [P] Extend `apps/mobile/test/repo/economy_writes_test.dart` (contracts/trip-records.md
  "Guards"):
  - `lib/features/trip/data/drift_trip_records.dart` and `lib/features/trip/trip_providers.dart` may
    import `app_database.dart`;
  - a new rule: outside `lib/core/storage/` and `drift_trip_records.dart`, no file writes
    `tripRecord`, `tripRecordCommand` or `tripIntent` (`into(`, `update(`, `delete(`, `batch(`,
    `custom*(`);
  - `drift_trip_records.dart` never writes an economy table;
  - self-tests on small source strings. Fails until T022 exists.
- [X] T008 [P] Create `apps/mobile/test/repo/no_ads_in_trip_test.dart`: no file under
  `lib/features/trip/` imports `package:google_mobile_ads/` or `package:wassal/core/ads/`
  (constitution IX, research R20). Self-test with a source string.
- [X] T009 [P] Create `apps/mobile/test/repo/trip_text_in_canvas_test.dart`: no file under
  `lib/features/trip/presentation/scene/` contains `TextPainter`, `TextComponent`,
  `TextBoxComponent` or `TextSpan` outside comments (contracts/ci-checks.md). Self-tests.
- [X] T010 [P] Create `apps/mobile/test/core/glossary/line_id_names_test.dart`: the glossary's
  `LineId.values` names equal `content_models`' `LineId.values` names, in the same order, and
  `toGlossaryLine`/`toContentLine` (T019) round-trip every value (research R23).
- [X] T011 [P] Extend `apps/mobile/test/core/theme/palette_test.dart` (research R17,
  contracts/ci-checks.md): exact values, opacity and these checks for the new tokens:
  - `fare`: `hibr` text on it ≥ 4.5:1; ΔL* ≥ 18 from `primary`;
  - `bubbleWarn`, `bubbleFight`, `bubbleThanks`: `hibr` text on each ≥ 4.5:1; `bubbleWarn` and
    `bubbleFight` differ by ΔL* ≥ 18;
  - the shirt tokens: ΔL* ≥ 18 between shirts that the skin table seats side by side (the test reads
    `shirtPairsToSeparate` from `skin_looks.dart`).

### Domain and storage: tests first

- [X] T012 [P] Write `apps/mobile/test/features/trip/domain/scene_layout_test.dart`
  (contracts/scene-layout.md):
  - for `tuktuk` and `micro_old` seat lists (from `content/examples/sample/vehicles/*.json`) at scene
    sizes 390×520, 360×456 and 360×420: near-row faces (`A`, `front`) ≥ 80 pt wide, back-row faces
    (`B`, `C`) ≥ 50 pt, every hit rect ≥ 44×44 and pairwise non-overlapping, every face and bubble
    anchor inside the scene;
  - the front seat's hit rect wins over `A_r`'s, and `A_r` keeps ≥ 44×44 of its own;
  - columns run `r`, `m`, `l` from the viewer's right;
  - at 360×316 (the 360×640 screen) faces shrink below their minimums while hit rects stay ≥ 44×44;
  - `bandHeights(screen)` gives top 110 (+ top inset), dashboard 230, overlap 16, and the scene the
    rest; a 744 pt screen gives a 420 pt scene.
- [X] T013 [P] Write `apps/mobile/test/features/trip/domain/skin_looks_test.dart`:
  - every `skin` in `content/examples/sample/trips/**` and in `content/source/**` (when present) has
    a `SkinLook`;
  - an unknown skin falls back by archetype with `labelKey == 'tripLookPassenger'`;
  - no `labelKey` is derived from an archetype for a known skin (a table check), and
    `accessory` values are exactly `none, cap, glasses, headphones, tie, scarf, headscarf`
    (contracts/rive-character.md).
- [X] T014 [P] Write `apps/mobile/test/features/trip/domain/station_strip_test.dart`
  (contracts/trip-view.md "The projection", research R16):
  - slots 0–3 by station order, letters by slot;
  - each price is `fare_piasters + fareIncreasePiasters`;
  - `reached` below `nextStation`, `next` at it;
  - `countdownMs = nextStation.atMs − tMs`, null after the last; `warning` at
    `≤ trip_station_warning_ms`;
  - `vehiclePermille` from the previous and next `at_ms`, following `ScheduleShifted`;
  - `studentIcon` when `rules.student_discount_pct > 0`.
- [X] T015 [P] Write `apps/mobile/test/features/trip/domain/projection_test.dart` for the core
  projection (data-model.md "The view"), using `TripEngine.start` on sample trips:
  - top bar: trip number from `trip_id`, line name or null, `reputationLow` below 40;
  - tokens: kind `fare` for fare tokens and `change` for every other kind; `blocked`, `dropped`,
    `progressPermille`;
  - hand, tray, `breakButton`, `undoUntilMs` from the engine's helpers;
  - presence `boarding` and `leaving` for the length of their animation after `PassengerBoarded` and
    `PassengerAlighted`;
  - `TripView`'s field list contains no fare, payment, balance or debt (a reflection-free check: the
    test lists the fields of every view type and compares with data-model.md's table).
- [X] T016 [P] Write `apps/mobile/test/features/trip/data/trip_records_test.dart`
  (contracts/trip-records.md "Tests"): create → appendCommand ×N → load gives the commands in `seq`
  order and the last `t_ms`; `saveClock`; `appendBoosterUse` writes the command and the intent in one
  transaction (a kill hook between them leaves neither); `deleteIntent`; `delete` removes the record,
  its commands and intents; `deleteAllExcept(keep)` and `deleteAllExcept(null)`;
  `StoredTrip.toReplayRecord()` rebuilds to the same `TripState.toJson()` as the live engine at the
  saved clock for `line_hay.02`; writes run in order even when issued without awaiting.
- [X] T017 [P] Update `apps/mobile/test/core/storage/app_database_test.dart`: the database creates
  exactly 11 tables (the 8 economy tables plus `trip_record`, `trip_record_command`, `trip_intent`);
  every column is `INTEGER` or `TEXT`. Add `apps/mobile/test/core/storage/trip_tables_upgrade_test.dart`:
  a v1 file with economy rows (seeded with `seedOps`) opens as v2 with every economy row unchanged and
  the three trip tables empty.

### Implementation

- [X] T018 Add the tokens (research R17) to `apps/mobile/lib/core/theme/tokens/colors.dart` and
  `WassalTokens` in `apps/mobile/lib/core/theme/app_theme.dart`: `fare`, `bubbleWarn`, `bubbleFight`,
  `bubbleThanks`, and the shirt colors as `ColorTokens.shirts` (one per skin family). Pick values that
  pass T011. Update `specs/001-m03-app-shell/contracts/design-tokens.md`'s table with each value, its
  L* and its use.
- [X] T019 [P] Create `apps/mobile/lib/core/config/tunable_snapshot.dart`:
  `Map<String, Object?> tunableSnapshot(ConfigSource config)` returning
  `{for (final t in Tunable.all) t.key: config.read(t)}` (enum values as their wire strings). Create
  `apps/mobile/lib/features/trip/domain/line_ids.dart` with `toGlossaryLine(LineId)` and
  `toContentLine(glossary.LineId)` by value name (research R23), importing the glossary with a prefix.
- [X] T020 Create the view types in `apps/mobile/lib/features/trip/domain/trip_view.dart`, exactly the
  table of data-model.md "The view" (`TripView`, `TopBarView`, `StationStripView`, `StationChip`,
  `PassengerView`, `TokenView`, `DroppedMoneyView`, `HandView`, `TraySlotView`, `BreakButtonView`,
  `BoosterSlotView`, `ChoiceView` and its three subclasses, `BubbleView`, `LogLine`, `HintView`,
  `BannerView`, `FailSummary`), immutable with `==`. Create
  `apps/mobile/lib/features/trip/domain/skin_looks.dart` (`SkinLook`, the skin table, the archetype
  fallbacks, `shirtPairsToSeparate`), `station_strip.dart`, `scene_layout.dart` (`SceneLayout`,
  `SeatGeometry`, `bandHeights`) and the core of `projection.dart`
  (`projectTripView(state, memory, session, looks)` with the parts T015 covers). Make T012–T015 pass.
- [X] T021 Add the three tables to `apps/mobile/lib/core/storage/tables.dart` exactly as data-model.md
  "Tables" (`trip_record` with `start_txn` TEXT PK, `trip_id`, `content_version`, `definition_json`,
  `seed`, `params_json`, `t_ms`, `created_at_ms`; `trip_record_command` with PK
  (`start_txn`, `seq`) and `command_json`; `trip_intent` with `request_txn` TEXT PK, `start_txn`,
  `kind`, `booster`). In `apps/mobile/lib/core/storage/app_database.dart`, set `schemaVersion => 2` and
  add `upgradeSteps[2]` creating them. Run `build_runner` and `make-migrations`; commit
  `drift_schemas/app/drift_schema_v2.json` and the generated `test/drift/` files. Make T017 pass.
- [X] T022 Create `apps/mobile/lib/features/trip/data/trip_records.dart` (the `TripRecords` interface,
  `TripRecordHeader`, `StoredTrip` with `toReplayRecord()`, `TripIntent`) and
  `apps/mobile/lib/features/trip/data/drift_trip_records.dart` (contracts/trip-records.md): a serial
  write queue; each method one transaction; `seq` = rows already in the record; `definition_json` and
  `params_json` in canonical JSON (`canonicalJson` from `content_models`); an optional
  `onKillPoint` callback for tests. Create `apps/mobile/lib/features/trip/data/trip_kill_point.dart`
  with `enum TripKillPoint`, shared by the store and later the controller, like M05's
  `EconomyKillPoint` (contracts/trip-controller.md "Test seams"). Make T007 and T016 pass.
- [X] T023 [P] Create `apps/mobile/lib/core/audio_haptics/`:
  - `sfx.dart`: `enum Sfx { coin, notePass, call, horn, fight, thanks, wrong, bump, alert }` with
    each file name, and `abstract interface class SfxPlayer { Future<void> load(); void play(Sfx s);
    Future<void> dispose(); }`;
  - `flame_sfx_player.dart`: one `AudioPool.create(source: AssetSource('audio/sfx/<file>.wav'),
    maxPlayers: 3, playerMode: PlayerMode.lowLatency)` per effect (not `FlameAudio.createPool`);
  - `haptics.dart`: `abstract interface class Haptics { void light(); void heavy(); }` and
    `SystemHaptics` over `HapticFeedback.lightImpact` and `heavyImpact`;
  - `audio_haptics_providers.dart`: keep-alive `sfxPlayerProvider` and `hapticsProvider`.
- [X] T024 [P] Create `apps/mobile/lib/features/trip/application/trip_settings.dart` (data-model.md
  "Preferences"): `TripSettings` with `soundOn`, `hapticsOn` (default on), `hintsSeen` (a set of
  archetype wire names), their setters, stored under `pref.trip_sound`, `pref.trip_haptics` and
  `pref.trip_hints_seen` (`on`/`off`; comma-separated). Add the three keys to
  `SharedPrefsSettingsStore.keys` in `apps/mobile/lib/core/preferences/shared_prefs_settings_store.dart`.
  Test it in `apps/mobile/test/features/trip/application/trip_settings_test.dart`.
- [X] T025 Create `apps/mobile/lib/features/trip/trip_providers.dart`: keep-alive `tripRecordsProvider`
  (`DriftTripRecords` over `appDatabaseProvider`), `tripSettingsProvider`, and placeholders for
  `passengerArtProvider` and `tripAdOffersProvider` filled in by later tasks. Run `build_runner`.

**Checkpoint**: guards, tokens, tables, the store, view types, layout, skins, strip, sound, vibration
and settings exist and their tests pass.

---

## Phase 3: User Story 1 - Play a trip from start to finish, offline (Priority: P1) 🎯 MVP

**Goal**: A trip opens, charges a liter, runs in fixed steps, shows the scene, the top bar and the
dashboard, lets the player pick, return, send, undo and tap, shows bubbles and «آخر كلام», and on the
last station records the result and goes to the result route, offline.

**Independent Test**: In airplane mode, open each sample trip and play it to the end; the scripted
player plays the regular-passenger fixtures through the controls and matches their expected results.

### Tests for User Story 1 (write first, must fail)

- [X] T026 [P] [US1] Write `apps/mobile/test/features/trip/domain/step_accumulator_test.dart`
  (research R4): 16 ms frames give one step every second or third frame; a 1 s frame runs at most 10
  steps and drops the rest; `alpha` = accumulator / 33; `clear()` empties it; a 0 ms first frame does
  nothing.
- [X] T027 [P] [US1] Write `apps/mobile/test/features/trip/domain/speech_test.dart`
  (contracts/trip-view.md "Speech and bubbles"): `pool.lines[variant % length]` with `ar-EG`;
  `{amount}` through `NumberFormatter.piasters` in both digit styles; `{station}` → the line's station
  name, or its letter without the line; no pool → null; bubble style by slot per the table.
- [X] T028 [P] [US1] Write `apps/mobile/test/features/trip/domain/bubble_queue_test.dart`: at most 2
  visible; each ≥ `bubbleMinMs` on the trip clock; FIFO; dropped after waiting `2 × bubbleMinMs`; one
  bubble per passenger at a time; a paused clock freezes everything.
- [X] T029 [P] [US1] Write `apps/mobile/test/features/trip/domain/talk_log_test.dart`: keeps the last
  two lines; passenger lines as `<label>: <text>`; `MoneyArrivedAtDriver` (fare), `BreakCompleted`,
  `MoneyDropped`, `DroppedLost`, `FareIncreased` lines with their ARB keys; labels from `SkinLook`,
  «الشلة» for a group payer, the station letter added when two aboard share a label.
- [X] T030 [P] [US1] Write `apps/mobile/test/features/trip/domain/cues_test.dart` for the US1 rows of
  contracts/trip-view.md "Cues": `MoneyArrivedAtDriver` → `coin` + light + log; `ChangeDelivered`
  exact → `thanks`; short → `wrong` + the bubble; over and not owed → no cue at all;
  `StationWarning` → `call`; `StationReached` → `horn`; `PassengerAlighted` fight → `fight` + heavy +
  shake; missed stop → `wrong`; `TokenBlocked` → no sound. Every row has at least two channels besides
  sound where the table says so.
- [X] T031 [P] [US1] Write `apps/mobile/test/features/trip/application/trip_controller_start_test.dart`
  (contracts/trip-controller.md "Opening" and "Finish"), with `testEconomy` and the sample pack:
  - nothing unfinished → a record is written under the request id, then `startTrip`; on `OpApplied` the
    engine starts and the phase is `running`; the economy's fuel dropped by one;
  - `no_fuel` → record deleted, phase `noFuel` with the next liter's time; `unknown_trip` → `ended` to
    Home; `OpWriteFailed` → record kept, phase `opening` with a retry that reuses the id;
  - another trip unfinished → `ended` redirecting to that trip;
  - `TripParams` equals `TripParams.fromTunables(tunableSnapshot(config), line)`; `bubbleMinMs` and
    `hintsMode` come from the per-line tunables;
  - `pick`, `returnHand`, `send`, `undo`, `tap` apply the matching engine commands only in `running`,
    and each accepted command appends one record row;
  - `advance` steps in 33 ms steps and emits cues; on `TripFinished` the phase goes `ending`, the result
    is recorded, the record deleted, and the phase becomes `ended` with the result route and the
    `TripResult`; `result_exists` on a retry counts as recorded;
  - `OpWriteFailed` on the result → phase stays `ending` with the retry message and the record kept;
    `retry()` records it with the same id, and the economy holds one result.
- [X] T032 [P] [US1] Write `apps/mobile/test/features/trip/presentation/dashboard_test.dart`: a tap on
  a drawer slot calls `pick(denomination)`; an empty slot is dashed and shakes on tap; a tap on the
  hand calls `returnHand`; a tap on a passenger hit area with money in hand calls `send`, and a drag
  from the hand onto a hit area does the same; «رجّع» shows only while `undoUntilMs` is ahead of the
  clock; the hand's total uses 20 pt digits in the player's digit style; «آخر كلام» shows two lines.
- [X] T033 [P] [US1] Write `apps/mobile/test/features/trip/presentation/trip_screen_test.dart`: the
  three bands at 390×844 (top 110, dashboard 230 overlapping 16); system bars hidden on entry and
  restored on exit; text scale clamped to 1.3; the token layer positions tokens from `SceneLayout` and
  `alpha`; passenger hit areas have semantics labels with seat and station letter and nothing about
  payment; the no-fuel card shows the next liter's countdown and links to the fuel sheet and Home.
- [X] T034 [P] [US1] Write `apps/mobile/test/features/trip/scripted_player_test.dart` with the
  scripted player in `apps/mobile/test/helpers/trip.dart`: for each fixture, it opens
  `TripController.forDefinition` on a test screen, and for each logged command advances to its `t_ms`
  and performs the matching widget gesture (slot tap, hand tap, passenger tap, undo, claim and choice
  answers, break mode, collect, booster, revive), then advances to the end; the result's JSON equals
  `expected_result`. The player also handles what the screen does that a fixture's log doesn't:
  - **Economy.** It opens `testEconomy` with a `firstState` holding, for each booster, as many as the
    log's `UseBooster` commands for it, and BONAT for each `Revive` at the catalog price, so no
    purchase card opens and the timing stays the log's.
  - **Disputes.** When the phase becomes `disputeOpen`, it answers at once with the passenger named
    by the log's next `ResolveDispute` for that dispute, or with the dispute's first candidate when
    the log has none. Such a run is marked inexact and skips the `expected_result` comparison. Only
    the three fixtures T092 excludes are inexact; the sample-trip runs of T044, T048 and T093 use
    this to play `line_hay.02`.

  In this task, run it for `core__*` except `core__false_accusation` (it needs claim answers: T062),
  `command__pick_return_send`, `command__undo_last_send`, `archetype__regular`,
  `ending__three_stars`, `ending__two_stars`, `ending__one_star`, `solver__line_hay_01` and
  `sample__line_hay_01_three_stars`.

### Implementation for User Story 1

- [X] T035 [US1] Create `apps/mobile/lib/features/trip/domain/step_accumulator.dart`, `speech.dart`,
  `bubble_queue.dart`, `talk_log.dart` and the US1 rows of `cues.dart` (`mapCues`, the `TripCue`
  types of data-model.md "Cues"). Extend `projection.dart` with bubbles and the log. Make T026–T030
  pass.
- [X] T036 [US1] Create `apps/mobile/lib/features/trip/application/trip_phase.dart`,
  `trip_session.dart` and `trip_controller.dart` (taking an optional `onKillPoint` with T022's
  `TripKillPoint`) with the Opening start path,
  `advance`, the five dashboard intents, the Finish sequence and `retry`
  (contracts/trip-controller.md), plus `TripController.forDefinition` for tests. Register
  `tripControllerProvider(tripId)` (auto-dispose) in `trip_providers.dart`. Make T031 pass.
- [X] T037 [US1] Create the stand-in scene in `apps/mobile/lib/features/trip/presentation/scene/`:
  - `trip_game.dart` (`TripGame extends FlameGame`, no fixed resolution, `update(dt)` →
    `controller.advance`);
  - `cabin_component.dart` (cabin and seats, static parts cached as a `Picture`),
    `windows_component.dart` (street moving, station sign approaching), `hand_component.dart`
    (rest and throw toward a passenger), `effects.dart` (highlight glow, and the shake on a
    `ShakeCue`, none under reduced motion; the bump reuses it in US4);
  - `passenger_art.dart`: `abstract interface class PassengerArtFactory` and `PassengerArt`
    (`update(PassengerView)`, `render`), and `StandInPassengerArt` drawing a face and shoulders in
    the sticker style with the `SkinLook`'s shirt token and accessory, the mood (calm, impatient,
    frowning with a sweat drop, angry), talking, asleep ("z z" as drawn shapes, not text) and
    headphones; `passenger_component.dart` placing it by `SceneLayout`, back rows first.

  Every color from tokens; no text in the canvas (T009). Fill `passengerArtProvider` with the stand-in.
- [X] T038 [US1] Create the overlays and bands in `apps/mobile/lib/features/trip/presentation/`:
  - `overlays/token_layer.dart`: a `Flow` whose delegate repositions token widgets every frame from
    `TripView.tokens` and `alpha` (research R3); each token is ≥ 40×24 pt with its amount at 15 pt,
    colored `fare`, `primary` or `danger` with «؟» when blocked;
  - `overlays/hit_areas.dart`: one transparent `Semantics` button per occupied seat, ≥ 44×44, calling
    `tap` or `send`, and a `DragTarget` for the hand;
  - `overlays/bubbles_layer.dart`: up to two bubbles, clamped inside the scene with 8 pt margins, tail
    toward the speaker, ≤ 60% of the scene's width, `TypeTokens.body` or larger, the pop skipped
    under reduced motion;
  - `top_bar/top_bar.dart` and `top_bar/station_strip_bar.dart` (FR-019, contracts/scene-layout.md);
  - `dashboard/dashboard.dart`, `dashboard/hand_slot.dart`, `dashboard/tray.dart`,
    `dashboard/talk_log_view.dart` (FR-028; boosters and the break button come in US5);
  - `cards/no_fuel_card.dart` and `cards/retry_card.dart`;
  - `trip_motion.dart` with the presentation constants of contracts/scene-layout.md "Motion";
  - `trip_screen.dart`: the bands from `bandHeights`, the `GameWidget`, the overlay `Stack`,
    `immersiveSticky` on entry and restore on exit, `MediaQuery.withClampedTextScaling(maxScaleFactor:
    1.3)`, and navigation on `ended` (`pushReplacement` to the result route with the `TripResult` as
    `extra`, or `go('/home')`).
- [X] T039 [US1] Wire the trip route in `apps/mobile/lib/core/routing/router.dart`: the `trip`
  destination builds `TripScreen(tripId)` inside `TripBackGuard`, keeping its path, name and links
  (the route table test stays unchanged). Consume cues in `trip_screen.dart`: `SoundCue` →
  `sfxPlayerProvider` when `soundOn`, `HapticCue` → `hapticsProvider` when `hapticsOn`; load the
  `SfxPlayer` when the trip opens.
- [X] T040 [US1] Add the US1 ARB keys to `apps/mobile/lib/l10n/app_ar.arb` (contracts/trip-view.md
  "Player text"): `tripTopBar*`, `tripStrip*`, `tripStationLetter1`–`4` (أ، ب، ج، د),
  `tripHand*`, `tripTray*`, `tripUndo`, `tripLook*` (one per skin family in `skin_looks.dart`, plus
  `tripLookPassenger` «راكب» and `tripLookGroup` «الشلة»), `tripLog*`, `tripNoFuel*`, `tripRetry*`,
  `tripSemantics*`. Make T027–T029, T032 and T033 pass.
- [X] T041 [US1] Make T034 pass for the US1 fixtures, fixing the controls (never the engine or the
  fixtures).
- [X] T042 [P] [US1] Write `apps/mobile/test/goldens/trip/trip_us1_goldens_test.dart`: an idle trip on
  `tuktuk` (`line_hay.01`) and on `micro_old` (`line_gamaa.02`), money in transit, two bubbles, a
  station warning, and the no-fuel card, each on `TripSurface.reference`, `a06` and `compact`, in RTL,
  with both digit styles, using the stand-in art. Generate the PNGs on Linux.
- [X] T043 [P] [US1] Write `apps/mobile/test/a11y/trip_minimum_sizes_test.dart`: on the three trip
  surfaces, faces (from `SceneLayout`) ≥ 80 and ≥ 50 pt, tokens ≥ 40×24 with a 15 pt amount, bubble
  text ≥ 15 pt, every tap target ≥ 44×44 (`iOSTapTargetGuideline`), all text ≥ 12 pt,
  `textContrastGuideline` and `labeledTapTargetGuideline`, in the US1 golden states. Bottom third
  (FR-018, constitution XI): every semantics node with a tap action outside the scene's rect lies in
  the bottom third of the screen, except the pause button, and the debug icon when the flavor isn't
  prod.
- [X] T044 [US1] Write `apps/mobile/integration_test/trip_offline_test.dart` (SC-001): with the
  connectivity source reporting offline, play each of the five sample trips to the end through the
  controls (the scripted player on the real app, with T034's economy and dispute rules). After each,
  check that the economy's balance grew by the result's earnings and that the record is gone.

**Checkpoint**: a sample trip plays from start to finish offline, with goldens and size checks.

---

## Phase 4: User Story 2 - A trip survives every interruption (Priority: P1)

**Goal**: Pause on lifecycle, button and back; the full pause card; leave and restart; resume a killed
trip at launch, paused; clean up stale records.

**Independent Test**: Kill and relaunch at 50 random moments of the sample trips; each time the state
is identical and no liter was spent.

### Tests for User Story 2 (write first, must fail)

- [X] T045 [P] [US2] Write `apps/mobile/test/features/trip/application/trip_controller_pause_test.dart`
  (contracts/trip-controller.md "Pausing and lifecycle", "Leave", "Restart"):
  - `pause(lifecycle|button|back)` pauses the engine, clears the accumulator and saves the record's
    clock; `advance` does nothing while paused; `resume` resumes;
  - leave from `paused`: `Abandon` applied and saved, the abandoned result recorded, the record deleted,
    `ended` to Home, no liter returned;
  - restart from `paused`: the abandoned result recorded, then a new record and a new start (one more
    liter), the engine starts afresh at 0 ms;
  - restart is unavailable with 0 liters and no unlimited window;
  - `OpWriteFailed` while restarting: on the abandoned result, phase `ending` with a retry that reuses
    its id and no new start; on the new start, phase `opening` with a retry that reuses the start's
    id. Either way the economy holds one result and charges one liter.
- [X] T046 [P] [US2] Write `apps/mobile/test/features/trip/application/trip_controller_resume_test.dart`
  (contracts/trip-controller.md "Opening" step 3, "Ending without a record"):
  - an unfinished running trip with a record → rebuilt, phase `paused`, no new start, fuel unchanged;
  - a rebuilt trip with an open dispute queues it for after «كمّل المشوار»;
  - a rebuilt finished trip records its result and ends at the result route;
  - no record, or a record whose command is rejected on replay → an abandoned result recorded, the
    player can start trips again;
  - the engine-built abandoned result and the `TripResult.fromJson` one (the hash of `[[0, "Abandon"]]`,
    zero counters, `duration_ms` 0) have equal JSON.
- [X] T047 [P] [US2] Write `apps/mobile/test/features/boot/boot_resume_test.dart`: with an unfinished
  trip the boot hand-off goes to `/trip/<tripId>`, otherwise to `/home`; stale records (a record with
  no unfinished start, an orphan intent) are deleted before the hand-off; `HomeArrival` doesn't fire on
  that launch.
- [X] T048 [P] [US2] Write `apps/mobile/test/features/trip/kill_rebuild_test.dart` (SC-006): on a
  temp-file database, play the five sample trips with the scripted player; at 50 seeded random points
  (`TripKillPoint` after a write), dispose everything, reopen the same file, open the trip; the rebuilt
  `TripState.toJson()` equals the live engine's at the record's saved clock, and the economy's fuel and
  start count didn't change. At half of the points, `pause(lifecycle)` runs before the kill, as when
  the app leaves the foreground: the saved clock is then the kill's moment, and the rebuilt state
  equals the live one exactly (SC-006).
- [X] T049 [P] [US2] Write `apps/mobile/test/features/trip/presentation/pause_card_test.dart`: back
  and the pause button show the card; it has «كمّل المشوار», «عيد المشوار» with "−١ بنزين",
  «ارجع الموقف» and two switches; the switches write `pref.trip_sound` and `pref.trip_haptics` at once;
  restart shows as unavailable with an empty tank; returning to the app after `paused` shows the card.

### Implementation for User Story 2

- [X] T050 [US2] Extend `trip_controller.dart` with `pause`, `resume`, `leave`, `restart`, the Opening
  resume path (rebuild, queued disputes, finished trip), "Ending without a record" and the Leave and
  Restart sequences. Make T045 and T046 pass.
- [X] T051 [US2] Create `apps/mobile/lib/features/trip/presentation/cards/pause_card.dart` (FR-013) and
  make `TripBackGuard` in `apps/mobile/lib/core/routing/trip_pause_overlay.dart` call
  `pause(PauseReason.back)` and show it; remove M03's simple `TripPauseOverlay` body, keeping the
  `tripPause` destination (overlay, no URL) and M03's three ARB keys. Add the `AppLifecycleListener` in
  `trip_screen.dart` (`inactive`, `hidden`, `paused` → `pause(lifecycle)`). Add the `tripPause*` ARB
  keys. Make T049 pass.
- [X] T052 [US2] In `apps/mobile/lib/features/boot/boot_screen.dart`, run
  `TripRecords.deleteAllExcept(unfinished?.startTxn)` and hand off to `/trip/<tripId>` when
  `economyViewProvider`'s `unfinished` is set (contracts/trip-controller.md "Launch"). Make T047 pass.
- [X] T053 [US2] Make T048 pass. Add the pause card to the goldens (`trip_us2_goldens_test.dart`, three
  surfaces, both digit styles) and to `trip_minimum_sizes_test.dart`.
- [X] T054 [US2] Write `apps/mobile/integration_test/trip_relaunch_test.dart` (FR-055): mid-trip,
  dispose the app's `ProviderScope` and pump a fresh one over the same database files; the trip opens
  paused at the same clock; continue and finish it.

**Checkpoint**: a trip survives pauses, leaving, restarting and a kill.

---

## Phase 5: User Story 3 - Every passenger type and choice of the MVP lines (Priority: P2)

**Goal**: Every archetype looks and behaves as the ux-spec says, drawn with the owner's Rive character;
claims are answered next to the passenger; who has paid never leaks.

**Independent Test**: The archetype fixtures play through the controls; the who-paid check passes on
every frame of every sample trip.

### Tests for User Story 3 (write first, must fail)

- [X] T055 [P] [US3] Write `apps/mobile/test/features/trip/domain/who_paid_test.dart` (FR-033,
  contracts/trip-view.md "Who has paid"): play every fixture through the engine; at every step,
  `ledgerBadge` is null unless `state.ledgerPeekActive`; `nearStopPulse` is set only for a passenger in
  the last warning's `owed` who is still owed, and cleared at `StationReached`; speaker labels never
  change when only the archetype changes (swap a passenger's archetype, keep the skin: same labels).
- [X] T056 [P] [US3] Write `apps/mobile/test/features/trip/domain/passenger_view_test.dart`: `mood` 3
  when leaving with a fight, impatient or the trip failed, 2 at `patiencePermille ≤ 333`, 1 at
  `≤ 666`, else 0; `asleep`, `waking`, `headphones` (muted), `attentive`; `talking` while a bubble is
  visible.
- [X] T057 [P] [US3] Write `apps/mobile/test/features/trip/presentation/claim_choice_test.dart`:
  `ClaimRaised` shows «ماشي» and «لأ، ما دفعتش!» under the passenger (each ≥ 44×44), the trip keeps
  running, and the answers call `answerClaim(insist: false|true)`; two open claims don't overlap each
  other or the dashboard; a claim left open closes when the passenger gets off, as accepted.
- [X] T058 [P] [US3] Write `apps/mobile/test/features/trip/rive_character_contract_test.dart` and
  `rive_character_goldens_test.dart` (contracts/rive-character.md "Tests"), with `RiveNative.init()` in
  `setUpAll` and `Factory.flutter`; and `apps/mobile/test/features/trip/presentation/passenger_art_test.dart`
  (`PassengerView` → the seven properties against a fake view-model instance). The first two fail until
  T059.

### Implementation for User Story 3

- [ ] T059 [US3] **Owner** (before merge): add `apps/mobile/assets/rive/passenger.riv` matching
  contracts/rive-character.md, exported from a Cadet (or higher) plan; note the plan in the PR.
  *(The file and its goldens are in, 2026-10-23; the plan is still to be named in the PR.)*
- [X] T060 [US3] Create `apps/mobile/lib/features/trip/presentation/scene/rive_passenger_art.dart`: the
  file decoded once with `File.asset('assets/rive/passenger.riv', riveFactory: Factory.flutter)` and
  cached in a keep-alive provider; per passenger a new `ArtboardInstance` of `Passenger`, its
  `StateMachine`, a `ViewModelInstance` from the file's `Passenger` view model bound to it, wrapped in
  `flame_rive`'s `RiveComponent`; `shirt` and `accessory` set once from `SkinLook`, the other properties
  on each view change; everything disposed when the passenger leaves. `passengerArtProvider` uses it
  when the file loads, else the stand-in. Make T058 pass.
- [X] T061 [US3] Extend `projection.dart` with mood, alertness, `nearStopPulse` and the claim choices;
  create `apps/mobile/lib/features/trip/presentation/overlays/choices_layer.dart` (claims now; change
  requests in US4) and the station-patch pulse; extend `trip_controller.dart` with `answerClaim`. Add
  `tripClaim*` ARB keys. Make T055–T057 pass.
- [X] T062 [US3] Extend the scripted player (T034) to the `archetype__*` fixtures and
  `core__false_accusation`; make them pass.
- [X] T063 [US3] Add to the goldens (`trip_us3_goldens_test.dart`, stand-in art): a blocked token with
  «؟», a sleeper, headphones, an open claim, a near-stop pulse; three surfaces, both digit styles; and
  add them to `trip_minimum_sizes_test.dart`.
- [X] T064 [US3] Write `apps/mobile/integration_test/trip_perf_test.dart` (SC-003 to SC-005, research
  R25) and `apps/mobile/tool/perf/trip_fps.sh <package> <trip_id>`: play `line_gamaa.02` with the real
  character in every seat under `IntegrationTestWidgetsFlutterBinding.watchPerformance`, report average
  fps, the worst one-second window, the drawer-tap-to-hand latency, the time to first frame and memory;
  the script runs it with `flutter drive --profile` and prints the summary.
- [ ] T065 [US3] **Owner**: run `tool/perf/trip_fps.sh com.wassalogra.app.dev line_gamaa.02` on the
  Galaxy A06 as soon as T060 is in (research R25 "Order of work"); paste the output in the PR. If it
  misses 45 fps, apply research R1's mitigations in order before continuing.

**Checkpoint**: every archetype plays through the controls with the real character, and nothing leaks
who has paid.

---

## Phase 6: User Story 4 - The in-trip events (Priority: P2)

**Goal**: The eight events look and play as the ux-spec's table says; the payment dispute stops the
clock; the change request is answered inline.

**Independent Test**: The `event__*` fixtures (except `event__payment_dispute`) play through the
controls; a dispute test trip plays the screen's way.

### Tests for User Story 4 (write first, must fail)

- [X] T066 [P] [US4] Extend `cues_test.dart` with the US4 rows of contracts/trip-view.md "Cues":
  `MoneyDropped` → `bump` + heavy + shake + log; `DroppedLost` → log; `FareIncreased` → `alert` + banner
  + log; `BreakCompleted` → `coin` + light + log (break mode is US5's); shake skipped under reduced
  motion.
- [X] T067 [P] [US4] Write `apps/mobile/test/features/trip/application/trip_controller_dispute_test.dart`
  (contracts/trip-controller.md "Disputes"): a step emitting `DisputeRaised` ends in `disputeOpen` with
  the engine paused; `answerDispute` applies `ResolveDispute` while paused and resumes; two disputes from
  one step are asked one after the other; an answer that fails the trip goes to `failed`; the record
  holds the resolution and rebuilds to the same state.
- [X] T068 [P] [US4] Write `apps/mobile/test/features/trip/presentation/events_test.dart`: dropped notes
  are tappable (≥ 44×44) until `droppedUntilMs` and call `collect`; the fare banner slides in with the old
  and new fare and the strip's prices change; `drop_me_here` turns the patch into the pulsing «هنا»
  star; the change request shows «فكّله» and «معلش» inline while running; the dispute card shows both
  faces and «مين اللي دفع؟»; traffic and open road change the windows; a roadside pickup walks in
  through the door.

### Implementation for User Story 4

- [X] T069 [US4] Extend `cues.dart`, `projection.dart` (dropped money, banner, `drop_me_here` star,
  change-request choices) and `trip_controller.dart` (`collect`, `answerChangeRequest`, `disputeOpen`
  with its queue, `answerDispute`). Make T066 and T067 pass.
- [X] T070 [US4] Create `apps/mobile/lib/features/trip/presentation/cards/dispute_card.dart`,
  `overlays/banner.dart`; extend `overlays/token_layer.dart` with dropped notes, `overlays/choices_layer.dart`
  with change requests, `scene/effects.dart` with the floor glint (the shake exists since T037),
  `scene/windows_component.dart` with traffic and the open road, and `passenger_component.dart`
  with the walk-in through the door. Add `tripDispute*`, `tripChangeRequest*`, `tripBanner*` ARB keys.
  Make T068 pass.
- [X] T071 [US4] Extend the scripted player to every `event__*` fixture except `event__payment_dispute`;
  add `apps/mobile/test/features/trip/dispute_screen_way_test.dart`, which plays `event__payment_dispute`'s
  definition answering the dispute when it opens, and checks the result against the engine's own
  `replay` of the log the controller recorded.
- [X] T072 [US4] Add each event's look and the dispute card to the goldens (`trip_us4_goldens_test.dart`,
  three surfaces, both digit styles) and to `trip_minimum_sizes_test.dart`.

**Checkpoint**: every event plays; disputes stop the clock until answered.

---

## Phase 7: User Story 5 - Help when the player is stuck (Priority: P2)

**Goal**: «حد معاه فكة؟», the four boosters with their purchase card, undo, rejection lines, and بلية's
hints by line.

**Independent Test**: With a test economy holding boosters and BONAT, use each booster, buy one that's
out, request breaks to the limit; check commands, inventory, balances and the screen.

### Tests for User Story 5 (write first, must fail)

- [X] T073 [P] [US5] Write `apps/mobile/test/features/trip/application/trip_controller_booster_test.dart`
  (contracts/trip-controller.md "Booster use", "Booster purchase"):
  - with stock: `UseBooster` applied first, then the command row and a `trip_intent` written in one
    transaction, then `useBooster` with the intent's id, then the intent deleted; the inventory drops by
    one;
  - kill after the transaction → the rebuild sends the intent with the same id and the economy charges
    once; kill before → neither the command nor the charge exists;
  - `OpWriteFailed` keeps the intent; `OpRefused` deletes it and the engine's use stands;
  - `traffic_jam` at `booster_traffic_jam_max_per_trip` uses: not applied, slot disabled;
  - with none left: phase `boosterCard` (engine paused); `buyBooster` charges the catalog price, then
    uses it and resumes; `insufficient_funds` keeps the card with the missing amount; `not_for_sale`
    disables the slot; `OpWriteFailed` keeps the card with the retry message, and the next tap reuses
    the id so BONAT is charged once; `closeBoosterCard` resumes without charging.
- [X] T074 [P] [US5] Write `apps/mobile/test/features/trip/application/trip_controller_break_test.dart`:
  `startBreak` enters pick mode with the slots the engine would accept glowing (notes ≥
  `trip_break_min_piasters` present in the drawer); `pickBreak` applies `RequestBreak`;
  `cancelBreak` leaves it; the button shows `breaksLeft` and is disabled at 0; `break_limit` and
  `cannot_make_change` show their lines (contracts/trip-view.md "Rejections").
- [X] T075 [P] [US5] Write `apps/mobile/test/features/trip/domain/hints_test.dart` (contracts/trip-view.md
  "Hints"): `always` → on a warning with `owed`, a hint at the first owed passenger until the station or
  until they are no longer owed; `first_time` → each archetype's trigger per the table, never for one in
  `hintsSeen`, the false claimer's hint points at nobody; `off` → none; one hint at a time, each for
  `bubbleMinMs`.
- [X] T076 [P] [US5] Write `apps/mobile/test/features/trip/presentation/help_test.dart`: the booster row
  shows counts, or the BONAT price when 0; ledger-peek badges («دافع», «لسه») show only during the peek;
  the purchase card shows price and balance, and «ناقصك …» when short; بلية's head and pointer show the
  hint; the rejection line shows in the log's place for 2 s; `command_limit` disables every control but
  pause.

### Implementation for User Story 5

- [X] T077 [US5] Create `apps/mobile/lib/features/trip/domain/hints.dart`; extend `projection.dart`
  (boosters with economy inventory and catalog price, break mode, ledger badges, hint, rejection line)
  and `cues.dart` (`FeedbackCue`); extend `trip_controller.dart` with `useBooster`, `buyBooster`,
  `closeBoosterCard`, `startBreak`, `pickBreak`, `cancelBreak`, rejection feedback, sending pending
  intents on resume, and saving `hintsSeen`. Make T073–T075 pass.
- [X] T078 [US5] Create `dashboard/boosters_row.dart`, the break button in `dashboard/hand_slot.dart`,
  `cards/booster_card.dart`, `overlays/hint_layer.dart` (بلية's head as a stand-in drawing with a
  bubble and a pointing hand), and the ledger badges in `overlays/choices_layer.dart`. Add `tripBreak*`,
  `tripBooster*`, `tripHint*` and `tripReject*` ARB keys. Make T076 pass.
- [X] T079 [US5] Extend the scripted player to `booster__*` and `command__request_break`; make them pass.
- [X] T080 [US5] Add the boosters row, the purchase card (affordable and short), break mode, ledger
  badges and a hint to the goldens (`trip_us5_goldens_test.dart`) and to `trip_minimum_sizes_test.dart`.

**Checkpoint**: every helper works, with its economy effects exactly once.

---

## Phase 8: User Story 6 - Failing, and getting back in (Priority: P2)

**Goal**: The failure card with its causes, the BONAT revive under the engine's and the economy's rules,
restart and leave from it, the story condition, and the ad seam that stays closed until M11.

**Independent Test**: Fail a trip, revive with BONAT, fail again (no second revive), restart, and fail
another to go home; check balances, results and the engine.

### Tests for User Story 6 (write first, must fail)

- [X] T081 [P] [US6] Write `apps/mobile/test/features/trip/domain/fail_summary_test.dart`: the top two
  causes by points lost; each count = points lost ÷ that cause's penalty in the params; plural keys per
  count; `revive` offered only under the controller's rule, with the catalog price and `affordable`.
- [X] T082 [P] [US6] Write `apps/mobile/test/features/trip/application/trip_controller_fail_test.dart`
  (contracts/trip-controller.md "Revive", "Leave", "Restart"):
  - `TripFailed` → phase `failed`; the offer shows only when `state.revivable`,
    `commandsAccepted < 1200`, `!unfinished.revived` and a catalog price exists;
  - `revive`: `buy(kind: revive)` first, then `Revive` applied and saved, phase `running`;
    `insufficient_funds` keeps the card; `already_revived` applies `Revive` only if the engine allows it;
    `OpWriteFailed` applies nothing and keeps the card with the retry message, and the next tap
    reuses the id so BONAT is charged once; a kill between `buy`'s `OpApplied` and `Revive`
    (`TripKillPoint`) is revived on the rebuild without a second charge;
  - a second failure offers no revive; a story trip failed by a fight offers none;
  - leave and restart from `failed` record the `failed` result (no `Abandon`);
  - resume of a failed trip shows the card; resume of a failed trip the economy says was revived applies
    `Revive` without charging.
- [X] T083 [P] [US6] Write `apps/mobile/test/features/trip/application/no_ads_while_running_test.dart`:
  across a full scripted trip with a fail, a revive and the traffic-jam slot, `SpyTripAdOffers` is never
  called while the engine is `running` (constitution IX), and no ad button shows.
- [X] T084 [P] [US6] Write `apps/mobile/test/features/trip/presentation/failure_card_test.dart`: every
  face frowns; the card shows «المشوار باظ», the cause line, «صالح بـ… بون» (affordable or not),
  «عيد المشوار» with its liter and «ارجع الموقف»; the story condition strip shows under the station
  strip for `kind: story` with `no_fights_required`.

### Implementation for User Story 6

- [X] T085 [US6] Create `apps/mobile/lib/features/trip/domain/fail_summary.dart` and
  `apps/mobile/lib/features/trip/application/trip_ad_offers.dart` (`TripAdOffers`, `NoTripAdOffers`;
  fill `tripAdOffersProvider`); extend `projection.dart` (`failSummary`, `storyCondition`, all faces at
  mood 3 when failed) and `trip_controller.dart` (`revive`, the failed resume path, leave and restart
  from `failed`). Make T081–T083 pass.
- [X] T086 [US6] Create `cards/failure_card.dart` and `overlays/story_strip.dart`. Add `tripFail*`,
  `tripCause*` (ICU plurals) and `tripStory*` ARB keys. Make T084 pass.
- [X] T087 [US6] Extend the scripted player to `ending__failed`, `ending__revived`,
  `ending__story_fight_fails` and `ending__abandoned`; make them pass.
- [X] T088 [US6] Add the failure card (with and without the revive, affordable and not) and the story
  strip to the goldens (`trip_us6_goldens_test.dart`) and to `trip_minimum_sizes_test.dart`.

**Checkpoint**: failing is recoverable, fairly, and no ad can appear.

---

## Phase 9: User Story 7 - Playtest tools on internal builds (Priority: P3)

**Goal**: A trip list on Home's placeholder, a debug panel, and a result placeholder with the outcome,
on dev and staging only.

**Independent Test**: On a dev build, open each trip from the list, use the panel, read a summary; on a
prod build, neither the list nor the panel exists.

### Tests for User Story 7 (write first, must fail)

- [X] T089 [P] [US7] Write `apps/mobile/test/features/trip/presentation/playtest_test.dart` (research
  R21): with `flavorProvider` dev and staging, Home's placeholder lists every trip of the active pack by
  line, and a tap opens `/trip/<id>`; with prod, no list; the debug icon (dev and staging only) pauses the
  trip and shows trip id, revision, seed, clock, status, reputation and counters, and its button puts the
  replay record's JSON on the clipboard; the result placeholder shows outcome, stars with their three
  conditions and pay from the route's `extra`, and from `lastResult` without it.

### Implementation for User Story 7

- [X] T090 [US7] Create `apps/mobile/lib/features/trip/presentation/playtest/trip_list.dart`,
  `debug_panel.dart` and `result_summary.dart`. In `router.dart`, pass `TripList` as Home's placeholder
  `extra` when the flavor isn't prod, and build the result route's placeholder with `ResultSummary`
  (reading `GoRouterState.extra` as `TripResult?`). Add the debug icon to `top_bar.dart` behind the
  flavor check, and `pause(PauseReason.debugPanel)` while the panel is open. Add `tripDebug*` and
  `tripPlaytest*` ARB keys. Make T089 pass.
- [X] T091 [US7] Regenerate M03's goldens that now show the trip screen, Home's list and the result
  summary (`test/goldens/navigation_goldens_test.dart`, `all_destinations_goldens_test.dart`,
  `shell_goldens_test.dart`) with `tripTestOverrides`; check `test/a11y/minimum_sizes_test.dart` still
  passes on M03's surfaces, including 360×640 (touch targets and text).

**Checkpoint**: the delivery plan's playtest can run on a staging build.

---

## Phase 10: Polish & Cross-Cutting Concerns

**Purpose**: The full fixture sweep, the cross-story checks, documents, owner actions, review.

- [X] T092 Run the scripted player over all 58 reproducible fixtures (every fixture except
  `event__payment_dispute` and `solver__line_hay_02`; `sample__line_hay_02_three_stars` answers its
  dispute in the step that raises it, so it plays, research R11) and assert the count is 58 (SC-002);
  assert the excluded two are exactly those, with the reason in the test.
- [X] T093 [P] Write `apps/mobile/test/features/trip/who_paid_frames_test.dart` (SC-008): play every
  sample trip with the scripted player through the widgets; at every pumped frame, find no «دافع» or
  «لسه» badge outside a peek, and no semantics label containing payment words (the ARB values of the
  badges).
- [X] T094 [P] Write `apps/mobile/test/features/trip/channels_test.dart` (constitution XI): with sound
  and vibration off and reduced motion on, every key event of contracts/trip-view.md "Cues" still
  produces its visual and its words; with them on, the sound and vibration play; no shake and no bubble
  pop under reduced motion.
- [X] T095 [P] Update `docs/architecture-mobile.md` (research "Documents updated"): §2 dependencies
  (`flame_rive`, `flame_test`); §8 (scene coordinates in points, Flame draws while Flutter handles touch
  and text including token amounts, view-model properties instead of state-machine inputs,
  `Factory.flutter`, the 744 pt rule); §10 (`TripController`, the trip record tables and the intent
  outbox); §24.6 resolved (research R1); §24.4 adds the UI side (research R8).
- [X] T096 [P] Update `docs/delivery-plan.md`: M05 merged in #8 (tick it and step 4); the hand-overs
  M02 resolved, including M03's pause control (constitution 1.4.0); under Step 7, a "Handed over
  from M02" item for M07: a trip layout for screens under 744 pt in which faces keep their
  50/80 pt minimums, with goldens at 360×640. That item ends M02's approved exception to
  constitution XI (Complexity Tracking in `specs/008-m02-trip-screen/plan.md`). Add M02's progress
  entry when the PR opens.
- [X] T097 [P] Update `CLAUDE.md`'s mobile section: the `rive_native` setup commands (Linux before
  `flutter test`, Android before the first build), `tool/sfx/generate.py`, `tool/perf/trip_fps.sh`, the
  Rive file's place and contract, and the trip tables in the database notes.
- [X] T098 Add M02's section to `docs/owner-actions.md` with task IDs: before merge T059 (the
  character file and its plan) and T065 (the A06 run); after merge T100 (download size) and T101
  (playtest); update "Open now".
- [ ] T099 Run the checks: format, `flutter analyze --fatal-infos`, `flutter test --coverage`,
  `tool/check_coverage.dart --min 80`, `flutter test test/drift`, and quickstart scenarios 1–9 on a dev
  build. Fix what fails. *(2026-10-22: the automated checks pass, with the `rive` tests excluded until
  T059; scenarios 1–9 need a device and are item 3 of M02's owner actions.)*
- [ ] T100 **Owner** (after merge): build the release app bundle and check the arm64 download with
  `bundletool get-size total`; it must stay under 80 MB.
- [ ] T101 **Owner** (after merge): the playtest of SC-009 with five testers on a staging build; record
  who finishes `line_hay.01` and who replays by choice.
- [X] T102 Review the diff:
  - run the `code-reviewer` and `flutter-reviewer` agents on `apps/mobile`;
  - check every changed file against constitution I, II, IV, V, VI, VII, VIII, IX, X, XI and XIII;
  - fix every CRITICAL and HIGH finding.
  *(2026-10-22: no CRITICAL; five HIGH fixed, each with a test that fails without it: a booster
  use whose charge failed is charged before the result, which waits for it; a use not charged yet
  counts against the stock, so a second tap or a second «buy» gets no free use; the pulses beat on
  the trip clock; the system bars stay hidden when one trip screen replaces another (and
  `TripScreen` is keyed by trip); a card hides the trip under it from the screen reader. Also fixed:
  the shake keeps its control's state, the dragged hand has the trip's text style, and a start race
  can't leave the screen opening. Left, with reasons in the completion report: the Flame loop
  behind cards, and four unlikely error paths.)*

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies. T001 first; T002–T004 in parallel with it.
- **Foundational (Phase 2)**: depends on Setup.
  - T005 first (the helpers).
  - Then the tests T006–T017 in parallel.
  - Then T018 and T019 in parallel → T020 → T021 → T022; T023 and T024 alongside T020–T022 → T025.
- **US1 (Phase 3)**: depends on Foundational. Tests T026–T034 in parallel, then T035 → T036 → T037 →
  T038 → T039 → T040 → T041, then T042–T044 (T042 and T043 in parallel).
- **US2 (Phase 4)**: depends on US1 (the controller and the screen). Tests T045–T049 in parallel, then
  T050 → T051 → T052 → T053 → T054.
- **US3 (Phase 5)**: depends on US1. It can run alongside US2 except where both edit
  `trip_controller.dart` and `projection.dart` (do US2's T050 first). T059 (owner) gates T060's tests,
  not the rest. T064 → T065 as soon as T060 is in.
- **US4 (Phase 6)**: depends on US1 and US3's `choices_layer.dart` (T061).
- **US5 (Phase 7)**: depends on US1, US3 (ledger badges in `choices_layer.dart`) and US2 (pending intents
  sent on resume).
- **US6 (Phase 8)**: depends on US2 (resume, leave, restart) and US5 (the ad seam sits next to the
  traffic-jam slot).
- **US7 (Phase 9)**: depends on US1 only; T091 runs after every screen exists, so after US6.
- **Polish (Phase 10)**: after every story. T093–T097 in parallel, then T092, T098, T099 → T102. T100
  and T101 are the owner's, after merge.

### Within Each User Story

- Tests first, and they must fail.
- The shared files grow in order US1 → US2 → US3 → US4 → US5 → US6: `trip_controller.dart`,
  `projection.dart`, `cues.dart`, `choices_layer.dart`, `app_ar.arb`.
- Run `build_runner` after every provider or table change, and `make-migrations` after the table change
  in T021.

### Parallel Opportunities

- **Setup:** T002–T004.
- **Foundational:** the tests T006–T017; T023 and T024 beside the domain and storage work.
- **US1:** T026–T034; then T042 and T043.
- **US2:** T045–T049.
- **US3:** T055–T058.
- **US4:** T066–T068.
- **US5:** T073–T076.
- **US6:** T081–T084.
- **Polish:** T093–T097.

---

## Parallel Example: Foundational tests

```text
T006 test/repo/domain_imports_test.dart
T007 test/repo/economy_writes_test.dart
T008 test/repo/no_ads_in_trip_test.dart
T009 test/repo/trip_text_in_canvas_test.dart
T010 test/core/glossary/line_id_names_test.dart
T011 test/core/theme/palette_test.dart
T012 test/features/trip/domain/scene_layout_test.dart
T013 test/features/trip/domain/skin_looks_test.dart
T014 test/features/trip/domain/station_strip_test.dart
T015 test/features/trip/domain/projection_test.dart
T016 test/features/trip/data/trip_records_test.dart
T017 test/core/storage/app_database_test.dart + trip_tables_upgrade_test.dart
```

## Parallel Example: User Story 1

```text
T026 test/features/trip/domain/step_accumulator_test.dart
T027 test/features/trip/domain/speech_test.dart
T028 test/features/trip/domain/bubble_queue_test.dart
T029 test/features/trip/domain/talk_log_test.dart
T030 test/features/trip/domain/cues_test.dart
T031 test/features/trip/application/trip_controller_start_test.dart
T032 test/features/trip/presentation/dashboard_test.dart
T033 test/features/trip/presentation/trip_screen_test.dart
T034 test/features/trip/scripted_player_test.dart
```

---

## Implementation Strategy

### MVP First (User Stories 1 and 2)

1. Phase 1 and Phase 2.
2. Phase 3 (US1): a trip plays from start to finish, offline.
3. Phase 4 (US2): a trip survives pauses and kills. Without it, a killed trip blocks every later trip
   (the economy refuses a new start while one is unfinished), so US1 isn't shippable alone.
4. **Stop and validate**: quickstart scenarios 1–3, and the delivery plan's "a trip from the bundled
   pack plays from start to finish with no network".

### Incremental Delivery

1. US1 + US2: the playable, safe trip.
2. US3: the passenger types and the real character, then the A06 run (T065) right away.
3. US4: the events.
4. US5: the helpers and the hints.
5. US6: failing and reviving.
6. US7: the playtest tools, so the milestone's playtest can start.
7. Polish, review, then merge as one PR, with T059 and T065 done.

### Notes

- **[P]** tasks are in different files with no dependencies on incomplete tasks.
- Never edit a generated file: Riverpod's and drift's `*.g.dart`, `drift_schemas/` (only
  `make-migrations` writes it), `test/drift/`, `lib/l10n/generated/`, and `assets/audio/sfx/*.wav` (only
  `generate.py` writes them).
- Never change the engine, `RULES.md` or a parity fixture to make a screen test pass: the screen adapts
  to the engine (constitution I, III).
- Never stash, reset or discard to get past a failing hook. Ask the owner.
- Commit after each task or logical group, with Conventional Commits.
