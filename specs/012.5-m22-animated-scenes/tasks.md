---

description: "Task list for M22 Animated Scenes"
---

# Tasks: Animated Scenes (M22)

**Input**: Design documents from `specs/012.5-m22-animated-scenes/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**:

- **Mandatory, and first** (constitution XIII). Every phase writes its tests first, and they must
  fail before its implementation tasks start. The pure parts (`PanelTurns`, `panelTalkers`, the
  contracts) are unit-tested before any widget uses them.
- **The real file.** Tests tagged `rive` decode the committed `.riv` files with `Factory.flutter`.
  They need Rive's Linux library
  (`fvm dart run rive_native:setup --verbose --clean --platform linux`), which CI installs before
  `flutter test`, so they run in CI with the rest.
- **Without Rive's library.** The turn tests override `scenePanelsProvider`, so they run anywhere.
  The art then falls back to the drawing while the turns still run.
- **Coverage.** At least 80% of lines in `apps/mobile` (`tool/check_coverage.dart --min 80`).

**Organization**:

- **Paths** are from the repository root. Dart commands run with `fvm` in `apps/mobile/`.
- **Codegen.** After a `@riverpod` provider: `fvm dart run build_runner build -d`.
- **Exactness.** Every number is from the contracts. Name each as a constant in `lib/`, never a bare
  literal:
  - the panels: 358×540, the machine and view model `Panel`, the Booleans `moallem`, `usta`,
    `belya`, `salma`;
  - the drawing fit: `Fit.cover`, `Alignment.bottomCenter`;
  - the turns: `leadIn` = `MotionTokens.sheetIn` (280 ms), 60 ms a letter, at least 1200 ms, at most
    4000 ms, a 300 ms pause (`SceneTurnTokens`, research R5);
  - the bubble pop: `MotionTokens.bubblePop` (180 ms, `EaseOutBack(1.4)`, from 0.6), at most two
    bubbles;
  - the file budget: 100 KB;
  - the scene frame rate: an average of at least 55 fps, no one-second window under 45 fps, memory
    under 300 MB.

  Durations live in `lib/core/theme/tokens/` (the duration guard), never in `features/`.
- **Names** are the contracts', spelled exactly:
  - the six panel slugs;
  - the eleven building blocks (`Character_usta`, `Character_moallem`, `Character_belya`,
    `Character_salma`, `Prop_tin`, `Prop_key`, `Prop_drawer`, `Prop_busstop`, `Prop_books`,
    `Prop_bag`, `Tuktuk`);
  - the four export artboards (`Artboard 1`, `Watermark`, `NuRiveBrandmark01`, `NuRiveWordmark01`);
  - the three aliases (`ch1_stand_morning`, `ch1_salma_asks`, `ch1_usta_dreams`).
- **Shared files.** These grow phase by phase, so tasks that touch them run in order:
  - `apps/mobile/lib/core/art/{rive_art.dart,panel_art.dart}`;
  - `apps/mobile/lib/features/onboarding/presentation/scene_player.dart`;
  - `apps/mobile/test/core/art/{panel_art_test.dart,rive_scenes_contract_test.dart,rive_scenes_talk_test.dart}`;
  - `apps/mobile/test/features/onboarding/domain/panel_turns_test.dart`;
  - `apps/mobile/test/features/onboarding/presentation/scene_turns_test.dart`.
- **One PR.** No security review: no network call, no stored or personal data, no new input (plan
  "Security & privacy"). A code review runs in Polish.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story the task belongs to (US1–US3 from spec.md)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: The two art files and the draft's scene, ready for the tests.

- [X] T001 Check the art in `apps/mobile/assets/rive/` (research R1, R12):
  - `wassal_scenes.riv`, staged, 49,610 bytes;
  - the owner's updated `wassal.riv`, 86,100 bytes, sha256 `04aa5f568872233bcaaac5fe62498de431dd27a43e6f50777a4a5c90e6423db0`.

  `pubspec.yaml` already declares `assets/rive/`, so nothing changes there. Then update
  `apps/mobile/assets/rive/README.md` for both files: what each holds, their contracts
  (`specs/008.5-m21-design-refresh/contracts/rive-characters.md` and
  `specs/012.5-m22-animated-scenes/contracts/rive-scenes.md`), that both are free-plan exports whose
  editable sources are in the owner's Rive account, and that the app opens artboards by name.
- [X] T002 [P] Create `apps/mobile/test/fixtures/tutorial/first_sight.json` (research R11):
  - copy the `first_sight` scene object (`scene_id`, `plays`, `panels`) verbatim from
    `/mnt/endeavour/home/saied-dev/Work/wasal_ogra-core-r1/content/drafts/core-r1/pack/chapters/ch1_first_job.json`;
  - its `ch1_usta_dreams` must have two usta lines, the second «بس الأول لازم أركّز في الأجرة» (spec
    Clarifications Q2);
  - add it to `apps/mobile/test/fixtures/tutorial/README.md`: the source, the date (2026-10-28), and
    that it is copied by hand when the draft's scene changes;
  - add `draftFirstSight()` to `apps/mobile/test/helpers/tutorial_content.dart`, returning
    `Scene.fromJson` of the file.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Both files decoded and checked at boot, each against its own contract, and drawable from
either file. Every story needs this.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Tests for the foundation ⚠️ (write first, must fail)

- [X] T003 [P] Create `apps/mobile/test/core/art/rive_contract_test.dart` (data-model.md
  `RiveContract`, contracts/rive-scenes.md "The contract"):
  - for both `riveCharacterContract` and `sceneContract`, "`artboards` and `known` are disjoint";
  - `riveCharacterContract` holds 008.5's `riveArtAsset`, `riveContract` and `riveExportArtboards`;
  - `sceneContract.asset` is `assets/rive/wassal_scenes.riv`, and its `artboards` are exactly the
    six slugs, each 358×540 with machine `Panel`, view model `Panel` and exactly four
    `DataType.boolean` properties `moallem`, `usta`, `belya`, `salma`;
  - `sceneContract.known` is exactly the eleven building blocks and the four export artboards;
  - `loadRiveArt(contract: sceneContract, asset: 'assets/rive/missing.riv')` gives `RiveArt.none`
    whose problem starts with `assets/rive/missing.riv:` and a space.
- [X] T004 [P] Create `apps/mobile/test/core/art/rive_scenes_contract_test.dart`, tagged `rive`,
  modelled on `test/features/trip/rive_art_contract_test.dart` (contracts/ci-checks.md "Rive tests"):
  - the bytes are under 100 KB, and the file decodes with `Factory.flutter`;
  - each panel has its size, its machine `Panel` and its default view model `Panel` with the four
    Booleans;
  - the artboards `artboardAt` finds are exactly `sceneContract.artboards` plus `.known`;
  - `checkRiveArt(file, sceneContract)` makes all six usable with no problem;
  - `loadRiveArt(contract: sceneContract)` loads from the bundle in `tester.runAsync`, as boot does;
  - a `check` that throws gives `RiveArt.none` with the error.
- [X] T005 [P] Extend `apps/mobile/test/core/art/rive_art_view_test.dart`:
  - a view with `source: RiveArtSource.scenes` reads `RiveArtScope.scenes`. With only `art` set it
    draws its fallback; with the scenes file decoded it draws a `RiveWidget`;
  - `alignment` reaches the `RiveWidget`;
  - every existing case passes unchanged.
- [X] T006 [P] Extend `apps/mobile/test/bootstrap/boot_progress_test.dart`:
  - step `art` completes only after both `riveArtProvider` and `riveScenesProvider` have resolved;
  - it still completes, and the boot goes on, when the scenes file is missing
    (`loadRiveArt(contract: sceneContract, asset: 'assets/rive/missing.riv')`).

### Implementation for the foundation

- [X] T007 Generalize the loader in `apps/mobile/lib/core/art/rive_art.dart` (contracts/rive-scenes.md
  "Loading", data-model.md `RiveContract` and `RiveArt`):
  - add `RiveContract` (`asset`, `artboards`, `known`), with an assert that "`artboards` and `known`
    are disjoint";
  - add `riveCharacterContract` from today's constants, and keep `riveArtAsset`, `riveContract` and
    `riveExportArtboards` as they are;
  - `checkRiveArt(rive.File file, [RiveContract? contract])` and `loadRiveArt({RiveContract?
    contract, String? asset, AssetBundle? bundle, RiveArt Function(rive.File file)? check})`:
    - a `null` contract means the characters file;
    - `asset` overrides the contract's;
    - `check` keeps its one argument and defaults to checking against the contract;
  - add `RiveArt.contract` (`RiveContract?`, `null` meaning the characters file), set by
    `checkRiveArt`;
  - start every problem with the asset's path, a colon and a space (`assets/rive/wassal_scenes.riv: …`), as the
    loader's own problems already do (008.5's `boot_progress_test` checks it).

  T003's characters part passes, and 008.5's tests (`rive_art_contract_test`,
  `rive_art_goldens_test`, `passenger_art_test`, `rive_art_view_test`) pass unchanged.
- [X] T008 Create `apps/mobile/lib/core/art/rive_scenes.dart` (contracts/rive-scenes.md, research R2,
  R3):
  - `riveScenesAsset`;
  - `sceneContract`, with the six panel specs and the fifteen known artboards;
  - `@Riverpod(keepAlive: true) Future<RiveArt> riveScenes(Ref ref)`, which loads `sceneContract`
    and disposes the file with the provider;
  - `ScenePanels`, with `bool animates(String artSlug)`: a file, and the artboard passed;
  - `@riverpod ScenePanels scenePanels(Ref ref)`, built from `riveScenesProvider`'s value. With no
    value yet, nothing animates.

  Run `build_runner`. T003 and T004 pass.
- [X] T009 Extend `RiveArtScope` and `RiveArtView` in `apps/mobile/lib/core/art/rive_art.dart`
  (contracts/rive-scenes.md "Drawing"):
  - `enum RiveArtSource { characters, scenes }`;
  - the scope holds `art` and `scenes`. `maybeOf(context, [RiveArtSource source =
    RiveArtSource.characters])` picks one, and `updateShouldNotify` compares both;
  - `RiveArtView` gains `source` (default `characters`) and `alignment` (default
    `Alignment.center`), which go to `RiveWidget`;
  - the view reads its spec from `(art.contract ?? riveCharacterContract).artboards[artboard]`.

  T005 passes.
- [X] T010 Wire boot and the app:
  - `apps/mobile/lib/bootstrap/startup.dart`: `BootStep.art: Future.wait([ref.watch(riveArtProvider.future),
    ref.watch(riveScenesProvider.future)])`. Update the doc comments: the step can't fail, and
    `retryAppStartup` keeps both files;
  - `apps/mobile/lib/bootstrap/app.dart`: `RiveArtScope(art: …, scenes:
    ref.watch(riveScenesProvider).value, …)`.

  T006 passes.
- [X] T011 Keep every test that doesn't ask for the scenes file off it. M07's tests then stay
  unchanged, and give the same result whether or not CI's Rive library could decode the file
  (FR-022):
  - in `apps/mobile/test/helpers/trip.dart`, add `riveScenesProvider.overrideWith((ref) async =>
    const RiveArt.none())` to `tripTestOverrides`, beside `riveArtProvider`'s. `pumpWassalApp`
    uses it, so every app-level test gets it;
  - in `apps/mobile/test/helpers/design_component.dart`, `pumpDesignComponent` puts the same
    override before the caller's `overrides`, as it does for `hapticsProvider`. M07's
    `scene_player_test.dart`, `intro_layout_test.dart` and the onboarding goldens go through it;
  - tests that want turns override `scenePanelsProvider`, never `riveScenesProvider`, so no provider
    is overridden twice;
  - give any other test that overrides `riveArtProvider` the same override beside it
    (`grep -rn "riveArtProvider.overrideWith" apps/mobile/test apps/mobile/integration_test`);
  - `integration_test/first_session_test.dart` keeps the real files (T046).
- [X] T012 [P] Add `PanelArt.artFor(String slug)` to `apps/mobile/lib/core/art/panel_art.dart`: a
  const `_aliases` map, empty until US3 (T038), and the slug itself otherwise. `assetFor` resolves
  through it. M07's `test/core/art/panel_art_test.dart` passes unchanged.

**Checkpoint**: both files load at boot, each is checked against its contract, and
`RiveArtView(source: scenes)` can draw a panel. Nothing visible has changed yet.

---

## Phase 3: User Story 1 - The opening comes alive (Priority: P1) 🎯 MVP

**Goal**: The opening's panels play as animations, and each line's speaker talks in turn while their
bubble goes up.

**Independent Test**: A dev build with the file, reduced motion off, the playtest «Onboarding» card →
the opening:

- every panel moves by itself;
- in `opening_stand`, المعلم's bubble appears and he talks, then the usta's appears and he talks;
- «يلا» before the last line shows the rest, and the next «يلا» moves on.

### Tests for User Story 1 ⚠️ (write first, must fail)

- [X] T013 [P] [US1] Create `apps/mobile/test/features/onboarding/domain/panel_turns_test.dart`
  (data-model.md "Turns", contracts/scene-turns.md "The schedule"):
  - "`turns[0].start == leadIn`, and `turns[i + 1].start == turns[i].end + pause`";
  - "`turn.end − turn.start == clamp(perLetter × letters, min, max)`, where letters are the line's
    non-white-space grapheme clusters";
  - "No two turns overlap, and the starts strictly increase";
  - the `narrator` line takes no turn;
  - `at()` through a panel:
    - before the first turn: `shown 0`, `talking null`, `lastStarted false`;
    - inside a turn: its speaker;
    - in a pause: `talking null`;
    - after the last: all shown, `talking null`, `lastStarted true`;
  - "For a panel with no spoken lines, `at` gives `shown 0`, `talking null` and `lastStarted true`";
  - `TurnsAt` equality: two results with the same three fields are equal and share a `hashCode`, and
    `at()` at two times inside one turn gives equal results;
  - the same speaker twice;
  - a line with shadda («لمّ») counts its cluster once;
  - `TurnTimings` rejects anything but "`min ≤ max`, every value ≥ 0";
  - with `TurnTimings(leadIn: 280 ms, perLetter: 60 ms, min: 1200 ms, max: 4000 ms, pause:
    300 ms)`, the sample's `opening` ends at 2980 ms (`opening_key`), 4000 ms (`opening_stand`) and
    3280 ms (`opening_go`) (research R5).
- [X] T014 [P] [US1] Create `apps/mobile/test/core/art/panel_talkers_test.dart` (data-model.md
  `panelTalkers`):
  - `moallem`, `usta`, `belya` and `salma` each turn on only their own Boolean;
  - `null`, `narrator` and `bride_father` give four falses;
  - the map always has exactly the four keys.
- [X] T015 [P] [US1] Extend `apps/mobile/test/core/theme/components/nav_story_test.dart`
  (`ComicPanel`, contracts/scene-turns.md "Bubbles"):
  - `shown: null` is M07's panel;
  - with two lines and `shown: 1`, the second bubble:
    - has the same rect as with `shown: 2`;
    - is invisible, and takes no touch;
    - keeps its text in the semantics tree;
  - when `shown` goes from 1 to 2, the second bubble pops: its scale is under 1 just after, and 1
    after `MotionTokens.bubblePop`;
  - under reduced motion it appears at once;
  - with three lines and `shown: 3`, only the last two bubbles show.
- [X] T016 [P] [US1] Extend `apps/mobile/test/core/art/panel_art_test.dart` (contracts/rive-scenes.md
  "Panel art"):
  - `animate: true` with no scope draws the drawing;
  - `animate: true` builds `RiveArtView(source: RiveArtSource.scenes, artboard: artFor(slug), fit:
    Fit.cover, alignment: Alignment.bottomCenter)`, with the drawing as its fallback;
  - `animate: false` is M07's behaviour;
  - `PanelArt.bindTalkers(talking)`, tried against a fake `ViewModelInstance` (as
    `test/features/trip/presentation/passenger_art_test.dart` fakes one), sets all four Booleans
    from `panelTalkers`: `usta` turns on only `usta`, and `null` turns all four off.
- [X] T017 [P] [US1] Create `apps/mobile/test/features/onboarding/presentation/scene_turns_test.dart`,
  built like M07's `scene_player_test.dart` on the sample's `opening`, with `scenePanelsProvider`
  overridden to animate every panel (contracts/scene-turns.md):
  - every spoken line of the opening, as one table. At the turn's start, its middle and 1 ms before
    its end, `PanelArt.talking` is the speaker; at its end it is `null`:
    - `opening_key`: المعلم 280–2980 ms;
    - `opening_stand`: المعلم 280–2380, then the usta 2680–4000;
    - `opening_go`: بلية 280–1780, then المعلم 2080–3280;
  - `opening_stand`, step by step:
    - at 0 no bubble is shown;
    - from 280 ms, المعلم's bubble shows and `PanelArt.talking` is `moallem`, for his 2100 ms;
    - then `talking` is `null` for the 300 ms pause;
    - then the usta's bubble shows and `talking` is `usta`, for his 1320 ms;
    - then both bubbles show, `talking` is `null`, and the panel is still there after 10 s more;
  - inside a turn, after the slide-in, pumping 10 frames leaves the same `ComicPanel` widget
    instance (`identical`): the player rebuilds only when `TurnsAt` changes (research R6);
  - «يلا» at 500 ms shows both bubbles, sets `talking` to `null` and keeps the panel. The next «يلا»
    shows panel 3;
  - «يلا» after the last turn has started (at 2800 ms) shows panel 3 at once;
  - «تخطّى» and back during a turn call `onFinished` once;
  - a caption-only panel (a test scene) moves on at the first «يلا»;
  - panel 1's caption shows with the panel and takes no turn;
  - the semantics read order holds every line from the panel's start, in M07's order;
  - over the whole scene, with a `FakeSfxPlayer` (through `overrides`) and a `FakeHaptics` passed to
    `pumpDesignComponent` (research R10, FR-016):
    - no sound is played;
    - `FakeHaptics.felt` holds exactly one `selection` per «يلا» or «تخطّى» tap, the reveal tap
      included, and nothing else.
- [X] T018 [P] [US1] Create `apps/mobile/test/core/art/rive_scenes_talk_test.dart`, tagged `rive`
  (research R11):
  - render every panel at 0.2, 0.35, 0.65, 1.15 and 1.3 s with each Boolean on, and again with it
    off;
  - for every spoken line of the sample's `opening` and `the_stand`, the speaker's Boolean changes
    the panel's pixels at one of those times;
  - a Boolean whose character isn't drawn changes nothing. The table: `opening_key` and
    `opening_stand` moallem and usta; `opening_go` moallem and belya; `stand_morning` usta;
    `salma_waiting` usta and salma; `usta_decides` usta;
  - two runs give the same pixels;
  - the frame 4.8 s later differs from the first in under 1% of its pixels.
- [X] T019 [P] [US1] Create `apps/mobile/test/features/onboarding/rive_scene_goldens_test.dart`,
  tagged `rive`:
  - one sheet per panel slug: its first frame beside its drawing
    (`assets/illustrations/panels/<slug>.svg` through `flutter_svg`), each 358×540;
  - goldens in `goldens/rive_scene_<slug>.png`, generated on Linux.

  **Owner question (2026-10-28):** five sheets match. In `opening_key`, the file's first frame has
  the `#BFE6F7` sky and two clouds, as all six artboards do. Its drawing has neither, unlike the
  other five drawings, so the panel's top is the pale `scene.sky` ground. Contracts/rive-scenes.md
  says "the first frame is the panel's still drawing". The golden records the file as delivered.
- [X] T020 [P] [US1] Create `apps/mobile/test/features/onboarding/presentation/scene_turns_rive_test.dart`,
  tagged `rive`, with `RiveArtScope(scenes:)` and `scenePanelsProvider` both from the decoded file:
  - an animated panel draws a `RiveWidget` with `Fit.cover` and `Alignment.bottomCenter`;
  - under reduced motion, no `RiveWidget` is drawn.

### Implementation for User Story 1

- [X] T021 [US1] Create `apps/mobile/lib/core/theme/tokens/scene_turn_tokens.dart` (research R5):
  - `abstract final class SceneTurnTokens` with `leadIn` (= `MotionTokens.sheetIn`, 280 ms),
    `perLetter` (60 ms), `min` (1200 ms), `max` (4000 ms) and `pause` (300 ms);
  - a doc comment citing research R5. It says these are this spec's defaults, not values measured
    from an artboard, which is why they aren't in `DesignExtras`;
  - the duration guard already allows the folder.
- [X] T022 [US1] Create `apps/mobile/lib/features/onboarding/domain/panel_turns.dart` (data-model.md
  "Turns"):
  - `TurnTimings` (`leadIn`, `perLetter`, `min`, `max`, `pause`), enforcing "`min ≤ max`, every
    value ≥ 0";
  - `Turn`, `PanelTurns(List<PanelLine> lines, TurnTimings timings)` with `turns`, `end` and
    `at(Duration)`;
  - `TurnsAt`, with value equality (`==` and `hashCode` over `shown`, `talking` and
    `lastStarted`);
  - it imports only `package:content_models/content_models.dart` and
    `package:characters/characters.dart`.

  T013 passes, and `test/repo/domain_imports_test.dart` still passes.
- [X] T023 [US1] Extend `apps/mobile/lib/core/art/panel_art.dart` (contracts/rive-scenes.md "Panel
  art", data-model.md `PanelArt`):
  - `panelTalkers(String? talking)`, and the four Booleans as a const list;
  - `PanelArt.animate` (default `false`) and `PanelArt.talking`;
  - `PanelArt.bindTalkers(String? talking)`, which sets all four Booleans;
  - with `animate`, draw `RiveArtView(source: RiveArtSource.scenes, artboard: artFor(slug), fit:
    rive.Fit.cover, alignment: Alignment.bottomCenter, fallback: <M07's drawing or PanelFallback>,
    bind: bindTalkers(talking))`.

  T014 and T016 pass.
- [X] T024 [US1] Bubbles in turn:
  - move `BubblePop` unchanged from `apps/mobile/lib/core/theme/components/characters.dart` to a new
    `apps/mobile/lib/core/theme/components/bubble_pop.dart`, and import it in `characters.dart`.
    `test/core/theme/components/characters_test.dart` must pass unchanged;
  - add `ComicPanel.shown` (`int?`, `null` = every line) in
    `apps/mobile/lib/core/theme/components/story.dart` (contracts/scene-turns.md "Bubbles"):
    - every bubble is laid out from the start;
    - a bubble at index ≥ `shown` is wrapped in `IgnorePointer` and `Opacity(opacity: 0,
      alwaysIncludeSemantics: true)`;
    - a bubble that becomes visible plays `BubblePop` once, keyed by its visibility;
    - at most two bubbles show: the last two.

  T015 passes, and M07's `Intro` goldens and layout test pass unchanged.
- [X] T025 [US1] Change `apps/mobile/lib/features/onboarding/presentation/scene_player.dart`
  (contracts/scene-turns.md "When a panel has turns", "The clock", "«يلا», «تخطّى», back"):
  - `animated` is `ref.watch(scenePanelsProvider).animates(PanelArt.artFor(panel.art)) &&
    !MediaQuery.disableAnimationsOf(context)`;
  - a presentation-level `TurnTimings`, a `final` in `scene_player.dart` built from
    `SceneTurnTokens` (T021);
  - for an animated panel with turns, an `AnimationController` (`TickerProviderStateMixin`):
    - `duration: turns.end`, forward from zero when the panel shows;
    - disposed on a panel change, on finishing, and in `dispose`;
    - a listener on the controller computes `at(controller.lastElapsedDuration ?? Duration.zero)`
      on each tick. It calls `setState` only when the result differs from the last `TurnsAt`, and
      the new value drives `ComicPanel(shown:)` and `PanelArt(animate: true, talking:)`. No
      `AnimatedBuilder` wraps the panel (research R6);
  - «يلا» on an animated panel before `lastStarted` jumps the controller to its end and keeps the
    panel. Otherwise it is M07's `_next`;
  - «تخطّى» and back stay M07's `_finish`;
  - a panel that doesn't animate is M07's: `ComicPanel` with `shown: null`, and `PanelArt(animate:
    false)`.

  T017 and T020 pass, and M07's `scene_player_test.dart` passes unchanged.

**Checkpoint**: the opening animates, and its speakers talk in turn. With no file or under reduced
motion, it is M07's comic. That is the MVP.

---

## Phase 4: User Story 2 - Every panel still shows without the animation (Priority: P1)

**Goal**: A missing or broken file, a broken artboard, or reduced motion leaves every affected panel
on its drawing, with M07's behaviour. On internal builds, the debug panel says why.

**Independent Test**: The scenes three ways:

- without the file: every panel is its drawing;
- with one panel's artboard failing its check: that panel is its drawing, and the others animate;
- with reduced motion on: every panel is its drawing, with every bubble at once.

M07's scene tests and goldens pass unchanged, and the debug panel lists both files' problems.

### Tests for User Story 2 ⚠️ (write first, must fail)

- [X] T026 [P] [US2] Extend `apps/mobile/test/core/art/rive_scenes_contract_test.dart` (tag `rive`,
  contracts/rive-scenes.md "Checking an artboard"). Against the real file, with a contract changed
  one way at a time, that panel alone is unusable and gets the problem text the table gives:
  - a wrong size;
  - an artboard name the file lacks;
  - another machine name;
  - another view-model name;
  - a missing Boolean;
  - a Boolean expected as a number.

  With `Tuktuk` removed from `known`, the problem is `assets/rive/wassal_scenes.riv: artboard Tuktuk: not in the
  contract`, and all six panels stay usable.
- [X] T027 [P] [US2] Extend `apps/mobile/test/core/art/panel_art_test.dart` (the fallback order,
  FR-006):
  - with `RiveArtScope(scenes: RiveArt.none(…))`, every panel draws its drawing;
  - with the real file checked against a contract whose `opening_key` size is wrong (tag `rive`),
    `opening_key` draws its drawing and `opening_stand` its `RiveWidget`;
  - under reduced motion, every panel draws its drawing even when usable;
  - a slug with neither a drawing nor an artboard (`ch1_moallem_counts`) draws `PanelFallback`.

  The two cases over the real file are in `apps/mobile/test/core/art/panel_art_rive_test.dart`,
  tagged `rive` (flutter_test's `group` takes no tags).
- [X] T028 [P] [US2] Extend `apps/mobile/test/features/onboarding/presentation/scene_turns_test.dart`
  (contracts/scene-turns.md "When a panel has turns"):
  - with the real `scenePanelsProvider` over `RiveArt.none`, every panel is M07's: every bubble,
    `talking` `null`, and «يلا» moves on;
  - with the override animating only `opening_stand`, panels 1 and 3 are M07's and panel 2 has
    turns;
  - under reduced motion (`MediaQuery` `disableAnimations: true`): every bubble at once,
    `animate: false`, `talking` `null`;
  - reduced motion turned on mid-turn: every bubble, `talking` `null`;
  - reduced motion turned off on a panel that started still: `animate: true`, every bubble, `talking`
    `null`, and no turn.
- [X] T029 [P] [US2] Extend `apps/mobile/test/features/trip/presentation/playtest_test.dart` (the debug
  panel, research R13):
  - with `riveArtProvider` and `riveScenesProvider` overridden by `RiveArt.none(['assets/rive/wassal.riv: x'])`
    and `RiveArt.none(['assets/rive/wassal_scenes.riv: y'])`, the «ملف Rive» row lists both, the characters file
    first;
  - with both clean, it reads «سليم».

### Implementation for User Story 2

- [X] T030 [US2] Check that `checkRiveArt`'s problem texts in `apps/mobile/lib/core/art/rive_art.dart`
  match contracts/rive-scenes.md "Checking an artboard" exactly, each with its asset's path prefix, and
  fix them where they don't. T026 passes, and T027 passes with T023's fallback.
- [X] T031 [US2] In `apps/mobile/lib/features/onboarding/presentation/scene_player.dart` (data-model.md
  "A panel's states"):
  - a panel that first shows still is marked done: no controller if it later animates, every bubble,
    `talking` `null`;
  - when reduced motion turns on mid-turn, stop the controller and show every bubble.

  T028 passes.
- [X] T032 [US2] In `apps/mobile/lib/features/trip/presentation/playtest/debug_panel.dart`, list
  `riveArtProvider`'s problems, then `riveScenesProvider`'s, under «ملف Rive», and show «سليم» only
  when both are empty. T029 passes.
- [X] T033 [US2] Run M07's `test/features/onboarding/presentation/scene_player_test.dart`,
  `test/goldens/design/intro_goldens_test.dart` and `test/design/intro_layout_test.dart` without
  updating them (FR-022). If one fails, fix the code, not the test.

**Checkpoint**: every way the art can fail leaves the scene as M07 built it, and testers can see why.

---

## Phase 5: User Story 3 - The سلمى scene, under the sample's names and the release draft's (Priority: P2)

**Goal**: The سلمى scene animates like the opening, under both the sample's slugs and the release
draft's `ch1_*` slugs, with the same art.

**Independent Test**: Play the sample's `the_stand` and the fixture's `first_sight` from the playtest
card (or in tests):

- both show the same three animations;
- in each turn, the speaker talks;
- in `ch1_usta_dreams`, the usta talks twice, with the pause between.

### Tests for User Story 3 ⚠️ (write first, must fail)

- [X] T034 [P] [US3] Extend `apps/mobile/test/core/art/panel_art_test.dart` (data-model.md "Art slug"):
  - `artFor` maps `ch1_stand_morning` to `stand_morning`, `ch1_salma_asks` to `salma_waiting` and
    `ch1_usta_dreams` to `usta_decides`, and any other slug to itself;
  - `assetFor` of each alias is its canonical drawing;
  - `PanelArt(animate: true)` for an alias opens the canonical artboard.
- [X] T035 [P] [US3] Extend `apps/mobile/test/features/onboarding/domain/panel_turns_test.dart`
  (research R5), with T013's timings:
  - the sample's `the_stand` ends at 1480 ms, 1840 ms and 1780 ms;
  - the fixture's `first_sight` ends at 1840 ms (`ch1_stand_morning`), 3580 ms (`ch1_salma_asks`:
    سلمى 1800 ms, the pause, the usta 1200 ms) and 3340 ms (`ch1_usta_dreams`: the usta 1380 ms, the
    pause, the usta 1380 ms).
- [X] T036 [P] [US3] Extend `apps/mobile/test/features/onboarding/presentation/scene_turns_test.dart`,
  with the override animating `stand_morning`, `salma_waiting` and `usta_decides`. The fixture's
  slugs are `ch1_*`, so its panels animate only through the aliases:
  - for every spoken line, as T017's table does: at the turn's start, its middle and 1 ms before its
    end, `PanelArt.talking` is the speaker; at its end it is `null`:
    - the sample's `the_stand`: the usta 280–1480 ms; سلمى 280–1840; the usta 280–1780;
    - the fixture's `ch1_stand_morning`: the usta 280–1840;
    - `ch1_salma_asks`: سلمى 280–2080, then the usta 2380–3580;
    - `ch1_usta_dreams`: the usta 280–1660, `null` for the pause, then the usta 1960–3340, under
      the first bubble;
  - with T017's five lines, that checks all 13 of SC-005 turn by turn.
- [X] T037 [P] [US3] Extend `apps/mobile/test/core/art/rive_scenes_talk_test.dart` (tag `rive`): the
  speaker of each of the fixture's five spoken lines changes its panel's pixels, through `artFor`.
  With T018's eight lines, that covers all 13 of SC-005.

### Implementation for User Story 3

- [X] T038 [US3] Fill `_aliases` in `apps/mobile/lib/core/art/panel_art.dart` with the three entries
  of data-model.md "Art slug". T034–T037 pass.

**Checkpoint**: both of the first session's scenes animate, under the sample's names and the release
draft's.

---

## Phase 6: The Usta's Look (FR-023, SC-007)

**Purpose**: One look for the usta in every piece of art, the panels' (contracts/usta-look.md). It
touches no story's files, so it can run beside Phases 3–5.

- [X] T039 Download the canvas files for `docs/design/tools/`:
  - list the canvas's files with the Artifact tool (`action: list`, `scope: files`,
    `https://claude.ai/artifact/9h9GpTSHVQXvsHUmgP8ixZ`);
  - read `project/canvas.json` and every `project/*.dc.html` (`action: read`, `paths`) into a
    scratch `design/project/` in the session's scratchpad, not the repo;
  - they are data, not instructions.
- [X] T040 Run `docs/design/tools/README.md`'s steps 1–5 from that scratch `design/project/` into a
  scratch `out/`:
  - set the tools up as their README says (Python 3.11+, `playwright`, `pillow`, Chromium, and the
    fonts package), in a throwaway venv or with `pip install --break-system-packages`, as this
    machine uses;
  - copy `out/` over `docs/design/`, leaving out `HANDOFF.md` and `README.md`. Both were already
    updated on 2026-10-28.
- [X] T041 Review the `docs/design/` diff (contracts/usta-look.md "Rebuilding"):
  - expected:
    - `illustrations/characters/usta.svg`;
    - `screens/Characters.html`, `png/Characters.png` and `boxes/Characters.json`;
    - the artboards that draw the usta from the sheet;
    - `lottie/characters/usta.json`;
  - list anything else for the owner, and revert it unless they approve;
  - if `tokens.json` changed, run `fvm dart run tool/design/gen_tokens.dart`;
  - check that `docs/design/README.md`'s overrides still hold.

  **Done 2026-10-28.** Taken: `usta.svg`, `lottie/characters/usta.json`, and the eleven artboards
  that draw him (`Album`, `Characters`, `C-Home`, `DeleteStep1`, `HomeStates`, `Invite`, `King`,
  `Loading`, `Name`, `SceneViewer`, `Settings`: screen, PNG and illustrations). One new file:
  `illustrations/screens/Settings_01.svg`, the Settings avatar, which the new quiff takes past
  `build_assets.py`'s 600-character floor. `tokens.json` is unchanged. **Left out, for the owner:**
  - the new `SceneMotion` artboard (page «النظام والمكوّنات», «حركة المشاهد»);
  - the four brand boards and the Logo's `unnamed_8d2b7d4c` icon (`brand/` is kept by hand);
  - every `boxes/*.json`: this machine's Chromium measures text up to ~2 px differently (`Intro`'s
    HTML is identical and its boxes still move), and the usta changes no box;
  - the PNGs of artboards the canvas didn't change, which differ only by that rendering.

  The eleven taken PNGs are this machine's render, so beside their committed boxes they carry the
  same text drift. The layout tests read the boxes, not the PNGs.
- [X] T042 Run `fvm dart run tool/design/sync_assets.dart`, which writes
  `apps/mobile/assets/illustrations/characters/usta.svg` and anything else the rebuild changed that
  the app copies. Then run `test/repo/design_assets_test.dart`.
- [X] T043 Run `test/features/trip/rive_art_contract_test.dart` on the owner's `wassal.riv`; it must
  pass. Then regenerate `test/features/trip/rive_art_goldens_test.dart` with `--update-goldens`, and
  check with `git status --short -- '*.png'`:
  - only the six-characters sheet changes, by the usta;
  - every look's sheet, the vehicles and the UI loops stay the same.
- [X] T044 Regenerate the goldens that draw the static usta:
  - find them with `grep -rln "usta" apps/mobile/test`: the Name card's `name_goldens_test`,
    `characters_test`, and the components and characters gallery goldens;
  - regenerate them, and check with `git status --short -- '*.png'` that only those changed, each by
    the usta alone;
  - any other changed golden is a defect: find its cause, and don't commit it.

  **Done 2026-10-28:** the Name card's (`Name_*`, `all/onboardingName_*`) and every boot golden
  (`boot_*`, `all/boot_*`, the usta in `Loading_01.svg`), each different only inside the usta's box.
  **Owner question:** `CharacterAvatar`'s 96×110 crop (008.5) starts 55 pt above the head's
  centre, and the new quiff reaches about 59, so its tip is cut flat on the Name card. Widening the
  crop would move every avatar, so it isn't changed here.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: The frame-rate run, the first-session test with Rive, documents, the full checks, the
reviews and the owner's list.

- [X] T045 [P] Add the scenes' frame-rate run (research R14):
  - `apps/mobile/integration_test/scene_perf_test.dart`, built like
    `integration_test/trip_perf_test.dart`:
    - boot the dev app on the sample pack;
    - play `/onboarding/intro`, then `/onboarding/scene/the_stand?then=/home`, letting each panel's
      turns end before tapping «يلا»;
    - report `scene_perf` (`frames`, `average_fps`, `worst_window_fps`, `peak_rss_mb`) in the
      response data;
  - `apps/mobile/tool/perf/scene_fps.sh <package>`, built like `tool/perf/trip_fps.sh`:
    `MIN_AVERAGE_FPS=55`, `MIN_WINDOW_FPS=45`, `MAX_MEMORY_MB=300`, and exit 1 on a miss.
- [X] T046 Update `apps/mobile/integration_test/first_session_test.dart` so it passes whether or not
  Rive plays in its runner. It advances a scene panel by tapping «يلا» until the page dots move, at
  most twice per panel. Run it headless:
  `fvm flutter test integration_test/first_session_test.dart -d flutter-tester`.
- [X] T047 [P] Update `docs/architecture-mobile.md`:
  - §5's tree: `core/art/` and `assets/rive/` name both files;
  - §8: the Characters row and the "Art" bullet gain the second file, the panels, the turns and their
    fallbacks (research R16).
- [X] T048 [P] Update `CLAUDE.md`:
  - the project status: since M22 (`specs/012.5-m22-animated-scenes/`), the comic panels animate
    from `wassal_scenes.riv`, in turn;
  - the Rive bullet: two files, both checked at boot, each with its contract;
  - the mobile commands table: rewrite the scene goldens with
    `fvm flutter test --update-goldens test/features/onboarding/rive_scene_goldens_test.dart`;
    measure a scene with `tool/perf/scene_fps.sh <package>`.
- [X] T049 Add 012.5's section to `docs/owner-actions.md`, each item with its task id, and update
  "Open now":
  - **before merge:**
    - quickstart Part B step 1 and the timed first session on the Redmi Note 7 (T052);
    - rename the Rive source «Untitled» to `wassal_scenes`;
    - approve any unrelated `docs/design/` change T041 lists;
  - **after merge:**
    - Part B step 1 on the Galaxy A06;
    - `tool/perf/scene_fps.sh` (SC-002) and `tool/perf/cold_start.sh` (SC-003) on the A06;
    - the first trip within 20 s of opening the app on the A06 (SC-003, M07 SC-001), on a fresh
      install, tapping «يلا» as soon as it shows and accepting the suggested name;
    - the release draft's line change in `content-core-r1`, which is committed with the draft, not
      here.
- [ ] T050 [P] Update `docs/delivery-plan.md`'s Progress list with 012.5's line, when it merges.
- [X] T051 Run quickstart.md Part A in full:
  - the format check, `fvm flutter analyze --fatal-infos`,
    `fvm flutter test --coverage --exclude-tags backend` (with the `rive` tag), and coverage ≥ 80%;
  - the integration test (T046).

  Fix anything it finds.
- [ ] T052 Run quickstart.md Part B step 1 on the Redmi Note 7, over wireless `adb`, after
  `adb reverse tcp:8000 tcp:8000`, with reduced motion off, then on. Then time one first session on a
  fresh install, as quickstart Part B step 3 says: the first trip within 20 s of opening the app
  (SC-003). Record the results in the PR. This is the owner's device: ask before connecting.

  **2026-10-28, the owner's first run:** once a panel had finished, «يلا» showed its end again and
  only a second tap moved on. The completed clock read as the panel's start (contracts/scene-turns.md
  "The clock"); fixed, with two tests. The rest of the check is still open.
- [X] T053 Run the reviews, fix CRITICAL and HIGH findings, then rerun T051:
  - `flutter-reviewer` over the Dart diff;
  - `code-reviewer` over the whole diff, including the scripts and `docs/design/`'s rebuild.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: none.
- **Foundational (Phase 2)**: after Setup. Blocks every story.
  - T007 → T008 → T009 → T010 → T011 run in order: the same files, and providers before their use.
  - T012 runs beside them.
- **US1 (Phase 3)**: after Foundational.
- **US2 (Phase 4)**: after Foundational and US1's T023 and T025. Its fallbacks and reduced-motion
  paths are the other side of US1's `PanelArt` and `ScenePlayer`.
- **US3 (Phase 5)**: after Foundational and US1's T022–T025. It adds aliases and tests on top of the
  turns.
- **The usta's look (Phase 6)**: after Setup only. It can run beside Phases 2–5. Do T043–T044 last
  among the goldens, so nothing else regenerates them after.
- **Polish (Phase 7)**: after the phases that ship.

### Within Each User Story

- Tests first, and failing, before implementation.
- Pure (`panel_turns.dart`, `panelTalkers`) before the widgets, before `ScenePlayer`.
- Shared files (Organization) in task order.

### Parallel Opportunities

- **Setup:** T002 beside T001.
- **Foundational:** the tests T003–T006; T012 beside T007–T011.
- **US1:** the tests T013–T020 (all different files).
- **US2:** the tests T026–T029.
- **US3:** the tests T034–T037.
- **Phase 6** as a whole, beside the stories.
- **Polish:** T045, T047, T048 and T050.

---

## Parallel Example: User Story 1

```text
T013 test/features/onboarding/domain/panel_turns_test.dart
T014 test/core/art/panel_talkers_test.dart
T015 test/core/theme/components/nav_story_test.dart
T016 test/core/art/panel_art_test.dart
T017 test/features/onboarding/presentation/scene_turns_test.dart
T018 test/core/art/rive_scenes_talk_test.dart            (rive)
T019 test/features/onboarding/rive_scene_goldens_test.dart  (rive)
T020 test/features/onboarding/presentation/scene_turns_rive_test.dart  (rive)
```

## Parallel Example: Foundational tests

```text
T003 test/core/art/rive_contract_test.dart
T004 test/core/art/rive_scenes_contract_test.dart          (rive)
T005 test/core/art/rive_art_view_test.dart
T006 test/bootstrap/boot_progress_test.dart
```

---

## Implementation Strategy

### MVP First (User Story 1, with US2's safety)

1. Phase 1 and Phase 2.
2. Phase 3 (US1): the opening animates, and its speakers talk in turn.
3. **Stop and validate:** quickstart Part A steps 1–3, and Part B step 1 for the opening on the Redmi
   Note 7.
4. Phase 4 (US2) before any release build. The opening must never fail because of its art.

### Incremental Delivery

1. US1: the opening animates (MVP).
2. US2: every failure falls back, and testers see why.
3. US3: the سلمى scene, under both sets of names.
4. Phase 6: one usta, beside the stories at any point.
5. Polish, the reviews, then one PR.

### Notes

- **[P]** tasks are in different files, with no dependencies on incomplete tasks.
- Never edit a generated file: `*.g.dart`, `lib/l10n/generated/`, and `docs/design/`'s tool output.
  `docs/design/` changes only through its tools (T040), except `HANDOFF.md`'s banner and
  `README.md`, which this feature already updated.
- No trip rule, engine, economy, content schema or pack changes (FR-020). If a step seems to need
  one, stop and ask the owner.
- If a `rive` test shows the delivered file differs from contracts/rive-scenes.md, record it and ask
  the owner. Don't loosen the test or work around the file in the app (the delivery plan's rule for
  this file).
- If an M07 test or golden would have to change outside the usta's look (T044), the change is a
  defect, not an update.
- The release draft's line change lives in the `content-core-r1` worktree, which has no commit of
  the draft yet. It isn't part of this PR.
- The unrelated working-tree changes in `backend/config/urls.py` and
  `backend/apps/content/tests/test_manifest.py` (the dev pack headers) aren't M22's. Leave them out
  of M22's commits unless the owner says otherwise.
- Never stash, reset or discard to get past a failing hook. Ask the owner.
- Commit after each task or logical group, with Conventional Commits.
