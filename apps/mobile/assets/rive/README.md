# The Rive files

Two files, both the owner's, both exported from Rive's free plan with data binding. Their editable
sources are in the owner's Rive account. Boot decodes both in its step `art`, and checks each against
its own contract. A file or an artboard that fails falls back to the design's static SVGs, and the
debug panel lists the problems.

## `wassal.riv`: people, vehicles and UI

It animates every person, vehicle and UI effect in the «كرتون ناعم» design
(specs/008.5-m21-design-refresh, FR-030 – FR-035):

| Artboard | What it draws |
| --- | --- |
| `Person` | all 24 people (the 18 passengers and the 6 story characters), picked by its `look` number |
| `Vehicle` | `tuktuk`, `microbus_old`, `microbus_new` and `microbus_travel`, picked by `look` |
| `CoachHand`, `Stars`, `CoinsBurst`, … | the 11 UI animations (the coach hand, stars, bursts, confetti, the loading wheel, …) |

- It must match `specs/008.5-m21-design-refresh/contracts/rive-characters.md`: the artboards, their
  state machines, and their view models with every property.
  `test/features/trip/rive_art_contract_test.dart` checks it, and
  `test/features/trip/rive_art_goldens_test.dart` draws it (regenerate them with
  `fvm flutter test --update-goldens test/features/trip/rive_art_goldens_test.dart` after an export).
- Since M22 (specs/012.5-m22-animated-scenes, FR-023), its usta (`look` 18) has the panels' look:
  the lighter skin and the forelock.

## `wassal_scenes.riv`: the comic panels

It plays the first session's comic panels (specs/012.5-m22-animated-scenes):

| Artboard | What it draws |
| --- | --- |
| `opening_key`, `opening_stand`, `opening_go` | the opening's three panels |
| `stand_morning`, `salma_waiting`, `usta_decides` | the سلمى scene's three panels (the release draft's `ch1_*` names map to them) |

- It must match `specs/012.5-m22-animated-scenes/contracts/rive-scenes.md`. Each panel is 358×540,
  with the state machine `Panel` and the default view model `Panel`, whose four Booleans `moallem`,
  `usta`, `belya` and `salma` make that character talk. `test/core/art/rive_scenes_contract_test.dart`
  checks it, `test/core/art/rive_scenes_talk_test.dart` checks who talks where, and
  `test/features/onboarding/rive_scene_goldens_test.dart` draws each panel's first frame beside its
  drawing (regenerate it with
  `fvm flutter test --update-goldens test/features/onboarding/rive_scene_goldens_test.dart`).
- The panels nest its building blocks (`Character_*`, `Prop_*`, `Tuktuk`), which the app never opens
  on their own.

## Both files

- The export adds its own artboards: the file's default frame (`iPhone 16 - 1` in `wassal.riv`,
  `Artboard 1` in `wassal_scenes.riv`) and Rive's splash (`Watermark`, `NuRiveBrandmark01`,
  `NuRiveWordmark01`). The app opens every artboard by name and never draws them.
- They must be made for this project, not remixed from a community file (those are CC BY 4.0).
- Nothing else goes in this folder.

Without a file, the app draws its art with the design's static SVGs and the game still plays, but
the tests tagged `rive` fail.
