# Implementation Plan: Home, Pre-trip Card and Result Screen (M08)

**Branch**: `013-m08-home-result` | **Date**: 2026-10-27, updated 2026-10-28 after M07 and M22 merged |
**Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/013-m08-home-result/spec.md`

## Summary

M08 replaces the placeholders a player passes through on every trip with the design's screens:

- **Home** (`C-Home`, `HomeStates`):
  - the header, with the fuel countdown on trusted time;
  - the street scene with the next trip's vehicle, its roof sign and its caller;
  - the line card, «يلا نطلع!» and the savings card;
  - the out-of-fuel, offline, maintenance and early-chapter states;
  - empty slots for the daily row and the morning piggy (R3, R4, R11–R13).
- **The next trip** (Clarifications Q1): derived from a new phone-side mirror of the server's unlock
  rules (B03 R6), so Home never offers a trip the server would refuse as `not_unlocked` (R2, R3).
- **The savings target:** the chapter goal before the apartment opens, the next apartment piece
  after. When the apartment opens is read from the pack (the first `complete_room` chapter), in one
  function M10 can change (R4).
- **The pre-trip card** (`PreTrip`), as a sheet:
  - stop prices in drop-off order;
  - rule lines;
  - the «جديد» card from a met set derived from progress;
  - star goals;
  - booster counts with an in-place buy through a confirmation dialog;
  - the story chip and condition;
  - «اطلع» to `/trip/<id>`.

  The «في الجديد بس» setting is a device preference, with a row on Settings (R5–R7).
- **The result screen** (`Result`):
  - the trip hands over a `ResultArgs`: the result, the start id, the replay record, the best stars
    and the balance before;
  - the screen shows the result's own figures: stars with conditions, breakdown, the mistakes card
    with faces and wording, the pay, and the apartment bar moving from the old balance to the new;
  - the quote comes from a deterministic replay of the record, in an isolate;
  - a first three stars plays the celebration (R14, R15).
- **The share image** (`ShareCard`): rendered off screen at 1080×1080 and shared through a new
  `ShareGateway` over `share_plus` (R16).
- **M07, merged, read directly** (R8): the first session's next trip, no card for tutorial trips,
  the fuel lesson in place of the out-of-fuel state, M07's «كمّل» as the result's main action, the
  hidden boosters, and the driver's name. M08 adds two small members to M07's `FirstSession`.
- **Arrival at Home** (Clarifications Q4 and 2026-10-28, R9): one due item per arrival, in a fixed
  order. M07's `/home` scene redirect and `NameReaskHost` become its first two items; the first
  notification ask stays in M07's after-scene step.
- **Seams,** so later features plug in without editing these screens (R10):
  - **M11:** the between-trips checkpoint, the ×2 slot and the piggy;
  - **M13:** the daily row and the task banner;
  - **M10:** the story scene hooks.
- **Internal builds** keep the trip list and the sync card behind a debug button on Home (R21).
- **No rule, engine, economy, schema or database change.** «عيد المشوار» stays M02's direct restart
  (Clarifications Q2, R17). The أبو سمّاعة sentence says to call him twice (Clarifications Q3).

Technical decisions and their rationale: [research.md](./research.md).

## Technical Context

**Language/Version**: Dart 3.13 with the FVM-pinned Flutter 3.47.7 (`.fvmrc`).

**Primary Dependencies**:

- **New direct:** `share_plus`, the plugin mobile §2 and §16 already name. It sits behind
  `ShareGateway`. The version must ship its iOS plugin as a Swift Package, since the iOS build has
  no Podfile (R16).
- **Existing:** Riverpod 3 with its generator, `go_router`, `flutter_svg`, `rive` 0.14 (`Vehicle`,
  `Person`, `Stars`, `Confetti` artboards), `content_models`, `trip_engine` (`TripEngine.start`, commands,
  `PassengerSpeaks`, `ReplayRecord`).

**Storage**:

- **No database change** (the schema version stays).
- **One device preference:** `pref.pre_trip_card`.
- **Memory only:** the last finished trip this run, and the arrival queue's open flag.

**Testing**:

- `flutter_test` with fakes and in-memory SQLite, tests first for every pure function:
  - the unlock rules, ported case by case from `test_unlocks.py`;
  - the next trip, swept over packs;
  - the savings target, the met set, the briefing, the card mode;
  - the summary and the quote;
  - the arrival queue and M07's two arrival items;
  - M07's `FirstSession` additions.
- **Widget tests** for every state and transition; the countdown against a fake trusted clock.
- **The result against every finished parity fixture.**
- **Design checks** for the five artboards (samples, goldens in both digit styles, layout tests).
- **Accessibility sizes** at 360×640, 360×800 and 390×844, text scale 1.0 and 1.3.
- **An offline integration test** of Home → card → trip → result → next card → Home, headless
  (`-d flutter-tester`) like M07's, and M07's first-session test extended past trip 5 into Home and
  a card.
- Coverage ≥ 80% (R22).

**Target Platform**:

- **Android:** `minSdk 24`, `targetSdk 36`, all three flavors.
- **iOS 15.0:** on Codemagic; the one new plugin is a Swift Package.
- **Linux:** CI and goldens.

**Project Type**: A mobile app feature in the `wassal` monorepo, all under `apps/mobile/`:

- new `lib/features/{home,pre_trip,result}/` and `lib/core/progress/domain/`;
- a new `PassengerAvatar` component, and `BottomNav` gains disabled tabs;
- small changes to the router, the trip's exit (`ResultArgs`), Settings and the app builder (the
  arrival queue);
- changes to M07's merged code: `FirstSession.nextTutorialTrip` and a public `fuelLessonDue`; its
  scene redirect on `/home` and `NameReaskHost` become two arrival items (R8, R9);
- `StationTag` moves from the trip's `patches_layer.dart` into `core/theme/components/` (R25);
- `lib/core/platform/share_gateway.dart`.

**Performance Goals**:

- Home on screen and current within 1 s of leaving a result or switching tabs. Cold start to Home
  stays under 3 s (SC-002): Home's derivations are O(trips in the pack), run once per new view.
- The quote's replay stays under 150 ms on CI for the longest-trip stress fixture. It runs in
  `Isolate.run`, and the screen never waits for it.
- The share sheet within 1 s of the tap (SC-010).
- The countdown rebuilds only its own text, once a second.

**Constraints**:

- Offline-first: everything works with no network except the «محتاج نت» items. BONAT booster buys
  are optimistic.
- Integer money; formatting only at the presentation edge.
- No text in a canvas: the scene's sign, call and bubbles are Flutter widgets.
- Every string in `app_ar.arb`; every style value from the tokens.
- No ad SDK and no ad call. The checkpoint is an empty interface, never after «اطلع».
- Game state stays out of the preference store: the card setting is a device preference; the last
  finished trip is memory, and derived after a restart.
- No change to M02's restart, the engine, M05's operations or M06's sync.
- Every start goes through `/trip/<id>`, so M07's redirects apply.

**Scale/Scope**:

- 5 artboards; 3 feature folders and 1 core domain.
- About 45 new `lib/` files and 40 test files.
- About 140 strings.
- 1 new plugin, 1 new component, 1 changed component, 1 moved component.
- 0 tables, 0 operations, 0 routes.
- 3 docs updated (product spec, delivery plan, architecture-mobile), plus `CLAUDE.md` by hand.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**Before Phase 0:** PASS. Nothing in the spec asks for an exception. Principles I, II, III, IV and VI
allow none, and none is needed.

**After Phase 1 design:** PASS, as below.

| Principle | How M08 satisfies it |
| --- | --- |
| I. Engine purity | The UI computes no rule. Stars, flags, money, mistakes and earnings are shown as the `TripResult` holds them (FR-036). The quote is found by replaying the record through the engine's public API (`start`, `apply`, `stepTo`), which is driving the engine, not re-implementing it (R14). The unlock rules aren't trip rules: they mirror the server's progression rules (B03 R6), and their domain imports only `content_models`. New `domain/` folders are added to the imports guard. |
| II. Integer money | Fares, tips, over-paid change and mistakes are integer piasters; JENEHAT, BONAT, prices and fuel are integers. Formatting goes through `NumberFormatter` at the edge. The only arithmetic is the bar's before and after balances, both integers read from the economy. The integer-money guard covers the new folders. |
| III. Parity | No rule, scoring, parameter or PRNG change. Parity fixtures are untouched. The result screen is tested against every finished fixture (SC-004). |
| IV. Server authority | No value decided locally beyond what M05 allows: one BONAT spend (`buy`, booster) through `EconomyService`, optimistic up to the local balance, rolled back by M06 on refusal. No BONAT ↔ JENEHAT path. Unlock order is checked before asking (M05 hand-over), and the server still decides. |
| V. Offline-first | Home, the card, a trip, the result and sharing work offline. The shop tab, the BONAT pill's link, the daily challenge and the piggy show «محتاج نت» and never block play. Maintenance degrades nothing. |
| VI. Idempotency and time | The booster buy holds one `TxnId` per intent (a double tap buys once). Countdowns use `TrustedClock`; a device clock change has no effect (SC-003). |
| VII. Content, not code | Prices come from the catalog; names, stations, goals' subjects and speech from the pack. Player text is in ARB. The new card's sentences and the mistake wordings are app strings, because they describe engine rules, not content (spec Assumptions; R5, R15). |
| VIII. Tunables | No new balancing number. The card's default reads the existing `pre_trip_card_mode`. UI motion values (the barker's re-pop, count-up, bar fill) are design constants in `design_extras.dart`, not balancing. When the apartment opens is the pack's structure (R4), not a constant. |
| IX. No ads in a trip | No ad SDK or call. `BetweenTripsCheckpoint` runs only before the card or a direct start, never after «اطلع» or during a trip; M11 fills it. `no_ads_in_trip_test` unchanged. |
| X. RTL and Arabic first | Every screen is RTL; goldens in both digit styles for all five artboards; the share image follows the digit setting. |
| XI. Accessible minimums | 44×44 targets (the decline link's hit area included), 12 pt text, at 1.0 and 1.3 from 360×640 (Home scrolls below its minimum). Stations by colour and letter (أ ب ج د). Labels as the artboards, plus HANDOFF's missing ones. The fuel label isn't re-announced every second. Reduced motion stops pops, bursts, count-ups and idle loops. |
| XII. No runtime LLM | None. The quote is picked deterministically from the trip as played. |
| XIII. Small, testable | One spec folder; tests first for the pure domain; widget, golden, layout, a11y and integration tests; coverage ≥ 80%. |
| Platform constraints | Riverpod with its generator, `go_router`, drift untouched. The one new plugin sits behind `ShareGateway` and is a Swift Package on iOS (no Podfile). No HTTP. |

## Project Structure

### Documentation (this feature)

```text
specs/013-m08-home-result/
├── spec.md
├── plan.md              # This file
├── research.md          # R1–R26
├── data-model.md        # derived values, the one preference, state diagrams
├── quickstart.md        # validation guide
├── contracts/
│   ├── progress-rules.md   # the phone's mirror of B03 R6
│   ├── home.md             # Home, its states, startNextTrip, the arrival queue
│   ├── pre-trip-card.md    # the briefing, the card mode, the booster buy
│   ├── result.md           # ResultArgs, the screen, the quote, sharing
│   └── seams.md            # every plug-in point for M07, M09–M15
├── checklists/requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
apps/mobile/
├── lib/
│   ├── bootstrap/app.dart                          # + HomeArrivalQueue after ContentLifecycle
│   ├── core/
│   │   ├── progress/domain/                        # NEW: unlocks.dart, player_progress.dart
│   │   ├── platform/share_gateway.dart             # NEW: ShareGateway + SharePlusGateway
│   │   ├── routing/router.dart                     # real Home, card and result builders; − the /home scene
│   │   │                                           #   redirect and the NameReaskHost wrapper (R9)
│   │   ├── routing/shell_scaffold.dart             # shop tab disabled offline
│   │   ├── theme/components/avatars.dart           # NEW: PassengerAvatar
│   │   ├── theme/components/station_tag.dart       # MOVED: StationTag, from the trip's patches_layer.dart
│   │   ├── theme/components/nav.dart               # BottomNav.disabled
│   │   └── theme/tokens/design_extras.dart         # barkerRepop, payCountUp, aptBarFill, starLabelStagger
│   ├── features/
│   │   ├── home/{domain,application,presentation}/        # NEW (contracts/home.md)
│   │   ├── pre_trip/{domain,application,presentation}/    # NEW (contracts/pre-trip-card.md)
│   │   ├── result/{domain,application,presentation}/      # NEW (contracts/result.md)
│   │   ├── onboarding/                             # M07, merged
│   │   │   ├── domain/first_session.dart           # + nextTutorialTrip, fuelLessonDue public (R8)
│   │   │   └── presentation/
│   │   │       ├── arrival_items.dart              # NEW: DueSceneArrival, NameSheetArrival (R9)
│   │   │       └── name_reask_host.dart            # DELETED (its logic moves to NameSheetArrival)
│   │   ├── settings/settings_screen.dart           # + the card setting row
│   │   └── trip/
│   │       ├── application/trip_phase.dart         # ExitToResult(tripId, ResultArgs)
│   │       ├── application/trip_controller.dart    # builds ResultArgs on finish
│   │       ├── domain/looks.dart                   # + feminine flag
│   │       ├── presentation/trip_screen.dart       # passes ResultArgs as extra
│   │       └── presentation/playtest/result_summary.dart   # DELETED
│   └── l10n/app_ar.arb                             # ~140 keys (R18)
├── test/
│   ├── core/progress/                              # unlocks (ported), sample sweep
│   ├── features/{home,pre_trip,result}/            # unit + widget
│   ├── features/onboarding/                        # first_session_test (+2 members), arrival_items_test
│   ├── features/settings/                          # card setting row
│   ├── a11y/                                       # Home, card, result sizes
│   ├── design/samples/{c_home,home_states,pre_trip,result,share_card}.dart
│   ├── design/*_layout_test.dart
│   ├── goldens/design/*_goldens_test.dart
│   └── repo/domain_imports_test.dart               # + the new domain folders
├── integration_test/home_loop_test.dart            # NEW, headless
├── integration_test/first_session_test.dart       # extended past trip 5
└── pubspec.yaml                                    # + share_plus
docs/product-spec.md                                # أبو سمّاعة's row (Q3)
docs/delivery-plan.md                               # §9.3 #4 settled; progress tick on merge
docs/architecture-mobile.md                         # §2, §6 (ShareGateway), §13 (unlocks on the phone)
docs/owner-actions.md                               # M08's section
```

**Structure Decision**: The mobile feature-first layout of mobile §5, with `domain/` (pure),
`application/` (Riverpod) and `presentation/` per feature. The progression rules go in
`core/progress/domain/` because M09 and M10 need them too.

M07 already moved `CharacterAvatar` and `SpeechBubble` into `core/theme/components/characters.dart`,
and M08 imports them from there. M08 moves `StationTag` next to them, because the card's prices use
it too (R25).

## Complexity Tracking

No constitution deviation: the table is empty.

Three decisions depart from the design or the ux-spec rather than the constitution. They are listed
for the PR description and the owner's review (README override 3; research R24):

- the card's booster buy asks for confirmation instead of the 3-second undo, until M12 builds the
  undo flow (R7);
- the fuel pill's screen-reader label is minutes only (R11);
- the goal title uses the vehicle's full content name (R4).

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |

## What changes in M07's merged code

M07 merged before M08, so M08 wires to it directly (research R8, R9). M22 changes nothing here: it
animates the scenes M07 plays.

| Area | Change in this feature |
| --- | --- |
| First session | `FirstSession` gains `nextTutorialTrip`; `_fuelLessonDue` becomes the public `fuelLessonDue`; `nextAfterResult` is rewritten on top of `nextTutorialTrip` with the same results. Tests in M07's `first_session_test.dart`. |
| Result | M02's `ResultSummary` placeholder goes; the real result places M07's `FirstSessionContinue` («كمّل», key `first-session-continue`) where «مشوار تاني» goes whenever it shows. |
| Arrival | The `/home` row of the router's redirect and the `NameReaskHost` wrapper go. `DueSceneArrival` and `NameSheetArrival` replace them (contracts/seams.md). This departs from M07's hand-over, which kept `NameReaskHost`; the PR description says why (Clarifications 2026-10-28). |
| Name | Home reads `driverNameProvider`; no new key. |
| Tests | M07's `integration_test/first_session_test.dart` keeps passing over the real screens and is extended past trip 5. First-session states use `test/helpers/tutorial_content.dart`. |

The step-7 "done when" integration test (onboarding through the first 5 trips) is that extended
test.

## Owner approvals and actions

**Approvals** (before merge):

1. The strings drafted in research R18:
   - the 19 «جديد» names and sentences;
   - the goal titles;
   - the mistake lines and the three summary families;
   - the barker's call;
   - the rule line for discounts other than 50%;
   - the share caption.
2. The departures listed under Complexity Tracking (R7, R11, R4).
3. The expected golden differences (R20):
   - the barker, riders and painted street;
   - the event icons on the «جديد» card, which reuse existing glyphs. Proper event art is an optional
     design request.

**Actions:**

- **Before merge:**
  1. Run Codemagic's `ios-dev-unsigned` with `share_plus` and confirm there is no Podfile and the
     share sheet opens on a sideloaded device (quickstart §8).
  2. Review the five artboards' side-by-side images (quickstart §4).
- **After merge:**
  1. Do the device pass of quickstart §7 on the Redmi Note 7, or the Galaxy A06 when available.
     It covers SC-002, SC-003 and SC-010.
  2. Run the playtest for SC-008 and SC-009: 10 players. Do 8 of 10 know which star they missed and
     why from the result alone? Do 8 of 10 who meet a new type know what it does from the card?

`/speckit-implement` adds these to `docs/owner-actions.md`, each with its task ID.

## Agent context

The template's agent-context update script was not run. `CLAUDE.md` is maintained by hand at
implement time (research R23): the new domain folders in the guards line, `ShareGateway`, and
`pref.pre_trip_card`.
