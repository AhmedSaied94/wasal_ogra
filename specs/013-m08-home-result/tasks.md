---

description: "Task list for M08 Home, the Pre-trip Card and the Result Screen"
---

# Tasks: Home, Pre-trip Card and Result Screen (M08)

**Input**: Design documents from `specs/013-m08-home-result/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**:

- **Mandatory, and first** (constitution XIII). Tests come first for every pure function:
  - the unlock rules;
  - the next trip, the savings target and the line card;
  - the met set, the briefing and the card mode;
  - the summary and the quote;
  - M07's two new `FirstSession` members.

  Every phase writes its tests first, and they must fail before its implementation tasks start.
- **Real engine, real economy.** Result and quote tests replay the parity fixtures through the real
  engine. Economy-backed tests use the real `EconomyService` over in-memory drift
  (`test/helpers/economy.dart`).
- **First-session states** use M07's `test/helpers/tutorial_content.dart`, which layers the release
  draft's five tutorial trips over the sample.
- **Coverage.** At least 80% of lines in `apps/mobile` (`tool/check_coverage.dart`).

**Organization**:

- **Paths** are from the repository root. Dart commands run with `fvm` in `apps/mobile/`.
- **Codegen.** After a `@riverpod` provider: `fvm dart run build_runner build -d`. After ARB keys:
  `fvm flutter pub get`.
- **Exactness.** Every number is from the contracts. Name each as a constant in `lib/`, never a bare
  literal. The list:
  - the next-trip sweep's depth: 6; the ported unlock cases: 19;
  - Home: gutter 16, gaps 10, the scene card's minimum 180 pt, the name's max width 84, the
    offline banner's resize 332 → 282 at 844 pt over 200 ms `easeOut`, the button crossfade 150 ms;
  - `PassengerAvatar` sizes 38, 46, 50 and 60;
  - the result's stars 58 / 72 / 58, the share image's 48 / 62 / 48;
  - the share image: 360×360 at pixel ratio 3 (1080×1080);
  - the quote's replay budget: 150 ms on CI for the longest-trip stress fixture;
  - the fuel label: minute granularity, rounded up.

  New motion constants go in `apps/mobile/lib/core/theme/tokens/design_extras.dart`, the guards'
  allowed place: `barkerRepop` 6 s, `payCountUp` 600 ms, `aptBarFill` 600 ms `easeOut`,
  `starLabelStagger` 270 ms.
- **Names** are the contracts', spelled exactly:
  - `pref.pre_trip_card` with `always` | `new_only`;
  - `ResultArgs`, `ExitToResult`, `ArrivalItem`, `DueSceneArrival`, `NameSheetArrival`;
  - `BetweenTripsCheckpoint`, `ShareGateway`;
  - `nextTutorialTrip`, `fuelLessonDue`;
  - `first-session-continue` (M07's key, kept).
- **Shared files.** These grow story by story, so tasks that touch them run in order:
  - `apps/mobile/lib/core/routing/router.dart`;
  - `apps/mobile/lib/l10n/app_ar.arb`;
  - `apps/mobile/lib/features/trip/application/{trip_phase.dart,trip_controller.dart}`,
    `presentation/trip_screen.dart`;
  - `apps/mobile/lib/bootstrap/app.dart`;
  - `apps/mobile/lib/features/onboarding/domain/first_session.dart`;
  - `apps/mobile/lib/core/theme/tokens/design_extras.dart`;
  - `apps/mobile/test/repo/domain_imports_test.dart`.
- **No database, engine, operation, content-schema or tunable change** (plan). A task that seems to
  need one is wrong; stop and ask.
- **One PR.** Its description lists:
  - the three departures from the design (plan "Complexity Tracking");
  - the change to M07's hand-over (Clarifications 2026-10-28);
  - the expected golden differences (research R20).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story the task belongs to (US1–US6 from spec.md)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: The one new dependency and the motion constants.

- [X] T001 Add `share_plus` to `apps/mobile/pubspec.yaml` at its current release, with a comment
  naming research R16. Pick a version whose iOS plugin ships as a Swift Package, so the build stays
  without a Podfile (CLAUDE.md): check the package's `ios/` folder for `Package.swift`. Run
  `fvm flutter pub get`, and confirm no `ios/Podfile` appears.
- [X] T002 [P] Add `barkerRepop` (6 s), `payCountUp` (600 ms), `aptBarFill` (600 ms, `easeOut`) and
  `starLabelStagger` (270 ms) to `apps/mobile/lib/core/theme/tokens/design_extras.dart`, each with
  a comment naming its research section (R13, R19). Run `test/repo/no_raw_style_values_test.dart`.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The phone's unlock rules, M07's two new members, the shared components, and the guards.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Guards and rule tests: first

- [X] T003 [P] Extend `apps/mobile/test/repo/domain_imports_test.dart` (contracts/seams.md "Repo
  guards touched"):
  - `lib/core/progress/domain` may import only `package:content_models/`, `dart:core`,
    `dart:collection` and its own folder;
  - `lib/features/home/domain`, `lib/features/pre_trip/domain` and `lib/features/result/domain` may
    import only `content_models`, `trip_engine`, the content, economy and progress domains, and the
    trip domain's `looks.dart`.
- [X] T004 [P] Write `apps/mobile/test/core/progress/unlocks_test.dart`. It ports every one of the
  19 cases of `backend/apps/progress/tests/test_unlocks.py`, each Dart test named
  `'<python test name>'`. Add a comment at the top: when the Python file changes, this port changes
  in the same PR. Cover `apartmentOpens`: the first chapter by `order` whose goal is
  `complete_room`; null if none. Also write `apps/mobile/test/core/progress/sample_sweep_test.dart`
  (contracts/progress-rules.md "Tests", quickstart §2). Over the sample pack and
  `test/helpers/synthetic_packs.dart`, for every state reachable by finishing startable trips up to
  depth 6, `tripUnlocked`, `lineUnlocked`, `chapterUnlocked` and `currentChapter` agree with a table
  of expected unlocks written in the test.
- [X] T005 [P] Extend `apps/mobile/test/features/onboarding/domain/first_session_test.dart`
  (research R8):
  - `nextTutorialTrip` is the first unfinished tutorial trip while `inFirstSession`, else null;
  - `fuelLessonDue(tripId)` is true on a tutorial trip's first play at `fuelLessonTripIndex`, and
    on any tutorial trip with an empty tank and no window, until the grant or the lesson is done.
    It stays true when a scene is also due, where `beforeStart` returns `DueScene`;
  - `nextAfterResult` gives the same results as before, for every tutorial trip and for a
    non-tutorial one.

### The unlock rules and M07's members

- [X] T006 Create `apps/mobile/lib/core/progress/domain/player_progress.dart` and `unlocks.dart`
  (contracts/progress-rules.md):
  - `PlayerProgress` with `bestStars` (`Map<String, int>`, by trip id; missing = 0) and `owned`
    (`Set<(SkuKind, String)>`);
  - `vehicleOwned`, `lineComplete`, `lineUnlocked`, `tripUnlocked`, `chapterUnlocked`,
    `chapterComplete`, `roomComplete`, `itemPurchasable`, `currentChapter` and `apartmentOpens`,
    with the server's names, argument order and edge cases.

  Chapters are ordered by `(order, chapter_id)`, a line's trips by `tripsOf(line)`. T004 passes.
- [X] T007 Add the same "keep the Dart port in step" comment at the top of
  `backend/apps/progress/services/unlocks.py` and `backend/apps/progress/tests/test_unlocks.py`.
  Comments only; run `uv run ruff format --check .` in `backend/`.
- [X] T008 Create `apps/mobile/lib/core/progress/application/player_progress_provider.dart`:
  `playerProgressProvider` builds `PlayerProgress.of(view, content)` from `economyViewProvider` and
  `activeContentProvider`.
- [X] T009 In `apps/mobile/lib/features/onboarding/domain/first_session.dart`:
  - add `String? get nextTutorialTrip`;
  - make `_fuelLessonDue` the public `bool fuelLessonDue(String tripId)` and update its callers;
  - rewrite `nextAfterResult` on top of `nextTutorialTrip`.

  T005 passes, and so does M07's existing suite (`fvm flutter test test/features/onboarding`).

### Shared components: tests first

- [X] T010 [P] Write `apps/mobile/test/core/theme/components/passenger_avatar_test.dart` (research
  R25):
  - the four sizes, 38, 46, 50 and 60;
  - the `ground` circle, or `danger.soft` for a mistake;
  - the look's `Person` number, with the look's SVG as the fallback when Rive is off;
  - no idle loop.
- [X] T011 Create `PassengerAvatar` in `apps/mobile/lib/core/theme/components/avatars.dart`,
  cropped like `CharacterAvatar`. Add it to the gallery's components page
  (`apps/mobile/lib/features/dev/gallery/components_page.dart`). T010 passes.
- [X] T012 Move `StationTag` from
  `apps/mobile/lib/features/trip/presentation/overlays/patches_layer.dart` to
  `apps/mobile/lib/core/theme/components/station_tag.dart`, and update the trip's imports. No
  behaviour change: the trip goldens and `test/features/trip` pass unchanged.

**Checkpoint**: The unlock rules agree with the server's cases, M07's session exposes what Home
needs, and the components are ready.

---

## Phase 3: User Story 1 - One tap from Home to the next trip (Priority: P1) 🎯 MVP

**Goal**: A real Home with the header, the fuel countdown, the street scene, the line card,
«يلا نطلع!» and the savings card. One due item opens per arrival.

**Independent Test**: On a fresh dev build with the sample pack, every figure on Home matches the
economy and the pack. «يلا نطلع!» opens the next trip's card. After the trip, Home's line card has
moved on.

### Tests for User Story 1 ⚠️

- [X] T013 [P] [US1] Write `apps/mobile/test/features/home/domain/next_trip_test.dart` (research R3,
  data-model `NextTrip`):
  - each rule step: startable only; unfinished means `bestStars == 0`; the line played last; the
    earliest open line by `order`; then the fewest best stars on the line played last, the earliest
    by trip number on a tie; null for a pack with no startable trip;
  - "the line played last": the in-memory last finished trip, otherwise the trip with the latest
    `firstCompletedAtMs`, otherwise the first line by `order`;
  - a sweep over the sample pack and `test/helpers/synthetic_packs.dart` (several lines, a story
    trip mid-line, a locked story chapter). From a new player, finish each startable trip in every
    order up to depth 6, and assert that in every state `tripUnlocked(next)` holds and the line and
    trip match the expected ones;
  - with `tutorialContent()`: `nextTutorialTrip` wins while `inFirstSession`, and FR-010 takes over
    after trip 5.
- [X] T014 [P] [US1] Write `apps/mobile/test/features/home/domain/savings_target_test.dart`
  (research R4):
  - `ChapterGoalTarget` for each goal kind with its progress. `complete_line` is a `Count` of
    finished regular trips over the line's regular trips; `own_vehicle`, `purchase` and
    `complete_room` are an `Amount` of JENEHAT over the catalog price;
  - `ApartmentPieceTarget` from `apartmentOpens()` on: the first unowned item by `order` of the
    current chapter's goal room;
  - `NoTarget` for a pack without chapters;
  - `affordable`: an `Amount` with `have ≥ of`; a line goal never.
- [X] T015 [P] [US1] Write `apps/mobile/test/features/home/domain/line_card_test.dart`:
  - `tripIndex` is `NextTrip.index`, and `tripTotal` is `tripsOf(line).length`;
  - `finished` counts `bestStars ≥ 1`;
  - `starsEarned` is Σ `bestStars`, and `starsMax` is 3 × `tripTotal`.
- [X] T016 [P] [US1] Write `apps/mobile/test/features/home/trusted_countdown_test.dart` (research
  R11, SC-003):
  - a fake `trustedClockProvider` and a device clock moved ±1 h: the shown mm:ss follows trusted
    time only;
  - the countdown hides when `nextLiterAtMs` is null;
  - only the countdown's own text rebuilds;
  - the a11y label changes at most once a minute, rounded up, and the ticking text is excluded from
    semantics;
  - the timer is cancelled on dispose.
- [X] T017 [P] [US1] Write `apps/mobile/test/features/home/arrival_queue_test.dart` (research R9):
  - the order by `rank`;
  - at most one item per arrival;
  - nothing while an item is open, nor on the arrival that returns from it;
  - nothing unless the location is still `/home` at the end of the frame;
  - after `ContentLifecycle`'s pack switch;
  - never over a trip.
- [X] T018 [P] [US1] Write `apps/mobile/test/features/onboarding/arrival_items_test.dart`
  (contracts/seams.md):
  - with a scene due and the name refused, the first arrival plays the scene only, and the next
    arrival opens the name sheet;
  - the name sheet opens once per launch (`nameAskedProvider`);
  - M07's `afterScene` hook runs inside the scene's item, before it completes;
  - the router no longer redirects `/home` to a scene.
- [X] T019 [P] [US1] Write `apps/mobile/test/features/home/street_scene_test.dart` (FR-004, research
  R13):
  - the microbus carries the roof sign with the line's last station, and the barker (look
    `regular`) calls «{station}.. {station}!»;
  - the tuktuk has no sign, and بلية (look 23) calls instead;
  - the bubble pops on entry and again every `DesignExtras.barkerRepop`, checked with a fake clock;
  - under reduced motion there is no pop, and the idle loops stay on frame 0;
  - the scene isn't tappable, and its text is Flutter widgets, not canvas drawing.

  Then write `apps/mobile/test/features/home/home_screen_test.dart` (contracts/home.md):
  - the header's name from `driverNameProvider` («الأسطى» with none; one line, ellipsis at 84);
  - the level, and the pills from `economyViewProvider`, with `fuel/max` at the real maximum;
  - the line card's figures;
  - the savings card's piece and «جاهزة للشرا!» when affordable;
  - the links: profile → `/settings`, BONAT pill → `/shop`, fuel pill → the fuel sheet, line card →
    `/lines`, savings card → `/apartment`; the vehicle isn't tappable, and the JENEHAT pill isn't a
    link;
  - the apartment tab's dot while the target is affordable (FR-009);
  - a finished trip's new state shows on return with no reload;
  - `startNextTrip`'s branches with a fake checkpoint: the card, a tutorial trip straight to
    `/trip/<id>` while `inFirstSession`, and the fuel sheet on an empty tank.

### Implementation for User Story 1

- [X] T020 [P] [US1] Create `apps/mobile/lib/features/home/domain/next_trip.dart` (`NextTrip` with
  `tripId`, `lineId`, `index` 1-based in `tripsOf(line)`, and `isReplay`) and
  `apps/mobile/lib/features/home/domain/line_card.dart` (`LineCardFigures`). T013's rule steps and
  T015 pass.
- [X] T021 [P] [US1] Create `apps/mobile/lib/features/home/domain/savings_target.dart`: the sealed
  `SavingsTarget` (`ChapterGoalTarget`, `ApartmentPieceTarget`, `NoTarget`), with `Amount` and
  `Count` progress and `affordable`. T014 passes.
- [X] T022 [US1] Create the application layer in `apps/mobile/lib/features/home/application/`:
  - `last_finished_trip.dart`: `lastFinishedTripProvider`, keepAlive, memory only;
  - `checkpoint.dart`: `BetweenTripsCheckpoint` with a default `pass()` that returns at once;
  - `home_slots.dart`: `homeDailyRowProvider` and `morningPiggySlotProvider` (`WidgetBuilder?`,
    null), and `storySceneWaitingProvider` (false);
  - `home_model.dart`: `homeModelProvider` with every `HomeModel` field of data-model.md.
    `fuelState` is `empty` when "`liters < 1` with no window and no lesson due", `unlimited` with a
    window, else `normal`. The lesson is M07's `fuelLessonDue`. `next` is `nextTutorialTrip`, else
    `nextTrip(...)`.

  T013's sweep passes.
- [X] T023 [US1] Create `apps/mobile/lib/features/home/application/start_next_trip.dart` per
  contracts/home.md:
  1. an empty tank (not `fuelLessonDue`) → the fuel sheet's route;
  2. `await checkpoint.pass()`, then stop if the context is unmounted;
  3. a tutorial trip while `inFirstSession`, or `!shouldShowCard`, → `NavGuard.go(context,
     '/trip/$tripId')`; else `context.go('/home/pre-trip/$tripId')`.

  Until US2's `shouldShowCard` lands, treat the card as always shown.
- [X] T024 [US1] Create `apps/mobile/lib/features/home/application/arrival_queue.dart`
  (`ArrivalItem` with `rank`, `isDue`, `open`; `HomeArrivalQueue`; `arrivalItemsProvider`). Start it
  in `apps/mobile/lib/bootstrap/app.dart`'s `_afterStartup`, after `ContentLifecycle`, and dispose
  it with it. T017 passes.
- [X] T025 [US1] Create `apps/mobile/lib/features/onboarding/presentation/arrival_items.dart`:
  - `DueSceneArrival`, rank 10: due when `onArrivalAtHome()` returns a scene; pushes
    `/onboarding/scene/<id>?then=/home` and completes on the return;
  - `NameSheetArrival`, rank 20: due when `askName` and `nameAskedProvider` isn't done; marks it
    done, then awaits `showNameSheet(root, refused: facts.nameRefused)` on the root navigator.

  `arrivalItemsProvider` returns both. In `apps/mobile/lib/core/routing/router.dart`, remove the
  `/home` row of the redirect and the `NameReaskHost` wrapper. Delete
  `apps/mobile/lib/features/onboarding/presentation/name_reask_host.dart`. In M07's
  `apps/mobile/test/core/routing/first_session_redirect_test.dart`, replace the `/home` redirect
  cases with the same outcome through the arrival item: the scene plays, then `/home`. T018
  passes.
- [X] T026 [P] [US1] Create `apps/mobile/lib/features/home/presentation/trusted_countdown.dart`. It
  runs its own 1 s `Timer`, reads `trustedClockProvider` and formats with
  `NumberFormatter.countdown`. T016 passes.
- [X] T027 [P] [US1] Create `apps/mobile/lib/features/home/presentation/street_scene.dart` (research
  R13):
  - `StreetPainter` with the scene tokens at `C-Home_02.svg`'s geometry, anchored to the card's
    bottom;
  - the next trip's `VehicleSprite` idling;
  - the roof sign: a Flutter pill with the line's last station, microbus only;
  - the barker, a `Person` of look `regular` (`passengers/regular.svg` fallback), or بلية, look 23,
    on the tuktuk;
  - a `SpeechBubble` (character variant, no name) with `homeBarkerCall(station)`, popping on entry
    and every `DesignExtras.barkerRepop`;
  - two `PassengerAvatar` riders, looks `regular` and `hagga`.

  Under reduced motion there is no pop, and the idle loops pause on frame 0. Not tappable. T019's
  street scene cases pass.
- [X] T028 [P] [US1] Create the rest of `apps/mobile/lib/features/home/presentation/`:
  - `home_header.dart`: the profile, with `CharacterAvatar('usta')` in the 48 `sun` circle, the
    name, max width 84, and `homeLevelChip(n)`; then the JENEHAT, BONAT and fuel pills, with
    `TrustedCountdown` under the fuel figure;
  - `line_card.dart`;
  - `start_button.dart`: the normal state only here; US4 adds the others;
  - `savings_card.dart`: the piece variant, and the chapter-goal variant's layout.
- [X] T029 [US1] Create `apps/mobile/lib/features/home/presentation/home_screen.dart`: one column in
  `C-Home`'s order, a 16 pt gutter, 10 pt gaps, and the scene card as the only flexible block (no
  maximum, 180 pt minimum). Below that, scroll above the fixed bottom bar. The empty slots take no
  space. Add the apartment-dot listener on `homeModelProvider.select((m) => m.apartmentDot)` calling
  `newDotProvider(Section.apartment).show()`. T019 passes.
- [X] T030 [US1] In `apps/mobile/lib/core/routing/router.dart`, build
  `ReportFullyDrawn(child: HomeStatusArea(child: HomeScreen()))` for `/home` in every flavor, and
  remove the `RouteNames.home when playtest` branch. The testers' tools return in US6, in the same
  PR. Update `test/core/routing/route_table_test.dart` and `navigation_test.dart` where they named
  the placeholder.
- [X] T031 [P] [US1] Add the `home*`, `goal*` and `homeBarkerCall` keys to
  `apps/mobile/lib/l10n/app_ar.arb`: the HANDOFF strings as written, and the drafts of research R18
  for the goals and the barker. Include the a11y labels:
  - `homeA11yCoins`;
  - «يلا نطلع!» with «هيصرف لتر بنزين»;
  - the fuel pill's minute-only label.

  Numbers arrive formatted. Run `test/repo/no_arabic_literals_test.dart`.
- [X] T032 [US1] Add the `C-Home` design checks (research R20, 008.5's design-checks contract):
  - `apps/mobile/test/design/samples/c_home.dart`, with fakes for the daily row, the event circle
    and the piggy;
  - `apps/mobile/test/design/c_home_layout_test.dart`, against `docs/design/boxes/C-Home.json` at
    ±2 pt. Skip the garage hit area (phase 2, FR-008); the debug button is app-only;
  - `apps/mobile/test/goldens/design/c_home_goldens_test.dart`, at 390×844 in both digit styles,
    beside `docs/design/png/C-Home.png`.

  Run `--update-goldens` on Linux and review the images.
- [X] T033 [US1] Add Home to `apps/mobile/test/a11y/` minimum sizes: at 360×640, 360×800 and
  390×844, text scale 1.0 and 1.3, every tappable is at least 44×44 and every text at least 12 pt.
  Nothing is cut off or overlapping (SC-006).

**Checkpoint**: Home works and starts the next trip; M07's scene and name sheet open one per arrival.

---

## Phase 4: User Story 2 - The trip's briefing before the clock starts (Priority: P1)

**Goal**: The pre-trip card as a sheet: stop prices, rule lines, the «جديد» card, the star goals, the
boosters with the in-place buy, the story chip and condition, and «اطلع». Plus the card setting.

**Independent Test**: Each sample trip's card matches its data. Closing spends nothing. «اطلع»
opens the trip, which charges the liter.

### Tests for User Story 2 ⚠️

- [X] T034 [P] [US2] Write `apps/mobile/test/features/pre_trip/domain/met_set_test.dart`. The met set
  is "the archetypes and events of every trip in the active pack with `bestStars ≥ 1`". It skips
  trips the pack lacks and follows a restored progress.
- [X] T035 [P] [US2] Write `apps/mobile/test/features/pre_trip/domain/briefing_test.dart` (data-model
  `TripBriefing`):
  - `stops` in drop-off order (`at_seconds`), with `StopPrice` slots 1–4 and letters أ ب ج د;
  - four stops;
  - the `student` line only when the discount is above 0 and a student rides, with the
    percentage's variant;
  - `bag` and `childFree` built only for archetypes in `bagArchetypes` and `childArchetypes`;
  - `newSubject`: the trip's passengers in definition order, then its events; the first not met
    wins; `regular` is never new;
  - `starsEarned`;
  - the four boosters in the artboard's order;
  - `buyOffer`: the first tile with `count == 0`, null when every count is above 0 or while
    `boostersLocked`;
  - `boostersHidden` follows `boostersLocked`;
  - `isStory` and `storyRuleNoFights`.
- [X] T036 [P] [US2] Write `apps/mobile/test/features/pre_trip/domain/card_mode_test.dart`:
  `shouldShowCard` is `story` → show; `newSubject != null` → show; `mode == always` → show;
  otherwise open the trip directly.
- [X] T037 [P] [US2] Write `apps/mobile/test/features/pre_trip/domain/new_subjects_test.dart`:
  - `newCardSubjects` equals the archetypes of `content/engine/capabilities.json` minus `regular`,
    plus the eight in-trip events;
  - every subject has its `newCard*` name and sentence in `app_ar.arb`;
  - `bagArchetypes` and `childArchetypes` hold only archetypes `capabilities.json` lists (empty
    today);
  - every event has an icon in `eventIcons` that exists in `assets/icons/`.
- [X] T038 [P] [US2] Write `apps/mobile/test/features/pre_trip/pre_trip_card_test.dart`
  (contracts/pre-trip-card.md):
  - closing four ways (✕, a swipe past 25% or a fling, the scrim, system back) and on a tab switch,
    with nothing spent;
  - «اطلع» goes to `/trip/<id>`, and the liter is charged by the trip, not the card;
  - an empty tank opens the fuel sheet;
  - an unknown or locked trip pops to `/home` with nothing charged;
  - the story chip and the condition bar;
  - a scrolling body with the button pinned;
  - the boosters hidden while `boostersLocked`;
  - the buy flow: applied, refused (insufficient funds), a double tap that buys once, offline, a
    write failure.
- [X] T039 [P] [US2] Write `apps/mobile/test/features/settings/settings_pre_trip_card_test.dart`:
  - the «كارت ما قبل المشوار» row;
  - the saved `pref.pre_trip_card`;
  - "missing or invalid: the `pre_trip_card_mode` tunable".

### Implementation for User Story 2

- [X] T040 [P] [US2] Create `apps/mobile/lib/features/pre_trip/domain/met_set.dart` and
  `new_subjects.dart`:
  - the closed `newCardSubjects` table;
  - `eventIcons`, with research R5's table:

    | Event | Icon |
    | --- | --- |
    | `bump` | `warning` |
    | `traffic` | `booster_traffic` |
    | `open_road` | `route_bold` |
    | `fare_increase` | `coin_up` |
    | `drop_me_here` | `hand` |
    | `payment_dispute` | `speech` |
    | `change_request` | `call_change` |
    | `roadside_pickup` | `hand` |
  - empty `bagArchetypes` and `childArchetypes`.

  T034 and T037's table checks pass.
- [X] T041 [P] [US2] Create `apps/mobile/lib/features/pre_trip/domain/briefing.dart`
  (`TripBriefing`, `StopPrice`, `RuleLine`, the sealed `NewSubject` with `NewArchetype(archetype,
  look)` and `NewEvent(eventId, icon)`, `BoosterTile`, `BuyOffer`) and `card_mode.dart`
  (`shouldShowCard`). T035 and T036 pass.
- [X] T042 [US2] Create `apps/mobile/lib/features/pre_trip/application/`:
  - `card_mode_provider.dart`: `PreTripCardModeNotifier` over `settingsStoreProvider` with
    `pref.pre_trip_card` = `always` | `new_only`, falling back to the `pre_trip_card_mode` tunable;
  - `briefing_provider.dart`: `tripBriefingProvider(tripId)`;
  - `booster_purchase.dart`: `BoosterPurchase` holds one `TxnId` from the tap until the outcome
    (`_id ??= economy.newRequestId()`). It calls `economy.buy(_id, kind: SkuKind.booster, skuId:
    boosterWire[booster])`. `OpApplied` clears the id; a refusal or `OpWriteFailed` keeps it; a tap
    in flight does nothing.

  Wire `shouldShowCard` into `start_next_trip.dart` (T023).
- [X] T043 [US2] Create `apps/mobile/lib/features/pre_trip/presentation/`:
  - `pre_trip_card.dart`;
  - `stop_prices.dart`: up to four cells in one row, right to left, names wrapping to two lines;
  - `new_card.dart`: `PassengerAvatar(look, 60)` or the event icon, «جديد», the name and a
    two-line sentence;
  - `star_goals.dart`;
  - `booster_tiles.dart`: tiles not tappable, plus the buy chip;
  - `buy_dialog.dart`: an `AppDialog` with M02's booster content, «ناقصك …» when short, «اشتري» and
    «مش دلوقتي», no dismissal by tapping outside.

  «اطلع» is `AppButton.primary(xl)` with `CostChip` «−١» (hidden in a window), pinned at the
  bottom.
- [X] T044 [US2] In `apps/mobile/lib/core/routing/router.dart`, build `PreTripCard(tripId)` for
  `/home/pre-trip/:tripId` inside its `AppSheetPage`. T038 passes.
- [X] T045 [US2] Add the «كارت ما قبل المشوار» `Segmented` row («يظهر دايمًا», «في الجديد بس») to
  `apps/mobile/lib/features/settings/settings_screen.dart`, built like the digit-style row. T039
  passes.
- [X] T046 [P] [US2] Add the `preTrip*`, `newCard*` (the 19 names and sentences of research R18) and
  `settingsPreTripCard*` keys to `apps/mobile/lib/l10n/app_ar.arb`. Include the a11y labels: «اطلع،
  هيصرف لتر بنزين», each price cell «{station}، {price} جنيه», each star row, and each booster tile
  «{booster}، معاك {n}». The أبو سمّاعة sentence says to call him twice and nothing about routing
  money (Clarifications Q3). T037's ARB check passes.
- [X] T047 [US2] Add the `PreTrip` design checks:
  - `apps/mobile/test/design/samples/pre_trip.dart`: three stops, a student rule, أبو سمّاعة new,
    two stars, one booster at 0, over Home;
  - `apps/mobile/test/design/pre_trip_layout_test.dart`;
  - `apps/mobile/test/goldens/design/pre_trip_goldens_test.dart`, in both digit styles.

  Pair the buy chip with the dialog, not the shop (R20). Review the goldens.
- [X] T048 [US2] Add the card to `apps/mobile/test/a11y/` minimum sizes (SC-006).

**Checkpoint**: Home → card → trip works, and the card setting applies.

---

## Phase 5: User Story 3 - The pay, the stars and what went wrong (Priority: P1)

**Goal**: The result screen, from the trip's own result: stars with conditions, the quote, the
breakdown, the mistakes card, the pay, the apartment bar and the next step.

**Independent Test**: Over every finished parity fixture, every figure equals the recorded result.
«مشوار تاني» opens the next trip's card, and back opens Home.

### Tests for User Story 3 ⚠️

- [X] T049 [P] [US3] Write `apps/mobile/test/features/result/domain/summary_test.dart` (research R15):
  - the star rows from `starFlags` (`reached`, `noFights`, `noMistakes`);
  - the breakdown;
  - one mistake line per `mistakes` entry, with the look, `labelKey`, `feminine`, the kind and the
    amount, plus count lines for fights, missed stops and lost fares;
  - the amount's size select: `half` for 50, `one` for 100, `other`;
  - the summary family: fights cost the second star and the third; mistakes only cost the third;
    losses only cost no star. Each with its plurals;
  - `firstThreeStars` = `stars == 3 && bestStarsBefore < 3`;
  - the doubled pay when `lastResult.doubled` for this start;
  - nothing computed from anything else.
- [X] T050 [P] [US3] Write `apps/mobile/test/features/result/domain/quote_test.dart` (research R14):
  - the pick order: the last `thanks` or `tip`; else the last `pays`, `pays_group` or `pays_rest`
    from a passenger who never said `short_change`, `fight` or `accused`; else none;
  - the same quote after a kill and rebuild (M02's kill/rebuild helpers);
  - the replay ends on the record's `TripResult`;
  - the longest-trip stress fixture replays in under 150 ms (skipped under coverage, like the other
    budgets).
- [X] T051 [P] [US3] Write
  `apps/mobile/test/features/trip/application/trip_controller_result_args_test.dart`.
  A finished trip exits with `ExitToResult(tripId, ResultArgs)`. `bestStarsBefore` and
  `jenehatBefore` are read just before `recordResult`. A rebuild that finds a recorded result builds
  the same args, and a resumed result may skip the celebration by design.
- [X] T052 [P] [US3] Write `apps/mobile/test/features/result/result_screen_test.dart`
  (contracts/result.md):
  - for every `fixtures/parity/*.json` with `outcome == finished`, every figure equals the recorded
    result (SC-004);
  - without args: only `lastResult`'s pay, with the stars, quote, breakdown, mistakes and share
    hidden;
  - nothing kept → `/home`;
  - «مشوار تاني» with fuel and on an empty tank;
  - M07's «كمّل» (key `first-session-continue`) in «مشوار تاني»'s place during the first session
    and once after trip 5, with `tutorialContent()`;
  - back and system back → `/home`;
  - the celebration on a first three stars;
  - the apartment card (FR-043): the same target as Home's savings card; the bar runs from
    `jenehatBefore` to the balance now, with this trip's gain marked; «فاضلك {n} ج» while short,
    «تقدر تشتري {item}!» when the pay made it affordable; the chapter goal before the apartment
    opens; a tap opens `/apartment`. Without `ResultArgs`, the card shows the current balance with
    no gain marked;
  - reduced motion: final values, no bounce, burst or count-up;
  - `lastFinishedTripProvider` set on open.
- [X] T053 [P] [US3] Write
  `apps/mobile/test/features/trip/presentation/restart_unchanged_test.dart` (research R17,
  Clarifications Q2). «عيد المشوار» on the pause and failure cards still restarts the same trip
  directly for a liter, with no card, story and tutorial trips included.

### Implementation for User Story 3

- [X] T054 [US3] Create `apps/mobile/lib/features/result/domain/result_args.dart` (`ResultArgs` with
  `result`, `startTxn`, `replay`, `bestStarsBefore` and `jenehatBefore`). Then:
  - in `apps/mobile/lib/features/trip/application/trip_phase.dart`, `ExitToResult(tripId, args)`;
  - in `trip_controller.dart`, build the args on finish and on a rebuild;
  - in `presentation/trip_screen.dart`, `router.pushReplacement('/trip/$tripId/result', extra:
    args)`.

  T051 passes.
- [X] T055 [P] [US3] Add the `feminine` flag to `apps/mobile/lib/features/trip/domain/looks.dart`
  (`hagga`, `bags_lady`, `mother_kids`). Create
  `apps/mobile/lib/features/result/domain/summary.dart` (`ResultSummary`, `MistakesSummary`) and
  `quote.dart` (`pickQuote(ReplayRecord) → Quote?`, through `TripEngine.start` and the logged
  commands in `playLog`'s order). T049 and T050 pass.
- [X] T056 [US3] Create `apps/mobile/lib/features/result/application/`:
  - `result_model.dart`: `resultModelProvider(tripId, args)`. It sets `lastFinishedTripProvider`
    for a finished trip's args;
  - `quote_provider.dart`: a `FutureProvider` keyed by the start id, running
    `Isolate.run(() => pickQuote(record))`;
  - `result_slots.dart`: `resultDoubleSlotProvider` and `resultTaskSlotProvider` (null), and
    `storyAfterResultProvider` (no-op).
- [X] T057 [US3] Create `apps/mobile/lib/features/result/presentation/`:
  - `result_screen.dart`;
  - `result_stars.dart`: `wassal.riv`'s `Stars` artboard through `RiveArtView`, with `stars` = the
    count; labels fading in `DesignExtras.starLabelStagger` apart. The static `Stars` component at
    58/72/58 under reduced motion, without the file, and in goldens. Group label
    `resultA11yStars(count)`;
  - `quote_card.dart`: `PassengerAvatar(look, 50)`, two lines then an ellipsis, fading in when the
    quote arrives;
  - `breakdown_card.dart`;
  - `mistakes_card.dart`: a disclosure, with `PassengerAvatar(look, 38)` on `danger.soft`;
  - `pay_block.dart`: counts up over `DesignExtras.payCountUp`;
  - `apartment_card.dart`: the bar from `jenehatBefore` to now over `DesignExtras.aptBarFill`,
    after the pay; «فاضلك {n} ج» or «تقدر تشتري {item}!».

  The celebration plays the `Confetti` artboard and M02's `horn` cue once, gated by the sound
  setting, with «رقم قياسي جديد».
- [X] T058 [US3] Place the bottom row in `result_screen.dart`:
  - M07's `FirstSessionContinue(tripId)` whenever it shows;
  - otherwise «مشوار تاني» with «−١ لتر» (hidden in a window), through `storyAfterResultProvider`
    and then `startNextTrip(from: StartFrom.result)`;
  - the share button's place, filled in US5.
- [X] T059 [US3] In `apps/mobile/lib/core/routing/router.dart`, build `ResultScreen(tripId, args)`
  for `/trip/:tripId/result`, accepting a `ResultArgs`, a bare `TripResult` or nothing. Delete the
  placeholder branch and `apps/mobile/lib/features/trip/presentation/playtest/result_summary.dart`.
  T052 passes, and so does M07's `integration_test/first_session_test.dart`.
- [X] T060 [P] [US3] Add the `result*` and `mistake*` keys to `apps/mobile/lib/l10n/app_ar.arb`: the
  drafts of research R18, with ICU plurals (one, two, few, other), the `size` select and the
  `feminine` select. Include the a11y labels: back «ارجع الموقف», the stars group, «شارك النتيجة».
  The decline link's hit area is 44 even though it is drawn 36 high.
- [X] T061 [US3] Add the `Result` design checks:
  - `apps/mobile/test/design/samples/result.dart`, with fake task and ×2 slots;
  - `apps/mobile/test/design/result_layout_test.dart`, at 390×1100 as one tall surface. The
    mistakes summary is app-only;
  - `apps/mobile/test/goldens/design/result_goldens_test.dart`, in both digit styles.

  Review the goldens.
- [X] T062 [US3] Add the result to `apps/mobile/test/a11y/` minimum sizes (SC-006).

**Checkpoint**: The MVP loop: Home → card → trip → result → next card, with the first session
handled.

---

## Phase 6: User Story 4 - Home tells the truth about the player's state (Priority: P2)

**Goal**: Out of fuel, offline, maintenance, the early chapter, the unlimited window and the
first-session fuel lesson, each on Home without leaving it.

**Independent Test**: Run through each state as `HomeStates` draws it, and each transition back.

### Tests for User Story 4 ⚠️

- [X] T063 [P] [US4] Write `apps/mobile/test/features/home/home_states_test.dart` (contracts/home.md
  "States"):
  - out of fuel: `AppButton.danger` «البنزين خلص» with «اللتر الجاي {mm:ss}», the pill's empty
    style, both opening the fuel sheet;
  - a liter back turns it back without leaving Home;
  - offline: the banner announced once, the scene 332 → 282 at 844 pt, the shop tab and BONAT pill
    disabled with «محتاج نت», trips still start;
  - the network back;
  - maintenance in the banner's place, with trips working;
  - the early chapter: the goal card and the tuktuk with بلية;
  - the unlimited window: no «−١», and the window's time left;
  - the fuel lesson due: «يلا نطلع!» on an empty tank, going to `/trip/<id>`;
  - no next trip: the button disabled.
- [X] T064 [P] [US4] Extend `apps/mobile/test/core/theme/components/nav_story_test.dart`:
  `BottomNav.disabled` draws the cell at 0.45 opacity, ignores taps and exposes `enabled: false`
  with «المحل، محتاج نت».

### Implementation for User Story 4

- [X] T065 [US4] Add `disabled` (`List<bool>`) to `BottomNav` in
  `apps/mobile/lib/core/theme/components/nav.dart`. In
  `apps/mobile/lib/core/routing/shell_scaffold.dart`, pass the shop tab as disabled while
  `serverStatusProvider` says offline, on every tab. T064 passes.
- [X] T066 [US4] Complete `start_button.dart` (normal, empty, unlimited; a 150 ms crossfade, none
  under reduced motion), the fuel pill's empty and unlimited styles, and the BONAT pill's offline
  state (`onTap: null`, disabled semantics, the same label) in
  `apps/mobile/lib/features/home/presentation/`.
- [X] T067 [US4] In `home_screen.dart`, animate the scene card's shrink under `HomeStatusArea`'s
  banner or maintenance card over 200 ms `easeOut` (none under reduced motion). Finish
  `savings_card.dart`'s chapter-goal variant: the icon, title, «الفصل {n}», the lock with
  «الشقة بتتفتح في الفصل {n}», the progress and its bar; and «مشهد جديد مستنيك» when
  `storySceneWaiting`. T063 passes.
- [X] T068 [US4] Add the `HomeStates` design checks, with out of fuel, offline and chapter 2
  together, as drawn:
  - `apps/mobile/test/design/samples/home_states.dart`;
  - `apps/mobile/test/design/home_states_layout_test.dart`;
  - `apps/mobile/test/goldens/design/home_states_goldens_test.dart`, in both digit styles.

  Review the goldens.

**Checkpoint**: Every Home state is honest and recovers by itself.

---

## Phase 7: User Story 5 - Share a result as a picture (Priority: P3)

**Goal**: A 1080×1080 picture of the result, through the phone's share sheet, offline too.

**Independent Test**: Tap share and check the picture against `ShareCard`: size, content, both digit
styles. Do it offline too.

### Tests for User Story 5 ⚠️

- [X] T069 [P] [US5] Write `apps/mobile/test/features/result/share_action_test.dart`, with a fake
  `ShareGateway`:
  - a 1080×1080 PNG named `wassal_result_<trip_id>.png`;
  - the caption;
  - no quote card when there is no quote, with the stars centred;
  - Western digits;
  - the doubled pay;
  - offline;
  - a second tap while sharing is ignored;
  - an error shows the neutral retry toast and changes nothing.

### Implementation for User Story 5

- [X] T070 [P] [US5] Create `apps/mobile/lib/core/platform/share_gateway.dart`:
  `ShareGateway.shareImage(Uint8List png, {required String fileName, String? text})`,
  `SharePlusGateway` over `share_plus` with `XFile.fromData(png, mimeType: 'image/png', name:
  fileName)`, and `shareGatewayProvider`. Add `apps/mobile/test/helpers/fake_share_gateway.dart`.
- [X] T071 [US5] Create `apps/mobile/lib/features/result/presentation/share_card.dart`: the 360×360
  `ShareCard`, with the `sun` background and two `sun.glow` circles, the trip chip, the title at 34
  with the `sun.lip` shadow, static stars 48/62/48 with an `ink` outline, the quote card or none,
  the wordmark and «قبضت {amount}». Then create `share_action.dart`:
  1. pre-cache the SVGs;
  2. insert an off-screen `OverlayEntry` in a `RepaintBoundary`;
  3. await `endOfFrame`;
  4. `toImage(pixelRatio: 3)` and encode a PNG;
  5. remove the entry;
  6. call the gateway.

  Add a `// M15: share {kind: result_image}` comment at the call site.
- [X] T072 [US5] Add the share button to `result_screen.dart`, hidden without `ResultArgs`, and the
  `share*` keys (the caption draft of research R18) to `apps/mobile/lib/l10n/app_ar.arb`. T069
  passes.
- [X] T073 [US5] Add the `ShareCard` design checks at 360×360 in both digit styles:
  - `apps/mobile/test/design/samples/share_card.dart`;
  - its layout test;
  - `apps/mobile/test/goldens/design/share_card_goldens_test.dart`.

**Checkpoint**: Sharing works offline.

---

## Phase 8: User Story 6 - Testers keep their tools (Priority: P3)

**Goal**: The testers' tools behind a debug button on Home, on dev and staging only.

**Independent Test**: On staging, the debug button opens the trip list, the sync card and the
first-session card. On prod, none of them exists.

### Tests for User Story 6 ⚠️

- [X] T074 [P] [US6] Write `apps/mobile/test/features/home/debug_entry_test.dart`:
  - with `Flavor.dev` and `Flavor.staging`, the button opens a sheet with `TripList` (each trip
    opening `/trip/<id>` directly, with no card and no checkpoint), `SyncStatusCard`,
    `OnboardingCard` and `GalleryEntry`;
  - with `Flavor.prod`, neither the button nor the sheet exists.

### Implementation for User Story 6

- [X] T075 [US6] Create `apps/mobile/lib/features/home/presentation/debug_sheet.dart`: a modal
  `AppSheet` with `TripList`
  (`apps/mobile/lib/features/trip/presentation/playtest/trip_list.dart`), `SyncStatusCard` and
  `OnboardingCard` (`apps/mobile/lib/features/dev/`), and `GalleryEntry`. Add the 44 pt
  `IconCircleButton`, with M02's debug glyph, at the scene card's top-start corner while
  `flavorProvider != Flavor.prod`. T074 passes.

**Checkpoint**: All six stories work.

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: The integration tests, the documents, the full checks, the reviews and the owner's list.

- [X] T076 Write `apps/mobile/integration_test/home_loop_test.dart`, headless like M07's (`-d
  flutter-tester`). It runs offline, for a player whose tutorial is done:
  1. Home shows the next trip;
  2. «يلا نطلع!» → the card → «اطلع»;
  3. the trip, finished by M02's scripted player;
  4. the result's figures checked;
  5. «مشوار تاني» → the next card → close → Home, whose line card moved.

  It also times SC-002 with a real `Stopwatch`: from the result's back tap to Home's first frame
  with the new figures, and from a tab switch back to Home. Each is under 1 s. The cold start to
  Home stays the device pass's (T088).
- [X] T077 Extend `apps/mobile/integration_test/first_session_test.dart` past trip 5. Home shows
  FR-010's next trip, and «يلا نطلع!» opens its card: step 7's "onboarding through the first 5
  trips".
- [X] T078 [P] Update `docs/product-spec.md` «أنواع الركاب»: أبو سمّاعة's row drops
  «أو تلف الفلوس حواليه» (Clarifications Q3).
- [X] T079 [P] Update `docs/delivery-plan.md`:
  - HANDOFF §9.3 #4 settled as "no" in 013, in the "Before M07" row and step 7's Resolve list;
  - the Progress line for `013-m08-home-result` when it merges.
- [X] T080 [P] Update `docs/architecture-mobile.md`:
  - §2: `share_plus` used;
  - §5: the `features/{home,pre_trip,result}/` and `core/progress/domain/` trees;
  - §6: `ShareGateway` among the plugin interfaces;
  - §9: no route change, and Home's arrival queue;
  - §13: the phone's unlock rules.
- [X] T081 [P] Update `CLAUDE.md`:
  - "Project status": M08's line;
  - the guards line: the new domain folders;
  - `ShareGateway` and `pref.pre_trip_card`;
  - the mobile commands table: `fvm flutter test integration_test/home_loop_test.dart -d
    flutter-tester`.
- [X] T082 Add M08's section to `docs/owner-actions.md`, each item with its task ID, and update
  "Open now":
  - **Before merge:** T083 and T084, and the Codemagic and review steps of T086;
  - **After merge:** T088 and T089.
- [ ] T083 **Owner approval** of the strings in research R18:
  - the 19 «جديد» names and sentences;
  - the goal titles;
  - the mistake lines and the three summary families;
  - the barker's call;
  - the rule line for discounts other than 50%;
  - the share caption.

  Apply any changes in `apps/mobile/lib/l10n/app_ar.arb` and regenerate the goldens they touch.
- [ ] T084 **Owner approval** of the three departures (plan "Complexity Tracking": R7, R11, R4) and
  the expected golden differences (research R20): the barker, riders and painted street, the event
  icons that reuse glyphs, the full vehicle name and the minute-only label.
- [X] T085 Run CI's mobile commands in CLAUDE.md's order, in `apps/mobile/`, and fix anything they
  find:
  1. `fvm flutter pub get`;
  2. `fvm dart run build_runner build -d`;
  3. the Rive Linux setup (`fvm dart run rive_native:setup --verbose --clean --platform linux`);
  4. the format check;
  5. `fvm flutter analyze --fatal-infos`;
  6. `fvm flutter test --coverage --exclude-tags backend`;
  7. `fvm dart run tool/check_coverage.dart --min 80`;
  8. both integration tests, headless;
  9. `fvm flutter test --tags rive`.

  Also run `uv run ruff check . && uv run ruff format --check .` in `backend/` for T007's comments.
- [ ] T086 **Owner, before merge:**
  - run Codemagic's `ios-dev-unsigned` with `share_plus`, and confirm there is no Podfile and the
    share sheet opens on a sideloaded device (quickstart §8);
  - review the five artboards' side-by-side images (quickstart §4).
- [X] T087 Run the reviews, fix CRITICAL and HIGH findings, then rerun T085:
  - `flutter-reviewer` over the Dart diff: rebuild scope, `mounted` after awaits in
    `startNextTrip`, the share flow, the arrival queue, and the timer's disposal;
  - `security-reviewer` over the share flow (the file written, nothing leaked in logs) and the
    changes to M07's name and scene flows.
- [X] T090 Fix the preference store's allowlist, found on the owner's phone after T087. Add
  `pref.pre_trip_card` (this feature's, which crashed the first start from Home) and
  `update.dismissedVersion` (M06's, already on `master`: every bootstrap on a phone threw at its
  end, so the pack check after it never ran) to `SharedPrefsSettingsStore.keys`. Make
  `test/helpers/memory_settings_store.dart` refuse unlisted keys as `SharedPreferencesWithCache`
  does, so a new preference fails its tests until it is listed. In this PR, by the owner's choice;
  the PR description says so.
- [ ] T088 **Owner, after merge:** the device pass of quickstart §7 on the Redmi Note 7, or the
  Galaxy A06 when available, covering SC-002, SC-003 and SC-010 and the arrival check.
- [ ] T089 **Owner, after merge:** the 10-player playtest for SC-008 and SC-009. Do 8 of 10 know
  which star they missed and why, from the result alone? Do 8 of 10 who meet a new type know what it
  does from the card?

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: none.
- **Foundational (Phase 2)**: after Setup. Blocks every story. Within it:
  - the guards and tests T003–T005 come first;
  - the unlock rules (T006–T008) and M07's members (T009) run side by side;
  - the components (T010–T012) are independent of both.
- **US1 (Phase 3)**: after Foundational. Its card link opens the existing card route until US2.
- **US2 (Phase 4)**: after Foundational. T042 edits US1's `start_next_trip.dart` (T023).
- **US3 (Phase 5)**: after Foundational. «مشوار تاني» needs `startNextTrip` (T023), and the
  integration check at T059 needs US1's Home.
- **US4 (Phase 6)**: after US1 (Home's screen and button).
- **US5 (Phase 7)**: after US3 (the result screen).
- **US6 (Phase 8)**: after US1. It must land in the same PR as T030, which removes the playtest Home.
- **Polish (Phase 9)**: after the stories. T083 and T084 can start as soon as their strings and
  goldens exist.

### Within Each User Story

- Tests first, and failing, before implementation.
- Domain (pure), then application (providers), then presentation, then the router.
- Shared files (Organization) in task order.

### Parallel Opportunities

- **Setup:** T002 beside T001.
- **Foundational:** T003, T004, T005 and T010; then T006 and T009.
- **US1:** the tests T013–T019; then T020, T021, T026, T027, T028 and T031.
- **US2:** the tests T034–T039; then T040, T041 and T046.
- **US3:** the tests T049–T053; then T055 and T060.
- **US2 and US3** can run side by side after US1's T023, since they touch different feature folders.
  Their shared files are `router.dart` (T044 vs T059) and `app_ar.arb` (T046 vs T060), done in order.
- **Polish:** the documents T078–T081.

---

## Parallel Example: Foundational tests

```text
T003 test/repo/domain_imports_test.dart
T004 test/core/progress/unlocks_test.dart
T005 test/features/onboarding/domain/first_session_test.dart
T010 test/core/theme/components/passenger_avatar_test.dart
```

## Parallel Example: User Story 1

```text
T013 test/features/home/domain/next_trip_test.dart
T014 test/features/home/domain/savings_target_test.dart
T015 test/features/home/domain/line_card_test.dart
T016 test/features/home/trusted_countdown_test.dart
T017 test/features/home/arrival_queue_test.dart
T018 test/features/onboarding/arrival_items_test.dart
T019 test/features/home/{street_scene,home_screen}_test.dart
```

## Parallel Example: User Story 3

```text
T049 test/features/result/domain/summary_test.dart
T050 test/features/result/domain/quote_test.dart
T051 test/features/trip/application/trip_controller_result_args_test.dart
T052 test/features/result/result_screen_test.dart
T053 test/features/trip/presentation/restart_unchanged_test.dart
```

---

## Implementation Strategy

### MVP First (User Stories 1–3)

1. Phase 1 and Phase 2.
2. Phase 3 (US1): Home and the next trip, with M07's arrival items.
3. Phase 4 (US2): the card.
4. Phase 5 (US3): the result.
5. **Stop and validate**: Home → card → trip → result → next card on a dev build, and the first
   session through M07's `first_session_test`.

### Incremental Delivery

1. US1–US3: the loop, the MVP.
2. US4: Home's honest states.
3. US5: sharing.
4. US6: the testers' tools. Required before the PR is opened, since US1 removes the playtest Home.
5. Polish: the integration tests, the documents, the checks, the reviews and the owner's approvals.
