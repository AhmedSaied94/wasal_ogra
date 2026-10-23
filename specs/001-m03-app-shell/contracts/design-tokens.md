> **Superseded by** [specs/008.5-m21-design-refresh/contracts/design-tokens.md](../../008.5-m21-design-refresh/contracts/design-tokens.md) from M21. This page records what M03 built.

# Contract: Design Tokens («ستيكر الميكروباص»)

The only source of visual values in the app. Widgets read these through the theme; a literal color,
radius, border width, shadow or duration in widget code fails review. Covers FR-005 – FR-011 and FR-016a.
This palette **supersedes** ux-spec «الألوان» (Clarifications, 2026-10-18). FR-013 updates the ux-spec.

## Colors

| Token (Dart) | Name | Hex | CIE L\* | Role |
| --- | --- | --- | --- | --- |
| `shams` | شمس | `#FFD23F` | 85.9 | Screen background, the «حد معاه فكة؟» button, launch background |
| `hibr` | حبر | `#1D1A2B` | 10.4 | Borders, text, hard shadows, dark station letters |
| `waraq` | ورق | `#FFFFFF` | 100 | Cards, bubbles, light station letters, text on dark fills |
| `tablouh` | تابلوه | `#2A2633` | 16.1 | Dashboard and bottom-bar background |
| `primary` | أزرق | `#1A4B8C` | 32.1 | Primary buttons, exact money, progress |
| `danger` | برتقالي | `#F2542D` | 57.5 | Danger: station approaching, fight, shortage |
| `gold` | ذهبي | `#F5B301` | 77.1 | Coins and stars |
| `station1` | محطة ١ | `#3B2A6B` | 22.5 | 1st drop-off station of a trip (white letter) |
| `station2` | محطة ٢ | `#0F766E` | 44.5 | 2nd (white letter) |
| `station3` | محطة ٣ | `#5FAE4E` | 64.4 | 3rd (ink letter) |
| `station4` | محطة ٤ | `#A9DDF3` | 85.3 | 4th (ink letter) |
| `badgeNew` | — | alias of `danger` | 57.5 | The «new» dot fill (2 pt `hibr` outline) |
| `fare` | أخضر | `#7ACC6C` | 75.1 | A fare on its way to the driver (M02); change on its way back is `primary` |
| `bubbleWarn` | — | `#FFD9A8` | 88.8 | Warning bubble: a stop near, short change, impatience (M02) |
| `bubbleFight` | — | `#F2894A` | 67.5 | Fight bubble: a fight, an accusation, a missed stop (M02) |
| `bubbleThanks` | — | `#BFE3F7` | 88.3 | Thanks bubble: thanks, a tip, excess returned (M02) |
| `shirtEffendi` | — | `#8A8F99` | 59.3 | Stand-in passenger shirt: the effendi family (M02) |
| `shirtStudent` | — | `#EDF1F5` | 95.0 | Stand-in shirt: the student family (M02) |
| `shirtWorker` | — | `#24508F` | 34.2 | Stand-in shirt: the worker family (M02) |
| `shirtHajja` | — | `#2B2633` | 16.2 | Stand-in shirt: the hajja family (M02) |
| `shirtYoung` | — | `#C23B2E` | 45.4 | Stand-in shirt: the young family (M02) |
| `shirtPlain` | — | `#D9C9A3` | 81.4 | Stand-in shirt: an unknown skin's fallback (M02) |

Station colors are assigned by stop order within a trip, never by station identity. A trip has at most
four drop-off stations (spec, Assumptions).

## Palette checks (automated, FR-011)

The palette test computes WCAG 2.1 relative luminance and CIE L\* (D65) from the hex values above and
fails the build on any violation.

**Must differ in lightness (ΔL\* ≥ 18):**

| Pair | ΔL\* |
| --- | --- |
| station1 – station2 | 22.0 |
| station2 – station3 | 19.9 |
| station3 – station4 | 20.9 |
| station1 – station3, station1 – station4, station2 – station4 | 41.9, 62.8, 40.8 |
| primary – danger | 25.3 |
| fare – primary (a fare and change in flight) | 42.9 |
| bubbleWarn – bubbleFight | 21.3 |
| shirtEffendi – shirtWorker, shirtStudent – shirtYoung (same accessory, `shirtPairsToSeparate`) | 25.1, 49.6 |

**Text on fill (≥ 4.5:1; ≥ 3:1 only for text ≥ 18.66 px bold or 24 px regular):**

| Text on fill | Ratio | Used by |
| --- | --- | --- |
| hibr on shams | 11.78 | Screen text |
| hibr on waraq | 17.01 | Cards, secondary button |
| waraq on primary | 8.65 | Primary button |
| waraq on tablouh | 14.75 | Bottom bar, unselected tab |
| shams on tablouh | 10.22 | Bottom bar, selected tab |
| hibr on danger | 4.92 | Text on danger fills (white is 3.45, which fails) |
| hibr on gold | 9.18 | Coin and star badges |
| waraq on station1 / station2 | 12.14 / 5.47 | Station letters |
| hibr on station3 / station4 | 6.20 / 11.60 | Station letters |
| hibr on fare | 8.65 | The amount on a fare token (M02) |
| hibr on bubbleWarn / bubbleFight / bubbleThanks | 12.75 / 6.84 / 12.59 | Bubble text (M02) |

**Non-text contrast (≥ 3:1), «new» dot:** passes on every background through its fill or its outline:
on tablouh the fill gives 4.27; on shams the outline gives 11.78; on waraq the outline gives 17.01.

**Hue separation:** every station color's hue is at least 30° away from the danger hue (12°). The
station hues are 256°, 175°, 109° and 198°.

A new color, or a new text-on-fill pairing used anywhere in the app, must be added to these tables and
to the test in the same change.

## Typography

| Token | Face | Size (pt) | Weight | Use |
| --- | --- | --- | --- | --- |
| `display` | Lalezar | 32 | 400 | Big titles |
| `headline` | Lalezar | 24 | 400 | Screen titles |
| `button` | Lalezar | 20 | 400 | Primary and secondary buttons |
| `title` | Baloo Bhaijaan 2 | 18 | 700 | Card titles |
| `body` | Baloo Bhaijaan 2 | 15 | 500 | Body text (matches the 15 pt bubble minimum) |
| `label` | Baloo Bhaijaan 2 | 13 | 600 | Tab labels, small labels |
| `caption` | Baloo Bhaijaan 2 | 12 | 500 | Smallest allowed text |

- Fonts ship as assets under `apps/mobile/assets/fonts/`, together with their SIL OFL license texts.
- Baloo Bhaijaan 2 is a variable font (weights 400–800).
- System text scaling is clamped to 1.0×–1.3× at the app root (FR-030).

## Shape

| Token | Value (pt) | Use |
| --- | --- | --- |
| `borderCard` | 2.5 | Cards, buttons, sheets |
| `radiusCard` | 18 | Cards, sheet top corners |
| `radiusControl` | 14 | Buttons |
| `shadowCard` | 4 | Hard shadow offset on cards (no blur) |
| `shadowPrimary` | 5 | Hard shadow offset on the primary button (no blur) |
| `badgeSize` | 12 | «New» dot outer diameter, outline included |
| `badgeOutline` | 2 | «New» dot outline width |
| `minTouch` | 44 | Minimum touch target edge |

Hard shadows fall down and toward the end side: bottom-left in RTL, bottom-right in LTR.

## Motion

| Token | Value | Use |
| --- | --- | --- |
| `fast` | 150 ms | Press feedback, fades |
| `screen` | 250 ms | Page transitions |
| `sheet` | 250 ms | Sheet open and close |

All values are under ⅓ s (FR-022). When the phone's reduce-motion setting is on, page and sheet
transitions become a fade of `fast` or less, with no slide or bounce.

## Space

`xs 4` · `s 8` · `m 12` · `l 16` · `xl 24` · `xxl 32` (pt). Screen side gutter is `l`.

## Shared components (FR-008)

| Component | Spec |
| --- | --- |
| `PrimaryButton` | `primary` fill, `waraq` text in `button` style, `hibr` border `borderCard`, `radiusControl`, `shadowPrimary`. Minimum height 52, full width by default. Pressed: shadow drops to 0 and the button shifts by the shadow offset. |
| `SecondaryButton` | Same as `PrimaryButton`, but with a `waraq` fill and `hibr` text. |
| `StickerCard` | `waraq` fill, `hibr` border `borderCard`, `radiusCard`, `shadowCard`. |
| `WassalBottomBar` | `tablouh` fill, four equal cells, each cell is the full touch target (≥ 44×44). Each tab has an icon and a `label` text. Selected: `shams` icon and label. Unselected: `waraq`. Sits above the system gesture area. |
| `NewDot` | `badgeNew` fill, `badgeOutline` `hibr` outline, `badgeSize` total, at the icon's top-end corner. Screen-reader label «جديد» (ARB key `newBadgeLabel`). |
