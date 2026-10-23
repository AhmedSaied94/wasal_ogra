# Contract: Checking Screens Against the Design

How each artboard in scope is checked: a sample state, a golden beside the design's PNG, and a layout
test against its measured boxes. Spec FR-039 – FR-041, SC-001, SC-004, SC-010; research R20. This is
the routine every later screen follows (spec US7).

## Pieces

| Piece | Where | What |
| --- | --- | --- |
| Sample builder | `test/design/samples/<artboard>.dart` | Builds the screen in the artboard's sample state with fakes: a scripted `TripModel` for trip artboards (M02's helpers), a fixed `BootProgress` for `Loading`, a component composition for `Components`, `Tokens` and `States`. Sample text may be Arabic: the no-Arabic guard covers `lib/` only. |
| Golden | `test/goldens/design/<artboard>_goldens_test.dart`, images in `test/goldens/design/goldens/<artboard>_<digits>.png` | the sample at the artboard's size, RTL, `arabicIndic` and `western` digits, text scale 1.0. Under `test/goldens/`, so CI's `update_goldens` run covers them. |
| Layout test | `test/design/<artboard>_layout_test.dart` | each tap box in `docs/design/boxes/<artboard>.json`, found in the widget tree, within ±2 pt |
| Box reader | `test/design/boxes.dart` | parses a boxes file; matches by `label`, else by `text`; the skip and pairing tables |
| Compare image | `build/design_compare/<artboard>.png` | the design's PNG and the golden side by side, written only with `--dart-define=DESIGN_COMPARE=true`, for the PR |

## Surfaces

| Artboard | Size | Top inset | Notes |
| --- | --- | --- | --- |
| phone artboards | 390×844 | 36 (the design's status bar) | `States`: 390×1400, scrolled |
| `Components` | 1200×1700 | 0 | a test composition of the shared components in the board's places |
| `Tokens` | 1200×1220 | 0 | a test composition of the token swatches; no taps |

The same samples also run at 360×800 (inset 24) for the minimum-size checks
([trip-layout.md](./trip-layout.md#guaranteed-sizes)), without a layout test, since the boxes are
measured at 390.

## Matching a box

For each box with `role: "tap"`:

1. If the box is in the artboard's **skip** table, skip it, with the reason printed.
2. If the box is in the artboard's **pairing** table, find the widget by the paired label.
3. Otherwise find the `Semantics` node whose label equals the box's `label`. With no `label`, use the
   node whose label contains the box's `text`.
4. Expect exactly one node. Its rect, in logical pixels from the top-left of the surface, must be
   within ±2 pt of `(x, y, w, h)` on every side.

A failure prints the box id, the label, both rects and the artboard. **Every tappable in the sample
must be matched by a box or listed as app-only** (the debug icon on internal builds), so a control
the design doesn't have can't slip in.

## Skips and pairings in this feature

| Artboard | Box | Kind | Why |
| --- | --- | --- | --- |
| `C-Trip` | «للنموذج بس: افتح شاشة النتيجة» | skip | prototype navigation |
| `Loading` | the full-screen link «كمّل» | skip | prototype navigation |
| `Fail` | the unlabelled 322×66 button at y 320 | skip | the ad revive, M11's. Its place stays empty, so the boxes under it keep their positions. |
| `C-Trip` | the ten passenger boxes | pairing | The design's labels name the type and who owes («المستعجل، نازل الكوبري، ليه باقي»). The app's follow spec FR-036: the look, the stop, and «ليه باقي» only while hot. Each box is paired with its seat's label in the sample. |
| `TripEvents`, `StoryTrip`, `Tutorial` | tray cells labelled only «×٣» | pairing | the design's sample drops the denomination; the app's label is «جنيه، معاك ٣», as in `C-Trip` |
| `Tutorial` | — | scope | only the 11 HUD and dashboard boxes and the hint (بلية's head, his bubble, the hand: HANDOFF blocks 5–7, as rects) are checked. The coach scrim, the hole and the locked-boosters bar are M07's. |

A later feature removes its skip when it builds the thing (M11 removes the `Fail` one).

## What a golden may differ in

The owner reviews each golden beside its PNG (SC-010). These differences are expected and are listed
in the PR:

| Artboard | Difference | Why |
| --- | --- | --- |
| all trip artboards | passengers drawn by the static art in goldens | the Rive files have their own goldens (rive-characters.md) |
| `C-Trip`, `TripEvents` | no light garland | phase 2 cosmetic |
| `StoryTrip` | no story title or front-seat character; the condition strip carries M02's text | content has no fields for them (research R11) |
| `StoryTrip`, `C-Trip` | station letters أ ب ج د | M02 R16 |
| `Fail` | no ad revive | M11 |
| `TripEvents` | no ad badge on «زحمة» | M11 |
| `Pause` | «عيد المشوار» restarts directly | M02 FR-011 |
| `Tutorial` | riders on the tuktuk's seats, not the drawing's two positions; no scrim | trip-layout.md; M07 |

Any other visible difference is a bug, unless the owner accepts it in the PR.

## Every later screen

A feature that builds a screen from an artboard adds:

- its sample builder;
- its golden at the artboard's size, in both digit styles;
- its layout test, with its skips and pairings and the reason for each.

It also lists the expected differences in its PR, with the compare images. The delivery plan's
"Design sources" table names the artboard.
