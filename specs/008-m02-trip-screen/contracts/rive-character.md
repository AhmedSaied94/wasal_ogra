# Contract: The Passenger Character File

What `apps/mobile/assets/rive/passenger.riv` must contain, so the app can draw every passenger with it
(spec FR-045, Clarifications). The owner supplies the file before the merge; the app's contract test
fails until it is committed and matches this page. Runtime: `rive 0.14.11` through `flame_rive`, with
the Flutter renderer (research R1).

## The file

| Item | Name | Notes |
| --- | --- | --- |
| Artboard | `Passenger` | Head and shoulders, facing the camera. About 200×240 units, with the face's width about 160 units, so the app can scale it to a seat. Transparent background. |
| State machine | `Passenger` | Plays on its own; the app only sets the view model below. |
| View model | `Passenger` | Bound to the artboard as its default view model. |

## View-model properties

The app sets these on each passenger's own instance. Names are exact and case-sensitive.

| Property | Type | Values | What it must show |
| --- | --- | --- | --- |
| `mood` | Number | 0, 1, 2, 3 | 0 calm and smiling; 1 a little impatient; 2 frowning with a sweat drop; 3 angry (a fight, a failed trip). Changes blend in about 200 ms. |
| `talking` | Boolean | | Mouth moves while true. |
| `asleep` | Boolean | | Head tilted, eyes closed, a "z z" loop. False wakes them. |
| `headphones` | Boolean | | Headphones on, with music marks by the ears. False: headphones around the neck. |
| `alight` | Trigger | | A short "standing up" motion (about 400 ms); the app moves the character out afterwards. |
| `shirt` | Color | any | The shirt and shoulders' fill. Outlines stay ink (`#1D1A2B`). |
| `accessory` | Enum | `none`, `cap`, `glasses`, `headphones`, `tie`, `scarf`, `headscarf` | One accessory drawn on the character. `headphones` here is the look of the type; the `headphones` boolean is the on/off state. |

- Any combination must look right: asleep with headphones, angry and talking, and so on.
- The style is «ستيكر الميكروباص»: flat fills, thick ink outlines (about 6 units), no gradients, no
  text inside the file.
- At 50 pt wide on screen (the smallest back-row face), the mood must still be readable.

## Export

- Exported from a paid Rive plan (Cadet or above), so the file plays without a Rive splash screen
  (research R1). Record the plan in the PR.
- Made for this project, not remixed from a community file (community files are CC BY 4.0).
- Target size: under 300 KB.

## How the app uses it

- Decodes the file once (`File.asset(…, riveFactory: Factory.flutter)`) and caches it.
- Per passenger: a new `ArtboardInstance` of `Passenger`, its `StateMachine`, and a new
  `ViewModelInstance` bound to it; all disposed when the passenger leaves.
- Sets `shirt` and `accessory` once, from the passenger's `SkinLook`, and the other properties every
  time the passenger's view changes (data-model.md, `PassengerView`).
- If the file is missing or fails to load, every passenger falls back to the stand-in painter, and the
  trip still plays.

## Tests

- `rive_character_contract_test.dart` (runs after `rive_native:setup --platform linux`): the file
  loads with `Factory.flutter`; the artboard, state machine and view model exist; every property above
  exists with its type; `accessory` has exactly the listed values.
- `rive_character_goldens_test.dart`: one golden per `mood`, plus asleep, headphones and talking, at
  80 pt and 50 pt, with `Factory.flutter`. Generated on Linux; CI's run is the reference.
- `passenger_art_test.dart`: the mapping from `PassengerView` to the properties, against a fake
  instance.
