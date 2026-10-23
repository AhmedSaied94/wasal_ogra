# Contract: Layout, Scene and Sizes

Where everything sits on the trip screen, what draws it, and the sizes it guarantees. `SceneLayout`
is a pure function in `lib/features/trip/domain/`; both the Flame scene and the Flutter overlays read
its output, so they line up by construction (research R3).

## Bands

Portrait only. The trip hides the system bars (`immersiveSticky`); the display cutout's top inset
still applies.

| Band | Height | Content |
| --- | --- | --- |
| Top bar | 110 pt (plus the cutout inset) | pause (right), line and trip number (middle), reputation (left); the station strip under them |
| Scene | the rest: `H − 110 − 230 + 16` | the Flame scene and its overlays |
| Dashboard | 230 pt, drawn over the scene's last 16 pt | hand + «حد معاه فكة؟», drawer (2 rows), boosters, «آخر كلام» |

- The bands never shrink. Their touch targets (≥ 44×44 pt) and text (≥ 12 pt) hold on every screen,
  including M03's 360×640 surface.
- Text scale is clamped to 1.3 inside the trip.
- Every control the player plays with outside the scene is in the dashboard, the bottom third of the
  screen (FR-018). Inside the scene: passengers, dropped notes and choice answers. The top bar holds
  only the controls that stop play: pause and, on internal builds, the debug icon. These are
  constitution XI's (1.4.0) exemptions; `trip_minimum_sizes_test.dart` checks that nothing else
  outside the scene is tappable above the bottom third.

## The scene's sizes

At a scene height of **420 pt or more** (a screen at least **744 pt** tall: 110 + 420 + 230 − 16),
`SceneLayout` guarantees:

| Element | Minimum |
| --- | --- |
| Face in the near row (row `A`, the front seat, the tuktuk's row) | 80 pt wide |
| Face in a back row (`B`, `C`, later `D`) | 50 pt wide |
| A passenger's hit area | 44×44 pt, not overlapping another's |
| Money token | 40×24 pt, amount at 15 pt |
| Dropped note's hit area | 44×44 pt |
| Bubble text | 15 pt (`TypeTokens.body`; bubbles aren't scaled) |
| Choice answer button | 44×44 pt |

Below 420 pt the scene shrinks and faces scale with it, under their minimums; the bands, tokens,
bubbles and buttons keep theirs (spec Edge Cases, research R15). That is the approved, time-boxed
exception to constitution XI in plan.md's Complexity Tracking, which M07 removes. The 360×800 Galaxy
A06 has a 456 pt scene.

## Seats

`SceneLayout(seats, size)` gives each seat a face rectangle, a hit rectangle, a bubble anchor (above
the head) and a token anchor (the hands). The camera looks from the windshield at the passengers'
faces.

| Vehicle | Rows, bottom to top | Notes |
| --- | --- | --- |
| `tuktuk` | `A` (3 seats) | one near row across the width; faces about 100 pt |
| `micro_old` | `front` (bottom right), `A` (3), `B` (3), `C` (3) | `A` is the largest row; each row further back is smaller and higher |

- Columns follow the seat's `col` from the viewer's right to left: `r`, `m`, `l` (RTL).
- Rows further back are scaled down by depth, never below the back-row minimum.
- Where the front seat's face covers part of `A_r`, the front seat's hit area wins, and `A_r` keeps a
  44×44 pt area of its own.
- Empty seats are drawn as empty seats.
- The windows take the top of the scene; the stations' signs and the traffic pass in them.
- The driver's hand rests at the bottom left of the scene, above the dashboard's overlap.

## Layers, bottom to top

| # | Layer | Drawn by |
| --- | --- | --- |
| 1 | Cabin, seats, windows and their street | Flame (static parts cached as a picture) |
| 2 | Passengers, back row first, so nearer rows cover farther ones | Flame (`RiveComponent` or the stand-in) |
| 3 | The driver's hand | Flame |
| 4 | Effects: shake (moves layers 1–3), glints, the highlight glow | Flame |
| 5 | Money tokens and dropped notes, with their amounts | Flutter `Flow`, repositioned each frame |
| 6 | Passenger hit areas (transparent, with semantics) | Flutter |
| 7 | Choice answers, the station-patch pulse, ledger badges | Flutter |
| 8 | Bubbles, بلية's hint, the fare banner, the story condition strip | Flutter |
| 9 | Cards: pause, failure, dispute, booster purchase, empty fuel, debug panel | Flutter dialogs over everything, modal for the screen reader too (the layers under a card leave the semantics tree) |

The top bar and the dashboard are Flutter widgets outside the scene. The dashboard is drawn after the
scene, so it covers the scene's last 16 pt.

## Bubbles

- Anchored above the speaker's head, with the tail toward them.
- Moved inside the scene, with 8 pt margins, when the anchor is near an edge; the tail still points at
  the speaker.
- At most 60% of the scene's width; text wraps, at least 15 pt.
- Two visible bubbles never overlap: the second moves up or across.

## Motion

| Motion | Length | Reduced motion |
| --- | --- | --- |
| A token's hop | the engine's `duration_ms`, interpolated | unchanged (it carries the game) |
| Highlight before a throw | 500 ms | shown, without the pulse |
| Bubble pop | 150 ms | none |
| Shake (bump, fight) | 300 ms | none |
| Walk in or out | 600 ms | a fade |
| Fare banner | in 250 ms, holds 3 s, out 250 ms | a fade |
| Countdown pulse (warning) | 1 s cycle | a steady orange |
| Street in the windows | 60 pt/s; 15% of it in traffic (with stopped cars), 3× on the open road | unchanged |
| A roadside wave | 1.2 s from the pickup, while they walk in | the arm doesn't swing |
| A note's glint on the floor | twinkles; fades over the note's last second | without the twinkle |
| «هنا» star, a raised price on the strip | the star pulses on a 1 s cycle; the price pops in over 250 ms | steady; no pop |

These are presentation constants in `trip_motion.dart`, not tunables (research R23).

## Goldens and size checks

| Surface | Size | Checks |
| --- | --- | --- |
| reference | 390×844 | trip goldens, every FR-054 state; minimum sizes on `SceneLayout` and the render |
| a06 | 360×800 | trip goldens for the idle trips; minimum sizes |
| compact | 360×744 | the smallest compliant screen; minimum sizes |
| small (M03) | 360×640 | M03's existing checks: touch targets, text, no exception |

Each trip golden runs in RTL with both digit styles and the stand-in passengers. The Rive character
has its own goldens ([rive-character.md](./rive-character.md)).
