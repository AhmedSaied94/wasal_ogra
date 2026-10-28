---

description: "Task list for M07 Onboarding and the Tutorial Trips"
---

# Tasks: Onboarding and the Tutorial Trips (M07)

**Input**: Design documents from `specs/012-m07-onboarding/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**:

- **Mandatory, and first** (constitution XIII). Tests come first for `FirstSession`,
  `TutorialCoach`, `NameRules`, the two operations' rules and the snapshot mapping. Every phase
  writes its tests first, and they must fail before its implementation tasks start.
- **Real SQLite, real engine.** Store and service tests use real drift databases
  (`NativeDatabase.memory()`, or a temp file when a test reopens it). Coach tests build `TripState`s
  by running the real engine on the tutorial fixture's trips, never by hand.
- **Against the real stack.** `test/backend/` (tag `backend`) runs in the existing `sync-e2e` job.
- **Coverage.** At least 80% of lines in `apps/mobile` (`tool/check_coverage.dart`). The content kit
  and the backend keep their own gates.

**Organization**:

- **Paths** are from the repository root.
  - Dart commands run with `fvm` in `apps/mobile/`.
  - Content kit commands run with `uv` in `tools/content_kit/`.
  - Backend commands run with `uv` in `backend/`, with the dev stack up.
- **Codegen.**
  - After a `@riverpod` provider or a drift table: `fvm dart run build_runner build -d`.
  - After the v4 tables: `fvm dart run drift_dev make-migrations`, and commit its output.
  - After the schema change: `uv run wassal-content codegen`, then `fvm dart pub get && fvm dart run
    build_runner build -d` in `packages/content_models`, then `uv sync --reinstall-package
    wassal-content` in `backend/`.
- **Exactness.** Every number is from the contracts. Name each as a constant in `lib/`, never a bare
  literal. The list:
  - the name: 2 and 16 characters, at least 20 suggestions, 24 in the starting pool;
  - the tutorial: 5 trips; steps 1–8;
  - the coach: hole `inflate(6)`, radius 18, ring 4; scrim fade 200 ms; hole move 250 ms
    `easeOutCubic`; ring pulse 1.0↔1.06;
  - the scene player: panel change ≤ 280 ms (`sheetIn`), 150 ms fade under reduced motion;
  - the fuel lesson: needle sweep 600 ms `easeOutCubic`;
  - the compact layout: HUD 72, dashboard 226, rows and gaps as in contracts/compact-trip-layout.md,
    the 334 pt reference scene, the 408 pt boundary, `T + 764` and `T + 690`, and the seat tables.

  Motion constants live in `lib/features/trip/presentation/trip_motion.dart` (trip) or
  `MotionTokens` (elsewhere), the guards' allowed places.
- **Wire and content names** are the contracts', spelled exactly: `settings_update`, `tutorial_gift`,
  `display_name`, `grants.tutorial`, `plays`, `opening`, `after_trip`, `narrator`.
- **Shared files.** These grow story by story, so tasks that touch them run in order:
  - `apps/mobile/lib/core/storage/tables.dart`, `app_database.dart`;
  - `apps/mobile/lib/core/economy/{economy.dart,economy_service.dart,drift_economy_store.dart}`,
    `domain/rules.dart`;
  - `apps/mobile/lib/core/routing/{routes.dart,router.dart}`;
  - `apps/mobile/lib/features/trip/application/trip_controller.dart`,
    `presentation/trip_screen.dart`, `presentation/dashboard/dashboard.dart`;
  - `apps/mobile/lib/features/onboarding/onboarding_providers.dart`;
  - `apps/mobile/lib/l10n/app_ar.arb`;
  - `apps/mobile/lib/features/dev/gallery/components_page.dart`.
- **One PR**, with a security review: sync, personal data (the name), and B04's admin (plan
  "Security & privacy").

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story the task belongs to (US1–US6 from spec.md)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: The one new direct dependency, the tutorial fixture and the first panel's art.

- [X] T001 Add `characters` as a direct dependency in `apps/mobile/pubspec.yaml`, with a comment
  naming research R7 (grapheme-cluster lengths in the pure `NameRules`). Use the version already in
  `pubspec.lock` (Flutter's), then run `fvm flutter pub get`.
- [X] T002 [P] Create the tutorial fixture `apps/mobile/test/fixtures/tutorial/` (research R20):
  - copy `line_hay.01.json`–`line_hay.05.json` and `lines/line_hay.json` from
    `/mnt/endeavour/home/saied-dev/Work/wasal_ogra-core-r1/content/drafts/core-r1/pack/`;
  - copy the speech pools the five trips name that the sample lacks (`sleeper.boards`,
    `sleeper.missed_stop`, `sleeper.woke`, and any other `speech_keys` they use);
  - add `README.md` saying where they came from (the `content-core-r1` worktree, with the date), that
    they are copies kept for M07's tests, and that a change to the draft's trips 01–05 is copied here
    by hand.
- [X] T003 [P] Extend `apps/mobile/tool/design/sync_assets.dart` to copy
  `docs/design/illustrations/screens/Intro_01.svg` to
  `apps/mobile/assets/illustrations/panels/opening_key.svg` (contracts/scenes.md "Panel art"). Add
  the folder to `pubspec.yaml`'s assets, run the tool, and run `test/repo/design_assets_test.dart`.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The content schema's `plays` end to end (kit, sample, backend), database v4 with the two
operations and the projection's new fields, the shared components, and the first session's core.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Test helpers and guards: first

- [X] T004 [P] Create `apps/mobile/test/helpers/tutorial_content.dart` with `tutorialContent()`. It
  returns a `ContentSource` that layers T002's fixture over the bundled sample: the first line's
  definition and its trips 01–05, plus the extra speech pools. Every other part stays the sample's.
  A self-test checks that the five trips validate and are ordered 01–05.
- [X] T005 [P] Extend `apps/mobile/test/repo/economy_writes_test.dart`:
  - `player_state` is written only by `lib/core/economy/drift_economy_store.dart`;
  - `first_session` only by `lib/features/onboarding/data/drift_first_session_store.dart`.
- [X] T006 [P] Extend `apps/mobile/test/repo/domain_imports_test.dart`:
  `lib/features/onboarding/domain/` may import only `dart:core`, `package:characters`,
  `content_models`, `trip_engine`, the economy and content domains, and
  `lib/features/trip/domain/`. `lib/core/economy/domain/profile_rules.dart` may also import
  `lib/features/onboarding/domain/name_rules.dart` (the one name check the phone and the economy
  share, research R7–R8), and nothing else from `features/`.

### The content schema's `plays`: tests first

- [X] T007 [P] Add the content kit cases (contracts/scenes.md "Validator rules"):
  - `content/examples/valid/chapter_with_plays.json`: a chapter with an `opening` scene and an
    `after_trip` scene;
  - `content/examples/invalid/`, each with its `expected.json` entry:
    - an `opening` in a chapter whose `order` isn't 1 (V-C3);
    - two `opening` scenes (V-C3);
    - an `opening` with a `trip_id` (V-C3);
    - an `after_trip` without a `trip_id` (V-C4);
    - an `after_trip` naming an unknown trip (V-C4);
    - two scenes naming the same trip (V-C4);
    - a `narrator` line that isn't the panel's first (V-C5);
    - two `narrator` lines in a panel (V-C5).
  - Extend `tools/content_kit/tests/` so each case is asserted with its code.

### The content schema's `plays`: implementation

- [X] T008 Change `content/schemas/chapter.schema.json` exactly as contracts/scenes.md "Schema":
  - `$defs.ScenePlays`: closed, `required: ["kind"]`, `kind` → `ScenePlaysKind`, `trip_id` →
    `common.schema.json#/$defs/TripId`;
  - `$defs.ScenePlaysKind`: `enum: ["opening", "after_trip"]`, with its description;
  - `Scene.properties.plays` → `ScenePlays` (not required).

  Then run `uv run wassal-content codegen`, and `build_runner` in `packages/content_models`. Commit
  the schema, `_generated.py`, `src/wassal_content/schemas/*.json` and `lib/src/generated/*.dart`.
  `uv run wassal-content codegen --check` passes.
- [X] T009 Implement V-C3, V-C4 and V-C5 in `tools/content_kit/src/wassal_content/rules/references.py`
  (contracts/scenes.md table), and list them with V-C1 and V-C2 in the kit's rule table. T007's cases
  pass, and `uv run ruff check . && uv run mypy . && uv run pytest` is green.
- [X] T010 Update `content/examples/sample/chapters/ch1_first_job.json` (contracts/scenes.md "The sample
  pack"):
  - a new first scene `opening` with `plays: {"kind": "opening"}` and the three panels (`opening_key`,
    `opening_stand`, `opening_go`), lines verbatim from the contract;
  - `the_stand` gains `plays: {"kind": "after_trip", "trip_id": "line_hay.03"}`.

  Then:
  - `uv run wassal-content validate-source ../../content/examples/sample`;
  - `uv run wassal-content golden --update` (review the diff);
  - `uv run wassal-content bundle dev --out ../../apps/mobile/assets/content/dev`;
  - `bundle dev --check`.

  No trip changes.
- [X] T011 [P] Write B04's tests first in `backend/apps/content/tests/`:
  - `test_import_export.py`: the sample round-trips byte for byte with `plays` and the `narrator`
    lines; update the record counts (61 + the opening scene's records) in `test_import_export.py`
    and `test_history.py`;
  - `test_scene_plays.py` (new):
    - each invalid `plays` from T007 is refused at import with its code;
    - the database check refuses `plays_trip` without `after_trip` and the reverse;
    - `SceneInline` renders `plays_kind` and `plays_trip`;
  - `test_lookups_rules.py`: chapter 1's `"scenes": ["opening", "the_stand"]`.
- [X] T012 Implement B04's side (contracts/scenes.md "Backend B04"):
  - `backend/apps/content/models/story.py` `Scene`:
    `plays_kind = CharField(max_length=16, choices=[("opening", …), ("after_trip", …)], blank=True)`;
    `plays_trip = ForeignKey("content.Trip", null=True, blank=True, on_delete=PROTECT,
    related_name="+")`; and CHECK `content_scene_plays_trip`:
    `(plays_kind = 'after_trip') = (plays_trip IS NOT NULL)`;
  - `migrations/0009_scene_plays.py` (expand-only);
  - `services/importer.py` `chapter()`: reads `plays`, resolving `trip_id` like `story_trip_id`;
  - `services/snapshot.py` `scene_part()`: writes `plays` in schema key order when set;
  - `admin/authoring.py` `SceneInline`: shows both fields.

  Then `uv sync --reinstall-package wassal-content` and
  `uv run manage.py makemigrations --check --dry-run`. T011 passes, and the whole backend suite is
  green (`uv run pytest -n 4 --cov --cov-fail-under=80`).

### Database v4 and the economy: tests first

- [X] T013 [P] Create `apps/mobile/test/core/storage/schema_v4_test.dart`:
  - `ledger_ops.op_type` accepts all nine wire names, including `settings_update` and `tutorial_gift`;
  - `player_state` and `first_session` each allow one row (`id = 1`) and read as `(null, false)` and
    the defaults when absent;
  - `first_session.step_reached` is "0–8, default 0";
  - `scenes_due` and `scenes_seen` default to `'[]'`;
  - no REAL column.
- [X] T014 [P] Create `apps/mobile/test/features/onboarding/domain/name_rules_test.dart`
  (contracts/name.md "`NameRules`"):
  - trim and collapse;
  - `empty`; `tooShort` at 1 grapheme cluster, `ok` at 2;
  - 16 characters `ok`;
  - `onlyDigits` for Western and Arabic-Indic digits (with spaces);
  - `badCharacters` for a control character, a bidi mark (U+200F, U+202E), a zero-width joiner and
    space (U+200D, U+200B), and a private-use character.

  Invert the v3 test that refused `tutorial_gift` (`test/core/storage/schema_v3_test.dart:170`).
- [X] T015 [P] Extend `apps/mobile/test/core/economy/domain/economy_state_test.dart`: `displayName`
  and `tutorialGranted` round-trip through `toJson`/`fromJson`, and a v3 base JSON without them reads
  as `null` and `false`.
- [X] T016 [P] Create `apps/mobile/test/core/economy/domain/profile_rules_test.dart`, and extend
  `gift_rules_test.dart` (contracts/fuel-lesson.md "The operation", contracts/name.md):
  - `settings_update`:
    - validate refuses `invalidName` for every `NameCheck` failure;
    - apply sets `displayName`;
    - no deltas;
    - `stillValid` is true;
  - `tutorial_gift`:
    - validate refuses `alreadyGranted` when `tutorialGranted`;
    - apply fills to `fuelMax` with `fuelDelta` recorded, and sets `tutorialGranted`;
    - a full tank gives delta 0 and still sets the flag;
    - `stillValid` is false once the base is granted.
- [X] T017 [P] Extend `apps/mobile/test/core/economy/economy_service_test.dart` on a real database:
  - `setDisplayName` then `view.displayName`;
  - `grantTutorialGift` twice: `OpApplied`, then `OpRefused(alreadyGranted)`;
  - `replaceFromServer` with `tutorialGranted: true` drops a pending local gift;
  - `nameRefused` is true when the newest `settings_update` row is `rejected`, and false after a new
    one;
  - after a rejected `settings_update`, `view.displayName` goes back to the server's last accepted
    name, or to null (shown as «الأسطى») when it never accepted one (FR-017).
- [X] T018 [P] Extend `apps/mobile/test/core/sync/domain/state_snapshot_test.dart` and the wire tests:
  - `grants.tutorial` maps to `tutorialGranted`, and `player.display_name` to `displayName`;
  - a missing `grants` reads as `false`.

### Database v4 and the economy: implementation

- [X] T019 Add to `apps/mobile/lib/core/storage/tables.dart` (data-model.md "App database v4"):
  - `LedgerOps.opType`'s `isIn` list: the seven v3 names plus `settings_update` and `tutorial_gift`;
  - **`PlayerStateTable`** (`player_state`): `id` INTEGER "`= 1` (one row)"; `display_name` TEXT
    "nullable; no length CHECK, since the server allows up to 20 and its name wins on a restore";
    `tutorial_granted` BOOLEAN "not null, default false";
  - **`FirstSessionTable`** (`first_session`): `id` INTEGER "`= 1`"; `opening_done_at_ms` INTEGER
    nullable; `scenes_due` TEXT "JSON array of scene ids, default `[]`"; `scenes_seen` TEXT "JSON
    array of scene ids, default `[]`"; `fuel_lesson_done_at_ms` INTEGER nullable; `step_reached`
    INTEGER "0–8, default 0"; `done_at_ms` INTEGER nullable.
- [X] T020 Bump `schemaVersion` to 4 in `apps/mobile/lib/core/storage/app_database.dart` with
  `_toV4` in `upgradeSteps`:
  - rebuild `ledger_ops` with `TableMigration(schema.ledgerOps)` as `_toV3` did, rows kept;
  - create `player_state` and `first_session`, inserting nothing.

  Run `build_runner` and `fvm dart run drift_dev make-migrations`. Commit
  `drift_schemas/app/drift_schema_v4.json` and the generated `test/drift/app/` files. T013 and the
  generated migration test pass.
- [X] T021 Create `apps/mobile/lib/features/onboarding/domain/name_rules.dart` (`NameCheck`
  sealed: `ok(normalized)`, `empty`, `tooShort`, `onlyDigits`, `badCharacters`). Use
  `package:characters` for lengths, and constants `nameMinLength = 2` and `nameMaxLength = 16`.
  T014 passes. It imports only `package:characters`.
- [X] T022 Extend the economy domain in `apps/mobile/lib/core/economy/domain/`:
  - `op.dart`: `OpType.settingsUpdate('settings_update')`, `OpType.tutorialGift('tutorial_gift')`;
    `SettingsUpdateRequest(String name)`, `TutorialGiftRequest()`;
  - `EconomyRefusal`: `invalidName`, `alreadyGranted`;
  - `economy_state.dart`: `String? displayName`, `bool tutorialGranted` (JSON keys `display_name`
    and `tutorial_granted`, absent → `null`/`false`);
  - `profile_rules.dart` (new) and `gift_rules.dart`: the rules of T016, `settings_update` checking
    the name with `NameRules` (T021);
  - `rules.dart`: the four switches (`validate`, `apply`, `stillValid`, `requestMatches`).

  T015 and T016 pass.
- [X] T023 Wire both operations through the store and the service:
  - `drift_economy_store.dart`: read and write `player_state` in `commit`, `rebuild`, `applyAnswer`
    and `takeServerState`; build the view's `displayName`, `tutorialGranted` and `nameRefused`
    (one query on the newest `settings_update` row);
  - `economy.dart`: `setDisplayName(TxnId, String)` and `grantTutorialGift(TxnId)` on `Economy`,
    and the three view fields on `EconomyView`;
  - `economy_service.dart`: both on the serial queue through `_submit`.

  T017 passes.
- [X] T024 Map the server's state in `apps/mobile/lib/core/sync/`:
  - `domain/wire/state.dart`: `StateSnapshot.grants` (`tutorial: bool`, absent → `false`);
  - `domain/state_snapshot.dart` `stateFromSnapshot`: `displayName` and `tutorialGranted`;
  - update the doc line that says `grants` isn't mapped yet.

  T018 passes, and the existing sync suites stay green.

### Shared components: tests first, then implementation

- [X] T025 Move `SpeechBubble` (from `features/trip/presentation/overlays/bubbles_layer.dart`) and
  `CharacterAvatar` (from `features/trip/presentation/scene/character_avatar.dart`) to
  `apps/mobile/lib/core/theme/components/characters.dart`, exported with the other components.
  Update every import, and move their tests next to the other component tests. No behaviour change:
  all trip goldens stay identical.
- [X] T026 [P] Write component tests in `apps/mobile/test/core/theme/components/nav_story_test.dart`:
  - `PageDots(count: 3, index: 0)`: the active pill is 26×10, the others 10×10, gap 8; in RTL the
    first dot is on the right; semantics «اللوحة ١ من ٣»;
  - `ComicPanel` with two lines: two bubbles stacked; a caption chip from the `caption` argument;
  - both digit styles.
- [X] T027 Add `PageDots` and extend `ComicPanel` to take `lines: List<(String speaker, String text)>`
  in `apps/mobile/lib/core/theme/components/story.dart`; add both to the gallery
  (`features/dev/gallery/components_page.dart`). T026 passes.

### The first session's core: tests first

- [X] T028 [P] Create `apps/mobile/test/features/onboarding/domain/first_session_test.dart`, one group
  per row of contracts/first-session.md "Answers":
  - `launchTarget` for `newPlayer`, `offline`, `timedOut`, `notFirstOpen`, `restored`, with and
    without progress, opening done, a name, and no opening scene;
  - `beforeStart`: a due scene first; the fuel lesson for the last tutorial trip with `plays == 0`,
    or for any tutorial trip with liters < 1 outside an unlimited window; never once granted or done;
    never for a non-tutorial trip;
  - `onArrivalAtHome`;
  - `nextAfterResult` along the five trips, then `/home`;
  - `inFirstSession`, `coachFor` (first finish only), `boostersLocked`;
  - `tutorialDone` with five tutorial trips and with three (the sample);
  - `tutorialTrips` derived from the pack (the line whose unlock is `start`, the first five by
    number).
- [X] T029 [P] Create `apps/mobile/test/features/onboarding/data/drift_first_session_store_test.dart`:
  - each write is idempotent;
  - `step_reached` refuses to go down;
  - `scenes_due`/`scenes_seen` add without duplicates;
  - the row is created on first write.

### The first session's core: implementation

- [X] T030 Create `apps/mobile/lib/features/onboarding/domain/first_session.dart`:
  `FirstSessionFlags`, `FirstSessionFacts`, sealed `BeforeStart` (`DueScene(sceneId)`,
  `FuelLessonDue()`), `FirstSession` with every answer in contracts/first-session.md, and
  `tutorialTripsOf(Pack)` (research R3). T028 passes.
- [X] T031 Create `apps/mobile/lib/features/onboarding/data/drift_first_session_store.dart` (the only
  writer of `first_session`): `flags` stream, `markOpeningDone`, `addSceneDue`, `markSceneSeen`,
  `markFuelLessonDone`, `reachStep(n)` (monotonic), `markDone`. T029 passes.
- [X] T032 Create `apps/mobile/lib/features/onboarding/onboarding_providers.dart`:
  - `firstSessionFlagsProvider` (stream of the row);
  - `firstSessionProvider` (a `FirstSession` from the flags, `economyViewProvider` and the active
    content);
  - `firstSessionStoreProvider`.

  Run `build_runner`.

**Checkpoint**: The schema carries `plays` through the kit and B04; the sample has its opening scene;
database v4 migrates; both operations work in the economy and map from the server's state; the first
session answers every question in pure tests.

---

## Phase 3: User Story 1 - A new player is driving within seconds (Priority: P1) 🎯 MVP

**Goal**: Boot sends a new player to the opening scene, then the Name card, then tutorial trip 1; a
restored player goes to Home.

**Independent Test**: A fresh install with the network off: «يلا» ×3, «تمام», and trip 1 starts within
20 s, and the playtest Home then shows the chosen name. With «تخطّى» and with the network on, the
same.

### Tests for User Story 1 ⚠️ (write first, must fail)

- [X] T033 [P] [US1] Create `apps/mobile/test/features/onboarding/domain/name_pool_test.dart`:
  `namePool` from the ARB has at least 20 names, no duplicates, and each is `ok`.
- [X] T034 [P] [US1] Create `backend/apps/accounts/tests/test_name_pool.py` (research R7):
  - read `apps/mobile/lib/l10n/app_ar.arb`'s `namePool`;
  - split on «،»;
  - run each name through the `settings_update` name validator with the seeded `NameFilterEntry`
    list;
  - assert 0 refusals.
- [X] T035 [P] [US1] Extend `apps/mobile/test/features/boot/boot_screen_test.dart`:
  - each `FirstOpenOutcome` lands on `launchTarget`'s location;
  - an unfinished trip still wins;
  - `restored` sets `opening_done_at_ms`;
  - a relaunch after the opening and before the name lands on `/onboarding/name`;
  - a relaunch after the name and before trip 1's first frame lands on `/trip/<trip 1>` (FR-002).
- [X] T036 [P] [US1] Create `apps/mobile/test/features/onboarding/presentation/scene_player_test.dart`:
  - «يلا» advances one panel; on the last it finishes;
  - «تخطّى» and back finish at once;
  - finishing the opening sets `opening_done_at_ms` and goes to `/onboarding/name`;
  - a pack without an opening scene redirects `/onboarding/intro` to `/onboarding/name`;
  - the narrator line is the caption chip, and two speaking lines make two bubbles;
  - the semantics read order (contracts/scenes.md);
  - reduced motion: a 150 ms fade;
  - opening the scene writes step 1 (`stepReached`), never lowering a later one.
- [X] T037 [P] [US1] Create `apps/mobile/test/core/art/panel_art_test.dart`:
  - `opening_key` maps to its asset;
  - an unknown slug renders `PanelFallback`, with each speaker but `narrator` as a `CharacterAvatar`
    and the current speaker in front.
- [X] T038 [P] [US1] Create `apps/mobile/test/features/onboarding/presentation/name_screen_test.dart`:
  - the field holds the seeded suggestion; the dice changes it, never to the same;
  - «تمام» disabled (45%, no lip) for empty, spaces, 1 character, digits only and a bidi mark;
  - the field stops at 16;
  - the keyboard's done key acts like «تمام»;
  - back does nothing;
  - with the keyboard up, the whole card stays visible;
  - «تمام» records one `settings_update` with the normalized name and goes to `/trip/<trip 1>`,
    offline;
  - with no opening scene in the pack, opening the Name card writes step 1.
- [X] T039 [P] [US1] Add the `Intro` design checks (contracts/ci-checks.md):
  - `apps/mobile/test/design/samples/intro.dart` (the sample's `opening` scene, panel 1);
  - `apps/mobile/test/goldens/design/intro_goldens_test.dart`;
  - `apps/mobile/test/design/intro_layout_test.dart`: taps box 2 «تخطّى» and box 14 «يلا» within
    ±2 pt.
- [X] T040 [P] [US1] Add the `Name` design checks:
  - `samples/name.dart` (seed giving «حمادة»);
  - `name_goldens_test.dart`;
  - `name_layout_test.dart`: box 9 (the dice, «اقترح اسم تاني»), box 12 «تمام» and the field (box 8).
- [X] T041 [P] [US1] Update `apps/mobile/test/core/routing/route_table_test.dart` and
  `navigation_test.dart`:
  - the two new destinations (contracts/first-session.md "New routes"), with their links;
  - intro → name → trip by the real screens' buttons, not placeholder links;
  - the all-destinations goldens include the two new routes;
  - the playtest Home shows the driver's name: «الأسطى» before one is saved, the saved one after.

### Implementation for User Story 1

- [X] T042 [US1] Add to `apps/mobile/lib/l10n/app_ar.arb`, verbatim from contracts/name.md and
  contracts/scenes.md, with descriptions:
  - `introSkip`, `introNext`, `introPageOf` (`n` and `total` as preformatted Strings);
  - `nameTitle`, `nameSubtitle`, `nameFieldLabel`, `nameSuggestAnother`, `nameHelper`, `nameCta`,
    `driverNameDefault`;
  - `namePool` (the 24 names, separated by «،»).

  Run `fvm flutter pub get` (l10n). T033 passes, and T034 passes in the backend.
- [X] T043 [US1] Create `apps/mobile/lib/core/art/panel_art.dart`: `PanelArt.assetFor(slug)` (a
  const map, today `opening_key`) and `PanelFallback(speakers:, current:)`, which draws
  `ColorTokens.sceneSky`, a street strip, and each speaker but `narrator` at 1.6×, the current one in
  front. T037 passes.
- [X] T044 [US1] Create `apps/mobile/lib/features/onboarding/presentation/scene_player.dart` (contracts/
  scenes.md "The player"):
  - the `Intro` layout from 008.5's components, `PageDots` and the extended `ComicPanel`;
  - the narrator line as the caption;
  - panel motion constants;
  - an `onFinished` callback.

  Create the `/onboarding/intro` page, which writes step 1 when it opens, plays the pack's `opening`
  scene, marks it done through the store, and goes to `/onboarding/name`. T036 passes.
- [X] T045 [US1] Create `apps/mobile/lib/features/onboarding/presentation/name_screen.dart`
  (contracts/name.md "The Name card"):
  - the `Name` artboard's blocks;
  - `CharacterAvatar('usta')`;
  - `AppTextField(maxLength: 16)`;
  - the dice with `dice.svg`;
  - `PopScope(canPop: false)`;
  - the card lifted by `viewInsets`;
  - on open, step ≥ 1 through the store (the first step when the pack has no opening scene);
  - «تمام»: `economy.setDisplayName`, then `context.go('/trip/<tutorialTrips[0]>')`.

  The first suggestion's seed comes from a provider, so tests inject it. T038 passes.
- [X] T046 [US1] Add `driverNameProvider` to `apps/mobile/lib/features/onboarding/onboarding_providers.dart`:
  the view's `displayName`, else `driverNameDefault` (contracts/name.md "The name shown").
  - It reads only the economy's projection, never M06's `account.display_name` (data-model.md "Two
    copies of the name, two jobs").
  - Show it in the playtest Home's header in `router.dart` (dev and staging), the one screen that
    shows the name until M08 builds Home.

  T041's name check passes.
- [X] T047 [US1] Update `apps/mobile/lib/core/routing/routes.dart` and `router.dart`:
  - add `onboardingScene` (`/onboarding/scene/:sceneId`, page, links `trip`, `home`) and
    `onboardingFuel` (`/onboarding/fuel`, page, links `trip`);
  - set `onboardingName`'s links to `trip`;
  - `_page` builds the scene player and the Name screen;
  - add the redirect `/onboarding/intro` → `/onboarding/name` when the pack has no opening scene;
  - add a `safeThen(String?)` helper that accepts only `/trip/<id>` and `/home`, anything else
    becoming `/home`.

  T041 passes.
- [X] T048 [US1] Update `apps/mobile/lib/features/boot/boot_screen.dart` (contracts/first-session.md
  "Boot"):
  - keep the outcome from `_waitForFirstOpen`;
  - after `handOver()`: an unfinished trip as before, else `context.go(firstSession.launchTarget(outcome))`;
  - `restored` sets `opening_done_at_ms`.

  T035 passes.
- [X] T049 [US1] Make T039 and T040 pass:
  - run `fvm flutter test --update-goldens test/goldens/design/{intro,name}_goldens_test.dart` on
    Linux;
  - review the images beside `docs/design/png/{Intro,Name}.png`
    (`--dart-define=DESIGN_COMPARE=true`);
  - list the expected differences in the test files.

**Checkpoint**: US1 works alone: a new player goes through the opening scene and the Name card into
trip 1 offline, and a restored player lands on Home.

---

## Phase 4: User Story 2 - بلية teaches the five tutorial trips (Priority: P1)

**Goal**: Each tutorial trip's lesson shows at its moment, from the trip's state, with the scrim, the
hole, بلية and his line. The trip's clock keeps running, and the boosters show the locked bar.

**Independent Test**: Play each fixture trip on a fresh profile: each step starts at its moment,
only the target responds, the lines name the real amount and station, and doing what بلية asks ends
the step. A replay after a finish shows no coach.

### Tests for User Story 2 ⚠️ (write first, must fail)

- [X] T050 [P] [US2] Create `apps/mobile/test/features/onboarding/domain/tutorial_coach_test.dart`,
  one group per row of contracts/coach.md "Lessons". States come from running the real engine on
  `tutorialContent()`'s trips to the moment:
  - lesson 0: starts on the first `paidIn > 0`; target `tray`; ends on a tap or after
    `trip_bubble_min_ms_line_hay`;
  - lesson 1:
    - the first owed passenger;
    - `trayCell(v100)` with `giveChange(300, v100, 3)` while the hand holds less;
    - then `passenger(p)` with `tapRider`;
    - ends when a `change` token targets `p`;
    - the fallback (`coin` null, target `tray`) when no single coin pays;
  - lesson 2: `stationCountdown` first, then as lesson 1; ends at the stop;
  - lesson 3: the asleep passenger; ends when not asleep;
  - lesson 4: no in-trip step;
  - a step ends when its target leaves; one step at a time; `done` steps don't repeat; a rebuilt
    state brings the open step back.
- [X] T051 [P] [US2] Create `apps/mobile/test/helpers/coached_player.dart`: drives a `TripController`
  by taking each step's active target (a tray cell is a `pick`, a passenger a `tapPassenger`), and
  otherwise lets time run. It returns the result and the step ids seen. Add a self-test.
- [X] T052 [P] [US2] Create `apps/mobile/test/features/onboarding/tutorial_content_test.dart`
  (FR-047):
  - the coached player on each of `tutorialContent()`'s five trips sees every lesson's steps (none
    for lesson 4) and finishes with at least one star;
  - the same on `assets/content/release` when a pack is there, skipped otherwise.
- [X] T053 [P] [US2] Create `apps/mobile/test/features/trip/application/trip_controller_coach_test.dart`:
  - `TripModel.coach` is set only when `coachFor` gives a lesson;
  - `HintState` shows nothing while a step shows;
  - the memory resets on `open`;
  - after a kill and resume, the open step returns;
  - the clock advances during a step (Clarifications Q1);
  - بلية's bubble and the two-bubble limit (contracts/coach.md "بلية's bubble"):
    - with two rider bubbles up, a step starts without its bubble, which appears when one leaves;
    - while it shows, a second rider line waits;
    - a step that ends early keeps the bubble until its minimum time;
    - a hint follows the same rules;
  - extend `test/features/trip/domain/bubble_queue_test.dart`: with `reserved: 1`, at most one rider
    bubble shows; with the default `reserved: 0`, M02's cases are unchanged.
- [X] T054 [P] [US2] Create `apps/mobile/test/features/onboarding/presentation/coach_layer_test.dart`:
  - a tap outside the hole changes nothing;
  - a tap inside reaches the tray cell or the passenger (one command sent);
  - lesson 0's tap anywhere is consumed;
  - the hole follows the target after a relayout (a text-scale change);
  - `SemanticsService.announce` fires once per step with «بلية: …»;
  - only the target is focusable;
  - reduced motion: no ring pulse and no hand bob;
  - back opens the pause card, and the step returns after resume;
  - when a step ends before its bubble's minimum time, the scrim, the hole and the hand go at once and
    a tap outside reaches the game again, while بلية and the bubble stay until the time is up.
- [X] T055 [P] [US2] Create `apps/mobile/test/repo/coach_state_reads_test.dart`: `.balance` and
  `.paidIn` of `PassengerState` appear in `lib/` only under `features/trip/domain/projection.dart`
  and `features/onboarding/domain/`.
- [X] T056 [P] [US2] Create `apps/mobile/test/features/trip/presentation/boosters_locked_bar_test.dart`:
  - 44 tall, r 14, `dashboard.raised`, the lock icon and the text, centred;
  - semantics is a label, not a button;
  - `TripFacts.boostersLocked` swaps it for `BoostersRow`, and no booster control exists;
  - both digit styles.
- [X] T057 [P] [US2] Replace `apps/mobile/test/design/samples/tutorial_hint.dart` with
  `samples/tutorial.dart`:
  - the fixture's `line_hay.02` when the change is due;
  - the coach on the «١» cell (`v100`);
  - the locked bar.

  Then update `tutorial_goldens_test.dart` and `tutorial_layout_test.dart` to match the hole, the
  hand, بلية, the bubble and the locked bar (boxes 48, 49). Keep the two drawn riders skipped with
  008.5 R7's reason. Remove the "M07's" pending notes.

### Implementation for User Story 2

- [X] T058 [US2] Add the coach strings to `apps/mobile/lib/l10n/app_ar.arb`, verbatim from
  contracts/coach.md "Lines":
  - `coachFareArrived`, `coachGiveChange` (plural `count`), `coachGiveChangeAny`, `coachTapRider`,
    `coachStopNear`, `coachWakeSleeper`, `coachName`, `coachAnnouncement`;
  - `coachCoinName` (a `select` on the `Denomination` names);
  - `tripBoostersLocked`.
- [X] T059 [US2] Create `apps/mobile/lib/features/onboarding/domain/tutorial_coach.dart`:
  - `CoachInput`, `CoachView`, sealed `CoachTarget` (`tray`, `trayCell`, `passenger`,
    `stationCountdown`), sealed `CoachLine`, `CoachStepId`, `CoachMemory`;
  - `TutorialCoach.step`, with the coin rule (the largest `d` with `balance % d == 0` and
    `tray[d] ≥ balance / d`).

  T050 passes.
- [X] T060 [US2] Create `apps/mobile/lib/features/trip/presentation/coach_anchors.dart`:
  - `CoachAnchors` (a `ChangeNotifier` map `CoachAnchorId → Rect`, provided by `TripScope`);
  - `CoachAnchor(id, child)`, a render proxy that reports `localToGlobal` rects after layout;
  - wrap `Tray` (`tray`), each `TrayCell` (`trayCell(<denom>)`) and the `StationStrip`'s countdown
    chip (`stationCountdown`) in `presentation/dashboard/tray.dart` and `presentation/top_bar/`.
- [X] T061 [US2] Add the coach to the trip:
  - `TripModel.coach` (`CoachView?`) in `application/trip_phase.dart`;
  - in `application/trip_controller.dart`: take `TutorialCoach?` and its lesson; keep a
    `CoachMemory` (reset on `open`); call `step` on each publish; record a step done when its end
    holds; skip `HintState` while a step shows;
  - بلية's bubble (contracts/coach.md "بلية's bubble"):
    - `BubbleQueue.at(…, reserved:)` in `domain/bubble_queue.dart`, default 0;
    - `PresentationMemory` keeps بلية's bubble from a step or a hint;
    - it shows only when at most one rider bubble is up, and passes `reserved: 1` while it shows;
    - it stays for its minimum time after its step ends;
    - `HintLayer` draws the hint's from there;
  - `tutorialCoachProvider(tripId)` in `onboarding_providers.dart` (`coachFor`, plus US6's debug
    switch, false until then), read in `trip_providers.dart`.

  T053 passes.
- [X] T062 [US2] Create `apps/mobile/lib/features/onboarding/presentation/coach_layer.dart`
  (contracts/coach.md "The overlay"):
  - `CoachMark(target:, children:, showHand: true)`, with the target from `CoachAnchors` or the
    seat's hit rect plus the scene origin;
  - بلية and the `SpeechBubble.character` in `IgnorePointer`, from the presentation memory's بلية
    bubble (T061). After the step ends, the layer keeps only بلية and the bubble, untouchable, until
    the bubble's time is up;
  - the announcement and the focus;
  - the motion constants `coachScrimFade` (200 ms) and `coachHoleMove` (250 ms, `easeOutCubic`) in
    `trip_motion.dart`.

  Insert it in `presentation/trip_screen.dart` above `HintLayer` and below the cards, while
  `phase == running`. T054 passes.
- [X] T063 [US2] Create `apps/mobile/lib/features/trip/presentation/dashboard/boosters_locked_bar.dart`.
  Add `TripFacts.boostersLocked` (from `firstSessionProvider.boostersLocked`, read in
  `trip_providers.dart`), and swap the bar for `BoostersRow` in `dashboard.dart`. T056 passes.
- [X] T064 [US2] Make T051, T052, T055 and T057 pass:
  - regenerate the `Tutorial` goldens on Linux;
  - review them beside `docs/design/png/Tutorial.png`;
  - list the expected differences.

**Checkpoint**: US1 + US2 make the MVP. A new player is taught the change, the stop and the sleeper
inside real trips, offline.

---

## Phase 5: User Story 3 - The first session holds together (Priority: P2)

**Goal**: The guided order (Clarifications Q2), the سلمى scene after trip 3, the fuel lesson and the
tutorial gift before trip 5, resumes after a kill, a late restore, and the steps for M15.

**Independent Test**: The whole first session offline in the integration test: the scene once, the
lesson once, a full tank, the locked bar in all five trips, and Home at the end. Kills at every step
resume correctly. Online, the server holds one tutorial gift.

### Tests for User Story 3 ⚠️ (write first, must fail)

- [X] T065 [P] [US3] Create `apps/mobile/test/features/onboarding/application/first_session_service_test.dart`:
  - a first finish of `line_hay.03` adds its `after_trip` scene to `scenes_due`;
  - a later finish doesn't;
  - a restored progress doesn't;
  - starts write steps 2, 3, 4, 7 and 8;
  - the scene writes 5, the ask's place 6;
  - `done_at_ms` once `tutorialDone`.
- [X] T066 [P] [US3] Create `apps/mobile/test/core/routing/first_session_redirect_test.dart`:
  - `/trip/<id>` goes first to a due scene, then to the trip;
  - the fuel lesson for trip 5's first start and for an empty tank, then the trip;
  - `/home` with a due scene plays it, then Home;
  - boot's resume of the unfinished trip is never redirected;
  - a `then` outside `/trip/…` and `/home` becomes `/home`.
- [X] T067 [P] [US3] Create `apps/mobile/test/features/trip/presentation/result_continue_test.dart`:
  - on the placeholder result, «كمّل» (key `first-session-continue`) appears while `inFirstSession`
    and after the last tutorial trip;
  - it goes to `nextAfterResult`;
  - it is absent afterwards;
  - Home stays linked.
- [X] T068 [P] [US3] Create `apps/mobile/test/features/onboarding/presentation/fuel_lesson_screen_test.dart`:
  - the gauge starts at the current liters;
  - the button calls `grantTutorialGift` once, marks the lesson done, and goes to `/trip/<then>`;
  - `alreadyGranted` carries on without error;
  - back does nothing;
  - a kill before the button leaves no gift and no mark;
  - reduced motion draws the gauge full;
  - the refill line uses `fuel_regen_minutes` with its plural.
- [X] T069 [P] [US3] Create `apps/mobile/test/features/onboarding/application/first_session_lifecycle_test.dart`:
  - a `progressRestoredProvider` event on `/onboarding/intro` or `/onboarding/name` with a restored
    name or progress goes to `/home` and sets the opening done;
  - on a trip route, nothing happens;
  - a name confirmed before the restore wins (FR-005).
- [X] T070 [P] [US3] Create `apps/mobile/test/features/onboarding/first_session_kill_test.dart`, on real
  SQLite with the trip records. Kill at each step (FR-051):
  - in the opening;
  - on the Name card;
  - between the name and trip 1;
  - in each trip;
  - on trip 3's result before «كمّل»;
  - in the scene;
  - on the fuel lesson before the button;
  - right after it.

  Check the next launch's target, never a repeated opening or name, and at most one `tutorial_gift`
  row not rejected.
- [X] T071 [P] [US3] Create `apps/mobile/integration_test/first_session_test.dart`
  (contracts/ci-checks.md "Integration"):
  1. `tutorialContent()`, a fresh database, outcome `offline`.
  2. The opening («يلا» ×3) and the Name card.
  3. The five trips by the coached player, with the scene after trip 3 and the fuel lesson before
     trip 5.
  4. Home.
  5. Then online against `FakeApi`: exactly one `settings_update` and one `tutorial_gift`.

  Along the way, assert SC-002:
  - each of lessons 0–3's steps is seen in its trip;
  - the locked bar shows, and no booster control exists, in all five trips;
  - the after-trip scene plays exactly once;
  - the fuel lesson shows once, and the tank is full when trip 5 starts;
  - the session ends on `/home`.
- [X] T072 [P] [US3] Create `apps/mobile/test/backend/first_session_sync_test.dart` (tag `backend`):
  - both operations reach the dev stack and come back in GET /v1/state (`grants.tutorial`,
    `display_name`);
  - a second `tutorial_gift` is `already_granted`.

### Implementation for User Story 3

- [X] T073 [US3] **Owner step (blocks T080; T079 is aligned to it afterwards):**
  1. Draw `FuelLesson` on the Claude Design canvas «وصّل الأجرة — Design» from contracts/fuel-lesson.md
     Part 1, with the five missing comic panels (research R15): `opening_stand`, `opening_go`, and
     the سلمى scene's three.
  2. Export it with `docs/design/tools`: `export.py`, `boxes.py` + `boxes_post.py`, and
     `build_assets.py`.
  3. Commit `docs/design/screens/FuelLesson.html`, `png/FuelLesson.png`, `boxes/FuelLesson.json`, the
     new illustrations and `manifest.json`.
  4. Map the new panel slugs in `PanelArt` and `sync_assets.dart`.

  Until then, the panels show `PanelFallback`.
  Done on 2026-10-28:
  - The owner drew the six boards on the canvas, with Claude Design.
  - Claude exported only the six new boards: other boards' boxes and PNGs differ by a point from a
    newer Chromium's font shaping, and the brand page was never exported.
  - The five slugs are mapped.
- [X] T074 [US3] Create `apps/mobile/lib/features/onboarding/application/first_session_service.dart`:
  - it listens to the economy's views and writes the flags of contracts/first-session.md "Events that
    write the flags";
  - `FirstSessionHooks` with an async `afterScene`, a no-op;
  - wired as a keep-alive provider started in `bootstrap/app.dart`.

  T065 passes.
- [X] T075 [US3] Add the redirects to `apps/mobile/lib/core/routing/router.dart` (contracts/first-session.md
  "Router"):
  - `/trip/:tripId` (unless it is the unfinished trip) → the due scene or the fuel lesson with
    `then`;
  - `/home` → a due scene;
  - the `/onboarding/scene/:sceneId` page plays the scene by id, marks it seen, awaits
    `FirstSessionHooks.afterScene`, writes step 6, and goes to `safeThen(then)`.

  T066 passes.
- [X] T076 [US3] Add «كمّل» to the placeholder result in `apps/mobile/lib/core/routing/router.dart`'s
  result page (or `features/trip/presentation/playtest/result_summary.dart`):
  - `AppButton.primary(size: l)`, key `first-session-continue`, ARB `firstSessionContinue` «كمّل»;
  - it goes to `nextAfterResult(tripId)`.

  T067 passes.
- [X] T077 [US3] Create `apps/mobile/lib/features/onboarding/application/first_session_lifecycle.dart`
  (a listener on `progressRestoredProvider`, in the app builder in `bootstrap/app.dart`). T069
  passes.
- [X] T078 [US3] Add the fuel lesson strings to `apps/mobile/lib/l10n/app_ar.arb`, verbatim from
  contracts/fuel-lesson.md: `fuelLessonTitle`, `fuelLessonSpeaker`, `fuelLessonLine`,
  `fuelLessonGauge`, `fuelLessonRefill` (plural `minutes`) and `fuelLessonCta`.
- [X] T079 [US3] Create `apps/mobile/lib/features/onboarding/presentation/fuel_lesson_screen.dart`:
  - built now from contracts/fuel-lesson.md Part 1 (its blocks, sizes and strings), so the
    integration test (T071) isn't held up by the drawing; once T073's board is exported, aligned to
    it in the same PR;
  - the gauge from Rive's `FuelGauge` contract, with the static and `ProgressBar` fallbacks;
  - the needle sweep (600 ms, `easeOutCubic`);
  - the button's three steps (contracts/fuel-lesson.md Part 2).

  Add the `/onboarding/fuel` page. T068 passes.
- [X] T080 [US3] (after T073) Add the `FuelLesson` design checks:
  - `apps/mobile/test/design/samples/fuel_lesson.dart` (1/5 → full);
  - `test/goldens/design/fuel_lesson_goldens_test.dart`;
  - `test/design/fuel_lesson_layout_test.dart` against `boxes/FuelLesson.json`.

  Regenerate the goldens on Linux and review them side by side.
  Done on 2026-10-28, with T079 aligned to the board:
  - the circles and the frame are `Name`'s;
  - the gauge is the board's, with the pump inside the arc and the marks E and F (new ARB strings
    `fuelGaugeEmpty` and `fuelGaugeFull`);
  - Rive's `FuelGauge` is drawn at 1.5× so its arc lies on the board's;
  - the refill line is on the board's 18 pt line.

  The golden test lists the expected differences.
- [X] T081 [US3] Make T070, T071 and T072 pass.
  - Run the integration test with `fvm flutter test integration_test/first_session_test.dart -d linux`.
  - Run the backend case in the `sync-e2e` way: stack up, seed, then `--tags backend`.

**Checkpoint**: US1–US3 work. The first session runs from first open to Home in the product spec's
order, survives kills, and syncs one gift.

---

## Phase 6: User Story 4 - The driver's name reaches the server (Priority: P2)

**Goal**: A refused name rolls back without a balance toast and is asked again on Home as a sheet.

**Independent Test**: With `FakeApi` refusing the name: the playtest Home's name falls back, no toast, and the
next arrival at Home opens the sheet with the refused line and a fresh suggestion, at most once per
launch.

### Tests for User Story 4 ⚠️ (write first, must fail)

- [X] T082 [P] [US4] Extend `apps/mobile/test/core/sync/sync_engine_test.dart`:
  - a rejected `settings_update` sets no toast;
  - a rejected `tutorial_gift` does;
  - the rejected name row's reason is stored.
- [X] T083 [P] [US4] Create `apps/mobile/test/features/onboarding/presentation/name_sheet_test.dart`:
  - the sheet with and without `nameRefusedLine`;
  - «تمام» records a new `settings_update` and closes;
  - drag, ✕, back and the scrim dismiss it;
  - both digit styles (goldens).
- [X] T084 [P] [US4] Create `apps/mobile/test/features/onboarding/presentation/name_reask_host_test.dart`:
  - on Home with `nameRefused`, the sheet opens once, and not again in the same launch;
  - with no name after a trip has started, it opens without the line;
  - never during a trip;
  - a new launch opens it again until a name is accepted.
- [X] T085 [P] [US4] Extend `apps/mobile/test/backend/first_session_sync_test.dart`: a name in the
  seeded filter comes back `rejected` with `validation_error`, and the phone's `nameRefused` turns
  true.

### Implementation for User Story 4

- [X] T086 [US4] In `apps/mobile/lib/core/sync/sync_engine.dart`, make `_isVisible` return false for
  `OpType.settingsUpdate`, with a comment naming research R7. T082 passes.
- [X] T087 [US4] Create `apps/mobile/lib/features/onboarding/presentation/name_sheet.dart` (the Name
  card's content in an `AppSheet`, contracts/name.md "The re-ask") and `name_reask_host.dart`.
  - Put `NameReaskHost` in Home's page in `router.dart` (the placeholder and the playtest Home).
  - Add `nameRefusedLine` to `app_ar.arb`.
  - Refactor `name_screen.dart` to share the card content with the sheet.

  T083 and T084 pass.
- [X] T088 [US4] Add a `NameFilterEntry` for a test term to
  `apps/mobile/test/backend/seed_backend.py`, and make T085 pass.

**Checkpoint**: US1–US4 work. The name the player picks reaches the server, and a refusal is handled
kindly.

---

## Phase 7: User Story 5 - Short screens keep every minimum (Priority: P2)

**Goal**: The compact profile below `T + 764`, closing M02's exception (contracts/compact-trip-layout.md).

**Independent Test**: The size tests at 360×640 and 360×720, at text scales 1.0 and 1.3, for both
vehicles: every minimum met and every play control in the bottom third.

### Tests for User Story 5 ⚠️ (write first, must fail)

- [X] T089 [P] [US5] Extend `apps/mobile/test/features/trip/domain/scene_layout_test.dart`:
  - the profile switches at `T + 764`;
  - compact heights: HUD 72, dashboard 226, scene `H − T − 282`;
  - the `micro_old` compact table at scenes 334 (360 and 390 wide) and 407 (C y 46 at 0.6, B 122 at
    0.66, A 206 at 0.952, front 284 at 0.952, hand (162, 290));
  - 008.5's table from 408;
  - the tuktuk at `scene − 136`, scale 1.15;
  - hit areas ≥ 44×44 and not overlapping;
  - every face at its minimum.
- [X] T090 [P] [US5] Extend `apps/mobile/test/a11y/trip_minimum_sizes_test.dart` and
  `test/helpers/trip.dart`:
  - add the `mid` surface (360×720, T 24) to `TripSurface`;
  - make `small` (360×640, T 24) compliant;
  - check every US1–US6 case on all four surfaces at 1.0 and 1.3;
  - a coach step on `small` and `mid` at 1.0 and 1.3 (lesson 1 on the fixture's `line_hay.02`, when
    the change is due): the hole, بلية, the hand and the bubble are fully on screen, and the bubble's
    text is ≥ 15 pt (FR-042);
  - the bottom-third test: every tappable outside the scene, except pause and debug, has
    y ≥ 2H/3.
- [X] T091 [P] [US5] Create `apps/mobile/test/features/trip/presentation/compact_profile_test.dart`:
  - the compact HUD: pause, the full strip, the 6 pt reputation bar, and the low chip under 40%;
  - the compact dashboard: the one-line log on top, then the four rows;
  - the pause card shows the trip's title only in the compact profile.

### Implementation for User Story 5

- [X] T092 [US5] In `apps/mobile/lib/features/trip/domain/scene_layout.dart`, add `TripProfile`
  (`regular`, `compact`) to `TripZones`, the compact heights, and the compact seat tables, verbatim
  from contracts/compact-trip-layout.md. Rules:
  - y = `design y − (334 − scene)`;
  - below a 334 pt scene, scale by `scene / 334` with hit areas clamped to 44;
  - hit rects narrowed at midpoints.

  T089 passes.
- [X] T093 [US5] Build the compact `TripHud` in `apps/mobile/lib/features/trip/presentation/top_bar/`:
  - the 64 pt row with pause and `StationStrip`;
  - `ReputationBar` as a 6 pt bar inside the strip card, with its semantics, and the «تحت ٤٠٪» chip;
  - station labels wrap, never clip.
- [X] T094 [US5] Build the compact `Dashboard` in `apps/mobile/lib/features/trip/presentation/dashboard/dashboard.dart`:
  rows at 8 (the log, one line, 20), 32, 80, 128 and 176 (44 each), with 6 at the bottom. The log
  stays a live region.
- [X] T095 [US5] Show the trip's title in the pause card's header in the compact profile
  (`presentation/cards/pause_card.dart`), and pick the profile in `trip_screen.dart`. T090 and T091
  pass.
- [X] T096 [US5] Regenerate the trip goldens' `small` images and add `mid` ones for US1 and the
  `Tutorial` state (`test/goldens/trip/`), on Linux. Attach the 360×640 images for the owner's
  approval.
- [X] T097 [US5] Close the exception in the documents:
  - `specs/008-m02-trip-screen/plan.md` Complexity Tracking: mark it closed by M07;
  - `specs/008.5-m21-design-refresh/contracts/trip-layout.md` "The exception": a pointer to
    `specs/012-m07-onboarding/contracts/compact-trip-layout.md`.

**Checkpoint**: US1–US5 work. Constitution XI holds on every supported screen.

---

## Phase 8: User Story 6 - Testers can replay the first session (Priority: P3)

**Goal**: The «Onboarding» card on the playtest Home (dev and staging).

**Independent Test**: On a staging-flavored widget test, each first-session screen opens from the
card, and "coach everywhere" coaches a finished tutorial trip. A prod build has none of it.

- [X] T098 [P] [US6] Create `apps/mobile/test/features/dev/onboarding_card_test.dart`:
  - the card opens the opening scene, the Name card, an after-trip scene and the fuel lesson (each
    with `then=/home`);
  - the switch makes `coachFor` return a lesson for a finished tutorial trip;
  - the trip list marks tutorial trips;
  - with `Flavor.prod`, neither the card nor the switch exists.
- [X] T099 [US6] Create `apps/mobile/lib/features/dev/onboarding_card.dart` and the in-memory
  `coachEverywhereProvider`, read by `tutorialCoachProvider`. Add the card to the playtest Home in
  `router.dart` beside `TripList`, and mark tutorial trips in `presentation/playtest/trip_list.dart`.
  The card's labels are dev-only strings in `app_ar.arb`, like the existing playtest ones. T098
  passes.

**Checkpoint**: All six stories work.

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Documents, the full checks, the reviews and the owner's list.

- [X] T100 [P] Update `docs/architecture-mobile.md`:
  - §5: the `features/onboarding/` tree;
  - §8: the compact profile, and the end of the exception;
  - §9: `/onboarding/scene/:sceneId` and `/onboarding/fuel`;
  - §12: `settings_update` and `tutorial_gift` as local operations; `player_state`; the name's
    rollback.
- [X] T101 [P] Document `Scene.plays` and the `narrator` convention in `docs/architecture-backend.md`
  (the content section), `content/README.md` ("Scenes") and B04's authoring notes in
  `docs/runbooks/content-publishing.md`.
- [X] T102 [P] Update `docs/delivery-plan.md`:
  - Design sources: `FuelLesson` in M07's row;
  - step 7: HANDOFF §9.3 #3 resolved in M07 (research R18);
  - Progress: M07's line when it merges.
- [X] T103 [P] Update `CLAUDE.md`:
  - the writers rule: `player_state` by the economy store, `first_session` by
    `lib/features/onboarding/data/drift_first_session_store.dart`;
  - the tutorial fixture (`apps/mobile/test/fixtures/tutorial/`) and where it comes from;
  - the guards list: the coach's state reads.
- [X] T104 Add M07's section to `docs/owner-actions.md`, each item with its task id, and update
  "Open now".
  - **Before the fuel lesson's design checks (T080):** T073.
  - **Before merge:**
    - approve the coach lines (T058), the fuel lesson's lines (T078), the name pool, the refused
      line and the default name (T042, T087), and the compact look (T096);
    - quickstart Part B on the Redmi Note 7 with the draft imported (T106).
  - **After merge:**
    - SC-001 timed on the Galaxy A06;
    - `tool/perf/trip_fps.sh` on a coached tutorial trip;
    - the moderated playtest with five new players (SC-007);
    - the release draft's opening scene and `plays` on `content-core-r1` (research "Handed to later
      features").
- [X] T105 Run quickstart.md Part A in full: the content kit, the backend, and the app (format,
  analyze with `--fatal-infos`, `flutter test --coverage --exclude-tags backend`, coverage ≥ 80%, the
  integration test, and `sync-e2e`). Fix anything it finds.
- [ ] T106 Run quickstart.md Part B on the Redmi Note 7 (steps 1–15) with the draft imported on the
  local stack. Record the results in the PR.
- [X] T107 Run reviews, fix CRITICAL and HIGH findings, then rerun T105.
  - **Security review** (`security-reviewer` agent) of the diff: what the sync sends; the display
    name kept out of logs; `safeThen`'s path check; B04's import of `plays` (no unchecked foreign
    key); the admin inline's permissions.
  - **Code review:** `flutter-reviewer` over the Dart diff, `python-reviewer` over the backend and
    the content kit.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: none.
- **Foundational (Phase 2)**: after Setup. Blocks every story. Within it:
  - the content path (T007–T012) and the database path (T013–T024) run side by side;
  - the components (T025–T027) and the first-session core (T028–T032) follow T022–T023, since the
    facts read the view's new fields.
- **US1 (Phase 3)**: after Foundational.
- **US2 (Phase 4)**: after Foundational. Its coach reads `coachFor` (T030). The `Tutorial` checks
  (T057) need T063's bar.
- **US3 (Phase 5)**:
  - after US1 (the scene player and the routes) and US2 (the coached player, for the integration
    test);
  - only T080 waits for the owner's T073; T079 is built from the brief first and aligned to the
    board after it.
- **US4 (Phase 6)**: after US1 (the Name card).
- **US5 (Phase 7)**: after Foundational. It touches the trip's layout files, so it is best done after
  US2's anchors (T060), whose rects it must keep correct.
- **US6 (Phase 8)**: after US2 and US3 (the screens and the switch it opens).
- **Polish (Phase 9)**: after the stories that ship.

### Within Each User Story

- Tests first, and failing, before implementation.
- Domain (pure) before the stores, before the services, before the wiring and the screens.
- Shared files (Organization) in task order.

### Parallel Opportunities

- **Setup:** T002 and T003.
- **Foundational:**
  - the helpers and guards T004–T006;
  - the content tests T007 and T011, beside the database tests T013–T018;
  - the component tests T026;
  - the core tests T028 and T029.
- **Within each story,** every test task marked [P].
- **US4 and US5** can proceed beside US3 once US1 and US2's anchors are in, since they touch
  different files except `router.dart` (US4) and `trip_screen.dart` (US5).
- **Polish:** the documents T100–T103.

---

## Parallel Example: Foundational tests

```text
T004 test/helpers/tutorial_content.dart
T005 test/repo/economy_writes_test.dart
T006 test/repo/domain_imports_test.dart
T007 content/examples/{valid,invalid}/ + tools/content_kit/tests/
T011 backend/apps/content/tests/
T013 test/core/storage/schema_v4_test.dart
T014 test/features/onboarding/domain/name_rules_test.dart
T015 test/core/economy/domain/economy_state_test.dart
T016 test/core/economy/domain/{profile,gift}_rules_test.dart
T017 test/core/economy/economy_service_test.dart
T018 test/core/sync/domain/state_snapshot_test.dart
```

## Parallel Example: User Story 2

```text
T050 test/features/onboarding/domain/tutorial_coach_test.dart
T051 test/helpers/coached_player.dart
T052 test/features/onboarding/tutorial_content_test.dart
T053 test/features/trip/application/trip_controller_coach_test.dart
T054 test/features/onboarding/presentation/coach_layer_test.dart
T055 test/repo/coach_state_reads_test.dart
T056 test/features/trip/presentation/boosters_locked_bar_test.dart
T057 test/design/samples/tutorial.dart + tutorial goldens and layout test
```

---

## Implementation Strategy

### MVP First (User Stories 1 and 2)

1. Phase 1 and Phase 2.
2. Phase 3 (US1): a new player reaches trip 1 in seconds.
3. Phase 4 (US2): بلية teaches inside the trips.
4. **Stop and validate**: quickstart Part B steps 1–3 and 6 on the phone, and T052's coached player.

### Incremental Delivery

1. US1 + US2: the MVP.
2. US3: the whole session in order, the سلمى scene, the fuel lesson and the gift. The step's "done
   when" (the integration test from onboarding through the first 5 trips) is here. Only the fuel
   lesson's design checks wait for the owner's artboard (T073).
3. US4: the name's refusal path.
4. US5: the compact layout, which closes the exception.
5. US6: the testers' card. It can come right after US2 if it helps the device runs.
6. Polish, the reviews, then one PR.

### Notes

- **[P]** tasks are in different files with no dependencies on incomplete tasks.
- Never edit a generated file: `*.g.dart`, `lib/l10n/generated/`, `_generated.py`, the content kit's
  schema copies, `packages/content_models/lib/src/generated/`, `drift_schemas/` and the generated
  `test/drift/` files.
- The sample's trips and every parity fixture stay unchanged. If a step seems to need them changed,
  stop and ask the owner.
- If a compact size test can't pass for `micro_old` at 360×640, stop and ask the owner (research R19
  "Risk"). Don't loosen the test.
- The unrelated working-tree changes in `backend/config/urls.py` and
  `backend/apps/content/tests/test_manifest.py`, found while planning, aren't M07's. Leave them out
  of M07's commits unless the owner says otherwise.
- Never stash, reset or discard to get past a failing hook. Ask the owner.
- Commit after each task or logical group, with Conventional Commits.
