# Contract: Trip Layout, Scene and Sizes

Where everything sits on the trip screen in the new design, and the sizes it guarantees. Spec FR-019 –
FR-024, research R7 – R10. **Supersedes** M02's [scene-layout.md](../../008-m02-trip-screen/contracts/scene-layout.md),
whose rules stay where this page doesn't replace them:

- the scene is in points;
- `SceneLayout` is one pure function, read by the Flame scene and the Flutter overlays alike;
- text is never drawn in the canvas;
- every control the player plays with outside the scene is in the dashboard;
- the front seat wins over `A_r`.

Design coordinates are HANDOFF §4.2's and `layout.trip` in `tokens.json`: points in the 390×444 scene,
origin top-left.

## Zones

Portrait. The trip hides the system bars (`immersiveSticky`, M02).

| Zone | Height | Content |
| --- | --- | --- |
| Top inset | `T = max(viewPadding.top, 24)` (in immersive mode, the cutout) | nothing |
| `TripHud` | 114 | row 1, 44 tall: pause, title (with the story chip), `ReputationBar`; row 2: `StationStrip` (64, a white card) |
| Gap | 8, or less on a short screen (below) | |
| Scene | `S0 − gap`, where `S0 = H − T − 114 − 258 + 16` is the room for the gap and the scene | the Flame scene and its overlays |
| `Dashboard` | 258, drawn over the scene's last 16 | rows at 12, 62, 112, 162 and 212 from its top: hand and «حد معاه فكة؟»; tray rows 1 and 2; boosters; «آخر كلام» (36) |

- The zones never scroll, and the HUD and dashboard never shrink.
- Over 430 pt wide, the zones keep 390 and are centred, and the cabin is drawn to the screen's width
  behind them.
- On the reference frame with the design's 36 pt inset, the scene is 444 pt, its top is at y 158, and
  every zone matches the artboards to the point.

## Height

| Room `S0` | Gap | Scene | What happens |
| --- | --- | --- | --- |
| ≥ 452 | 8 | `S0 − 8` ≥ 444 | The cabin wall grows at the top. Seats keep their distance from the scene's bottom. |
| 444 – 451 | `S0 − 444` | 444 | The design, exactly. |
| 408 – 443 | 0 | `S0` | The top is cropped by `crop = 444 − S0` (at most 36): the wall and the back window, never a face or a tag. Seat y = design y − `crop`. |
| < 408 | 0 | `S0` | Cropped by 36, then the cabin, faces, tags and hit areas scale down by `S0 / 408` (`scale`). This is the exception, below. |

- **Threshold.** A screen keeps every minimum when `H ≥ T + 764`: 788 pt with T = 24, and 800 pt with
  the design's 36.
- **Phones.** The Galaxy A06 (360×800, cutout under 24 pt) has `S0 = 420`: no gap, a 420 pt scene, a
  24 pt crop, no scaling.
- **The exception.** Below the threshold, M02's approved exception to constitution XI continues
  unchanged until M07 (spec Clarifications; plan Complexity Tracking): only the scene's faces and its
  drawn sizes shrink. The HUD, dashboard, notes, bubbles, choice buttons and every hit area keep their
  minimums, since hit areas are clamped to 44×44 after scaling.

## Width

- `xFactor = w / 390`, with `w` the scene's width (320–430).
- Every design x is multiplied by `xFactor`, except the front seat's, which is kept from the end edge
  (`x = w − 40`).
- Sizes don't scale with width. Hit areas narrow to the seat spacing when they would overlap, and never
  below 44 pt.

## Seats: `micro_old`

Seat ids are architecture §7.2's (`front`, `A`–`C` × `r`, `m`, `l`). In RTL, `r` is the largest x.

| Row | Rig scale | Face width | Face centre y | x: `l`, `m`, `r` | Tag | Hit rect from the face centre (dx, dy, w×h) |
| --- | --- | --- | --- | --- | --- | --- |
| `C` (back) | 0.625 | 52.5 | 92 | 126, 195, 264 | 24 | (−34, −30, 68×80) |
| `B` (middle) | 0.8 | 67.2 | 196 | 98, 195, 292 | 26 | (−46, −36, 92×100) |
| `A` (near) | 1.0 | 84 | 308 | 62, 176, 290 | 30 | (−56, −46, 112×112); `A_r` (−56, −46, 100×80) |
| `front` | 1.0 | 84 | 392 | 350 (end edge − 40) | 30 | (−50, −48, 90×80) |
| driver's hand | — | — | 398 | 162 | — | — |

- **Face width** is the rig's head (radius 42) × rig scale. The design's drawn radii (25, 32, 41) are
  inside it.
- **Tags** sit at `face + (−38, +46) × rig scale`, and the front seat's at `face + (−32, +18)`
  (`C-Trip`). A tag is a circle of its size with a 2.5 pt white border. `hot` adds a 3 pt `danger` ring
  outside and pulses.
- **Bubbles.** The anchor is the tail tip, `face − (0, 42 × rig scale + 8)`.
- **Notes.** A note's anchor is `face + (0, 50 × rig scale)` (the hands), and the driver's is the hand.

## Seats: `tuktuk`

| Row | Rig scale | Face width | Face centre y | x: `l`, `m`, `r` | Tag | Hit rect |
| --- | --- | --- | --- | --- | --- | --- |
| `A` | 1.15 | 96.6 | 308 | 62, 195, 328 | 30 | (−60, −52, 120×120), narrowed to the spacing |

The tuktuk's cabin has one bench, and its windows show the street on both sides (`Tutorial`).

## Guaranteed sizes

On the reference frame (390×844) and on the A06 (360×800), at text scales 1.0 and 1.3:

| Element | Minimum | At 390 | At 360 |
| --- | --- | --- | --- |
| Near-row and front faces | 80 | 84 | 84 (the front shows 82 before the edge) |
| Back-row faces | 50 | 52.5 | 52.5 |
| A passenger's hit area | 44×44, none overlapping | 68×80 back | 63.7×80 back |
| Money note | 40×24, digits 15 | 42×26, 16 | same |
| Fallen note's hit area | 44×44 | 44×44 | same |
| Choice answer | 44×44 | 73–125×44 | same |
| Bubble text | 15 | 16, not scaled | same |
| Dashboard targets | 44×44 | 87×44 cells | (360 − 24 − 18) / 4 = 79.5×44 |
| Any text | 12 | 12 (`label`) | same |

`test/features/trip/domain/scene_layout_test.dart` checks `SceneLayout` on 390×444, 360×420 and
430×452. `test/a11y/trip_minimum_sizes_test.dart` checks the rendered trip on both surfaces. M02's
bottom-third rule is checked as before: outside the scene and the dashboard, only pause and the debug
icon are tappable.

## Text scale

| Where | Scale |
| --- | --- |
| `TripHud`, `StationStrip`, `Dashboard`, `StationTag`, `LedgerBadge`, `MoneyNote` | clamped to 1.0–1.15 |
| `SpeechBubble` | none (16 pt, M02) |
| Banners, choice popovers, cards, the hint bubble | 1.0–1.3 (M03) |

## Layers, bottom to top

| # | Layer | Drawn by |
| --- | --- | --- |
| 1 | Cabin: wall, floor, back window, side windows with the moving street and the next station's sign in its colour, benches (cached picture) | Flame |
| 2 | Passengers, back row first; the story character in the front seat when content adds one | Flame: `PassengerAvatar` (Rive or static) |
| 3 | The driver's hand | Flame |
| 4 | Effects: shake (layers 1–3), the `targeted` halo, glints | Flame |
| 5 | `MoneyNote`s and fallen notes | Flutter `Flow` |
| 6 | Hit areas (transparent, with semantics) | Flutter |
| 7 | `StationTag`s and `LedgerBadge`s, `ChoicePopover`, the dispute's faces | Flutter |
| 8 | `SpeechBubble`s, the hint (بلية, his bubble, the hand), `EventBanner`, the story condition strip | Flutter |
| 9 | Cards: `Pause`, `Fail`, the `AppDialog`s, the debug panel | Flutter, modal |

## Bubbles

- At most 2 visible. Each shows for at least the line's `trip_bubble_min_ms_<line_id>` (M02).
- The tail points at the speaker. The bubble is clamped 10 pt inside the scene, and kept out of the
  story strip's top 56 pt. When the top is cropped, a back-row bubble may overlap its speaker's hair,
  never the eyes.
- At most 60% of the scene's width; text wraps.
- Two bubbles never overlap: the second moves up or across.

## The hint

- **بلية** is drawn at the scene's bottom-end corner, 96×110, overlapping the dashboard's top by about
  30 pt (`Tutorial` block 6, `x = w − 102`).
- **His bubble** is a `SpeechBubble.character`, end-aligned 14 pt from the start edge and 104 from the
  end, with its tail toward him.
- **The hand** (56×64) points at the hint's target rect, which comes from the live layout.
- There is no scrim. The hint takes no touch.

## Motion

From HANDOFF §6.5 and M02:

| Motion | Length | Reduced motion |
| --- | --- | --- |
| A note's hop | the engine's `duration_ms` (the line's tunable), on a slight arc, easeInOut | unchanged |
| Bubble pop | 180 ms, easeOutBack(1.4) from the tail | none |
| `hot` tag pulse | 1 ↔ 1.18, 600 ms loop | steady ring |
| Countdown chip under 8 s | pulse, 500 ms loop | steady |
| Getting off | up 12, fade, 600 ms | a fade |
| Shake (bump, fight) | 6 pt, 300 ms | none |
| `EventBanner` | slide 12 pt + fade, 200 ms; holds 4 s | a fade |
| Street in the windows | M02's speeds | no parallax: one layer |
| Booster active countdown | each second | unchanged |

The constants come from `MotionTokens`. The hop times stay tunables.

## Golden surfaces

| Surface | Size | Inset | Runs |
| --- | --- | --- | --- |
| reference | 390×844 | 36 | artboard goldens and layout tests; every M02 trip state |
| a06 | 360×800 | 24 | M02's trip states; minimum sizes |
| small | 360×640 | 24 | the exception: HUD, dashboard and hit areas keep their sizes; no overlap |

M02's 360×744 surface is retired: it falls under the exception now (research R20).
