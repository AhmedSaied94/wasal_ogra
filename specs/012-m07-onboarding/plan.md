# Implementation Plan: Onboarding and the Tutorial Trips (M07)

**Branch**: `012-m07-onboarding` | **Date**: 2026-10-27 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/012-m07-onboarding/spec.md`

## Summary

M07 turns a fresh install into a first session that teaches the game inside five trips. It covers:

- **A first-session state machine** (`FirstSession`), built from stored facts: a new `first_session`
  table, trip progress, the tutorial grant and the name, and the active pack. It decides:
  - where boot goes (the intro, the Name card, trip 1, or Home for a restored player);
  - what comes before a trip (a due scene, the fuel lesson);
  - what a result leads to.
  - Two router redirects make every way into a trip go through it (R1–R4, R11, R12).
- **Scenes as content:**
  - `Scene` gains an optional `plays` (`opening`, `after_trip` + trip id);
  - a `narrator` line is a panel's caption;
  - B04 stores the new field (a migration, the importer, the export, the admin).
  - One comic player, built to `Intro`, plays the opening and the سلمى scene. Panels without a
    drawing get a fallback made from the character art (R5, R6, R13, R15).
- **The Name card**, built to `Name`:
  - the phone's name rules and a pool of 24 suggestions, which the backend checks against its filter;
  - the name saved at once as a `settings_update` operation (Clarifications Q3);
  - a refusal rolls the name back through M06's fold, and the Name card reopens as a sheet on Home
    (R7).
- **Two new operations,** `settings_update` and `tutorial_gift`. The name and the tutorial grant join
  the economy projection, so rollbacks and restores handle them, and they are mapped from GET
  /v1/state. Database v4 (R8).
- **The coach:**
  - a pure `TutorialCoach` computes each lesson's step from the trip's state, so a kill or a resume
    brings it back;
  - 008.5's `CoachMark` draws the scrim, the hole, the ring and the hand around a live rect from a
    new anchor registry;
  - بلية's lines name the trip's real amount, coin and station (resolving HANDOFF §9.3 #3);
  - the trip's clock keeps running (Clarifications Q1; R14, R16, R18).
- **The guided order** (Clarifications Q2): trip 1 → 2 → 3 → the سلمى scene → the notification ask's
  place (M14) → trip 4 → the fuel lesson → trip 5 → Home, through a «كمّل» on M02's placeholder
  result until M08 (R12).
- **The fuel lesson** (Clarifications Q4): a card built to a new `FuelLesson` artboard, drawn on the
  Claude Design canvas from this plan's brief. It fills the tank once as the `tutorial_gift`
  (R9, R10).
- **The locked boosters bar** until the tutorial ends (R17).
- **A compact trip layout** below `inset + 764` pt:
  - a 72 pt HUD and a 226 pt dashboard, with the controls in the bottom third;
  - compact seat tables that keep every face at its minimum at 360×640.
  - It closes M02's approved exception to constitution XI (R19).
- **Test content** from the release draft's five tutorial trips, a fixture, while the sample's trips
  stay untouched (R20).
- **Internal tools** to replay every first-session screen (R21).

Technical approach and versions: [research.md](./research.md).

## Technical Context

**Language/Version**:

- Dart 3.13 with the FVM-pinned Flutter 3.47.7 (`.fvmrc`).
- Python 3.13 (uv) for the content kit and the backend.

**Primary Dependencies**:

- **New direct:** `characters` (already in the lock through Flutter), for grapheme-cluster lengths in
  the pure name rules.
- **Existing:** Riverpod 3 with its generator, `go_router`, drift, Flame and `rive` 0.14 (the trip and
  the characters), `content_models`, `trip_engine`, `flutter_svg`.
- Backend: Django 5.2 (B04's content app); content kit: Pydantic codegen.
- **Rejected:** a Unicode-normalization package (R7); a tutorial flag on trips (R3).

**Storage**:

- **App database v4:**
  - `ledger_ops`' type CHECK gains two types;
  - new `player_state` (`display_name`, `tutorial_granted`);
  - new `first_session` (data-model.md).
- **Backend:** `content.Scene.plays_kind` and `.plays_trip` (migration `0009_scene_plays`).
- **Memory:** the coach's per-run memory, the name sheet's per-launch flag, the debug coach switch.

**Testing**:

- `flutter_test` on real SQLite and fakes:
  - unit tests first for `FirstSession`, `TutorialCoach`, `NameRules` and the two operations' rules;
  - goldens and layout tests for `Intro`, `Name`, `Tutorial` and `FuelLesson`;
  - the compact size tests at 360×640 and 360×720;
  - kill tests at every step;
  - an integration test of the whole first session offline;
  - a `sync-e2e` case;
  - drift's v3 → v4 migration test.
- Content kit: pytest for V-C3–V-C5 and `codegen --check`.
- Backend: pytest for the scene field and the name pool.
- Coverage ≥ 80% (R22, contracts/ci-checks.md).

**Target Platform**:

- **Android**: `minSdk 24`, `targetSdk 36`, all three flavors.
- **iOS 15.0**: built on Codemagic; no Podfile, and no new plugin.
- **Linux**: for CI and goldens.

**Project Type**: A mobile app feature in the `wassal` monorepo. It touches:

- `apps/mobile/lib/features/onboarding/` (new);
- the trip feature: coach hook, anchors, locked bar, compact layout;
- the economy and sync domains: two operations, the projection, the mapping;
- boot and the router;
- the content schema with the content kit;
- B04's content app;
- the sample pack;
- the design assets tool.

**Performance Goals**:

- The first trip within 20 s of first open on the Galaxy A06, tapping through (SC-001). Boot's cold
  start is unchanged, and the opening scene and Name card add no loading.
- The coach costs one pure evaluation per published model (O(passengers)) and one rect report per
  layout. The trip keeps its frame budget (M02's `trip_fps.sh` on the A06).
- No new work at launch beyond reading one row.

**Constraints**:

- Offline-first: nothing in the first session waits for the network.
- No rules change, no parity fixture change, and no engine change (constitution I, III).
- The trip's clock is never paused by the coach.
- No ads in the first session.
- No text in the Flame canvas.
- The coach is the only reader of amounts the trip view hides, and only in tutorial trips.
- Game state stays out of the preference store.
- Each table has one writer.
- Integer money.
- Every player-facing string is in `app_ar.arb`; scene text is in the pack.

**Scale/Scope**:

- 2 operation types, 2 new tables and 1 changed one, 2 routes.
- 4 artboards (1 new) and 3 new components.
- About 35 strings.
- About 30 new `lib/` files and about 30 test files.
- 1 backend migration, 3 validator rules, 1 schema field, the sample's chapter 1, and 6 documents
  updated.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| # | Principle | Applies | How M07 satisfies it |
| --- | --- | --- | --- |
| I | Engine purity | Yes | No engine change. The coach is app code that reads the exported `TripState` (R14). |
| II | Integer money | Yes | Amounts in the coach's lines are integer piasters, formatted only for display. The new columns are INTEGER, TEXT or BOOLEAN (no REAL, the guard). |
| III | Parity | Yes | No rule, parameter or fixture change. The sample's trips are untouched (R20). The trip's clock isn't paused (Clarifications Q1). |
| IV | Server authority | Yes | `tutorial_gift` adds fuel, never BONAT, and the server decides it once (`already_granted`). The name is the server's to accept, and a refusal rolls back through M06's fold (R7, R8). The direction test lists both operations. |
| V | Offline-first | Yes | The whole first session runs offline. The name never waits for the server (Clarifications Q3), and the gift applies at once and syncs later. First trip within 20 s (SC-001). No registration, settings, network or ads before it. |
| VI | Idempotency | Yes | Both operations carry UUIDv7 `client_txn_id`s. The gift's local rule and `stillValid` keep one per player; the server's `already_granted` is the backstop. The flags are monotonic (steps never go down; scenes are recorded once). |
| VII | Content, not code | Yes | The scenes, their order and their captions are pack data (R5). The tutorial trips are derived from the pack (R3). UI strings (coach lines, names, lesson) are in `app_ar.arb`. The scene text is in content. |
| VIII | Tunable numbers | Yes | No new balancing number. The refill minutes in the lesson come from `fuel_regen_minutes`. The look-only step lasts `trip_bubble_min_ms_<line>`. Motion durations are `MotionTokens`. |
| IX | No ads in a trip | Yes | No ad call. M11 is handed `tutorialDone` to hold interstitials. |
| X | RTL and Arabic first | Yes | Every screen in RTL with both digit styles (goldens). Amounts and counts follow the digit setting, and counts use Arabic plural forms. |
| XI | Accessible minimums | Yes, and it closes M02's exception | The compact profile keeps every minimum from 360×640 at text scales 1.0 and 1.3, with play controls in the bottom third (R19, contracts/compact-trip-layout.md). The coach is announced, and only its target is focusable. بلية's bubble, a coach step's or a hint's, counts toward the two-bubble limit and stays up for its minimum time (contracts/coach.md), which also brings M02's hints under the limit. Reduced motion removes the pulse and the bob. The new components keep 44 pt targets and 12 pt text. |
| XII | No runtime LLM | No | — |
| XIII | Small, testable features | Yes | One spec folder. Tests first for the state machine, the coach, the name rules and the operations. Kill tests at every step, an integration test, goldens and layout tests, migration and guards. Coverage ≥ 80%. |

**Locked stack.**

- Riverpod with its generator, `go_router`, drift and `freezed`.
- Rive for the people and the coach's hand, with static fallbacks.
- No new plugin, so no new interface. The coach reaches the engine's state only through
  `TripController`.

**Security & privacy.**

- **A security review is needed.** The PR changes what the sync sends (two operations), stores the
  player's display name, and changes B04's admin and import.
- The display name is the only personal data. It is the player's own in-game name, as before (M06).
  It is never logged (the no-secret-logging guard covers it).
- The name pool is checked against the server's filter so suggestions are never offensive or refused.
- The redirect's `then` is limited to in-app paths (`/trip/...`, `/home`), so a crafted deep link
  can't send the flow elsewhere.

**Performance budgets.**

- The cold start is unchanged.
- The first trip within 20 s (SC-001), timed on the A06 after merge.
- The trip's frame budget is checked with `tool/perf/trip_fps.sh` on a tutorial trip with the coach
  on.

**CI gates.**

- The mobile analyze, test, golden and coverage jobs, with more tests.
- The `sync-e2e` job gains one case.
- The backend's tests and migration check; the content kit's `codegen --check`, golden and bundle
  check.
- The OpenAPI diff stays empty: no API change.

**Gate result (pre-research): PASS.** No principle is broken. XI goes from an approved exception to
compliant.

**Gate result (post-design): PASS.** The re-check after Phase 1 found:

- the onboarding domain imports only what the extended guard allows;
- the two operations and the projection's new fields go through the economy store's transactions;
- `then` targets are checked;
- the compact numbers meet XI on paper, and the size tests are the proof (R19 "Risk": an
  implementation that can't meet them stops and asks, rather than shipping a miss);
- no BONAT path is added.

## Project Structure

### Documentation (this feature)

```text
specs/012-m07-onboarding/
├── plan.md                       # This file
├── research.md                   # Phase 0: decisions R1–R23, owner actions, hand-overs
├── data-model.md                 # Phase 1: tables v4, domain values, transitions, invariants
├── quickstart.md                 # Phase 1: Part A automated, Part B on a device, done when
├── contracts/
│   ├── first-session.md          # FirstSession, boot, redirects, routes, the result's «كمّل», hooks
│   ├── coach.md                  # lessons, lines, the overlay, anchors, the locked bar
│   ├── name.md                   # NameRules, the pool, the card, the operation, refusal, the sheet
│   ├── fuel-lesson.md            # the FuelLesson artboard brief; the screen; tutorial_gift
│   ├── scenes.md                 # Scene.plays, narrator captions, B04, the sample, ScenePlayer, panel art
│   ├── compact-trip-layout.md    # profiles, compact HUD and dashboard, seat tables, sizes, tests
│   └── ci-checks.md              # tests, guards, goldens, integration
├── checklists/requirements.md
└── tasks.md                      # Phase 2 (/speckit-tasks), not created here
```

### Source Code (repository root)

```text
content/
├── schemas/chapter.schema.json                     # Scene.plays, ScenePlays, ScenePlaysKind
├── examples/sample/chapters/ch1_first_job.json     # + the opening scene; plays on the_stand
├── examples/sample.golden.json                     # regenerated
├── examples/valid/chapter_with_plays.json, invalid/…  # NEW cases
└── README.md                                       # plays, narrator
tools/content_kit/src/wassal_content/
├── models/_generated.py, schemas/*.json            # codegen
└── rules/references.py                             # V-C3–V-C5
packages/content_models/lib/src/generated/chapter.dart   # codegen
backend/apps/content/
├── models/story.py                                 # Scene.plays_kind, plays_trip
├── migrations/0009_scene_plays.py                  # NEW
├── services/{importer,snapshot}.py                 # read and write plays
├── admin/authoring.py                              # SceneInline
└── tests/                                          # round trip, counts, invalid plays
backend/apps/accounts/tests/test_name_pool.py       # NEW: the pool against the filter
apps/mobile/
├── pubspec.yaml                                    # characters (direct)
├── drift_schemas/app/drift_schema_v4.json          # NEW (make-migrations)
├── assets/
│   ├── content/dev/{core-1.json.gz,bundled.json}   # regenerated (bundle dev)
│   └── illustrations/panels/opening_key.svg        # NEW (sync_assets)
├── tool/design/sync_assets.dart                    # copies the panel and lesson art
├── lib/
│   ├── core/
│   │   ├── art/panel_art.dart                      # NEW: PanelArt, PanelFallback
│   │   ├── economy/
│   │   │   ├── economy.dart                        # setDisplayName, grantTutorialGift; view fields
│   │   │   ├── economy_service.dart, drift_economy_store.dart   # the ops; player_state
│   │   │   └── domain/{op,rules,profile_rules,gift_rules,economy_state}.dart
│   │   ├── sync/
│   │   │   ├── domain/{wire/state.dart,state_snapshot.dart}     # grants, display_name
│   │   │   └── sync_engine.dart                    # _isVisible: not settings_update
│   │   ├── storage/{tables.dart,app_database.dart} # v4: CHECK, player_state, first_session
│   │   ├── routing/{routes.dart,router.dart}       # two routes; redirects; onboarding pages; «كمّل»
│   │   └── theme/components/
│   │       ├── story.dart                          # PageDots; ComicPanel with a list of lines
│   │       └── characters.dart                     # NEW home of SpeechBubble and CharacterAvatar (moved from features/trip)
│   ├── features/
│   │   ├── onboarding/                             # NEW
│   │   │   ├── domain/{first_session,tutorial_coach,name_rules}.dart
│   │   │   ├── data/drift_first_session_store.dart
│   │   │   ├── application/{first_session_service,first_session_lifecycle}.dart
│   │   │   ├── presentation/{scene_player,name_screen,name_sheet,name_reask_host,fuel_lesson_screen,coach_layer}.dart
│   │   │   └── onboarding_providers.dart
│   │   ├── trip/
│   │   │   ├── application/trip_controller.dart    # coach hook; hints skipped during a step
│   │   │   ├── domain/{scene_layout,trip_facts,trip_view}.dart   # compact profile; boostersLocked; coach
│   │   │   └── presentation/
│   │   │       ├── coach_anchors.dart              # NEW
│   │   │       ├── trip_screen.dart                # CoachLayer; compact zones
│   │   │       ├── top_bar/…                       # compact HUD; anchor on the countdown
│   │   │       ├── dashboard/{dashboard,tray,boosters_locked_bar}.dart  # compact; anchors; NEW bar
│   │   │       └── cards/pause_card.dart           # the title in the compact profile
│   │   ├── boot/boot_screen.dart                   # launchTarget
│   │   └── dev/onboarding_card.dart                # NEW: the playtest tools
│   └── l10n/app_ar.arb                             # about 35 strings
├── test/ …                                         # contracts/ci-checks.md
│   └── fixtures/tutorial/                          # NEW: the draft's five trips, line, sleeper pools
└── integration_test/first_session_test.dart        # NEW
docs/architecture-mobile.md                         # §5, §8, §9, §12
docs/architecture-backend.md                        # content: Scene.plays, narrator
docs/delivery-plan.md                               # FuelLesson in Design sources; #3 resolved; Progress
docs/design/                                        # FuelLesson + panels (owner step, exported by its tools)
docs/owner-actions.md                               # M07 section (at /speckit-implement)
CLAUDE.md                                           # first_session writer; tutorial fixture
```

**Structure decision.**

- **`features/onboarding/`** holds everything the first session owns: its domain, its store, its
  screens and the coach. The trip feature only gains hooks (the coach in the model, anchors, the
  locked bar) and the compact layout, which is the trip's own concern.
- **`SpeechBubble` and `CharacterAvatar` move to `core/theme/components/`.** They are HANDOFF §3
  components that the onboarding screens and the trip both use, and the move avoids a two-way import
  between the features.
- **No new package.** The coach is app presentation logic over the engine's exported state.

## Complexity Tracking

No new deviations.

**Closed here:** M02's approved exception to constitution XI (faces under their minimums below the
threshold, time-boxed until M07; `specs/008-m02-trip-screen/plan.md`, continued by 008.5). The compact
profile replaces it, and that entry is marked closed in this PR. If the size tests show a minimum
can't hold for `micro_old` at 360×640, implementation stops for the owner's decision (research R19)
instead of reopening the exception silently.
