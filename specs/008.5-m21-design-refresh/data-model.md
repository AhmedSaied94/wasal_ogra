# Data Model: Design Refresh (M21)

M21 stores nothing new. It adds no table, no column, no preference and no tunable (spec FR-003). What
it adds is app data (generated tokens, the look table, the trip's design geometry), a few in-memory
values the screens draw from, and small presentation fields on M02's view. The engine's types are
M01's, and the trip's view, session and records are M02's
([data-model.md](../008-m02-trip-screen/data-model.md)). Neither is repeated here.

## Generated: the design tokens

`lib/core/theme/tokens/design_tokens.dart`, written by `tool/design/gen_tokens.dart` from
`docs/design/tokens.json`, and committed. The full mapping is in
[contracts/design-tokens.md](./contracts/design-tokens.md).

| Class | From | Holds |
| --- | --- | --- |
| `ColorTokens` | `color`, `dashboard`, `money_note`, `denomination`, `scene`, `character` | `static const Color`s, one per key (`groundLip`, `inkMuted`, `dashboardRaised`, `noteFare`, `denom200`, `sceneSeatHi`, `characterSkin0` …) |
| `StationColors` | `station` | four `(bg, letter)` pairs, by alighting order |
| `TypeTokens` | `type` | 13 `TextStyle`s: family, weight, size, `height`, even leading |
| `RadiusTokens` | `radius` | 11 `double`s and their `Radius`/`BorderRadius` |
| `LipTokens` | `lip` | 21 `BoxShadow`s (offset y, colour, no blur), plus each lip's depth for presses |
| `RingTokens` | `ring` | 5 rings: width, colour, inset, dashed |
| `SpaceTokens` | `space` | 9 `double`s (`s2` … `s24`) |
| `LayoutTokens` | `layout` | frame, gutter, nav, touch minimum, CTA and button sizes; `trip`: HUD, scene, dashboard, the seat table, bubble limits |
| `MotionTokens` | `motion` | `Duration`s and `Curve`s, with the pulse and shake amounts |
| `WassalTokens` | all colours | the `ThemeExtension`, read as `context.tokens` (M03's pattern) |

**Hand-written beside it:** `design_extras.dart`, the values the artboards use between tokens. Each
names its artboard (`loadingWordmark`, `pauseButtonLabel`, `failTitle`, `bubbleLipTranslucent`).

**Rules:**

- A token value changes only through `tokens.json` and the generator.
- No widget defines a colour, radius, shadow, font size, animation duration or curve. M03's raw-value
  guard checks this, extended to all of these in UI code (tasks T116), with everything under `tokens/`
  allowed.

## App data: looks

`lib/features/trip/domain/looks.dart` replaces M02's `skin_looks.dart`.

### `Look`

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | `String` | The design's art id (HANDOFF §5.3): `regular`, `hagga`, … |
| `labelKey` | `String` | ARB key of the speaker label in the log and the screen-reader text. |
| `rive` | `int` | Its `look` number in `wassal.riv`'s `Person` artboard (contracts/rive-characters.md "Looks"). |
| `svg` | `String` | `assets/illustrations/passengers/<id>.svg`. |

The MVP's twelve looks and their labels:

| `id` | Label key | Label | Why |
| --- | --- | --- | --- |
| `regular` | `tripLookPassenger` | راكب | the default look |
| `hagga` | `tripLookHajja` | الحاجة | seen |
| `sleeper` | `tripLookPassenger` | راكب | sleeping is a state the art shows, not a label |
| `effendi_200` | `tripLookEffendi` | الأفندي | seen: suit and tie |
| `student` | `tripLookStudent` | الطالب | seen |
| `headphones` | `tripLookHeadphones` | أبو سمّاعة | seen |
| `hurried` | `tripLookPassenger` | راكب | its name is a behaviour |
| `claimer` | `tripLookPassenger` | راكب | hidden |
| `group_payer` | `tripLookPassenger` | راكب | its name is a behaviour; a group keeps M02's «الشلة» in the log |
| `chatterbox` | `tripLookPassenger` | راكب | its name is a behaviour |
| `regular_customer` | `tripLookPassenger` | راكب | hidden |
| `honest` | `tripLookPassenger` | راكب | hidden |

`tripLookHeadphones` is a new ARB key. `tripLookWorker` and `tripLookYoung` go,
since no look uses them.

### Skin to look

`lookFor(String skin, Archetype archetype) → Look`, pure. First match wins:

1. `skin` is a look id: that look.
2. `skin` is in `skinAliases`: its look.

   | Skin (sample pack) | Look |
   | --- | --- |
   | `effendi_suit`, `effendi_tie` | `effendi_200` |
   | `hajja_black` | `hagga` |
   | `student_cap` | `student` |
   | `worker_blue` | `regular` |
   | `young_cap` | `group_payer` |

3. Otherwise M02's fallback, with the label `tripLookPassenger` (`archetype` → look):
   - `hajja` → `hagga`
   - `student` → `student`
   - `headphones` → `headphones`
   - `sleeper` → `sleeper`
   - `hurry` → `hurried`
   - `big_note` → `effendi_200`
   - any other → `regular`

**Validation:**

- Every alias points to a look.
- Every look has an ARB key, an artboard in the contract, and an SVG on disk (a repo test).
- No step reads a hidden archetype (`claimer`, `honest`, `regular_customer`, `group_payer`, `changer`,
  `dodger`): a test feeds every archetype with an unknown skin and expects `regular` for each hidden one.

## In memory: the trip's layout

`lib/features/trip/domain/scene_layout.dart` is rewritten. It stays pure (its inputs are numbers) and is
tested on its output ([contracts/trip-layout.md](./contracts/trip-layout.md)).

### `TripZones`

| Field | Meaning |
| --- | --- |
| `inset` | `max(viewPadding.top, 24)` |
| `hud` | 114 |
| `gap` | 8, or 0 when the screen is short |
| `scene` | what is left: `height − inset − hud − gap − dashboard + overlap` |
| `dashboard`, `overlap` | 258, 16 |
| `width` | `min(screen width, 430)`; centred above 430 |

### `SceneLayout`

| Field | Meaning |
| --- | --- |
| `width`, `height` | the scene's size in points |
| `crop` | `max(0, 444 − height)`, at most 36: points cut from the top of the cabin |
| `scale` | 1, or `height / 408` below 408 (the M02 exception, faces only) |
| `xFactor` | `width / 390` |
| `seats` | `Map<String, SeatLayout>` for the vehicle's seats |
| `hand` | the driver's hand anchor |
| `vehicle` | `micro_old` or `tuktuk` (glossary ids) |

### `SeatLayout`

| Field | Meaning |
| --- | --- |
| `seatId` | `front`, `A_r` … `C_l` (architecture §7.2) |
| `row` | `front`, `A`, `B`, `C` |
| `face` | the head's centre: `(x × xFactor, y − crop)` from the design table |
| `rigScale` | 1.0, 0.8, 0.625 (tuktuk 1.15) × `scale` |
| `faceWidth` | `84 × rigScale`; at least 80 (A, front) or 50 (C) whenever `scale` is 1 |
| `tag` | the station tag's centre and size (24, 26 or 30) |
| `hit` | the tap rect: the design's size, narrowed to the seat spacing, never under 44×44 |
| `bubbleAnchor` | the tail tip, 8 pt above the head |

## In memory: the art

### `ArtTier`

`rive` (every seat), `near_rive` (rows A and the front seat in Rive, the rest static), `static`. Its
default is `rive`, unless the A06 measurement sets `near_rive` (research R18). Dev and staging can
switch it from the debug panel, for the session only.

### `RiveArt`

What `riveArtProvider` holds after boot.

| Field | Type | Meaning |
| --- | --- | --- |
| `file` | `File?` | `wassal.riv`, or null when it is missing or fails to load |
| `usable` | `Set<String>` | the artboards that passed the contract check (`Person`, `Vehicle`, `CoachHand`, …) |
| `problems` | `List<String>` | what the contract check found, shown in the debug panel |

A null file means static art for everything. An artboard missing from `usable` falls back alone:
without `Person`, every person is static.

### `CharacterPose`

One looping state per passenger, picked by `poseFor` and set on the file as one input
([contracts/rive-characters.md](./contracts/rive-characters.md), "From a pose to the inputs"):

`idle`, `talk`, `impatient_1`, `impatient_2`, `sleep`, `headphones`, `change_due`, `fight`, `claim`,
plus `surprised` and `angry` (story characters only).

### `CharacterTrigger`

The one-shot animations, as the file's triggers: `board`, `alight`, `call`, `happy`, `targeted`. Waking
and taking the headphones off play from the view's `asleep` and `headphones` turning false.

### Functions and cues

- `poseFor(PassengerView view, {required bool failed}) → CharacterPose`, pure, with research R16's
  table.
- `CharacterCue(passengerId, CharacterTrigger)`, a new `TripCue` that M02's `mapCues` makes from the
  engine's events (research R16). The scene plays it on that passenger's art.

## M02's view: what changes

### `PassengerView`

| Field | Change |
| --- | --- |
| `look` | `SkinLook` becomes `Look`. |
| `claimOpen` | **New** `bool`: their «أنا دافع!» is waiting for an answer (`state.claims`). |

It is a presentation field. It reads the engine's state, decides no rule, and reveals nothing the spec
hides: the claim is on screen already, as its popover.

### `FailSummary`

| Field | Change |
| --- | --- |
| `brokeStoryRule` | **New** `bool`: a story trip failed by `no_fights_required` (`storyCondition == false`). The chip leads with `tripFailStoryRule`. |
| `angryFaces` | **New** `List<String>` of up to 3 passenger ids, from the engine's passenger states: `outcome == fight`, then `missedStop`, then those still aboard by seat order (`A_r` first). Drawn in their looks. |

### `TripView`

`TripView` itself has no new fields. `storyCondition` (M02) drives the HUD chip and the strip. Two of
its parts gain fields the new HUD and dashboard draw (found in implementation; M02's table in
`specs/008-m02-trip-screen/data-model.md` lists them, and `projection_test.dart` reads it):

| Type | Field | Meaning |
| --- | --- | --- |
| `StationChip` | `basePiasters` | the stop's fare before a raise: the strip strikes it through beside the new one |
| `StationChip` | `atMs` | the stop's time: its dot sits at `atMs / the last stop's atMs` (research R9) |
| `BoosterSlotView` | `activeUntilMs?` | while «الدفتر» works (`ledgerPeekUntilMs`): its badge counts the seconds down |
| `LedgerBadge` | `onFriend` | **New value** («على صاحبه», `TripEvents` block 5): a group member whose fare another of their group sent, with nothing owed to them. `paid` now means they sent their own. |

## In memory: the boot screen

### `BootProgress`

| Field | Meaning |
| --- | --- |
| `steps` | the steps in order: `settings`, `tunables`, `content`, `database`, `economy`, `art` |
| `done` | the steps finished |
| `value` | `done.length / steps.length`, from 0 to 1 |
| `failed` | the step that failed, or null; the screen shows M03's retry |

`appStartup` reports each step as it finishes. M06 adds a step.

## Assets

| Path | What | Source |
| --- | --- | --- |
| `assets/fonts/Marhey-VariableFont_wght.ttf`, `ReadexPro-VariableFont_HEXP_wght.ttf`, `OFL-*.txt` | fonts | google/fonts |
| `assets/rive/wassal.riv` | the art | owner |
| `assets/icons/*.svg` | the 92 icons | `docs/design/icons/` (synced) |
| `assets/illustrations/{passengers,characters,vehicles,screens}/*.svg` | static art and the loading art | `docs/design/illustrations/` (synced) |

Removed: `Lalezar-Regular.ttf`, `BalooBhaijaan2-VariableFont_wght.ttf` and their licences, and
`assets/rive/passenger.riv`.

## Strings (ARB)

| Change | Keys |
| --- | --- |
| New | `loadingLine1` («بنعدّ الفكة..»; the pool is the list `loadingLines(l10n)` in `boot_screen.dart`, and a new line is a new `loadingLineN` key plus one list entry), `tripStoryChip` («مشوار قصة»), `tripFailStoryRule`, `tripLookHeadphones`, `tripPauseTitle` and `tripPauseSubtitle` if `Pause`'s copy differs from M02's, the `Pause` back-to-stand label, and the screen-reader labels the artboards' `aria-label`s add |
| Removed | `tripLookWorker`, `tripLookYoung` |
| Unchanged | everything else in M02's and M03's set, including `tripStoryNoFights` and the failure causes |

Every new key has a description. The no-Arabic guard keeps Arabic out of `lib/`.

## Validation summary

| Rule | Checked by |
| --- | --- |
| Generated tokens equal `tokens.json` | `test/repo/design_tokens_test.dart` |
| No raw style values outside `tokens/` (and the trip's named motion constants) | M03's `no_raw_style_values_test.dart`, extended (tasks T116) |
| Copied SVGs equal their sources | `test/repo/design_assets_test.dart` |
| Every look complete; no hidden archetype picks a look | `test/features/trip/domain/looks_test.dart` |
| Every minimum holds at 390×844 and 360×800 | `test/features/trip/domain/scene_layout_test.dart`, `test/a11y/trip_minimum_sizes_test.dart` |
| A pose for every `PassengerView`, a trigger for every event in R16 | `test/features/trip/domain/pose_test.dart`, `cues_test.dart` |
| No old font, sticker component or `passenger.riv` named in `lib/` | `test/repo/no_retired_design_test.dart` |
