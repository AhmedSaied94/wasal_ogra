# Contract: Talking in Turn

How an animated panel plays its lines one at a time, with the speaker talking. Spec FR-011–FR-019;
research R5–R10. It changes M07's `ScenePlayer` and `ComicPanel`
([scenes.md](../../012-m07-onboarding/contracts/scenes.md) "The player"), and only for panels that
animate.

## When a panel has turns

`ScenePlayer` decides once per panel, on each build:

```text
animated = ref.watch(scenePanelsProvider).animates(PanelArt.artFor(panel.art))
           && !MediaQuery.disableAnimationsOf(context)
```

| `animated` | Art | Bubbles | «يلا» |
| --- | --- | --- | --- |
| true | `PanelArt(animate: true, talking: …)` | in turns | shows the rest, then moves on (below) |
| false | `PanelArt` as M07 | all at once, as M07 | moves on, as M07 |

A panel that first shows as a drawing is marked done. If `animated` later turns true (reduced motion
switched off), it shows the animation with every bubble and no turn.

## The schedule (`PanelTurns`, `features/onboarding/domain/panel_turns.dart`)

Pure Dart: `content_models`' `PanelLine`s in, `Duration`s out. It may import `content_models` and
`characters`, nothing from Flutter (the domain-folder guard lists both).

```text
PanelTurns(List<PanelLine> lines, TurnTimings timings)
  turns        // spoken lines only (speaker != 'narrator'), in order
  end          // last turn's end; Duration.zero with no turns
  at(elapsed)  // TurnsAt(shown, talking, lastStarted)
```

- `letters(text)`: grapheme clusters of `text` that aren't white space.
- A turn lasts `clamp(perLetter × letters, min, max)`.
- The first turn starts at `leadIn`, and each later one `pause` after the previous ends.
- `at(t)`:
  - `shown` is the number of turns with `start ≤ t`;
  - `talking` is the speaker of the turn with `start ≤ t < end`, else `null`;
  - `lastStarted` is `t ≥ turns.last.start` (true when there are no turns).
- Two `TurnsAt` are equal when their three fields are.
- `ScenePlayer` builds its `TurnTimings` from `SceneTurnTokens`
  (`core/theme/tokens/scene_turn_tokens.dart`):
  - `leadIn` = `MotionTokens.sheetIn` (280 ms);
  - `perLetter` 60 ms;
  - `min` 1200 ms;
  - `max` 4000 ms;
  - `pause` 300 ms.

  The domain class takes them as arguments and imports no tokens.

## The clock (`ScenePlayer`)

- One `AnimationController` per animated panel, created when the panel shows, with `duration:
  turns.end` and `forward()` from zero. It is disposed when the panel changes, the scene finishes or
  the player is removed.
- On each tick, a listener computes `at(controller.lastElapsedDuration ?? Duration.zero)`, or
  `at(turns.end)` once the controller has completed: its last tick clears `lastElapsedDuration`
  before it notifies, which would read as the panel's start (found on the Redmi, 2026-10-28). Only
  when it differs from the last `TurnsAt` does the player call `setState`, and the new value goes to:
  - `ComicPanel(shown: at.shown)`;
  - `PanelArt(talking: at.talking)`.

  A panel of *n* turns builds at most 2*n* + 1 times: its first build, then each turn's start and
  end. No `AnimatedBuilder` wraps the panel.
- A panel with no turns (caption only) gets no controller. It is done at once.
- The controller only drives the turns. The Rive machine plays on its own ticker, through
  `RiveWidget`.

## «يلا», «تخطّى», back

| When | «يلا» does |
| --- | --- |
| animated, `!at.lastStarted` | ends the turns: the controller jumps to its end, every bubble shows (at most two), nobody talks, the panel stays |
| animated, `at.lastStarted`, or done | M07's `_next`: the next panel, or `_finish` on the last |
| not animated | M07's `_next` |

- «تخطّى» and back: M07's `_finish`, whatever the turn. The controller and the Rive instance go with
  the player.
- «يلا» keeps its label, its look and its press feedback: `Pressable`'s tick (`Haptics.selection`,
  silent with the vibration setting off), on the reveal tap too (FR-016).

## Bubbles (`ComicPanel`, `core/theme/components/story.dart`)

- New parameter `shown` (`int?`; `null` means all lines, M07's behaviour), so every existing call and
  golden is unchanged.
- Every line's bubble is laid out from the start, in the same column as M07's, so a bubble appearing
  moves nothing.
- A bubble at index ≥ `shown` is invisible: `Opacity(opacity: 0, alwaysIncludeSemantics: true)`. It
  takes no touch and stays in the semantics tree.
- A bubble that becomes visible is wrapped in `BubblePop` (moved from `characters.dart` to a shared
  place in `core/theme/components/`, unchanged). It grows from 0.6 at its bottom over
  `MotionTokens.bubblePop`, and under reduced motion it appears at once.
- At most two bubbles show: with more than two lines, only the last two of the shown ones are seen.
  An older one keeps its place, unseen and untouchable, and stays in the semantics tree (FR-018).
  Without turns (`shown: null`) every bubble shows, as M07 drew them (FR-017). Today's scenes never
  reach it.

## The talking Booleans

- `panelTalkers(talking)` (data-model.md) gives the four values. `PanelArt`'s `bind` sets all four
  on every build.
- The speaker label in the bubble is M07's: the player's name for `usta`, `sceneSpeaker` for the
  others. The Boolean is always the speaker id (`usta`), never the name.

## Read order (FR-018)

Unchanged from M07: the title, the caption, each speaker and line, «اللوحة {n} من {total}», «يلا»,
then «تخطّى». Every line is in it from the panel's start, because hidden bubbles keep their semantics.
No live announcement is added when a bubble appears: the reader already has the line.

## Motion

| What | Value |
| --- | --- |
| Panel change | M07's: a slide and fade within `sheetIn`; under reduced motion a 150 ms fade |
| First turn | after `leadIn` = `sheetIn`, once the panel has landed |
| A bubble appearing | `BubblePop` (`bubblePop`, 180 ms, `EaseOutBack(1.4)`) |
| The mouth | the file's `talk` loop (0.5 s) while the Boolean is on, `talk_off` (0.1 s) when it goes off |

Nothing new is added under reduced motion: a panel never animates then, so it never has turns.

## Sound

No sound. Turns, the reveal and the panel changes call nothing in `core/audio_haptics/` (FR-012,
research R10). The only call during a scene is the press tick of «يلا» and «تخطّى», which every
`Pressable` gives (FR-016).

## Edge cases

| Case | Behaviour |
| --- | --- |
| A speaker with no Boolean (`bride_father`, …) | a turn and a bubble; all four Booleans false |
| A speaker not drawn in the panel | a turn and a bubble; their Boolean is on, and the file ignores it |
| The same speaker twice | two turns with the pause between; the Boolean goes off for the pause |
| Background mid-turn | frames stop, and so does the clock; on return it catches up to the frame time |
| Text scale 1.3 | bubbles wrap as in M07; the layout doesn't move when one appears |
| Short screens | the panel is shorter (M07); the art is `Fit.cover`, bottom centre; bubbles as M07 |
