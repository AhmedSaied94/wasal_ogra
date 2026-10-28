# Data Model: Animated Scenes (M22)

Phase 1 of [plan.md](./plan.md). This feature stores nothing: no table, no column, no preference, and
no content-schema change. Everything here lives in memory for a launch (the files) or a panel (the
turns). The contracts spell out each value's behaviour: [rive-scenes.md](./contracts/rive-scenes.md)
and [scene-turns.md](./contracts/scene-turns.md).

## The art files (`lib/core/art/`)

### `RiveContract` (new)

What a Rive file must hold for the app to draw it. The first file's constants become one instance.

| Field | Type | Meaning |
| --- | --- | --- |
| `asset` | `String` | the bundled asset path |
| `artboards` | `Map<String, ArtboardSpec>` | the artboards the app draws, each with its size, machine, view model and properties (008.5's `ArtboardSpec`, unchanged) |
| `known` | `Set<String>` | artboards the file may hold that the app never draws: the export's own, and nested building blocks |

- `riveCharacterContract`: `assets/rive/wassal.riv`; today's `riveContract` and
  `riveExportArtboards`, unchanged.
- `sceneContract`: `assets/rive/wassal_scenes.riv`, with six panel specs and 15 known artboards
  (contracts/rive-scenes.md "The contract").
- **Rule:** `artboards` and `known` are disjoint (a test checks both contracts).

### `RiveArt` (changed)

008.5's result of decoding and checking a file.

| Field | Type | Change |
| --- | --- | --- |
| `file` | `rive.File?` | unchanged |
| `usable` | `Set<String>` | unchanged: the artboards that passed |
| `problems` | `List<String>` | each problem now starts with the asset's path, a colon and a space (R2) |
| `contract` | `RiveContract?` | **new**: what it was checked against, so `RiveArtView` reads the spec from the file it draws. `null` means the characters file's contract, which keeps 008.5's hand-built `const RiveArt(…)` and `RiveArt.none(…)` in tests valid. |

`has(artboard)` is unchanged: a file, and the artboard passed.

`checkRiveArt(file, [RiveContract? contract])` and `loadRiveArt({RiveContract? contract, String?
asset, AssetBundle? bundle, RiveArt Function(rive.File) check})` default to the characters file's
contract when it is `null`. `riveContract` isn't `const`, so it can't be a default value. `asset`
overrides the contract's asset, as `boot_progress_test` uses it, and `check` keeps its one argument.
So every 008.5 call compiles unchanged.

### `RiveArtSource` (new enum)

`characters` (the first file, the default everywhere) or `scenes`. It picks which file
`RiveArtView` reads from `RiveArtScope`.

### `RiveArtScope` (changed)

Carries both files: `art` (the characters, as today) and `scenes`. `bootstrap/app.dart` fills both
from `riveArtProvider` and `riveScenesProvider`. Tests and goldens that build no scope get every
fallback, as today.

## Panels (`lib/core/art/panel_art.dart`)

### Art slug

The slug a panel's `art` names (content), mapped through `PanelArt.artFor`:

| Content slug | Art slug |
| --- | --- |
| `ch1_stand_morning` | `stand_morning` |
| `ch1_salma_asks` | `salma_waiting` |
| `ch1_usta_dreams` | `usta_decides` |
| any other | itself |

The art slug names both the drawing (`PanelArt.assetFor`) and the artboard.

### `PanelArt` (changed)

| Parameter | Type | Meaning |
| --- | --- | --- |
| `slug`, `speakers`, `current` | as M07 | unchanged |
| `animate` | `bool`, default `false` | **new**: draw the artboard (with the drawing as its fallback) |
| `talking` | `String?` | **new**: the speaker whose Boolean is on, or none |

### `panelTalkers(String? talking)` (new, pure)

`→ Map<String, bool>` over `moallem`, `usta`, `belya` and `salma`: the one equal to `talking` is
true, the others false; an unknown speaker or `null` gives four falses.

### `ScenePanels` (new, application)

`scenePanelsProvider` → `ScenePanels`, with `bool animates(String artSlug)`. It is true when the
scenes file loaded and the artboard passed its check. Tests override it.

## Turns (`lib/features/onboarding/domain/panel_turns.dart`, pure Dart)

### `TurnTimings`

| Field | Type | The scenes' value (`SceneTurnTokens`) |
| --- | --- | --- |
| `leadIn` | `Duration` | `.leadIn` = `MotionTokens.sheetIn` (280 ms) |
| `perLetter` | `Duration` | `.perLetter`, 60 ms |
| `min` | `Duration` | `.min`, 1200 ms |
| `max` | `Duration` | `.max`, 4000 ms |
| `pause` | `Duration` | `.pause`, 300 ms |

**Rules:** `min ≤ max`, every value ≥ 0. The scenes' values are named constants in
`core/theme/tokens/scene_turn_tokens.dart` (`SceneTurnTokens`). `ScenePlayer` builds its
`TurnTimings` from them, a `final` in `scene_player.dart`. The domain class takes them as arguments,
so it imports no Flutter.

### `Turn`

| Field | Type | Meaning |
| --- | --- | --- |
| `index` | `int` | the line's position among the panel's spoken lines (0-based) |
| `speaker` | `String` | the line's `speaker` |
| `start`, `end` | `Duration` | from the panel's arrival |

### `PanelTurns`

Built from a panel's lines and a `TurnTimings`:

- `turns`: one `Turn` per line whose speaker isn't `narrator`, in order;
- `end`: the last turn's end, or zero when there are none;
- `at(Duration elapsed)` → `TurnsAt`.

**Rules:**

- `turns[0].start == leadIn`, and `turns[i + 1].start == turns[i].end + pause`.
- `turn.end − turn.start == clamp(perLetter × letters, min, max)`, where letters are the line's
  non-white-space grapheme clusters.
- No two turns overlap, and the starts strictly increase.

### `TurnsAt`

| Field | Type | Meaning |
| --- | --- | --- |
| `shown` | `int` | the number of turns that have started (0 … `turns.length`) |
| `talking` | `String?` | the speaker of the turn in progress; `null` before the first, in a pause, and after the last |
| `lastStarted` | `bool` | whether the last turn has started; it decides what «يلا» does (FR-016) |

For a panel with no spoken lines, `at` gives `shown 0`, `talking null` and `lastStarted true`.

Two `TurnsAt` are equal when their three fields are, so `ScenePlayer` rebuilds only when one
changes: at each turn's start and end.

## A panel's states in the player

`ScenePlayer` holds, for the panel on screen, its mode and, when animated, its turn clock.

```text
mode: still ──(reduced motion off, file ready)──▶ animated, done
      animated ──(reduced motion on)──▶ still

animated:
  arriving ─(leadIn)─▶ turn 1 ─▶ pause ─▶ turn 2 … ─▶ done
      │                  │                  │
      └────────── «يلا» before the last turn has started ──────────▶ done
done ─(«يلا»)─▶ next panel, or the scene finishes
any ─(«تخطّى» or back)─▶ the scene finishes
```

| State | Bubbles | Talking | «يلا» |
| --- | --- | --- | --- |
| still | every bubble | nobody | moves on (M07) |
| arriving | none yet (laid out, invisible) | nobody | shows every bubble, then the panel is done |
| turn *i* | 1 … *i* | the speaker of turn *i* | shows every bubble while turn *i* isn't the last; moves on once it is |
| pause | 1 … *i* | nobody | shows every bubble, then the panel is done |
| done | every bubble (at most two) | nobody | moves on (M07) |

- A panel that starts still is marked done, so turning reduced motion off shows its animation with
  every bubble and no turn (spec Edge Cases).
- The clock is the panel's own and goes when the panel goes, so a new panel always starts at
  "arriving".
