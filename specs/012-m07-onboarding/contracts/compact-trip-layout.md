# Contract: The Compact Trip Layout

The trip screen below the threshold, which closes M02's approved exception to constitution XI. Spec
FR-040–FR-043, User Story 5; research R19. It extends 008.5's
[trip-layout.md](../../008.5-m21-design-refresh/contracts/trip-layout.md), whose rules hold wherever
this page doesn't replace them. Above the threshold nothing changes.

The numbers are a first proposal, checked by the size tests. If a minimum can't hold for `micro_old`
at 360×640, the implementation stops and asks the owner (research R19 "Risk").

## Profiles

`T = max(viewPadding.top, 24)`, `H` the screen height, `w` the scene width.

| Profile | When | HUD | Gap | Dashboard | Scene |
| --- | --- | --- | --- | --- | --- |
| `regular` | `H ≥ T + 764` | 114 | 0–8 | 258 | 008.5's |
| `compact` | `H < T + 764` | 72 | 0 | 226 | `H − T − 72 − 226 + 16` |

At 360×640 with T = 24, the compact scene is **334 pt**. At 360×720 it is 414 pt.

`TripZones` (`domain/scene_layout.dart`) gains `profile`. `minCompliantHeight(inset)` stays
`inset + 764` and now picks the profile, instead of marking the exception.

## `TripHud`, compact (72)

| y (from the inset) | Height | Content |
| --- | --- | --- |
| 0 | 8 | padding: room for the reputation line and its chip above the card |
| 8 | 64 | Start edge: the pause `IconCircleButton` (44, centred vertically). Then 8 pt, then `StationStrip` (64: dots, letters, names, prices, the vehicle marker, the countdown chip) filling the width. |
| 5 | 6 | The `ReputationBar` becomes a 6 pt line centred on the strip card's top edge, over the track's length (`primary`, `danger` under 40%). Its semantics label is unchanged. «تحت ٤٠٪» shows as a chip centred on the line at the strip's end when low. |

- **Changed in implementation:** the line runs along the card's *top* edge, not its bottom, and the
  HUD's padding is 8 above the card and none under it. The bottom of the 64 pt card holds the fares
  and the countdown chip, which a line there would cross; on the top edge it crosses nothing, and the
  8 pt keep the chip under the inset.
- The trip's title («خط الحي · المشوار ٢») moves to the pause card's header in the compact profile
  (spec FR-041 as amended).
- At 360 wide the strip is 360 − 16 × 2 − 44 − 8 = 276 pt. Station labels never clip: they keep one
  line each and are pushed apart within the card. **Changed in implementation:** so four long names
  (the release pack's `line_hay`: العشرين، الطالبية، التعاون، المريوطية), a raised fare and the
  countdown fit, the compact strip leaves out the depot's «الموقف» label and shows a raised fare as
  its new fare alone, in its `danger.soft` pill (the regular strip keeps the old one struck through).
  None of today's names (nine letters at most) needs a second line.
- Internal builds keep the debug button beside pause, so their strip is 224 pt. There the worst case
  above can reach over the debug button; prod builds are tested to fit.

## `Dashboard`, compact (226)

| y (from its top) | Height | Row |
| --- | --- | --- |
| 8 | 20 | `LastWordsLog`, one line (the newest), 12–13/600 `dashboard.text`; still a live region |
| 32 | 44 | `HandSlot` + `CallChangeButton` |
| 80 | 44 | `Tray` row 1 |
| 128 | 44 | `Tray` row 2 |
| 176 | 44 | `BoostersRow`, or `BoostersLockedBar` |
| 220 | 6 | padding |

- The four control rows fill the bottom 194 pt: at 640 pt the controls start at y 446, inside the
  bottom third (y ≥ 426.7).
- The dashboard still overlaps the scene's last 16 pt and keeps its 28 pt top radius.

## Seats

- **The scene is 408 pt or more** (`H ≥ T + 690` in the compact profile): 008.5's tables, with its
  crop.
- **The scene is under 408 pt:** the compact tables below, anchored to the scene's bottom. Every y
  is `design y − (334 − scene)`, so a taller scene adds wall at the top.

### `micro_old`, compact

| Row | Rig scale | Face | Face centre y (scene 334) | x: `l`, `m`, `r` | Tag |
| --- | --- | --- | --- | --- | --- |
| `C` (back) | 0.6 | 50.4 | 46 | 126, 195, 264 (× `w/390`) | 24 |
| `B` (middle) | 0.66 | 55.4 | 122 | 98, 195, 292 | 26 |
| `A` (near) | 0.952 | 80 | 206 | 62, 176, 290 | 30 |
| `front` | 0.952 | 80 | 284 | `w − 40` | 30 |
| driver's hand | — | — | 290 | 162 | — |

### `tuktuk`, compact

| Row | Rig scale | Face | Face centre y | x |
| --- | --- | --- | --- | --- |
| `A` | 1.15 | 96.6 | `scene − 136` | 62, 195, 328 (× `w/390`) |

### Rules carried over

- **Tags** at `face + (−38, +46) × scale` (front `(−32, +18)`).
- **Bubble anchors** at `face − (0, 42 × scale + 8)`, clamped 10 pt inside the scene. A back-row
  bubble may overlap its speaker's hair, never the eyes.
- **Notes** at `face + (0, 50 × scale)`.
- **Hit rects** are 008.5's × (compact scale / design scale), then narrowed where two would overlap
  (to the midpoint), never below 44×44. The front seat wins over `A_r`.
- **Under 334 pt of scene** (screens under 640 pt, outside the supported range): the compact table
  scales by `scene / 334`, and hit areas are clamped to 44×44, as M02 did.

## Guaranteed sizes (compact)

At 360×640 (T 24) and 360×720 (T 24), at text scales 1.0 and 1.3:

| Element | Minimum | Compact |
| --- | --- | --- |
| Near-row and front faces | 80 | 80 |
| Back-row faces | 50 | 50.4 |
| A passenger's hit area | 44×44, none overlapping | ≥ 44×44 after narrowing |
| Money note | 40×24, digits 15 | 42×26, 16 |
| Bubble text | 15 | 16 |
| Dashboard targets | 44×44 | (w − 24 − 18) / 4 × 44 |
| Any text | 12 | 12 |
| Play controls | the bottom third | the bottom 194 pt of 640 |

## The coach and the hint in the compact profile

- بلية (96×110) keeps its corner. In the tuktuk it covers no seat.
- In `micro_old`, the hint (not the coach: tutorial trips are on the tuktuk) may overlap the front
  seat's face. M02's rule stays: the hint takes no touch.
- `CoachAnchors` reports the compact rects, so the hole follows (coach.md).

## Tests

- **`test/features/trip/domain/scene_layout_test.dart`:**
  - the profile switch at `T + 764`;
  - the compact tables at scenes 334 (360 and 390 wide) and 407;
  - the 408 boundary;
  - no overlapping hit areas;
  - every face at its minimum.
- **`test/a11y/trip_minimum_sizes_test.dart`:** the `small` surface (360×640, T 24) is no longer
  exempt; a `mid` surface (360×720, T 24) is added; every US1–US6 case at 1.0 and 1.3.
- **The bottom-third test:** every tappable outside the scene and the HUD's pause and debug buttons
  sits at y ≥ 2H/3, on all four surfaces.
- **Goldens:** the trip goldens' `small` images are regenerated, and `mid` ones are added for US1
  and the `Tutorial` state.
- **The coach:** a coach step on `small` and `mid` at 1.0 and 1.3 (lesson 1 on the fixture's
  `line_hay.02`): the hole, بلية, the hand and the bubble fully on screen, and bubble text ≥ 15 pt
  (FR-042).
- **Owner check:** approve the compact look from the 360×640 goldens (owner-actions).

## Documents

- `docs/architecture-mobile.md` §8: the threshold now picks the compact profile, and the exception is
  closed.
- `specs/008.5-m21-design-refresh/contracts/trip-layout.md` "The exception": a pointer here.
- `specs/008-m02-trip-screen/plan.md` Complexity Tracking: the entry is marked closed by M07.
