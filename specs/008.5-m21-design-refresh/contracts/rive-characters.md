# Contract: The Rive Art File

What `apps/mobile/assets/rive/wassal.riv` contains, and how the app drives it to draw every passenger,
story character, vehicle and UI animation in the «كرتون ناعم» style (spec FR-030 – FR-035, research
R15 – R17). **Supersedes** M02's [rive-character.md](../../008-m02-trip-screen/contracts/rive-character.md)
and its single `passenger.riv`. Runtime: `rive 0.14.11` through `flame_rive` and `RiveWidget`, with
the Flutter renderer (`Factory.flutter`).

**Revised 2026-10-23 to the file the owner delivered.** The plan's draft asked for four files, a
`Character` view model and a `pose` enum. The owner made one file whose people take M02-style inputs
(a `look`, a `mood` number and booleans). It holds every look, state, vehicle and UI animation the
draft listed, plus the six later passengers and the two later vehicles. This page describes that file
as it is; the app adapts (research R15 and R16, "Revised"). The things the file doesn't have yet are
under [Open](#open).

## Reference material

| What | Where | Use |
| --- | --- | --- |
| The art | `docs/design/illustrations/{passengers,characters,vehicles}/*.svg` | the drawings the looks match, shape for shape |
| The states as drawn | `docs/design/illustrations/passenger_states/`, `screens/Characters.html` | how each state looks |
| The motion | `docs/design/lottie/` (open `lottie/index.html`) | timings and what moves in each state. A reference only; no Lottie in the app. |
| The rig | HANDOFF §5.1 and §6.2 | the shared skeleton |

## The file

| Artboard | Size | State machine | View model (default) | Used in this feature by |
| --- | --- | --- | --- | --- |
| `Person` | 200×240 | `Passenger` | `Passenger` | every passenger in the trip; `belya` (look 23) in hints; the other characters in the gallery, ready for M07–M10 |
| `Vehicle` | 236×150 | `Vehicle` | `Vehicle` | the loading screen; ready for Home (M07) |
| `CoachHand` | 100×100 | `CoachHand` | none | hints |
| `LoadingWheel` | 80×80 | `LoadingWheel` | none | `States` |
| `Stars`, `CoinsBurst`, `BonatBurst`, `Confetti`, `FuelGauge`, `GiftOpen`, `SparklePlace`, `RingShine`, `NotifBell` | see [UI animations](#ui-animations) | named as the artboard | see there | the gallery, ready for later features |
| `Splash` | 236×150 | `Splash` | `Splash` | not used: the loading screen draws `Vehicle` over its own road (research R6) |

- Each artboard's state machine is named after it and plays on its own; the app only sets view-model
  properties.
- The file also holds `iPhone 16 - 1` (its default artboard, an empty frame) and the free plan's
  splash: `Watermark` (Rive's logo on black) with `NuRiveBrandmark01` and `NuRiveWordmark01`. The app
  opens every artboard by name and never draws these four, and the check accepts them
  ([Export](#export)).

## People: passengers and story characters

| Item | Value |
| --- | --- |
| Artboard | `Person`, 200×240, transparent |
| Rig | HANDOFF §5.1: head centre near (100, 100), head radius about 42, drawn at near-row size. The app places the artboard by the head centre and scales it by the row (1.0, 0.8, 0.625; 1.15 in the tuktuk). |
| Style | flat fills, no outlines, no gradients, as the SVGs; no text in the file (a note's «٢٠٠» is not drawn) |
| Looks | one artboard draws all 24 people; `look` picks one |

### Looks

`look` follows HANDOFF §5.3's passengers in order, then the story characters (checked against the
SVGs on 2026-10-23):

| `look` | Person | `look` | Person | `look` | Person |
| --- | --- | --- | --- | --- | --- |
| 0 | `regular` | 8 | `group_payer` | 16 | `regular_customer` |
| 1 | `hagga` | 9 | `chatterbox` | 17 | `honest` |
| 2 | `sleeper` | 10 | `changer` | 18 | `usta` |
| 3 | `hurried` | 11 | `bags_lady` | 19 | `salma` |
| 4 | `effendi_200` | 12 | `dodger` | 20 | `bride_father` |
| 5 | `student` | 13 | `mother_kids` | 21 | `bride_mother` |
| 6 | `headphones` | 14 | `big_family` | 22 | `moallem` |
| 7 | `claimer` | 15 | `traveler` | 23 | `belya` |

A value outside 0–23 draws a bare face; the app never sets one.

### `Passenger` properties

Names are exact and case-sensitive. The app makes its own instance per person; the file's instances
(`test_look0`, `test_look1`) are the owner's.

| Property | Type | Values | What it shows |
| --- | --- | --- | --- |
| `look` | Number | 0–23 | the person ([Looks](#looks)) |
| `mood` | Number | 0–4 | 0 calm (`idle`, blinking); 1 `impatient_1`; 2 `impatient_2` (frown, sweat drop); 3 `fight` (red face, gritted teeth, sparks); 4 `angry` (red face, frown) |
| `talking` | Boolean | | `talk`: the mouth moves |
| `asleep` | Boolean | | `sleep`: head tilted, eyes closed, «z z». Turning false plays `wake`. |
| `headphones` | Boolean | | `headphones`: the headphones on, eyes closed, notes. Turning false lifts them off (`call_2`'s motion). Drawn on `headphones` (6). |
| `changeDue` | Boolean | | `change_due`: open mouth |
| `claim` | Boolean | | `claim`: shifty eyes, one brow up |
| `surprised` | Boolean | | `surprised` (story characters) |
| `board` | Trigger | | slides in from the door side, 0.6 s |
| `alight` | Trigger | | rises and fades over 0.6 s; ends invisible |
| `call` | Trigger | | `call_1`: one cup lifts, eyes open, then back to `headphones` |
| `happy` | Trigger | | squint smile and a heart |
| `targeted` | Trigger | | a `sun` halo behind |

- After playing once, a one-shot returns to the current state, except `alight`.
- Timings are HANDOFF §6.2's: `idle` 2 s with a blink, `talk` 0.5 s, `impatient_*` and `change_due`
  1 s, `sleep` 2 s, `wake` 0.67 s, `call` 0.5 s, `happy` 1 s.
- At 52 pt (a back-row face), `impatient_2`, `sleep`, `headphones`, `fight` and `claim` must each be
  recognisable.

### From a pose to the inputs

The app still picks one pose per passenger from M02's view, first match wins (research R16, unchanged):

| # | When | Pose |
| --- | --- | --- |
| 1 | getting off with a fight (`outcome`) | `fight` |
| 2 | their «أنا دافع!» is open (`claimOpen`) | `claim` |
| 3 | their stop is next and they're still owed (`nearStopPulse`) | `change_due` |
| 4 | asleep or waking | `sleep` |
| 5 | headphones on (muted) | `headphones` |
| 6 | `mood` 2 or 3 (frowning, patience gone, or the trip failed) | `impatient_2` |
| 7 | `mood` 1 | `impatient_1` |
| 8 | talking | `talk` |
| 9 | otherwise | `idle` |

It then sets that pose's input and turns the others off, so combinations the design never draws, such
as sleeping and talking, never reach the file:

| Pose | Inputs (everything else false, `mood` 0) |
| --- | --- |
| `fight` | `mood` 3 |
| `claim` | `claim` |
| `change_due` | `changeDue` |
| `sleep` | `asleep`, except while waking: then false, so the file plays `wake` |
| `headphones` | `headphones` |
| `impatient_2` | `mood` 2 |
| `impatient_1` | `mood` 1 |
| `talk` | `talking` |
| `idle` | none |

`headphones` also follows the view's headphones in every pose. The gear stays on while the passenger
wears it, and the take-off plays only when the view says they took it off.

Passengers never get `surprised` or `mood` 4; those are the story characters'.

### Triggers

Triggers come from the engine's events through `CharacterCue` (data-model.md):

| Event or cue | Trigger |
| --- | --- |
| `PassengerBoarded` | `board` |
| `PassengerAlighted` | `alight` |
| `PassengerCalled` with no `PassengerAttentive` in the same step | `call` |
| `PassengerAttentive` | none: the view's headphones go false, and the file lifts them off |
| `PassengerWoke` | none: `asleep` goes false, and the file plays `wake` |
| `ChangeDelivered{exact}` | `happy` |
| M02's `HighlightCue`, the 500 ms glow before a send | `targeted` |

### Skin tone

The file has no skin-tone input: each look keeps its drawn skin, so two passengers with the same look
look alike ([Open](#open) 3).

## Vehicles

| Item | Value |
| --- | --- |
| Artboard | `Vehicle`, 236×150, transparent, side view facing left (the direction of travel) |
| `look` | Number: 0 `tuktuk`, 1 `microbus_old`, 2 `microbus_new`, 3 `microbus_travel` |
| `driving` | Boolean: false, the body bobs (`idle`); true, the wheels spin (`drive`) |
| `brake` | Trigger: the nose dips |
| `honk` | Trigger: squash and horn lines, 0.6 s |
| Not in the file | the roof sign, which is a Flutter overlay (the loading screen's «الموقف») |

## UI animations

| Artboard | Size | View model | Properties |
| --- | --- | --- | --- |
| `CoachHand` | 100×100 | none | `tap` loop while shown |
| `Stars` | 240×100 | `Stars` | `stars` (Number 0–3): plays up to that star |
| `CoinsBurst`, `BonatBurst` | 200×200 | `Fx` | `play` (Trigger) |
| `Confetti` | 390×300 | `Fx` | `play` (Trigger) |
| `FuelGauge` | 156×110 | `Fuel` | `level` (Number 0–100): the needle |
| `GiftOpen` | 160×160 | `Fx` | `play` (Trigger) |
| `SparklePlace` | 120×120 | `Fx` | `play` (Trigger) |
| `RingShine` | 120×120 | none | loop |
| `LoadingWheel` | 80×80 | none | loop |
| `NotifBell` | 60×60 | `Fx` | `play` (Trigger) |

Sizes are the Lottie reference files' (`docs/design/lottie/ui/`). The app scales by the box it draws
into.

## Export

- Exported from Rive's free plan, with data binding. The owner decided on 2026-10-23 not to buy a
  seat (research R15). The free export carries Rive's splash as its own artboards. The Rive runtime
  has no splash logic, so a player sees it only if an artboard is opened by default or by its name,
  and the app does neither.
- Made for this project from the design's SVGs, not remixed from community files.
- Budget: about 3 MB. The delivered file is 86 KB.

## How the app uses it

- **Loading.** `riveArtProvider` decodes the file once, in the boot step `art`
  (`File.asset(…, riveFactory: Factory.flutter)`). It checks the file against this page and records
  what's wrong in `RiveArt.problems`.
  - A file that fails to load falls back to static art as a whole.
  - An artboard that is missing, or lacks its state machine, view model or a property, falls back
    alone: without `Person`, every person is static.
- **Instances.** Per passenger: an instance of `Person`, its `Passenger` state machine, and a new
  `Passenger` view-model instance bound to it, all disposed when the passenger leaves.
  - `look` is set once.
  - The pose's inputs and `headphones` are set whenever the view changes.
  - Triggers fire on their cues.
- **Reduced motion.** The file has no input that holds the effects still ([Open](#open) 2). While
  reduced motion is on, people are drawn with the static art, whose loops keep playing with their
  marks still (spec Edge Cases).
- **Tiers.** `ArtTier` decides which seats use Rive (research R18). The others, and every fallback,
  draw the static SVG with code-driven motion (research R17).
- **Contract violations.** A file that breaks this page shows its problems in the debug panel on dev
  and staging. In prod it falls back silently.

## Tests

All of these are tagged `rive`, and run after `rive_native:setup --platform linux`.

| Test | Checks |
| --- | --- |
| `test/features/trip/rive_art_contract_test.dart` | the file loads with `Factory.flutter`; every artboard above exists with its size and state machine; each view model is the artboard's default and has every property with its type |
| `test/features/trip/rive_art_goldens_test.dart` | one sheet per MVP look (data-model.md `Look`) with `idle`, `talk`, `impatient_2`, `sleep`, `headphones`, `fight` and `claim` at 84 and 52.5 pt; one sheet of the six characters in `idle` and `talk`; one of the four vehicles in `idle`. Generated on Linux; CI's run is the reference. |
| `test/features/trip/domain/poses_test.dart` (not tagged) | the pose table and the cue mapping |
| `test/features/trip/passenger_art_test.dart` (not tagged) | the pose-to-input mapping, against a fake instance; a missing artboard falls back to static |

## Open

Asked of the owner on 2026-10-23 (docs/owner-actions.md, 008.5):

1. ~~**Clean the export.**~~ Closed on 2026-10-23: the owner exports from the free plan
   ([Export](#export)).
2. **`reducedMotion`** (Boolean on `Passenger`): true keeps the loops but holds the effects still
   (z's, sweat, sparks, hearts, notes). With it, the app sets it and keeps Rive under reduced motion.
3. **Skin tone**, optional: a `skinTone` (Color) for the face and hands, so passengers with the same
   look differ. Without it, each look keeps its drawn skin.
