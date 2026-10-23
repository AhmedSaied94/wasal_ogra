# The Rive file

`wassal.riv` is the owner's Rive file. It animates every person, vehicle and UI effect in the
«كرتون ناعم» design (specs/008.5-m21-design-refresh, FR-030 – FR-035):

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
- It is exported from Rive's free plan (the owner's decision of 2026-10-23). The export adds
  Rive's splash as its own artboards (`Watermark`, `NuRiveBrandmark01`, `NuRiveWordmark01`). The app
  opens every artboard by name and never draws them.
- It must be made for this project, not remixed from a community file (those are CC BY 4.0).
- Nothing else goes in this folder.

Without the file, the app draws everything with the design's static SVGs and the trip still plays,
but the tests tagged `rive` fail.
