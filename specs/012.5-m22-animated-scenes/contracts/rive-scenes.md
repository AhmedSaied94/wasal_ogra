# Contract: The Scenes Art File

What `apps/mobile/assets/rive/wassal_scenes.riv` must hold, and how the app loads, checks and draws
it. Spec FR-001–FR-010; research R1–R4, R13, R15. It extends 008.5's
[rive-characters.md](../../008.5-m21-design-refresh/contracts/rive-characters.md) "How the app uses
it" (the loader, the check and `RiveArtView`) to a second file, and M07's
[scenes.md](../../012-m07-onboarding/contracts/scenes.md) "Panel art" with the animation.

## The file

| What | Value |
| --- | --- |
| Asset | `assets/rive/wassal_scenes.riv` (declared under `flutter: assets:` as the folder is today) |
| Made by | Claude Design, with the Rive MCP, from the canvas's six panel drawings; exported from Rive's free plan with data binding |
| Editable source | the owner's Rive account (still named «Untitled»: owner step) |
| Reference | the canvas board «حركة المشاهد» (`SceneMotion`) and HANDOFF §6.8 |
| Size | 49,610 bytes as delivered; budget under 100 KB (SC-006) |
| Runtime | `rive 0.14.11` and `rive_native`, `Factory.flutter`, as the first file |

## The contract (`sceneContract`, `lib/core/art/rive_scenes.dart`)

### The panels: drawn by the app

| Artboard | Size | State machine | Default view model | Booleans |
| --- | --- | --- | --- | --- |
| `opening_key` | 358×540 | `Panel` | `Panel` | `moallem`, `usta`, `belya`, `salma` |
| `opening_stand` | 358×540 | `Panel` | `Panel` | the same four |
| `opening_go` | 358×540 | `Panel` | `Panel` | the same four |
| `stand_morning` | 358×540 | `Panel` | `Panel` | the same four |
| `salma_waiting` | 358×540 | `Panel` | `Panel` | the same four |
| `usta_decides` | 358×540 | `Panel` | `Panel` | the same four |

- The machine plays by itself and loops; the app only sets the four Booleans.
- `true` makes that character talk where they are drawn. A character who isn't drawn ignores it.
  With all four false, the characters breathe and blink (HANDOFF §6.8).
- The first frame is the panel's still drawing.

### Known artboards: never drawn, never a problem

| Kind | Artboards |
| --- | --- |
| Building blocks, nested in the panels | `Character_usta`, `Character_moallem`, `Character_belya`, `Character_salma`, `Prop_tin`, `Prop_key`, `Prop_drawer`, `Prop_busstop`, `Prop_books`, `Prop_bag`, `Tuktuk` |
| The export's own | `Artboard 1` (the file's default), `Watermark`, `NuRiveBrandmark01`, `NuRiveWordmark01` |

Any other artboard is a problem, `assets/rive/wassal_scenes.riv: artboard <name>: not in the contract`, and
changes nothing else.

## Loading (`lib/core/art/rive_art.dart`, `rive_scenes.dart`)

- `loadRiveArt({RiveContract? contract, String? asset, AssetBundle? bundle, check})` and
  `checkRiveArt(rive.File file, [RiveContract? contract])`. They work as 008.5's, but read the
  contract from the argument, the characters file's when it is `null`. `asset` still overrides the
  path, and `check` keeps its one argument, so 008.5's calls and tests stay as they are
  (data-model.md `RiveArt`).
- `riveScenesProvider` (`@Riverpod(keepAlive: true)`) loads `sceneContract` and disposes the file
  when the provider is disposed.
- Boot step `art` (`lib/bootstrap/startup.dart`): `Future.wait([riveArtProvider.future,
  riveScenesProvider.future])`. The step can't fail (each load returns a `RiveArt`), and
  `retryAppStartup` invalidates neither.
- Every failure is a problem, never a throw: no asset, no native library, not a Rive file, a decode
  error, or a check that throws. The file is then `RiveArt.none`, and every panel shows its drawing
  (FR-004).
- Problems start with the asset's path: `assets/rive/wassal_scenes.riv: …` and
  `assets/rive/wassal.riv: …`. The loader's own problems already did, and 008.5's
  `boot_progress_test` checks it, so the check's problems follow them.

## Checking an artboard

As 008.5's `_check`, against the panel's spec. Each failure below leaves that panel to its drawing,
alone:

| Failure | Problem text |
| --- | --- |
| missing | `artboard <name>: missing` |
| wrong size | `artboard <name>: <w>×<h>, not 358×540` |
| no `Panel` machine | `artboard <name>: no state machine Panel` |
| another default view model | `artboard <name>: view model <x>, not Panel` |
| a Boolean missing or of another type | `view model Panel: <b> is <type or missing>, not boolean` |

## Drawing (`RiveArtView`, `RiveArtScope`)

- `RiveArtScope` carries `art` (the characters) and `scenes`. `bootstrap/app.dart` sets both from
  the two providers' values.
- `RiveArtView` gains:
  - `source`: `RiveArtSource.characters` (the default, so every current call is unchanged) or
    `.scenes`;
  - `alignment`: default `Alignment.center`, as `RiveWidget` draws today.

  It reads the spec from `RiveArt.contract`, not from the first file's constant.
- Panels use `source: scenes`, `fit: Fit.cover`, `alignment: Alignment.bottomCenter` (FR-008; the
  drawing is `BoxFit.cover`, bottom centre).
- `RiveArtView` already draws its fallback when there is no scope, no file, a failed artboard or
  reduced motion, and opens one controller and one view-model instance per widget, disposed with it.
  Panels keep all of that (FR-009).
- View-model instance: the exported default instance (`Instance`, all false) or a new one, as
  `RiveArtView._open` does today, bound with `DataBind.byInstance`.

## Panel art (`lib/core/art/panel_art.dart`)

- `PanelArt.artFor(slug)`: the three aliases of the release draft (data-model.md "Art slug"), else
  the slug.
- `PanelArt.assetFor(slug)` resolves through `artFor` first, so `ch1_*` gets the drawing.
- With `animate: true`: `RiveArtView(source: scenes, artboard: artFor(slug), fallback: <the
  drawing or PanelFallback>, bind: (vm) => set the four Booleans from panelTalkers(talking))`.
- With `animate: false` (the default): M07's drawing, else `PanelFallback`, unchanged.

## The debug panel

`features/trip/presentation/playtest/debug_panel.dart`'s «ملف Rive» row lists both files'
problems, the characters file first; «سليم» only when both lists are empty. Dev and staging builds
only, as today.

## What this doesn't change

- `wassal.riv`'s contract (008.5), except that its problems now carry the asset's path.
- `ArtTier`: it applies to the trip's seats only; panels ignore it.
- M07's `PanelFallback`, its drawings map and its `sync_assets.dart` entries.
