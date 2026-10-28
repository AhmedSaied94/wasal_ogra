# Contract: Tests and CI

What proves each requirement, and where it runs. Spec FR-021, FR-022, SC-001–SC-007; research R5–R14.
Tests come first for the pure parts (`PanelTurns`, `panelTalkers`, the contract check), as
constitution XIII asks. The mobile CI job already runs `rive_native:setup` before `flutter test`, so
the `rive`-tagged tests below run in CI with the rest.

## Unit tests (no Rive, no widgets)

| Test | Checks |
| --- | --- |
| `test/features/onboarding/domain/panel_turns_test.dart` | the caption takes no turn; order; `leadIn`; each length is `perLetter × letters`, clamped to `[min, max]`; the pause; `at()` before, inside, between and after turns; `lastStarted`; the same speaker twice; a caption-only panel; letters count grapheme clusters, not code points (a line with shadda); the timings of the sample's six panels and the draft's three (research R5's table) |
| `test/core/art/panel_talkers_test.dart` | each of the four speakers turns on its Boolean alone; `null`, `narrator` and an unknown speaker turn all four off |
| `test/core/art/rive_contract_test.dart` | both contracts: `artboards` and `known` are disjoint; the scene contract names the six slugs, the 11 building blocks and the 4 export artboards; problems carry the asset's path |

## Widget tests (no Rive's library needed)

| Test | Checks |
| --- | --- |
| `test/core/art/panel_art_test.dart` (extended) | the order: animation, drawing, `PanelFallback`; `animate: false` draws M07's art; the three aliases draw the canonical drawing |
| `test/core/art/rive_art_view_test.dart` (extended) | `source: scenes` reads the scope's second file; `alignment` reaches `RiveWidget`; without a scenes file, a scenes view draws its fallback; every existing case unchanged |
| `test/features/onboarding/presentation/scene_turns_test.dart` (new; `scenePanelsProvider` overridden to animate every panel) | bubbles appear in turn (`shown` follows the schedule); for every spoken line of the sample's `opening` and `the_stand` and the fixture's `first_sight` (all 13 of SC-005), `PanelArt.talking` is the speaker for exactly the turn; within a turn the player doesn't rebuild (the same `ComicPanel` instance); «يلا» before the last turn shows every bubble and stays, and the next «يلا» moves on; «يلا» after the last turn has started moves on; «تخطّى» and back finish during a turn; a caption-only panel moves on at the first «يلا»; reduced motion: every bubble at once, `talking` null, `animate` false; reduced motion switched off mid-panel: the animation, every bubble, no turn; the read order holds every line from the panel's start; no sound over the scene, and one `selection` haptic per «يلا» or «تخطّى» tap (R10) |
| `test/features/onboarding/presentation/scene_player_test.dart` (M07's, unchanged) | passes as it is: `pumpDesignComponent` defaults `riveScenesProvider` to `RiveArt.none()`, so no panel animates, whether or not CI's Rive library could decode the file (FR-022) |
| `test/core/theme/components/nav_story_test.dart` (`ComicPanel`'s, extended) | `shown: null` is M07's panel; hidden bubbles keep their place and their semantics; a newly shown bubble pops; at most two bubbles |
| `test/features/trip/presentation/playtest_test.dart` (the debug panel's, extended) | both files' problems listed, each with its asset's path; «سليم» only when both are clean |
| `test/bootstrap/boot_progress_test.dart` (extended if needed) | step `art` completes when both files have loaded, and when either fails to |

## Rive tests (tag `rive`, the real files)

| Test | Checks |
| --- | --- |
| `test/core/art/rive_scenes_contract_test.dart` | the file loads with `Factory.flutter` under the 100 KB budget; each panel's size, machine and default view model with its four Booleans; the known artboards and nothing else; `checkRiveArt` passes every panel with no problem; loads from the bundle as boot does; a check that throws gives `RiveArt.none` |
| `test/core/art/rive_scenes_talk_test.dart` | every panel rendered at fixed times with each Boolean on and off: the speaker of every spoken line of the sample's `opening` and `the_stand` and the draft's `first_sight` (`test/fixtures/tutorial/first_sight.json`) changes pixels; a Boolean whose character isn't drawn changes none (the spec's "Who talks where" table); two runs give the same pixels; the frame 4.8 s on matches the first, apart from the characters' own shorter loops (a set tolerance) |
| `test/features/onboarding/rive_scene_goldens_test.dart` | one sheet per panel: its first frame beside its drawing; goldens in `test/features/onboarding/goldens/rive_scene_<slug>.png` |
| `test/features/onboarding/presentation/scene_turns_rive_test.dart` | the real file in `RiveArtScope`: an animated panel draws a `RiveWidget` with `Fit.cover` and `Alignment.bottomCenter`; its view model's Booleans follow the turns (read back from the bound instance) |
| `test/features/trip/rive_art_contract_test.dart` (008.5's) | passes on the owner's updated `wassal.riv` |
| `test/features/trip/rive_art_goldens_test.dart` (008.5's) | regenerated: only the six-characters sheet changes, by the usta (contracts/usta-look.md) |

## Goldens

- **New:** the six `rive_scene_<slug>.png` sheets (tag `rive`).
- **Changed, for the usta's look only:** the goldens listed in contracts/usta-look.md.
- **Unchanged:** M07's `Intro` goldens and every other scene golden. Without a scope the panels are
  drawings, and their drawings already show the panels' usta.
- Goldens are generated on Linux, and CI's run is the reference (`update_goldens: true`).

## Guards (`test/repo/`), unchanged and still passing

- No raw durations outside `core/theme/tokens/`: the turn timings are `SceneTurnTokens` constants,
  in that folder.
- No Arabic in `lib/`: no new string.
- Domain imports: `panel_turns.dart` imports `content_models` and `characters`, both allowed for
  `features/onboarding/domain/`.
- The design assets match `sync_assets.dart`'s output, including the new `usta.svg`.
- The design tokens match `tokens.json`, unless the rebuild changes it (then regenerate with
  `tool/design/gen_tokens.dart`).

## Integration and device runs

| Run | Where | Checks |
| --- | --- | --- |
| `integration_test/first_session_test.dart` | CI, headless (`-d flutter-tester`) | passes whether or not Rive can play there; with Rive it taps «يلا» twice on panels with turns |
| `integration_test/scene_perf_test.dart` + `tool/perf/scene_fps.sh` (new) | the Galaxy A06, profile, dev flavor (owner) | the opening and the سلمى scene with their turns: average ≥ 55 fps, no one-second window under 45, memory < 300 MB (SC-002) |
| `tool/perf/cold_start.sh` | the Galaxy A06 (owner) | Home within 3 s with both files (SC-003) |
| The first trip, timed by hand | the Redmi Note 7 before merge, the Galaxy A06 after (owner) | a fresh install, «يلا» tapped as soon as it shows, the suggested name accepted: the first trip starts within 20 s of opening the app (SC-003, M07 SC-001) |
| The phone check | the Redmi Note 7 and the Galaxy A06 (owner) | each panel animates, no Rive splash, the speaker talks in every turn (SC-001); scenes opened from the playtest «Onboarding» card |

## Coverage

≥ 80% for `apps/mobile` (`tool/check_coverage.dart --min 80`), as every feature. The pure schedule
and the mapping are fully covered by their unit tests.
