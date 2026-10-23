# The passenger character

This folder holds one file: `passenger.riv`, the owner's Rive character, which draws every passenger
in a trip (specs/008-m02-trip-screen, FR-045).

- It must match `specs/008-m02-trip-screen/contracts/rive-character.md`: the `Passenger` artboard,
  state machine and view model, with the properties `mood`, `talking`, `asleep`, `headphones`,
  `alight`, `shirt` and `accessory`. `rive_character_contract_test.dart` checks it.
- It must be exported from a paid Rive plan (Cadet or above), so it plays without Rive's splash
  screen. Record the plan that exported it in the pull request.
- It must be made for this project, not remixed from a community file (those are CC BY 4.0).
- Nothing else goes in this folder.

Without the file the app draws every passenger with the stand-in painter and the trip still plays,
but the character's contract test and goldens fail until it is committed (owner action T059).
