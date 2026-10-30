---

description: "Task list for M10 Apartment, Story Chapters, Scenes and Family Requests"
---

# Tasks: Apartment, Story Chapters, Scenes and Family Requests (M10)

**Input**: Design documents from `specs/015-m10-apartment-story/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**:

- **Mandatory, and first** (constitution XIII). Write the tests first for:
  - the two economy operations' validators, the state mapping, the wire and the v5 migration;
  - every pure function (story, requests, rewards, the apartment and story domains, rider comments);
  - the purchases and the claim.

  Every phase writes its tests first, and they must fail before its implementation tasks start.
- **Real economy.** Economy-backed tests use the real `EconomyService` over in-memory drift
  (`apps/mobile/test/helpers/economy.dart`). The purchase and claim outcome tables also run against a
  fake `Economy`.
- **Packs.**
  - The sample pack (after T008);
  - `synthetic_packs.dart`'s new `artboardSalon()` (the artboards' salon: four pieces, نجفة 2,400,
    أنتريه 3,200, three requests, seven chapters with ch4 current) and `storyShaped()` (the release
    draft's shape: ch1–4, the salon's four pieces at 750, 1,050, 1,300 and 1,600, three requests,
    goal scenes for ch2 and ch4, `the_fatha` after `line_gamaa.18`);
  - M07's `tutorial_content.dart` for first-session states.
- **Coverage.** At least 80% of lines in `apps/mobile`, `tools/content_kit` and `backend`;
  `packages/trip_engine` keeps ≥ 90%.

**Organization**:

- **Paths and commands.** Paths are from the repository root. Dart commands run with `fvm` in
  `apps/mobile/` (or the package named). Python commands run with `uv` in the folder named.
- **Codegen.**
  - After a `@riverpod` provider: `fvm dart run build_runner build -d`.
  - After ARB keys: `fvm flutter pub get`.
  - After a schema change: `uv run wassal-content codegen` in `tools/content_kit`, then
    `build_runner` in `packages/content_models`.
  - After a drift table change: `fvm dart run drift_dev make-migrations`.
- **Exactness.** Every number is from the contracts and HANDOFF. Name each as a constant in `lib/`,
  never a bare literal. Radii, colours, type and shadows come from the tokens (the raw-style guard).
  The list:
  - **Room:**
    - the design space 358×300;
    - slot bounds x 0–334, y 0–276, w 24–358, h 24–300;
    - chips 44 high, the «+» circle 30, names ellipsised at 160, clamped 8 inside the card;
    - outlines dashed 3;
    - the drop-in about 300 ms (`MotionTokens.dialogIn`); the tab crossfade ≤ 150 ms.
  - **Rooms view:** chapter bar 56; `Segmented` 258 wide with tabs 36 high extended to the 44 row;
    the requests button 92×44 and its badge 20; grid 2 columns of 175, gap 8, cards 56.
  - **Goal view:** goal art 190 high; avatar 46; the ready CTA 64; its price chip 32.
  - **RoomDone:** the dialog from x 16 to 374, top 168; room art 260×130; CTA 60; «بعدين» 44.
  - **Requests:** avatar 52; the claim's collapse 200 ms.
  - **Viewer:**
    - panel 540 high;
    - bubbles w190 at top 120 (start side) and w180 at top 236 (end side), stagger 150 ms;
    - dots 10 → 26, gap 8;
    - «تخطّى» 44 high; the last panel's buttons 64, flex 1 : 2;
    - share 358×540 at ×3.
  - **Timeline:** rows 80 (done), 104 (current), 58 (locked); nodes 24 and 32; thumbnails 70×56;
    the rail 4.
  - **Album:** thumbnails 96; the card button 36; 2 columns, gap 12.
  - **Riders:** 1–2 per trip; `Person` looks 18–23.
  - **Checks:** layout tolerance ±2 pt; SC-009's 0.5 s and 1 s.
- **Names** are the contracts', spelled exactly:
  - **Economy:** `OpType.storyProgress` (`story_progress`), `OpType.claimRequest` (`claim_request`),
    `StoryProgressRequest`, `ClaimRequest`, `EconomyRefusal.alreadyRecorded`, `recordScene`,
    `claimRequest`, `EconomyState.scenesSeen`, `.requestsClaimed`, `EconomyView.confirmed`,
    `ConfirmedState`, `StateStory`, `StateChapter`.
  - **Progress:** `SceneMoment` (`Opening`, `AfterTrip`, `GoalMet`), `SceneState`, `sceneUnlocked`,
    `sceneState`, `scenesInStoryOrder`, `waitingScenes`, `goalSceneOf`, `afterTripSceneOf`,
    `RequestState`, `requestStates`, `RewardSource`, `PendingReward`, `pendingRewards`,
    `pendingRewardsProvider`.
  - **Apartment:** `ApartmentView` (`GoalView`, `RoomsView`), `apartmentView`, `GoalViewModel`,
    `RoomModel`, `PieceSheetModel`, `GoalPurchase`, `PiecePurchase` (`roomCompleted`,
    `chapterCompleted`), `RequestClaim`, `RoomDoneDialog`, `RequestsSheet`, `PendingChip`,
    `RoomScene`, `RoomFallback`, `PieceFallback`, `ChapterRow`, `chapterRows`, `ChaptersPage`.
  - **Providers:** `pieceStyleMemoryProvider`, `roomTabProvider`, `goalBarSeenProvider`.
  - **Story:** `StoryService` (`recordSeen`, `backfill`), `StoryDueWatcher`, `StoryAfterResultImpl`,
    `SceneSequence`, `SceneViewerPage`, `ScenePanelView`, `ScenePanelShare`, `AlbumCard`, `album`,
    `AlbumPage`, `renderOffscreenPng`.
  - **Home:** `StoryEndTarget`, `nextPiece`, `StartFrom.apartment`.
  - **Routes:** `RouteNames.storyScene` (`/story/scene/:sceneId`), `RouteNames.storyAlbum`
    (`/story/album`), `RouteNames.apartmentPreTrip` (`/apartment/pre-trip/:tripId`),
    `ParamValidators.sceneId` (`^[a-z][a-z0-9_]{1,31}$`).
  - **Trip:** `TripFacts.storyInfo`, `TripView.storyStrip` (`StoryStripView`), `RiderComment`,
    `riderComment`, `RiderComponent`, `CharacterBubble`, `characterAt`.
  - **Content:** `StoryCharacter`, `CharacterLine`, `StoryTripInfo`, `StoryRider`, `RiderComments`,
    `ItemSlot`, and the fields `goal_art`, `goal_line`, `ready_line`, `tagline`, `story_trip_info`,
    `title`, `art`, `done_line`, `slot`, `comment`, `character`.
- **Shared files.** These grow story by story, so tasks that touch them run in order:
  - `apps/mobile/lib/core/routing/{routes.dart,router.dart}`;
  - `apps/mobile/lib/l10n/app_ar.arb`;
  - `apps/mobile/lib/features/apartment/application/apartment_providers.dart`;
  - `apps/mobile/lib/features/apartment/presentation/{apartment_screen.dart,rooms_view.dart}`;
  - `apps/mobile/lib/features/story/story_overrides.dart`;
  - `apps/mobile/lib/bootstrap/{app.dart,bootstrap.dart}`;
  - `apps/mobile/test/helpers/{synthetic_packs.dart,pump_app.dart}`;
  - `apps/mobile/test/repo/domain_imports_test.dart`.
- **No engine rule, tunable, server rule or B03 change** (plan). The engine gains one export line. The
  backend change is B04's content app only. A task that seems to need more is wrong; stop and ask.
- **One PR.** Its description lists:
  - the departures from the design (plan "Complexity Tracking");
  - the changes to merged code (plan "What changes in merged code");
  - the expected golden differences (research R18);
  - the staging rebuild after deploy (research R16).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story the task belongs to (US1–US8 from spec.md)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: The apartment's art and fallbacks, and the engine's one export.

- [X] T001 [P] Add the apartment art to `apps/mobile/tool/design/sync_assets.dart` (research R17), with
  a comment naming R17:
  - `docs/design/illustrations/screens/AptGoal_01.svg` →
    `assets/illustrations/apartment/goals/goal_shabka.svg`;
  - `AptGoal_03.svg` → `assets/illustrations/apartment/teaser_room.svg`;
  - `Piece_01.svg` → `assets/illustrations/apartment/pieces/antreeh_modern.svg`;
  - `SceneViewer_01.svg` → `assets/illustrations/panels/ch4_mother_looks.svg`.

  Run `fvm dart run tool/design/sync_assets.dart`. Then:
  - create `apps/mobile/lib/core/art/apartment_art.dart`: `ApartmentArt.room(slug)`,
    `.piece(slug)` and `.goal(slug)`, each a const map from slug to asset path that returns null for
    unknown slugs;
  - add `ch4_mother_looks` to `PanelArt`'s drawings in `apps/mobile/lib/core/art/panel_art.dart`;
  - declare the folders in `apps/mobile/pubspec.yaml`.

  Run `test/repo/design_assets_test.dart`, updating only the expectations that pin these files.
- [X] T002 [P] In `packages/trip_engine/lib/trip_engine.dart` add
  `export 'src/prng.dart' show Xorshift32;` with a comment naming M10 research R15 (rider comments
  pick their line without the engine's state).
  - Add `packages/trip_engine/test/prng_export_test.dart`: the first `next()` of `Xorshift32(1)` and
    of `Xorshift32(0xDEADBEEF)` equal the values `src/prng.dart`'s own test pins.
  - Run `fvm dart test --coverage` in `packages/trip_engine`; coverage stays ≥ 90%.
  - Run `uv run wassal-solver parity` in `tools/solver`; it is unchanged.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The content fields end to end, the two economy operations with the state mapping and
schema 5, the story, request and reward rules, the test packs, the routes and the overrides.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### The content fields ([contracts/content-fields.md](./contracts/content-fields.md))

- [X] T003 Edit the schemas exactly as contracts/content-fields.md "Schemas" gives them:
  - `content/schemas/common.schema.json`: `StoryCharacter`, enum `usta`, `salma`, `bride_father`,
    `bride_mother`, `moallem`, `belya`;
  - `content/schemas/chapter.schema.json`:
    - the optional `goal_art`, `goal_line`, `ready_line`, `tagline` and `story_trip_info`;
    - `$defs` `CharacterLine`, `StoryTripInfo` (`riders` `minItems` 1, `maxItems` 2), `StoryRider`
      (`seat` pattern `^(front|[A-D])_[rml]$`, or `trip.schema.json`'s named seat def if one exists)
      and `RiderComments`;
    - `Scene.required` becomes `["scene_id", "title", "panels"]`;
    - `ScenePlays.description` becomes "When the app plays the scene by itself. Absent: when the
      chapter's goal is met (M10).";
  - `content/schemas/room.schema.json`: optional `art` (Slug) and `done_line`;
  - `content/schemas/item.schema.json`:
    - required `slot` (`ItemSlot`: integers `x` 0–334, `y` 0–276, `w` 24–358, `h` 24–300);
    - optional `comment`;
    - `ItemVariant.comment` optional;
  - `content/schemas/family_request.schema.json`: required `character` (`StoryCharacter`).

  Then, in `tools/content_kit`:
  1. `uv run wassal-content codegen`, and commit
     `src/wassal_content/schemas/*.schema.json` and `models/_generated.py`;
  2. `uv run wassal-content codegen --check`.

  `content/schemas/schema-set.json` stays `1.0`.
- [X] T004 In `packages/content_models` run `fvm dart pub get && fvm dart run build_runner build -d`.
  Confirm the generated Dart has `StoryCharacter`, `CharacterLine`, `StoryTripInfo`, `StoryRider`,
  `RiderComments` and `ItemSlot`, and the new fields on `Chapter`, `Scene`, `Room`, `Item`,
  `ItemVariant` and `FamilyRequest`. Commit `lib/src/generated/*.dart`. (Depends on T003.)
- [X] T005 [P] Write the rule tests first in `tools/content_kit/tests/test_rules.py`, one failing case
  per new code with its path (contracts/content-fields.md "Rules"):
  - **V-C6:** `story_trip_info` without `story_trip_id`;
  - **V-C7:** a rider's seat not in the trip's seats; a seat a passenger names; two riders in one
    seat;
  - **V-C8:** a comment key naming no pool; a pool line with `{amount}`;
  - **V-C9:** `fail_reason` on a trip without `rules.no_fights_required`;
  - **V-C10:** two scenes without `plays` in one chapter;
  - **V-C11:** a duplicate `scene_id` across chapters;
  - **V-C12:** three non-narrator lines in a panel;
  - **V-R3:** `x + w > 358` and `y + h > 300`;
  - **V-R4:** a request's `variant_id` not among its item's.

  Each case also passes with a valid neighbour. (Depends on T003.)
- [X] T006 Implement the nine rules in
  `tools/content_kit/src/wassal_content/rules/references.py` (`_chapter`, `_scene_plays`,
  `_narrators`, `_item`, `_family_request`; contracts/content-fields.md "Rules"), each with its code
  and JSON path. Skip V-C11 or V-R4 only if an existing rule (V-U1, V-R2) already reports exactly
  that case, and say which in a comment. Make T005 pass. (Depends on T005.)
- [X] T007 [P] Update the examples so each still reports only its own error:
  - **Add the new required fields** (`title` on scenes, `slot` on items, `character` on requests) to
    every file under `content/examples/valid/{chapter,item,family_request,pack}/` and
    `content/examples/invalid/{chapter,item,family_request}/`.
  - **New valid files:** `valid/chapter/chapter_with_story_trip_info.json` and
    `valid/item/item_with_slot.json`.
  - **New invalid files,** one per rule V-C6–V-C12, V-R3 and V-R4, and one per schema refusal:
    - `invalid/chapter/scene_no_title.json` → `$.scenes[0].title`;
    - `invalid/item/no_slot.json` → `$.slot`;
    - `invalid/item/slot_w_10.json` → `$.slot.w`;
    - `invalid/family_request/no_character.json` → `$.character`;
    - `invalid/family_request/unknown_character.json` → `$.character`.

    List them all in `invalid/expected.json`.

  Run `uv run pytest` in `tools/content_kit`. (Depends on T003, T006.)
- [X] T008 Update the sample in the export format (sorted keys, 2-space indent, trailing newline), as
  contracts/content-fields.md "The sample pack" lists:
  - `content/examples/sample/chapters/ch1_first_job.json`:
    - `goal_art`, `goal_line` (moallem), `tagline`;
    - titles on `opening` and `the_stand`;
    - `story_trip_info` for `line_hay.03`: title, condition, `fail_reason`, and one rider
      `moallem` in `A_l` with `comments.short_change` and `comments.fight`;
  - `ch2_her_father.json`: a goal scene (three panels with existing panel slugs, `title`, no
    `plays`), `goal_line`, `ready_line`;
  - `ch3_shabka.json`: `goal_art`, `goal_line` (bride_mother), `ready_line`;
  - `ch4_salon.json`: `tagline`, and a goal scene (three panels including `ch4_mother_looks`,
    `title`);
  - `rooms/salon.json`: `art`, `done_line`;
  - `items/salon.nish.json` and `items/salon.sitara.json`: `slot`, each variant's `comment`, and the
    item's `comment`;
  - `family_requests/req_nish_crystal.json`: `character: bride_mother`;
  - new `speech/story.moallem.short_change.json` and `speech/story.moallem.fight.json`, one or two
    lines each, with no digits and no placeholders.

  The texts are drafts in the characters' voice. No trip definition changes; confirm `line_hay.03`'s
  passengers don't use `A_l`. Then, in `tools/content_kit`:
  1. `uv run wassal-content validate-source ../../content/examples/sample`;
  2. `uv run wassal-content golden --update`, and review `content/examples/sample.golden.json`;
  3. `uv run wassal-content bundle dev --out ../../apps/mobile/assets/content/dev`.

  Commit `apps/mobile/assets/content/dev/{core-1.json.gz,bundled.json}`. Run `uv run wassal-solver
  parity` and `uv run pytest -n 4` in `tools/solver`: unchanged. (Depends on T003, T006.)
- [X] T009 [P] In `packages/content_models/test/`, extend the round-trip test so it reads every new
  field from the sample and the valid examples. Run `fvm dart test`. (Depends on T004, T008.)
- [X] T010 Write the B04 tests first in `backend/apps/content/tests/`:
  - new `test_story_fields.py`:
    - importing each new invalid example of T007 is refused with the kit's error;
    - the riders' order survives a round trip;
    - `StoryRider`'s `(chapter, order)` and `(chapter, seat_id)` are unique;
  - extend `test_admin_authoring.py`: every new field and the `StoryRiderInline` (`max_num=2`) save;
  - update the sample round trip (byte for byte, with the riders' row count).

  (Depends on T007, T008.)
- [X] T011 Implement B04 (contracts/content-fields.md "B04"):
  - **Models** in `backend/apps/content/models/story.py`:
    - `Chapter`: `goal_art` (slug, blank), `goal_line_speaker` (choices, blank),
      `goal_line_ar_eg`/`_ar`, `ready_line_*`, `tagline_*`, `story_title_*`,
      `story_condition_*`, `story_fail_reason_*`, with a check that `goal_line_speaker` is set
      exactly when `goal_line_ar_eg` is;
    - `StoryRider` (`chapter` FK `related_name="riders"`, `order` 1–2, `character`, `seat_id`,
      `comment_short_change`, `comment_false_accusation`, `comment_fight`, `comment_missed_stop`,
      `comment_impatient`);
    - `Scene`: `title_*`;
    - `Room`: `art`, `done_line_*`;
    - `Item`: `slot_x`, `slot_y`, `slot_w`, `slot_h` (with bound checks), `comment_*`;
    - `ItemVariant`: `comment_*`;
    - `FamilyRequest`: `character`.
  - **Migration** `backend/apps/content/migrations/0011_m10_story_fields.py`: expand-only, every
    column with `db_default` (`""`, or `0` for the slot).
  - **Services:**
    - `services/importer.py`: `chapter()` reads the five fields and recreates the riders; also
      `room()`, `item()` and `request()`;
    - `services/snapshot.py`: `chapter_part`, `scene_part` (`title` after `scene_id`, in schema
      key order), `room_part`, `item_part`, `request_part`, writing optional fields only when set.
  - **Admin:** `admin/authoring.py` gains the fields and `StoryRiderInline`.

  Run `uv sync --reinstall-package wassal-content`, `uv run manage.py makemigrations --check
  --dry-run` and `uv run pytest -n 4 --cov --cov-fail-under=80` in `backend`. Make T010 pass.
  (Depends on T010.)
- [X] T012 [P] Add the fields to the release draft in the `content-core-r1` worktree
  (`/mnt/endeavour/home/saied-dev/Work/wasal_ogra-core-r1/content/drafts/core-r1/pack/`), uncommitted
  as the draft is (contracts/content-fields.md "The release draft"):
  - scene titles, goal art, goal and ready lines, taglines, room art and `done_line`;
  - the four salon items' `slot` and comments;
  - `the_fatha` gains `plays: {kind: after_trip, trip_id: line_gamaa.18}`;
  - `story_trip_info`:
    - `line_hay.20`: moallem in `A_m`;
    - `line_gamaa.01`: bride_father in `front_r`, with a `fail_reason`;
    - `line_gamaa.18`: bride_mother in `front_r` and salma in `A_r`;
  - the riders' comment pools;
  - the askers: `req_nagafa_crystal` and `req_nish_golden` bride_mother, `req_antreeh_classic`
    bride_father.

  First check that no passenger of those trips names the riders' seats. If one does, pick another
  free seat and note it. Run `uv run wassal-content validate-source` on the draft. (Depends on T006.)

### The economy's two operations ([contracts/economy-ops.md](./contracts/economy-ops.md)): tests first

- [X] T013 [P] Write `apps/mobile/test/core/economy/domain/story_rules_test.dart`:
  - `story_progress`: `unknown_sku` (an unknown chapter, an unknown scene, a scene of another
    chapter), then `already_recorded`, in that order; apply adds the scene; `stillValid` on a base
    that already has it is a no-op;
  - `claim_request`: `unknown_sku`, `already_granted`, then `not_eligible` (not owned; owned in
    another variant); apply adds the id and never changes a balance; `stillValid` drops a claim no
    longer eligible on a new base;
  - `requestMatches` for both.
- [X] T014 [P] Extend `apps/mobile/test/core/economy/domain/economy_state_test.dart`:
  - `scenesSeen` and `requestsClaimed` in `==`/`hashCode`;
  - the canonical JSON writes them sorted (`"scenes_seen": {"ch1_first_job": ["opening"]}`,
    `"requests_claimed": [...]`) and reads them back;
  - `newPlayer` starts both empty.
- [X] T015 [P] Extend `apps/mobile/test/core/economy/economy_service_test.dart` and `idempotency_test.dart`:
  - `recordScene` and `claimRequest` return `OpApplied` and store one row;
  - the same `TxnId` again is `repeated: true`;
  - a refused repeat (`already_recorded`, `already_granted`) stores no row;
  - `claimRequest` leaves `bonat` unchanged.
- [X] T016 [P] Extend `apps/mobile/test/core/sync/domain/op_wire_test.dart` (both payloads with
  `content_version`, as contracts/economy-ops.md "Wire") and `state_snapshot_test.dart` (`story`
  mapped into `scenesSeen` by `chapter_id` and into `requestsClaimed`; `status` ignored; ids the pack
  lacks kept).

### The economy's two operations: implementation

- [X] T017 Add `storyProgress('story_progress')` and `claimRequest('claim_request')` to `OpType`, and
  `StoryProgressRequest` and `ClaimRequest`, in `apps/mobile/lib/core/economy/domain/op.dart`. Add
  `alreadyRecorded('already_recorded')` to
  `apps/mobile/lib/core/economy/domain/economy_refusal.dart`.
- [X] T018 Add `scenesSeen` (`Map<String, Set<String>>`, by chapter wire name, unmodifiable) and
  `requestsClaimed` (`Set<String>`, unmodifiable) to
  `apps/mobile/lib/core/economy/domain/economy_state.dart`: `copyWith`, `==`, `hashCode`, the
  canonical JSON (sorted) and `newPlayer`. Make T014 pass. (Depends on T017.)
- [X] T019 Create `apps/mobile/lib/core/economy/domain/story_rules.dart` (`validateStoryProgress`,
  `applyStoryProgress`, `storyProgressStillValid`, and the same three for `claim_request`), from the
  rule table in contracts/economy-ops.md. Wire them into `rules.dart`'s `validate`, `apply`,
  `stillValid` and `requestMatches` switches.
  - The economy domain must not import `core/progress/domain/`: the chapter's unlock is the caller's
    rule.
  - Make T013 pass. (Depends on T018.)
- [X] T020 Add `recordScene(TxnId id, {required ChapterId chapterId, required String sceneId})` and
  `claimRequest(TxnId id, {required String requestId})` to
  `apps/mobile/lib/core/economy/economy.dart` and implement them in `economy_service.dart`, as
  `grantTutorialGift` is. Make T015 pass. (Depends on T019.)
- [X] T021 Schema 5 in `apps/mobile/lib/core/storage/app_database.dart`:
  - `schemaVersion` 5;
  - `ledger_ops.op_type`'s `isIn` list gains both types;
  - `player_state` gains `scenes_seen TEXT NOT NULL DEFAULT '{}'` and
    `requests_claimed TEXT NOT NULL DEFAULT '[]'`;
  - `_toV5` rebuilds both tables with `alterTable(TableMigration(...))`, M07's step-4 way.

  Run `fvm dart run drift_dev make-migrations`, and commit
  `apps/mobile/drift_schemas/app/drift_schema_v5.json`, the generated steps and
  `apps/mobile/test/drift/app/`. Add a case that opens a v4 database with `ledger_ops` rows at v5
  and keeps them.

  `apps/mobile/lib/core/economy/drift_economy_store.dart` reads and writes the two columns in the
  same transaction as the rest of `player_state`, and `takeServerState` writes them. Run
  `test/repo/economy_writes_test.dart`. (Depends on T018.)
- [X] T022 Add both types to `contentVersionTypes`, with their payloads, in
  `apps/mobile/lib/core/sync/domain/op_wire.dart`.
  In `apps/mobile/lib/core/sync/domain/state_snapshot.dart`:
  - add `StateStory` and `StateChapter` from the OpenAPI `Story`/`ChapterState` shape;
  - map them in `stateFromSnapshot`;
  - reword the doc comment to "`stats` isn't mapped yet (M13)".

  Make T016 pass. (Depends on T018.)
- [X] T023 In `apps/mobile/lib/core/economy/economy.dart`, give `EconomyView`
  (contracts/economy-ops.md "`economy.dart`"):
  - the projection's `scenesSeen` and `requestsClaimed`, unmodifiable, from `EconomyState`;
  - `ConfirmedState` and `EconomyView.confirmed`: the base's ownership, `variantOf`, progress,
    `scenesSeen` and `requestsClaimed`, read-only, with no balances.

  Fill the first from the projection and the second from the projection base in
  `economy_service.dart`.
  - Add `playerProgressOfConfirmed(ConfirmedState, ContentSource)` beside `playerProgressOf` in
    `apps/mobile/lib/core/progress/application/player_progress_provider.dart`.
  - Test first in `apps/mobile/test/core/economy/confirmed_view_test.dart`:
    - a recorded scene and a claim show in the view's `scenesSeen` and `requestsClaimed` at once;
    - a pending purchase, scene or claim is in the projection and not in `confirmed`;
    - after `applyAnswer` accepts it, both have it;
    - a state replacement sets both.

  (Depends on T020.)

### The story, request and reward rules: tests first

- [X] T024 [P] Write `apps/mobile/test/core/progress/story_test.dart` (contracts/story-flow.md "The
  rules"):
  - `momentOf` for each kind;
  - `sceneUnlocked` per moment;
  - `sceneState` from `scenesSeen`;
  - `scenesInStoryOrder`: chapters by `(order, chapter_id)`, then list order, with `storyShaped()`'s
    chapter 2 goal scene first;
  - `waitingScenes`;
  - `goalSceneOf`, `afterTripSceneOf`.
- [X] T025 [P] Write `apps/mobile/test/core/progress/requests_test.dart` (data-model "Family
  request"), with the styles from a `variantOf` function (`PlayerProgress` holds none):
  - each state: `locked`, `open`, `done` (with and without a variant), `missed`, `claimed`;
  - the count (open + done);
  - the list order (done first, then room and item `order`).
- [ ] T026 [P] Write `apps/mobile/test/core/progress/rewards_test.dart` (contracts/economy-ops.md
  "Pending rewards"):
  - each source pending, then received once the confirmed progress has it;
  - a room completing its chapter yields two rewards;
  - a rolled-back purchase yields none;
  - an empty base marks every completion pending.

### The story, request and reward rules: implementation

- [ ] T027 [P] Implement `apps/mobile/lib/core/progress/domain/story.dart`. Make T024 pass.
- [ ] T028 [P] Implement `apps/mobile/lib/core/progress/domain/requests.dart`
  (`RequestState { locked, open, done, missed, claimed }`, `requestStates(c, p, variantOf,
  requestsClaimed)` with `variantOf` a `String? Function(String itemId)` that callers fill from
  `EconomyView.variantOf`, and `openRequestCount`). Make T025 pass.
- [ ] T029 Implement `apps/mobile/lib/core/progress/domain/rewards.dart` and `pendingRewardsProvider`
  in `apps/mobile/lib/core/progress/application/pending_rewards_provider.dart` (watches
  `economyViewProvider` and `contentSourceProvider`). Run build_runner. Make T026 pass. (Depends on
  T023.)

### Shared pieces

- [ ] T030 [P] Add `lib/features/apartment/domain` and `lib/features/story/domain` to `_domains` in
  `apps/mobile/test/repo/domain_imports_test.dart`, with an allowance (`_storyAllowed`): the content
  models, the content source, the economy's `wire.dart`, `core/progress/domain/`, Home's
  `savings_target.dart` and their own folder. Add the scan test for it, with allowed and refused URIs.
  `rider_comments.dart` stays under `_tripAllowed`.
- [ ] T031 [P] Add `artboardSalon()` and `storyShaped()` (Tests, above) to
  `apps/mobile/test/helpers/synthetic_packs.dart`, through M08's `editPack`, and their
  self-tests to `synthetic_packs_test.dart` (if it exists, else beside the helper's existing tests).
  Both must pass `validate-source`'s rules through the Dart reader.
- [X] T032 [P] Create `apps/mobile/lib/core/content/domain/story_characters.dart`:
  `storyCharacterArt(StoryCharacter)`, an exhaustive switch to the art names `CharacterAvatar.looks`
  and ARB `sceneSpeaker` use (`usta`, `salma`, `bride_father`, …). Test it in
  `apps/mobile/test/core/content/story_characters_test.dart`: every value maps, and every name has
  a `looks` entry.
- [X] T033 Routes in `apps/mobile/lib/core/routing/routes.dart`:
  - `RouteNames.storyScene` (`/story/scene/:sceneId`), `RouteNames.storyAlbum` (`/story/album`) and
    `RouteNames.apartmentPreTrip` (`/apartment/pre-trip/:tripId`), with their sections, titles
    (`destStoryScene`, `destStoryAlbum`, `destPreTrip`) and `links`;
  - `ParamValidators.sceneId` = `^[a-z][a-z0-9_]{1,31}$`;
  - `sampleParams` gains `'sceneId': 'the_stand'`.

  In `router.dart`, register them as root pages, with `/story/album` and `/story/scene/:sceneId`
  before `/story/:chapterId` (literal segments first), each building `PlaceholderScreen` until its
  story. Add the three `dest*` titles to `apps/mobile/lib/l10n/app_ar.arb`. Update
  `apps/mobile/test/core/routing/` (navigation, validators, all-destination goldens: regenerate and
  review the new `story_*`/`apartment_*` ones).
- [X] T034 Add `StartFrom.apartment` to
  `apps/mobile/lib/features/home/application/start_next_trip.dart`. The card opens at
  `/apartment/pre-trip/:tripId` (a root page building M08's `PreTripCard` with its close leading to
  `/apartment`, M09's `linePreTrip` way), registered in `router.dart` for
  `RouteNames.apartmentPreTrip`. Extend `apps/mobile/test/features/home/start_next_trip_test.dart`:
  the apartment's location, the fuel sheet on an empty tank, a due scene first. (Depends on T033.)
  The due-scene case seeds M07's list (`first_session.scenesDue`); M10's goal scenes join the same
  list with `StoryDueWatcher` (T088).
- [X] T035 Create `apps/mobile/lib/features/story/story_overrides.dart`: `List<Override>
  storyOverrides()`, holding for now `storySceneWaitingProvider.overrideWith((ref) =>
  waitingScenes(...).isNotEmpty)` from the content, progress and `economyViewProvider.scenesSeen`.
  - The seen scenes are the projection's plus M07's `first_session` ones, so an install from before
    `StoryService.backfill` (T088) doesn't read the opening as waiting (T153).
  - Pass it to the `ProviderScope` in `apps/mobile/lib/bootstrap/bootstrap.dart`, and before the
    test overrides in `apps/mobile/test/helpers/pump_app.dart`.
  - Test it in `apps/mobile/test/features/story/story_overrides_test.dart`: false with nothing
    waiting, true with a scene waiting. (Depends on T027.)

**Checkpoint**: The content carries the story, the phone records and syncs scenes and claims, and the
rules are proven. Stories can start.

---

## Phase 3: User Story 1 - Save toward the chapter's goal (Priority: P1) 🎯 MVP

**Goal**: The tab's goal view for chapters 1–3, ready state, and the shabka bought with its story
trip's card opening ([contracts/apartment.md](./contracts/apartment.md) "The goal view").

**Independent Test**: With the sample and a scripted state, offline, open the tab:

- in chapter 1 (8 regular trips done): «خلّص خط الحي» with «٨ / … مشوار»;
- in chapter 3 below the shabka's price, then above it: only the last shows «جاهزة!» and the button.

Tap it: the shabka is bought once, and the shabka trip's card opens at `/apartment/pre-trip/...`.

### Tests for User Story 1 ⚠️

- [ ] T036 [P] [US1] Write `apps/mobile/test/features/apartment/domain/apartment_view_test.dart`:
  - `GoalView` below `apartmentOpens`, and with no room chapter;
  - `RoomsView` from it on;
  - `storyEnd` when the current chapter is complete.
- [ ] T037 [P] [US1] Write `apps/mobile/test/features/apartment/domain/goal_view_model_test.dart`:
  - the three goal kinds: `Count` for a line, `Amount` for a vehicle and a purchase;
  - `ready` only when affordable and not owned, never for a line;
  - `ready_line` replaces the line's text when ready;
  - the actions `buyChapter(price)`, `openVehicleSheet(id)` and none;
  - art: `goal_art` through `ApartmentArt.goal`, else the vehicle, tuktuk or ring fallback.
- [ ] T038 [P] [US1] Write `apps/mobile/test/features/apartment/application/goal_purchase_test.dart`,
  against a fake `Economy` and the real one:
  - rules first (`notAllowed` for a locked chapter, a non-purchase goal, an owned goal; nothing
    sent);
  - one held `TxnId` across `insufficient_funds` and `OpWriteFailed`, cleared on `OpApplied` and on
    a final refusal;
  - a double tap spends once (SC-002).
- [ ] T039 [P] [US1] Write `apps/mobile/test/features/apartment/goal_view_test.dart`:
  - chapter 1, 2 and 3 states;
  - the bar animating from `goalBarSeenProvider`'s value;
  - «جاهزة!» and the CTA;
  - chapter 2's CTA opening `/lines/vehicle/micro_old`;
  - the shabka CTA buying, then `/apartment/pre-trip/<story trip>` (or the fuel sheet on an empty
    tank);
  - the chapter bar → `/apartment/chapters`;
  - a sync changing the balance redraws;
  - the «{goal} جاهزة» announcement in the ready state.

### Implementation for User Story 1

- [ ] T040 [P] [US1] Implement `apps/mobile/lib/features/apartment/domain/apartment_view.dart`
  (`ApartmentView`, `GoalView`, `RoomsView`, `apartmentView`). Make T036 pass.
- [ ] T041 [P] [US1] Implement `apps/mobile/lib/features/apartment/domain/goal_view_model.dart`
  (`GoalViewModel`, `GoalArt`, `GoalAction`) over M08's `savingsTarget`. Make T037 pass.
- [ ] T042 [US1] Implement `apps/mobile/lib/features/apartment/application/goal_purchase.dart`
  (contracts/apartment.md "`GoalPurchase`"), with `economy.buy(id, kind: SkuKind.chapter, skuId:
  chapterId)`. Make T038 pass.
- [ ] T043 [US1] Create `apps/mobile/lib/features/apartment/application/apartment_providers.dart`:
  - `apartmentViewProvider` (watches content, progress, `economyViewProvider`);
  - `goalBarSeenProvider` (keepAlive, in memory);
  - `goalPurchaseProvider`.

  Run build_runner.
- [ ] T044 [P] [US1] Create `apps/mobile/lib/features/apartment/presentation/chapter_bar.dart`, the
  `primary` bar shared by both views (56 high, `lip.primary.m`, `press`): the title and its trailing
  part, the whole a `Pressable` to `/apartment/chapters`, label «الفصل {n}: {name}، كل الفصول».
  Also an optional trailing child (US4's chip).
- [ ] T045 [US1] Create `apps/mobile/lib/features/apartment/presentation/goal_view.dart`:
  - the goal card: art 190, the goal row (`maxLines 1` on the amount), the gold `ProgressBar`
    animated with `sheetIn`, and the character line with `CharacterAvatar` 46 and the speaker from
    `sceneSpeaker`;
  - the ready chip and the CTA 64 with the price chip 32;
  - the teaser (`paper` with the `outline` ring, the teaser art, «شقة العُمر», the body).

  On «اشتري», call `GoalPurchase`, then the coin burst, then `startNextTrip(context, ref, tripId:
  …, from: StartFrom.apartment)` when the chapter's story trip isn't finished. Guard `mounted`
  after every await.
- [ ] T046 [US1] Create `apps/mobile/lib/features/apartment/presentation/apartment_screen.dart`: the
  header (title by view, the JENEHAT `CurrencyPill` with no tap), the chapter bar, and the view by
  `apartmentViewProvider` (`RoomsView` a placeholder until T062), in a scroll view above the shell's
  nav.
- [ ] T047 [US1] Add the goal view's strings to `apps/mobile/lib/l10n/app_ar.arb` (HANDOFF
  `aptGoal.*`, `apartment.*`; research R19), then run `fvm flutter pub get`:
  - `aptGoalTitle`, `aptGoalChapterBar`, `aptGoalAllChapters`;
  - `aptGoalProgress` («{saved} / {target} ج»), `aptGoalTrips` («{done} / {total} مشوار»);
  - `apartmentTitle`, `aptGoalLockedBody`;
  - `apartmentGoalReady`, `apartmentBuyGoal`, `apartmentBuyGoalA11y`, `apartmentGoalReadyA11y`;
  - `aptGoalChapterA11y`, `aptGoalProgressA11y`.
- [ ] T048 [US1] In `apps/mobile/lib/core/routing/router.dart`'s `_page`, build `ApartmentScreen()` for
  `RouteNames.apartment`. Regenerate and review `test/goldens/goldens/all/apartment_*.png` and the
  shell's apartment goldens. Update `test/core/routing/{navigation,frame_design}_test.dart` where
  they expect the placeholder. Make T039 pass.
- [ ] T049 [P] [US1] Add the `AptGoal` and `AptGoalReady` design checks:
  - `apps/mobile/test/design/samples/apt_goal.dart` (ch3 with 2,200 of 6,000, and ready with
    6,240), over a synthetic pack with the artboard's shabka price;
  - `test/design/{apt_goal,apt_goal_ready}_layout_test.dart`;
  - `test/goldens/design/apt_goal_goldens_test.dart`, in both digit styles.

  List the expected differences (research R18) at the top of each.
- [ ] T050 [P] [US1] Write `apps/mobile/test/a11y/apt_goal_minimum_sizes_test.dart`: every tappable
  ≥ 44×44 and every text ≥ 12 pt, at 360×640, 360×800 and 390×844, scale 1.0 and 1.3, in chapter 1
  and ready.

**Checkpoint**: The tab shows the chapter's goal, and the shabka is bought offline.

---

## Phase 4: User Story 2 - Furnish the room piece by piece (Priority: P1)

**Goal**: The rooms view, the room drawing from content slots, the piece sheet with styles and the
request mark, and buying a piece ([contracts/apartment.md](./contracts/apartment.md) "The rooms
view", "The piece sheet").

**Independent Test**: With `artboardSalon()` (two pieces owned, in chosen styles), open the tab
offline:

- the drawing shows the two pieces and two dashed places with chips;
- the grid shows «اتركّبت» twice, the next piece's shortfall and the other's price.

Open the next piece, switch styles, raise the balance and buy: the piece is in place in that style,
«جهّزت ٣ من ٤», and the price is spent once.

### Tests for User Story 2 ⚠️

- [ ] T051 [P] [US2] Write `apps/mobile/test/features/apartment/domain/room_model_test.dart`:
  - tabs: selectable when the room's chapter is unlocked, locked otherwise (including rooms the pack
    lacks, with their ARB names);
  - cells: `owned(variant)`, `nextTarget` equal to `nextPiece` (Home's) with shortfall, progress and
    `affordable`, `missing(price)`;
  - `owned/total`, the goal scene and its state, the requests count;
  - a variant the pack no longer has drawn as the first.
- [ ] T052 [P] [US2] Write `apps/mobile/test/features/apartment/domain/piece_sheet_model_test.dart`:
  - the remembered style, else the first;
  - سلمى's line from the variant, else the item, else none;
  - `requestMarks` for open requests only;
  - `missesRequest` when another style is selected;
  - one-style pieces;
  - the price and balance.
- [ ] T053 [P] [US2] Write `apps/mobile/test/features/apartment/application/piece_purchase_test.dart`:
  - rules first (`itemPurchasable`, not owned);
  - the held id;
  - refusals spend nothing;
  - `roomCompleted` and `chapterCompleted` true only for the purchase that completes them, and false
    after a sync or a state replacement completes the room;
  - a double tap spends once.
- [ ] T054 [P] [US2] Write `apps/mobile/test/features/apartment/rooms_view_test.dart`:
  - the chapter bar's text and bar;
  - tabs (locked inert and read «مقفولة», the 44 hit row);
  - the requests button with its badge hidden at 0;
  - the room scene's layers and chip clamp;
  - each cell state with «تقدر تشتريها»;
  - the strip;
  - a missing piece's chip and card → `/apartment/item/<id>`, an owned one inert;
  - the crossfade on a tab switch;
  - six pieces at 1.3× scroll;
  - after a purchase: the drop-in, the chip gone, «اتركّبت», the count, سلمى's bubble until the
    next tap, the «اشتريت {piece}» announcement;
  - under reduced motion, fades only;
  - the pending chip.
- [ ] T055 [P] [US2] Write `apps/mobile/test/features/apartment/piece_sheet_test.dart`:
  - styles switching the preview, chip and line, never the price;
  - the request mark and the missed line;
  - affordable «اشتري» with «−{n} ج»;
  - short «ناقصك» and «اطلع مشوار» → `startNextTrip(from: StartFrom.apartment)`;
  - the button disabled in flight;
  - close, swipe and back → `/apartment`;
  - an owned or locked or unknown item redirects to `/apartment`;
  - a sync making it unaffordable switches the button before the tap.

### Implementation for User Story 2

- [ ] T056 [P] [US2] Rename M08's `_nextPiece` to the exported `nextPiece(c, p, room)` in
  `apps/mobile/lib/features/home/domain/savings_target.dart` (behaviour unchanged; its tests still
  pass). Implement `apps/mobile/lib/features/apartment/domain/room_model.dart` (`RoomModel`,
  `RoomTab`, `PieceCell`), taking `variantOf` for the owned pieces' styles. Make T051 pass.
- [ ] T057 [P] [US2] Implement `apps/mobile/lib/features/apartment/domain/piece_sheet_model.dart`,
  taking `variantOf` (its request marks come through `requestStates`). Make T052 pass.
- [ ] T058 [US2] Implement `apps/mobile/lib/features/apartment/application/piece_purchase.dart`
  (`PiecePurchase`, `PiecePurchaseResult` with `roomCompleted` and `chapterCompleted`), with
  `economy.buy(id, kind: SkuKind.item, skuId: itemId, variantId: variantId)`. Add
  `pieceStyleMemoryProvider` and `roomTabProvider` (keepAlive, in memory), `roomModelProvider` and
  `pieceSheetModelProvider` to `apartment_providers.dart`. Run build_runner. Make T053 pass.
- [ ] T059 [P] [US2] Create `apps/mobile/lib/features/apartment/presentation/room_scene.dart`:
  - `RoomScene` (the 358×300 design space in a `FittedBox`);
  - the layers in contracts/apartment.md's order;
  - the dashed `CustomPaint` outline;
  - the chip (`Pressable`, label «{item}، {price} جنيه»).

  Also create `room_fallback.dart` with `RoomFallback` (`scene.room`/`scene.floor`) and
  `PieceFallback` (`ground.lip`). Add a `scene.roomCard` token to `AppPalette` only if no existing
  token matches the drawn card colour, with its dark value.
- [ ] T060 [P] [US2] Create `apps/mobile/lib/features/apartment/presentation/pending_chip.dart`
  (`PendingChip` over `pendingRewardsProvider`: the `sun.soft` pill, «+{n} بون في الطريق», label
  «{n} بون في الطريق، توصل مع المزامنة», hidden when empty).
- [ ] T061 [US2] Create `apps/mobile/lib/features/apartment/presentation/piece_sheet.dart` (contracts/
  apartment.md "The piece sheet"):
  - an `AppSheetPage(ownHeader: true)`, the header, preview and style cards (art through
    `ApartmentArt.piece`, else `PieceFallback`);
  - the `StatusChip` mark;
  - سلمى's line, the price and «معاك»;
  - the missed line in `danger.ink` 13/700;
  - the two buttons.

  Selecting writes `pieceStyleMemoryProvider`. On `OpApplied` it pops with the result for the rooms
  view.
- [ ] T062 [US2] Create `apps/mobile/lib/features/apartment/presentation/rooms_view.dart`:
  - the chapter bar's room content, the `Segmented` tabs, the requests button with `CountBadge`
    (`primary`/white);
  - `RoomScene`, the grid (`role=list` «قطع {room}») and the `InfoStrip`;
  - after a purchase, the drop-in (`dialogIn`) and سلمى's `SpeechBubble` (`bubblePop`) until the
    next tap or scroll.

  Wire it into `apartment_screen.dart`, with `PendingChip` in both views' headers.
- [ ] T063 [US2] Add the rooms view's and sheet's strings to `app_ar.arb` (HANDOFF `aptRooms.*`,
  `piece.*`; research R19), then `fvm flutter pub get`:
  - `aptRoomsChapterProgress` («جهّزت {owned} من {total}»), `aptRoomsRequests`,
    `aptRoomsRequestsA11y`, `aptRoomsTabsA11y`, `aptRoomsLockedTab`;
  - `aptRoomsChip`, `aptRoomsChipA11y`, `aptRoomsGridA11y`, `aptRoomsInstalled`;
  - `aptRoomsShort` («ناقصك {n}»), `aptRoomsAffordable` («تقدر تشتريها»), `aptRoomsPrice`,
    `aptRoomsStrip`;
  - `roomTeaserName` (select by `RoomId`);
  - `pieceSamePrice`, `pieceBalance`, `pieceShort`, `pieceGoTrip`, `pieceBuy`, `pieceBuyA11y`;
  - `pieceRequestMark` («طلب {asker}»), `pieceMissesRequest` («لو اخترت ده، طلب {asker} هيفوتك»);
  - `aptBought` («اشتريت {piece}»);
  - `pendingRewards` («+{n} بون في الطريق»), `pendingRewardsA11y`.

  BONAT agreement uses ICU plurals (§9.1 #3).
- [ ] T064 [US2] In `router.dart`'s `_page`, build `PieceSheet(itemId: …)` as an
  `AppSheetPage(ownHeader: true)` for `RouteNames.apartmentItem`, redirecting owned, locked and
  unknown items to `/apartment`. Regenerate and review the all-destination goldens it touches. Make
  T054 and T055 pass.
- [ ] T065 [P] [US2] Add the `AptRooms` and `Piece` design checks:
  - `apps/mobile/test/design/samples/{apt_rooms,piece}.dart` over `artboardSalon()`, using
    `AptRooms_01.svg` as the fake room art;
  - `test/design/{apt_rooms,piece}_layout_test.dart`;
  - `test/goldens/design/{apt_rooms,piece}_goldens_test.dart`, in both digit styles.

  List the expected differences at the top of each: the badge in `primary`/white, the fuel chip
  «−١» with its icon, the ✕ labelled «قفل».
- [ ] T066 [P] [US2] Write `apps/mobile/test/a11y/{apt_rooms,piece}_minimum_sizes_test.dart` at the
  three sizes and both scales.

**Checkpoint**: The salon is furnished piece by piece, offline, in the player's styles.

---

## Phase 5: User Story 3 - Finish a room and a chapter (Priority: P2)

**Goal**: `RoomDone` with the reward on its way, and the end of the available story everywhere
([contracts/apartment.md](./contracts/apartment.md) "RoomDone", "The end of the story").

**Independent Test**: With a state one piece short of a complete salon, buy the last piece offline:

- the dialog opens once, with the room's and the chapter's reward «في الطريق»;
- the BONAT balance doesn't change;
- «بعدين» leaves the scene waiting.

Against a test server, the balance rises by that sum once after the sync (US5's T098).

### Tests for User Story 3 ⚠️

- [ ] T067 [P] [US3] Write `apps/mobile/test/features/apartment/room_done_dialog_test.dart`:
  - the chip, title, art and quote;
  - the reward as the room's plus the chapter's when `chapterCompleted`;
  - «في الطريق» while pending, gone once received;
  - «شوف المشهد» → `/story/scene/<goal scene>?then=/apartment`, hidden without a goal scene;
  - «بعدين», scrim and back close and leave the scene waiting;
  - focus on the CTA, and the announcement;
  - opened once for several offline purchases (only the completing one);
  - never after a sync or a restore;
  - a rollback of the completing purchase removes the pending reward (spec US3 scenario 6).
- [ ] T068 [P] [US3] Extend `apps/mobile/test/features/home/domain/savings_target_test.dart`
  (`StoryEndTarget` when the current chapter is complete; `NoTarget` for a pack without chapters) and
  `apps/mobile/test/features/home/savings_card_test.dart`, and the result's apartment card test:
  - the end card's text, no bar, tap → `/apartment`;
  - the result's card hidden.

### Implementation for User Story 3

- [ ] T069 [US3] Add `StoryEndTarget` to
  `apps/mobile/lib/features/home/domain/savings_target.dart`. Draw it in
  `apps/mobile/lib/features/home/presentation/savings_card.dart`. Treat it as hidden in
  `apps/mobile/lib/features/result/presentation/apartment_card.dart`, and keep
  `home_screen.dart`'s card shown for it. Fix every `switch` the compiler reports. Make T068 pass.
- [ ] T070 [US3] Create `apps/mobile/lib/features/apartment/presentation/room_done_dialog.dart`
  (`RoomDoneDialog`, through `showAppDialog`): `RoomScene` at 260×130 with the confetti behind
  (`ui/confetti` in Rive when drawn, else a token-coloured burst), and the parts of
  contracts/apartment.md's table. No `bonat_burst`.
- [ ] T071 [US3] In `rooms_view.dart`, open `RoomDoneDialog` once the drop-in ends when the purchase
  result has `roomCompleted`. Show the end strip «باقي الحكاية جاية في تحديث قريب» and the full bar
  when `storyEnd`. Make T067 pass.
- [ ] T072 [US3] Add `roomDoneTitle`, `roomDoneChip`, `roomDoneReward`, `roomDonePending`
  («في الطريق»), `roomDoneCta`, `roomDoneLater`, `roomDoneA11y`, `storyEndLine` and
  `homeStoryEndA11y` to `app_ar.arb`, then `fvm flutter pub get`.
- [ ] T073 [P] [US3] Add the `RoomDone` design checks (`test/design/samples/room_done.dart`, the
  layout test and the goldens), with the expected differences: «في الطريق» under the pill, no
  `bonat_burst`.
- [ ] T074 [P] [US3] Write `apps/mobile/test/a11y/room_done_minimum_sizes_test.dart` at the three
  sizes and both scales.

**Checkpoint**: A finished room celebrates, the server pays, and the end of the story is graceful.

---

## Phase 6: User Story 4 - Watch the story's scenes when they happen (Priority: P2)

**Goal**: Scenes unlock at their moments, play where story-flow.md says, in M07's look in the first
session and the viewer after it, recorded once and shared as an image
([contracts/story-flow.md](./contracts/story-flow.md),
[contracts/scene-viewer.md](./contracts/scene-viewer.md) "The viewer").

**Independent Test**: With the sample:

- finish المعلم's story trip for the first time: its scene plays on leaving the result; finish it
  again: no scene;
- buy the microbus in Lines, then go Home: chapter 2's scene plays as the arrival item;
- tap through every panel, share the last, and skip another halfway.

Each scene is recorded once, with one `story_progress` per scene queued.

### Tests for User Story 4 ⚠️

- [ ] T075 [P] [US4] Write `apps/mobile/test/features/story/application/story_service_test.dart`:
  - `recordSeen` marks M07's flag and queues one `story_progress`;
  - a replay queues nothing;
  - a locked scene sends nothing;
  - an unknown id is ignored;
  - `OpWriteFailed` keeps the held id for the next call;
  - `backfill` sends only the scenes M07 saw and the economy lacks, once.
- [ ] T076 [P] [US4] Write `apps/mobile/test/features/story/application/story_due_watcher_test.dart`:
  - a vehicle bought here makes chapter 2's goal scene due;
  - a room completion makes nothing due;
  - a completion restored by a state replacement makes nothing due;
  - a restart with the completion still pending is idempotent.
- [ ] T077 [P] [US4] Write `apps/mobile/test/features/story/application/story_after_result_test.dart`:
  - plays a waiting after-trip scene and awaits it;
  - returns at once for a seen scene, a trip with no scene, and a failed trip.
- [ ] T078 [P] [US4] Write `apps/mobile/test/features/story/domain/scene_sequence_test.dart`: one
  scene; a chapter's unlocked scenes in story order; nothing unlocked.
- [ ] T079 [P] [US4] Write `apps/mobile/test/features/story/scene_viewer_page_test.dart`
  (contracts/scene-viewer.md "Taps" table, row by row):
  - the top bar, bubbles' sides and the narrator caption;
  - الأسطى as the driver's name, else «الأسطى»;
  - the dots, and the last panel's buttons;
  - a sequence moving to the next scene and restarting the dots;
  - skip and back recording what was reached;
  - `then` honoured;
  - an unknown scene or nothing unlocked going to `then`, else `/apartment`;
  - reduced motion (crossfade ≤ 150 ms, still art);
  - «اللوحة {i} من {n}» announced.
- [ ] T080 [P] [US4] Move M08's share render test to
  `apps/mobile/test/core/platform/offscreen_render_test.dart` (output unchanged). Write
  `apps/mobile/test/features/story/scene_share_test.dart`: `FakeShareGateway` receives a PNG of
  358×540 ×3 with the still drawing (never Rive), offline; a failure shows M08's share error.
- [ ] T081 [P] [US4] Extend `apps/mobile/test/features/onboarding/arrival_items_test.dart`, the
  router's `/trip` redirect test in `apps/mobile/test/core/routing/`, and
  `apps/mobile/test/features/home/savings_card_test.dart`:
  - inside the first session, M07's `/onboarding/scene/:id`; after it, `/story/scene/:id` with the
    same `then`;
  - the savings card taps to the first waiting scene while `sceneWaiting`, else `/apartment`.

### Implementation for User Story 4

- [ ] T082 [US4] Implement `apps/mobile/lib/features/story/application/story_service.dart`
  (`StoryService`, `storyServiceProvider`; contracts/story-flow.md "Recording a scene"). Make T075
  pass, except backfill's wiring (T097).
- [ ] T083 [US4] Implement `apps/mobile/lib/features/story/application/story_due_watcher.dart` and
  start it in `apps/mobile/lib/bootstrap/app.dart` beside `HomeArrivalQueue` and `LinesDotWatcher`,
  disposed with them. Make T076 pass.
- [ ] T084 [P] [US4] Implement `apps/mobile/lib/features/story/domain/scene_sequence.dart`. Make T078
  pass.
- [ ] T085 [P] [US4] Move `renderSharePicture` to
  `apps/mobile/lib/core/platform/offscreen_render.dart` as `renderOffscreenPng(BuildContext, Widget,
  Size, {double pixelRatio = 3})`. `apps/mobile/lib/features/result/presentation/share_action.dart`
  calls it with its card. M08's share golden is unchanged.
- [ ] T086 [P] [US4] Create
  `apps/mobile/lib/features/story/presentation/{scene_panel_view,scene_panel_share}.dart`:
  - `ScenePanelView`: `PanelArt` in the 540 frame, up to two `SpeechBubble`s at the start/end
    positions (clamped inside), the narrator caption, speakers through `storyCharacterArt` and
    `sceneSpeaker`, with M22's turns;
  - `ScenePanelShare`: the still drawing, the bubbles and a wordmark strip, at 358×540.
- [ ] T087 [US4] Create `apps/mobile/lib/features/story/presentation/scene_viewer_page.dart`
  (`SceneViewerPage`):
  - the dark full screen;
  - the taps of the contract's table;
  - `sheetIn` slides from the reading side, the `bubblePop` stagger, the dots;
  - «شارك» through `renderOffscreenPng` and `ShareGateway.shareImage`;
  - `recordSeen` on reaching a scene's last panel, on «كمّل», on «تخطّى» and on back;
  - `mounted` guarded after every await.

  Make T079 and T080 pass.
- [ ] T088 [US4] Implement `StoryAfterResultImpl` in
  `apps/mobile/lib/features/story/application/story_after_result.dart`: push
  `/story/scene/:id` through `routerProvider` and await its pop. Add
  `storyAfterResultProvider.overrideWith(...)` to `storyOverrides()`. Make T077 pass.
- [ ] T089 [US4] Change M07's merged code (plan "What changes in merged code"):
  - `apps/mobile/lib/features/onboarding/presentation/arrival_items.dart` (`DueSceneArrival.open`):
    the location by `firstSession.inFirstSession`;
  - the `/trip` redirect's due-scene case in `apps/mobile/lib/core/routing/router.dart`: the same
    choice;
  - `apps/mobile/lib/features/onboarding/presentation/scene_page.dart` (`_finished`):
    `storyService.recordSeen` in place of `service.sceneSeen`.

  Run M07's tests and `integration_test/first_session_test.dart`, unchanged. Make T081's first part
  pass.
- [ ] T090 [US4] In `apps/mobile/lib/features/home/presentation/savings_card.dart`, tap to
  `/story/scene/<first waiting>?then=/home` while `sceneWaiting`, else `/apartment`. Make T081 pass.
- [ ] T091 [US4] In `rooms_view.dart`, give the chapter bar its trailing «شوف المشهد» chip (its own
  `Pressable`, label «شوف المشهد: {title}») while the room is complete and its goal scene waits.
  Extend T054's test for it.
- [ ] T092 [US4] Add the viewer's strings to `app_ar.arb` (HANDOFF `scene.*`, under `sceneViewer*` so
  M07's `scene*` keys keep their meaning), then `fvm flutter pub get`:
  - `sceneViewerChapterLabel`, `sceneViewerSkip`, `sceneViewerPageA11y`;
  - `sceneViewerShare`, `sceneViewerContinue`, `sceneViewerNextPanelA11y`;
  - `shareSceneText`, `aptWatchScene`.
- [ ] T093 [US4] In `router.dart`'s `_page`, build `SceneViewerPage` for `RouteNames.storyScene` and
  `RouteNames.story`. Regenerate and review their all-destination goldens.
- [ ] T094 [P] [US4] Add the `SceneViewer` design checks (`test/design/samples/scene_viewer.dart`
  with the synced `ch4_mother_looks` panel, the layout test and goldens in both digit styles).
- [ ] T095 [P] [US4] Write `apps/mobile/test/a11y/scene_viewer_minimum_sizes_test.dart` at the three
  sizes and both scales.

**Checkpoint**: Every scene plays at its moment, once, and replays and shares from the viewer.

---

## Phase 7: User Story 5 - My story follows me (Priority: P2)

**Goal**: A restore brings back the seen scenes, the claims and the apartment, and plays nothing by
itself. M07's earlier scenes reach the server (spec FR-052, FR-054).

**Independent Test**: Against a test server, play to chapter 4 with two pieces, three scenes seen and
one request claimed, sync, then restore on a fresh install. The tab, timeline, album and requests
match, and no scene plays by itself.

### Tests for User Story 5 ⚠️

- [ ] T096 [P] [US5] Write `apps/mobile/test/features/story/restore_test.dart`, with a fake server
  state replacing the phone's (M06's `replace_from_server` path):
  - the apartment's owned pieces in their styles;
  - `scenesSeen` and `requestsClaimed` from the state;
  - a scene unlocked and not seen waits, and none is due;
  - no `RoomDone`;
  - the pending chip empty.

### Implementation for User Story 5

- [ ] T097 [US5] Call `StoryService.backfill()` once from `apps/mobile/lib/bootstrap/app.dart` after
  the economy and content providers resolve, and guard it so it runs once per launch. Make T075's
  backfill cases and T096 pass.
- [ ] T098 [US5] Write `apps/mobile/test/backend/story_sync_test.dart` (tag `backend`), with its seed
  in `apps/mobile/test/backend/seed_backend.py` if needed (quickstart §6):
  - the shabka bought, a scene recorded, the salon's pieces bought and a claim made through M10's
    paths, then a sync;
  - all accepted, none `not_unlocked`;
  - the room's, chapter's and request's BONAT in the wallet once, and the phone's balance only after
    the sync;
  - a fresh install restoring the account shows the same state, with nothing due.

**Checkpoint**: The story is the player's across phones.

---

## Phase 8: User Story 6 - Look back over the story (Priority: P3)

**Goal**: The timeline and the album ([contracts/scene-viewer.md](./contracts/scene-viewer.md)
"The timeline", "The album").

**Independent Test**: With a chapter-4 state (three scenes seen, one waiting):

- the timeline shows chapters 1–3 done, 4 current with «{owned} من {total} قطع», the pieces and the
  scene's name, and 5–7 locked;
- the album's count matches the unlocked scenes, and each card opens its scene from panel 1,
  granting nothing.

### Tests for User Story 6 ⚠️

- [ ] T099 [P] [US6] Write `apps/mobile/test/features/apartment/domain/chapter_rows_test.dart`:
  - seven rows by the glossary's order, with ARB names for chapters the pack lacks;
  - the done row's thumbnail (the first panel of the last unlocked scene), and no button without a
    scene;
  - the current row for a room goal and for each other goal kind;
  - no current row at the end of the story.
- [ ] T100 [P] [US6] Write `apps/mobile/test/features/story/domain/album_test.dart`: one card per
  scene in story order; a waiting scene counted unlocked; the count.
- [ ] T101 [P] [US6] Write `apps/mobile/test/features/apartment/chapters_page_test.dart`:
  - the rows and their sentences;
  - «شوف المشهد» → `/story/<chapterId>`;
  - «ألبوم المشاهد» → `/story/album`;
  - the rail filled to the current node, animating once per chapter change;
  - back → `/apartment`;
  - seven rows at 1.3× scroll.
- [ ] T102 [P] [US6] Write `apps/mobile/test/features/story/album_page_test.dart`:
  - the count chip and the intro;
  - unlocked cards → `/story/scene/<id>?then=/story/album`;
  - locked cards inert, with their labels;
  - a replay queues no op.

### Implementation for User Story 6

- [ ] T103 [P] [US6] Implement `apps/mobile/lib/features/apartment/domain/chapter_rows.dart`
  (`ChapterRow`, `DoneRow`, `CurrentRow`, `LockedRow`, `chapterRows`). Make T099 pass.
- [ ] T104 [P] [US6] Implement `apps/mobile/lib/features/story/domain/album.dart` (`AlbumCard`,
  `UnlockedCard`, `LockedCard`, `album`). Make T100 pass.
- [ ] T105 [US6] Create `apps/mobile/lib/features/apartment/presentation/chapters_page.dart`:
  - the `ScreenHeader` with the album pill;
  - the rail;
  - the `ol` of rows (done 80, current 104 with `aria-current`, locked 58 in the locked look).

  Make T101 pass.
- [ ] T106 [US6] Create `apps/mobile/lib/features/story/presentation/album_page.dart`: the header with
  the count chip, the intro, and the two-column grid of unlocked and locked cards. Make T102 pass.
- [ ] T107 [US6] Add the timeline's and album's strings to `app_ar.arb` (HANDOFF `chapters.*`,
  `album.*`; research R19), then `fvm flutter pub get`:
  - `chaptersBack`, `chaptersTitle`, `chaptersAlbum`, `chaptersNumber`;
  - `chaptersWatchScene`, `chaptersCurrent`, `chaptersItemsChip`, `chaptersCurrentDesc`;
  - `chaptersRowA11y` (done, current, locked);
  - `chapterTeaserName` (select by `ChapterId`);
  - `albumTitle`, `albumCount`, `albumIntro`, `albumWatchAgain`, `albumLocked`, `albumCardA11y`.
- [ ] T108 [US6] In `router.dart`'s `_page`, build `ChaptersPage` for `RouteNames.apartmentChapters`
  and `AlbumPage` for `RouteNames.storyAlbum`. Regenerate and review their all-destination goldens.
- [ ] T109 [P] [US6] Add the `Chapters` and `Album` design checks (samples over `artboardSalon()`,
  layout tests, goldens), with the expected difference: the album follows the pack's scenes (Q3).
- [ ] T110 [P] [US6] Write `apps/mobile/test/a11y/{chapters,album}_minimum_sizes_test.dart` at the
  three sizes and both scales.

**Checkpoint**: The story can be looked back on and rewatched, granting nothing.

---

## Phase 9: User Story 7 - Answer the bride's family's requests (Priority: P3)

**Goal**: The requests sheet, «خد», and the badge ([contracts/apartment.md](./contracts/apartment.md)
"Family requests").

**Independent Test**: With a chapter-4 state where النجفة is owned in «كريستال» and the other two
requested pieces aren't, open the requests:

- the chandelier's request is done with «خد», and the others are open with their conditions;
- «خد» offline collapses the row, lowers the count and queues one `claim_request`;
- the balance doesn't change until a sync.

### Tests for User Story 7 ⚠️

- [ ] T111 [P] [US7] Write `apps/mobile/test/features/apartment/application/request_claim_test.dart`:
  - rules first (only `done`);
  - the held id;
  - a double tap claims once;
  - a server refusal (M06's rollback) returns the request to the list.
- [ ] T112 [P] [US7] Write `apps/mobile/test/features/apartment/requests_sheet_test.dart`:
  - done rows first with the happy avatar, «خلص · +{n} بونات» and «خد»;
  - open rows with the neutral avatar, the condition template and «+{n} بون»;
  - a missed request absent;
  - the claim's collapse (200 ms) and toast, online and offline;
  - the badge dropping;
  - the empty state;
  - the row labels;
  - close, swipe and back → `/apartment`.

### Implementation for User Story 7

- [ ] T113 [US7] Implement `apps/mobile/lib/features/apartment/application/request_claim.dart`
  (`RequestClaim`, `requestClaimProvider`). Make T111 pass.
- [ ] T114 [US7] Create `apps/mobile/lib/features/apartment/presentation/requests_sheet.dart`
  (`RequestsSheet`, an `AppSheetPage` with its header): rows as `ListRow` with `CharacterAvatar` 52,
  the condition from `requestCondition`/`requestConditionVariant`, and the `States` empty pattern.
- [ ] T115 [US7] Add `requestsTitle`, `requestsSubtitle`, `requestsDone`, `requestsClaim`,
  `requestsReward`, `requestConditionVariant` («{item} بشكل «{variant}»»), `requestCondition`
  («اشتري {item}»), `requestsEmpty`, `requestsRowA11y`, `requestsClaimToast` and
  `requestsClaimToastOffline` to `app_ar.arb`, then `fvm flutter pub get`.
- [ ] T116 [US7] In `router.dart`'s `_page`, build `RequestsSheet` for `RouteNames.apartmentRequests`.
  Make T112 pass, and extend T054 for the badge's count from `requestStates`.
- [ ] T117 [P] [US7] Add the `Requests` design checks. Skip the counted row's boxes (2c) with the
  reason «the server's `claim_request` checks only a piece and its style (B03 R9)».
- [ ] T118 [P] [US7] Write `apps/mobile/test/a11y/requests_minimum_sizes_test.dart` at the three
  sizes and both scales.

**Checkpoint**: Requests can be claimed offline, and the server pays them.

---

## Phase 10: User Story 8 - Ride with the story's characters (Priority: P3)

**Goal**: Riders, the story title, the condition, the failure reason and comments, from content, with
the engine untouched ([contracts/story-trip.md](./contracts/story-trip.md)).

**Independent Test**: With the sample's `line_hay.03`:

- the top bar shows the story chip and title, and the strip the content's condition;
- المعلم sits in `A_l` with no tag and no hit area;
- a scripted short change makes him comment once; a scripted over-change makes no comment;
- a fight fails the trip with the content's failure line.

### Tests for User Story 8 ⚠️

- [ ] T119 [P] [US8] Write `apps/mobile/test/features/trip/domain/rider_comments_test.dart`:
  - each mapped `RepCause` → its pool;
  - unmapped causes and an over-change sequence → none;
  - two riders → the first with a pool;
  - the same `(seed, ordinal)` → the same line;
  - a zero seed state → state 1;
  - the engine's PRNG state unchanged.
- [ ] T120 [P] [US8] Extend `apps/mobile/test/features/trip/domain/presentation_memory_test.dart` and
  `bubble_queue_test.dart`:
  - a comment takes the character slot;
  - بلية wins a tie;
  - a comment waiting past `bubbleMinMs` is dropped;
  - it stays its minimum;
  - never more than two bubbles in total (constitution XI).
- [ ] T121 [P] [US8] Extend `apps/mobile/test/features/trip/domain/fail_summary_test.dart`
  (`failReason` replaces the rule line; without it, M02's) and the projection test (`storyStrip` for a
  rule, for a content condition without a rule, and absent).
- [ ] T122 [P] [US8] Write the widget tests:
  - `apps/mobile/test/features/trip/top_bar/trip_title_test.dart`: the story chip over the content
    title;
  - `apps/mobile/test/features/trip/overlays/story_strip_test.dart`: the content condition; the strip
    without a rule and without a broken state;
  - `apps/mobile/test/features/trip/scene/rider_component_test.dart`: drawn at its seat's face, no
    hit area, the SVG fallback, `surprised` fired once on a comment;
  - `apps/mobile/test/features/trip/overlays/bubbles_layer_test.dart`: the rider bubble anchored over
    the face with the name chip and a polite announcement.

### Implementation for User Story 8

- [ ] T123 [US8] Add `TripFacts.storyInfo` in `apps/mobile/lib/features/trip/domain/trip_facts.dart`,
  set in `apps/mobile/lib/features/trip/application/trip_controller.dart` from the chapter whose
  `story_trip_id` is the trip.
- [ ] T124 [P] [US8] Implement `apps/mobile/lib/features/trip/domain/rider_comments.dart` (`RiderComment`,
  `riderComment`, through `SpeechResolver.resolve` and `Xorshift32`). Make T119 pass.
- [ ] T125 [US8] In `apps/mobile/lib/features/trip/domain/presentation_memory.dart`:
  - generalise بلية's slot to `CharacterBubble{speaker, source, line, shownAtMs}` and `characterAt`,
    with بلية's wish first;
  - feed rider comments from `ReputationChanged` events with their ordinal.

  In `trip_view.dart` and `projection.dart`, add `StoryStripView` and `TripView.storyStrip`. Update
  M07's بلية callers to the new names. Make T120 and T121 pass.
- [ ] T126 [US8] Switch the trip's presentation to the content:
  - the five layout checks to `storyStrip != null`: `top_bar/top_bar.dart`,
    `overlays/hint_layer.dart`, `overlays/bubbles_layer.dart`, `overlays/fast_forward_strip.dart`,
    `overlays/story_strip.dart`;
  - `TripTitle` to the story chip and title;
  - `StoryStrip` to the content condition;
  - `fail_summary.dart`/`cards/failure_card.dart` to `failReason`;
  - the rider bubble's name chip in `bubbles_layer.dart`.
- [ ] T127 [US8] Create `apps/mobile/lib/features/trip/presentation/scene/rider_component.dart`
  (`RiderComponent`: `Person` with `CharacterAvatar.looks[storyCharacterArt(c)]` at
  `SeatLayout.face`, the SVG fallback, the `mood`/`surprised` inputs, no hit area). Add one per rider
  in `scene/trip_game.dart`, in row order. Make T122 pass.
- [ ] T128 [US8] Add `tripStoryChip` (if M02 has none), `tripRiderA11y` («{name} راكب معاك») and
  `tripRiderSays` («{name}: {line}») to `app_ar.arb`, then `fvm flutter pub get`.
- [ ] T129 [US8] Update `apps/mobile/test/goldens/design/story_trip_goldens_test.dart` with the rider,
  the title and the content condition (and the unchanged look without `story_trip_info`). Write
  `apps/mobile/integration_test/story_trip_test.dart`, headless, with M02's scripted player:
  - a short change → one comment;
  - an over-change → none;
  - the `TripResult` equals the same run with the riders removed from the content.

**Checkpoint**: Story trips carry their characters; the rules and results are the same.

---

## Phase 11: The Owner's Boards

**Purpose**: The states the artboards don't draw, drawn by the owner
([contracts/design-briefs.md](./contracts/design-briefs.md)). Phases 3–10 build every state from the
brief, so only these checks wait for the export.

- [ ] T130 **Owner:** draw the ten boards on the Claude Design canvas: `AptGoalLine`,
  `AptGoalVehicle`, `AptRoomsAffordable`, `AptRoomsBought`, `AptRoomsDone`, `PieceAffordable`,
  `RoomDonePending`, `ChaptersGoal`, `RequestsEmpty`, `HomeStoryEnd`. Export them with
  `docs/design/tools` into `docs/design/{screens,png,boxes}/`, or hand the export to Claude
  (`docs/owner-actions.md` section 015, item 1).
- [ ] T131 After T130's apartment boards land, align `goal_view.dart`, `rooms_view.dart`,
  `room_scene.dart`, `pending_chip.dart`, `piece_sheet.dart` and `room_done_dialog.dart` to them.
  Add `test/design/samples/<board>.dart`, the layout tests and the goldens for `AptGoalLine`,
  `AptGoalVehicle`, `AptRoomsAffordable`, `AptRoomsBought`, `AptRoomsDone`, `PieceAffordable` and
  `RoomDonePending`. Move the boards' copy into `app_ar.arb`.
- [ ] T132 After T130's other boards land, align `chapters_page.dart`, `requests_sheet.dart` and
  `savings_card.dart` to `ChaptersGoal`, `RequestsEmpty` and `HomeStoryEnd`, with their samples,
  layout tests and goldens.
- [ ] T133 Write "As drawn (date)" notes in
  `specs/015-m10-apartment-story/contracts/design-briefs.md` for each board, and add the boards to
  M10's row of `docs/delivery-plan.md` "Design sources".

---

## Phase 12: Polish & Cross-Cutting Concerns

**Purpose**: The integration tests, the documents, the full checks, the reviews and the owner's list.

- [ ] T134 Write `apps/mobile/integration_test/apartment_loop_test.dart`, headless (`-d
  flutter-tester`), offline, for a scripted chapter-3 player with enough coins and the card setting
  on «always» (quickstart §5):
  1. the shabka bought once, then its trip's card, whose close lands on the rooms view;
  2. the salon's pieces bought, one in a requested style, and «خد» showing the pending toast, with
     BONAT unchanged;
  3. `RoomDone` with «في الطريق», then «شوف المشهد» playing the goal scene, recorded once;
  4. the timeline with chapter 4 done, and the album counting every scene.

  Time SC-009 with a `Stopwatch` (the tab, a sheet and the timeline under 0.5 s; a first panel under
  1 s on CI). M07's, M08's and M09's integration tests still pass.
- [ ] T135 Write `apps/mobile/test/core/progress/story_run_test.dart` (SC-005): over `storyShaped()`
  and the sample, script a player from the first open to chapter 4's end through the economy. Every
  scene becomes waiting at its moment exactly once, is due or offered where story-flow.md says, and
  is in the album at the end.

  SC-005 names the first-release pack, which is still a draft in the `content-core-r1` worktree. So the
  test also runs over a pack file:
  - With `--dart-define=STORY_RUN_PACK=<path to a .json.gz>`, a second group runs the same script
    over that pack. Without it, the group is skipped, saying why.
  - Build the draft (after T012) with
    `uv run wassal-content bundle dev --source /mnt/endeavour/home/saied-dev/Work/wasal_ogra-core-r1/content/drafts/core-r1/pack --out <scratch dir>`
    in `tools/content_kit`, never into `apps/mobile/assets/`. Then run
    `fvm flutter test test/core/progress/story_run_test.dart --dart-define=STORY_RUN_PACK=<the .json.gz it wrote>`.
  - Record the result in `docs/owner-actions.md` section 015. If the kit refuses to bundle the draft,
    record the refusal and its reason, and rerun when the draft is promoted.

  (Depends on T012.)
- [ ] T136 [P] Update `docs/architecture-mobile.md`:
  - §5: the `features/apartment/` and `features/story/` trees;
  - §9: `/story/scene/:sceneId`, `/story/album`, `/apartment/pre-trip/:tripId`;
  - §12: `story_progress`, `claim_request` and the `story` mapping;
  - §13: the story, request and reward rules, and pending vs received;
  - §14: the content fields.
- [ ] T137 [P] Update the content docs:
  - `docs/architecture-backend.md` §9: the fields and `StoryRider`;
  - `content/README.md` "Scenes": the goal moment and V-C10–C12, and a new "What the apartment shows
    (M10)";
  - `specs/003-b04-content-pipeline/contracts/content-schemas.md`: the new codes and fields;
  - `specs/003-b04-content-pipeline/data-model.md`: the new columns and `content.StoryRider`;
  - `docs/runbooks/content-publishing.md`: the republish after this deploy.
- [ ] T138 [P] Update `docs/delivery-plan.md`: HANDOFF §9.3 #2 marked settled (the tab from chapter
  1). Add the Progress line for `015-m10-apartment-story` when it merges. T133 does the Design
  sources row.
- [ ] T139 [P] Update the guides by hand:
  - `apps/mobile/CLAUDE.md`: M10 in the area's features; the two operations and schema 5; the new
    domain folders in the guards line; the synced apartment art; the routes; the integration tests'
    commands;
  - `tools/content_kit/CLAUDE.md`: the fields and V-C6–V-C12, V-R3, V-R4;
  - `backend/CLAUDE.md`: migration `0011` and `StoryRider`;
  - `packages/trip_engine/CLAUDE.md`: the `Xorshift32` export and why;
  - the root `CLAUDE.md`: "015 M10 apartment and story" in the feature list.
- [ ] T140 Complete section 015 of `docs/owner-actions.md`, each item with its task ID, and update
  "Open now":
  - **before merge:** T130, T141–T143, T146;
  - **after merge:** T147–T150;
  - T012's change to the release draft.
- [ ] T141 **Owner approval** of the strings drafted in research R19, and of any copy the boards
  changed. Apply changes in `apps/mobile/lib/l10n/app_ar.arb` and regenerate the goldens they touch.
- [ ] T142 **Owner approval** of:
  - the departures (plan "Complexity Tracking");
  - the expected golden differences of the nine artboards (research R18);
  - the goldens of the composed states, in both digit styles
    (`apps/mobile/test/goldens/design/goldens/`): the apartment offline, at 360 pt and 1.3×, and any
    owner board not yet drawn.
- [ ] T143 **Owner approval** of the release draft's new texts (T012): scene titles; character, ready
  and room lines; style comments; taglines; the riders, their comments and failure reasons; the
  askers.
- [ ] T144 Run every CI check and fix anything found:
  - **`tools/content_kit`:** `uv run ruff check . && uv run ruff format --check . && uv run mypy .
    && uv run pytest --cov --cov-fail-under=80`, `codegen --check`, `golden`,
    `bundle dev --check --out ../../apps/mobile/assets/content/dev`.
  - **`packages/content_models`:** analyze, test, coverage.
  - **`packages/trip_engine`:** analyze, test, coverage ≥ 90%.
  - **`backend`:** ruff, mypy, `pytest -n 4 --cov --cov-fail-under=80`,
    `makemigrations --check --dry-run`, and `spectacular` unchanged.
  - **`tools/solver`:** ruff, mypy, `pytest -n 4`, `wassal-solver parity`.
  - **`apps/mobile`,** in its guide's order: pub get, build_runner, Rive setup, format, analyze,
    `flutter test --coverage --exclude-tags backend`, `check_coverage --min 80`, every integration
    test headless, `flutter test --tags rive`.
- [ ] T145 Run the reviews, fix CRITICAL and HIGH findings, then rerun T144:
  - `flutter-reviewer` over the Dart diff: rebuild scope; `mounted` after awaits in the purchases,
    the claim, the viewer and `StoryAfterResultImpl`; the watcher's disposal; the drift migration;
  - `python-reviewer` over `backend/apps/content` and `tools/content_kit`;
  - `security-reviewer` over the purchase and claim paths (one intent, no client price, no BONAT
    added on the phone, rollback), the new operations' wire payloads, and the share render (no
    player data beyond the panel).
- [ ] T146 **Owner, before merge:** review the side-by-side images of the nine artboards and every
  exported board (quickstart §4).
- [ ] T147 **Owner, after merge:** deploy, then rebuild and publish a fresh pack on staging. Packs
  without the required fields no longer read (research R16, `docs/runbooks/content-publishing.md`).
- [ ] T148 **Owner, after merge:** the device pass of quickstart §7 on the Redmi Note 7, or the
  Galaxy A06 when available, covering SC-009. Claude asks before connecting to the phone.
- [ ] T149 **Owner, after merge:** the moderated playtest for SC-010. After opening the tab once, can
  four of five new players say what they are saving for and how much is left? Claude records the
  count in `docs/owner-actions.md` section 015.
- [ ] T150 **Owner, not blocking:** the art of research R17: the empty salon, the twelve style
  drawings, chapters 1–4's undrawn panels and the goal drawings. The fallbacks ship meanwhile. Each
  drawing lands in `docs/design/illustrations/` and is synced into
  `apps/mobile/assets/illustrations/{apartment,panels}/` by `tool/design/sync_assets.dart`.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: none.
- **Foundational (Phase 2)**: after Setup. Blocks every story. Within it:
  - T003 → T004; T003 → T005 → T006 → T007; T008 after T006; T009 after T004 and T008;
  - T010 after T007 and T008 → T011; T012 after T006;
  - T013–T016 (tests) at any time → T017 → T018 → T019 → T020 → T023; T021 and T022 after T018;
  - T024–T026 (tests) at any time; T027 and T028 after T004; T029 after T023;
  - T030–T032 at any time after T004; T033 → T034; T035 after T027.
- **US1 (Phase 3)**: after Foundational.
- **US2 (Phase 4)**: after Foundational. T062 edits US1's `apartment_screen.dart` (T046), and the
  chapter bar comes from T044.
- **US3 (Phase 5)**: after US2 (`RoomDone` opens from `PiecePurchase`'s result in `rooms_view.dart`).
- **US4 (Phase 6)**: after Foundational. T091 edits US2's `rooms_view.dart`. `RoomDone`'s
  «شوف المشهد» (T070) reaches the viewer once T093 lands.
- **US5 (Phase 7)**: after US4's `StoryService` (T082). T098 also needs US1–US3 and US7's claim
  (T113).
- **US6 (Phase 8)**: after Foundational. Its replays need US4's viewer (T087) to play.
- **US7 (Phase 9)**: after Foundational. The badge sits in US2's `rooms_view.dart` (T062), and the
  piece sheet's mark (T061) uses the same `requestStates`.
- **US8 (Phase 10)**: after Foundational (T002, T004, T008, T032). Independent of the apartment.
- **Owner's boards (Phase 11)**: T130 can start now. T131–T133 wait for the export and for the
  stories whose screens they align.
- **Polish (Phase 12)**: after the stories. T134 needs US1–US4, US6 and US7; T135 needs US4, and
  T012 for its run over the release draft;
  T141–T143 can start as soon as their strings, goldens and texts exist.

### Within Each User Story

- Tests first, and failing, before implementation.
- Domain (pure), then application (providers), then presentation, then the router.
- Shared files (Organization) in task order.

### Parallel Opportunities

- **Setup:** T001 and T002.
- **Foundational:**
  - the content chain beside the economy chain, side by side;
  - T005, T009 and T012 once their inputs exist;
  - the tests T013–T016 and T024–T026 together;
  - T027 and T028; T030–T032.
- **US1:** the tests T036–T039; then T040, T041 and T044; then T049 and T050.
- **US2:** the tests T051–T055; then T056, T057, T059 and T060; then T065 and T066.
- **US4:** the tests T075–T081; then T084, T085 and T086; then T094 and T095.
- **US6:** the tests T099–T102; then T103 and T104; then T109 and T110.
- **US8** runs beside US1–US7 once Foundational is done: it touches only `features/trip/` and its
  own strings (`app_ar.arb` in task order).
- **Polish:** the documents T136–T139.

---

## Parallel Example: Foundational

```text
T005 tools/content_kit/tests/test_rules.py
T013 apps/mobile/test/core/economy/domain/story_rules_test.dart
T014 apps/mobile/test/core/economy/domain/economy_state_test.dart
T016 apps/mobile/test/core/sync/domain/{op_wire,state_snapshot}_test.dart
T024 apps/mobile/test/core/progress/story_test.dart
T025 apps/mobile/test/core/progress/requests_test.dart
T026 apps/mobile/test/core/progress/rewards_test.dart
```

## Parallel Example: User Story 2

```text
T051 test/features/apartment/domain/room_model_test.dart
T052 test/features/apartment/domain/piece_sheet_model_test.dart
T053 test/features/apartment/application/piece_purchase_test.dart
T054 test/features/apartment/rooms_view_test.dart
T055 test/features/apartment/piece_sheet_test.dart
```

## Parallel Example: User Story 4

```text
T075 test/features/story/application/story_service_test.dart
T076 test/features/story/application/story_due_watcher_test.dart
T077 test/features/story/application/story_after_result_test.dart
T078 test/features/story/domain/scene_sequence_test.dart
T079 test/features/story/scene_viewer_page_test.dart
```

---

## Implementation Strategy

### MVP First (User Stories 1–2)

1. Phase 1 and Phase 2: the content fields everywhere, the two operations with schema 5, and the
   proven rules.
2. Phase 3 (US1): the goal view and the shabka.
3. Phase 4 (US2): the rooms view, the piece sheet and buying a piece.
4. **Stop and validate**: on a dev build, offline, save to the shabka, buy it, play its card, and
   furnish two pieces of the salon in chosen styles.

### Incremental Delivery

1. US1–US2: save and furnish. The MVP.
2. US3: the finished room, its reward on its way, and the end of the story.
3. US4: scenes at their moments, the viewer and share. Required before the PR: the release's
   chapter scenes depend on it.
4. US5: restore and backfill, proven against the dev stack.
5. US6: the timeline and the album.
6. US7: family requests.
7. US8: riders in story trips.
8. The owner's boards as they land (Phase 11). Each board aligns its state and adds its checks.
9. Polish: the integration tests, the documents, the checks, the reviews and the owner's approvals.

---

## Phase 13: Review fixes (round 1)

These tasks come from `reviews/round-1.md`.

- [X] T151 [R1-1] Fix `content_item_slot_minimum` in `backend/apps/content/migrations/0011_m10_story_fields.py` (and the matching `Meta.constraints` of `Item` in `backend/apps/content/models/story.py`): the migration adds `slot_w`/`slot_h` with `db_default=0` and then a CHECK requiring both ≥ 24, which Postgres rejects on any database that already has `Item` rows. After the fix the migration must run on a database that has items (expand-only): either let the not-yet-authored `0` pass (for example `slot_w = 0 OR slot_w >= 24`, and the same for `slot_h`) or move the minimum into a later migration; the kit's V-R3 and the build keep refusing a missing slot. Regenerate nothing by hand; run `makemigrations --check`. Add a migration test that migrates from `0010` with an `Item` row in place and fails before the fix. (HIGH, per the expand/contract rule and T011)
- [X] T152 [R1-2] Fix the `no-any-return` error at `tools/content_kit/tests/test_rules.py:107`: type the value `_riders` returns (for example `riders: list[dict[str, Any]] = pack[…]; return riders`) with no `# type: ignore`. `uv run mypy .` in `tools/content_kit` must exit 0. (HIGH, step 3 failing check)
- [X] T153 [R1-3] Stop `storyOverrides()` showing «مشهد جديد مستنيك» on Home before scenes are recorded: in `apps/mobile/lib/features/story/story_overrides.dart`, `apps/mobile/lib/bootstrap/bootstrap.dart` and `apps/mobile/test/helpers/pump_app.dart`, make the waiting-scene slot count M07's `first_session` scenes as seen, or keep the override out of the real app until `StoryService.backfill` and `recordSeen` (T088 and its backfill task) exist. Then make the Home fixtures treat the sample's opening as seen (`test/design/samples/c_home.dart`, `home_states.dart`, the shared player state), regenerate the Home goldens (`C-Home_*`, `HomeStates_*`, `dot_*`, `server_states_*`, `all/home*`) so they show the savings bar as `docs/design/png/C-Home.png` does, and keep the waiting text in its own golden. Add a test that fails before the fix: a player who saw the opening in `first_session` sees the bar. (HIGH, per FR-031 and `apps/mobile/CLAUDE.md` "Checking a screen against the design")
- [X] T154 [R1-4] Remove the duplicate `destPreTrip` pair at `apps/mobile/lib/l10n/app_ar.arb:103` (the key exists at line 59 and `routes.dart:165` and `:220` use it): reuse the existing key for `RouteNames.apartmentPreTrip`, or give that route its own key and keep the old wording. Add a repo test that fails on a duplicate key in `app_ar.arb`, and update the placeholder goldens that carried the new title. (MEDIUM, per T033 and the l10n rule)
- [X] T155 [R1-6] In `backend/apps/content/models/story.py` (`Chapter.clean`) require `story_title` whenever the chapter has a story condition, a fail reason or any rider, and in `backend/apps/content/services/snapshot.py:208` stop dropping those fields when the title is empty (emit them so the schema refuses the shape). Add a test in `backend/apps/content/tests/test_story_fields.py` that fails before the fix: riders and a condition with an empty title are refused at save and never silently dropped from the built pack. (MEDIUM, per FR-056 and FR-057)
- [X] T156 [R1-7] Add the missing T034 case to `apps/mobile/test/features/home/application/start_next_trip_test.dart`: starting from `StartFrom.apartment` while a scene is due goes to the scene first (needs the due-scene source of T088 or a seeded one), and make the empty-tank test exercise apartment-specific code. If the due-scene source isn't built yet, say so beside T034 and put the case in the story that builds it. (MEDIUM, per T034)

## Phase 14: Review fixes (round 2)

These tasks come from `reviews/round-2.md`.

- [ ] T157 [R2-1] Give the apartment's pre-trip page the same treatment as `linePreTrip` in `apps/mobile/lib/core/routing/router.dart` (the `RouteNames.apartmentPreTrip` case, about line 275): it wraps `PreTripCard` in `Scaffold(body: SafeArea(…))`, so the card runs edge to edge (the stop cards, the stars, the «لسه» hints and the «اطلع» button touch the screen edges; see `apps/mobile/test/goldens/goldens/all/apartmentPreTrip_western.png` beside `linePreTrip_western.png`). Build `PreTripCard` the way `linePreTrip` does (the sheet surface and side insets M09 gives it, no extra `Scaffold`), keeping the `ValueKey(tripId)`, `leaveTo: '/apartment'` and `closeTo: '/apartment'`. Regenerate the `apartmentPreTrip_*` goldens, and add a test that fails before the fix, for example a layout assertion in `apps/mobile/test/core/routing/` (or beside the card's own test) that the card's content sits inside the same side inset as the Lines card at 390×844. (MEDIUM, per FR-060, T034 and `contracts/apartment.md` "M09's `linePreTrip` pattern")
