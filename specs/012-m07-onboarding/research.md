# Research: Onboarding and the Tutorial Trips (M07)

Decisions for [spec.md](./spec.md). Each has the decision, the reason, and what was rejected. M07 builds
on M02's trip screen (`specs/008-m02-trip-screen/`), 008.5's design and layout
(`specs/008.5-m21-design-refresh/contracts/`), M05's economy (`specs/007-m05-local-economy/`), M06's
account and sync (`specs/011-m06-identity-sync/contracts/`), and B03's operations
(`specs/010-b03-ledger-sync/contracts/operations.md`).

## R1. The first session is a small state machine over stored facts

- **Decision:** a pure `FirstSession` (`lib/features/onboarding/domain/first_session.dart`) answers
  every "what comes next" question from four inputs. It holds no state of its own:
  - **the phone's flags**, in a new single-row table `first_session` (R2): the opening scene done,
    the after-trip scenes due and seen, the fuel lesson done, the highest step reached, the tutorial
    done;
  - **the economy's view**: `progress` (which trips have `firstCompletedAtMs`), `unfinished`,
    fuel, and the new `tutorialGranted` and `displayName` (R8, R9);
  - **the active pack**: the tutorial trips (R3) and chapter 1's scenes with their `plays` (R5);
  - **the first open's outcome** (M06's `FirstOpenOutcome`), at boot only.
- Its answers:
  - `launchTarget(outcome)`: where boot goes (R4);
  - `beforeStart(tripId)`: the fuel lesson or a due scene that must come before a trip starts, or
    nothing (R10, R11);
  - `onArrivalAtHome()`: a due scene, or the name sheet (R7);
  - `nextAfterResult(tripId)`: the result screen's main action in the first session (R12);
  - `coachFor(tripId)`: whether a trip is coached (R14);
  - `boostersLocked`, `tutorialDone` and `stepReached` (1–8) for the trip screen, M11 and M15.
- **Why:** after a kill, a restore or a content switch, the answer is rebuilt from what is stored,
  never from what the app remembers. Every rule is a pure function, tested without widgets.
- **Rejected:**
  - one stored "current step" index: it can disagree with trip progress after a restore, a retry or
    a failed trip, and needs repair code;
  - deriving everything from trip progress alone: the opening scene, the scenes and the fuel lesson
    leave no trace in it.

## R2. Where the flags live: a `first_session` table in the app database (v4)

- **Decision:** one row, written only by `DriftFirstSessionStore`
  (`lib/features/onboarding/data/drift_first_session_store.dart`). Columns are in data-model.md.
  The economy-writers guard (`test/repo/economy_writes_test.dart`) gains this store and table.
- **Why:** the constitution and `SettingsStore`'s own rule keep game state out of the preference
  store ("never tokens, secrets or game state"). Drift is where game state lives, and the table is
  tiny.
- **The database goes to v4 anyway** for the two new operation types (R8), so one migration covers
  everything: `make-migrations` writes `drift_schemas/app/drift_schema_v4.json` and the v3 → v4 step
  test.
- **Rejected:** the preference store (game state, and its allowlist would need four new keys); a
  column on `account` (that table holds server facts, written by M06's store).

## R3. Which trips are the tutorial

- **Decision:** the first five trips, by number, of the line whose unlock is `start` in the active
  pack. In every pack so far that is `line_hay.01`–`.05`. A pack with fewer has a shorter tutorial: the
  tutorial is done when every tutorial trip the pack has is finished (R12).
- Story trips are counted like any other (the sample's `line_hay.03` is a story trip).
- **Why:** constitution VII keeps trips as data. The rule follows the content, so no trip id is
  written in code. It also matches the UX spec's "the first five trips of خط الحي".
- **Rejected:**
  - a `tutorial` flag on trips: it changes `TripDefinition`, an engine input, so every parity fixture
    and both engines would be touched for a flag the engine ignores;
  - hard-coded ids.

## R4. Where a launch goes

- **Decision:** `BootScreen._handOver` keeps M06's order (wait for the first open, mark the account
  step, clean the trip records, `handOver()`), then:
  1. An unfinished trip opens that trip, paused (M02, unchanged).
  2. Otherwise `FirstSession.launchTarget(outcome)`:
     - `restored`: Home. The opening scene is marked done, since this player has played before.
     - Any trip progress or a recorded trip start on the phone (a player past the first trip):
       Home.
     - Otherwise, the first session's next step: the opening scene (`/onboarding/intro`) if it is
       not done, the Name card (`/onboarding/name`) if there is no name (R7), or tutorial trip 1.
- The outcome no longer goes unused (`boot_screen.dart` discards it today).
- **Why:** FR-001–FR-003. "Has the first trip started" is answered by the economy (a `trip_start`
  operation or progress), so a kill between the Name card and the trip's first frame resumes at trip
  1, and a kill during it resumes the trip.

## R5. Scenes: when each plays is content, a caption is a narrator line

- **Decision (schema):** `Scene` gains an optional `plays`, a closed object `ScenePlays`:
  - `kind`: `ScenePlaysKind`, either `opening` (at the first open, before the Name card) or
    `after_trip` (right after the trip's first finish);
  - `trip_id`: a `TripId`, present for `after_trip` only.
  - Scenes without `plays` are played by M10's rules (album, chapter end, rooms). M10 adds kinds to the
    enum.
  - The restricted profile allows it: optional properties are left out of `required`, and the
    object and enum are named in `$defs` (`tools/content_kit/src/wassal_content/profile.py`).
    `content/source/pack.json` doesn't exist yet, so schemas may change freely, and adding an
    optional property isn't breaking anyway (`schema_diff.py`).
- **Validator rules** (content kit, new codes in the V-C family):
  - `opening` is allowed only in the chapter with `order` 1, at most once in the pack, and without
    `trip_id`;
  - `after_trip` needs a `trip_id` of a trip in the pack;
  - at most one scene per `after_trip` trip.
- **Captions:** a panel line whose `speaker` is `narrator` is the panel's caption, drawn in
  `ComicPanel`'s caption chip (`Intro` block 2a), not in a bubble. At most one per panel, and it
  comes first. A validator rule enforces both.
  - This needs no schema field and no backend change, since `SceneLine` already stores any speaker.
  - The convention is documented in `content/README.md` and B04's authoring notes.
- **Why:**
  - The spec makes the scenes content (FR-006, FR-046), and M10 needs the same "when it plays"
    signal for story trips (`moallem_verdict` after `line_hay.20`).
  - A `Panel.caption` field would need new array columns on B04's `Scene` (panels are not rows
    there), while the narrator line rides on the existing `SceneLine` rows.
- **Rejected:**
  - a convention on scene ids (`opening`): hidden semantics in an id;
  - scene order in the chapter: fragile, and M10's scenes don't follow it;
  - a `Panel.caption` field: backend arrays for one line of text.

## R6. Backend B04 follows the schema (relational, not JSON)

- **Decision:** `apps/content` stores chapters in columns (`models/story.py`: `Scene.panel_art`,
  `SceneLine` rows). The new field needs:
  - `Scene.plays_kind` (a `CharField` with choices, blank) and `Scene.plays_trip` (a nullable FK to
    `Trip`, `PROTECT`), with a check that `plays_trip` is set exactly when the kind is
    `after_trip`;
  - migration `0009_scene_plays` (expand-only, both nullable, no backfill);
  - `services/importer.py` `chapter()`, `services/snapshot.py` `scene_part()`, the admin's
    `SceneInline` (`admin/authoring.py`) and `services/lookups.py` `rules_document()`, which lists
    scenes, gains each scene's `plays` (as built, `rules_document()` stays unchanged, as
    contracts/scenes.md has it: nothing it serves reads `plays`);
  - tests: the round trip of the sample (`test_import_export.py`, byte for byte), the counts (61
    records → the new total, R22), `test_lookups_rules.py`'s chapter 1 scenes, and a validation case
    for each rule.
- Then `uv sync --reinstall-package wassal-content` in `backend/`. The content kit is imported by
  path (`backend/pyproject.toml`).
- **No API change:** packs are files, and the manifest is unchanged. The OpenAPI diff stays empty.
- **Why:** without it, an import from the admin drops `plays`, and the round-trip test fails.
- **The release draft** (`content/drafts/core-r1`, branch `content-core-r1`, in its own worktree)
  isn't on this branch. Its follow-up is handed over: add the opening scene and `plays` (R22).

## R7. The driver's name

- **Decision (rules the phone checks):** after trimming and collapsing inner whitespace, 2–16
  characters (grapheme clusters, with the `characters` package Flutter already ships); not only
  digits (Western or Arabic-Indic); no control, bidi or zero-width characters.
  - This is B03 R10's set, with the design's 16 as the maximum.
  - The phone does no NFKC: Dart has no Unicode normalization in its core libraries, and the server
    normalizes before its own check. A name the two judge differently is the rare refusal the re-ask
    handles.
  - The filter list stays the server's.
  - `NameRules` lives in `lib/features/onboarding/domain/name_rules.dart` (pure).
  - The field stops at 16 characters (`AppTextField.maxLength`). A paste is cut to 16, then checked.
- **Suggested names:** 24 Egyptian driver nicknames in `app_ar.arb` as `namePool`, separated by
  «،» (list in contracts/name.md). The dice picks a random one other than the one showing.
  - **FR-013's check lives in the backend:** `apps/accounts/tests/test_name_pool.py` reads the ARB
    file and runs every name through the server's validator and the seeded filter. 0 refusals.
    The phone can't run the server's filter, and the backend already reads repo files in its parity
    tests (`test_tunables_parity.py`).
  - A Dart test checks the pool against `NameRules` and that it has at least 20 names.
- **Saving (Clarifications Q3):** «تمام» records a `settings_update` operation
  `{"display_name": <name>}` through `Economy.setDisplayName` (R8). It never waits for the network.
  The name shown is the projection's `displayName` (R8), so it shows at once, offline.
- **Refusal:**
  - The server answers `validation_error` with `details.field = "display_name"` (B03).
  - M06's answer handling marks the operation rejected and refolds without it, so the projection's
    name goes back to the server's last accepted name (the base). Nothing else is needed for
    FR-017.
  - The view's `nameRefused` is true when the newest `settings_update` row is rejected (R8).
  - M06's rollback toast must not fire for a name: `SyncEngine._isVisible` excludes
    `settings_update`, since it changes no balance.
- **Re-ask (FR-018):** on arrival at Home, outside a trip, if the view has no name or `nameRefused`
  is true, and the sheet hasn't opened in this launch, the Name card opens as an `AppSheet`:
  - with a fresh suggestion;
  - with the error line «الاسم ده مينفعش. اختار اسم تاني.» only when `nameRefused`;
  - closable;
  - the "opened this launch" memory is in memory only.
  - The same sheet is M14's edit form (FR-019).
- **No name anywhere** shows the neutral default «الأسطى» (`driverNameDefault`).
- **Why:** offline-first, and the 20 s first trip. The rollback machinery M06 already has does the
  work.
- **Rejected:**
  - a name stored in the `account` table before the server accepts it: that table holds server facts,
    and a refusal would need its own repair;
  - waiting online for a verdict (Clarifications Q3).

## R8. Two new operations, and the name and the grant in the projection

- **Decision:** `OpType` gains `settingsUpdate('settings_update')` and `tutorialGift('tutorial_gift')`.
  - **Requests** (sealed `OpRequest`): `SettingsUpdateRequest(name)` and `TutorialGiftRequest()`.
  - **Rules** (`domain/profile_rules.dart`, `domain/gift_rules.dart`):
    - `settings_update`:
      - validate refuses `invalidName` (the phone's `NameRules`);
      - apply sets `displayName`;
      - `stillValid` is true;
      - no deltas.
    - `tutorial_gift`:
      - validate refuses `alreadyGranted` when `tutorialGranted`;
      - apply sets `fuel = fillToMax(...) ?? fuel` and `tutorialGranted = true`, with the fuel
        delta recorded like `comeback_gift`'s;
      - `stillValid` is `!base.tutorialGranted`, so a grant that arrives from the server drops a
        pending local one.
  - **Entry points** on `Economy` (the screens' interface): `setDisplayName(TxnId, String)` and
    `grantTutorialGift(TxnId)`. Neither is a sync call, so `EconomySync` is unchanged.
- **The projection** (`EconomyState`) gains `displayName` (String?) and `tutorialGranted` (bool):
  - stored in a new single-row table `player_state` (`id`, `display_name`, `tutorial_granted`),
    written only by `DriftEconomyStore`;
  - kept in the base state's JSON, read as `null`/`false` when absent, so v3 bases still parse;
  - mapped by `stateFromSnapshot` from GET /v1/state: `player.display_name` and `grants.tutorial`.
    `StateSnapshot` gains `grants`. This is part of M06 R12's mapping, handed to M07.
- **The view** (`EconomyView`) gains `displayName`, `nameRefused` and `tutorialGranted`.
  `nameRefused` is one query: the newest `settings_update` row's sync status is `rejected`.
- **Wire:** `opWire` sends the stored payload as is. `settings_update` carries `{display_name}`,
  `tutorial_gift` `{}`. Neither is in `contentVersionTypes`.
- **The database CHECK** on `ledger_ops.op_type` lists the wire names, so v4 rebuilds `ledger_ops`
  as v3 did (`TableMigration`), and adds `player_state` and `first_session` (R2).
- **M06's `account.display_name`** stays the server's last answer, unchanged. The name shown is the
  projection's, through `driverNameProvider` (data-model.md "Two copies of the name, two jobs").
- **Guards:**
  - `economy_sync_access_test.dart` is unchanged (the new entry points are on `Economy`);
  - the writers guard adds `player_state`;
  - the domain-imports guard lets `core/economy/domain/profile_rules.dart` import
    `features/onboarding/domain/name_rules.dart` (the one name check the phone and the economy share,
    R7), and nothing else from `features/`.
- **Why:**
  - The projection is the one place every rollback, rebase and restore already goes through, so the
    name and the grant follow those rules with no new code paths (FR-005, FR-017, FR-035).
  - A refused gift is undone like any operation.
- **Rejected:** a grants table keyed by kind (one bool today; M13's comeback gift is tracked in
  `server_info` by M06).

## R9. Fuel max for the gift

- **Decision:** the gift fills to the tunable `fuel_max` (5), as `comeback_gift` does. The server's
  fill (B03) is the same, so the phone and the server agree.
- **Entitlements:** `fuelMaxBonus` and `fuel_max_subscriber` are unused on the phone today. They are
  M12's and M17's, and nothing here depends on them.

## R10. The fuel lesson (Clarifications Q4)

- **Decision:** a card at its own route, `/onboarding/fuel?then=<tripId>` (`RouteNames.onboardingFuel`,
  a page). Its look comes from a new artboard, `FuelLesson`, drawn on the Claude Design canvas
  «وصّل الأجرة — Design» in Style C and exported with `docs/design/tools`.
  - The artboard brief is [contracts/fuel-lesson.md](./contracts/fuel-lesson.md).
  - The illustration it uses is copied by `tool/design/sync_assets.dart`.
- **When:** `FirstSession.beforeStart(tripId)` returns the lesson when the tutorial gift isn't
  granted and either:
  - `tripId` is the last tutorial trip and it has never been started; or
  - `tripId` is a tutorial trip and the tank holds less than one liter (outside an unlimited
    window).
- **What it does:**
  1. Shows المعلم's lines, and the gauge animates from the current liters to the maximum.
  2. On «يلا على المشوار», calls `grantTutorialGift` (once; the rule refuses a second), marks the
     lesson done, and goes to `then`.
  - The grant happens on the button, not on open, so a kill before it doesn't leave a full tank
    without the lesson.
- **The copy** (contracts/fuel-lesson.md) uses `fuel_regen_minutes` as a placeholder, not the number.
  The owner approves it.
- **Until the artboard is committed**, the card isn't built. The tasks order it after the
  owner step (owner-actions).
- **Why:** FR-033–FR-035; the owner chose a card with its own artboard.

## R11. Where the first session cuts in: router redirects

- **Decision:** two rules in the router's global `redirect`, after the boot rule. Both call
  `FirstSession`:
  - **`/trip/:tripId` being started** (no unfinished trip with that id): when `beforeStart` returns
    something, go there first: the due scene (`/onboarding/scene/<sceneId>?then=/trip/<id>`) or the
    fuel lesson (`/onboarding/fuel?then=<id>`).
  - **`/home`**: when a scene is due, play it first, then Home.
  - Each target's last action goes to its `then`.
- **Why:** every way into a trip passes through the router: the result's continue, the pre-trip
  card (M08), Home's main button (M08), the dev trip list, and boot's resume. So one rule covers
  FR-031, FR-033 and FR-037 for features not built yet.
- **Boot's resume of an unfinished trip** is not a start, so it is never redirected.
- **Rejected:** checks in each caller (M08 would have to repeat them); checks inside `TripController`
  (the controller would learn about scenes and lessons).

## R12. The session's order and the result screen

- **Decision:**
  - **The order is fixed (Clarifications Q2):** trip 1 → 2 → 3 → the scene that `plays` after trip
    3 → the notification ask (M14) → trip 4 → the fuel lesson → trip 5 → Home.
  - **`nextAfterResult(tripId)`** for a tutorial trip the player just finished: the next tutorial
    trip's start (the redirects add the scene and the lesson), or Home after the last one.
  - **The result screen** is still M02's placeholder (`/trip/:tripId/result`, `ResultSummary`). M07
    adds a primary «كمّل» (`AppButton.primary`) to it while `FirstSession.inFirstSession`. Its target
    is `nextAfterResult`, and its links keep Home. M08 makes it the real screen's main action
    (contracts/first-session.md "For M08").
  - **Tutorial trips opened from the sequence skip the pre-trip card:** they go to `/trip/<id>`
    directly, which is how the placeholder links today anyway.
  - **The scene after trip 3** becomes due when trip 3's result is recorded as its first finish. The
    store's `scenes_due` is written then, so a kill on the result screen still plays it (FR-031).
  - **The notification ask (step 6)** is a hook M14 fills. M07 marks step 6 reached and goes on.
  - **Tutorial done:** every tutorial trip the pack has has `firstCompletedAtMs`. Taken server state
    counts too (FR-039).
- **`stepReached`** (1–8, for M15) is written as the player reaches each step:
  1. the opening scene starts (or the Name card opens, when the pack has no opening scene);
  2. trip 1 starts;
  3. trip 2 starts;
  4. trip 3 starts;
  5. the scene;
  6. the ask's place;
  7. trip 4 starts;
  8. trip 5 starts.
  It never goes down.

## R13. The opening scene and the after-trip scene: one comic player

- **Decision:** `ScenePlayer` (`lib/features/onboarding/presentation/scene_player.dart`) builds the
  `Intro` artboard for any scene:
  - the chapter title as the header;
  - one `ComicPanel` per panel, with the panel's art (R15), the narrator line as the caption, and
    the first speaking line as speaker and text;
  - further speaking lines of the same panel show in a second bubble, below the first (`ComicPanel`
    takes a list of lines);
  - page dots, «تخطّى», «يلا».
- **Routes:**
  - `/onboarding/intro` plays the pack's `opening` scene. With none, it redirects to
    `/onboarding/name` (FR-010).
  - `/onboarding/scene/:sceneId?then=…` plays an after-trip scene (`RouteNames.onboardingScene`).
  - Both are pages without the bottom nav.
- **Behaviour:**
  - tap «يلا» to advance; never automatic;
  - «تخطّى» and back finish the scene;
  - finishing marks it done in `first_session` (the opening, or that scene id) before navigating.
- **Page dots** are a new small component, `PageDots` (`core/theme/components/story.dart`):
  `Intro` boxes 10–13, with a semantics label of «اللوحة {n} من {total}».
- **Motion:** panel change is a slide-and-fade ≤ 280 ms on the `sheetIn` curve; the bubble pops with
  `bubblePop`. Reduced motion: a 150 ms fade. Durations come from `MotionTokens`.
- **Why:** both scenes are drawn the same way (HANDOFF `Intro`). M10's `SceneViewer` (share,
  «كمّل», scene title) is a different artboard, built there.

## R14. The coach: lessons from the trip's state, not from events

- **Decision:** a pure `TutorialCoach` (`lib/features/onboarding/domain/tutorial_coach.dart`)
  computes the step to show from the engine's `TripState`, the `TripView`, the trip's lesson, and
  its own small memory. It never uses events.
  - **Why state:** the engine keeps no event history, and a rebuild after a kill discards the
    events on the way (`engine.dart:37-57`). A step from state comes back by itself after a resume
    (FR-027).
  - **Lesson by tutorial index** (R3's order), not by trip id. Conditions use exported model
    fields: `PassengerState.isOwed` (`fareSent && balance > 0`), `paidIn`, `alertness`,
    `presence`; `TripState.tray`, `hand`, `tokens`, `lastSend`; `PassengerView.nearStopPulse`.
    The table is in [contracts/coach.md](./contracts/coach.md).
  - **Memory:** the steps finished in this trip run. It is in memory, kept by the controller, and
    reset on `open`. After a kill, a step whose condition still holds shows again, which FR-027
    wants. Trip 1's look-only step may show once more after a kill.
  - **One step at a time** (FR-026): the lessons are ordered, and a step whose target is gone ends.
- **The coach reads amounts** (the change owed) that the trip view hides on purpose (M02 FR-033:
  "the screen doesn't give away who's owed").
  - The tutorial is the exception the design draws («ليه باقي ٣»), and the coach is the only reader.
  - It runs only for a tutorial trip's first finish (R1 `coachFor`), or with the debug switch.
  - A guard limits `TutorialCoach`'s state reads to `features/onboarding/domain/`.
- **Wiring:**
  - `TripController` gets an optional `TutorialCoach` from `tutorialCoachProvider(tripId)` (in
    `features/onboarding/`).
  - On each publish, it calls `coach.step(...)` and puts the result in `TripModel.coach`
    (`CoachView?`).
  - `HintState` is skipped while a step shows (FR-028).
- **Why:** FR-021–FR-030 with no rules change (constitution III). The trip's clock is untouched
  (Clarifications Q1).

## R15. Panel art

- **Decision:** a panel's `art` slug maps to an app asset through `PanelArt`
  (`lib/core/art/panel_art.dart`): a const map from slug to SVG under
  `assets/illustrations/panels/`, copied from `docs/design/illustrations/` by `sync_assets.dart`.
  - At first one drawing existed: `Intro_01.svg`, the opening scene's first panel. It becomes
    `panels/opening_key.svg`.
- **A slug with no drawing** gets `PanelFallback`:
  - the panel's sky (`scene.sky`) over a street strip;
  - the panel's speakers (not the narrator) as `CharacterAvatar`s, side by side and large, the
    current speaker in front.
  - It is drawn from existing art, so every scene plays before its drawings exist, and M10 reuses
    it.
- **The missing drawings** are the opening's panels 2–3 and the سلمى scene's three. They go on the
  Claude Design canvas with `FuelLesson` (an owner step). Each lands as a new map entry and a golden
  update, with no code change.
  - Drawn on 2026-10-28 as the artboards `PanelOpeningStand`, `PanelOpeningGo`,
    `PanelStandMorning`, `PanelSalmaWaiting` and `PanelUstaDecides`. Each artboard's one drawing,
    `<Artboard>_01.svg`, becomes `panels/<slug>.svg`, so all six of the sample's panels are drawn.
- **Why:** art ships in the app, not in packs (delivery plan, "Known gaps"). A missing drawing must
  never block a scene.

## R16. The coach overlay on the trip screen

- **Decision:** `CoachLayer` (`lib/features/onboarding/presentation/coach_layer.dart`), placed above
  the hint layer and below the cards (008.5's layer 8½):
  - **`CoachMark`** (008.5, `core/theme/components/story.dart`):
    - the scrim `scrimCoach` with the hole `target.inflate(6)`, r 18, and the 4 pt sun ring;
    - `CoachHand` placed at the target;
    - its hit test absorbs every tap outside the hole and lets taps inside fall through to the real
      control (FR-024).
  - **بلية and the bubble** as in the hint (`CharacterAvatar('belya')`, `SpeechBubble.character`),
    in `CoachMark.children`, above the scrim. The bubble and بلية take no touch.
  - **Targets** come from a `CoachAnchors` registry (`features/trip/presentation/coach_anchors.dart`):
    - the tray, each tray cell and the station strip's countdown chip are wrapped in `CoachAnchor(id)`,
      a render proxy that reports its global rect after layout;
    - passengers come from `SceneLayout`'s seat hit rect, offset by the scene's origin.
    - So the hole follows the live layout in every arrangement, including the compact one (FR-023,
      FR-042).
  - **Motion:** scrim fade 200 ms; the hole moves 250 ms `easeOutCubic`; the ring pulses 1.0↔1.06
    (`hotTagPulse`); the hand bobs. Reduced motion: no pulse, no bob (FR-045). Values from
    `MotionTokens`; the new ones are added there.
  - **Accessibility:**
    - When a step starts, «بلية: {line}» is announced as a live region (`SemanticsService.announce`
      plus a live-region node);
    - while a step shows, `ExcludeSemantics` wraps everything but the target, whose semantics node
      gets focus (`SemanticsAction.focus` on a post-frame callback) (FR-044).
  - **Back:** the trip screen's `PopScope` already pauses. The pause card is a layer above, and the
    step returns after resume, since it is recomputed from state (FR-027).
- **Bubble placement** keeps `Tutorial`'s: left 14, right 104, its bottom 8 above بلية's top. At text
  scale 1.3 it grows upward and stays inside the screen (clamped).
- **The two-bubble limit and the minimum time** (constitution XI, found by `/speckit-analyze`):
  - بلية's bubble, a step's or a hint's, counts as one of the two bubbles allowed at once;
  - it stays up for its minimum time even when its step ends sooner, while the scrim and the hole go
    at once (contracts/coach.md "بلية's bubble and the two-bubble limit");
  - M02's hints had the same gap, closed here by the same rule.
- **Why:** `CoachMark` was built for this in 008.5 and tested in the gallery. A rect registry is the
  only way to follow dashboard and HUD controls, which have no other geometry source (no
  `GlobalKey`s today).
- **Rejected:** computing rects from the dashboard's row math (breaks with the compact arrangement
  and text scale); `GlobalKey`s on each control (the registry is one mechanism for all).

## R17. The locked boosters bar

- **Decision:** `BoostersLockedBar` (`features/trip/presentation/dashboard/boosters_locked_bar.dart`)
  is drawn as `Tutorial` blocks 3a, 48 and 49:
  - 366×44 at the boosters row, r 14, `dashboard.raised`;
  - a lock icon 16 and «المساعدات بتتفتح بعد المشوار الخامس» in `dashboard.muted`, `caption` 600.
  - `TripFacts.boostersLocked` (from `FirstSession.boostersLocked`) swaps it in for `BoostersRow`.
  - `UseBooster` can't be sent: the controls aren't there.
- **Why:** FR-038. The bar is a trip component, so it lives with the dashboard.

## R18. Coach lines (resolves HANDOFF §9.3 #3)

- **Decision:** the lines below, in `app_ar.arb`. Numbers are preformatted strings, and counts use
  ICU plurals (`arb_placeholders_test` rule).

  | Trip | Key | Line |
  | --- | --- | --- |
  | 1 | `coachFareArrived` | «شايف؟ الأجرة وصلت الدرج» |
  | 2 | `coachGiveChange` | «ليه باقي {amount}. دوس على {coin} {count, plural, =1{مرة} =2{مرتين} few{{count} مرات} other{{count} مرة}}، وبعدين دوس عليه.» |
  | 2 | `coachGiveChangeAny` | «ليه باقي {amount}. خد الفكة من الدرج، وبعدين دوس عليه.» |
  | 2, 3 | `coachTapRider` | «دلوقتي دوس عليه.» (the second target, once the hand holds the change) |
  | 3 | `coachStopNear` | «نازل {station}، لازم ياخد باقيه قبلها» |
  | 4 | `coachWakeSleeper` | «ده نايم، دوس عليه صحّيه» |
  | — | `coachCoinName` | a `select` on the denomination: «النص جنيه», «الجنيه», «الخمسة», «العشرة», «العشرين», «الخمسين», «المية», «الميتين» |

- **The coin** is the largest denomination `d` such that `d` divides the amount owed and the tray
  holds at least `amount / d` of it. With none, the fallback line is used. For trip 2 of the draft
  (owed 3), that is the 1-pound coin three times, exactly as drawn.
- **The station** is the station's name from the line, in the active pack.
- **Why:** the ux-spec gives lines 1, 3 and 4, the artboard gives line 2, and the brief requires
  `{station}`. The second-target line is new: the drawn sequence points at the rider after the coins,
  and silence there confused the M02 playtest the ux-spec describes.
- **Owner action:** approve the lines (with the fuel lesson's and the name's).

## R19. Short screens: a compact arrangement below the threshold

- **Decision:** below `inset + 764` pt, the trip uses the **compact profile**. It closes M02's
  exception. The full geometry is [contracts/compact-trip-layout.md](./contracts/compact-trip-layout.md).
  - **`TripHud` compact: 72 pt.**
    - One 64 pt row: the pause button, then the `StationStrip` (unchanged, full information).
    - The `ReputationBar` becomes a 6 pt bar along the strip card's bottom edge, with its
      semantics label and the «تحت ٤٠٪» chip when low. (Implementation moved it to the card's top
      edge, clear of the fares: contracts/compact-trip-layout.md.)
    - The trip's title moves to the pause card (spec FR-041 amended, R23).
  - **`Dashboard` compact: 226 pt.**
    - The «آخر كلام» log moves to the top as one line (20 pt), followed by the hand row, the two
      tray rows and the boosters row, with 4 pt gaps.
    - The four control rows sit in the bottom 202 pt, which is inside the bottom third at 640 pt
      (213 pt).
  - **The scene** takes the rest: 334 pt at 360×640 with a 24 pt inset.
  - **Seats.** At a scene of 408 pt or more, 008.5's table with its crop applies. Below 408, the
    compact seat table:
    - `micro_old`: back `C` y 46 at scale 0.6 (face 50.4); middle `B` y 122 at 0.66 (55); near `A` y
      206 at 0.952 (80); `front` y 284 at 0.952 (80); hand (162, 290).
    - `tuktuk`: its row at `scene − 136`, scale 1.15.
    - All of it is anchored to the scene's bottom, with extra room growing the wall at the top.
    - Hit areas narrow to the seat spacing, never below 44 pt.
  - **Under 334 pt of scene** (screens under 640 pt, outside the supported range): the compact table
    scales down as M02 did, with hit areas clamped to 44. The supported range starts at 360×640
    (spec Assumptions).
- **Checks:**
  - `scene_layout_test.dart` checks the compact table at 360×334, 390×334 and at the threshold edge.
  - `trip_minimum_sizes_test.dart` gains the `small` (360×640, now compliant) and `mid` (360×720)
    surfaces, at text scales 1.0 and 1.3.
  - The goldens' `small` images are regenerated.
  - The owner approves the compact look from the goldens (owner action), since no artboard draws it.
- **Why:**
  - The arithmetic: at 640 pt with a 24 pt inset, 008.5's bars leave a 260 pt scene, and
    `micro_old` needs about 334 pt at its minimum scales.
  - Only the bars can give that room, and they can't move controls out of the bottom third.
  - The middle row has no minimum of its own, so it shrinks toward the back row's.
- **Risk:** the numbers are a first proposal. If the size tests show a minimum can't hold at 640 for
  `micro_old`, the implementation stops and asks the owner (crop more wall, or keep a time-boxed
  exception for screens under 680 pt). It doesn't ship a silent miss.

## R20. Tutorial content for tests and for playing on a device

- **Decision:**
  - **The sample's trips stay as they are.**
    - Rewriting `line_hay.01`–`.03` would change 6 parity fixtures and their expectations, the
      engine's exact-timing story test, the solver's tests and about 200 backend economy tests (the
      `HAY_DONE` sets).
    - Adding `.04`–`.05` would break every "exactly five trips" list and the line-completion tests.
    - None of that is M07's purpose.
  - **A test fixture of the release draft's five tutorial trips**, `apps/mobile/test/fixtures/tutorial/`:
    - `line_hay.01`–`.05.json` from `content/drafts/core-r1/pack/trips/line_hay/`;
    - the draft's `line_hay` line and the sleeper's speech pools.
    - A helper, `tutorialContent()`, layers them over the sample bundle.
    - FR-047's coached player, the integration test and the `Tutorial` sample use it.
  - **The release pack, when bundled:** CI runs FR-047's check on `assets/content/release` too, and
    skips it while that folder has no pack.
  - **The sample gains chapter 1's opening scene** (`opening`, 3 panels, with the `Intro` copy) and
    `plays: after_trip line_hay.03` on `the_stand`. Then:
    - the golden checksums and the dev bundle are regenerated;
    - B04's tests are updated (R6).
    - Parity fixtures don't change: they hold trips only.
  - **On a device:** a dev build plays the real tutorial against the local stack.
    1. Import the draft as a zip in the dev admin and publish it.
    2. M04's updater downloads it and switches at the next launch (quickstart Part B).
    - With only the bundled sample, a dev build has a three-trip tutorial (its `line_hay.03` is a
      story trip) and no fuel lesson unless the tank runs dry.
- **Spec amended:** FR-046 now says this (R23).
- **Why:** the tests use the trips the players will get, and nothing outside M07 changes.

## R21. Internal builds

- **Decision:**
  - **On the playtest Home** (dev and staging, `playtest = flavor != prod`), an «Onboarding» card next
    to the trip list:
    - open the opening scene, the Name card, any after-trip scene, and the fuel lesson (with
      `then=/home`);
    - a switch, "coach on every tutorial trip", held in memory, that `tutorialCoachProvider` reads.
  - **The trip list** marks tutorial trips.
  - None of it is reachable on prod; the existing `playtest` gate and a routing test check that.
- **Why:** FR-048, US6.

## R22. Testing

- **Tests first** (constitution XIII):
  - `FirstSession`'s rules: launch targets, `beforeStart`, `nextAfterResult`, tutorial done, steps;
  - `TutorialCoach`'s lessons: each condition, target and end, from built states;
  - `NameRules`;
  - the two operations' rules, including `stillValid` after a server grant;
  - the snapshot mapping of `grants.tutorial` and `display_name`.
- **Widget and golden:**
  - `Intro`, `Name`, `Tutorial` and `FuelLesson`: sample builder, goldens in both digit styles, and
    layout test (`expectLayoutMatches`);
    - `Tutorial` keeps 008.5's passenger pairing note: the tuktuk's seats stay at 008.5's x, so the
      two drawn riders are skipped with that reason, while the hole, the hand, بلية, the bubble and
      the locked bar are matched;
  - `PageDots`, `BoostersLockedBar`, `PanelFallback` and the name sheet;
  - the compact arrangement's goldens at `small` and `mid`.
- **Integration:**
  - `integration_test/first_session_test.dart`: offline, from a fresh database through the five
    fixture trips, played by the coached player, to Home. It then syncs against `FakeApi`: one
    `settings_update`, one `tutorial_gift`.
  - A `sync-e2e` case (`test/backend/`) sends both operations to the dev stack and reads them back.
- **Kills:** `first_session_kill_test.dart` kills at each step (FR-051) with the store and the trip
  records on real SQLite.
- **Migration:** v3 → v4 by `make-migrations`' generated test, plus a data check (an existing v3
  wallet keeps its values; `player_state` starts empty and false).
- **Guards:**
  - the writers guard: `player_state`, `first_session`;
  - the coach's state-read guard (R14);
  - no Arabic in `lib/` (the name pool is in the ARB);
  - the route table test (two new routes);
  - the l10n placeholder rules.
- **Backend:** `test_name_pool.py` (R7), B04's scene tests (R6), and the content kit's validator
  cases (R5).
- **Coverage:** ≥ 80% for the app; the content kit and backend keep their gates.
- **The record count** in B04's tests becomes 61 plus the opening scene's records (one scene and its
  lines). The exact number is set when the sample changes.

## R23. Documents updated in this PR

- **The spec:**
  - FR-041: the trip's title may move to the pause card in the compact arrangement;
  - FR-046, FR-047 and the content assumption: R20;
  - FR-038 and FR-039, and an edge case: a pack with fewer than five tutorial trips (R3);
  - FR-006: the caption is the narrator line.
- **`docs/architecture-mobile.md`:**
  - §8: the compact profile and the end of the exception;
  - §9: the two new routes;
  - §12: the two new local operations;
  - §5: the `features/onboarding/` tree.
- **`docs/architecture-backend.md`** (content §): `Scene.plays` and the narrator convention.
- **`content/README.md` and B04's authoring notes:** `plays`, `narrator`.
- **`docs/delivery-plan.md`:**
  - Design sources: `FuelLesson` in M07's row;
  - step 7: HANDOFF §9.3 #3 resolved;
  - Progress, at merge.
- **`CLAUDE.md`:** the first-session store in the writers rule; the tutorial fixture.
- **`docs/owner-actions.md`** (at `/speckit-implement`): the M07 section (below).
- **`specs/008.5-m21-design-refresh/contracts/trip-layout.md`:** a pointer from "The exception" to the
  compact contract.

## Owner actions (for `docs/owner-actions.md`)

- **Before the fuel lesson is built:** draw `FuelLesson` from contracts/fuel-lesson.md on the Claude
  Design canvas, plus the five missing comic panels (R15). Then rebuild `docs/design/` with its
  tools (`export.py`, `boxes.py`, `build_assets.py`).
- **Before merge:**
  - approve the coach lines, the fuel lesson's lines, the name pool, the refused-name line and the
    default name;
  - approve the compact trip look from the 360×640 goldens;
  - play the first session on the Redmi Note 7 with the draft imported on the local stack
    (quickstart Part B).
- **After merge:**
  - the first-trip timing on the Galaxy A06 (SC-001);
  - a moderated playtest with five new players (SC-007);
  - add the opening scene and `plays` to the release draft on `content-core-r1`.

## Handed to later features

- **M08:**
  - the result screen's main action is `FirstSession.nextAfterResult` while `inFirstSession`;
  - Home starts the next trip through `/trip/<id>`, so the redirects apply;
  - the pre-trip card shows no boosters while `boostersLocked`;
  - Home keeps `NameReaskHost`.
- **M10:**
  - send `story_progress` for the scenes in `first_session`;
  - play scenes without `plays`, and add kinds to `ScenePlaysKind`;
  - reuse `ScenePlayer`'s panel art map and `PanelFallback` in `SceneViewer`.
- **M11:** no interstitial while `!tutorialDone`.
- **M14:**
  - the notification ask at step 6's hook;
  - the settings name edit with the name sheet.
- **M15:** report `tutorial_step` from `stepReached`.
- **Content (`content-core-r1`):** the opening scene, `plays` on `first_sight` (after `line_hay.03`) and
  on `moallem_verdict` (after `line_hay.20`), and narrator captions.
