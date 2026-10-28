# Research: Animated Scenes (M22)

Phase 0 of [plan.md](./plan.md). Each decision gives what was chosen, why, and what was rejected.
The spec left no NEEDS CLARIFICATION; the open points below are design choices the spec delegated
("the plan places them…") or facts checked against the code on 2026-10-28.

## R1. Loading the second file

- **Decision:** a second `RiveArt`, from the same loader as the first.
  - `loadRiveArt` and `checkRiveArt` take a `RiveContract` (data-model.md) instead of reading the
    first file's constants. The first file's contract is today's `riveContract` with
    `riveExportArtboards`, so its behaviour doesn't change.
  - A new keep-alive provider, `riveScenesProvider`, decodes `assets/rive/wassal_scenes.riv` against
    `sceneContract` (contracts/rive-scenes.md).
  - Boot's step `art` waits for both files: `BootStep.art: Future.wait([riveArt, riveScenes])`. Each
    load never throws (`loadRiveArt` turns every failure into a problem), so the step still never
    fails, and `retryAppStartup` keeps both files.
- **Why:**
  - A new player's first screen after Loading is the opening scene. Loading the file there would
    leave the first panel on its drawing while the file decodes, then swap mid-panel.
  - The two loads run side by side, and the file is 49.6 KB, so the step takes no longer in practice
    (SC-003 measures it).
  - One loader and one check keep the two files' failure handling identical (FR-004, spec
    "Defaults": the same check as the first file).
- **Rejected:**
  - Decoding when a scene opens: the swap above, and a second failure path.
  - A new `BootStep.scenes`: it changes the Loading screen's progress and its tests for no gain.
  - Merging the panels into `wassal.riv`: the owner's two files are made and exported separately
    (HANDOFF §6.8), and 008.5's contract tests would have to learn the panels.

## R2. The scenes file's contract and check

- **Decision:**
  - `sceneContract` names the six panel artboards, each 358×540, with the machine `Panel` and the
    default view model `Panel` holding four Booleans (`moallem`, `usta`, `belya`, `salma`).
  - It lists two sets of known extra artboards. Neither is a problem, and neither is ever opened:
    - the building blocks the panels nest: the four `Character_*`, the six `Prop_*` and `Tuktuk`;
    - the export's own: `Artboard 1`, `Watermark`, `NuRiveBrandmark01`, `NuRiveWordmark01`.
  - Any other artboard is a problem and changes nothing else, as in the first file.
  - Problems are prefixed with the asset's path (`assets/rive/wassal_scenes.riv: artboard …`), as
    the loader's own problems already were, so the debug panel can list both files' problems in
    one place (FR-005).
- **Why:** the file as delivered has exactly these artboards (spec Assumptions). Opening by name is
  what keeps the free plan's splash and the empty default artboard off screen (008.5 R15).
- **Rejected:**
  - Checking the building blocks too: the panels draw them; a broken one shows in the panel's golden
    and the file test (R11), which a size check wouldn't catch anyway.
  - Treating an unknown artboard as fatal for the file: one stray export artboard would take every
    panel back to its drawing.

## R3. Which art a panel draws, decided once

- **Decision:**
  - `ScenePlayer` decides, per panel, whether it animates:
    `animated = scenePanels.animates(artSlug) && !MediaQuery.disableAnimationsOf(context)`.
    `scenePanelsProvider` (application layer) answers `animates` from `riveScenesProvider`: the file
    loaded and the artboard passed. Tests override it.
  - `PanelArt` gains `animate` and `talking`. With `animate`, it draws the panel's artboard through
    `RiveArtView`, with the drawing as the view's fallback, so a missing file at draw time still
    shows the drawing. Without `animate`, it draws what it draws today: the drawing, else
    `PanelFallback`.
  - `RiveArtView` gains:
    - `source` (`RiveArtSource.characters`, the default, or `.scenes`), read from `RiveArtScope`,
      which now carries both files;
    - `alignment`, so panels draw with `Fit.cover` and `Alignment.bottomCenter`, as the drawings do
      (`BoxFit.cover`, bottom centre) and as HANDOFF §6.8 asks (FR-008).

    Every existing call keeps its behaviour: the defaults are the first file and `Alignment.center`.
- **Why:**
  - The turns (R5–R7) and the art must agree. If the player ran turns while the art fell back, or
    the other way round, the panel would talk with nobody moving, or move with every bubble already
    up.
  - One decision point is also the test seam: an override of `scenePanelsProvider` runs the turns
    without Rive's native library, and the Rive-tagged tests use the real file.
- **Rejected:**
  - Letting `PanelArt` decide alone: `ScenePlayer` would have to repeat the logic to know whether to
    run turns.
  - A separate widget for animated panels: it would duplicate `RiveArtView`'s open, bind and dispose
    logic, which 008.5 already tests.

## R4. The release draft's three names

- **Decision:** `PanelArt.artFor(slug)`, a const map `ch1_stand_morning → stand_morning`,
  `ch1_salma_asks → salma_waiting`, `ch1_usta_dreams → usta_decides`. Every other slug maps to itself.
  The drawing lookup (`assetFor`) and the artboard name both use the result.
- **Why:** they are the same three pictures (spec FR-010). One map keeps the drawing and the
  animation from disagreeing, and adds no asset.
- **Rejected:**
  - Copying the SVGs under the draft's names: two copies to keep in step, and `sync_assets.dart` and
    `design_assets_test` would grow for no art.
  - Renaming the draft's slugs: the draft is content whose brief names them, and the owner chose those
    names. The delivery plan lists the aliases as this feature's work.

## R5. The turn schedule

- **Decision:** a pure `PanelTurns`, in `features/onboarding/domain/panel_turns.dart`:
  - built from a panel's lines (the caption is dropped) and `TurnTimings`;
  - each turn's length is `perLetter × letters`, clamped to `[min, max]`. Letters are the line's
    grapheme clusters that aren't white space (`characters`, already a direct dependency since M07);
  - the first turn starts after `leadIn`; each later one starts `pause` after the one before ends;
  - `at(elapsed)` gives the number of bubbles shown and the speaker talking (or none);
  - `end` is when the last turn ends.
- **Values** (named constants in a new `core/theme/tokens/scene_turn_tokens.dart`, `SceneTurnTokens`;
  `ScenePlayer` builds its `TurnTimings` from them):

  | Value | Default | Why |
  | --- | --- | --- |
  | `leadIn` | `MotionTokens.sheetIn` (280 ms) | the panel's slide-in; the first bubble pops once it lands |
  | `perLetter` | 60 ms | about 16 letters a second, an unhurried reading pace for short Egyptian lines |
  | `min` | 1200 ms | a short line («يلا، على الله.») still gets a few mouth flaps of the 0.5 s `talk` loop |
  | `max` | 4000 ms | a long line doesn't hold the next speaker back for long |
  | `pause` | 300 ms | a beat between speakers, so the change of speaker shows |

  With these values, measured from the panel's arrival to the end of its last turn:

  | Scene | Panel 1 | Panel 2 | Panel 3 |
  | --- | --- | --- | --- |
  | The sample's `opening` | 3.0 s | 4.0 s | 3.3 s |
  | The sample's `the_stand` | 1.5 s | 1.8 s | 1.8 s |
  | The draft's `first_sight` | 1.8 s | 3.6 s | 3.3 s |

  Letters per line run from 12 to 45, so every turn is 1.2–2.7 s, and none reaches the ceiling. A
  player who reads along waits at most 4 s on a panel, and «يلا» shows the rest at once (R9).
- **Why:**
  - A pure schedule is the part worth testing hard (order, bounds, pause, edge cases) without
    widgets or Rive (constitution XIII).
  - These are presentation values, like the motion tokens. They don't balance the game, so no
    Remote Config key is needed (constitution VIII; spec "Defaults"). The repo guard allows
    durations only under `core/theme/tokens/`, so they get their own file there.
- **Rejected:**
  - Adding them to `DesignExtras`: that class holds only values measured from the artboards' HTML,
    each naming its artboard, and these are this spec's own defaults.
  - Fixed-length turns: a two-word line and a two-clause line would talk for the same time.
  - Timing from the file (Rive events at the end of a mouth loop): the file has no events, and the
    length belongs to the text, which is content.
  - A tunable per value: nothing to retune for balance, and a number the player never notices.

## R6. The turn clock

- **Decision:** `ScenePlayer` keeps one `AnimationController` for the current panel. It is created
  when an animated panel shows, its duration is `PanelTurns.end`, and it is disposed when the panel
  leaves.
  - On each tick, a listener computes `PanelTurns.at(controller elapsed)`, the bubbles shown and the
    speaker talking. It calls `setState` only when the result differs from the last (`TurnsAt` has
    value equality), and the new value goes to `ComicPanel` and `PanelArt`. A panel of *n* turns
    builds at most 2*n* + 1 times (its first build, then each turn's start and end), not on every
    frame, so the Booleans are set again only when one changes.
  - «يلا» before the last turn has started jumps the controller to its end (FR-016).
  - A panel that starts as a drawing (reduced motion, no file) is marked done: if reduced motion is
    turned off while it shows, it switches to its animation with every bubble shown and nobody
    talking (spec Edge Cases).
  - In the background no frames run, so the controller stops. On return it catches up to the
    frame's time stamp: the turns go on or have ended. No bubble is lost, and none starts over (spec
    Edge Cases).
- **Why:** a frame-driven controller stops with the app, is driven by `tester.pump(duration)` in
  widget tests without fake timers, and is disposed with the panel (FR-009). The panel's slide-in
  already runs on the same frames.
- **Rejected:**
  - An `AnimatedBuilder` around the panel: it rebuilds `ComicPanel` and sets the four Booleans on
    every frame, for a value that changes a few times a panel, on the A06's frame budget (SC-002).
  - `Timer`s: not tied to frames, they keep running in the background, and they need `fakeAsync` in
    tests.
  - Rive's own clock, read back from the state machine: the app can't read where a loop is, and the
    turns are the app's, not the file's.

## R7. Bubbles in turn

- **Decision:** `ComicPanel` gains `shown` (how many bubbles are visible; default all, so M07's calls
  and goldens don't change).
  - Every bubble is laid out from the start. The ones beyond `shown` are invisible but stay in the
    semantics tree (`Opacity` 0, `alwaysIncludeSemantics: true`). So every line is in the read order
    from the panel's start (FR-018), and nothing moves when a bubble appears.
  - A bubble that becomes visible pops with `BubblePop` (`MotionTokens.bubblePop`, 180 ms, grows from
    0.6 at the bottom), the design's pop that `SpeechBubble` already uses. Under reduced motion
    `BubblePop` shows the bubble at once, but a panel never runs turns then anyway.
  - At most two bubbles show (constitution XI): in turn, `ComicPanel` shows the last two shown when
    a panel has more lines, and an older one goes unseen in its place, still read. Today's scenes
    have at most two.
- **Why:** M07's panel bubbles arrive with the panel and have no entrance of their own, so a bubble
  that appears mid-panel needs one. The design's `bubblePop` is that entrance. Keeping the layout
  fixed avoids a jump, and keeps the read order whole without a second semantics tree.
- **Rejected:**
  - Adding bubbles to the tree as they appear: the read order would change under a screen reader,
    and the column would shift.
  - A second, hidden semantics node with every line: two descriptions of the same panel to keep in
    step.

## R8. The talking Booleans

- **Decision:** a pure `panelTalkers(String? talking)` returns the four Booleans: the one named
  `talking` is true, the others false; an unknown speaker or none sets all four false.
  `PanelArt`'s `bind` sets all four on every build, so turning off is as certain as turning on.
- **Why:** FR-012's "at most one, none between turns" is then one table test. Setting all four every
  time means no state is left over from a previous turn or panel.
- **Rejected:** setting only the changed Boolean: a missed rebuild could leave a speaker talking.

## R9. «يلا», «تخطّى» and back during turns

- **Decision:**
  - «يلا» runs the reveal while `PanelTurns.at(elapsed)` hasn't reached the last turn, and moves on
    otherwise. Moving on and finishing are M07's code paths, unchanged.
  - «تخطّى» and back call M07's `_finish`, which removes the player, and with it the controller and
    the Rive instance.
  - No new string, and no change to «يلا»'s look or its press feedback.
- **Why:** the owner's answer (spec Clarifications). Reusing M07's paths keeps the scene's flags
  (opening done, scene seen) written exactly once, as today.
- **Rejected:** disabling «يلا» until the last turn (offered, not chosen).

## R10. Silence

- **Decision:** the scene adds no sound and no haptic of its own. Turns, the reveal and the panel
  changes call nothing in the app's sound and haptics service (`core/audio_haptics/`).
  - The one call left is the press tick every `Pressable` gives (`pressFeedbackProvider`, which
    calls `Haptics.selection` and goes silent with the vibration setting off). «يلا» and «تخطّى»
    keep it, the reveal tap included (FR-016).
  - A scene-player test records both fakes (`FakeSfxPlayer`, `FakeHaptics`). It finds no sound over
    the whole scene, and exactly one `selection` per «يلا» or «تخطّى» tap.
- **Why:** the owner's answer (spec Clarifications Q4) is about sound, and FR-016 keeps the press
  feedback. The test keeps a later change from adding a sound, or a haptic to a turn, by accident.

## R11. Checking the delivered file in tests

- **Decision**, all tagged `rive`:
  - **The contract** (`test/core/art/rive_scenes_contract_test.dart`): every panel artboard, its size,
    machine and view model with its Booleans; the building blocks and the export's artboards are the
    known extras, and nothing else; the check passes with no problem; the file loads from the bundle
    as boot does.
  - **Who talks where** (`test/core/art/rive_scenes_talk_test.dart`): every panel is rendered at
    fixed times with each Boolean on and off, as in the spec's check of 2026-10-28.
    - For every spoken line of the sample's `opening` and `the_stand` and the draft's `first_sight`,
      the speaker's Boolean changes the panel's pixels.
    - A Boolean whose character isn't drawn changes nothing. That pins the spec's "Who talks where"
      table.
    - Two runs give the same pixels, and the frame 4.8 s on matches the first, so the loop closes.
  - **Goldens** (`test/features/onboarding/rive_scene_goldens_test.dart`): one sheet per panel with
    its first frame beside its drawing, generated on Linux; CI's run is the reference.
- **Why:** this is the delivered file's own test, as 008.5 has for `wassal.riv`. If a later export
  breaks a mouth or renames an artboard, CI says so before a phone does.
- **The draft's lines:** the release draft isn't in the repo, so its `first_sight` scene is copied
  into `test/fixtures/tutorial/first_sight.json` beside M07's copies of the draft's trips (its README
  says what and when).

## R12. The usta's look (FR-023)

- **Decision:**
  1. `apps/mobile/assets/rive/wassal.riv`: the owner's updated file, already in the working tree.
     Checked on 2026-10-28: only `look` 18 renders differently. The other 23 people and the four
     vehicles are identical to the pixel, and 008.5's contract test passes.
  2. `docs/design/`: rebuilt from the canvas with its tools (`docs/design/tools/README.md` steps 1–5),
     from the canvas's `project/` files downloaded with the Artifact tool. The diff is reviewed:
     - the usta's drawing and the artboards that draw it from the sheet are expected to change;
     - `HANDOFF.md` is already rebuilt (with the banner and the README's overrides updated on
       2026-10-28);
     - any other change the canvas brings is listed for the owner before it is kept.
  3. `tool/design/sync_assets.dart` copies the new `illustrations/characters/usta.svg` into
     `apps/mobile/assets/illustrations/characters/`, and `design_assets_test` checks the copy.
  4. The goldens that draw the usta are rewritten and reviewed:
     - static: the Name card (`name_goldens_test`), `characters_test` and the components gallery,
       wherever they draw `CharacterAvatar('usta')`;
     - Rive: the six-characters sheet of `rive_art_goldens_test`.

     No other golden may change. The six scene panels' goldens don't, because their drawings
     already show the panels' usta. In the opening panels, the old skin colour `#C68B5E` that
     remains belongs to المعلم.
- **Why:** SC-007, one look everywhere. The static usta is drawn wherever Rive isn't, and the trip's
  art and the panels already show the new look.
- **Rejected:**
  - Hand-editing `usta.svg`: `docs/design/` is generated from the canvas and never hand-edited (its
    tools' README).
  - Leaving the static art for later: under reduced motion the usta would change face between the
    scenes and the Name card.

## R13. The debug panel

- **Decision:** the trip's debug panel (`features/trip/presentation/playtest/debug_panel.dart`) lists
  `riveArtProvider`'s problems, then `riveScenesProvider`'s, under its existing «ملف Rive» row.
  Each line carries its asset's path. Prod builds have no debug panel, so they fall back silently
  (FR-005).
- **Why:** it is where art problems already show on dev and staging. A tester who sees a panel on its
  drawing opens any trip's debug panel and reads why.
- **Rejected:** a second list on the playtest «Onboarding» card: two places to look, and the card is
  about replaying steps, not art.

## R14. Performance

- **Decision:**
  - **Scene frame rate**, with a new `integration_test/scene_perf_test.dart` and
    `tool/perf/scene_fps.sh`, built like `trip_perf_test.dart` and `trip_fps.sh`. In a profile build
    of the dev flavor on the Galaxy A06, it plays the opening's three panels and the سلمى scene with
    their turns. Budgets: an average of at least 55 fps, no one-second window under 45 fps (SC-002),
    and memory under 300 MB.
  - **Cold start:** `tool/perf/cold_start.sh` as before; Home within 3 s (SC-003).
  - **The first trip within 20 s** (SC-003, M07 SC-001), timed by hand on a fresh install. Open the
    app, tap «يلا» as soon as it shows and accept the suggested name. The reveal can add one tap per
    animated panel, so this is checked again, not assumed.
- **Why:** SC-002 borrows the trip's floor, so it is measured the trip's way. Only one panel's
  instance lives at a time (R6), plus the outgoing one during M07's 280 ms slide.
- **Expected:** the file has no bones and no meshes, and a panel is one artboard with a few nested
  ones (HANDOFF §6.8), far lighter than a trip's twelve `Person` instances, which 008.5 runs.
- **If it misses:** the phones report it and the owner decides. The art tier doesn't apply to scenes
  (spec "Defaults"), so there is no automatic switch.

## R15. Rive's splash

- **Decision:** nothing in the app. The renders of 2026-10-28 show every panel's own art at t = 0,
  and its loop moving by 0.35 s. The first-frame goldens (R11) would show a splash if one were drawn.
  The phone check (SC-001) confirms it on both phones.
- **Why:** the Rive runtime has no splash logic (008.5 R15). The board's and HANDOFF §6.8's note most
  likely describes the editor's preview.

## R16. Documents

- **Decision:**
  - `docs/architecture-mobile.md`: §5's tree (`core/art/` and `assets/rive/` name both files) and §8
    (the Characters row and the "Art" bullet: the second file, the panels, the turns).
  - `CLAUDE.md`: the project status (M22), the Rive bullet (two files, both checked at boot) and the
    Rive golden command for the scenes.
  - `docs/delivery-plan.md`: the Progress list, when this feature merges.
  - `docs/owner-actions.md`: a 012.5 section at `/speckit-implement`:
    - the phone checks (SC-001) and the A06 runs (SC-002, SC-003);
    - renaming the Rive source from «Untitled» to `wassal_scenes`;
    - the release draft's line change, which travels with the draft.
  - `apps/mobile/assets/rive/README.md`: the second file.
  - `test/fixtures/tutorial/README.md`: the new `first_sight.json`.
- **Not changed:** M07's `contracts/scenes.md` and 008.5's `contracts/rive-characters.md` are merged
  features' records. This feature's contracts extend them, and say where (contracts/rive-scenes.md).

## Handed over to later features

- **M10** (the album and `SceneViewer`, chapters 2–4): replays use the same `PanelArt` and turns. New
  panels follow the same path: a drawing and an artboard named after its slug, in this file or a later
  one, with the same four Booleans or more. A new character's Boolean extends `sceneContract`.
- **The owner, whenever Claude Design can:**
  - a `reducedMotion` input on `Panel`, so panels could keep moving gently under reduced motion. It is
    the same open ask as 008.5's "Open" 2.
  - a `belya` in `usta_decides` is no longer needed, now that the draft's line is the usta's.
