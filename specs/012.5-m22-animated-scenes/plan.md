# Implementation Plan: Animated Scenes (M22)

**Branch**: `012.5-m22-animated-scenes` | **Date**: 2026-10-28 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/012.5-m22-animated-scenes/spec.md`

## Summary

M22 plays M07's comic panels as Rive animations from a second file, `wassal_scenes.riv`. The
characters and the tuktuk move, and each line's speaker talks in turn while their bubble goes up.
The still drawings stay the fallback. It covers:

- **The second file** (R1, R2):
  - decoded in boot's `art` step beside `wassal.riv`, by the same loader, now given a
    `RiveContract`;
  - checked against a scene contract: six 358×540 panels, each with the machine `Panel` and the view
    model `Panel` with four Booleans. The file's building blocks and the export's own artboards are
    accepted and never drawn;
  - a failure falls back per panel, and the debug panel lists both files' problems (R13).
- **What a panel draws** (R3, R4):
  - `ScenePlayer` decides once whether a panel animates: the file passed for that panel, and reduced
    motion is off;
  - `PanelArt` draws the artboard through `RiveArtView`, which gains a source and an alignment, with
    `Fit.cover` at the bottom centre, as the drawing. The drawing is the fallback, then
    `PanelFallback`;
  - the release draft's three `ch1_*` slugs map to the sample's art.
- **Talking in turn** (R5–R10):
  - a pure `PanelTurns` schedule (60 ms a letter, 1.2–4 s, a 0.3 s pause, after the panel's 280 ms
    slide-in), driven by a frame-based clock per panel;
  - `ComicPanel` gains `shown`: hidden bubbles keep their place and their semantics, and each one
    that appears pops with the design's `BubblePop`;
  - `panelTalkers` sets the four Booleans, one at a time;
  - «يلا» before the last turn shows the rest, and the next one moves on (Clarifications Q1);
  - no sound (Q4). With a drawing, M07's behaviour stays exactly as it is.
- **The usta's look** (R12, Clarifications Q3):
  - the owner's updated `wassal.riv`, where only `look` 18 changed;
  - `docs/design/` rebuilt from the canvas, and the app's static `usta.svg` copied from it;
  - only the goldens that draw him change.
- **Tests** (R11, R14): the delivered file's own contract, who-talks-where and first-frame goldens
  (tag `rive`); the schedule and the mapping first; turns through a provider seam; and a
  frame-rate run on the Galaxy A06.

The release draft's بلية line already went to the usta in the `content-core-r1` worktree, so every
spoken line has its speaker drawn. Technical approach: [research.md](./research.md).

## Technical Context

**Language/Version**: Dart 3.13 with the FVM-pinned Flutter 3.47.7 (`.fvmrc`). Python 3.11+ only for
`docs/design/tools/` (the canvas rebuild).

**Primary Dependencies**:

- **Existing:**
  - `rive` 0.14.11 with `rive_native` (`Factory.flutter`), Riverpod 3 with its generator, `go_router`;
  - `flutter_svg` (the drawings), `characters` (grapheme clusters, direct since M07),
    `content_models` (the scene's lines).
- **None new.** No plugin, so no new interface.
- **Rejected:**
  - Lottie for the panels (the constitution locks Rive);
  - a second Rive runtime or `Factory.rive` (008.5 keeps `Factory.flutter`, which works in Linux
    `flutter test`).

**Storage**: none. No table, column, preference or schema change. The files are decoded once per
launch, and the turns live per panel (data-model.md).

**Testing**:

- `flutter_test`:
  - unit tests first for `PanelTurns`, `panelTalkers` and both contracts;
  - widget tests for the turns, through `scenePanelsProvider` overridden, without Rive's library;
  - `rive`-tagged tests on the real files: the contract, who talks where by pixel difference, the
    first-frame goldens, and the bound Booleans;
  - M07's scene tests and `Intro` goldens unchanged;
  - the usta's goldens regenerated and reviewed.
- An integration test for the scenes' frame rate on the A06. Coverage ≥ 80%
  (contracts/ci-checks.md).

**Target Platform**: Android (`minSdk 24`, `targetSdk 36`) and iOS 15.0 (Codemagic; no Podfile, no new
plugin), all three flavors. Linux for CI and goldens.

**Project Type**: A mobile-app feature in the `wassal` monorepo. It touches:

- `apps/mobile/lib/core/art/` (the second file, the contract, `RiveArtView`, `PanelArt`);
- `core/theme/components/story.dart` (`ComicPanel`, `BubblePop`);
- `features/onboarding/` (`PanelTurns`, `ScenePlayer`);
- boot and the app scope, and the trip's debug panel;
- the assets (`wassal.riv`, `wassal_scenes.riv`, `usta.svg`) and `docs/design/`.

No backend, content or engine change.

**Performance Goals**:

- A scene on the Galaxy A06: an average of at least 55 fps, no one-second window under 45 fps, and
  memory under 300 MB (SC-002, research R14).
- Cold start to Home under 3 s with both files (SC-003). The two decodes run side by side, and the
  second file is 49.6 KB.
- One panel's Rive instance at a time, plus the outgoing one during the 280 ms slide.
- The player rebuilds only when a turn starts or ends, not on every frame (R6).
- A new player still starts the first trip within 20 s of opening the app, timed by hand (SC-003,
  M07 SC-001).

**Constraints**:

- No rule, engine, economy, content or schema change (FR-020).
- Each panel falls back on its own, and nothing in the file can stop boot (FR-004).
- Under reduced motion, every panel is its drawing (FR-007).
- No raw durations outside `core/theme/tokens/`, no Arabic in `lib/`, no new string.
- Only `look` 18 changes in `wassal.riv`.
- `docs/design/` is rebuilt from the canvas, never hand-edited.

**Scale/Scope**:

- 1 new asset, 1 replaced asset, 1 static drawing re-synced.
- About 8 changed and 4 new `lib/` files; about 6 new and 8 extended test files (the two pump
  helpers included).
- 6 new golden sheets, plus the usta's changed goldens.
- 1 integration test and 1 perf script; 5 documents updated.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| # | Principle | Applies | How M22 satisfies it |
| --- | --- | --- | --- |
| I | Engine purity | No | No engine change. Scenes aren't trips. `PanelTurns` is app domain code with no Flutter import. |
| II | Integer money | No | No money anywhere in the feature. |
| III | Parity | No | No rule, parameter or fixture change. |
| IV | Server authority | No | No currency, purchase or entitlement path. |
| V | Offline-first | Yes | Both files ship in the app and are decoded at boot. Nothing waits for the network, and the first trip stays within 20 s (SC-003, M07 SC-001). |
| VI | Idempotency | No | No state-changing request. The scene flags are written once, by M07's unchanged paths (R9). |
| VII | Content, not code | Yes | The lines, speakers and panel slugs stay pack data. The three aliases map content slugs to the app's own art, as `PanelArt`'s drawing map already does (art ships in the app, M07 R15). No player text in code; no new string. |
| VIII | Tunable numbers | Yes | No new balancing number. The turn timings are presentation values, like the motion tokens, so they are named constants in `core/theme/tokens/` (`SceneTurnTokens`), not Remote Config keys (R5; spec "Defaults"). |
| IX | No ads in a trip | No | No ad call. |
| X | RTL and Arabic first | Yes | The panels' layout and bubbles are M07's, in RTL. The art is a picture, and the speakers stand where the drawings put them. Goldens run in RTL with both digit styles (M07's unchanged; the new Rive sheets have no text). |
| XI | Accessible minimums | Yes | At most two bubbles at once (FR-014). Bubble text and «يلا»/«تخطّى» keep M07's sizes. Reduced motion shows the still drawing, with no pop and no turns (FR-007, FR-017). Every line is in the read order from the start (FR-018). The bubbles' text contrast is unchanged: they are opaque over the art, the sun's glow included. |
| XII | No runtime LLM | No | — |
| XIII | Small, testable features | Yes | One spec folder (`012.5-…`, as the delivery plan's convention for M21/M22). Tests first for the schedule, the mapping and the contracts. The delivered file has its own `rive`-tagged tests. Goldens, an integration run, coverage ≥ 80%. |

**Locked stack.** Rive (`rive` 0.14, `Factory.flutter`) for the animation, with the static SVGs as
the fallback. Riverpod with its generator. No new plugin and no new interface.

**Security & privacy.** No security review is needed:

- no network call, no stored data, no personal data;
- no new input: the panels read only bundled assets and pack text the app already shows.

A malformed or hostile `.riv` can only fail to decode, which falls back (FR-004). The file is
reviewed and committed like any asset.

**Performance budgets.**

- The scenes' frame rate on the A06 is measured like the trip's (R14).
- The cold start is re-run with both files.
- Memory stays under the trip's 300 MB.

**CI gates.**

- The mobile analyze, format, test (with the `rive` tag, after `rive_native:setup`), golden and
  coverage jobs.
- The guards as they are.
- No backend, content-kit or OpenAPI change.

**Gate result (pre-research): PASS.** No principle is broken. VIII applies by its own scope: the turn
timings don't balance the game.

**Gate result (post-design): PASS.** The re-check after Phase 1 found:

- `panel_turns.dart` imports only what `features/onboarding/domain/` allows (`content_models`,
  `characters`);
- the timings sit in `core/theme/tokens/` as the duration guard requires;
- the read order holds every line, and the two-bubble limit holds;
- the scene flags still have one writer (M07's `_finish`);
- the only change to `wassal.riv` is the usta's look, which its contract test and goldens show.

## Project Structure

### Documentation (this feature)

```text
specs/012.5-m22-animated-scenes/
├── spec.md                  # the feature (with Clarifications 2026-10-28)
├── plan.md                  # this file
├── research.md              # Phase 0: R1–R16, hand-overs
├── data-model.md            # Phase 1: contracts, panels, turns, a panel's states
├── quickstart.md            # Phase 1: Part A automated, Part B on the phones, done when
├── contracts/
│   ├── rive-scenes.md       # the file, its contract, loading, the check, drawing, the debug panel
│   ├── scene-turns.md       # the schedule, the clock, «يلا», bubbles, Booleans, read order, motion
│   ├── usta-look.md         # the look, where it changes, the canvas rebuild, the goldens
│   └── ci-checks.md         # unit, widget, rive and golden tests; guards; device runs
├── checklists/requirements.md
└── tasks.md                 # Phase 2 (/speckit-tasks), not created here
```

### Source Code (repository root)

```text
apps/mobile/
├── assets/
│   ├── rive/
│   │   ├── wassal_scenes.riv                    # NEW (staged): the six panels
│   │   ├── wassal.riv                           # REPLACED: the owner's export, look 18 only
│   │   └── README.md                            # both files
│   └── illustrations/characters/usta.svg        # re-synced from docs/design
├── lib/
│   ├── bootstrap/
│   │   ├── startup.dart                         # step art waits for both files
│   │   └── app.dart                             # RiveArtScope(art:, scenes:)
│   ├── core/
│   │   ├── art/
│   │   │   ├── rive_art.dart                    # RiveContract; loadRiveArt/checkRiveArt take it; RiveArt.contract; RiveArtSource; RiveArtView source + alignment; file-name prefix on problems
│   │   │   ├── rive_scenes.dart                 # NEW: sceneContract, riveScenesProvider, scenePanelsProvider/ScenePanels
│   │   │   └── panel_art.dart                   # artFor aliases; animate, talking; panelTalkers
│   │   └── theme/
│   │       ├── components/story.dart            # ComicPanel.shown; hidden bubbles keep semantics; BubblePop on appear
│   │       ├── components/characters.dart       # BubblePop moved out (shared), SpeechBubble unchanged
│   │       └── tokens/scene_turn_tokens.dart    # NEW: SceneTurnTokens (leadIn, perLetter, min, max, pause)
│   └── features/
│       ├── onboarding/
│       │   ├── domain/panel_turns.dart          # NEW: TurnTimings, Turn, PanelTurns, TurnsAt
│       │   └── presentation/scene_player.dart   # animated or not; the turn clock; «يلا» reveal
│       └── trip/presentation/playtest/debug_panel.dart   # both files' problems
├── test/
│   ├── core/art/                                # rive_contract, panel_talkers (NEW); panel_art, rive_art_view (extended); rive_scenes_contract, rive_scenes_talk (NEW, rive)
│   ├── core/theme/components/nav_story_test.dart   # ComicPanel.shown
│   ├── features/onboarding/
│   │   ├── domain/panel_turns_test.dart         # NEW
│   │   ├── presentation/scene_turns_test.dart   # NEW
│   │   ├── presentation/scene_turns_rive_test.dart   # NEW (rive)
│   │   └── rive_scene_goldens_test.dart         # NEW (rive) + goldens/rive_scene_<slug>.png
│   ├── features/trip/presentation/playtest_test.dart   # both files' problems
│   ├── fixtures/tutorial/first_sight.json       # NEW: the draft's سلمى scene (README updated)
│   └── …                                        # the usta's goldens, regenerated (contracts/usta-look.md)
├── integration_test/scene_perf_test.dart        # NEW
└── tool/perf/scene_fps.sh                       # NEW
docs/design/                                     # rebuilt from the canvas (usta); HANDOFF.md and README.md already updated
docs/architecture-mobile.md                      # §5 tree, §8 Characters and Art
docs/delivery-plan.md                            # Progress, at merge
docs/owner-actions.md                            # 012.5 section, at /speckit-implement
CLAUDE.md                                        # status M22; Rive: two files; scene goldens command
```

**Structure decision.**

- **The second file and the panels' art live in `core/art/`**, beside the first file. Loading,
  checking and drawing are shared art concerns, and the album (M10) will draw panels too.
- **The turns live in `features/onboarding/`**: the schedule in `domain/`, pure, and the clock in
  `ScenePlayer`, which owns the panels' order and «يلا». If M10's viewer needs the turns, the
  schedule moves to `core/` then, with its tests.
- **`BubblePop` moves to a shared spot in `core/theme/components/`** because both `SpeechBubble` and
  `ComicPanel` use it. It moves unchanged.
- **No new package.**

## Complexity Tracking

No deviations. Constitution VIII is satisfied by scope: the turn timings are presentation values, not
balancing numbers (research R5), like every motion token since 008.5.
