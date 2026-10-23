# وصّل الأجرة — Design handoff for Claude Code

> **Project overrides: read [README.md](README.md) first.** In this repo, animation stays on
> **Rive**, which the constitution locks: §6's Lottie runtime does not apply, and `lottie/` is a
> motion reference only. Identifiers come from the architecture glossary (§3), not from the art
> names here. On behaviour, merged features' decisions win over this file.

Style C, "soft cartoon". Covers every screen of the first release (النسخة الأولى, 48 artboards with their states), the phase 2 and public-launch screens that are designed, the design system, characters, passengers and vehicles.

## Contents

- 0. Read this first
- 1. What changed from `ux-spec.md`
- 2. Tokens → Flutter theme
- 3. Components
- 4. Trip screen geometry and rendering
- 5. Characters, passengers, vehicles
- 6. Animation: Lottie pipeline (replaces Rive)
- 7. Navigation map
- 8. Accessibility
- 9. Decisions and open questions
- 10. Build order and acceptance
- 11. Screens
  - Screens: onboarding, home, pre-trip, result
  - Screens: trip, lines, vehicles
  - Screens: apartment, story, shop
  - Screens: daily return, settings, shared states, later phases
  - Screens: states added during handoff

## 0. Read this first

**This package replaces the visual parts of `docs/ux-spec.md`.** Build the app so that every screen matches its render in `png/` when run on a 390×844 logical-pixel device. Behaviour that isn't described here still comes from `ux-spec.md` and `architecture-mobile.md`.

### Source of truth, in order

1. **`screens/<Artboard>.html`** — exported from the Claude Design canvas. Exact sizes, colours, radii, shadows, copy and icon art. Open one in a browser at 390 px wide to inspect it with dev tools.
2. **`png/<Artboard>.png`** — the same HTML rendered at 2x. Use it for visual comparison (golden tests, §10).
3. **This document** — routes, components, dynamic data, interactions, states, motion, accessibility. §11 has one section per screen.
   `boxes/<Artboard>.json` is the HTML measured in a browser (every box's position, size, colour, font), for when you need a number without reading CSS.
4. `ux-spec.md` (Arabic) for game rules and behaviour this document doesn't restate. Its «النظام البصري» section (colours, fonts, outlines, dark bottom bar) is **superseded** — see §1.

If the HTML and this document disagree on a *visual* value, the HTML wins. If they disagree on *behaviour*, this document wins. Either way, note the conflict in the PR description.

The living design is the canvas «وصّل الأجرة — Design»: https://claude.ai/artifact/9h9GpTSHVQXvsHUmgP8ixZ (pages: النسخة الأولى · مرحلة ٢ والإطلاق · النظام والمكوّنات). The files here are a snapshot of it.

### Package layout

```text
docs/design/
├── HANDOFF.md                 # this file
├── tokens.json                # every colour, type style, radius, lip, layout and motion value
├── manifest.json              # artboard → html/png/size/page
├── screens/                   # 48 standalone HTML artboards (+ fonts.css, fonts/ for the browser only)
├── png/                       # 48 renders at 2x
├── boxes/                     # every visible box per artboard, measured: x, y, w, h, colour (+token), font, radius, shadow
├── icons/                     # 92 icons as SVG + manifest.json + index.html contact sheet
├── illustrations/             # SVG art: passengers/, characters/, passenger_states/, vehicles/, screens/
├── lottie/                    # 46 Lottie animations (passengers, characters, vehicles, ui) + index.html player
└── tools/                     # scripts that regenerate everything above from the canvas (README inside)
```

### Things in the HTML to ignore

- Anything labelled «للنموذج بس» (prototype only), e.g. the invisible 44 px link at the bottom of `C-Trip` that jumps to the result screen.
- `href="X.html"` links are the prototype's click-through. They tell you **where a tap goes** (mapped to routes in §7), not how to implement navigation.
- `aria-label`s are real: reuse them as Flutter `Semantics` labels.

### Sample data

Every number and name in the artboards is **sample data**: player names (أحمد, حمادة), balances, prices, station prices (٤٫٥ / ٧ / ٩), trip counts, leaderboard rows, dates. Store prices are drawn as «[سعر المتجر]» and must come from the store at runtime. Real values come from the trip engine, content packs and Remote Config (architecture §7, §13, §14).

## 1. What changed from `ux-spec.md`

| Area | ux-spec «النظام البصري» | Now (this package) |
| --- | --- | --- |
| Overall look | "ستيكر الميكروباص": yellow ground, thick black outlines | Soft cartoon: pale sky ground `ground`, white cards, **no outlines**, depth from solid "lip" shadows |
| Fonts | Lalezar + Baloo Bhaijaan 2 | **Marhey** (display, buttons) + **Readex Pro** (text, numbers) |
| Primary | #1F5FA8 | `primary` #1A4B8C (lip #0F2F5A) |
| Danger | #C2410C | `danger` #F2542D with **ink text only**; `danger.ink` #C23A17 for red text on white |
| Station colours | one colour per named station | four colours **by stop order** on the line (`station[0..3]`), letter always shown |
| Cards | white, 2.5 outline, radius 18, shadow 4 | white, radius 22, lip 5 `ground.lip`, no outline |
| Bottom bar | dark | white, radius 28 top, active tab = primary pill (see `BottomNav`) |
| Characters | Rive | **Lottie** (§6; architecture §2/§8 updated to match) |
| Trip scene | logical 390×470 | **390×444** (min 420), see §4 |

Minimum sizes from the UX test are unchanged and enforced: back-row face ≥ 50, near-row face ≥ 80, bubble text ≥ 15, money note ≥ 40×24 with 15+ digits, touch ≥ 44×44, any text ≥ 12.

## 2. Tokens → Flutter theme

All values are in `tokens.json`. Generate `lib/core/theme/tokens.g.dart` from it (a small script in `tools/` is fine) so values are never retyped by hand. Names map 1:1: `color.primary.lip` → `AppColors.primaryLip`, `type.display.l` → `AppText.displayL`, `lip.card` → `AppLip.card`.

### 2.1 Colour (summary)

| Token | Hex | Use |
| --- | --- | --- |
| `ground` / `ground.lip` | #E8F4FB / #C7DDEA | page background / lip under white cards, switch-off track |
| `paper` | #FFFFFF | cards, sheets, bubbles |
| `track` / `outline` | #E3EEF5 / #D5E6F0 | progress tracks, dividers / locked-card ring |
| `locked.bg` | #F4F8FB | locked cards (never use opacity for locked) |
| `ink` / `ink.2` / `ink.muted` | #1D1A2B / #4A4558 / #5B6475 | text: primary / secondary / captions |
| `icon.off` | #8A93A6 | inactive icons only, never text |
| `sun` / `sun.lip` / `sun.soft` | #FFD23F / #D9A800 / #FFF1C2 | splash, call-change button, sun CTAs / its lip / tip & offer cards |
| `primary` / `primary.lip` / `primary.soft` | #1A4B8C / #0F2F5A / #DCEBFA | CTAs, progress, active tab / lip / change notes, selected chips |
| `danger` / `danger.ink` / `danger.soft` | #F2542D / #C23A17 / #FFD9CC | out-of-fuel CTA, fight bubble, banners (ink text) / red text, danger lip / warn bubble, blocked note |
| `gold` | #F5B301 | coins, stars, gold progress (savings) |
| `dashboard.*` | #2A2633 · #3A3646 · #6B6678 · #D9D4E2 · #A9A3B5 | trip dashboard bg · raised · line · text · muted |
| `scrim` | rgba(29,26,43,.6) | behind sheets and dialogs (coach mark .62) |

Stations, money notes, denominations, scene and character colours are in `tokens.json` (`station`, `money_note`, `denomination`, `scene`, `character`).

### 2.2 Type

Bundle the fonts as assets (download the TTFs from Google Fonts: *Marhey* and *Readex Pro*, both OFL; the `screens/fonts/` woff2 files are browser-only subsets). Register families `Marhey` (500/600/700) and `ReadexPro` (400/500/600/700).

| Token | Font | Weight | Size | Line height | Use |
| --- | --- | --- | --- | --- | --- |
| `display.xl` | Marhey | 700 | 32 | 1.2 | result title, splash |
| `display.l` | Marhey | 700 | 28 | 1.2 | screen titles |
| `button.xl` | Marhey | 700 | 27 | 1.0 | 64 px CTA |
| `display.m` | Marhey | 700 | 22–26 (24) | 1.2 | sheet and dialog titles |
| `button.l` | Marhey | 700 | 21 | 1.0 | 54–58 px buttons |
| `display.s` | Marhey | 700 | 18 | 1.2 | card titles |
| `quote` | Marhey | 600 | 16–19 (17) | 1.35 | character quotes «…» |
| `number.l` | Readex Pro | 700 | 20 | 1.1 | hand total, prices |
| `bubble` | Readex Pro | 700 | 16 (min 15) | 1.2 | speech bubbles |
| `row` | Readex Pro | 500–700 | 15 | 1.35 | list rows |
| `body` | Readex Pro | 500 | 14 | 1.5 | body copy |
| `caption` | Readex Pro | 500 | 13 | 1.4 | meta lines |
| `label` | Readex Pro | 600 | 12 | 1.2 | chips, tab labels — **smallest size anywhere** |

- Set `leadingDistribution: TextLeadingDistribution.even` on every style so Flutter places Arabic glyphs inside the line box the way CSS does. Without it Marhey text sits low inside buttons.
- When a screen uses a size between tokens (e.g. 17, 19, 21, 26 in a few places), use the HTML value; don't round to the nearest token.
- Text scaling: respect the system setting up to 1.3× on normal screens; clamp the trip HUD, dashboard and station tags to 1.15× so the trip stays playable.

**Digits.** Arabic-Indic by default (`١٢٣`), decimal `٫`, thousands `٬` (e.g. `١٬٢٤٠`, `١٥٫٥`). A setting switches to Western digits (`Settings`). Format every number through one helper (`formatNumber(num, {decimals})`) that reads that setting; never interpolate raw numbers into strings.

### 2.3 Shape, depth, rings

- **Radius:** `tray` 14 · `m` 16 · `bubble` 18 · `l` 20 · `card` 22 · `xl` 24 · `scene` 26 · `sheet` 28 (top corners) · `pill` 999. Smaller radii (5–12) appear on chips and bars; take them from the HTML.
- **Lip (the only shadow style):** `BoxShadow(offset: Offset(0, lip.y), blurRadius: 0, color: lip.color)`. Cards `0 5 #C7DDEA`, primary CTA `0 6 #0F2F5A`, sun `0 4 #D9A800`, danger `0 6 #C23A17`, tray cell `0 3 #C9C4D3`, bottom nav `0 -4 #D5E6F0`.
- **Pressed state:** translate the widget down by its lip and set the lip to 0, 80 ms ease-out; release reverses. Every tappable with a lip does this. Add `HapticFeedback.selectionClick()` on press (respect the haptics setting).
- **Rings (inset borders)** are allowed only for: locked cards (2 px `outline`), empty tray cells and empty slots (2 px dashed `ground.lip` / `dashboard.line`), selected choice (3 px `primary`), hot station tag (3 px `danger`, outside). In Flutter use `Border.all(strokeAlign: BorderSide.strokeAlignInside)`; dashed via a `CustomPainter`.
- **New-dot:** 12 px circle, `danger` fill, 2 px `ink` ring — the one outline in the system. Placed at the top-end corner of the icon it marks.
- **Disabled:** 45% opacity, no lip, no press animation.

### 2.4 Layout

- Design frame 390×844. **Gutter 16.** Bottom nav 88 (includes 18 bottom padding), shown only on Home, Lines, Apartment, Shop.
- The design's 36 px top inset stands for the status bar: use `max(MediaQuery.padding.top, 24)` instead of a fixed 36. Bottom: add `MediaQuery.padding.bottom` under the nav and under sheet CTAs.
- Widths: everything is fluid between the gutters; cards stretch, grids keep their column count (2, 3 or 4 as drawn).
- Heights: screens taller than 844 in the design (Result 1100, Shop 1240, Settings 1420, States 1400, Event 1200) **scroll**; headers stay pinned where the HTML pins them (`position: sticky` / outside the scroll area).
- Short screens (< 780 high): Home's street scene shrinks first (min 220), then the screen scrolls. The trip screen never scrolls — see §4.
- Wide phones (> 430): keep the 390 design width centred for the trip screen; other screens just stretch.

### 2.5 HTML → Flutter cheat-sheet

| HTML/CSS in the artboards | Flutter |
| --- | --- |
| `dir="rtl"` and child order | App runs with `Directionality.rtl` (locale `ar`). Keep children in the **same order as the HTML**: the first child is at the right in both. Use `EdgeInsetsDirectional`, `AlignmentDirectional`, `PositionedDirectional`. |
| `display:flex; flex-direction:column; gap:N` | `Column(spacing: N)` (Flutter ≥ 3.27) |
| `flex: 1` / `flex: none` | `Expanded` / fixed child |
| `box-shadow: 0 Npx 0 C` | lip `BoxShadow`, blur 0 |
| `box-shadow: inset 0 0 0 Wpx C` | inside `Border` (ring) |
| `border-radius: 999px` | `StadiumBorder` / `BorderRadius.circular(999)` |
| `text-overflow: ellipsis; white-space: nowrap` | `maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false` |
| `position:absolute; top:…` inside a relative box | `Stack` + `PositionedDirectional` |
| inline `<svg>` icon (24×24) | `icons/<name>.svg` via `flutter_svg`, tinted with `ColorFilter.mode(color, BlendMode.srcIn)` when the icon is mono |
| large inline `<svg>` art | `illustrations/…svg` via `flutter_svg`, or the Lottie asset named in §6 when it animates |
| `<a href>` / `<button>` | `InkWell`-free tappable (`GestureDetector` + the press animation from §2.3); no Material ripples anywhere |
| `aria-label` | `Semantics(label: …)` |

## 3. Components

Build these once in `lib/core/ui/` (or `lib/core/widgets/`), with a widgetbook/gallery page that reproduces `screens/Components.html`. Screens must use them rather than restyling raw widgets. Sizes are logical px.

### 3.1 Buttons

| Component | Spec | States |
| --- | --- | --- |
| `AppButton.primary(size: xl)` | h 64, radius 22, `primary`, lip `0 6 primary.lip`, label `button.xl` white; optional trailing cost chip (sun pill h 32, `−١` + fuel icon) | default · pressed (lip 0, +6) · disabled (45%, no lip) · loading (label replaced by 3-dot pulse, not tappable) |
| `AppButton.primary(size: l)` | h 54–58, radius 20, lip `0 5 primary.lip`, label `button.l` | same |
| `AppButton.secondary` | h 54–60, white, lip `0 5 ground.lip` (or 2 px `ground.lip` ring on white backgrounds, as in `Result`), label `button.l` ink | same |
| `AppButton.sun` | `sun` fill, lip `0 4 sun.lip`, ink label; used for «حد معاه فكة؟» and sun CTAs | same |
| `AppButton.danger` | `danger` fill, **ink** label, lip `0 6 danger.ink` | same |
| `AppButton.tertiary` | text-only, `primary` 700, ≥ 44 high hit area | pressed = 70% opacity |
| `RewardedAdButton` | h 66, radius 22, `primary`, lip `0 6 primary.lip`, `ad_play_on_primary` icon + two lines: title Marhey 700 22 + benefit line `label` white (e.g. «اقبض ×٢» / «+١٧٠ بدل ٨٥») | adds **ad not ready** state: icon `ad_not_ready`, label «الإعلان مش جاهز» , disabled look — see `States` |
| `IconCircleButton` | 44×44 circle; on `ground` pages white with lip `0 4 ground.lip`; inside sheets `ground` fill, no lip | icons: `close`, `back` (points right in RTL), `pause`, `edit`, `copy` |

### 3.2 Pills, badges, chips

| Component | Spec |
| --- | --- |
| `CurrencyPill(kind)` | h 44, radius 999, white, lip `0 4 ground.lip`, padding 0 6 0 12, value `number` 16/700 + 24 px icon (`coin` / `bonat` / `fuel`). Fuel variant shows `٤/٥` (15/700) over the refill timer (12/500 `ink.muted`). Fuel 0 → `danger.soft` background with lip `danger.soft.lip`. Some screens use a 40 px tall variant (take it from the HTML). Bonat pill opens the Shop; fuel pill opens the Fuel sheet (§9.1). |
| `CountBadge` | `primary` fill, white 12/700, radius 999, min 22×18 — e.g. `٢/٣` on Tasks |
| `NewDot` | 12 px, `danger`, 2 px `ink` ring |
| `StatusChip` | h 22–24, radius 999, 12/700. Variants: new «جديد» (`danger` fill, ink text), story «مشوار قصة» (`sun`), done «خلص» (`primary.soft`, `primary` text), offline «محتاج نت» (`track`, `ink.2`) |
| `PriceTag` | currency icon + number; store prices show the localized store string (placeholder «[سعر المتجر]») |
| `Stars` | three stars; earned = `gold` with `sun.lip` lip, missing = outline `icon.off` |

### 3.3 Controls and containers

| Component | Spec |
| --- | --- |
| `AppSwitch` | track 52×30, radius 999, padding 3, knob 24 white; on = `primary` track, knob at the **end** side (left in RTL); off = `ground.lip` track, knob at the start. Lives in a white row h 52, radius 16, label 15. Tap anywhere on the row toggles. |
| `Segmented(sun|primary)` | container white, radius 14, padding 4, gap 4; segments h 40, radius 10, 13 px; active = `sun` with ink 700 (rooms in Apartment) or `primary` with white 700 (Garage tabs, Settings options); inactive `ink.2` 600 |
| `AppTextField` | h 52, white, radius 16, 2 px inside ring `ground.lip`, padding 0 14, text 18/600 ink; focused ring 2 px `primary` |
| `AppCard` | `paper`, radius 22, lip `0 5 ground.lip`, padding 14–16 |
| `ListRow` | h 52–70, title `row` + optional caption, trailing chevron `back` mirrored / switch / price |
| `ProgressBar` | h 8–12, radius 999, track `track`; fill `primary` (trip, tasks), `gold` (savings), `sun` (event) |
| `ScreenHeader` | h 52: `IconCircleButton.back` + title `display.l` (+ optional trailing pills) |
| `Sheet` | rises from the bottom, radius 28 top, white, grabber 44×5 `outline` centred near the top, title Marhey 700 22–26, `IconCircleButton.close` at the end side. Dismiss: drag down > 25% or fling, ✕, system back, tap on scrim. Scrim `scrim`. |
| `AppDialog` | centred card, radius 26, padding 20, scrim; dismiss only through its buttons (no tap-outside for spend confirmations) |
| `EventBanner` | full-width minus gutters, h 54, radius 18, `danger` fill, lip `0 4 danger.ink`, padding 0 14, warning icon, title Marhey 700 17 ink + subtitle 12/600 ink. Auto-hides after 4 s. |
| `OfflineBanner` | h 40, radius 14, `dashboard.bg`, padding 0 12, white 12.5/600 text + `wifi_off` icon in `sun` |
| `UndoToast` | h 52, radius 18, `dashboard.bg`, padding 0 8 0 14, white 13 text, trailing sun button h 38 radius 12 «رجّع ٣» with seconds left; 3 s; only for bonat purchases under 50 (≥ 50 asks to confirm instead) |
| `BottomNav` | h 88, white, radius 28 top, lip `0 -4 outline`, 4 equal tabs: الموقف · الخطوط · الشقة · المحل. Active: `primary` pill 60×34 with white glyph, label `primary` 13/700. Inactive: 24 px `icon.off` glyph, label `ink.muted` 13/600. New-dot on the icon's top-end corner. |
| `DailyCircle` | 56 circle (white, lip `0 4 ground.lip`; event variant filled `station[0]`) + label chip under it (white, 12/700) + optional `NewDot` or `CountBadge` | 
| `ComicPanel` | white card radius 22 with art, speaker label (12/700 `ink.2`) and bubble text `quote` |
| `CoachMark` | scrim `scrim.coach` with a rounded hole (r 18) around the single tappable target, 4 px `sun` ring around the hole, pointing hand (`lottie/ui/coach_hand`), Belya bubble (`SpeechBubble.character`). Only the target receives taps. |

### 3.4 Trip components

| Component | Spec |
| --- | --- |
| `TripHud` | h 114 under the top inset: row 1 (h 44): pause `IconCircleButton`, line + trip title `display.s`, `ReputationBar`; row 2: `StationStrip` (h 64, white card radius 20) |
| `ReputationBar` | label «السمعة» 12/700 + bar 90×10; fill `primary`; turns `danger` under 40% with chip «تحت ٤٠٪» |
| `StationStrip` | track with a vehicle marker (sun chip with microbus icon) moving start→end; one dot per station (station colour + letter, white letter on stations 1–2, ink on 3–4), name 12/700 and price 12/600 under it; passed part `primary`. **Next station**: 3 px `danger` ring + countdown chip `١٨ث` (`danger` fill, ink text) that pulses under 8 s. |
| `StationTag` | circle on the passenger's shoulder: back 24 · middle 26 · near 30, station colour + letter (12–14/700), 2.5 px white border. `hot` (station next and change still owed): extra 3 px `danger` outer ring + pulse 1→1.18, 600 ms loop. `alightHere` «نزّلني هنا»: star variant used by the coach. |
| `SpeechBubble` | white, radius 18, padding 3 14 5, `bubble` text (16/700), tail = 14×14 square rotated 45° poking 6 px out toward the speaker's head, lip `0 4 rgba(26,75,140,.18)`. Variants: normal; warn (`danger.soft`, lip `rgba(242,84,45,.35)`); fight («إنت بتتهمني؟!»: `danger` fill, ink text, lip `0 4 danger.ink`); thanks (`primary.soft`, `primary` text); character (name label 12/700 over `quote` text, used for Belya/story characters). Max **2** visible; others queue; each lasts ≥ 3.5 s (`trip_bubble_min_ms_<line>` from Remote Config). Clamp inside the scene. |
| `MoneyNote` | h 26, min-w 42, padding 0 9, radius 7, lip `0 3` in the kind's lip colour, digits 16/700; kinds from `money_note` tokens: fare (green, travels toward the driver), change (blue, travels to the back), blocked (`danger.soft` + `؟` badge, waiting on a chain-breaker), fallen (sun ring, after a bump; tap within 3 s), in hand. Hops seat → seat along the column; per-hop time by line 1.3 / 1.1 / 0.9 s. |
| `LedgerBadge` | under a face for 5 s; 12/700, line-height 18, radius 999, padding 0 8: paid «دافع» (`primary`, white text), not yet «لسه» (`danger`, ink text), on friend «على صاحبه» (white, ink text) |
| `ChoicePopover` | white container radius 18, padding 5, gap 6, lip `0 4 rgba(26,75,140,.25)`, next to the passenger; two buttons h 44 radius 14 14/700: «ماشي» (`ground` fill) and «لأ، ما دفعتش!» (`danger`, ink text) |
| `Dashboard` | h 258, radius 28 top, `dashboard.bg`, overlaps the scene by 16. Rows: `HandSlot` + `CallChangeButton` (h 44) · `ChangeTray` (2×4) · `BoosterButton` ×4 (h 44) · `LastWordsLog` (h 36). |
| `HandSlot` | dashed 2 px `sun` ring, radius 14, h 44; shows what's in hand as mini notes (min-w 26 × 20, radius 5, denomination colour, 12/700) and coins (24 circles), then `= total` (20/700, white) at the end side; empty state «فاضية» `dashboard.muted`. Break mode: «اختار ورقة ١٠+» in `danger`. |
| `CallChangeButton` | `AppButton.sun` h 44, «حد معاه فكة؟» + remaining `×٢` + speaker icon; 0 left = disabled |
| `TrayCell` | h 44, white, radius 14, lip `0 3 #C9C4D3`, 14/700; denomination glyph (coin = 26 circle, note = small rect, in its `denomination` colour) + count `×٣`. States: full · empty (2 px dashed `dashboard.line`, text `dashboard.text`, not tappable) · breakable (in break mode: ≥ 10 notes get a 3 px `danger` ring) · pressed (lip 0) |
| `BoosterButton` | h 44, `dashboard.raised`, radius 14, icon + name 12/600 `dashboard.text`; badge pinned at top −9 / end −4 (pill, padding 0 7, 12/700): count `×١` (sun), price `٨ بون` (primary), ad «إعلان» (primary), active timer `٤ث` (sun ring, `primary` fill) |
| `LastWordsLog` | two lines 12–13/600 `dashboard.text`, newest at the bottom («آخر كلام») |
| `TripScene` | Flame `GameWidget`, see §4 |

## 4. Trip screen geometry and rendering

Frame stack (390 wide): top inset 36 → `TripHud` 114 → gap 8 → **scene 444** → `Dashboard` 258 (−16 overlap) = 844.

On other devices: HUD and dashboard keep their heights; the scene gets the rest. Scene scale `s = min(width / 390, sceneHeight / 444)`. If the scene would be shorter than 420 logical px, crop the top of the cabin wall (never the passengers) instead of scaling further. Never scroll the trip screen.

### 4.1 Layers

| Layer | Tech | Content |
| --- | --- | --- |
| Cabin & street | Flame (`TripScene`) | wall `scene.wall`, floor, benches (`scene.seat` / `seat.hi`), side windows with parallax street (buildings, next-station sign that grows as it approaches), bump shake |
| Passengers | Flame + Lottie (`PassengerAvatar`) | one per seat, state segment from the engine every tick (§6) |
| Money in flight | Flame | `MoneyNote` sprites moving seat → seat |
| Overlays | Flutter widgets positioned from scene coordinates × `s` | `StationTag`, `SpeechBubble`, `LedgerBadge`, `ChoicePopover`, fallen-note hit areas, coach mark |
| HUD & dashboard | Flutter | as §3.4 |

Text never renders inside Flame: Arabic shaping and accessibility are better in Flutter overlays.

### 4.2 Seat positions (scene coordinates, origin top-left of the 390×444 scene)

| Row | Face radius | Rig scale | Face centre y | Face centre x | Tag | Tap target |
| --- | --- | --- | --- | --- | --- | --- |
| Row D (new microbus only, 2 seats) | 20 | 0.5 | 40 | 160 · 230 | 24 | 60×70 |
| Back (row C) | 25 | 0.625 | 92 | 126 · 195 · 264 | 24 | 68×80 |
| Middle (row B) | 32 | 0.8 | 196 | 98 · 195 · 292 | 26 | 92×100 |
| Near (row A) | 41 | 1.0 | 308 | 62 · 176 · 290 | 30 | 112×112 |
| Front seat | 41 | 1.0 | 392 | 350 | 30 | 90×80 |
| Driver's hand | — | — | 398 | 162 | — | — |

Row D is not drawn in the artboards (the new microbus is phase 2); positions above follow the same perspective and must be checked against `illustrations/vehicles/seatmap_*.svg`. Tuktuk uses only the near row. Seat ids follow architecture §7.2 (`front`, `A`–`D`, columns `r`/`m`/`l`); in RTL the `r` column is x = 290/292/264.

The exact drawing (benches, window frames, passengers, tags, bubbles and notes as placed in a busy moment) is `screens/C-Trip.html`; variations are `TripEvents`, `StoryTrip` and `Tutorial`. Their per-screen sections below give every position.

## 5. Characters, passengers, vehicles

### 5.1 Base rig (all people)

Every person is built from one rig, head centre at (0,0), designed at near-row size (head r 42) and scaled per row:

- torso `M-46 108 Q-50 52 -18 46 L18 46 Q50 52 46 108 Z` (shirt colour)
- head `circle r 42` (skin), hair `M-42 -2 Q-44 -48 0 -48 Q44 -48 42 -2 Q28 -24 0 -24 Q-28 -24 -42 -2 Z`
- eyes at (±15, 6) r 5.5 `ink`, highlights at (−13,4)/(17,4) r 1.8 white
- blush at (±26, 18) r 7, `blush` 60%
- mouth: smile `M-12 22 Q0 32 12 22` (stroke 4.4) · talk `M-13 18 Q0 36 13 18 Z` (filled)
- hijab variant: `M-52 12 Q-52 -56 0 -56 Q52 -56 52 12 L52 60 Q0 74 -52 60 Z` with the face circle r 32 at (0, 4)
- accessories are separate layers: headphones (band + `gold` cups), glasses, cap, tie, bags, kids, luggage

Skins `character.skin[0..3]`, hair `character.hair[0..1]`, grey hair `#D9D4E2`.

### 5.2 Story characters (`illustrations/characters/`)

| id | Name | Look | Role |
| --- | --- | --- | --- |
| `usta` | الأسطى | dark quiff, `primary` shirt, white collar | the player; name is the player's |
| `salma` | سلمى | coral hijab #E8846B with sun dotted trim, `primary` top, yellow pencil | the bride |
| `bride_father` | أبو العروسة | grey side hair, rectangular glasses, grey moustache, dark suit, blue tie | strict, kind; hardest trips |
| `bride_mother` | أم العروسة | purple hijab #7C6FB0, gold earrings and necklace, mauve top #B5838D | list details, requests |
| `moallem` | المعلم | white skullcap, grey sideburns, big grey moustache, galabeya #8FA3B8, red scarf | owns the tuktuk; tutor |
| `belya` | بلية | sun cap worn backwards, gap tooth, red shirt | the hint voice (coach) |

### 5.3 Passenger types (`illustrations/passengers/`)

| id (`skin`) | Type | Mechanic | First line |
| --- | --- | --- | --- |
| `regular` | العادي | pays exact or with a bigger note | الحي |
| `hagga` | الحاجة | lots of metal change, slow passing | الحي |
| `sleeper` | النايم | breaks the chain until woken | الحي |
| `hurried` | المستعجل | low patience, wants change immediately | الحي |
| `effendi_200` | الأفندي أبو ٢٠٠ | big note on a small fare | الجامعة |
| `student` | الطالب | half fare with card | الجامعة |
| `headphones` | أبو سمّاعة | call twice or route around him | الجامعة |
| `claimer` | «أنا دافع!» | claims he paid | الجامعة |
| `group_payer` | «خلّيها عليّا» | pays for a group | الجامعة |
| `chatterbox` | الرغّاي | distracts his neighbour, slows the row | الجامعة |
| `changer` | اللي بيفك | offers to break a big note | السوق |
| `bags_lady` | الست بالشنط | bag fare, slower passing | السوق |
| `dodger` | المتهرب | gets off without paying | السوق |
| `mother_kids` | الأم والعيال | one kid full fare, one half | المصيف |
| `big_family` | العيلة الكبيرة | one man pays for six | المصيف |
| `traveler` | المسافر | far stop, big money | السفر |
| `regular_customer` | الزبون الدايم | comes back, tips | high reputation |
| `honest` | الأمين | returns extra change | any |

### 5.4 Passenger states = animation segments

Drawn on `screens/Characters.html` (second row) and exported to `illustrations/passenger_states/`. The engine's passenger state (architecture §7.6) picks one segment per passenger each tick:

| Segment | Look | Loop | Trigger |
| --- | --- | --- | --- |
| `idle` | smile, blink every 3–5 s | loop | default |
| `talk` | open mouth, tongue | loop while a bubble is shown | `PassengerSpeaks` |
| `impatient_1` → `impatient_2` | angry brows, frown, sweat drop | loop | patience < 50% → < 25% |
| `sleep` / `wake` | head tilted 18°, closed eyes, "z z" | loop / one-shot | asleep / woken |
| `headphones`, `call_1`, `call_2` | eyes closed, gold headphones; first call lifts one cup, second removes | loop / one-shot | chain-breaker |
| `change_due` | open mouth + `hot` tag pulse | loop | station next and change owed |
| `fight` | red face, angry brows, gritted teeth, sparks | loop + screen shake 300 ms | `PassengerAlighted{fight}` / false accusation |
| `alight` | moves up 12 and fades over 0.6 s | one-shot | `StationReached` |
| `board` | slides in from the door side (right) | one-shot | `PassengerBoarded` |
| `targeted` | sun halo 0.5 s | one-shot | money aimed at this seat |
| `happy` | squint smile, heart | one-shot | `ChangeDelivered{exact}` |
| `claim` | shifty eyes, one brow up | loop | `ClaimRaised` |

### 5.5 Vehicles (`illustrations/vehicles/`, `screens/Vehicles.html`)

| id | Vehicle | Seats (scene layout) | Price | Lines | Phase |
| --- | --- | --- | --- | --- | --- |
| `tuktuk` | توكتوك المعلم | 3 — near row only | free (not owned) | الحي | MVP |
| `microbus_old` | ميكروباص قديم | 10 — rows C, B, A × 3 + front | ٢٬٠٠٠ ج | الجامعة | MVP |
| `microbus_new` | ميكروباص جديد | 12 — row D (2) + C, B, A × 3 + front | ٥٬٠٠٠ ج | السوق · المصيف | Phase 2 |
| `microbus_travel` | ميكروباص سفر | 12 + luggage on the roof (seen through the back window) | ١٢٬٠٠٠ ج | السفر | Public launch |

Side views face left (direction of travel). The line sign on the roof (sun pill with the line name, as on Home) is a Flutter overlay, not baked into the art. Liveries: old = white + `primary` stripe + `danger` pinstripe; new = white + teal #3E9C8F stripe + sun pinstripe; travel = white + `station[0]` stripe + sun pinstripe + gold curtains.

## 6. Animation: Lottie pipeline (replaces Rive)

### 6.1 Runtime

| Use | Package | Notes |
| --- | --- | --- |
| UI animations in Flutter screens | `lottie` (pure-Dart renderer) | `Lottie.asset(..., controller:)`; play named segments from markers |
| Passengers, characters in the trip scene | `flame_lottie` (`LottieComponent`) | one component per seat; see the performance gate below |
| State machines (`.lottie`) | `dotlottie_loader` + `lottie` | **not in MVP**; only for UI after a device test |

Pin exact versions at kickoff and record them in `research.md`. Architecture §2, §5 (`assets/lottie/` replaces `assets/rive/`), §8 and the Rive decision in §25 are updated in `architecture-mobile.md`.

**Segments are Lottie markers.** Each animated asset carries named markers (`"markers": [{"cm": "idle", "tm": 0, "dr": 60}, …]` at 30 fps). Code plays a segment with `composition.getMarker('idle')` and animates the controller between the marker's start and end (loop for loop segments, once for one-shots, then return to `idle`).

**The animations already exist.** `lottie/` holds 46 generated Lottie files, built straight from the design SVGs by `tools/gen_people.py` and `tools/gen_ui.py`, and checked frame by frame in a Lottie player (`lottie/index.html` plays every file and every segment). They are production-usable placeholders in the exact art of the design: an animator can later polish any file in Lottie Creator as long as the **marker names and layer names stay the same** (§6.2), so code never changes.

- One file per passenger type and per character (each type keeps its own drawn clothes, hair, props), all sharing the same rig, layer names and markers.
- Skin tones can still vary at runtime: `ValueDelegate.color(['**', 'skin', '**'], value: …)`. Hide an accessory with `ValueDelegate.opacity(['**', 'acc_headphones', '**'], value: 0)` (e.g. after أبو سمّاعة takes his headphones off with `call_2`).
- The content pack's `skin` slug (architecture §3.6) maps to `lottie/passengers/<skin>.json`.

### 6.2 Layer and marker contract

Passengers and characters: 30 fps, artboard 200×240, head centre at (100, 100), drawn at near-row scale (head r 42). The main composition holds one precomp layer (`passenger` or `character`, carries bob / board / alight motion) and `fx_halo` under it. Inside the precomp:

| Layer | Parent | Content |
| --- | --- | --- |
| `body`, `head`, `face` | — | null layers: body anchor, head rotation (sleep tilt, shakes), face scale (smaller for hijab faces) |
| `acc_back` | body | anything drawn behind the torso (kids of العيلة الكبيرة, luggage of المسافر) |
| `shirt` | body | torso and collar, tie, straps |
| `acc_hijab` | head | hijab / hood behind the face |
| `skin` | head | face circle |
| `fx_flush` | head | red face during `fight` / `angry` |
| `hair` | head | hair |
| `blush` | face | cheeks |
| `acc_face` | head | glasses, moustache, caps, eyebrows, skullcap, sunglasses… |
| `eyes`, `eyes_closed`, `eyes_sleep`, `eyes_happy`, `eyes_shifty` (+ `eyes_wide` for characters) | face | eye variants, one visible per frame |
| `brows_angry`, `brow_raised` | face | expression brows |
| `mouth_smile`, `mouth_talk`, `mouth_frown`, `mouth_teeth`, `mouth_sleep`, `mouth_big`, `mouth_smirk` (+ `mouth_o` for characters) | face | mouth variants, one visible per frame |
| `acc_headphones` | head | أبو سمّاعة only: lifts on `call_1`, comes off on `call_2` |
| `acc_front` | body | props in front: bags, notes, coins, kid on the lap, watch |
| `fx_sweat`, `fx_z`, `fx_sparks`, `fx_heart` | head | effects driven by segments |

Markers:

| Marker | Frames | Type |
| --- | --- | --- |
| `idle` | 0–59 | loop (blink at 40–46, 1.5 px breathing bob) |
| `talk` | 60–74 | loop (mouth flaps) |
| `impatient_1` | 75–104 | loop (angry brows, frown, sweat, small head wiggle) |
| `impatient_2` | 105–134 | loop (stronger shake, dripping sweat) |
| `sleep` | 135–194 | loop (head tilted 18°, "z z" rising) |
| `wake` | 195–214 | once → `idle` |
| `headphones` | 215–274 | loop (eyes closed, nodding to music) |
| `call_1` | 275–289 | once → `headphones` (headphones lift, eyes open) |
| `call_2` | 290–304 | once → `idle` (headphones come off) |
| `change_due` | 305–334 | loop (talking, angry brows, hopping) |
| `fight` | 335–364 | loop (red face, teeth, sparks, shake) |
| `happy` | 365–394 | once → `idle` (squint smile, heart pops) |
| `claim` | 395–424 | loop (shifty eyes, raised brow, smirk) |
| `targeted` | 425–439 | once (sun halo behind) |
| `board` | 440–457 | once → `idle` (slides in from the door side) |
| `alight` | 458–475 | once → remove (rises 12 and fades) |
| `surprised` | 476–505 | characters only, loop |
| `angry` | 506–535 | characters only, loop |

Vehicles: 236×150, markers `idle` (0–35, body bob), `drive` (36–47, wheels spin, loop), `brake` (48–65, nose dips), `honk` (66–83, squash + horn lines). The line sign is a Flutter overlay, not in the file.

### 6.3 Asset list (in `lottie/`, copy to `assets/lottie/`)

| File | Used on | Markers |
| --- | --- | --- |
| `passengers/<skin>.json` × 18 (`regular`, `hagga`, `sleeper`, `hurried`, `effendi_200`, `student`, `headphones`, `claimer`, `group_payer`, `chatterbox`, `changer`, `bags_lady`, `dodger`, `mother_kids`, `big_family`, `traveler`, `regular_customer`, `honest`) | trip scene, PreTrip new-passenger card, LineDetails | §6.2 |
| `characters/<id>.json` × 6 (`usta`, `salma`, `bride_father`, `bride_mother`, `moallem`, `belya`) | Intro, Tutorial coach, StoryTrip front seat, Fail, Result quote, SceneViewer, Requests, Returning, RoomDone | §6.2 + `surprised`, `angry` |
| `vehicles/<id>.json` × 4 (`tuktuk`, `microbus_old`, `microbus_new`, `microbus_travel`) | Home street scene, Lines, BuyVehicle, Garage | `idle`, `drive`, `brake`, `honk` |
| `ui/splash_drive.json` | Loading | `loop` |
| `ui/coach_hand.json` | Tutorial, `CoachMark` | `tap` |
| `ui/stars.json` | Result | play 0 → end of `one` / `two` / `three` for the stars earned |
| `ui/coins_burst.json` | Result payout, Daily claim | `burst` |
| `ui/bonat_burst.json` | PurchaseDone, RoomDone reward | `burst` |
| `ui/fuel_fill.json` | Fuel sheet, refill | `empty`, `fill` |
| `ui/gift_open.json` | Daily | `open` |
| `ui/sparkle_place.json` | item bought in Piece / placed in AptRooms | `place` |
| `ui/ring_shine.json` | AptGoal, AptGoalReady | `loop` |
| `ui/confetti.json` | RoomDone, chapter complete, 3 stars | `burst` |
| `ui/loading_wheel.json` | `States` loading | `loop` |
| `ui/notif_bell.json` | NotifAsk | `ring` |

Known simplifications in the generated files: text inside props is dropped (the ٢٠٠ on the أفندي's note, the ٥٠/٥ notes), بلية's gap tooth is replaced by the shared mouths, and بلية has no `point` segment (the coach uses `ui/coach_hand`). Regenerate after art changes with `tools/` (README there).

**Fallback.** If a Lottie file fails to load, or for the third performance tier below, `PassengerAvatar`, `CharacterAvatar` and `VehicleSprite` render the static SVG from `illustrations/` with code-driven motion (idle bob 2 px / 1.2 s).

### 6.4 Performance gate (trip scene)

On the cheapest target phone (Galaxy A06 class): 12 passengers animating + 2 bubbles + 3 money notes in flight at 60 fps, p90 frame time < 16 ms (build + raster), memory < 300 MB.

1. Try direct `LottieComponent` rendering first.
2. If it misses the gate: cache each passenger's current segment as a `SpriteAnimation` rendered at its on-screen size (loops at 15 fps), key = (skin, segment, row). Render on first use, keep an LRU of ~40 animations.
3. If that still misses: static SVG faces with code-driven transforms (the fallback above) for rows B–D, Lottie only for row A and the front seat.

Record the measurements in `research.md`.

### 6.5 UI motion (code)

| Element | Trigger | Animation | Duration / curve |
| --- | --- | --- | --- |
| Any button with a lip | press / release | translateY(+lip), lip → 0 | 80 ms ease-out |
| `Sheet` | open / close | slide up from bottom + scrim fade | 280 ms easeOutCubic / 200 ms easeInCubic |
| `AppDialog` | open | scale 0.92 → 1 + fade | 220 ms easeOutBack(1.2) |
| `UndoToast`, banners | show / hide | slide 12 px + fade | 200 ms ease-out; toast holds 3 s, banner 4 s |
| `SpeechBubble` | appear | scale 0.6 → 1 from the tail | 180 ms easeOutBack(1.4) |
| `StationTag.hot` | station next + change owed | scale 1 ↔ 1.18 | 600 ms loop |
| Countdown chip | < 8 s | pulse | 500 ms loop |
| `MoneyNote` | each hop | move seat → seat on a slight arc | 1.3 / 1.1 / 0.9 s per hop by line, easeInOut |
| Passenger alight | `StationReached` | up 12 + fade | 600 ms |
| Scene | bump, fight | shake 6 px | 300 ms |
| Payout number | Result | count up from 0 | 600 ms easeOutCubic |
| Progress bars | value change | width tween | 500 ms easeOutCubic |
| `NewDot` | appears | scale 0 → 1.2 → 1 | 240 ms |
| Tab switch | `BottomNav` | cross-fade | 150 ms |

**Reduced motion** (system setting or in-app): no shake, no bubble pop, no star bounce, no parallax; fades ≤ 150 ms only. Lottie loops keep playing but `fx_*` effects stay still.

**Sound and haptics** follow ux-spec «الحركة والصوت والاهتزاز»: coin clink in the tray, paper fold when a note passes, «على جنب يا أسطى» voice, horn at the station; light haptic when money arrives, heavy on a fight; settings toggle both.

## 7. Navigation map

`go_router`, shell route for the bottom nav. Back button is always top-right (RTL start); Android back on the trip opens Pause. "Sheet" = modal bottom sheet route; "dialog" = modal dialog route.

| Artboard | Screen | Route | Presentation | Phase |
| --- | --- | --- | --- | --- |
| `Loading` | التحميل | `/boot` | full screen | MVP |
| `Intro` | المشهد الافتتاحي | `/onboarding/intro` | full screen | MVP |
| `Name` | اسم الأسطى | `/onboarding/name` | full screen | MVP |
| `Tutorial` | التعليم داخل المشوار | `/trip/:tripId` (tutorial trips of خط الحي) with coach overlay | overlay | MVP |
| `NotifAsk` | طلب الإشعارات | `/home/notif-ask` (new route), after the first trips | dialog | MVP |
| `C-Home` | الموقف | `/home` | shell tab | MVP |
| `HomeStates` | الموقف: حالات | `/home` | states | MVP |
| `PreTrip` | كارت ما قبل المشوار | `/home/pre-trip/:tripId` | sheet | MVP |
| `C-Trip` | المشوار | `/trip/:tripId` | full screen | MVP |
| `TripEvents` | المشوار: أحداث | `/trip/:tripId` | states | MVP |
| `StoryTrip` | مشوار قصة | `/trip/:tripId` (story trip) | full screen | MVP |
| `Pause` | نافذة الإيقاف | over `/trip/:tripId` | dialog | MVP |
| `Fail` | فشل المشوار | over `/trip/:tripId` | dialog | MVP |
| `Result` | النتيجة | `/trip/:tripId/result` | full screen | MVP |
| `ShareCard` | صورة المشاركة | rendered off-screen, shared with `share_plus` | image | MVP |
| `Lines` | الخطوط | `/lines` | shell tab | MVP |
| `LineDetails` | تفاصيل الخط | `/lines/:lineId` | sheet | MVP |
| `BuyVehicle` | شراء العربية | `/lines/vehicle/:vehicleId` | sheet | MVP |
| `AptGoal` | الشقة (الفصول ١–٣) | `/apartment` | shell tab | MVP |
| `AptRooms` | الشقة (من الفصل ٤) | `/apartment` | shell tab | MVP |
| `Piece` | لوح القطعة | `/apartment/item/:itemId` | sheet | MVP |
| `SceneViewer` | عارض المشاهد | `/story/:chapterId` | full screen | MVP |
| `Chapters` | خط الفصول | `/apartment/chapters` | full screen | MVP |
| `Requests` | طلبات أهل العروسة | `/apartment/requests` | sheet | MVP |
| `AptGoalReady` | الشقة: الهدف جاهز | `/apartment` when the chapter goal is affordable | state | MVP |
| `RoomDone` | الغرفة خلصت | over `/apartment` after the last item of a room | dialog | MVP |
| `Album` | ألبوم المشاهد | `/story/album` (new route) | full screen | MVP |
| `Shop` | المحل | `/shop` | shell tab | MVP |
| `Fuel` | نافذة البنزين | `/shop/fuel` (also opened from Home) | sheet | MVP |
| `PurchaseDone` | الشرا تمّ | `/shop/purchase-done` (new route) after a purchase | dialog | MVP |
| `Daily` | المكافأة اليومية | `/daily/reward` | full screen | MVP |
| `Tasks` | مهام اليوم | `/daily/tasks` | sheet | MVP |
| `Challenge` | تحدي اليوم | `/daily/challenge` | full screen | MVP |
| `Settings` | الإعدادات | `/settings` | full screen | MVP |
| `DeleteStep1` | حذف الحساب: خطوة ١ | `/settings/account/delete` (new route) | full screen | MVP |
| `DeleteAccount` | حذف الحساب: خطوة ٢ | `/settings/account/delete/confirm` (new route) | full screen | MVP |
| `Returning` | رجوع الغايب | `/welcome-back` (new route), at boot after a long absence | dialog | MVP |
| `States` | الحالات العامة | everywhere | components | MVP |
| `Garage` | الجراج | `/garage` | full screen | Phase 2 |
| `Starter` | باقة البداية | `/shop/starter` (new route), once after finishing خط الحي | dialog | Phase 2 |
| `King` | ملك الخط | `/leagues` | full screen | Public launch |
| `Event` | المناسبة وتذكرة الموسم | `/events/:seasonKey` | full screen | Public launch |
| `Invite` | ادعي صاحبك | `/settings/referral` | full screen | Public launch |

The per-screen sections (§11) list every tap and where it goes.

## 8. Accessibility

- Every tappable has a `Semantics` label; use the HTML `aria-label` text verbatim. Icon-only buttons (pause, close, back, copy) always have one.
- Hit areas ≥ 44×44 even when the visible shape is smaller (station dots, tray counts, new-dots aren't targets).
- Reading order follows RTL visual order: header → main content → primary CTA → bottom nav.
- Live announcements (`SemanticsService.announce`): station warnings («الكوبري جاية، المستعجل ليه باقي»), fare raised, trip result, purchase result, offline/online changes.
- Colour is never the only cue: stations carry letters, ledger badges carry words, stars have a check/✗ caption on Result.
- Contrast: body text on white ≥ 4.5:1 (ink, ink.2, ink.muted pass; `icon.off` is icons only). White text only on `primary`, `primary.lip`, `station[0..1]`, dashboard. Never white on `danger` or `sun`.
- Text scale up to 1.3× (1.15× clamp in the trip HUD/dashboard). Reduced motion as §6.5.

## 9. Decisions and open questions

The per-screen reviews (§11, "Notes" in each section) found small inconsistencies between artboards. These rules settle them; follow the rule even where one artboard differs.

### 9.1 Decisions (follow these)

1. **Lottie, not Rive.** Architecture §2/§5/§8/§25 now say so.
2. **Design sizes win** over older numbers in the UX spec and architecture: scene 390×444, HUD 114, dashboard 258.
3. **BONAT wording.** Price tags, chips and badges always say «بون» (`٨ بون`, `+١٠ بون`). Inside sentences use Arabic number agreement: ٣–١٠ «بونات», ١١ and up «بون».
4. **Fuel cost** is one chip everywhere: sun pill «−١» + fuel icon (as on Home and PreTrip). Where an artboard writes «−١ لتر» (Result, Pause, Fail, Piece, Event), use the chip.
5. **Disabled** is always 45% opacity with no lip, including the "daily ad limit reached" button in `States` and the offline items drawn at 55%.
6. **Locked.** Progression-locked (lines, vehicles, chapters, rooms, album, line cells) = `locked.bg` + 2 px `outline` ring + `ink.2` text + lock icon, no opacity. Pay-locked (paid season-pass track) = `sun.soft` + lock icon. A passed station dot at 35% is a "passed" state, not locked.
7. **Currency pills:** fuel pill opens the Fuel sheet (`/shop/fuel`), bonat pill opens the Shop, coins pill isn't tappable.
8. **Counters** use `CountBadge` (`primary`, white text). The Requests count drawn in red is a `CountBadge` too.
9. **Hit areas** are ≥ 44×44 even where the drawn shape is smaller (undo «رجّع», station dots aren't targets).
10. **Text never clips.** Chips, banners and cells with text grow (`min-height`) and wrap to two centred lines; nothing truncates except the player's name (one line, ellipsis after 84 px).
11. **Rewarded ad inside a trip** (booster «زحمة» with «إعلان»): pause the engine, show the rewarded ad, resume on return. Architecture §15.1's "no ads during a trip" applies to interstitials.
12. **Passenger semantics label** = type + stop («المستعجل، نازل الكوبري»). Add «ليه باقي» only while that passenger's tag is `hot`, so the label never reveals more than the screen shows.
13. **Store prices** always come from the store (`ProductDetails.price`); «[سعر المتجر]» in the art is a placeholder.

### 9.2 States described here instead of drawn

| State | Screen | Rule |
| --- | --- | --- |
| Item affordable | `Piece` | CTA becomes `AppButton.primary(xl)` «اشتريها» with a sun price chip «−٣٬٢٠٠ ج»; the «ناقصك» line and progress disappear. After buying: sheet closes, `ui/sparkle_place` on the slot, Salma comments (UX «لوح القطعة»). |
| Room's last item bought | `AptRooms` → `RoomDone` | drawn |
| Chapter goal affordable | `AptGoal` → `AptGoalReady` | drawn; buying opens the chapter scene |
| Daily reward already claimed | `Daily` | today's cell shows a check like past days; CTA disabled «تعالى بكرة» with a countdown chip (`clock` icon + time to midnight) |
| Not enough money for a vehicle | `BuyVehicle` | CTA disabled; above it «ناقصك {n} ج» in `danger.ink` 14/700 + gold `ProgressBar` of balance / price |
| Revive already used | `Fail` | hide the rewarded revive card; keep «عيد المشوار» and «ارجع الموقف» |
| Story rule broken (e.g. a fight with أبو العروسة riding) | `StoryTrip` | goes to `Fail` with the reason line «أبو العروسة شاف خناقة» instead of the reputation line |
| Undo after a throw | `C-Trip` | for 1 s after money leaves the hand, a sun chip «رجّع» (h 32, hit area 44) sits at the end side of `HandSlot`; tapping returns the money |
| Edit name | `Settings` | opens the `Name` screen as a `Sheet` with the current name filled in |
| Garage cosmetics tab, Event with pass owned, redeem-code input (Invite) | later phases | design before those phases start |

### 9.3 Open product questions

1. **Half fare that can't be paid.** On خط الجامعة the fare is ٨٫٥, so a student's half fare is ٤٫٢٥, which half-pound coins can't pay. Round half fares (suggest up, to the nearest ٠٫٥) or make base fares even.
2. **When the Apartment tab opens.** UX says locked in chapters 1–2; the design shows the goal view (`AptGoal`) from the start and rooms from chapter 4. The design's approach keeps the dream visible; confirm.
3. **Tutorial order.** The `Tutorial` artboard is trip 2 of خط الحي (first change); confirm the per-trip coach lines in UX «التعليم داخل المشاوير».
4. **Routing money around أبو سمّاعة.** The product spec and PreTrip copy allow passing money via the neighbouring seat; engine §7.7 currently blocks the column. The engine needs the `redirect` path for this.
5. **Ledger booster duration:** badges live 5 s (UX, Components); architecture §3.3 says the booster lasts 10 s. Confirm both numbers.
6. **Day-7 sticker** is an MVP daily reward, but cosmetics arrive with the Garage in phase 2. Swap it for BONAT in MVP?
7. **Settings shows the «ملك الخط» notification switch** in MVP; hide it until leagues launch.
8. **Backend gaps found while specifying:** a grant path for the comeback gift and for family-request rewards (backend §7.4 has no op), stats for longest streak and trip count, a maintenance end time in the 503 response, and a `trip_id` scheme for daily-challenge and event trips.
9. **Sample data everywhere** (see §0): prices and economy numbers come from content packs / Remote Config.

## 10. Build order and acceptance

1. `tokens.g.dart` + theme + fonts.
2. Component gallery reproducing `screens/Components.html` (and `Tokens.html`). Review side by side with the PNGs before building screens.
3. Screens in this order: Home → PreTrip → Trip (static layout with a fake engine state that matches `C-Trip`) → Result → Lines → Apartment → Shop → Daily → Settings → onboarding → states.
4. For each screen, a **golden test** at 390×844 with the artboard's sample data, plus a **layout test** that checks key widgets against `boxes/<Artboard>.json`: find each tappable by its semantics label and assert its rect is within ±2 px of the measured box. `boxes/` holds every visible box of every artboard (position, size, colour with token name, font, radius, shadow), measured from the HTML.
5. Put the Flutter golden next to `png/<Artboard>.png` in the PR so a human can compare. Pixel-exact equality isn't expected (different text rasterisers); layout, colours, sizes and copy are.

## 11. Screens

One section per artboard, grouped as on the canvas. Each lists route, layout (sizes measured from the HTML), dynamic data, interactions, states, motion, accessibility, exact strings, and notes. The decisions in §9.1 override anything a section says.

### Screens: onboarding, home, pre-trip, result

Conventions for this part: x/y are logical px measured from the rendered artboard (origin top-left of the 390-wide frame); "abs" = absolute frame coordinates. Every number on screen is formatted by the app digit formatter (Arabic-Indic by default, `٬` thousands, `٫` decimal; Western when the setting is on). Money in piasters is shown as pounds: `450 → «٤٫٥»`, `700 → «٧»` (no trailing `٫٠`).

---

#### التحميل — `Loading`

| | |
| --- | --- |
| Route | `/boot` (full screen) |
| Feature folder | `features/onboarding/` |
| Phase | MVP |
| Files | `screens/Loading.html` · `png/Loading.png` |

**Purpose.** Cold-start splash while the app opens the DB, loads the bundled content pack and calls `/v1/bootstrap`. It then routes to onboarding (first launch) or to Home / daily reward / welcome back (returning).

**Layout, top to bottom.**

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 0 | Background | 390×844 | Flat fill. Decorative circles: (330,120) r70 and (40,700) r110. Small cloud at x44–104, y≈142–160, 70% opacity | `sun` · circles `sun.glow` · cloud `paper` |
| 1 | Wordmark | y210, 289×66, centered | «وصّل الأجرة», Marhey 700 60 / lh 1.1, solid text shadow (0, 5) | `ink` · shadow `sun.lip` |
| 2 | Tagline | y282, h19, centered (gap 6 under wordmark) | «لمّ الأجرة صح، والباقي يرجع لصاحبه» | `type.row` (500) · `ink.2` |
| 3 | Vehicle illustration | x45 y341, 300×170 | `VehicleSprite` `micro_old` (white body, `primary` stripe + `danger` pinstripe, red bulb trim), roof sign pill «الموقف» (`ink` bg, Marhey 15 `sun`), speed lines on the right, ground shadow | `paper`, `primary`, `danger`, `scene.tyre`, `scene.hub`, `scene.window`, shadow `sun.lip` 50% |
| 4 | Road progress bar | x45 y668, 300×24, r `pill` | `ProgressBar` drawn as a road: bar `scene.road`, lip 4 `sun.lip`; dashed lane line inset 14, 4 high, 14 on / 12 off, `paper` 80%. Vehicle marker 44×30 r12, `primary`, lip 3 `primary.lip`, white microbus glyph 26×18, top −10, horizontally centred on the progress point | `scene.road`, `paper`, `primary`, `primary.lip`, `sun.lip` |
| 5 | Loading line | y706, h20, centered (gap 14) | Random line from a pool, sample «بنعدّ الفكة..» | Readex 16/600 · `ink` |

Block 4 + 5 sit at `bottom: 118` (x45–345).

**Dynamic data.**
- Progress 0–100 → boot pipeline progress (DB open → content pack verified → bootstrap response). The marker sits at `right: {p}%` (RTL: it travels right → left). Sample value 62.
- Loading line → random pick from a local pool of short lines (only «بنعدّ الفكة..» is written).
- Wordmark, tagline, sign «الموقف»: static.

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| Whole screen | — | None. The full-screen `<a href="Intro.html">` is prototype navigation only. |
| (auto) | boot finished | First launch → `/onboarding/intro`. Returning → `/home`, or `/daily/reward` / welcome back first (see UX «خريطة الشاشات»). |

**States & edge cases.**
- Fast boot (< 2 s): no minimum display time; route away as soon as ready (UX spec).
- Offline boot: continue with local data, no error (offline-first); Home then shows `OfflineBanner` (see `HomeStates`).
- Force update / maintenance from bootstrap: show the cards drawn on `States`.
- No white flash: the native splash colour must be `sun` so it matches this screen.

**Motion.**
- Microbus enters from the right on first frame (UX: «الميكروباص داخل من اليمين»), then idles (Lottie loop of `VehicleSprite`).
- Marker position tweens with progress (linear, ≤150 ms per update). Reduced motion: no entrance, marker jumps.

**Accessibility.**
- `ProgressBar` semantics: label «التحميل», value 0–100.
- Illustration and decorations excluded from semantics. Wordmark read once as «وصّل الأجرة».

**Strings.**
- `loading.wordmark: "وصّل الأجرة"`
- `loading.tagline: "لمّ الأجرة صح، والباقي يرجع لصاحبه"`
- `loading.vehicleSign: "الموقف"`
- `loading.line1: "بنعدّ الفكة.."` (first entry of the random pool)
- `loading.a11yProgress: "التحميل"`

**Notes.**
- Wordmark is Marhey 60, larger than `type.display.xl` (32, "splash"). Treat it as a logo style (or an image asset), not a type token.
- Only one loading line is written; the pool needs more lines from content.

---

#### المشهد الافتتاحي — `Intro`

| | |
| --- | --- |
| Route | `/onboarding/intro` (full screen) |
| Feature folder | `features/onboarding/` |
| Phase | MVP |
| Files | `screens/Intro.html` · `png/Intro.png` |

**Purpose.** About 10 seconds of comic (3 panels): the master hands the driver the tuktuk key and gives the game's rule. The player can skip.

**Layout, top to bottom.** Screen padding 36 / 16 / 28, column gap 16.

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 0 | Background | 390×844 | Dark | `dashboard.bg` |
| 1 | Header row | y36, h44 | Right: chapter title «أول شغلانة» (`type.display.s`). Left: skip pill «تخطّى» 71×44, padding 0 16, r `pill` | title `sun` · pill bg `dashboard.raised`, text `paper` Readex 14/600 |
| 2 | Comic panel | y96, 358×540 | `ComicPanel`, r `radius.scene` (26), lip 6 `ink` (`lip.dark`). Panel art: sky, street buildings, master's tuktuk, المعلم handing a key to the driver | bg `scene.sky` · `lip.dark` |
| 2a | Scene caption chip | abs (30,110), 148×26 | «الموقف، الصبح بدري», padding 4/12/6, r12 | bg `sun`, lip 3 `sun.lip` (`lip.sun.s`), `type.caption` 700 `ink` |
| 2b | Speech bubble | abs (124,172), 236×120 | `SpeechBubble` character: name «المعلم» (`type.label`, `ink.muted`) + line «خد مفتاح التوكتوك. لمّ الأجرة صح، والباقي يرجع لصاحبه.» (Marhey 600 19, lh 1.45). Padding 10/16/12, r20, tail at the bottom, 64 from the right edge, pointing at المعلم | `paper`, `type.quote` (19), lip 4 rgba(26,75,140,.18) |
| 3 | Page dots | y652, h10, centered, gap 8 | 3 dots; active 26×10, inactive 10×10, r `pill`. First dot (rightmost) = panel 1 | active `sun` · inactive `dashboard.line` |
| 4 | CTA | y752, 358×64 (pushed to bottom) | `AppButton` primary xl «يلا» | `primary`, `lip.primary`, `type.button.xl` |

**Dynamic data.**
- Panel art, caption and bubble text → chapter `ch1_first_job` intro scene from the content pack (3 panels; only panel 1 is drawn).
- Chapter title «أول شغلانة» → chapter 1 name (product spec «الفصول»).
- Active dot index → current panel.

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| «تخطّى» | tap | `/onboarding/name` (replace, no back to intro) |
| «يلا» | tap | Next panel; on panel 3 → `/onboarding/name` |
| System back | press | Same as «تخطّى» (no way back to Loading) |

**States & edge cases.**
- First launch only. Never shown again (the scene stays in the story album).
- Long bubble text: wrap; bubble grows downward; max width 236.

**Motion.**
- Panel change: crossfade/slide ≤ 280 ms (`sheetIn` curve); bubble `bubblePop`. Reduced motion: fade ≤ 150 ms.

**Accessibility.**
- Read order: chapter title → caption → speaker + line → «اللوحة ١ من ٣» → «يلا» → «تخطّى».
- Dots group label: «اللوحة {n} من {total}». Skip pill is 44 high (min target met).

**Strings.**
- `intro.chapterTitle: "أول شغلانة"` (from chapter content)
- `intro.skip: "تخطّى"`
- `intro.panel1.caption: "الموقف، الصبح بدري"`
- `intro.panel1.speaker: "المعلم"`
- `intro.panel1.line: "خد مفتاح التوكتوك. لمّ الأجرة صح، والباقي يرجع لصاحبه."`
- `intro.pageOf: "اللوحة {n} من {total}"`
- `intro.next: "يلا"`

**Notes.**
- The artboard links «يلا» straight to `Name`. The UX spec says 3 panels in sequence, so «يلا» should advance panels. Panels 2–3 are not drawn.
- UX spec "≈10 seconds" could mean auto-advance. Not specified: assume tap-to-advance only.
- Bubble lip colour rgba(26,75,140,.18) is not a token (same as other bubbles).

---

#### اسم الأسطى — `Name`

| | |
| --- | --- |
| Route | `/onboarding/name` (full screen) |
| Feature folder | `features/onboarding/` |
| Phase | MVP |
| Files | `screens/Name.html` · `png/Name.png` |

**Purpose.** One card to name the driver. A suggested name is already filled, so one tap continues.

**Layout, top to bottom.** Card is vertically centred in the frame (padding 36 / 16 / 28).

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 0 | Background | 390×844 | Decorative circles (340,90) r90 and (30,760) r120 | `ground` · circles `primary.soft` |
| 1 | Card | x16 y250, 358×353 | `AppCard`, padding 76/20/22, gap 14, r `radius.scene` (26) | `paper`, lip 6 `ground.lip` (`lip.card.big`) |
| 1a | Avatar | abs (139,194), 112×112, overlaps the card top by 56 | Circle with the driver's `CharacterAvatar` (104×104, bottom-aligned) | bg `sun`, lip 5 `sun.lip` |
| 1b | Title | y326, h34 | «اسمك إيه يا أسطى؟», centered | `type.display.l` · `ink` |
| 1c | Subtitle | y373, h18 | «الاسم ده هيظهر في الموقف وفي ترتيب ملك الخط.», centered | `type.body` · `ink.muted` |
| 1d | Field label | y405, h16 | «اسمك» (label for the field) | `type.caption` 600 · `ink` |
| 1e | Name field | y427, 256×54 (right) | `AppTextField`, value = suggested name, padding 0 16, Readex 20/600, max 16 chars, r16, inset ring 2 | bg `ground`, ring `ground.lip`, text `ink`, focus outline 3 `primary` |
| 1f | Suggest button | x36 y427, 54×54 (left, gap 8) | Dice glyph 24 (stroke `ink` 2.2), r16 | bg `sun.soft`, lip 4 #EED38A |
| 1g | Helper | y487, h15 | «تقدر تغيّره بعدين من الإعدادات.» | `type.label` 500 · `ink.muted` |
| 1h | CTA | y520, 318×60 | `AppButton` primary l «تمام» (Marhey 25, r20) | `primary`, `lip.primary` |

**Dynamic data.**
- Field initial value → random name from a local suggested-names pool (sample «حمادة»).
- Avatar → default driver look (`CharacterAvatar` driver).
- Saved value → `profile.display_name` (drift), synced later as a `settings_update` op.

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| Name field | tap / type | Edit; RTL input; max 16 chars |
| Suggest (dice) | tap | Replace the field with another pool name |
| «تمام» / keyboard done | tap | Trim and save name → first tutorial trip `/trip/line_hay.01` (tutorial overlay, see `Tutorial`) |
| System back | press | Ignored (onboarding is linear) |

**States & edge cases.**
- Empty or whitespace-only → «تمام» disabled (45% opacity, no lip).
- Keyboard open: keep the card fully visible (shift the centred card up into the remaining space).
- Long names: field limit 16 chars; Home truncates at 84 px with ellipsis (see `C-Home`).
- Works offline (local only).

**Motion.**
- Card enters with `dialogIn`; buttons use `press`. Dice: quick 150 ms text swap.

**Accessibility.**
- Field labelled «اسمك» (label is linked to the input). Dice: «اقترح اسم تاني». Read order: title → subtitle → label → field → dice → helper → CTA.

**Strings.**
- `name.title: "اسمك إيه يا أسطى؟"`
- `name.subtitle: "الاسم ده هيظهر في الموقف وفي ترتيب ملك الخط."`
- `name.fieldLabel: "اسمك"`
- `name.a11ySuggest: "اقترح اسم تاني"`
- `name.helper: "تقدر تغيّره بعدين من الإعدادات."`
- `name.cta: "تمام"`

**Notes.**
- Dice lip #EED38A is not a token (same as the morning-piggy banner on Home); propose `sun.soft.lip`.
- CTA is 60 high, outside `AppButton` l (54–58); Components labels 54–60 for secondary. Use 60.
- Name rules beyond 16 chars (allowed scripts, profanity filter, since names appear in leagues) are not specified.

---

#### التعليم داخل المشوار — `Tutorial`

| | |
| --- | --- |
| Route | overlay on `/trip/:tripId` for tutorial trips `line_hay.01`–`line_hay.05` (no own route) |
| Feature folder | `features/onboarding/` (tutorial overlays) on top of `features/trip/` |
| Phase | MVP |
| Files | `screens/Tutorial.html` · `png/Tutorial.png` |

**Purpose.** Teaching happens inside the first 5 trips. بلية points at the one control to use; the rest of the screen dims and ignores touches. The artboard shows **tutorial trip 2** (tuktuk, two passengers): the first time the player returns change.

**Layout, top to bottom.** The base screen is the trip screen (see the `C-Trip` section). Only tutorial-specific values and the overlay are listed here.

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 1 | `TripHud` | y36, h114 (+8 gap) | Pause `IconCircleButton` 44; title «خط الحي · المشوار ٢» (`type.display.s`); `ReputationBar` 92×12 at 100%. `StationStrip` 358×64: start dot «الموقف» at the right edge, vehicle marker at 30%, `StationTag` back-size 24 «ف» (order 1) at 55% with hot ring and countdown chip «٢٤ث», «م» (order 2) at 100%; labels «الفرن ٧ ج», «المدرسة ٧ ج» | as `C-Trip`; countdown chip `danger` bg + `ink` text |
| 2 | `TripScene` | y158, 390×444 | `tuktuk` cabin: one bench (`scene.seat`), 2 near-row passengers at scene x≈118 (الحاجة, glasses) and x≈270 (young man), scale 1.15; `StationTag` near 30 at scene (55,296) «م» and (207,292) «ف» (hot); driver hand at (162,398) | `scene.*`, `station[0..1]` |
| 3 | `Dashboard` | y586, h258 (overlap 16) | `HandSlot` empty «فاضية» (dashed `sun` border); `CallChangeButton` «حد معاه فكة؟ ×٢» (disabled under scrim); `ChangeTray` نص×٢، ١×٤، ٥×٢، ١٠×١ full, ٢٠/٥٠/١٠٠/٢٠٠ empty; `LastWordsLog` 2 lines | as `C-Trip` |
| 3a | Boosters locked bar (**new component** `BoostersLockedBar`) | y748, 366×44, r14 | Replaces the `BoosterButton` row during trips 1–5: lock glyph 16 + «المساعدات بتتفتح بعد المشوار الخامس», centered | bg `dashboard.raised`, text/icon `dashboard.muted`, `type.caption` 600 |
| 4 | Coach scrim | 390×844 | `CoachMark` scrim with one rounded hole: abs (192,642) 99×56 r18 = target tray cell (198,648 87×44) + 6 padding; ring 4 around the hole | `scrim.coach` (0.62), ring `sun` |
| 5 | Coach bubble | abs left 14, right 104, top 468 (272×89) | `SpeechBubble` character: name «بلية» + «ليه باقي ٣. دوس على الجنيه ٣ مرات، وبعدين دوس عليه.» Padding 10/14/12, r20; tail on the right edge, 22 from the bottom, pointing at بلية | `paper`, name `type.label` `ink.muted`, text Marhey 600 18 lh 1.45 (`type.quote`), lip 4 rgba(26,75,140,.25) |
| 6 | بلية head | abs (288,470), 96×110 | `CharacterAvatar` `bulya` (yellow cap, orange shirt), bottom-right corner of the scene, overlapping the dashboard top | — |
| 7 | Pointing hand | abs (230,690), 56×64 | Hand glyph pointing up into the target cell (`paper` fill, `ink` 3 stroke) | `paper`, `ink` |

**Dynamic data.**
- HUD, scene, tray, log: from the tutorial `TripDefinition` and engine state (`TripViewState`), as in `C-Trip`. Samples: change due 3, log «الحاجة: اتفضل يا ابني، سبعة» / «وصلك ١٠ من الراكب».
- Coach step (target rect, text, pointer position) → tutorial script per trip (content), triggered by engine events (e.g. `MoneyArrivedAtDriver` with `change_due > 0`).
- Hole rect → the live layout rect of the target widget + 6 px padding (do not hard-code).
- Boosters locked bar shown while `tutorial trip index ≤ 5`.

**Coach-mark sequence (as drawn, trip 2).**
1. Fare 10 arrives from the young man (owes 3) → scrim + hole on tray cell «١», hand points at it, بلية: «ليه باقي ٣. دوس على الجنيه ٣ مرات، وبعدين دوس عليه.»
2. Each tap on «١» moves one coin to `HandSlot` (`PickFromTray(100)`); the hole stays until the hand holds 3. *(inferred from the copy)*
3. Hole moves to the passenger who is owed change (near-row face «ف»); tap → `SendHand(passenger_id)`. *(inferred, not drawn)*
4. Overlay dismisses; trip continues normally.

UX spec tutorial table (only step 2 is drawn):

| Trip | Teaches | بلية line (UX spec) |
| --- | --- | --- |
| 1 (tuktuk, 2 riders) | Fares reach the tray by themselves | «شايف؟ الأجرة وصلت الدرج» |
| 2 | Returning change: tap coins, then the rider | «ليه باقي ٣، دوس على الجنيهات وبعدين عليه» (drawn copy differs, use the drawn one) |
| 3 | Station + countdown | «نازل الكوبري، لازم ياخد باقيه قبلها» |
| 4 | Sleeping rider | «ده نايم، دوس عليه صحّيه» |
| 5 | Fuel | المعلم gives a free refuel and explains the fuel gauge (copy not written) |

After trip 3: Salma scene, then `NotifAsk`. Analytics `tutorial_step` 1..8 maps to the 8 first-session steps (product spec «أول جلسة»).

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| Target inside the hole | tap | Normal trip command; advances the coach step |
| Anything outside the hole | tap | Ignored (no feedback) |
| Coach bubble / بلية | tap | Ignored |
| System back | press | Opens pause overlay (as in `C-Trip`) |

**States & edge cases.**
- Player taps «١» more than 3 times: the 4th tap is still allowed by the engine; keep the hole on the tray and let the coach text stay until the hand total equals the change due. Wrong amount is not blocked; it counts as a normal mistake.
- App backgrounded during a coach step: resume on the same step.
- Replay of a tutorial trip from Lines: no coach overlay (first play only).
- Hints after the tutorial: `trip_hints_enabled_line_hay` keeps بلية hints on line_hay (UX «الصعوبة والمساعدة حسب الخط»), same visual without the scrim.

**Motion.**
- Scrim fade in 200 ms; hole moves between targets 250 ms easeOutCubic; ring pulses like `hotTagPulse` (scale 1.0↔1.06 suggested). Bubble `bubblePop`. Hand: small tap bob loop (8 px, 600 ms). Reduced motion: no ring pulse, no bob.

**Accessibility.**
- Announce the coach text as a live region when a step starts («بلية: …»).
- While a step is active, only the target is focusable; screen-reader focus jumps to it after the announcement.
- Reuse `C-Trip` labels: «إيقاف مؤقت», «المحطات وأسعارها», «التابلوه», «إيدك فاضية», «درج الفكة», tray cells «جنيه، معاك ٤» / «٢٠ جنيه، مفيش».

**Strings.**
- `tutorial.coachName: "بلية"`
- `tutorial.trip1: "شايف؟ الأجرة وصلت الدرج"` (UX spec, not drawn)
- `tutorial.trip2: "ليه باقي ٣. دوس على الجنيه ٣ مرات، وبعدين دوس عليه."`
- `tutorial.trip3: "نازل {station}، لازم ياخد باقيه قبلها"` (UX spec, not drawn)
- `tutorial.trip4: "ده نايم، دوس عليه صحّيه"` (UX spec, not drawn)
- `tutorial.boostersLocked: "المساعدات بتتفتح بعد المشوار الخامس"`

**Notes.**
- The assignment calls this "the first trip"; the artboard is trip 2 («المشوار ٢», change return).
- UX trip-3 line names «الكوبري», but the line_hay tutorial stations drawn are الفرن / المدرسة. Use a `{station}` placeholder.
- The engine pauses on "any overlay" (arch §7.3). It is not specified whether tray/passenger commands are accepted while the clock is frozen for a coach step. The countdown «٢٤ث» suggests time keeps running. Needs a decision.
- The locked boosters bar is not in the UX spec; it is drawn only here.
- The tuktuk seat layout (2 riders, x 118/270, scale 1.15) differs from `layout.trip.faces` (microbus) in tokens.

---

#### طلب الإشعارات — `NotifAsk`

| | |
| --- | --- |
| Route | `/home/notif-ask` **(new route)**, dialog over `/home` |
| Feature folder | `features/onboarding/` |
| Phase | MVP |
| Files | `screens/NotifAsk.html` · `png/NotifAsk.png` |

**Purpose.** In-game pre-prompt, shown after the Salma scene (after tutorial trip 3) and before the OS permission dialog, so the OS prompt only appears for players who said yes.

**Layout, top to bottom.**

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 0 | Behind | 390×844 | Home (drawn as a grey skeleton) under `Scrim` | `scrim` (0.60) |
| 1 | Dialog | x16 y190, 358×444 | `AppDialog`, padding 24/20/20, gap 14, items centered, r `radius.scene` (26) | `paper`, lip 6 rgba(0,0,0,.25) |
| 1a | Illustration | y214, 150×120 | Fuel gauge (needle near full, green arc) + ringing bell | `ground` disc, arc `track` / `station[2]` green, bell `sun`/`gold`, ring marks `danger` |
| 1b | Title | y348, 318×68 (2 lines) | «تحب نقولك لما البنزين يتملى؟», centered | `type.display.m` (26), lh 1.3 |
| 1c | Body | y430, h45 | «وكمان لما تحدي اليوم ينزل، أو سلمى تبعتلك. مش أكتر من إشعارين في اليوم.», centered, lh 1.6 | `type.body` · `ink.muted` |
| 1d | Yes | y488, 318×60 | `AppButton` primary l «أيوه» (Marhey 24, r20) | `primary`, `lip.primary` |
| 1e | Later | y562, 318×52 | `AppButton` tertiary «بعدين» (no lip, r18) | bg `ground`, Readex 16/600 `ink` |

**Dynamic data.**
- All copy is static. Daily cap «إشعارين» mirrors Remote Config `notif_daily_max` (2); if the value changes, the copy must change too.

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| «أيوه» | tap | Request the OS permission (Android 13+ / iOS). Granted → register the FCM token (`POST /v1/push-tokens`), enable the default toggles, schedule the local «البنزين اتملى». Then close → `/home` |
| «بعدين» | tap | Store `notif_ask_snoozed_until = now + 3 days` → close → `/home` |
| Scrim / system back | tap / press | Same as «بعدين» |

**States & edge cases.**
- OS permission already granted, or permanently denied: skip this dialog entirely.
- After «بعدين», do not ask again for 3 days (UX spec).
- Offline: «أيوه» still requests the OS permission; token registration is queued.

**Motion.** `dialogIn` (220 ms easeOutBack 1.2); scrim fade 200 ms; `press` on buttons.

**Accessibility.** Dialog semantics labelled by the title (`aria-labelledby`). Focus starts on the title; read order title → body → «أيوه» → «بعدين». Both buttons ≥ 52 high.

**Strings.**
- `notifAsk.title: "تحب نقولك لما البنزين يتملى؟"`
- `notifAsk.body: "وكمان لما تحدي اليوم ينزل، أو سلمى تبعتلك. مش أكتر من إشعارين في اليوم."`
- `notifAsk.yes: "أيوه"`
- `notifAsk.later: "بعدين"`

**Notes.**
- Dialog lip rgba(0,0,0,.25) is not a token.
- When to ask again after the 3-day snooze (which trigger) is not specified.
- No route in arch §9; proposed `/home/notif-ask`. It could also be shown imperatively by the onboarding flow controller.

---

#### الموقف — `C-Home`

| | |
| --- | --- |
| Route | `/home` (shell route with `BottomNav`) |
| Feature folder | `features/home/` |
| Phase | MVP (event circle: Public launch; vehicle tap → garage: Phase 2) |
| Files | `screens/C-Home.html` · `png/C-Home.png` |

**Purpose.** The hub. One tap starts a trip, and the dream (apartment savings) is always visible. Daily-return entry points, currencies and navigation live here.

**Layout, top to bottom.** Content column padding 0 16 10, gap 10, starting at the top inset 36; `BottomNav` pinned at y756.

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 1 | Header | y36, h58 | **Right:** profile button: avatar 48 circle (driver `CharacterAvatar` 46) + name «أحمد» (Marhey 700 19, max-width 84, ellipsis) + level chip «درجة ٣» (pill, padding 0 8). **Left (gap 6):** `CurrencyPill` coins «١٬٢٤٠» 78×44 · `CurrencyPill` bonat «٨٥» 66×44 · `CurrencyPill` fuel+timer 71×44 («٤/٥» 15/700 over «١٢:٣٠» 12/500) | avatar `sun` + lip 4 `sun.lip`; chip `paper` bg, `primary` `type.label`; pills `paper`, lip 4 `ground.lip` (`lip.card.small`), r `pill`, padding 0 6 0 12, gap 5, value Readex 16/700; timer `ink.muted`; icons coin `gold`/`sun`, ticket `primary`, pump `danger` |
| 2 | Scene card | y104, 358×332 | r `radius.scene`, clip. Street: sun disc (40,44) r20, cloud, 5 buildings, kerb, road with lane dashes. `VehicleSprite` `micro_old` with roof line sign «الجامعة» (pill 96×26, Marhey 15), riders in the windows, barker (التبّاع) waving in the door | bg `scene.sky`, lip 6 `ground.lip` (`lip.card.big`); road `scene.road`; kerb `scene.kerb`; sign `sun` + `ink` |
| 2a | Daily row | abs right 26, y114; 4 × 58 wide, gap 6 | `DailyCircle` ×4: «الهدية» (`NewDot`), «المهام» (`CountBadge` «٢/٣» at top −4 / left −2), «التحدي» (`NewDot`), «رمضان» (event, filled circle). Circle 46 + label pill 12/600 h16 padding 0 7, gap 3. `NewDot` at top 0 / left 5 | circles `paper` (event: #3B2A6B), lip 4 rgba(26,75,140,.18); label `paper` bg `ink`; `NewDot` per `ring.new_dot`; badge `primary` + `paper` `type.label` 700 |
| 2b | Barker bubble | abs (229,186), 137×33 | `SpeechBubble` character, no name: «جامعة.. جامعة!» (Marhey 600 17), padding 4/14/6, r18, tail bottom 54 from the right | `paper`, `type.quote` (17), lip 4 rgba(26,75,140,.18) |
| 2c | Garage hit area | abs (48,210), 294×202 | Invisible button over the vehicle | — |
| 3 | Line card | y446, 358×70 | `AppCard` link, padding 0 14, gap 12. Icon tile 44 r14 (route glyph). Title «خط الجامعة» + meta «المشوار ١٢ من ٣٠» on one baseline; `ProgressBar` primary h10 below (40%). Left: star 24 + «٢٧/٩٠» 16/700 | `paper`, lip 5 `ground.lip` (`lip.card`), r `radius.card`; tile `primary.soft` + `primary`; title `type.display.s`; meta `type.caption` `ink.muted`; bar `track` / `primary`; star `gold` |
| 4 | Start CTA | y526, 358×64 | `AppButton` primary xl «يلا نطلع!» + fuel chip (h30, padding 0 10, pump glyph 16 + «−١» 14/700), gap 12 | `primary`, `lip.primary`, `type.button.xl`; chip `sun` bg, `ink` |
| 5 | Savings card | y600, 358×84 | `AppCard` link. Ring icon tile 54 r18. Row 1: «تحويش الجواز» / «الفصل ٤». Row 2: «الجاية: الأنتريه» / «١٬٢٤٠ / ٣٬٢٠٠ ج» (700). `ProgressBar` gold h10 (39%) | tile `sun.soft`; title `type.display.s`; chapter `type.label` `ink.muted`; row 2 `type.body`; bar `track` / `gold` |
| 6 | Morning piggy | y694, 358×52 | `RewardedAdButton` (wide banner variant): pig glyph 30; «حصّالة الصبح» (Marhey 16) over «اتفرج على إعلان وخد جنيهات وبونات» (12.5/500); left chip «ببلاش» h32 with TV glyph 16 | bg `sun.soft`, lip 4 #EED38A, r18; sub `ink.2`; chip `primary` + `paper` 14/700 |
| 7 | `BottomNav` | y756, 390×88 | 4 tabs (RTL): الموقف (active), الخطوط, الشقة (`NewDot` at the icon's top-end), المحل. Padding 8/10/18. Active: `primary` pill 60×34 + white glyph, label 13/700 `primary`; others: glyph 24 stroke 2.4 `icon.off`, label 13/600 `ink.muted` | `paper`, top radius 26, lip −4 `outline` (`lip.nav`) |

**Dynamic data.**
- Avatar / name / level → `profile` (`display_name`, `driver_level`; chip «درجة {n}»).
- Coins → `wallet.jenehat`; bonat → `wallet.bonat`; fuel → `wallet.fuel` / `fuel_max` (5; 7 for subscribers); timer → time to the next liter (mm:ss) from `fuel_updated_at_server` + `fuel_regen_minutes` (server-corrected clock, arch §13). Ticks every second.
- Daily row: gift `NewDot` when today's reward is unclaimed; tasks badge `{done}/{total}` from `daily_state`; challenge `NewDot` when today's challenge is unplayed; event circle only while a season event is active (name + icon from event content).
- Scene: active vehicle from `ownership` (`micro_old` here), current line sign = the line's terminus name, barker call per line (content; sample «جامعة.. جامعة!»), later cosmetics/event decorations.
- Line card: current line name; `{n}` = next trip index, `{total}` = trips in line; bar = completed / total; stars = sum of `best_stars` / (3 × total).
- CTA fuel cost → 1 per trip (product rule).
- Savings card: chapter number (`story_state`), next item name and price (catalog), have = `wallet.jenehat`, bar = have / price (capped 100%).
- Piggy: shown when `morning_piggy` is available today (cap 1/day).
- Nav `NewDot`s: something new in that section (e.g. apartment item affordable or scene waiting).

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| Profile (avatar + name) | tap | `/settings` |
| Coins pill | — | Not interactive |
| Bonat pill | tap | `/shop` |
| Fuel pill | tap | `/shop` (as drawn) |
| «الهدية» / «المهام» / «التحدي» | tap | `/daily/reward` / `/daily/tasks` / `/daily/challenge` |
| Event circle | tap | `/events/:seasonKey` (public launch) |
| Vehicle | tap | `/garage` (Phase 2) |
| Line card | tap | `/lines` |
| «يلا نطلع!» | tap | Interstitial check (`AdsGateway.maybeShowInterstitial()`, rules §3.4) → `/home/pre-trip/:tripId`; if `pre_trip_card_mode` = new-only and nothing is new → `/trip/:tripId` directly (fuel spent at trip start) |
| Savings card | tap | `/apartment` |
| Morning piggy | tap | `AdsGateway.showRewarded(morning_piggy)` → server SSV grant → poll `/v1/ads/rewards/{nonce}` → wallet updates |
| Bottom nav tabs | tap | `/home`, `/lines`, `/apartment`, `/shop` |

**States & edge cases.**
- Out of fuel, offline, early chapter (apartment locked): drawn on `HomeStates`.
- Not drawn (UX spec only): next item affordable → savings card highlighted with «جاهزة للشرا!»; story scene waiting → card shows «مشهد جديد مستنيك» instead of the bar; season event → scene decorations + event circle.
- Fuel full (5/5): timer value not drawn; hide the timer line.
- Long name: one line, max 84 px, ellipsis. Large numbers: pills grow; at 7+ digits keep `٬` grouping (no abbreviation specified).
- Height budget: everything fits exactly at 844. The scene card absorbs height changes (332 here, 282 when the offline banner shows), so implement it as the flexible block.
- Content pack swap happens on a Home visit (arch §14.1), never visible mid-render.

**Motion.**
- Barker bubble `bubblePop` on enter, re-pops every few seconds (interval not specified). Vehicle and barker idle Lottie loops.
- `NewDot` static. Currency changes: count-up ≤ 300 ms (suggested). Cards/buttons `press`.
- Reduced motion: no pop, idle loops paused on frame 0.

**Accessibility.**
- Labels (from HTML): profile «ملف الأسطى والإعدادات»; bonat «البونات ٨٥، افتح المحل»; fuel «البنزين ٤ من ٥، اللتر الجاي بعد ١٢ دقيقة و٣٠ ثانية»; «هدية اليوم، فيها جديد»; «مهام اليوم، خلصت ٢ من ٣»; «تحدي اليوم، فيه جديد»; «مناسبة رمضان»; vehicle «الجراج: زوّق عربيتك»; line «الخطوط: خط الجامعة، المشوار ١٢ من ٣٠، النجوم ٢٧ من ٩٠»; savings «تحويش الجواز: الفصل ٤، الجاية الأنتريه»; nav «التنقل الرئيسي», apartment tab «الشقة، فيها جديد».
- Missing in HTML (add): coins pill, start CTA (include the fuel cost), piggy banner.
- Reading order: header (profile → coins → bonat → fuel) → daily row → barker → line card → CTA → savings → piggy → nav. Fuel timer label updates are not announced every second.
- Targets: pills 44 high; daily circles 58×65.

**Strings.**
- `home.levelChip: "درجة {n}"`
- `home.daily.gift: "الهدية"` · `home.daily.tasks: "المهام"` · `home.daily.challenge: "التحدي"` · `home.daily.tasksBadge: "{done}/{total}"`
- `home.fuelValue: "{fuel}/{max}"`
- `home.lineTripOf: "المشوار {n} من {total}"` · `home.lineStars: "{earned}/{max}"`
- `home.ctaStart: "يلا نطلع!"` · `home.fuelCost: "−{n}"`
- `home.savings.title: "تحويش الجواز"` · `home.savings.chapter: "الفصل {n}"` · `home.savings.next: "الجاية: {item}"` · `home.savings.amount: "{have} / {price} ج"`
- `home.piggy.title: "حصّالة الصبح"` · `home.piggy.body: "اتفرج على إعلان وخد جنيهات وبونات"` · `home.piggy.cta: "ببلاش"`
- `nav.home: "الموقف"` · `nav.lines: "الخطوط"` · `nav.apartment: "الشقة"` · `nav.shop: "المحل"` · `nav.a11yLabel: "التنقل الرئيسي"` · `nav.a11yNew: "{tab}، فيها جديد"`
- `home.a11y.profile: "ملف الأسطى والإعدادات"` · `home.a11y.bonat: "البونات {n}، افتح المحل"` · `home.a11y.fuel: "البنزين {fuel} من {max}، اللتر الجاي بعد {m} دقيقة و{s} ثانية"` · `home.a11y.gift: "هدية اليوم، فيها جديد"` · `home.a11y.tasks: "مهام اليوم، خلصت {done} من {total}"` · `home.a11y.challenge: "تحدي اليوم، فيه جديد"` · `home.a11y.event: "مناسبة {name}"` · `home.a11y.garage: "الجراج: زوّق عربيتك"` · `home.a11y.line: "الخطوط: {line}، المشوار {n} من {total}، النجوم {earned} من {max}"` · `home.a11y.savings: "تحويش الجواز: الفصل {n}، الجاية {item}"`
- Dynamic content, not ARB: line sign, barker call, event name.

**Notes.**
- The vehicle opens `/garage`, which is Phase 2. MVP behaviour is undefined (suggest: not tappable in MVP).
- Fuel pill → `/shop` here but → `/shop/fuel` on `HomeStates`. Consider always opening the fuel sheet.
- Event circle colour #3B2A6B reuses `station[0].bg`; it should come from the event theme.
- Non-token values: bubble/daily-circle lip rgba(26,75,140,.18); piggy lip #EED38A; text 12.5 px (piggy subtitle); name Marhey 19.
- The piggy is a `<button>` with no ad-not-ready state drawn; reuse `States` («الإعلان مش جاهز دلوقتي، جرّب كمان شوية»). What the banner shows after today's claim is not specified (suggest hide).

---

#### Home: alternate states (الموقف · البنزين خلص وأوفلاين) — `HomeStates`

| | |
| --- | --- |
| Route | `/home` (same screen as `C-Home`) |
| Feature folder | `features/home/` |
| Phase | MVP |
| Files | `screens/HomeStates.html` · `png/HomeStates.png` |

**Purpose.** One artboard combining three states of Home: **out of fuel**, **offline**, and **early chapter** (chapter 2, tuktuk, apartment still locked). Only the differences from `C-Home` are listed; each state applies on its own.

**Layout, top to bottom (differences only).**

| # | Block | State | Change vs `C-Home` | Tokens |
| --- | --- | --- | --- | --- |
| 1 | Header · bonat pill | offline | Not a link (shop needs network); same look | — |
| 1 | Header · fuel pill | out of fuel | 69×44, bg `danger.soft`, lip 4 #F2A08A; «٠/٥» 15/700; timer «١٢:٣٠» 12/**600** `ink` (not muted); → `/shop/fuel` | `danger.soft`, `ink` |
| 2 | `OfflineBanner` (new row) | offline | y104, 358×40, r14, padding 0 12, gap 8: wifi-off glyph 20 + «انت أوفلاين، المشاوير شغالة والتقدم هيتحفظ لما النت يرجع» (12.5/500, wraps to 2 lines) | bg `dashboard.bg`, glyph `sun`, text `paper` |
| 3 | Scene card | offline (banner present) | Shrinks to **282** high (y154) so the column still fits | — |
| 3 | Scene content | early chapter | `VehicleSprite` `tuktuk` (master's, no roof sign) with 2 riders; بلية (`CharacterAvatar` `bulya`) waves on the right instead of the barker; bubble «الحي.. الحي!» at abs (251,226) 115×33; **no garage hit area** (the tuktuk is not the player's) | `danger` / `danger.dark` tuktuk body |
| 3a | Daily row | no event + offline | 3 circles only (no event). «التحدي» disabled: opacity 0.55, no lip, glyph `icon.off`, label replaced by «محتاج نت», not tappable. Tasks badge «١/٣» | `icon.off` |
| 4 | Line card | early chapter | «خط الحي», «المشوار ٨ من ٢٠», bar 35%, stars «١٤/٦٠» | — |
| 5 | Start CTA | out of fuel | `AppButton` **danger** xl «البنزين خلص» (Marhey 26, `ink` text), lip 6 `danger.ink` (`lip.danger`); chip h30 `paper` bg: timer glyph 16 + «اللتر الجاي ١٢:٣٠» 13/700 `ink`; → `/shop/fuel` | `danger`, `lip.danger`, `ink`, `paper` |
| 6 | Savings card → chapter-goal card | early chapter (apartment locked) | Icon tile 54 `primary.soft` with microbus glyph; title «اشتري الميكروباص»; «الفصل ٢»; row 2: lock glyph 14 + «الشقة بتتفتح في الفصل ٤» (13/500 `ink.muted`) / «١٬٢٤٠ / ٢٬٠٠٠ ج» (13/700); `ProgressBar` gold 62%; → `/apartment` (AptGoal view) | `primary.soft`, `gold`, `ink.muted` |
| 7 | Morning piggy | offline | Not tappable: opacity 0.55, no lip; chip «محتاج نت» (`paper` bg, 13/700 `ink`) replaces «ببلاش»; pig glyph without the coin slot | — |
| 8 | `BottomNav` | offline / early chapter | «المحل» tab disabled: opacity 0.45, label «المحل، محتاج نت», not tappable. «الشقة» → `/apartment` (AptGoal), no `NewDot` | — |

**Dynamic data.**
- Out of fuel: `wallet.fuel == 0` (and no `fuel_unlimited_until` active). Timer as in `C-Home`.
- Offline: connectivity + last request failure (arch §11). Banner shows while offline. Disabled set per arch §11: shop, daily challenge, leagues, rewarded ads (piggy).
- Early chapter: chapter < 4 (`story_state`). Goal title, icon and target from chapter content: ch2 «اشتري الميكروباص» (target = `micro_old` price, sample 2,000); ch1 goal per UX spec is «خلّص خط الحي».

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| Fuel pill / «البنزين خلص» | tap | `/shop/fuel` (sheet over Home) |
| Disabled items (challenge, piggy, shop tab, bonat pill) | tap | No navigation. Optional light haptic; do not show a dialog |
| Chapter-goal card | tap | `/apartment` (pre-chapter-4 goal view) |
| `OfflineBanner` | — | Not interactive |

**States & edge cases.**
- Out of fuel **and** online: CTA danger as above; nothing else changes.
- Fuel refills while on Home: CTA returns to primary «يلا نطلع!» without a reload (timer reaches 0 → `wallet.fuel` 1).
- Network returns: banner hides, scene grows back to 332 (animate height 200 ms), disabled items re-enable.
- Chapter 1 (before the micro): same goal card with the ch1 goal; vehicle `tuktuk`.
- Banner text wraps to 2 lines in a 40 px box at 12.5 px. Allow min-height 40 and grow, or the second line clips at larger text scale.

**Motion.** Banner slides down 200 ms `easeOut`; scene height animates in sync. CTA variant swap: 150 ms crossfade.

**Accessibility.**
- Banner `role=status`: announce once when going offline.
- Labels (HTML): fuel «البنزين خلص، اللتر الجاي بعد ١٢ دقيقة و٣٠ ثانية»; «مهام اليوم، خلصت ١ من ٣»; «تحدي اليوم، محتاج نت» (disabled); line «الخطوط: خط الحي، المشوار ٨ من ٢٠»; goal «الفصل ٢: اشتري الميكروباص القديم»; shop tab «المحل، محتاج نت» (disabled).
- Disabled items expose a disabled state, not just low opacity.

**Strings.**
- `home.offlineBanner: "انت أوفلاين، المشاوير شغالة والتقدم هيتحفظ لما النت يرجع"`
- `common.needsNet: "محتاج نت"`
- `home.ctaOutOfFuel: "البنزين خلص"` · `home.nextLiter: "اللتر الجاي {time}"`
- `home.goal.apartmentLocked: "الشقة بتتفتح في الفصل {n}"`
- `home.a11y.fuelEmpty: "البنزين خلص، اللتر الجاي بعد {m} دقيقة و{s} ثانية"` · `home.a11y.challengeOffline: "تحدي اليوم، محتاج نت"` · `home.a11y.goal: "الفصل {n}: {goalLong}"` · `nav.a11yShopOffline: "المحل، محتاج نت"`
- Goal titles («اشتري الميكروباص», a11y «اشتري الميكروباص القديم») come from chapter content.

**Notes.**
- Disabled opacity is 0.55 (challenge, piggy) and 0.45 (shop tab). Tokens say disabled = 45%; unify to 0.45.
- Fuel pill lip #F2A08A equals `scene.seat.hi` (not semantic); propose `danger.soft.lip`.
- UX spec says the apartment is locked in chapters 1–2; the artboard (and `AptGoal`, «الفصول ١–٣») says it opens in chapter 4. The artboards look like the newer decision; confirm.
- Line bar sample is 35% for «المشوار ٨ من ٢٠» (C-Home: 40% for 12/30). Use completed / total.
- No tab is locked by chapter on this artboard; only Shop is disabled, because of offline.
- The line-card a11y label here omits stars; use the full `home.a11y.line` form.

---

#### كارت ما قبل المشوار — `PreTrip`

| | |
| --- | --- |
| Route | `/home/pre-trip/:tripId` (`Sheet` over `/home`) |
| Feature folder | `features/pre_trip/` |
| Phase | MVP |
| Files | `screens/PreTrip.html` · `png/PreTrip.png` |

**Purpose.** Before the clock starts: station prices, special rules, what's new, star goals and boosters, so the trip isn't confusing. Then «اطلع».

**Layout, top to bottom.**

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 0 | Behind | 390×844 | Home under `Scrim` (drawn as skeleton) | `scrim` (0.60) |
| 1 | `Sheet` | y154 → bottom, 390×690 | Padding 10/16/24, gap 12, top radius 28 | `paper`, `radius.sheet` |
| 1a | Grabber | y164, 44×5, centered | Drag handle | `outline`, r `pill` |
| 1b | Header | y181, h49 | Right: line name «خط الجامعة» over title «المشوار ١٢». Left: close `IconCircleButton` 44 (✕ 18, stroke 2.8), no lip | name `type.caption` 600 `ink.muted`; title `type.display.m` (26); close bg `ground`, glyph `ink` |
| 1c | Station prices | y242, 358×129, r20, padding 12/12/10, gap 10 | Label «أسعار المحطات». Grid 3 cols gap 8; each cell 106×51 r16 padding 8 gap 8: `StationTag` 30 (letter 15/700) + name 13/600 over price «٤٫٥ ج» 16/700. Order right → left = stop order. Rule line: student-card glyph 20 + «الطلبة بنص أجرة لو ورّوا الكارنيه» 13/500 | block `ground`; cells `paper`; tags `station[order]` (bg + letter colour); label `type.caption` 600 `ink.muted` |
| 1d | New in this trip | y383, 358×91, r20, padding 10/12, gap 12 | Avatar circle 60 (`paper`) with `PassengerAvatar` `headphones`; `StatusChip` «جديد» + name «أبو سمّاعة» (Marhey 17); description 13/500 lh 1.5 (2 lines) | bg `sun.soft`; chip `danger` bg + `ink` `type.label` 700; name `type.quote` 700 |
| 1e | Star goals | y486, h100, gap 6 | Label «النجوم»; 3 rows h22, gap 8: star 22 + text 14/500. Earned = filled; not earned = empty star + trailing «لسه» (12/600) | earned `gold`; empty fill `track` stroke `ground.lip` 1.5; «لسه» `ink.muted` |
| 1f | Boosters | y598, h138, gap 6 | Label «المساعدات»; grid 4 cols gap 8, tiles 84×66 r16: glyph 22 + name 12/600 + count «×١» 12/700. Order RTL: كيس فكة, الدفتر, صحّي النايم, زحمة. Buy chip (aligned right) 185×44 r `pill`: «+» 16 + «صحّي النايم بـ٨ بونات» 14/700 | tiles `ground`; chip `primary.soft` + `primary` |
| 1g | CTA | y756, 358×64 (pushed to bottom) | `AppButton` primary xl «اطلع» + fuel chip «−١» (same as Home) | `primary`, `lip.primary`, `type.button.xl`, chip `sun` |

**Dynamic data.**
- Line name ← `TripDefinition.line_id` → line content name; «المشوار {n}» ← `trip_id` index.
- Stations ← `TripDefinition.stations[]`: name from line content, price ← `fare_piasters` (`٤٫٥`, `٧`, `٩` are samples), colour/letter ← stop order (`station` tokens; letter = first letter of the name).
- Rule line ← `TripDefinition.rules` (`student_discount`, `bag_fare_piasters`, `child_free_age`); one line per active rule; hidden if none.
- New card ← first archetype or in-trip event this player has never met (local "seen" set); avatar = archetype skin; name + description from content. Hidden if nothing is new.
- Star rows ← `trip_progress.best_stars` for this trip (1 = finished, 2 = + no fights, 3 = + no mistakes); all three show «لسه» on a first play.
- Booster counts ← `inventory`; buy-chip price ← catalog (`wake_all` 8 BONAT).
- Fuel cost 1.

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| Close ✕ / swipe down / scrim / system back | tap / drag | Dismiss to `/home`; no fuel spent |
| Buy chip | tap | `/shop` (as drawn) |
| Booster tiles | — | Not interactive (display only) |
| «اطلع» | tap | Spend 1 FUEL (`trip_start` op) → `/trip/:tripId` (replace the sheet) |

**States & edge cases.**
- Story trip (not drawn here): header gets a «مشوار قصة» chip + character portrait, plus a `danger` special-condition bar «أبو العروسة راكب: أي خناقة والمشوار يتعاد» above the CTA (UX spec).
- `pre_trip_card_mode` = new-only (Settings): skip the sheet for regular trips with nothing new; always show it for story trips and trips with something new.
- Interstitial ad (rules §3.4) shows **before** the sheet opens, never after «اطلع».
- Overflow (story bar + rules + new card): scroll the body between header and CTA; keep the CTA pinned.
- Lines with 4 stations: the grid is drawn for 3. Needs a 4-column variant (cells ≈ 80 wide; names may need 2 lines).
- Booster count 0: tile looks the same with «×٠»; the buy chip offers that booster.
- Offline: buy chip disabled («محتاج نت»), «اطلع» works.

**Motion.** `sheetIn` 280 ms `easeOutCubic` / `sheetOut` 200 ms `easeInCubic`; scrim fade; `press` on CTA; drag-to-dismiss follows the finger, closes past 25% height or on fling.

**Accessibility.**
- Sheet semantics: dialog labelled by the title «المشوار ١٢»; close «اقفل».
- Station cell read as «الكوبري، ٤٫٥ جنيه» (suggested); star rows read with state («لسه» when not earned); booster tiles «كيس فكة، معاك ١» (suggested); CTA include «هيصرف لتر بنزين».
- Order: header → prices → rule → new → stars → boosters → buy chip → CTA → close.

**Strings.**
- `preTrip.title: "المشوار {n}"` · `preTrip.a11yClose: "اقفل"`
- `preTrip.pricesLabel: "أسعار المحطات"` · `preTrip.price: "{price} ج"`
- `preTrip.newChip: "جديد"`
- `preTrip.starsLabel: "النجوم"` · `preTrip.star1: "وصّل كل الركاب"` · `preTrip.star2: "من غير ولا خناقة"` · `preTrip.star3: "كل باقي يرجع صح من أول مرة"` · `preTrip.starNotYet: "لسه"`
- `preTrip.boostersLabel: "المساعدات"` · `booster.changeBag: "كيس فكة"` · `booster.ledger: "الدفتر"` · `booster.wakeAll: "صحّي النايم"` · `booster.trafficJam: "زحمة"` · `preTrip.boosterCount: "×{n}"`
- `preTrip.buyChip: "{booster} بـ{price} بونات"`
- `preTrip.cta: "اطلع"` · `common.fuelCost: "−{n}"`
- Content (not ARB): rule lines (e.g. «الطلبة بنص أجرة لو ورّوا الكارنيه»), archetype name/description (e.g. «أبو سمّاعة» / «مش سامع حاجة، والفلوس بتقف عنده. ناديه مرتين، أو لِف الفلوس من جنبه.»).

**Notes.**
- UX spec: «زرار "+" يشتري بالبونات» (buy in place). The artboard has one chip linking to `/shop`. Decide: in-place buy with `UndoToast` (Components: 3 s undo for bonat buys < 50) vs navigate. Also which booster gets the chip (first with count 0?) is not specified.
- The «أبو سمّاعة» copy says «أو لِف الفلوس من جنبه» (route money around him). The engine (§7.7) has a Muted passenger **block** the token with no routing around. Copy or engine must change.
- Analytics `trip_start.boosters_loaded` implies pre-loading boosters, but the tiles here are display-only.

---

#### النتيجة — `Result`

| | |
| --- | --- |
| Route | `/trip/:tripId/result` (full screen, scrolls; artboard 390×1100) |
| Feature folder | `features/result/` |
| Phase | MVP |
| Files | `screens/Result.html` · `png/Result.png` |

**Purpose.** Celebrate the payout, say exactly what went wrong, and offer «اقبض ×٢» at the best moment. Then the next trip, the apartment, or share.

**Layout, top to bottom.** Padding 36 / 16 / 24, gap 12, vertical scroll. At 844, the visible part ends around «لأ، خد ٨٥ بس» (the ×2 button, y754–824, is above the fold).

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 1 | Header | y36, h48 | `ScreenHeader`: back `IconCircleButton` 44 (chevron pointing right, lip 4) at the right; centred «المشوار ١٢ · خط الجامعة» (14/600); 44 spacer at the left | back `paper` + `lip.card.small`; title `type.body` 600 `ink.muted` |
| 2 | Task-done banner | y96, 358×40, r14, padding 0 12, gap 8 | Clipboard-check glyph 20 + «مهمة خلصت: رجّع ٢٠ باقي صح» (13/600) + trailing «+٥ بونات» (13/700) | bg `primary.soft`; glyph `primary`; reward `primary` |
| 3 | Title | y148, h40 | «وصلنا الجامعة!», centered, lh 40 | `type.display.xl` |
| 4 | Stars | y200, h112, 3 equal cols gap 8, bottom-aligned | `Stars` (result): RTL order «وصلت» (58), «من غير خناقات» (**72**, middle), «كل باقي صح» (58). Earned: filled + highlight stroke; not earned: outlined. Under each: status glyph 14 (✓ / ✕) + label 12/600 | earned `gold` + `sun.glow` highlight; empty fill `paper` stroke `ground.lip` 1.4; ✓ `primary`; ✕ `danger.ink`; `type.label` |
| 5 | Rider quote | y324, 358×72 | `AppCard`, padding 0 14, gap 12: `PassengerAvatar` 50 on a `ground` circle; «ربنا يكرمك يا ابني.. الباقي وصل» in «» (Marhey 600 17) over speaker «الحاجة» (12/600) | `paper`, `lip.card`, r22; `type.quote`; speaker `ink.muted` |
| 6 | Breakdown | y408, 358×150, padding 7 16 | `AppCard` with 4 `ListRow`s (equal height ≈35, 2 px dividers): «الأجرة اللي اتلمّت» ٧٨٫٥ · «البقشيش» +٧ · «باقي زيادة ضاع» −٠٫٥ · «الخناقات» ٠. Label 14/500 right, value 14/700 left | dividers `track`; tips `primary`; loss `danger.ink`; others `ink` |
| 7 | Mistakes (expandable) | y570, 358×96 (open) | `AppCard` disclosure: summary row h44 «غلطة واحدة ضيّعت النجمة التالتة» (14/700) + chevron 18 (up when open). Item rows: avatar 38 on `danger.soft` + «إديت الطالب زيادة نص جنيه» (14/500), gap 10, padding-bottom 10 | `paper`, `lip.card`, r22 |
| 8 | Payout | y678, h64, centered, gap 12 | «قبضت» (16/600) + coin 34 + «٨٥» (Marhey 700 50) + chip «+٥ بونات» (14/700, padding 2 10) | chip `primary.soft` + `primary` |
| 9 | Double CTA | y754, 358×70 | `RewardedAdButton`: TV glyph 28 + «اقبض ×٢» (Marhey 26) over «+١٧٠ بدل ٨٥» (13/500) | `primary`, `lip.primary`, r22; sub `primary.soft` |
| 10 | Decline link | y836, 358×36 | «لأ، خد ٨٥ بس» (14/600), centered | `AppButton` tertiary, `ink.muted` |
| 11 | Apartment progress | y884, 358×80 | `AppCard` link, padding 0 14, gap 12: item tile 52 r18 (item icon); «الأنتريه» / «١٬٣٢٥ / ٣٬٢٠٠ ج»; `ProgressBar` gold h12 (41%) with a 2% `sun` segment marking this trip's gain; «فاضلك ١٬٨٧٥ ج» (12/500) | tile `sun.soft`; bar `track` / `gold` / gain `sun`; remaining `ink.muted` |
| 12 | Bottom actions | y976, h60, gap 10 | `AppButton` secondary «مشوار تاني» (288×60, Marhey 21, inset ring 2 + lip 5) + chip «−١ لتر» (h26, 12/700); share button 60×60 (share glyph 26) | secondary `paper`, ring/lip `ground.lip`; chip `sun.soft`; share `sun` + `lip.sun` 5 |

**Dynamic data.** From `TripFinished {TripResult}` (§7.2) unless stated.
- Header ← trip index + line name. Title ← «وصلنا {last station name}!».
- Task banner ← daily task completed during this trip (`daily_state`): task name + BONAT reward. Hidden if none. Payout bonat chip shows the same reward.
- Stars ← `stars` + `star_flags {reached, no_fights, no_mistakes}`.
- Quote ← one spoken line from this trip (speech key + speaker skin + archetype name).
- Breakdown ← `fares_collected_piasters`, tips, `overpaid_piasters` (shown negative), `fights`.
- Mistakes ← `mistakes[] {passenger_id, kind, amount}` rendered with per-`kind` templates + passenger avatar; summary sentence by count and lost star. Card hidden when empty.
- Payout ← `earnings_jenehat` (sample 85 = 78.5 + 7 − 0.5).
- Double CTA ← `result_double` availability (1 per trip); «+{2×earnings} بدل {earnings}».
- Apartment card ← next catalog item, `wallet.jenehat` after payout, gain segment = previous → new balance; remaining = price − have.
- «−١ لتر» ← fuel cost 1.

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| Back / system back | tap | `/home` |
| Mistakes summary | tap | Expand / collapse |
| «اقبض ×٢» | tap | `AdsGateway.showRewarded(result_double)` → on reward add another `earnings_jenehat` (`ad_reward` op); payout animates to 170 |
| «لأ، خد ٨٥ بس» | tap | `/home` (base payout already credited) |
| Apartment card | tap | `/apartment` |
| «مشوار تاني» | tap | Interstitial check (§3.4) → `/home/pre-trip/:nextTripId`; if fuel 0 → `/shop/fuel` |
| Share | tap | Render `ShareCard` → OS share sheet (`share_plus`); analytics `share {kind: result_image}` |

**States & edge cases.**
- 3 stars first time: short celebration (decorations + horn) and «رقم قياسي جديد» on the line (UX; not drawn).
- Enough JENEHAT for the next item: card says «تقدر تشتري {item}!» and opens the apartment (UX; not drawn).
- Story trip: the chapter comic (`/story/:chapterId`) opens right after this screen (UX).
- Out of fuel: «مشوار تاني» opens `/shop/fuel`.
- Ad not ready or offline: use the `States` patterns («الإعلان مش جاهز دلوقتي، جرّب كمان شوية»; offline → «محتاج نت»). `remove_ads` and subscriptions do not hide this rewarded offer. After the ×2 is used, hide the CTA and the decline link (suggested; not drawn).
- No mistakes: hide card 7. No task: hide banner 2 and the payout chip.
- Long quote: max 2 lines then ellipsis; speaker 1 line.

**Motion.**
- Stars: `starIn` (350 ms, stagger 250, easeOutBack 1.6), one by one right → left; earned stars burst `lottie/ui/stars.json` (play to marker `one`/`two`/`three`). Labels fade in with their star.
- Payout count-up 0 → value (≤ 600 ms, suggested); ×2 animates to the doubled value.
- Apartment bar fills from old to new balance (UX «شريطها بيتحرك بالمبلغ الجديد»), 600 ms easeOut, after the payout.
- Reduced motion: no bounce/burst, values appear directly.

**Accessibility.**
- Labels (HTML): back «ارجع الموقف»; stars group «نجمتين من تلاتة» (`role=img`); share «شارك النتيجة». Task banner is `role=status` (announce once).
- Order: header → banner → title → stars → quote → breakdown → mistakes → payout → ×2 → decline → apartment → «مشوار تاني» → share.
- Decline link is 36 high: extend its hit area to 44.

**Strings.**
- `result.header: "المشوار {n} · {line}"` · `result.a11yBack: "ارجع الموقف"`
- `result.taskDone: "مهمة خلصت: {task}"` · `result.bonatReward: "+{n} بونات"`
- `result.title: "وصلنا {station}!"`
- `result.star1: "وصلت"` · `result.star2: "من غير خناقات"` · `result.star3: "كل باقي صح"` · `result.a11yStars: "{count} من تلاتة"` (plural forms: «نجمة واحدة» / «نجمتين» / «تلات نجوم» / «ولا نجمة»)
- `result.quote: "«{line}»"`
- `result.fares: "الأجرة اللي اتلمّت"` · `result.tips: "البقشيش"` · `result.overpaid: "باقي زيادة ضاع"` · `result.fights: "الخناقات"`
- `result.mistakesSummary.one: "غلطة واحدة ضيّعت النجمة التالتة"`
- `result.paid: "قبضت"`
- `result.double: "اقبض ×٢"` · `result.doubleSub: "+{doubled} بدل {base}"` · `result.decline: "لأ، خد {base} بس"`
- `result.aptAmount: "{have} / {price} ج"` · `result.aptRemaining: "فاضلك {n} ج"`
- `result.again: "مشوار تاني"` · `result.againFuel: "−{n} لتر"` · `result.a11yShare: "شارك النتيجة"`
- Mistake lines are per-kind templates in content (sample «إديت الطالب زيادة نص جنيه»).

**Notes.**
- Fuel chip differs: here «−١ لتر» on `sun.soft` with no glyph; on Home/PreTrip «−١» on `sun` with a pump glyph. Pick one.
- Selection rule for the quote («أطرف أو أحلى جملة») is not specified (e.g. a `quotable` flag in speech pools).
- Mistakes summary needs plural and which-star variants (only the one-mistake / star-3 sentence is written). Wording for fights is not written.
- UX copy «اديت» vs drawn «إديت»: use the drawn copy.

---

#### صورة المشاركة — `ShareCard`

| | |
| --- | --- |
| Route | none: offscreen image rendered from `/trip/:tripId/result` (not a screen) |
| Feature folder | `features/result/` |
| Phase | MVP (15-second clip replaces it at Public launch) |
| Files | `screens/ShareCard.html` · `png/ShareCard.png` |

**Purpose.** A 360×360 square image of the trip result, shared via the OS share sheet. Shows stars, the rider quote and the game name.

**Layout, top to bottom.** Canvas 360×360, padding 26 / 22 / 20, column centered, gap 10. Render as a widget in a `RepaintBoundary` at pixelRatio 3 → 1080×1080 PNG.

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 0 | Background | 360×360 | Flat + 2 circles: (320,40) r80, (30,330) r90 | `sun` · `sun.glow` |
| 1 | Trip chip | y26, 166×20, centered | «المشوار ١٢ · خط الجامعة» (13/600), padding 2 12, r `pill` | `paper`, `ink` |
| 2 | Title | y56, h39 | «وصلنا الجامعة!» Marhey 700 34, lh 1.15, text shadow (0,4) | `ink`, shadow `sun.lip` |
| 3 | Stars | y105, h62, gap 6, bottom-aligned | RTL: 48 · **62** · 48. Earned: filled + `ink` stroke 1.2; not earned: `sun.soft` fill + `sun.lip` stroke 1.2 | `gold`, `ink`, `sun.soft`, `sun.lip` |
| 4 | Quote card | y177, 316×66, r20, padding 10 12, gap 10 | `PassengerAvatar` 46 on `ground` circle; quote in «» Marhey 600 16 lh 1.35; speaker 12/600 | `paper`, lip 4 `sun.lip`; `type.quote` (16); speaker `ink.muted` |
| 5 | Footer | y305, 316×35 | Right: wordmark «وصّل الأجرة» Marhey 700 20. Left: coin 20 + «قبضت ٨٥» 13/700 | `ink`; coin `gold` / `sun.glow` |

**Dynamic data.**
- Trip chip, title, stars, quote + speaker + avatar, payout ← same sources as `Result`.
- Payout shows the final amount after ×2 if the player doubled (assumption, see Notes).
- Wordmark static.

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| (Result) share button | tap | Build image → `share_plus` with the PNG (file name e.g. `wassal_result_<trip_id>.png`) → OS share sheet; log `share {kind: result_image}` |

**States & edge cases.**
- 0 stars (finished trips always have ≥1; a failed trip has no Result) → not reachable.
- No quote available: drop the quote card and centre the stars (suggested).
- Long quote: max 2 lines; card grows up to 90, footer stays at the bottom.
- Digit setting applies to the image as well.
- Render offscreen with fonts already loaded (Marhey, Readex Pro) to avoid fallback glyphs.

**Motion.** None (static image).

**Accessibility.** N/A for the image. The Result share button carries «شارك النتيجة». Stars group label in the HTML («نجمتين من تلاتة») can be reused as share text alt if the share API takes text.

**Strings.**
- `share.tripChip: "المشوار {n} · {line}"`
- `share.title: "وصلنا {station}!"`
- `share.wordmark: "وصّل الأجرة"`
- `share.paid: "قبضت {amount}"`

**Notes.**
- Stars here have an `ink` outline, the only outlined stars in the system (style C is outline-free). Looks intentional for contrast on yellow; confirm.
- Whether the image shows base or doubled payout, and whether a share text/link (store URL) accompanies it, is not specified.

### Screens: trip, lines, vehicles

#### المشوار — `C-Trip`

| | |
| --- | --- |
| Route | `/trip/:tripId` (full screen, outside the bottom-nav shell; Pause and Fail are overlays on it) |
| Feature folder | `features/trip/` (rules live in `packages/trip_engine`, driven by `TripController`) |
| Phase | MVP |
| Files | `screens/C-Trip.html` · `png/C-Trip.png` |

**Purpose.** The core puzzle. Fares travel seat to seat to the driver; the player builds change in the hand from the tray and sends it to the right passenger before their station, without fights. Everything the player taps, except the passengers, sits in the bottom third.

**Layout, top to bottom.** Screen y in px (frame 390×844). Three fixed zones; nothing scrolls.

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 0 | Top inset | y 0–36 | status bar | `ground` |
| 1 | `TripHud` row | y 36–80, h 44, gutter 16, gap 10 | right: `IconCircleButton` pause (44, two-bar glyph 18). Middle (flex 1): title «خط الجامعة · المشوار ١٢», 1 line. Left: `ReputationBar` block (end-aligned, gap 4): label «السمعة» above a 92×12 pill, fill 72 % | button `paper`, lip `card.small`, glyph `primary`; title `display.s` (lh 1.1); label `label`; bar `paper` + 2 px inset `outline`, fill `primary` (`danger` under 40 %) |
| 2 | `StationStrip` card | y 86–150, h 64, x 16–374, padding 5/14/0 | track row h 26 (y 91–117) + label row h 28 (y 119–147, margin-top 2). Both rows are inset another 14, so the usable track is x 44→346 (302 px). Spec below | `paper`, radius `l`, lip `card.small` |
| 3 | Gap | 8 | — | — |
| 4 | `TripScene` + Flutter overlays | y 158–602 (390×444), clipped, top radius 26 | cabin, windows, 3 benches, 10 seats, money, driver's hand. Scene geometry below | `scene.*`, radius `scene` |
| 5 | `Dashboard` | y 586–844, h 258 (overlaps the scene by 16), top radius 28, padding 12, column gap 6 | 5 rows below. Content is 236 high, so the bottom padding is effectively 10 | `dashboard.bg` |

**StationStrip detail.**
- Track: 6 px pill `track` at y+10 of the track row. The progress fill grows from the right (start) end in `primary`, width = trip progress (sample 24 %).
- Depot: 14 px dot `ground.lip` centred on the right end (x 346). Its label «الموقف» is `label` in `ink.muted`.
- Station dots: 24 px circles in `station[order].bg`, letter `station[order].letter` 12/700 (first letter of the station name). Centre x = 346 − 302 × (`at_seconds` / last `at_seconds`). In the sample they sit at 36 / 68 / 100 % → x ≈ 237 / 141 / 44.
- Next station: 2 px `paper` border + 3 px outer `danger` ring (`ring.hot`).
- Vehicle marker: 28×26, radius 10, `sun`, lip `sun.s`, vehicle glyph 18×13 `primary`. Its centre x uses the same progress value as the fill (sample x ≈ 274).
- Labels (each centred on its dot, `nowrap`): station name 12/700, then «٤٫٥ ج» 12/500. The next station also gets a countdown chip «١٨ث» (`danger` bg, `ink` text, 12/700, pill, padding 0 6).

**Scene geometry** (scene-local px, origin = scene top-left; add 158 for screen y). The background, avatars, money tokens and hand render in Flame (arch §8). `StationTag`, `SpeechBubble`, `LedgerBadge`, `ChoicePopover`, `EventBanner` and the tap targets are Flutter overlays positioned from these coordinates.

| Element | Geometry | Tokens |
| --- | --- | --- |
| Wall / floor | full / rect y 182–444 | `scene.wall` / `scene.floor` |
| Back window | x 120 y 10, 150×52, r 16; 4 building blocks inside | `scene.sky` |
| Light garland | 12 dots r 3, x 130→262 every 12, y 15→18.5→15 (sags) | `danger`; a vehicle cosmetic («أنوار», Phase 2 garage). Only draw it if the player owns it |
| Side windows | left: (0,34)→(90,50)→(94,55…136)→(90,141)→(0,176); right mirrored over x 296–390; buildings scroll (parallax) | `scene.sky` |
| Next-station sign | in the left window: post x 46 y 106, 4×34 (`icon.off`); board x 10 y 76, 76×30, r 10, name 13/700 white centred at (48,96) | board `station[next].bg` |
| Benches | back x 88 y 104, 214×42, r 16 · middle x 46 y 212, 298×50, r 18 · near x 6 y 326, 378×58, r 22. Each has a highlight strip inset 8/4, h 8 / 9 / 10 | `scene.seat`, `scene.seat.hi` |

Seats: the anchor is the head centre; the body extends down to anchor.y + 108 × scale. Seat `col` r/m/l maps to screen right/middle/left. Money moves along its column toward the driver; rows `A` and `front` reach the driver directly (arch §7.7).

| Row (`row`) | Scale (head r) | Anchor x (left→right) | Anchor y | `StationTag` (size, top-left) | Tap target (top-left, w×h, radius 18) |
| --- | --- | --- | --- | --- | --- |
| back `C` | 0.625 (≈26) | 126 · 195 · 264 | 92 | 24 at (90,108) (159,108) (228,108) | 68×80 at (x−34, 62) |
| middle `B` | 0.8 (≈34) | 98 · 195 · 292 | 196 | 26 at (55,219) (152,219) (249,219) | 92×100 at (x−46, 160) |
| near `A` | 1.0 (42) | 62 · 176 · 290 | 308 | 30 at (9,339) (123,339) (237,339) | 112×112 at (6,262) (120,262); right seat 100×80 at (234,262) |
| front | 1.0 | 350 | 392 | 30 at (303,395) | 90×80 at (300,344) |
| driver hand | — | 162 | 398 | — | — |

- **Tag rule:** tag centre = anchor + (−38, +46) × row scale. The front seat is the exception at (−32, +18).
- **Tag style:** 2.5 px `paper` border, lip `0 2px 0 rgba(29,26,43,.25)`, letter 13 / 14 / 16 px 700.
- **Hot tag:** the lip is replaced by a 3 px `danger` outer ring, plus `hotTagPulse`.
- **Sample passengers** (`PassengerAvatar` by `skin`):
  - C.l المستعجل: angry brows, open mouth, `#7CC5E8` sweat drop; tag ك hot.
  - C.m sleeper: head rotated 18°, eyes closed; «z» glyphs Marhey 700 `lavender` 17 px at (214,66) and 22 px at (225,50).
  - C.r student: `danger` cap, `danger.dark` visor; talking.
  - B.l and B.m: a group (same striped shirt).
  - B.r headphones: `dashboard.bg` arc, `gold` cups; `lavender` notes at (342,160–178) and (246,146–160).
  - A.l الحاجة (hijab, glasses), A.m الأفندي (suit, tie, moustache), A.r woman, front: mother.

`MoneyNote`: h 26, min-w 42, padding 0 9, radius 7, 16/700 `ink`, lip 3 (colours from `money_note`).

| Note | Top-left | Kind |
| --- | --- | --- |
| «٥٠» | (167,255) | `fare`: mid-hop from B.m to A.m |
| «١٠» | (262,150) | `blocked`: rests on the blocker's (B.r) head top. A 22 px «؟» badge (`danger`, ink 14/700) sits centred 23 px above it |
| «١٥٫٥» | (150,362), min-w 52, rotated −18° | `in_hand`, held by the driver |
| fallen | not drawn here | Components: fare colours + 4 px `sun.glow` ring, rotated 12° |

Driver hand (comes up from under the dashboard):
- Sleeve: stroke 32 `paper` from (118,500) to (134,456).
- Forearm: stroke 23, skin `#E0A97A`, from (128,470) to (160,404).
- Palm: circle r 15 at (162,398).
- Thumb: ellipse 6×9, `#D69A6C`, at (155,385).

`SpeechBubble` (overlay): radius `bubble` 18, padding 3/14/5, type `bubble` (16/700, lh 1.35), one line, solid 4 px lip. Tail: 14×14 square rotated 45° (radius 0 0 4 0) at bottom −6, horizontally at the speaker's x.
- warn «الباقي يا أسطى!» at (50,22): `danger.soft`, lip rgba(242,84,45,.35). Speaker C.l.
- normal «خد ١٠، طالب» at (212,22): `paper`, lip rgba(26,75,140,.18), tail 46 from the left edge (= x 264). Speaker C.r.
- Placement: the tail tip sits about 8 px above the head top (back row: 58 vs 66). Clamp the bubble inside the scene, 10 px from the edges. At most 2 bubbles (`maxBubbles`); the rest queue. Each stays at least `trip_bubble_min_ms_<line_id>`.

**Dashboard rows.**

| # | Row | Screen y | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| D1 | Hand + call | 598–642, gap 8 | `HandSlot` (flex 1, ≈206 wide): 2 px dashed `sun` border, radius 16, padding 0 10, gap 6. Contains the hand glyph 22 (`sun` stroke), denomination chips (notes min-w 26/24 × 20, r 5; the «نص» coin is a 24 circle; 12/700 ink; gap 3), and the total «= ١٥٫٥» pushed to the end (left). The chips clip (overflow hidden). Next to it, `CallChangeButton` (hug, ≈152): megaphone 17 + «حد معاه فكة؟» 14/700 + «×٢» 12/700, padding 0 12, gap 5 | slot `dashboard.raised`; chips `denomination.<d>.bg`; total `number.l` white; button `sun`, ink, radius 16, lip `sun` |
| D2–3 | `ChangeTray` | 648–692 and 698–742 | 4×2 grid, gap 6, cells 87×44. RTL order: row 1 نص · ١ · ٥ · ١٠; row 2 ٢٠ · ٥٠ · ١٠٠ · ٢٠٠. `TrayCell` full: coin 26 circle (نص, ١) or note 34×20 r 5, then «×n», gap 6, 14/700. Empty: transparent, 2 px dashed border, and the glyph is dashed too | full `paper`, radius `tray`, lip `tray.cell`; glyph `denomination.<d>.bg`, 12/700; empty border `dashboard.line`, text `dashboard.text` |
| D4 | `BoosterButton` ×4 | 748–792 | 87×44 each, radius 14, column: icon 18 + label 12/600 lh 1.2. RTL order: كيس فكة · الدفتر · صحّي النايم · زحمة +١٠ث. Badge at top −9 / left −4 (the top-end corner in RTL), pill, padding 0 7, 12/700 lh 1.5. Badges overlap the tray row above by 3 px, as drawn | `dashboard.raised`, white; badge for count `sun`/ink; for ad and price `primary`/white |
| D5 | `LastWordsLog` | 798–834, h 36 | two centred lines: older «الشلة: خد ٥٠ عن تلاتة» 13/500; newest «الطالب: خد ١٠، طالب» 14/700 | older `dashboard.muted`, newest white |

Prototype only: the invisible 44×44 link at the dashboard's bottom-left («للنموذج بس: افتح شاشة النتيجة») is not built. `/trip/:tripId/result` opens on `TripFinished`.

**Dynamic data.** Everything in the artboard is sample data.
- Title: line name from content (`TripDefinition.line_id`) + `nn` from `trip_id` (`line_gamaa.12` → «١٢»).
- Reputation fill: `TripState.reputation` (0..100); `danger` under 40.
- Strip: `TripDefinition.stations[]` (order → colour, name → letter + label, `fare_piasters` → «٤٫٥ ج»). Progress = `t_ms` / (last `at_seconds` × 1000). Countdown = ceil((next `at_seconds` × 1000 − `t_ms`) / 1000). Hot styling from `StationWarning` (T−8 s).
- Seats and avatars: `TripDefinition.seats[]` + `TripState.passengers{}`. `skin` → look; state → avatar inputs (mood, talking, asleep, headphones, alight); `dest_station_id` → tag colour and letter. A tag is hot when the passenger is owed change and their station is warned. Empty seats show only the bench; boarding and alighting follow `PassengerBoarded` / `PassengerAlighted`.
- Window sign: the next station's name and colour.
- Bubbles: `PassengerSpeaks {passenger_id, speech_key, params}` → a speech-pool line (arch §14.2). The variant (normal / warn / fight / thanks) follows the key.
- Money: `TripState.tokens[]`. `kind` fare → fare colours; change / return / redirect → change colours; `blocked_by` set → blocked. Position is interpolated along `path` (`hop_index`, `hop_progress_ms`); the label is the sum of `amount[]`.
- Hand: `TripState.hand[]`. Tray: `TripState.tray{}`. Call count: 2 − breaks used (engine limit 2 per trip).
- Boosters: count from drift `inventory`, price from the content catalog, ad badge from `AdsGateway.isReady('traffic_jam')` + cap 1 per trip, «+١٠ث» from config, active timer from the engine.
- Log: the last 2 spoken or event lines, as `"{speaker}: {line}"`.

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| Pause button / Android back | tap | `pause()`, then the Pause overlay |
| `TrayCell` (count > 0) | tap | `PickFromTray(denomination)`, coin sound, pressed state (cell moves down 3, lip → 0) |
| `TrayCell` empty | tap | nothing (no sound) |
| `HandSlot` with money | tap | `ReturnHand()` |
| Passenger, hand not empty | tap | `SendHand(passenger_id)`: the target glows for 0.5 s, the hand throws, and a `change` token runs the chain. A «رجّع» control is live for 1000 ms (`trip_undo_window_ms`) → `UndoLastSend()`. **The undo control is not drawn; proposal: a `sun` pill inside `HandSlot`** |
| `HandSlot` → passenger | drag | same as tap-to-send |
| Passenger, empty hand | tap | `Tap(passenger_id)`: asks for the fare, wakes a sleeper, or calls a headphones passenger (needs 2 taps; they stay attentive for 15 s). On a passenger who already paid (or the false claimer) it triggers the «أنا دافع!» claim (see `TripEvents`) |
| `CallChangeButton` | tap | Break mode (Components): the button turns `danger` with «اختار ورقة ١٠+», and tray notes ≥ 10 with count > 0 become `breakable` (`sun.soft` + 3 px `danger` ring). Tapping one → `RequestBreak(d)`; a passenger breaks it after 1.5 s (`BreakCompleted`) |
| Fallen note | tap within 3 s | `CollectDropped(token_id)` |
| `BoosterButton` with count | tap | `UseBooster(id)`: `change_bag` fills the tray; `ledger_peek` shows ledger badges and a timer; `wake_all` wakes everyone; `traffic_jam` adds +10 s to the next station |
| `BoosterButton`, count 0, price badge | tap | Spend BONAT, then use. Show an `UndoToast` «اتشرى كيس فكة بـ١٠ بون» with «رجّع ٣» for 3 s (prices < 50; ≥ 50 asks to confirm; Components/States) |
| «زحمة» with ad badge | tap | `pause()` first (no ad calls while running, arch §15.1), show the rewarded ad `traffic_jam`, apply the booster on reward, then resume |

**States & edge cases.**
- Empty hand: «فاضية» 16/600 `dashboard.text`; aria «إيدك فاضية» (drawn in `TripEvents`).
- Many denominations in hand: the chips clip and the total stays visible. Proposal: merge equal notes as «١٠×٢».
- Reputation: under 40 % the fill turns `danger`. At 0, `TripFailed` → Fail overlay.
- Countdown under 8 s: the chip grows and pulses. Owed passengers' tags turn hot and pulse.
- Passed station: dot at 35 % and the price replaced by «عدّت» (drawn in `TripEvents`).
- `CallChangeButton` at ×0, or no note ≥ 10 in the tray: disabled (45 % opacity, no lip).
- Booster badge states: count / price / ad / active (`TripEvents`). If the ad isn't ready or the device is offline, fall back to the price badge «٨ بون». The States message «الإعلان مش جاهز دلوقتي، جرّب كمان شوية» applies.
- Vehicle layouts: tuktuk = near row only (3); `micro_old` = as drawn (10); `micro_new` / `micro_safar` add a 4th row (12). **4th-row geometry is not drawn.**
- Bubble queue: a bubble is never removed before its minimum duration; a third speaker waits.
- Long text: the HUD title is 1 line with an ellipsis. Station labels are `nowrap` and centred; names longer than about 9 characters at 12 px collide with neighbours, so content should cap them.
- App backgrounded or phone call → `pause()`; the Pause overlay shows on return. Content packs never swap during a trip.
- Variants on other artboards: story trip → `StoryTrip`; tutorial (tuktuk + coach marks) → `Tutorial`.

**Motion.**
- Money hops: `moneyHop` per line (hay 1300 / gamaa 1100 / market and later 900 ms, from `trip_hop_ms_<line_id>`), `easeInOut`. ×2 when the holder is `hajja`; the group redirect hop is 600 ms.
- Bubbles: `bubblePop` in, fade out after the minimum duration. Hot tags and the countdown under 8 s: `hotTagPulse`.
- Alight: `alight` (600 ms, dy −12, fade). Boarding: enters from the right door (not drawn).
- Fight or bump: `screenShake` 300 ms (amplitude 6) + haptic. Controls: `press` 80 ms. Target glow: 500 ms before the throw.
- Side windows scroll as parallax; the next-station sign grows as the stop nears.
- `PassengerAvatar` (Lottie) states: calm, talking, impatient (sweat), asleep (z), headphones (notes), angry, alight.
- Reduced motion: no shake, bubble pop, parallax or pulse (the hot ring stays static); fades ≤ 150 ms.

**Accessibility.**
- The scene SVG is decorative. Each seated passenger is a button labelled «{name}، {نازل/نازلة/نازلين} {station}».
- Append «، ليه باقي» only while that passenger's tag is hot. Example from the HTML: «المستعجل، نازل الكوبري، ليه باقي».
- The front seat reads «الأم في الكرسي اللي قدام، نازلة المستشفى».
- Labels:
  - Pause: «إيقاف مؤقت».
  - Strip: «المحطات وأسعارها»; dashboard: «التابلوه»; tray group: «درج الفكة».
  - Tray cells: «نص جنيه، معاك ١», «جنيه، معاك ٣», «١٠٠ جنيه، مفيش».
  - Hand: «في إيدك ١٥ ونص. دوس ترجّعها للدرج».
- Boosters have no label in the HTML. Proposal: «{name}، {badge}», e.g. «الدفتر، معاك واحد».
- `LastWordsLog` is the only `aria-live="polite"` region; bubbles are not announced separately.
- Reading order: HUD → passengers top to bottom, right to left (the HTML DOM runs left to right; reverse it) → hand, call button, tray (right to left), boosters, log.
- All targets are ≥ 44 (back-row passenger 68×80, tray cell 87×44).

**Strings.** Speech lines («الباقي يا أسطى!», «خد ١٠، طالب») come from the speech pools, not ARB. Denomination glyph labels come from `denomination.<d>.label`.
```
trip.pauseA11y: "إيقاف مؤقت"
trip.title: "{lineName} · المشوار {n}"
trip.reputation: "السمعة"
trip.stationsA11y: "المحطات وأسعارها"
trip.depot: "الموقف"
trip.stationFare: "{fare} ج"
trip.countdown: "{s}ث"
trip.dashboardA11y: "التابلوه"
trip.handA11y: "في إيدك {amountWords}. دوس ترجّعها للدرج"
trip.handTotal: "= {total}"
trip.callChange: "حد معاه فكة؟"
trip.callChangeCount: "×{n}"
trip.callChangePick: "اختار ورقة ١٠+"
trip.trayA11y: "درج الفكة"
trip.trayCellA11y: "{denomName}، معاك {n}"
trip.trayCellEmptyA11y: "{denomName}، مفيش"
trip.trayCount: "×{n}"
trip.denomHalf: "نص جنيه"
trip.denomOne: "جنيه"
trip.denomN: "{n} جنيه"
trip.boosterChangeBag: "كيس فكة"
trip.boosterLedger: "الدفتر"
trip.boosterWake: "صحّي النايم"
trip.boosterTraffic: "زحمة +{s}ث"
trip.boosterCount: "×{n}"
trip.boosterAd: "إعلان"
trip.boosterPrice: "{n} بون"
trip.passengerA11y: "{name}، {alightVerb} {station}"
trip.passengerOwedA11ySuffix: "، ليه باقي"
trip.frontSeatA11y: "{name} في الكرسي اللي قدام، {alightVerb} {station}"
trip.blockedMark: "؟"
trip.logLine: "{speaker}: {line}"
```

**Notes.**
- Zone heights: the UX spec says HUD ≈ 110 and dashboard 230, the design has 114 / 258. Follow the design (tokens `layout.trip`).
- Scene size: arch §8 gives the Flame scene as 390×470, the design has 390×444 (16 hidden under the dashboard, min 420). Align §8.
- Ledger duration: UX spec and Components say 5 s, arch §3.3 says 10 s.
- Undo «رجّع» (1 s after a throw) is specified but not drawn.
- The «زحمة» ad conflicts with the no-ads-while-running rule unless the trip pauses first.
- The bubble and station-tag lips use translucent colours that are not tokens.
- The garland lights appear only in `C-Trip` and `BuyVehicle`; treat them as a cosmetic.

---

#### المشوار: أحداث واختيارات — `TripEvents`

| | |
| --- | --- |
| Route | `/trip/:tripId` (runtime states of `C-Trip`) |
| Feature folder | `features/trip/` |
| Phase | MVP (`fare_increase`, «أنا دافع!» and `ledger_peek` on `line_gamaa`) |
| Files | `screens/TripEvents.html` · `png/TripEvents.png` |

**Purpose.** Three trip states shown at once: the «الأجرة زادت!» event, the «الدفتر» booster running, and a «أنا دافع!» claim waiting for the player's verdict. Only differences from `C-Trip` are listed.

**Layout, top to bottom (differences only).** Scene coordinates are scene-local.

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 1 | `ReputationBar` | — | sample 64 % | — |
| 2 | `StationStrip` | — | Progress 46 %, marker between ك and م. **Passed** ك: dot at opacity 0.35, no ring; label «الكوبري» + «عدّت» in `ink.muted`. **Next** م (hot ring): label shows the old fare struck through «٧» (`ink.muted`), the new fare chip «٨ ج» (`danger.soft`, radius 6, padding 0 4, 700), and the countdown «٢٢ث» | — |
| 3 | `EventBanner` (fare raised) | scene x 10→380, y 8–62, h 54, padding 0 14, gap 10 | Warning triangle 26 (ink, with the glyph in `danger`), then a column: «الأجرة زادت!» Marhey 700 18 and «المستشفى بقت ٨ بدل ٧. صحّح للي دفع بالقديم» 13/600. `role="alert"`. Covers the back window | `danger` bg, `ink` text, radius `bubble`, lip 4 `danger.ink` |
| 4 | Window sign | as `C-Trip` | «المستشفى» on `station[2].bg` (it is now the next station) | — |
| 5 | `LedgerBadge` ×8 | h 18, pill, padding 0 8, 12/700 | Shown instead of the station tags while the ledger is active. Centred on the face x. Top-left: back (104,132) «دافع», (176,132) «لسه», (242,132) «دافع»; middle (62,246) «على صاحبه», (176,246) «دافع», (272,246) «لسه»; near (42,352) «دافع», (270,352) «دافع». A.m is hidden by the popover; no badge is drawn for the front seat | paid `primary`/white · notYet `danger`/ink · onFriend `paper`/ink |
| 6 | Claim | A.m (176,308) | Avatar with angry brows (`#5A3A28`) and open mouth. `SpeechBubble` normal «أنا دافع!» at (116,228), tail centred. `ChoicePopover` at (70,370) (screen y 528–582): `paper`, radius 18, padding 5, gap 6, lip 4 rgba(26,75,140,.25). Buttons h 44, radius 14, padding 0 16, 15/700: «ماشي» (`ground`, ink) and «لأ، ما دفعتش!» (`danger`, ink, lip 3 `danger.ink`) | — |
| 7 | `HandSlot` empty | D1 | hand glyph + «فاضية» 16/600 at the end | `dashboard.text` |
| 8 | `CallChangeButton` | D1 | «×١» (one break used). The megaphone icon is missing here; keep it as in `C-Trip` | — |
| 9 | `BoosterButton` | D4 | **الدفتر active:** `primary` bg + 2 px inset `sun` ring, `aria-pressed="true"`, badge «٤ث» (`sun`/ink) counting down. **صحّي النايم** at count 0 shows a price badge «٨ بون» (`primary`/white) | — |
| 10 | `LastWordsLog` | D5 | «الأجرة زادت: المستشفى بقت ٨» / «الأفندي: أنا دافع!»; system events also write to the log | — |

**Dynamic data.**
- Banner: `EventStarted {event_id: fare_increase}` gives the station and the new fare. The old fare stays struck through until the station passes.
- Ledger badge per passenger:
  - paid: their fare reached the driver.
  - notYet: not paid yet.
  - onFriend: a group member whose fare the group payer sent.
  - Badges are visible while `ledger_peek` is active; the timer shows the seconds left.
- Claim: `ClaimRaised` (passenger_id); the popover is anchored under that face.
- Tray counts differ from `C-Trip` (sample).

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| «ماشي» | tap | `ResolveClaim(id, insist: false)`; if he lied, the fare is lost |
| «لأ، ما دفعتش!» | tap | `ResolveClaim(id, insist: true)`. If he lied: `LiarCaught` (reputation +10). If he had paid: `FalseAccusation` (reputation −20, fight bubble + shake) |
| `EventBanner` | — | not interactive; hides by itself |
| الدفتر while active | tap | no-op (proposal) |

**States & edge cases.**
- UX: «كل نافذة بتوقف الوقت لحد ما اللاعب يقرر». Call `pause()` while the `ChoicePopover` is open (confirm).
- The popover must stay inside the visible scene (bottom ≤ 428 scene-local).
- The «أنا دافع!» bubble covers the middle-row badges («على صاحبه», «دافع»). Bubbles draw above badges.
- Events not on this artboard:
  - Bump: fallen notes (Components).
  - Traffic: stopped cars in the windows, slower countdown.
  - Open road: faster windows and countdown.
  - «نزّلني هنا»: the passenger's tag becomes `StationTag alightHere` (30 px `sun` star, 3 px `danger` ring, pulsing; Components).
  - Payment dispute: «مين اللي دفع؟» popover with two 56×56 faces; selected = 3 px inset `primary` (Components).
  - Change request («فكّله» / «معلش») and roadside pickup: **not drawn**.

**Motion.**
- Banner: slides down from the top of the scene (`sheetIn`) and back up (`sheetOut`).
- Strip fare change: the old price strikes through, then the new chip pops in (`bubblePop`).
- Ledger badges: fade in and out (≤ 150 ms).
- Popover: `dialogIn`.
- False accusation: fight bubble + `screenShake`.

**Accessibility.**
- Banner `role="alert"`: announce once.
- Popover `role="group"` labelled «الأفندي بيقول إنه دفع»; focus moves to «ماشي».
- While badges show, append «، دافع / لسه / على صاحبه» to each passenger label.
- Active booster: pressed state, read as «الدفتر، فاضل ٤ ثواني».

**Strings.**
```
trip.fareRaisedTitle: "الأجرة زادت!"
trip.fareRaisedBody: "{station} بقت {newFare} بدل {oldFare}. صحّح للي دفع بالقديم"
trip.fareRaisedLog: "الأجرة زادت: {station} بقت {newFare}"
trip.stationPassed: "عدّت"
trip.ledgerPaid: "دافع"
trip.ledgerNotYet: "لسه"
trip.ledgerOnFriend: "على صاحبه"
trip.claimA11y: "{name} بيقول إنه دفع"
trip.claimAccept: "ماشي"
trip.claimInsist: "لأ، ما دفعتش!"
trip.handEmpty: "فاضية"
trip.handEmptyA11y: "إيدك فاضية"
trip.boosterTimer: "{s}ث"
```
«أنا دافع!» is a speech-pool line.

**Notes.**
- The passed-station dot uses 0.35 opacity (Components does too). Confirm this is allowed, given the "never opacity" rule for locked items.
- How the player "corrects" an old-fare payer has no command in arch §7.4 (Tap to ask the difference?).
- No banner duration is specified. Proposal: the line's bubble minimum.
- No ledger badge position is given for the front seat.

---

#### مشوار قصة — `StoryTrip`

| | |
| --- | --- |
| Route | `/trip/:tripId` (a trip flagged as a story trip in content, e.g. the «قصة» cells in `LineDetails`) |
| Feature folder | `features/trip/` (the comic afterwards is `features/story/`, `/story/:chapterId`) |
| Phase | MVP for ch1–4 story trips («مشوار الفرح», ch7: public launch) |
| Files | `screens/StoryTrip.html` · `png/StoryTrip.png` |

**Purpose.** The same trip with a story character in the front seat who comments on every mistake, and a special condition shown for the whole trip (here: any fight means a replay). Only differences from `C-Trip` are listed.

**Layout, top to bottom (differences only).**

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 1 | HUD title | 2 lines, lh 1.15 | `StatusChip` «مشوار قصة» (start-aligned, pill, padding 0 8) above the story title «أبو العروسة راكب». No line name or trip number | chip `sun`, `label` 700; title `display.s` |
| 2 | Strip | — | sample progress 18 %; countdown «٣١ث» (no pulse while ≥ 8 s) | — |
| 3 | Condition strip | scene x 10→380, y 8–48, h 40, padding 0 12, gap 8 | Shield-check icon 20 (`sun` shield, ink check) + «أبو العروسة راكب: أي خناقة والمشوار يتعاد» 13/600. `role="note"`. Visible for the whole trip | `dashboard.bg`, white text, radius 14 |
| 4 | Window | — | the sample shows a building in the left window (no sign). Keep the next-station sign as in `C-Trip` | — |
| 5 | Front seat | anchor (346,392), scale 1.05 | `CharacterAvatar` (أبو العروسة: grey hair, glasses, moustache, dark suit) instead of a passenger. No `StationTag`, no tap target | — |
| 6 | Character bubble | right edge x 294, top 352, content max-w 200 (≈ x 66–294, y 352–426) | `SpeechBubble` character: name «أبو العروسة» 12/600 `ink.muted`, then «الأستاذ اللي ورا مستعجل.. شوف باقيه.» in `quote` (Marhey 600, 16, lh 1.4), max 2 lines. Padding 6/14/8, lip 4 rgba(26,75,140,.25). Tail on the right edge (right −7, top 26) pointing at the character | `paper`, radius `bubble` |
| 7 | Warn bubble | (62,160), tail at right 30 | «الباقي يا أسطى!» from B.l (المستعجل: angry brows, frown, sweat drop) | as `C-Trip` |
| 8 | Hot tag | B.l (55,219) | `ring.hot` + pulse | — |
| 9 | Dashboard | — | hand «٥ + نص = ٥٫٥», «×٢», boosters ×2/×1/×1/إعلان; log «المستعجل: خد ١٠، نازل الكوبري» / «أبو العروسة: شوف باقيه». No money in flight; no garland | — |

**Dynamic data.**
- Story chip and title, condition text, character skin and name: story-trip content (chapter, e.g. `ch2_her_father`).
- Character comments: lines from the character's speech pool, triggered by mistakes (`ChangeDelivered over`, `FalseAccusation`, fights, missed stops).
- Story rule (here: no fights) comes from content.

**Interactions.** As in `C-Trip`. The character is not tappable (no target is drawn).

**States & edge cases.**
- A fight under the «no fights» condition means the trip must be replayed. **Not drawn:** whether this shows `Fail` (with or without revive) or goes straight to a retry.
- The character bubble covers the near-row tags of A.m and A.r (y 339–369). Raise the tags above it, or offset the bubble.
- While the condition strip shows, clamp bubbles below scene y 56 (proposal).
- The pre-trip card always shows for story trips (UX). After `Result`, open `/story/:chapterId`.
- Wedding trip: decorated vehicle and different music (UX), **not drawn**.

**Motion.**
- Character bubble: `bubblePop`.
- `CharacterAvatar` (Lottie) frowns on mistakes.
- The condition strip is static.

**Accessibility.**
- The title reads «مشوار قصة، أبو العروسة راكب».
- The condition strip (`role="note"`) is read right after the HUD.
- Character lines reach the log, so they are announced once through it.

**Strings.**
```
trip.storyChip: "مشوار قصة"
trip.storyTitle: "{storyTripTitle}"
trip.storyCondition: "{conditionText}"
trip.characterName: "{characterName}"
```
Title, condition text («أبو العروسة راكب: أي خناقة والمشوار يتعاد») and character name come from story content.

**Notes.**
- The UX spec asks for an orange condition strip under the station strip; the design uses a dark strip at the top of the scene. Follow the design.
- The middle-row bubble is drawn at y 160 over its own speaker's forehead, unlike `C-Trip` (tail 8 above the head top). The global geometry rule should decide.
- Station tags here have no lip; use the `C-Trip` style.

---

#### نافذة الإيقاف — `Pause`

| | |
| --- | --- |
| Route | overlay on `/trip/:tripId` (no route of its own; the engine is `paused`) |
| Feature folder | `features/trip/` |
| Phase | MVP |
| Files | `screens/Pause.html` · `png/Pause.png` |

**Purpose.** Freezes the trip. The player resumes, restarts (costs fuel) or leaves, and can flip sound and vibration.

**Layout, top to bottom.**

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 1 | Background | full | the frozen trip screen (the artboard uses placeholders) | — |
| 2 | `Scrim` | full | rgba(29,26,43,.62) | `scrim.coach` |
| 3 | `AppDialog` | x 16–374 (358), top y 170, h ≈ 435 (hugs content), padding 22/18/18, column gap 12 | `role="dialog"`, labelled by the title | `paper`, radius 26 (`scene`), lip 6 rgba(0,0,0,.25) |
| 3a | Illustration | 72×56, centred | Microbus side view: body `primary`, windows `scene.window`, tyres `dashboard.bg`, ground `scene.floor`, light `danger`. Static asset | — |
| 3b | Title | — | «واقفين على جنب», centred | `display.l` |
| 3c | Subtitle | — | «الوقت واقف. الركاب مستنيينك.», centred | `caption`, `ink.muted` |
| 3d | Resume | h 60 | `AppButton` primary «كمّل المشوار» (Marhey 700 23) | `primary`, radius 20, lip `primary` |
| 3e | Restart | h 54, gap 10 | `AppButton` secondary «عيد المشوار» 17/700 + fuel chip (h 26, pill, padding 0 8, fuel glyph 13, «−١ لتر» 12/700) | `paper`, radius 18, inset 2 `ground.lip` + lip 4 `ground.lip`; chip `sun.soft` |
| 3f | Home | h 48 | `AppButton` tertiary «ارجع الموقف» 15/700 | `primary` text |
| 3g | Toggles | border-top 2, padding-top 4; two halves, gap 10, each padding-top 10 | label 14/600 + `AppSwitch` 52×30 (padding 3, knob 24): «الصوت» on, «الاهتزاز» off | border `track`; switch on `primary`, off `ground.lip`, knob `paper` |

**Dynamic data.**
- Switch values: the same sound and vibration settings as `Settings` (profile settings JSON).
- Fuel cost: 1 per trip start (economy).
- Everything else is static.

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| «كمّل المشوار» | tap | close the overlay and resume the engine → `C-Trip` |
| «عيد المشوار» | tap | abandon the trip (no result) → `/home/pre-trip/:tripId` (same trip; fuel is spent on «اطلع» there) |
| «ارجع الموقف» | tap | abandon the trip → `/home` |
| `AppSwitch` | tap | toggle and persist immediately; sound mutes at once |
| Android back | press | same as «كمّل المشوار» (proposal; arch: back on the trip opens Pause) |

**States & edge cases.**
- Opens automatically on app background or a phone call (UX «مقاطعة»), shown on return.
- Fuel 0: «عيد المشوار» still routes to the pre-trip card, which handles the empty tank (Fuel sheet).
- Leaving or restarting has no confirmation step (not drawn). Fuel refund for an abandoned trip is open (arch §24.4).

**Motion.**
- Scrim fades in (150 ms); card `dialogIn`; buttons `press`.
- Closing: reverse the fade.

**Accessibility.**
- Dialog labelled by «واقفين على جنب»; focus starts on «كمّل المشوار».
- Switches use `role="switch"` with labels «الصوت» and «الاهتزاز».
- Trip audio and haptics are silent while paused.

**Strings.**
```
pause.title: "واقفين على جنب"
pause.subtitle: "الوقت واقف. الركاب مستنيينك."
pause.resume: "كمّل المشوار"
pause.restart: "عيد المشوار"
pause.fuelCost: "−{n} لتر"
pause.home: "ارجع الموقف"
pause.sound: "الصوت"
pause.vibration: "الاهتزاز"
```

**Notes.**
- Off-token values: the 23 px CTA font (between `button.l` 21 and `button.xl` 27), the dialog lip rgba(0,0,0,.25), and the 60 px button height.
- The fuel hint is a `sun.soft` chip here but plain text in `Fail`.

---

#### فشل المشوار — `Fail`

| | |
| --- | --- |
| Route | overlay on `/trip/:tripId` (engine status `failed`) |
| Feature folder | `features/trip/` |
| Phase | MVP |
| Files | `screens/Fail.html` · `png/Fail.png` |

**Purpose.** Reputation hit zero. The player can make up with the passengers once (rewarded ad or BONAT) and continue from the same point, or restart or go home.

**Layout, top to bottom.**

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 1 | Background | full | the frozen trip: all passengers angry, reputation bar empty/`danger` | — |
| 2 | `Scrim` | full | rgba(29,26,43,.66) | nearest `scrim.coach` |
| 3 | `AppDialog` | x 16–374, top y 120, h ≈ 430 (hugs content), padding 20/18/16, gap 12 | `role="dialog"`, labelled by the title | `paper`, radius 26, lip 6 rgba(0,0,0,.25) |
| 3a | Angry faces | 210×70, centred | 3 heads: scale 0.62 at x 40; hijab 0.7 at x 105; 0.62 at x 170 (with sweat drop). Angry brows, frowns | `PassengerAvatar` angry |
| 3b | Title | — | «المشوار باظ», centred, Marhey 700 30 | — |
| 3c | Reason chip | centred, pill, padding 3 12 | «خناقتين، وراكب فاتته محطته من غير باقيه» 13/600 | `danger.soft`, `ink` |
| 3d | Revive (ad) | h 66, padding 0 14, gap 10 | `RewardedAdButton`: ad glyph 26 (white) + column «صالح الركاب» Marhey 700 22 white / «إعلان قصير · السمعة ترجع ٤٠٪ وتكمّل من نفس النقطة» 12/500 | `primary`, radius 20, lip `primary`; subline `primary.soft` |
| 3e | Revive (BONAT) | h 54, gap 8 | `AppButton` secondary: BONAT ticket 22 (`primary`) + «صالح بـ٢٠ بون» 17/700 | `paper`, radius 18, inset 2 + lip 4 `ground.lip` |
| 3f | Caption | — | «الصلح مرة واحدة في المشوار», centred, 12/500 | `ink.muted` |
| 3g | Bottom row | gap 8, two tiles flex 1, h 48, radius 16 | «عيد المشوار» 15/700 + «−١ لتر» 12/600 `ink.muted` · «ارجع الموقف» 15/700 | `ground` bg, `ink` |

**Dynamic data.**
- Faces: up to 3 passengers from this trip, angry pose. Proposal: those who fought or missed their stop first.
- Reason: built from `TripState.counters` and `PassengerAlighted` outcomes (fights, left without change, missed stop), joined with «، و». Needs Arabic dual/plural forms (خناقة / خناقتين / {n} خناقات).
- «٤٠٪» from `rep_revive_to`; «٢٠» from the `revive` catalog price; «−١ لتر» from the fuel cost.
- Revive availability: `trip_revive` ad cap 1 per trip, revive once per trip.

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| «صالح الركاب» | tap | `AdsGateway.showRewarded('trip_revive')`. On reward: `Revive()` (reputation → 40), the overlay closes and the trip continues |
| «صالح بـ٢٠ بون» | tap | Spend 20 BONAT (`spend_bonat` op, optimistic offline), then `Revive()` |
| «عيد المشوار» | tap | → `/home/pre-trip/:tripId` |
| «ارجع الموقف» | tap | → `/home` |
| Android back / scrim | — | no dismiss; a choice is required (proposal) |

**States & edge cases.**
- Already revived this trip: hide 3d–3f and keep 3g (not drawn).
- Offline, ad not ready, or ad cap reached: the ad button is disabled (45 %, no lip) with «محتاج نت» or the States message «الإعلان مش جاهز دلوقتي، جرّب كمان شوية». The BONAT path stays.
- Ad cancelled or failed: stay on Fail, nothing spent.
- Not enough BONAT (< 20): **not drawn**. Proposal: open `/shop`.
- Copy length: the 3d subline wraps to 2 lines in the PNG. Let the button grow (min 66), or shorten the copy.
- Story-trip fail variant (fight under the «no fights» rule): not drawn (see `StoryTrip`).

**Motion.**
- Before the card: every passenger in the scene switches to the angry pose (UX).
- Then scrim fade + card `dialogIn`.

**Accessibility.**
- Dialog labelled by «المشوار باظ»; the reason chip is read right after it.
- Initial focus on «صالح الركاب», labelled «صالح الركاب، إعلان قصير، السمعة ترجع ٤٠٪».
- All targets ≥ 48.

**Strings.**
```
fail.title: "المشوار باظ"
fail.reviveAd: "صالح الركاب"
fail.reviveAdSub: "إعلان قصير · السمعة ترجع {pct}٪ وتكمّل من نفس النقطة"
fail.reviveBonat: "صالح بـ{price} بون"
fail.reviveOnce: "الصلح مرة واحدة في المشوار"
fail.restart: "عيد المشوار"
fail.fuelCost: "−{n} لتر"
fail.home: "ارجع الموقف"
fail.reasonFights: "{n, plural, one{خناقة} two{خناقتين} other{{n} خناقات}}"
fail.reasonLeftUnpaid: "راكب فاتته محطته من غير باقيه"
fail.reasonJoin: "، و"
```

**Notes.**
- Off-token values: title 30 px (between `display.l` 28 and `display.xl` 32) and scrim 0.66.
- The UX spec names the ad button «صالح الركاب»; the booster glossary names it «صالح الراكب».

---

#### الخطوط — `Lines`

| | |
| --- | --- |
| Route | `/lines` (bottom-nav tab, inside the shell) |
| Feature folder | `features/lines/` |
| Phase | MVP (the «ملك الخط» strip is public launch and not drawn) |
| Files | `screens/Lines.html` · `png/Lines.png` |

**Purpose.** Long-term progress. The player sees which vehicles they own and the line map, opens a line to play it, or sees what unlocks the next one.

**Layout, top to bottom.**

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 1 | Header | y 36–88, h 52, space-between | Title «الخطوط». Left (gap 6): `CurrencyPill` coins «١٬٢٤٠» (not tappable) and `CurrencyPill` BONAT «٨٥» → `/shop`. Pills h 40, padding 0 6 0 12, icon 22, 15/700 | title `display.l`; pills `paper`, lip `card.small` |
| 2 | Vehicle strip | y 98–194, h 96, 4 columns ≈ 83.5, gap 8, radius 18 | `role="list"` «العربيات», RTL: توكتوك · قديم · جديد · سفر. Done: check badge 20 (`primary`, white tick) at top 6 left 6, name 12/600. Current: «قديم · عربيتك» 12/700. Locked: sprite at 50 % opacity, name 12/600, coin 12 + «٥٬٠٠٠» 12/700 | done `paper` + lip `card.small`; current `sun` + lip `sun`; locked 2 px dashed `icon.off`, transparent |
| 3 | Line map | y 204–744 (540), padding-right 34 | Dashed road: 6 px wide, x 356–362, inset 20 top/bottom, dashes 10 on / 8 off. Cards stacked bottom-up (first line at the bottom), gap 12, h 92, x 16–340 (324) | road `icon.off` |
| 3a | Locked line ×3 (y 204, 308, 412) | padding 0 14, gap 12 | Lock icon 24 (`ink.muted` stroke) · title Marhey 700 17 + reason 12/500 («محتاج ميكروباص سفر», «بعد خط السوق», «محتاج ميكروباص جديد · الشنط والمتهرب») · trailing fare 13/700. Node: 24 circle with 3 px inset `icon.off` ring at right −32, top 34 | `locked.bg` + 2 px inset `outline`, text `ink.2`, radius `card`; node fill `ground` |
| 3b | Current line (y 516) | gap 10 | Title «خط الجامعة» + fare chip «٨٫٥ ج» (pill, 12/700) · features «نص الأجرة، الدفع الجماعي، «أنا دافع!»» 12/500 · stars: star 16 + «٢٧/٩٠ · المشوار ١٢ من ٣٠» 13/700 · trailing «كمّل» (h 44, padding 0 16, radius 16, Marhey 700 17). Node: 32×32, radius 10, vehicle glyph, at right −36, top 30 | `paper`, lip `card` + 3 px inset `primary` (`ring.selected`); title `display.s`; chip `ground`; features `ink.2`; star `gold`; button `primary`, lip `primary.s`; node `sun` + lip `sun.s` |
| 3c | Done line (y 620) | gap 12 | Title «خط الحي» + `StatusChip` «خلص» · stars «٥٤/٦٠ · عيد عشان النجوم» · fare «٧ ج». Node: 24 circle with white tick | `paper`, lip `card`; chip `primary.soft`/`primary`; node `primary` |
| 4 | `BottomNav` | y 756–844, h 88 | «الخطوط» active; `NewDot` on «الشقة» (sample) | global |

**Dynamic data.**
- Balances: wallet `JENEHAT`, `BONAT`.
- Vehicles: `ownership` + the active vehicle. Price from the content catalog. The short names «توكتوك/قديم/جديد/سفر» come from content.
- Lines: from the content pack, ordered by unlock. State:
  - done: all trips completed.
  - current: has a next trip.
  - locked: unlock rule is a `vehicle_id` or a previous line.
- Reason text: «محتاج {vehicle}» or «بعد {line}», plus «· {new mechanics}» from content. Fare: the line's base fare.
- Stars = Σ `trip_progress.best_stars` / (trips × 3). «المشوار {next} من {total}».
- All values are sample data (e.g. 27/90, 54/60, 1,240).

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| BONAT pill | tap | `/shop` |
| Vehicle tile (all four, as drawn) | tap | `/lines/vehicle/:vehicleId` |
| Locked line that needs a vehicle | tap | `/lines/vehicle/:vehicleId` for the required vehicle |
| Locked line that needs a previous line («خط المصيف») | tap | `/lines/:lineId` (as drawn) |
| Current or done line card | tap | `/lines/:lineId` (the whole card is one link, «كمّل» included) |
| `BottomNav` | tap | switch tab |

**States & edge cases.**
- First session: tuktuk is current, `line_hay` is current, and `line_gamaa` is locked «محتاج ميكروباص قديم».
- Lines that are not in the installed content pack (later phases): hide them (proposal). The sample shows all five.
- More lines than fit in 540 px: the map scrolls, and the road grows with it. On open, scroll so the current line is visible.
- Long names: title 1 line with ellipsis; reason 1 line with ellipsis.
- Offline: fully local, works.

**Motion.**
- Cards and tiles: `press`.
- After a vehicle purchase the tile switches to current. No animation is drawn.

**Accessibility.**
- Vehicle labels from the HTML: «توكتوك المعلم، خلصته», «ميكروباص قديم، عربيتك دلوقتي», «ميكروباص جديد، بـ٥٬٠٠٠ جنيه», «ميكروباص سفر، بـ١٢٬٠٠٠ جنيه».
- Line cards have no label in the HTML. Proposal: «{line}، {state}، {detail}», e.g. «خط السوق، مقفول، محتاج ميكروباص جديد».
- Reading order: header → vehicles right to left → lines top to bottom → nav.

**Strings.**
```
lines.title: "الخطوط"
lines.vehiclesA11y: "العربيات"
lines.vehicleCurrent: "{shortName} · عربيتك"
lines.vehicleDoneA11y: "{name}، خلصته"
lines.vehicleCurrentA11y: "{name}، عربيتك دلوقتي"
lines.vehicleLockedA11y: "{name}، بـ{price} جنيه"
lines.lockNeedsVehicle: "محتاج {vehicleName}"
lines.lockAfterLine: "بعد {lineName}"
lines.fare: "{fare} ج"
lines.stars: "{earned}/{max}"
lines.tripOf: "المشوار {n} من {total}"
lines.continue: "كمّل"
lines.done: "خلص"
lines.replayForStars: "عيد عشان النجوم"
```

**Notes.**
- Locked vehicle tiles (dashed `icon.off` border + 50 % opacity sprite) break the locked rule (`locked.bg` + outline ring + `ink.2`, never opacity). The locked line cards follow it.
- UX spec: "the current line has a «كمّل» button". The HTML makes the whole card open `LineDetails`. Consider «كمّل» → pre-trip for the next trip.
- Owned and current vehicle tiles also open `BuyVehicle`, but no owned variant is drawn (Garage in Phase 2?).

---

#### تفاصيل الخط — `LineDetails`

| | |
| --- | --- |
| Route | `/lines/:lineId` (sheet over `/lines`) |
| Feature folder | `features/lines/` |
| Phase | MVP |
| Files | `screens/LineDetails.html` · `png/LineDetails.png` |

**Purpose.** Shows every trip on a line with its best stars. The player replays finished trips for stars or plays the next one.

**Layout, top to bottom.**

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 1 | Background | full | `/lines` dimmed | `scrim` |
| 2 | `Sheet` | y 124–844, h 720, top radius 28, padding 10/16/24, gap 14 | `role="dialog"`, labelled by the title | `paper`, radius `sheet` |
| 2a | Grab handle | 44×5, pill, centred | — | `outline` |
| 2b | Header | row, gap 10 | Title «خط الجامعة» (Marhey 700 26) over a subtitle: star 16 + «٢٧ من ٩٠ نجمة · ١١ مشوار خلص» 13/600. Left: `IconCircleButton` close (44, ✕ 18) | title `display.m`; star `gold`; subtitle `ink.muted`; close bg `ground` |
| 2c | Trip grid | 5 columns (cell ≈ 65×62), gap 8, radius 16; RTL with 1 at the top-right; 4 rows (trips 1–20) | `role="list"` «مشاوير الخط». Cell states below | radius `m` |
| 2d | Hint | centred | «والمشاوير من ٢١ لـ ٣٠ بتظهر لما تقرّب» 12/500 | `ink.muted` |
| 2e | Info note | padding 10/12, gap 10 | info icon 22 (`primary` circle, white «!») + «المشاوير اللي خلصت تتعاد عشان النجوم. الجاية بتتفتح لما اللي قبلها يخلص.» 13/500, lh 1.5 | `ground`, radius 18 |
| 2f | CTA | y 756–820 (pinned to the bottom) | `AppButton` primary xl «العب المشوار ١٢» (Marhey 700 24) | `primary`, radius 22, lip `primary` |

Cell states:

| State | Look |
| --- | --- |
| done | `ground` bg; number 16/700; `Stars` 12 (earned `gold`, missing `ground.lip`) |
| story done | `sun.soft` bg; `StatusChip` «قصة» (`sun`, 12/700, lh 16, padding 0 6) centred at top −6 |
| current (next) | `primary` bg, lip `primary.s`; number 18/700 white + «كمّل» 12/700; `aria-current="step"` |
| locked | 2 px dashed `ground.lip` (`ring.empty`), transparent; number 16/600 `ink.muted`; lock 14 `icon.off` |
| story locked | 2 px dashed `gold` border; «قصة» chip at top −8 |

**Dynamic data.**
- Line name (content).
- Subtitle: Σ best stars, max (trips × 3), completed count, all from `trip_progress`.
- Per-cell best stars; story flags from content; the next trip is the first uncompleted one.
- Visible range: drawn up to trip 20 with the rest summarised (rule unclear; see Notes).
- CTA number = the next trip.
- Sample: the header says 27, but the cells add up to 25.

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| Done / story-done cell | tap | `/home/pre-trip/:tripId` (replay for stars) |
| Current cell | tap | `/home/pre-trip/:tripId` |
| Locked cell | tap | nothing (not a link) |
| CTA | tap | `/home/pre-trip/:nextTripId` |
| Close / swipe down / back | — | pop to `/lines` |

**States & edge cases.**
- Line fully done: the CTA is not drawn. Proposal: hide it, or offer a replay.
- `LineDetails` for a locked line (reachable from «خط المصيف»): not drawn.
- 20-trip line (`line_hay`): 4 rows, no hint.
- More than 4 rows: the grid scrolls inside the sheet above the pinned CTA (proposal).
- Fuel 0: handled by the pre-trip card. Whether replaying costs fuel is open (arch §24.5).
- Counts need plural rules («١١ مشوار», «٣ مشاوير»).

**Motion.**
- Sheet: `sheetIn` / `sheetOut`; scrim fade.
- Cells and CTA: `press`.

**Accessibility.**
- Cell labels from the HTML: «المشوار ١، تلات نجوم», «المشوار ٣، نجمتين», «المشوار ٧، نجمة», «المشوار ١٠، مشوار قصة، تلات نجوم», «المشوار ١٢، الجاي», «المشوار ١٣، مقفول», «المشوار ٢٠، مشوار قصة، مقفول».
- Close: «اقفل». Focus starts on the title.

**Strings.**
```
lineDetails.summary: "{stars} من {max} نجمة · {done} مشوار خلص"
lineDetails.closeA11y: "اقفل"
lineDetails.tripsA11y: "مشاوير الخط"
lineDetails.story: "قصة"
lineDetails.continue: "كمّل"
lineDetails.moreTrips: "والمشاوير من {from} لـ {to} بتظهر لما تقرّب"
lineDetails.info: "المشاوير اللي خلصت تتعاد عشان النجوم. الجاية بتتفتح لما اللي قبلها يخلص."
lineDetails.cta: "العب المشوار {n}"
lineDetails.tripA11y: "المشوار {n}، {state}"
lineDetails.state3: "تلات نجوم"
lineDetails.state2: "نجمتين"
lineDetails.state1: "نجمة"
lineDetails.stateNext: "الجاي"
lineDetails.stateLocked: "مقفول"
lineDetails.stateStory: "مشوار قصة"
```

**Notes.**
- The pre-trip route lives under `/home`. From here, either switch to the Home tab and open the sheet, or add `/lines/:lineId/pre-trip/:tripId` **(new route)**.
- Locked cells use a dashed ring + `ink.muted` instead of the locked rule.
- The CTA font (24) is off the `button.xl` token (27).
- The visible-range rule (shown up to 20 while on trip 12; perhaps "up to the next story trip") is not specified.

---

#### شراء العربية — `BuyVehicle`

| | |
| --- | --- |
| Route | `/lines/vehicle/:vehicleId` (sheet over `/lines`) |
| Feature folder | `features/lines/` |
| Phase | MVP for the sheet (`tuktuk`, `micro_old`); the sample vehicle `micro_new` is Phase 2 |
| Files | `screens/BuyVehicle.html` · `png/BuyVehicle.png` |

**Purpose.** The player weighs a bigger vehicle (more seats, a new line, more fare per trip) against the apartment savings goal, both paid in JENEHAT.

**Layout, top to bottom.**

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 1 | Background | full | `/lines` dimmed | `scrim` |
| 2 | `Sheet` | y 154–844, h 690, top radius 28, padding 10/16/24, gap 12 | `role="dialog"`, labelled by the title | `paper`, radius `sheet` |
| 2a | Grab handle | 44×5, centred | — | `outline` |
| 2b | Header | row, gap 10 | Title «ميكروباص جديد» (Marhey 700 26) + `IconCircleButton` close 44 | `display.m`; close bg `ground` |
| 2c | Preview | 358×190 (y ≈ 237–427), clipped | Sun r 22. Ground y 150–190 with a shadow ellipse. `VehicleSprite` wearing the player's cosmetics (sample: garland, star sticker, `sun` route sign «السوق» on the roof). Chip «بزينتك» (pill, 12/700, padding 2 10) at top 12, right 12 | bg `scene.sky`, radius `xl`; sun `sun.glow`; ground `scene.kerb`; shadow `scene.shadow`; chip `paper` |
| 2d | Benefits | 3 columns ≈ 114, gap 8; equal height (≈ 79) | `role="list"`. Tiles centred, padding 10/8, gap 4, labels 12/600: «١٢» (Marhey 700 22) + «كرسي بدل ١٠» · route icon 26 (`primary`) + «بيفتح خط السوق» · coin-up icon 26 (`gold`) + «قبض أكتر في كل مشوار» (2 lines) | `ground`, radius `m` |
| 2e | Price card | padding 4 14, h ≈ 92 | Row h 44: «السعر» 14/500 ↔ coin 22 + «٥٬٠٠٠» (Marhey 700 22). 2 px divider. Row h 40: «معاك» 14/500 ↔ «٦٬١٠٠ ج» 15/700 | `paper`, radius 18, inset 2 `track`; divider `track` |
| 2f | Apartment impact | padding 10/12, gap 10 | ring icon 24 + «بعد الشرا، فاضل للنجفة ٢٬٤٠٠ ج» 14/600, lh 1.5 | `sun.soft`, radius 18 |
| 2g | Buttons | y 756–820, gap 10 | «اشتريها» flex 2: `AppButton` primary h 64, Marhey 700 25. «لسه» flex 1: h 64, 17/700 | primary: `primary`, radius 22, lip `primary`; «لسه»: `ground`, radius 22 |

**Dynamic data.**
- Vehicle name, seats, the line it unlocks, price (catalog, JENEHAT), and owned cosmetics: content + `ownership`.
- «بدل ١٠»: seat count of the active vehicle.
- «معاك»: wallet JENEHAT.
- Impact line: the next unbought apartment item, with remaining = item price − (balance − vehicle price). Item name and price come from apartment progression.
- All numbers are sample data.

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| «اشتريها» | tap | `EconomyService.apply(spend_jenehat)` + `ownership` row. The vehicle becomes active and its line unlocks. The sheet closes → `/lines` |
| «لسه» / ✕ / swipe down / back | — | pop to `/lines`, nothing spent |

**States & edge cases.**
- Not enough JENEHAT: per the UX spec, «ناقصك {n} ج» replaces «اشتريها». Not drawn here. `Piece` shows the pattern: a `danger.ink` 15/700 label above the CTA. Components also shows a disabled «اشتريها» (45 %, no lip).
- Vehicle already owned or current (all tiles link here): **not drawn**.
- No next apartment item, or nothing left to save after the purchase: hide the impact line (proposal).
- No cosmetics owned (before the Phase 2 garage): show the plain sprite and hide «بزينتك» (proposal).
- Offline: works (JENEHAT is optimistic and synced later).
- Benefit labels: max 2 lines, centred.
- No success feedback is drawn.

**Motion.**
- Sheet: `sheetIn` / `sheetOut`; buttons `press`.
- The `VehicleSprite` may idle (Lottie).

**Accessibility.**
- Dialog labelled by the vehicle name; the preview is decorative.
- The price card reads «السعر ٥٬٠٠٠ جنيه، معاك ٦٬١٠٠ جنيه».
- Close: «اقفل». Both buttons are 64 px tall.

**Strings.**
```
buyVehicle.withCosmetics: "بزينتك"
buyVehicle.seatsVs: "كرسي بدل {n}"
buyVehicle.unlocksLine: "بيفتح {lineName}"
buyVehicle.moreEarnings: "قبض أكتر في كل مشوار"
buyVehicle.price: "السعر"
buyVehicle.balance: "معاك"
buyVehicle.balanceValue: "{n} ج"
buyVehicle.apartmentImpact: "بعد الشرا، فاضل {itemNameWithLi} {amount} ج"
buyVehicle.buy: "اشتريها"
buyVehicle.later: "لسه"
buyVehicle.shortfall: "ناقصك {amount} ج"
buyVehicle.closeA11y: "اقفل"
```

**Notes.**
- The impact copy needs the item name in its «لـ» form («النجفة» → «للنجفة»). Content should store it, or the string needs a helper. The UX example names «الأنتريه ١٬٨٠٠» instead.
- The CTA font (25) is off the `button.xl` token (27).

### Screens: apartment, story, shop

Conventions used in this part:

- `y` = top edge in the 390-wide artboard, `h` = height, both in logical px. Widths are 358 (gutter 16) unless stated. "Right/left" are as drawn (RTL: right = start).
- Colours that have no token are written as hex and marked **(non-token)**. Wallet = `wallet` table (§11); content = content pack (§14.1); RC = Remote Config key (§14.3).
- All numbers, names, prices and counts in the artboards are sample data unless a row says "static".
- Arabic plurals: «بون / بونات», «مرة / مرتين / مرات» must go through ICU `plural` (Arabic has zero/one/two/few/many/other). Only the forms drawn are given below; other forms need copy.

---

#### الشقة · الفصول ١–٣ — `AptGoal`

| | |
| --- | --- |
| Route | `/apartment` (shell tab «الشقة»). Same route as `AptRooms`; this variant renders while the current chapter is `ch1_first_job`, `ch2_her_father` or `ch3_shabka`. |
| Feature folder | `features/apartment/` |
| Phase | MVP |
| Files | `screens/AptGoal.html` · `png/AptGoal.png` |

**Purpose.** Before the apartment opens, the tab shows one savings goal for the current chapter (tuktuk key, old microbus, then the engagement ring «الشبكة»). The player sees how close they are, and the empty apartment teases what comes from chapter 4.

**Layout, top to bottom.** Content column: padding 0 16 12, gap 10, above a fixed `BottomNav`.

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 1 | Header | y36 h52 | Title «تحويش الجواز» on the right. `CurrencyPill` coins (h40, coin icon 22) on the left. | title `display.l`; pill `paper`, `radius.pill`, `lip.card.small`, 15/700 `ink` |
| 2 | Chapter bar (tappable) | y98 h56 | «الفصل ٣ · الشبكة» on the right. On the left: «كل الفصول» + chevron 16 pointing left. Padding 0 14. | bg `primary`, `radius.l`, `lip.primary.m`; title Marhey 700 18 (`display.s`) `paper`; trailing 13/600 `primary.soft` |
| 3 | Goal card | y164 h391 | `AppCard` (big). Padding 14, gap 12. Holds 3a–3d. | `paper`, `radius.scene` (26), `lip.card.big` |
| 3a | Goal art | y178 h190, w330 | Goal illustration (ring box on a halo, two sparkles). | bg `sun.soft`, `radius.l`; halo `sun.glow` |
| 3b | Goal row | y380 h41 | Goal name «الشبكة» on the right. «٢٬٢٠٠ / ٦٬٠٠٠ ج» on the left. Baseline-aligned. | name `display.m` (24); amount 15/700 `ink` |
| 3c | Progress | y433 h14 | `ProgressBar` gold, 37% in the sample | track `track`, fill `gold`, `radius.pill` |
| 3d | Character line | y459 h82 | `CharacterAvatar` 46 (circle, `paper` bg, bust cropped at the bottom). Then the quote (Marhey 600 16, lh 1.4) with speaker «أم العروسة» below it. | box `ground`, `radius.bubble`, padding 10/12, gap 10; quote `quote`; speaker `label` `ink.muted` |
| 4 | Locked apartment teaser | y565 h179 (fills the space down to y744) | Empty-room art 120×96 on the right. Lock icon 18 + «شقة العُمر», then the body text. Not tappable. | `paper` + 2px inset `outline` ring, `radius.xl`, padding 12/14; title `display.s`; body `caption` `ink.2`, lh 1.5 |
| 5 | `BottomNav` | y756 h88 | «الشقة» active | shared component |

**Dynamic data.**

- Coins pill and «{saved}» → `wallet.jenehat`.
- Chapter number and name → `story_state` current `chapter_id` + content chapter title.
- Goal art, goal name, «{target}» and the character line (avatar, quote, speaker) → content chapter definition for ch1–3.
- Progress = `min(jenehat, target) / target`. ch1's goal is "finish line_hay", which is not an amount: see Notes.
- Teaser card: static copy.

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| Chapter bar | tap | push `/apartment/chapters` (`Chapters`) |
| `BottomNav` items | tap | `/home`, `/lines`, `/shop`. Tapping «الشقة» again scrolls to top (no-op). |
| Teaser card, goal card | — | inert |

**States & edge cases.**

- Goal reached (saved ≥ target): not drawn. Progress caps at 100%. What CTA appears is open (see Notes).
- ch1 (goal = finish `line_hay`): same card, but the progress unit is trips. Not drawn.
- Large balances: the pill grows in width and the title keeps its size. The goal row amount never wraps (`maxLines 1`).
- Quote: at most 2 lines; ellipsis after that.
- Offline: works fully (local data).

**Motion.**

- Chapter bar press: `press` (moves down 5, lip → 0).
- `ProgressBar` animates from the last-seen value to the current one on entry, using the `sheetIn` timing (280 ms easeOutCubic). There is no dedicated token.
- `CharacterAvatar` plays its idle loop. Reduced motion: static.

**Accessibility.**

- Reading order: title → coins → chapter bar → goal name, amount, progress → quote → teaser → nav.
- `BottomNav` label from HTML: «التنقل الرئيسي».
- Proposed labels:
  - Pill: «الجنيهات {n}».
  - Chapter bar: «الفصل {n}: {name}، كل الفصول».
  - Progress: «الشبكة، {saved} من {target} جنيه».
- Chapter bar is 56 high, so it meets the 44 minimum.

**Strings.**

- `aptGoal.title: "تحويش الجواز"`
- `aptGoal.chapterBar: "الفصل {n} · {chapterName}"`
- `aptGoal.allChapters: "كل الفصول"`
- `aptGoal.progress: "{saved} / {target} ج"`
- `apartment.title: "شقة العُمر"` (shared with `AptRooms`)
- `aptGoal.lockedBody: "فاضية ومستنياك. العفش بيبدأ من الفصل ٤: الصالة."`
- Content (not ARB): goal name «الشبكة», quote «الشبكة أول حاجة الناس بتسأل عليها يا ابني», speaker «أم العروسة».

**Notes.**

- No completion state or CTA is drawn for a reached goal. ch2 is completed by buying `micro_old` in `BuyVehicle`. How ch3 «الشبكة» is "bought" is not defined anywhere: `spend_jenehat` (backend §7.4) allows `item | vehicle | upgrade`, so the ring could be an `item`, or the goal could unlock a story trip «مشوار الصاغة». Needs a decision and a design.
- The ch1 goal is "خلّص خط الحي" (product spec), not an amount, so the «{saved} / {target} ج» row has no ch1 design.
- The teaser card uses a `paper` background with the `outline` ring. The token rule for locked cards says `locked.bg`. Keep `paper` as drawn, or switch to `locked.bg`: designer to confirm.
- UX Home states say "before the apartment opens (ch1 and 2)". The UX apartment section says ch1–3. The design follows ch1–3.

---

#### الشقة · من الفصل ٤ — `AptRooms`

| | |
| --- | --- |
| Route | `/apartment` (shell tab «الشقة»). Renders from `ch4_salon` onwards. |
| Feature folder | `features/apartment/` |
| Phase | MVP (salon, ch4). Kitchen tab: Phase 2 (ch5). Bedroom tab: Public launch (ch6). |
| Files | `screens/AptRooms.html` · `png/AptRooms.png` |

**Purpose.** The player furnishes the current room. They see the room with what they already bought, tap a missing item's slot to open the item sheet, and track the chapter, the bride's family requests and the scene they will unlock.

**Layout, top to bottom.** Content column: padding 0 16 12, gap 10, above a fixed `BottomNav`.

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 1 | Header | y36 h52 | «شقة العُمر» + `CurrencyPill` coins | as in `AptGoal` |
| 2 | Chapter bar (tappable) | y98 h56 | Right: «الفصل ٤ · الصالة» (Marhey 700 17, lh 1.25) over «أهل العروسة جايين الخميس» (12/500). Left: «جهّزت ٢ من ٤» (12/600) over a `ProgressBar` 80×8 at 50%. | bg `primary`, `radius.l`, `lip.primary.m`; subtitle `primary.soft`; bar track `primary.lip`, fill `sun` |
| 3 | Rooms row | y164 h44 | `Segmented` (sun), w258, padding 4, gap 4. Tabs h36: «الصالة» 74, «المطبخ» 74, «أوضة النوم» 93 (flex 1.3). Locked tabs have a lock 12. On the left, a requests button 92×44: list icon 18 + «الطلبات» + `CountBadge` 20 at top-left (−6, −4). | segmented `paper`, radius 16 (`radius.m`), `lip.card.small`; active tab `sun`, radius 12, 13/700 `ink`; locked tab transparent, 13/600 `ink.muted`; requests button `sun.soft`, radius 16, lip 4 `#EED38A` **(non-token)**, 13/700; badge `danger` bg, 12/700 `ink` |
| 4 | Room scene | y218 h300 | Room illustration with owned items in their chosen style, and a dashed outline for each missing slot. Each missing slot has a chip (`PriceTag`-style pill, h44): blue circle 30 with «+» + «{item} · {price}». Chip positions in the sample: النجفة at x134 y290; الأنتريه at x132 y426. | card bg `#F6E7D4` **(non-token)**, `radius.scene`, `lip.card.big`; chip `paper`, `radius.pill`, lip 4 `rgba(26,75,140,.2)` **(non-token)**, 14/700 `ink`; «+» circle `primary`; outlines `#B9A07C` dashed 3px **(non-token, art)** |
| 5 | Room items grid | y528 h120 | `role=list`, 2 columns 175 wide, gap 8, cards h56, padding 0 12. Three card states: **owned**: name + «اتركّبت» with a check 14, not tappable, no lip. **Next target**: name + «ناقصك ١٬٨٧٥» + `ProgressBar` h6 (41%). **Other missing**: name + «٢٬٤٠٠ ج». | card `paper`, `radius.bubble`; tappable cards `lip.card.small`; name 14/600; owned status 12/700 `primary`; shortfall 12/700 `danger.ink`; price 13/700 `ink`; bar track `track`, fill `gold` |
| 6 | Next-scene strip | y658 h48 | Clapper icon 20 + «خلّص الصالة وافتح مشهد «زيارة أهل العروسة»». Not tappable. **(new component)** `InfoStrip`: a dark strip, same look as `OfflineBanner`. | `dashboard.bg`, `radius.m`, padding 0 12, gap 8; text `caption` `paper`; icon `sun` |
| 7 | `BottomNav` | y756 h88 | «الشقة» active | shared |

**Dynamic data.**

- Coins → `wallet.jenehat`.
- Chapter number, name and tagline («أهل العروسة جايين الخميس») → content chapter.
- «جهّزت {owned} من {total}» → count of `ownership` items in the chapter's room / room item count.
- Tabs → content rooms (`salon`, `kitchen`, `bedroom`). A tab is locked until its chapter starts (`story_state`).
- Requests badge → number of open family requests in `story_state` (see Notes for which ones count).
- Room scene → `ownership` (item + chosen style) drawn over the room background. Slot geometry (outline + chip anchor) comes from the content item definition, authored in a 358×300 design space and scaled.
- Item prices → content catalog (§13). Shortfall = `price − wallet.jenehat`. Progress = `jenehat / price`.
- Next-scene strip → content: current room name + the chapter's scene title.

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| Chapter bar | tap | push `/apartment/chapters` |
| Unlocked room tab | tap | switch room. Scene, grid and strip update. |
| Locked room tab | tap | inert (`aria-disabled`). No feedback is drawn. |
| «الطلبات» | tap | open sheet `/apartment/requests` (`Requests`) |
| Slot chip / missing-item card | tap | open sheet `/apartment/item/:itemId` (`Piece`), e.g. `salon.nish`-style ids |
| Owned item card | — | inert (as drawn) |
| `BottomNav` | tap | shell navigation |

**States & edge cases.**

- After a purchase (UX): the item drops into its slot, its chip disappears, the card turns to «اتركّبت», and a Salma `SpeechBubble` comment appears over the room. Not drawn.
- Room complete: the UX asks for a short celebration + BONAT reward + «شوف المشهد», which opens `/story/:chapterId`. **Not drawn.**
- Requests badge hidden when the count is 0.
- Overlapping slot chips: chip anchors are content data. They are clamped inside the 358×300 card (8 px inset). Names stay on 1 line (`maxLines 1`, ellipsis at 160 px).
- Grid names: 1 line, ellipsis. Status/price text never wraps and keeps priority.
- Rooms with 5–6 items (product spec allows 4–6): the grid grows by rows of 56 + gap 8. The column then needs to scroll (the artboard has 38 px spare). Make the content column a scroll view.
- Offline: fully works (JENEHAT purchases are offline-capable, §11).

**Motion.**

- `press` on the chapter bar, chips, cards and requests button.
- Tab switch: crossfade the scene ≤150 ms.
- Item drop-in after purchase: about 300 ms ease-out drop + settle (no token, propose `dialogIn` timing). Salma bubble uses `bubblePop`.
- Reduced motion: fades only.

**Accessibility.** Labels from the HTML:

- Tablist «الغرف».
- Requests button «طلبات أهل العروسة، ٢ مفتوحين» → `{n}`.
- Chips «الأنتريه، ٣٬٢٠٠ جنيه» → `{item}، {price} جنيه`.
- Grid list «قطع الصالة» → `قطع {room}`.
- Locked tabs: `aria-disabled` + read «مقفولة».

Other requirements:

- Tab buttons are 36 high. Extend the hit area to the full 44 row.
- The badge is decorative (its count is in the button label).

**Strings.**

- `apartment.title: "شقة العُمر"`
- `aptRooms.chapterBar: "الفصل {n} · {roomName}"`
- `aptRooms.progress: "جهّزت {owned} من {total}"`
- `aptRooms.requests: "الطلبات"`
- `aptRooms.requestsA11y: "طلبات أهل العروسة، {n} مفتوحين"`
- `aptRooms.slotChip: "{item} · {price}"`
- `aptRooms.slotA11y: "{item}، {price} جنيه"`
- `aptRooms.itemsA11y: "قطع {roomName}"`
- `aptRooms.installed: "اتركّبت"`
- `aptRooms.shortfall: "ناقصك {amount}"`
- `aptRooms.price: "{price} ج"`
- `aptRooms.nextScene: "خلّص {roomName} وافتح مشهد «{sceneName}»"`
- Content: room names, item names, chapter tagline, scene name.

**Notes.**

- Item card rule is ambiguous. With 1,325 saved, both النجفة (2,400) and الأنتريه (3,200) are unaffordable, yet only الأنتريه shows «ناقصك» + progress. This matches the Home card «الجاية الأنتريه»: one "next target" item gets the shortfall view. How the next item is chosen (content order? last opened? cheapest?) is unspecified. Affordable items presumably show the price, and maybe a highlight; this is not drawn.
- Locked room tabs use transparent + `ink.muted` + lock, not the locked-card rule (`locked.bg` + `outline` ring + `ink.2`). Keep as drawn: `Segmented` locked segment.
- `CountBadge` in the component board is `primary`/white. Here it is `danger`/`ink`, the `NewDot` palette. Designer to confirm which.
- UX lists the next-scene strip as non-interactive. Kept inert.

---

#### لوح القطعة — `Piece`

| | |
| --- | --- |
| Route | `/apartment/item/:itemId` (sheet over `/apartment`) |
| Feature folder | `features/apartment/` |
| Phase | MVP |
| Files | `screens/Piece.html` · `png/Piece.png` |

**Purpose.** Shows one apartment item large. The player picks one of three styles (same price) and buys it with saved pounds. If they can't afford it yet, the sheet shows the shortfall and sends them out on a trip.

**Layout, top to bottom.** Behind: `AptRooms` + `Scrim` (`scrim`). `Sheet` top at y144, h700, padding 10 16 24, gap 12.

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 0 | Sheet + grabber | y144 h700; grabber 44×5 at y154 | `Sheet` | `paper`, top radius `radius.sheet`; grabber `outline`, `radius.pill` |
| 1 | Header | y166 h64 | Room label «الصالة» (13/600) over the title «الأنتريه». `IconCircleButton` close 44 on the left. | label `caption` `ink.muted`; title Marhey 700 26 (`display.m`); close bg `ground`, no lip, ✕ 18 `ink` |
| 2 | Preview | y242 h210 | Item art in the selected style. Top-right: `StatusChip` with the style name «مودرن» (12/700, padding 2 10). | bg `#F6E7D4` **(non-token)**, `radius.xl`; chip `paper`, `radius.pill` |
| 3 | Style picker | y464 h92 | `role=radiogroup`, 3 columns × 114, gap 8: كلاسيك (right) · مودرن · شعبي (left). Each: thumbnail 64×40 + name. Selected: `paper` + selected ring + lip. Unselected: `ground`, no lip. | radius 18 (`radius.bubble`); selected `ring.selected` (3 `primary`) + `lip.card.small`, label 13/700 `primary`; unselected label 13/600 `ink` |
| 4 | Salma comment | y568 h56 | `CharacterAvatar` 40 (Salma) + «سلمى: «المودرن هيبقى لايق على الستاير الحمرا»» | bg `sun.soft`, `radius.bubble`, padding 8 12; text 13/600 lh 1.5 `ink` |
| 5 | Price box | y636 h94 | Row 1 (h44): «السعر (نفسه لكل الأشكال)» + coin 22 + «٣٬٢٠٠» (Marhey 700 22). 2px divider. Row 2 (h40): «معاك» + «١٬٣٢٥ ج» (15/700). | `paper` + 2px inset `track` ring, `radius.bubble`, padding 4 14; labels `body` (14/500); divider `track` |
| 6a | Shortfall (unaffordable) | y742 h19 | «ناقصك ١٬٨٧٥ ج», centred | 15/700 `danger.ink` |
| 6b | CTA (unaffordable) | y769 h64 | `AppButton` primary xl «اطلع مشوار» + a fuel-cost chip «−١ لتر» (h28, padding 0 9) | `primary`, radius 22 (`radius.card`), `lip.primary`; label Marhey 700 25; chip `sun`, `radius.pill`, 13/700 `ink` |
| 6′ | CTA (affordable) | replaces 6a + 6b | `AppButton` primary xl «اشتري» (UX). **Not drawn.** | as 6b |

**Dynamic data.**

- Room label, item name, three style names, thumbnails and preview art → content item (`<room_id>.<slug>`) with its 3 variants.
- Salma's line → content, one line per style. It changes when the selection changes.
- Price → catalog price (same for all styles).
- «معاك» → `wallet.jenehat`. Shortfall = `price − jenehat`.
- Initial selection → last chosen/default variant (content default). Selected variant is saved to `ownership` on purchase (`spend_jenehat.variant`, backend §7.4).
- «−١ لتر»: static copy (fuel per trip is always 1).

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| Style option | tap | select it. The preview, the chip and Salma's line update. Price unchanged. |
| «اطلع مشوار» | tap | close the sheet and open `/home/pre-trip/:tripId` for the next trip on the current line (HTML → `PreTrip`). If `wallet.fuel == 0` and no unlimited window, open `/shop/fuel` instead. |
| «اشتري» (affordable) | tap | `EconomyService.apply(spend_jenehat{sku_kind:item, sku_id, variant, price})`. The sheet closes (`sheetOut`), the item drops into the room, and a Salma bubble appears. Analytics `item_purchased{item_id, jenehat}`. |
| ✕ / swipe down / system back | — | close the sheet → `/apartment` |

**States & edge cases.**

- Affordable: the shortfall line hides and the CTA becomes «اشتري». Not drawn.
- Item has no variants (product spec: "some items have 3 styles"): hide the picker and the preview chip. The Salma line uses the item-level comment.
- A request depends on a style (e.g. crystal chandelier, see `Requests`): no marker on the style is drawn.
- Large numbers: the price row never wraps. The amount column is auto-width; the label ellipsizes first.
- Offline: works (JENEHAT purchase is offline-capable).
- Purchase double-tap: disable the CTA until the op is applied.

**Motion.** `sheetIn` / `sheetOut`. Style change: preview crossfade ≤150 ms; the selected ring follows with no movement. CTA `press`. Reduced motion: no drop-in bounce.

**Accessibility.**

- HTML: `role=dialog` labelled by the title; close «اقفل»; radiogroup «شكل الأنتريه» → `شكل {item}`; each style option is `role=radio` with `aria-checked`.
- Reading order: title → preview → styles → comment → price → shortfall → CTA.
- CTA label: «اطلع مشوار، بيصرف لتر بنزين» (proposed).

**Strings.**

- `piece.close: "اقفل"`
- `piece.stylesA11y: "شكل {item}"`
- `piece.salmaLine: "سلمى: «{line}»"`
- `piece.priceLabel: "السعر (نفسه لكل الأشكال)"`
- `piece.youHave: "معاك"`
- `piece.amount: "{amount} ج"`
- `piece.shortfall: "ناقصك {amount} ج"`
- `piece.goTrip: "اطلع مشوار"`
- `piece.fuelCost: "−١ لتر"`
- `piece.buy: "اشتري"` (UX, not drawn)
- Content: style names «كلاسيك / مودرن / شعبي», Salma lines, item and room names.

**Notes.**

- UX says «اطلع مشوار» "returns to Home". The design links it to `PreTrip` and shows a fuel cost. Follow the design (straight to the pre-trip card), and confirm.
- Fuel chip copy differs: «−١ لتر» here and on Result, «−١» on Home and PreTrip, «−١ بنزين» in the UX doc. Pick one.

---

#### عارض المشاهد — `SceneViewer`

| | |
| --- | --- |
| Route | `/story/:chapterId` (full screen, no `BottomNav`) |
| Feature folder | `features/story/` |
| Phase | MVP |
| Files | `screens/SceneViewer.html` · `png/SceneViewer.png` |

**Purpose.** Plays a chapter's comic scene, one panel at a time, with dialogue in Egyptian Arabic. It opens after a room or chapter is completed, after story trips, or for replay from `Chapters`.

**Layout, top to bottom.** Full-bleed `dashboard.bg`. Padding 36 16 28, gap 16.

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 1 | Top bar | y36 h44 | Right: «الفصل ٤ · المشهد» (12/600) over the scene title «زيارة أهل العروسة» (Marhey 700 18). Left: «تخطّى» pill (h44, padding 0 16). | caption `dashboard.muted`; title `sun`; pill `dashboard.raised`, `radius.pill`, 14/600 `paper`, no lip |
| 2 | Panel | y96 h540 | `ComicPanel`: panel art (room, characters). Up to 2 `SpeechBubble` (character variant) are laid over it. Bubble 1 «أم العروسة» w190, at top 120 / right 12 inside the panel. Bubble 2 «الأسطى» w180, at top 236 / left 12. Each bubble: speaker line + text, tail 16 (a rotated square) at the bottom, pointing at the speaker. | panel bg `#F6E7D4` **(non-token, art)**, `radius.scene`, `lip.dark`; bubble `paper`, radius 20 (`radius.l`), padding 8 14 10, lip 4 `rgba(26,75,140,.2)` **(non-token)**; speaker `label` `ink.muted`; text Marhey 600 18 lh 1.4 (`quote`) `ink` |
| 3 | Page dots | y652 h10 | One dot per panel, gap 8, centred. Current = pill 26×10. In RTL the first panel is on the right. | dots `dashboard.line`; current `sun`; `radius.pill` |
| 4 | Final actions (last panel only) | y752 h64 | «شارك» (flex 1 = 124, share icon 22) + «كمّل» (flex 2 = 224, `AppButton` primary xl), gap 10 | «شارك» `dashboard.raised`, radius 22, no lip, 18/700 `paper`, icon `sun`; «كمّل» `primary`, `lip.primary`, Marhey 700 25 |

**Dynamic data.**

- Chapter number, scene title, panel list (3–5 panels: art + bubbles: speaker, text, position, tail target) → content chapter scene.
- Current panel index → local UI state.
- `story_state.scenes_seen` is updated when the last panel is reached.

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| Anywhere on the panel (panels 1…n−1) | tap | next panel |
| «تخطّى» / system back | tap | mark the scene seen (first view: `story_progress{chapter_id, scene_id}` op) and pop to the caller. The HTML goes to `AptRooms` because the sample was opened from room completion. |
| «كمّل» | tap | same as «تخطّى», on the last panel |
| «شارك» | tap | render the current panel (art + bubbles) to an image and open the share sheet (`share_plus`). Analytics `share{kind: scene}`. |

**States & edge cases.**

- Panels 1…n−1: the final-actions row is hidden (UX: buttons only on the last panel). The space stays empty. No "tap to continue" hint is drawn.
- First view vs replay: the same UI. Replay from `Chapters` never re-grants rewards.
- Scene art not downloaded and offline: show the general loading/error pattern (`States`). Downloaded scenes work offline (§11).
- Bubble text longer than 3 lines at 18: content QA limit. Never shrink below `quote` 16. Bubbles stay clamped inside the panel.
- Speaker «الأسطى» may need the player's chosen name (see Notes).

**Motion.**

- Panel advance: slide in reading direction (next panel enters from the left in RTL) with crossfade, using `sheetIn` timing. No dedicated token.
- Bubbles appear after the panel with `bubblePop`, staggered 150 ms.
- Current dot width animates 10 → 26.
- Reduced motion: crossfade ≤150 ms, no pop.

**Accessibility.**

- Dots: `aria-label` «اللوحة ٤ من ٤» → `اللوحة {i} من {n}`. Announce it politely on every advance.
- Reading order per panel: speaker + text of each bubble, in authored order.
- The whole panel is one button labelled «اللوحة الجاية».
- «تخطّى» 44 high. Final buttons 64.

**Strings.**

- `scene.chapterLabel: "الفصل {n} · المشهد"`
- `scene.skip: "تخطّى"`
- `scene.pageA11y: "اللوحة {i} من {n}"`
- `scene.share: "شارك"`
- `scene.continue: "كمّل"`
- `scene.nextPanelA11y: "اللوحة الجاية"` (proposed)
- Content: scene title, speakers, dialogue lines.

**Notes.**

- Product spec allows sharing as "image or short video". Architecture MVP shares images only. The spec above assumes an image.
- Bubble speaker «الأسطى»: confirm whether it should use `profile.display_name`. The player names the driver.
- Recommended build: panel art as a static image layer, with bubbles as Flutter widgets positioned from content coordinates. This keeps Arabic shaping and l10n, as in §8 for trip bubbles.

---

#### خط الفصول — `Chapters`

| | |
| --- | --- |
| Route | `/apartment/chapters` (full screen, no `BottomNav`) |
| Feature folder | `features/apartment/` |
| Phase | MVP. ch5 content is Phase 2; ch6–7 are Public launch, but all seven rows show from MVP (later ones locked). |
| Files | `screens/Chapters.html` · `png/Chapters.png` |

**Purpose.** A vertical timeline of the seven chapters. Done chapters show their scene and can be replayed, the current one shows its goal, and future ones show only their name, locked.

**Layout, top to bottom.** Padding 36 16 24, gap 14.

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 1 | Header | y36 h52 | `ScreenHeader`: back `IconCircleButton` 44 (right) + «حكاية الجواز» + trailing pill «ألبوم المشاهد» (h44, w134, clapper icon 18) | back `paper`, `lip.card.small`, chevron 20 `ink`; title Marhey 700 26 (`display.m`); pill `paper`, `radius.pill`, `lip.card.small`, 13/700 `ink`, icon `sun` |
| 2 | Rail | x360 w4, y122→660 | Track over the whole list. Fill from the top down to just past the current node centre (h330 in the sample). `aria-hidden`. | track `ground.lip`, fill `primary`, radius 2 |
| 3 | Chapter list | y102, gap 10 | `ol`. Cards are 328 wide (padding-right 30 leaves room for the nodes). Nodes are centred on the rail. | — |
| 3a | Done chapter (×3) | h80 (y102, 192, 282) | Node 24 with a white check 12. Scene thumbnail 70×56. «الفصل ١» (12/600) over the name (Marhey 700 17). Button «شوف المشهد» (h44, padding 0 12) on the left. | card `paper`, radius 20 (`radius.l`), `lip.card.small`, padding 0 10 0 12; node `primary`; thumb radius 14 (`radius.tray`), bg per scene (content art); button `AppButton` tertiary m: `ground`, radius 14, 13/700 `primary` |
| 3b | Current chapter | h104 (y372) | Node 32 with a 5px ring. Row: «الفصل ٤ · دلوقتي» + `StatusChip` «٢ من ٤ قطع». Title «الصالة» (Marhey 700 20). Description «النيش، الستاير، الأنتريه، النجفة · المشهد: زيارة أهل العروسة» (up to 2 lines). `aria-current=step`. Not tappable. | card `primary`, radius 22 (`radius.card`), `lip.primary.m`, padding 0 14; node `sun` + ring `primary.soft`; meta 12/600 `primary.soft`; chip `sun`, 12/700 `ink`; title `paper`; desc `caption` `primary.soft` |
| 3c | Locked chapter (×3) | h58 (y486, 554, 622) | Empty node 24. «الفصل ٥» (12/600) + name (Marhey 700 16). Lock 18 at the end (left). | `locked.bg` + `ring.locked` (2 `outline`), `radius.bubble`, text `ink.2`; node `ground` + 3px inset `ground.lip`; lock `ink.muted` |

**Dynamic data.**

- Rows → content chapters (`ch1_first_job` … `ch7_wedding`): number, name, scene thumbnail.
- Status per row → `story_state.status` (done / current / locked).
- Current card:
  - Chip «{owned} من {total} قطع» → `ownership` count for the room.
  - Description = the room's item names joined with «، » + « · المشهد: {sceneName}».
- Rail fill height → index of the current chapter.

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| Back / system back | tap | pop to `/apartment` |
| «شوف المشهد» | tap | push `/story/:chapterId` (replay) |
| «ألبوم المشاهد» | tap | Opens `/story/album` **(new route)**, the `Album` screen (§11, new screens). |
| Current / locked rows | — | inert |

**States & edge cases.**

- Current chapter is a goal chapter (ch1–3): the chip and description must show the goal (e.g. «الشبكة · {saved} / {target} ج»). **Not drawn.**
- All chapters done (after ch7): no current card, rail fully filled. Not drawn.
- Long names: 1 line, ellipsis. Current description: max 2 lines, ellipsis.
- Seven rows fit in 844 with 140 px to spare. The list is still a scroll view, for safety on short devices and with large text.
- Replay offline with the scene not downloaded: see `SceneViewer`.

**Motion.** `press` on the buttons. Rail fill animates to the current node on first entry after a chapter changes, using `sheetIn` timing. Reduced motion: static.

**Accessibility.**

- HTML: back «رجوع»; current row `aria-current="step"`; rail and nodes `aria-hidden`.
- Each row reads as one sentence, e.g. «الفصل ١، أول شغلانة، خلص» (proposed) / «… مقفول».
- Buttons are 44 high.

**Strings.**

- `chapters.back: "رجوع"`
- `chapters.title: "حكاية الجواز"`
- `chapters.album: "ألبوم المشاهد"`
- `chapters.number: "الفصل {n}"`
- `chapters.watchScene: "شوف المشهد"`
- `chapters.current: "الفصل {n} · دلوقتي"`
- `chapters.itemsChip: "{owned} من {total} قطع"`
- `chapters.currentDesc: "{items} · المشهد: {sceneName}"`
- Content: chapter names.

**Notes.**

- The album is now drawn: see `Album` in the new-screens section.

---

#### طلبات أهل العروسة — `Requests`

| | |
| --- | --- |
| Route | `/apartment/requests` (sheet over `/apartment`) |
| Feature folder | `features/apartment/` |
| Phase | MVP |
| Files | `screens/Requests.html` · `png/Requests.png` |

**Purpose.** Lists the bride's family's optional side requests: who asked, what they want, the BONAT reward and progress. Completed ones can be claimed. Requests never block the story.

**Layout, top to bottom.** Behind: `AptRooms` + `Scrim`. `Sheet` top at y224, h620, padding 10 16 24, gap 12.

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 0 | Sheet + grabber | y224 h620; grabber 44×5 at y234 | `Sheet` | as `Piece` |
| 1 | Header | y251 h64 | «طلبات أهل العروسة» over the subtitle «اختيارية، ومش بتوقف القصة. مكافأتها بونات.». Close 44 on the left. | title Marhey 700 26 (`display.m`); subtitle `caption` `ink.muted`; close `IconCircleButton` bg `ground` |
| 2 | List | y327, gap 10 | Rows: `ListRow`, padding 12, gap 12. `CharacterAvatar` 52 (circle, `paper` bg, expression matches state) + text column (speaker 12/600 `ink.2`, quote Marhey 600 16 lh 1.35, then a status line). | radius 20 (`radius.l`) |
| 2a | Done, claimable | y327 h82 | Status «خلص · +١٠ بونات» (12/700 `primary`). `AppButton` primary m «خد» (h44, padding 0 16) on the left. | row bg `sun.soft`; button `primary`, radius 14, `lip.primary.s`, Marhey 700 17 `paper` |
| 2b | Open, one-shot condition | y419 h84 | Status line: condition «اختار شكل «كريستال» للنجفة» (12/600) … reward «+١٥ بون» (12/700) at the end | row bg `ground`; text `ink` |
| 2c | Open, counted condition | y512 h96 | As 2b («٣ مشاوير بتلات نجوم» … «+٢٠ بون») + `ProgressBar` h8 (33%) | bar track `paper`, fill `primary`, `radius.pill` |

**Dynamic data.**

- Request list → `story_state` family requests for the current chapter (content request definitions: `character`, quote, condition, reward BONAT, target count).
- Status → done/open, plus progress `{done}/{target}` for counted conditions.
- Conditions are evaluated from `ownership` (chosen variant) and `trip_progress` (stars).
- Avatar expression: happy when done, neutral when open (as drawn).

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| «خد» | tap | grant BONAT. The row leaves the list; the `AptRooms` badge updates. Feedback after the claim is not drawn (see Notes). |
| Rows 2b/2c | — | inert (as drawn) |
| ✕ / swipe down / system back | — | close → `/apartment` |

**States & edge cases.**

- No requests: use the `States` empty-list pattern (sentence + picture). Copy is not written yet.
- Many requests: the list scrolls inside the sheet. Header stays fixed.
- Quote: max 2 lines. Condition text: 1 line, ellipsis. Reward never truncates.
- Claimed requests: removed from the list (UX: "list of open requests").
- Offline: claiming BONAT is server-authoritative. Disable «خد» with `StatusChip` «محتاج نت», or queue the claim; decide with the backend (Notes).

**Motion.** `sheetIn` / `sheetOut`. Claim: the row collapses (height → 0 + fade, 200 ms, `toast` timing). Reduced motion: fade only.

**Accessibility.**

- HTML: `role=dialog` labelled by the title; close «اقفل».
- Each row reads as «{speaker}: {quote}. {condition}. المكافأة {n} بون. {status}».
- «خد» label: «خد {n} بونات» (proposed). Button 50×44.

**Strings.**

- `requests.title: "طلبات أهل العروسة"`
- `requests.subtitle: "اختيارية، ومش بتوقف القصة. مكافأتها بونات."`
- `requests.close: "اقفل"`
- `requests.doneReward: "خلص · +{n} بونات"` (ICU: few → «بونات»)
- `requests.reward: "+{n} بون"` (ICU: many/other → «بون»)
- `requests.claim: "خد"`
- Content: speaker names, quotes, conditions.

**Notes.**

- No sync op grants a request's BONAT. Backend §7.4 has `claim_task` and `story_progress` only. Needs a new op, or reuse `claim_task` with request ids.
- The `AptRooms` badge says «٢ مفتوحين» while the sheet has 3 rows (1 claimable + 2 open). Decide whether the badge counts open, claimable, or both. Claimable should probably be what draws attention.
- Should a request row deep-link to its item (e.g. chandelier → `Piece`)? Not drawn and not specified.

---

#### المحل — `Shop`

| | |
| --- | --- |
| Route | `/shop` (shell tab «المحل») |
| Feature folder | `features/shop/` |
| Phase | MVP (free fuel ad, fuel, boosters, BONAT packs, remove ads). Starter pack and subscription are Phase 2 and not on this artboard. |
| Files | `screens/Shop.html` · `png/Shop.png` (390×1240: scrolls) |

**Purpose.** The only place with real money. It is ordered from free/cheap at the top to expensive at the bottom: a free refuel via ad, fuel and boosters for BONAT, BONAT packs and «شيل الإعلانات» for store money. JENEHAT are never sold.

**Layout, top to bottom.** Scroll column: padding 0 16 16, gap 14. `BottomNav` is fixed at the bottom (y1152 in the artboard, i.e. viewport bottom). Content height ≈ 1116.

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 1 | Header | y36 h52 | «المحل» + `CurrencyPill` coins «١٬٢٤٠» + `CurrencyPill` bonat «٨٥» (gap 6) | `display.l`; pills as `AptGoal` |
| 2 | Free refuel | y102 h96 | `RewardedAdButton` (card form), padding 0 16, gap 12. Right: icon tile 60 (radius 18) with a fuel pump 34. Middle: «تفويلة ببلاش» (Marhey 700 20) over «اتفرج على إعلان وخد تفويلة كاملة · باقيلك مرتين النهارده» (13/500, 2 lines). Left: TV-play icon 28. | `primary`, `radius.xl`, `lip.primary`; tile `sun`; sub `primary.soft` |
| 3 | «البنزين» | h2 y212 h32; grid y252 h128 | 2 cards (gap 10), each: icon 40 + name 14/700 + `PriceTag` bonat (h30, padding 0 12, ticket 16). Cards: «تفويلة كاملة» «٣٠ بون» (right) · «بنزين مفتوح ساعة» «٨٠ بون» (left). | h2 `display.s`; card `paper`, radius 22, `lip.card`; tag `primary.soft` bg, 14/700 `primary` |
| 4 | «المساعدات» | h2 y394; grid y434 h186 | 2×2 cards h88 (row gap 10), padding 0 12, gap 10. Each: icon 34 + name (14/700, ≤2 lines) over «معاك {n}» (12/500) + price «{n} بون» (14/700) at the end. Order: كيس فكة · صحّي النايم / الدفتر · زحمة. | card `paper`, radius 20, `lip.card`; count `ink.muted`; price `primary` |
| 5 | «البونات» | h2 y634; rows y674/758/842 h76 (gap 8) | 3 rows, padding 0 14, gap 12. Each: icon 40 + «{pack} · {amount} بون» (15/700) over a sub line + price chip «[سعر المتجر]» (h40, padding 0 12, radius 14, 13/700). Subs: «ينفع برصيد الموبايل» (12/500 `ink.muted`), «+٥٠ هدية» and «+٢٠٠ زيادة مجانية» (12/700 `primary`). The large pack is highlighted, with ribbon `StatusChip` «أوفر كيس» (h18, 12/700) at top −9 / right 18. | rows `paper`, radius 20, `lip.card`; chip `sun`, `ink`; large row `sun.soft` + inset 3 `sun` ring + lip 5 `#EED38A` **(non-token)**; its chip `primary` with `paper` text; ribbon `danger` bg + `ink` text |
| 6 | «شيل الإعلانات» | y932 h96 | Icon tile 54 (`ground`, radius 18, crossed-out TV) + «شيل الإعلانات» (Marhey 700 18) over «الإعلانات اللي بين المشاوير بتختفي. إعلانات المكافآت تفضل باختيارك.» (12/500, lh 1.5, 3 lines) + price chip | card `paper`, radius 22, `lip.card`; body `ink.muted`; chip `sun` |
| 7 | Footer | y1042 h97 | Phone icon 18 + «ادفع برصيد موبايلك أو بالكارت» (13/600). Row (gap 8, h44): «استرجاع المشتريات», «الشروط». Then «مفيش صناديق عشوائية: اللي بتشوفه هو اللي بتاخده.» (12/500). | buttons `AppButton` tertiary m: `paper`, radius 14, no lip, 13/700 `primary`; note `ink.muted` |
| 8 | `BottomNav` | h88, fixed | «المحل» active | shared |

**Dynamic data.**

- Pills → `wallet.jenehat`, `wallet.bonat`.
- «باقيلك {n}…» = `ads_fuel_refill_daily_cap` (RC, 3) − today's `fuel_refill` count (shared with `Fuel`).
- BONAT prices (`refuel_full` 30, `fuel_unlimited_1h` 80, `change_bag` 10, `wake_all` 8, `ledger_peek` 12, `traffic_jam` 8) → content catalog (§13). Never hard-code them.
- «معاك {n}» → `inventory.count` per `booster_id`.
- Packs → `bonat_pack_s|m|l`. Amounts and bonus come from the catalog (sample 120 / 500+50 / 1,200+200). Which pack is «أوفر كيس» comes from the catalog flag.
- «[سعر المتجر]» → localized store price (`ProductDetails.price`) from `PurchaseGateway` product query (§15.2 step 1). Never hard-coded.
- Remove ads → `remove_ads`; owned state from `entitlements_cache.remove_ads`.

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| Free refuel card | tap | `AdsGateway.showRewarded(fuel_refill)`. On reward: fuel to max (`ad_reward` op). Analytics `ad_offer_shown` / `ad_reward_granted`. |
| Fuel card «تفويلة كاملة» (30) | tap | under 50 BONAT: buy at once (`spend_bonat{sku_kind: fuel}`) + `UndoToast` «اتشرى … بـ٣٠ بون» with «رجّع ٣» for 3 s (`States`) |
| Fuel card «بنزين مفتوح ساعة» (80) | tap | 50 BONAT or more: confirm `AppDialog` «هتصرف ٨٠ بون؟» «أيوه / لأ» (`States`). Then `fuel_unlimited_until = now + 60 min`. |
| Booster card | tap | buy one at once + `UndoToast` (all boosters < 50). `inventory.count` +1. |
| BONAT pack row | tap | `PurchaseGateway` buy flow → store payment sheet → `POST /v1/purchases/verify` → on success the `PurchaseDone` dialog. On failure the `States` card «الدفع ما تمّش». Analytics `iap_view` on screen open, `iap_purchase`. |
| «شيل الإعلانات» | tap | same flow for `remove_ads` |
| «استرجاع المشتريات» | tap | store restore, then verify each purchase (§15.2 step 5) |
| «الشروط» | tap | HTML → `Settings` (`/settings`). The terms are presumably there (see Notes). |
| `BottomNav` | tap | shell navigation |

**States & edge cases.**

- Ad not ready: `States` card «الإعلان مش جاهز دلوقتي، جرّب كمان شوية» with the BONAT alternative button.
- Daily cap reached: the free refuel card is disabled. Use the `States` «خلصت النهارده» treatment: 45% opacity, no lip.
- Not enough BONAT for an item: **not specified** (Notes).
- Store prices loading or product query failed: not drawn. Keep the chip at its size, show «…», and disable the row until a price arrives. Hide a product the store does not return.
- `remove_ads` owned: **not drawn** (Notes).
- Offline: `HomeStates` disables the whole «المحل» tab («المحل، محتاج نت», 45% opacity). If the network drops while the screen is open, disable the IAP rows, the ad card and restore with `StatusChip` «محتاج نت».
- Booster names wrap to 2 lines at this width (drawn: «كيس فكة», «صحّي النايم»). `maxLines 2`, never ellipsize. The price column never wraps.
- Fuel already full: the free refuel and «تفويلة كاملة» rows have no rule (Notes).
- Phase 2: the starter-pack offer goes above block 2 and the subscription card above block 6 (UX order). Not part of this artboard.

**Motion.**

- `press` on every card and row.
- `UndoToast` uses `toast` (200 ms, hold 3000). The confirm dialog uses `dialogIn`.
- After a booster buy, «معاك {n}» counts up and the BONAT pill counts down (≤300 ms).
- Reduced motion: no count animation.

**Accessibility.**

- Sections are labelled by their h2 («البنزين», «المساعدات», «البونات»).
- Each card/row is one button with one label, e.g. «كيس فكة، معاك ١، بـ١٠ بون» / «كيس كبير، ١٬٢٠٠ بون و٢٠٠ زيادة، {storePrice}» (proposed).
- Ribbon «أوفر كيس» is read as part of the row.
- All targets ≥ 44 (smallest: footer buttons 44).

**Strings.**

- `shop.title: "المحل"`
- `shop.freeFuelTitle: "تفويلة ببلاش"`
- `shop.freeFuelSub: "اتفرج على إعلان وخد تفويلة كاملة · {remaining}"`
- `shop.adRemaining: "باقيلك {n} مرات النهارده"` (ICU: two → «باقيلك مرتين النهارده» as drawn; one/other need copy)
- `shop.sectionFuel: "البنزين"`
- `shop.refuelFull: "تفويلة كاملة"`
- `shop.fuelUnlimited: "بنزين مفتوح ساعة"`
- `shop.bonatPrice: "{n} بون"`
- `shop.sectionBoosters: "المساعدات"`
- `shop.boosterOwned: "معاك {n}"`
- `booster.change_bag: "كيس فكة"` · `booster.wake_all: "صحّي النايم"` · `booster.ledger_peek: "الدفتر"` · `booster.traffic_jam: "زحمة"`
- `shop.sectionBonat: "البونات"`
- `shop.packS: "كيس صغير · {n} بون"` · `shop.packM: "كيس متوسط · {n} بون"` · `shop.packL: "كيس كبير · {n} بون"`
- `shop.packSSub: "ينفع برصيد الموبايل"`
- `shop.packGift: "+{n} هدية"` · `shop.packFree: "+{n} زيادة مجانية"`
- `shop.bestValue: "أوفر كيس"`
- `shop.removeAdsTitle: "شيل الإعلانات"`
- `shop.removeAdsBody: "الإعلانات اللي بين المشاوير بتختفي. إعلانات المكافآت تفضل باختيارك."`
- `shop.payMethods: "ادفع برصيد موبايلك أو بالكارت"`
- `shop.restore: "استرجاع المشتريات"`
- `shop.terms: "الشروط"`
- `shop.noLootBoxes: "مفيش صناديق عشوائية: اللي بتشوفه هو اللي بتاخده."`
- Placeholder, never shipped as text: «[سعر المتجر]».

**Notes.**

- The UX doc and architecture §11 disagree about offline:
  - UX/`HomeStates`: the shop is disabled offline.
  - §11: BONAT spending is optimistic offline.
  - Following the design means BONAT purchases happen offline only via the trip and `Fuel` sheet.
- Insufficient BONAT has no designed path: a disabled card, or a scroll to «البونات»?
- The owned `remove_ads` state is not designed: hide the card, or show `StatusChip` «خلص» in place of the price?
- «الشروط» goes to Settings. Confirm whether it should open the terms URL directly.
- "BONAT" unit inconsistency: «١٠ بون» / «٨ بون» here, but «+١٠ بونات» (`Requests`) and «بـ٨ بونات» (`States`). Proposal: price tags use the invariant unit «بون» (like «ج»), and sentences use ICU plural.
- The refuel product name differs: «تفويلة كاملة» here, «فوّل الخزان» in `Fuel`, «فوّل بـ٣٠ بون» in `States`.
- No rule says whether the free refuel / «تفويلة كاملة» are disabled when fuel is already full.

---

#### نافذة البنزين — `Fuel`

| | |
| --- | --- |
| Route | `/shop/fuel` (sheet). Opened over `/home` when «يلا نطلع!» is tapped with `fuel == 0` (`HomeStates`), and from «اطلع مشوار» in `Piece` when the tank is empty. |
| Feature folder | `features/shop/` |
| Phase | MVP |
| Files | `screens/Fuel.html` · `png/Fuel.png` |

**Purpose.** The tank is empty. The player chooses: watch an ad for a full tank, pay BONAT to fill it or to get unlimited fuel for an hour, or wait (optionally with a reminder when it's full).

**Layout, top to bottom.** Behind: `HomeStates` (fuel-empty Home) + `Scrim`. `Sheet` top at y154, h690, padding 10 16 24, gap 12.

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 0 | Sheet + grabber | y154 h690; grabber at y164 | `Sheet` | as `Piece` |
| 1 | Header | y181 h46 | «البنزين خلص» + close 44 on the left | Marhey 700 26 (`display.m`); close `IconCircleButton` bg `ground` |
| 2 | Art | y239 h150 | المعلم (`CharacterAvatar`, bust, left) + a fuel gauge with the needle on E (right). Top-right: a speech bubble «الخزان نشف يا أسطى» (max-w 160, tail at the bottom). | bg `sun.soft`, `radius.xl`; gauge arc `paper`, low zone `danger`, «E» `danger.ink`, «F» `ink`; bubble `SpeechBubble` normal: `paper`, radius 16, Marhey 600 16 lh 1.35, lip 3 `rgba(26,75,140,.18)` **(non-token)** |
| 3 | Timers | y401 h58 | 2 tiles (gap 8), padding 8 12: «اللتر الجاي بعد» / «١٢:٣٠» (right) · «الخزان يتملى بعد» / «١:٤٠:٠٠» (left) | tile `ground`, radius 16; label `label` `ink.muted`; value `number.l` (20/700) `ink` |
| 4 | Ad option | y471 h66 | `RewardedAdButton`: TV-play icon 26 + «اتفرج على إعلان وفوّل» (Marhey 700 21) over «باقيلك ٣ مرات النهارده» (12/500) | `primary`, radius 22, `lip.primary`; title `button.l` `paper`; sub `primary.soft` |
| 5 | BONAT option 1 | y549 h56 | `AppButton` secondary l: «فوّل الخزان» on the right, `PriceTag` bonat «٣٠ بون» (ticket 18) on the left. Padding 0 16. | `paper` + 2px inset `ground.lip` ring + lip 4 `ground.lip`, radius 18; label 16/700 `ink`; price 16/700 `primary` |
| 6 | BONAT option 2 | y617 h56 | same: «بنزين مفتوح ساعة» · «٨٠ بون» | same |
| 7 | Footer | y772 h48 | «استنى» on the right (`AppButton` tertiary, h48, padding 0 18). «فكّرني لما يتملى» + `AppSwitch` 52×30 (on) on the left. | «استنى» `ground`, radius 16, 15/700 `ink`; label 14/600; switch on = `primary`, knob 24 `paper`, at the left (RTL end) |

**Dynamic data.**

- Next-liter countdown = time to the next regen tick, from `wallet.fuel_updated_at_server` + `fuel_regen_minutes` (RC 20), using server-corrected time (§13). Format `m:ss`, ticking every second.
- Full-tank countdown = next tick + `(fuel_max − fuel − 1) × regen`. `fuel_max` is RC 5, or 7 for subscribers. Format `h:mm:ss`.
- Ads remaining = `ads_fuel_refill_daily_cap` (RC 3) − today's `fuel_refill` count (shared with `Shop`).
- Prices → catalog `refuel_full` (30) and `fuel_unlimited_1h` (80).
- Switch → the local-notification preference for «البنزين اتملى» (settings). Drawn on.
- Character line: static copy.

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| Ad option | tap | `AdsGateway.showRewarded(fuel_refill)`. On reward: fuel to max (`ad_reward` op), close the sheet. Analytics `fuel_empty{choice: ad}`. |
| «فوّل الخزان» (30) | tap | under 50: buy at once (`spend_bonat{sku_kind: fuel}`), fuel to max, `UndoToast` 3 s, close. `fuel_empty{choice: bonat}`. |
| «بنزين مفتوح ساعة» (80) | tap | confirm «هتصرف ٨٠ بون؟» (`States`), then `fuel_unlimited_until = now + 60 min`, close |
| «استنى» / ✕ / swipe down / back | tap | close → `/home` (HTML → `HomeStates`). `fuel_empty{choice: wait}`. |
| Switch | tap | schedule or cancel a local notification at the full-tank time (§16). If OS permission is missing, show the `NotifAsk` pre-prompt first. |

**States & edge cases.**

- Ad not ready / cap reached / offline: the ad option uses the `States` treatments («الإعلان مش جاهز دلوقتي…», disabled «خلصت النهارده», `StatusChip` «محتاج نت»). The BONAT options stay available. Offline BONAT spend is optimistic (§11).
- Insufficient BONAT: not specified (see `Shop` Notes).
- Fuel regenerates while the sheet is open (timer reaches 0): fuel > 0, so close the sheet and return the player to where they were (Notes).
- Subscriber: `fuel_max` 7 changes the full-tank time only.
- Unlimited window active: this sheet never opens.
- Timer at the hour boundary: switch the next-liter format to `h:mm:ss` only if ≥ 60 min (it can't happen with 20-min regen).

**Motion.** `sheetIn` / `sheetOut`. Timer digits update with no animation. The gauge needle may rest-wobble once on open (300 ms, disabled under reduced motion). After an ad or BONAT refill, the Home fuel pill fills when the sheet closes.

**Accessibility.**

- HTML: `role=dialog` labelled by the title; close «اقفل»; switch «فكّرني لما الخزان يتملى» (`role=switch`, `aria-checked`).
- The countdowns are read in words, like the Home pill label: «اللتر الجاي بعد ١٢ دقيقة و٣٠ ثانية». They are not a live region (would spam). Announce only when the value reaches 0.
- Switch hit area: the whole label + switch row (≥ 44).

**Strings.**

- `fuel.title: "البنزين خلص"`
- `fuel.close: "اقفل"`
- `fuel.moallemLine: "الخزان نشف يا أسطى"`
- `fuel.nextLiter: "اللتر الجاي بعد"`
- `fuel.fullIn: "الخزان يتملى بعد"`
- `fuel.watchAd: "اتفرج على إعلان وفوّل"`
- `fuel.adRemaining: "باقيلك {n} مرات النهارده"` (ICU few as drawn; two → «باقيلك مرتين النهارده» as on `Shop`; one needs copy)
- `fuel.refill: "فوّل الخزان"`
- `fuel.unlimited: "بنزين مفتوح ساعة"`
- `fuel.bonatPrice: "{n} بون"`
- `fuel.wait: "استنى"`
- `fuel.remind: "فكّرني لما يتملى"`
- `fuel.remindA11y: "فكّرني لما الخزان يتملى"`

**Notes.**

- Sample timers don't agree: if the next liter comes in 12:30, then with 5 liters at 20 min the tank is full in 1:32:30, not 1:40:00. Use the formula above.
- After a successful refill it is unspecified whether the player continues straight to `PreTrip` (they had tapped «يلا نطلع!») or lands on Home. Proposal: continue to the pre-trip card.
- UX lists option 2 as «فوّل بـ٣٠ بون». The design splits it into label «فوّل الخزان» + price tag. Follow the design.

---

#### الشرا تمّ — `PurchaseDone`

| | |
| --- | --- |
| Route | `/shop/purchase-done` (dialog over `/shop`) **(new route)**. It can also stay an un-routed dialog pushed by the purchase flow. |
| Feature folder | `features/shop/` |
| Phase | MVP |
| Files | `screens/PurchaseDone.html` · `png/PurchaseDone.png` |

**Purpose.** Confirms a real-money BONAT purchase after the server has verified it, and shows the BONAT flying into the balance.

**Layout, top to bottom.** Behind: the `Shop` skeleton + `Scrim`. The Shop header is redrawn **above** the scrim (title white, pills unchanged) so the balance stays visible.

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 1 | Header (above scrim) | y36 h52 | «المحل» + `CurrencyPill` coins «١٬٢٤٠» + `CurrencyPill` bonat «٦٣٥» highlighted with a 4px ring and no lip | title Marhey 700 28 `paper`; highlight `sun` ring 4 |
| 2 | Fly path | full frame, decorative | Dashed curve from the dialog top (195,300) to the BONAT pill (≈70,96), with 2 BONAT tickets in flight (rotated −30° / −40°, scale 1 / 0.8). `pointer-events: none`. | line `sun` 3px dash 2/8; ticket `primary` + 2px `paper` stroke |
| 3 | Dialog | x16 y250 w358 h374 | `AppDialog`, padding 22 18 18, gap 12, centred | `paper`, radius 26 (`radius.scene`), lip 6 `rgba(0,0,0,.25)` **(non-token)** |
| 3a | Art | 170×120 | Two BONAT tickets («بون») + 5 sun rays | tickets `primary` / `#7CA7D8` (= `character.shirt.default`); rays and label `sun` |
| 3b | Title | h52 | «وصلك ٥٥٠ بون!» | Marhey 700 30 (between `display.l` and `display.xl`) |
| 3c | Breakdown | h22 | `StatusChip` «٥٠٠ + ٥٠ هدية» (padding 2 12) | `primary.soft` bg, 14/600 `primary` |
| 3d | Body | 2 lines | «البونات للبنزين والمساعدات والزينة. الشقة بتتجهز بشغلك انت.» centred | `caption` `ink.muted` |
| 3e | CTA | h60, full dialog width | `AppButton` primary «تمام» | `primary`, radius 20 (`radius.l`), `lip.primary`, Marhey 700 24 |

**Dynamic data.**

- Total = pack amount + bonus of the purchased `product_id` (catalog).
- Breakdown «{base} + {bonus} هدية». Hide it when the bonus is 0 (small pack).
- BONAT pill = `wallet.bonat` after the server's verify response (§15.2 step 4). Coins pill = `wallet.jenehat`.
- Body: static copy.

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| «تمام» | tap | close the dialog → `/shop` |
| System back | — | same as «تمام» |
| Scrim | tap | inert (the player confirms with «تمام») |

**States & edge cases.**

- Shown only after `POST /v1/purchases/verify` succeeds and the store transaction is acknowledged. A pending or failed purchase never shows it. Failure → `States` «الدفع ما تمّش».
- Late grant (purchase completes on next launch via retry, §15.2 step 5): show the same dialog over whatever screen the player is on? Not specified.
- `remove_ads` (and Phase 2 products) have different content. **Not drawn.**
- Large amounts: the title stays on 1 line down to 24 px (auto-shrink), then wraps.

**Motion.**

- `dialogIn` for the dialog.
- 2–3 tickets travel along the path to the BONAT pill (≈600 ms, staggered 120 ms, easeInOut).
- On arrival: the pill ring pulses once (scale 1 → 1.06 → 1) and the number counts up from the old to the new balance.
- Reduced motion: no flight, the pill updates instantly, the ring is shown statically.

**Accessibility.**

- HTML: `role=dialog` labelled by the title.
- Announce the title politely on open. Focus «تمام».
- Read the BONAT pill as «البونات ٦٣٥» after the update.
- Decorative art and path: `aria-hidden`.

**Strings.**

- `purchaseDone.title: "وصلك {n} بون!"` (ICU: few would be «بونات»; packs are ≥100 so «بون»)
- `purchaseDone.breakdown: "{base} + {bonus} هدية"`
- `purchaseDone.body: "البونات للبنزين والمساعدات والزينة. الشقة بتتجهز بشغلك انت."`
- `purchaseDone.ok: "تمام"`
- Header uses `shop.title`.

**Notes.**

- The UX doc gives the title as «وصلك ٥٠٠ بون». The design adds the bonus («٥٥٠» + breakdown). Follow the design.

### Screens: daily return, settings, shared states, later phases

Conventions used in this part:

- y / h are logical px measured from the artboard HTML (rendered at 390 wide). x is only given when a block is narrower than the 16-px gutter.
- Type tokens are written `display.m`, `caption`, and so on. "`body` w600" means the `body` token at weight 600. Colours, radii and lips use the token names from `tokens.json`. Any value that is not a token is written as **non-token #HEX**.
- Icons are named after `icons/manifest.json` (for example `bonat_alt`). Illustrations are named after `illustrations/` (for example `illustrations/screens/Challenge_01.svg`).
- Every number is drawn through the digit formatter (Arabic-Indic by default, Western when that setting is on). BONAT counts use an ICU plural: «بونات» for 3–10 and «بون» for 11 and above (as on Daily and Tasks). See the plural note under States.

---

#### المكافأة اليومية — `Daily`

| | |
| --- | --- |
| Route | `/daily/reward` (full screen). It is pushed automatically at launch before `/home` when `bootstrap.daily.reward_claimable` is true, and it also opens from the Home `DailyCircle` «هدية اليوم». |
| Feature folder | `features/daily/` |
| Phase | MVP |
| Files | `screens/Daily.html` · `png/Daily.png` |

**Purpose.** This is the 7-day login streak. The player sees which days are already taken, today's gift and the big day-7 gift, then takes today's reward with one button.

**Layout, top to bottom.** No header and no back button. Padding is 60 top, 16 sides and 28 bottom.

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 0 | Background | 390×844 | Flat sun field with 2 decorative circles: r110 at (340,120) and r130 at (40,720) | `sun`, `sun.glow` |
| 1 | Hero | y60 h165, centred | Gift glyph 92×84 (inline SVG, ribbon `danger`, box `paper`; not in `icons/`). Title «هدية النهارده» with a text lip of 0 4 `sun.lip`. Streak line under it, gap 4 | `display.xl`; `body` w600 `ink` |
| 2 | Day grid | y241 h224 | `role=list`, 4 columns, gap 8, order right→left. Row 1 is days 1–4. Row 2 is day 5, day 6, then day 7 spanning 2 columns | `radius.l` (20) |
| 2a | Tile · claimed | 84×108 | «يوم n» 12/700, reward icon 30 at 50 % opacity, reward label 12/600. Check badge: 22-px `primary` circle with a white `check` 12, at top 6 / left 6 | `sun.soft`, `primary`, `label` |
| 2b | Tile · today | 84×108 | `paper` with a 4-px `primary` ring plus an outer lip 0 6 `primary.lip`. Label «النهارده» 12/700 `primary`, icon 36, reward label 12/700 | `primary`, `primary.lip` |
| 2c | Tile · upcoming | 84×108 | `paper`, icon 30 at full colour, label 12/600 | `paper`, `label` |
| 2d | Tile · day 7 | 175×108, padding 0 12, gap 12 | `primary` background with lip 5 `primary.lip`. Icon `medal_star` 56. Two-line text: «يوم ٧» 12/600 `primary.soft`, then the reward in Marhey 700 17 white with line-height 1.25 | `lip.primary.m`, `display.s`-like |
| 3 | Rule line | y481 h16, centred | «لو فوّت يوم…» | `caption` `ink` |
| — | Spacer | flex | | |
| 4 | CTA | y750 h66 | `AppButton` primary xl «خد» (Marhey 28 in the HTML) | `button.xl`, `radius.card`, `lip.primary` |

Reward icons: `bonat_alt` for BONAT (`bonat_muted` once claimed), `booster_change_bag`, `fuel`, `booster_ledger`, `medal_star`.

**Dynamic data.**
- Today's index (1–7) and which days are claimed come from `daily_state` (login streak), mirrored by the server's `DailyState.streak`. Whether a reward is claimable comes from `bootstrap.daily.reward_claimable`.
- The reward for each day (kind, amount, icon) comes from the content pack `daily_rewards[]`. Sample values: ٥ بونات, كيس فكة, ١٠ بونات, تفويلة, ١٥ بون, ٢ دفتر, ستيكر «على الله» + ٥٠ بون.
- The ordinal word in the streak line («الرابع») comes from today's index, using a list of words الأول…السابع.
- Everything else is static.

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| «خد» | tap | Grants today's reward through `EconomyService.apply` and queues the sync op `claim_daily_reward {day_index}`. The reward icon flies to its `CurrencyPill`, then the app calls `go('/home')`. Logs analytics `daily_reward_claimed`. |
| Day tiles | — | Not interactive. |
| System back | press | Proposal: return to `/home` without claiming. The Home `DailyCircle` keeps its `NewDot`. |

**States & edge cases.**
- **Missed a day:** the streak steps back one day only. The server applies the streak rule; the client just renders `daily_state`. The rule line is always shown.
- **Already claimed today** (opened again from Home): not drawn. See Notes.
- **Long reward labels:** one line at 12 px inside an 84-px tile, ellipsis at the end. The day-7 label wraps to at most 2 lines.
- **Offline:** the claim is a sync op. See Notes.

**Motion.**
- Today's tile pulses (UX: «بتنبض»). Proposal: use the `hotTagPulse` timing (600 ms, repeat) but cap the scale at 1.04. Turn it off when reduced motion is on.
- «خد» uses `press`. After claiming, the check badge enters with `bubblePop` and the reward icon flies to its pill (proposal: `sheetIn` 280 ms easeOutCubic).

**Accessibility.**
- The grid is `role=list` with the label «أيام الأسبوع». Each tile's label comes from the HTML: «اليوم ١، اتاخدت», «اليوم ٤، النهارده» (with `aria-current=date`), «اليوم ٥», «اليوم ٧، الهدية الكبيرة». Proposal: append the reward name to each label.
- Reading order: title → streak line → days 1→7 → rule line → «خد».
- The CTA is 358×66. No other targets.

**Strings.**
```
daily.title: "هدية النهارده"
daily.streak: "اليوم {ordinal} على التوالي. كمّل للهدية الكبيرة!"
daily.dayN: "يوم {n}"
daily.today: "النهارده"
daily.missRule: "لو فوّت يوم، بترجع خطوة واحدة بس، مش من الأول."
daily.cta: "خد"
daily.a11yList: "أيام الأسبوع"
daily.a11yClaimed: "اليوم {n}، اتاخدت"
daily.a11yToday: "اليوم {n}، النهارده"
daily.a11yDay: "اليوم {n}"
daily.a11yBig: "اليوم {n}، الهدية الكبيرة"
daily.rewardBonat: "{n, plural, few{{n} بونات} other{{n} بون}}"
daily.rewardChangeBag: "كيس فكة"
daily.rewardRefuel: "تفويلة"
daily.rewardLedger: "{n} دفتر"
daily.rewardSticker: "ستيكر «{name}» + {n} بون"
```

**Notes.**
- The day-7 reward includes a sticker, which is a cosmetic. Cosmetics arrive with the Garage in Phase 2. In MVP, day 7 must be BONAT-only, unless cosmetic ownership ships without the Garage.
- Not drawn or specified: the "already claimed today" state (proposal: today's tile shows as claimed and «خد» becomes «تمام» and just closes), what happens after day 7 (does the cycle restart?), and whether a claim works offline.
- The HTML CTA is 66 tall with 28-px text. The tokens say `cta.h` 64 and `button.xl` 27; use the tokens. The today ring is 4 px, but `ring.selected` is 3 px.

---

#### مهام اليوم — `Tasks`

| | |
| --- | --- |
| Route | `/daily/tasks` (sheet over `/home`) |
| Feature folder | `features/daily/` |
| Phase | MVP |
| Files | `screens/Tasks.html` · `png/Tasks.png` |

**Purpose.** Shows three short daily tasks with progress. The player claims the BONAT for finished tasks, or jumps straight into a trip to work on the rest.

**Layout, top to bottom.** The live `/home` stays rendered behind a `Scrim` (`scrim` 0.60). The HTML draws Home placeholders there.

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 0 | `Sheet` | y284 h560, full width, radius 28 at the top only, padding 10/16/24, gap 12 | Dialog labelled by the title | `paper`, `radius.sheet` |
| 1 | Grabber | 44×5, y294 | Pill | `outline` |
| 2 | Header row | y311 h64 | Title «مهام اليوم». Subtitle: `clock` 14 + «مهام جديدة بعد ٦ ساعات». `IconCircleButton` close 44 at the left end (`ground` fill, no lip) | `display.m` (26); `caption` w600 `ink.muted` |
| 3 | Task list | y387 h248 | 3 rows, each h76, gap 10, radius 20, padding 14, gap 12. The right side is a 48×48 icon tile (radius 16) | `radius.l`, `radius.m` |
| 3a | Row · done, unclaimed | h76 | `primary.soft` row. Icon tile is `primary` with a white `check` 26. Title 15/700. Meta «٢٠/٢٠ · +٥ بونات» 12/600 `primary`. `AppButton` primary m «خد» (h44, padding 0 18, radius 14, lip 4, Marhey 17) | `row` w700, `label`, `lip.primary.s` |
| 3b | Row · in progress | h76 | `ground` row. Icon tile is `paper` with the task icon (`booster_wake`, `star_ink` tinted `gold`). Line 1: title 15/700 with the reward 12/600 `ink.muted` at the end. Line 2: `ProgressBar` primary (h8, `paper` track) plus a count 12/700 | `ground`, `paper`, `primary` |
| — | Spacer | flex | | |
| 4 | Secondary CTA | y760 h60 | `AppButton` secondary «يلا نطلع مشوار» (Marhey 21, radius 20, inset ring 2 `ground.lip`, lip 5 `ground.lip`) | `button.l`, `radius.l` |

**Dynamic data.**
- The task list comes from `daily_state` (tasks), built from the content pack `tasks[]` (`TaskTemplate`): title, icon, target, BONAT reward. Samples: «رجّع ٢٠ باقي صح», «صحّي ٣ نايمين», «خلّص مشوار بتلات نجوم».
- Progress `{n}/{target}` comes from task counters that advance on accepted `trip_result` ops. The server keeps `DailyState.task_counters`.
- The reset countdown «بعد ٦ ساعات» is the time left until the next game day, using server-corrected time (§13).
- A row is "done" when the counter reaches the target. "Claimed" is stored in `daily_state`.

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| ✕ «اقفل», scrim, swipe down | tap / drag | Closes the sheet and returns to `/home`. |
| «خد» on a done task | tap | Sync op `claim_task`, +BONAT. The amount flies to the BONAT `CurrencyPill`. Logs analytics `daily_task_done`. |
| «يلا نطلع مشوار» | tap | Same as Home «يلا نطلع!»: opens `/home/pre-trip/:tripId` for the next trip on the current line. With fuel at 0 it opens `/shop/fuel` instead. |

**States & edge cases.**
- **Claimed row:** not drawn. Proposal: keep the done look and replace «خد» with a `StatusChip` «خلص».
- **All three claimed:** the rows stay, and the countdown stays visible.
- **Under one hour to reset:** the copy is not drawn. Proposal: «مهام جديدة بعد {m} دقيقة».
- **Long task titles:** wrap to 2 lines and let the row grow (minimum 76). Never truncate the reward or the count.
- **Offline:** progress still counts locally. A claim queues like any other sync op. See Notes.

**Motion.** The sheet uses `sheetIn` / `sheetOut`. «خد» uses `press`. Progress fill changes tween with `toast` (200 ms easeOut). The progress bar fills from the start side (right in RTL).

**Accessibility.**
- The sheet is a dialog labelled by «مهام اليوم». The close button is labelled «اقفل».
- Each row reads as: title, progress «{n} من {target}», reward. On claim, announce the granted BONAT as a polite live region.
- Reading order: title → timer → rows from top to bottom → CTA. All targets are at least 44.

**Strings.**
```
tasks.title: "مهام اليوم"
tasks.resetIn: "مهام جديدة بعد {h} ساعات"
tasks.close: "اقفل"
tasks.claim: "خد"
tasks.doneMeta: "{n}/{n} · +{reward} بونات"
tasks.reward: "+{reward} بونات"
tasks.progress: "{n}/{target}"
tasks.cta: "يلا نطلع مشوار"
```

**Notes.**
- Architecture §9 lists `/daily/tasks` without saying "(sheet)". The design is a sheet; use sheet presentation.
- The claimed-row style and the under-one-hour copy are not drawn.
- Granting BONAT is server-authoritative (§18.4). Should an offline claim show the BONAT optimistically or wait for the network? To be decided.

---

#### تحدي اليوم — `Challenge`

| | |
| --- | --- |
| Route | `/daily/challenge` (full screen) |
| Feature folder | `features/daily/` |
| Phase | MVP |
| Files | `screens/Challenge.html` · `png/Challenge.png` |

**Purpose.** Shows the one trip that every player gets today: what's special about it, the player's best result, the play button (the first attempt is free), and a spoiler-free share card.

**Layout, top to bottom.** Padding 36/16/24, gap 14.

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 1 | `ScreenHeader` | y36 h52 | `IconCircleButton` back (44, `paper`, lip 4). Title «تحدي النهارده». Trailing block, end-aligned: «الجاي بعد» 12/600 `ink.muted` above the countdown «٩:١٢:٤٠» 15/700 | `display.m` (26), `lip.card.small` |
| 2 | Hero card | y102 h303, radius 26 | Art area 358×200: `illustrations/screens/Challenge_01.svg` on `dashboard.raised` (effendi holding a ٢٠٠ note between two sleepers). Text area with padding 14/16/16 and gap 6: title in Marhey 700 20, white; description 13/500 `dashboard.text` | `dashboard.bg`, `lip.dark`, `radius.scene` |
| 3 | Best result | y419 h60, radius 20, padding 0 16 | `AppCard` row: «أحسن نتيجة ليك» 14/600 on one side; `Stars` 18 (`gold`, with the empty star in `ground.lip`) plus «في ٢:١٤» 15/700 on the other | `paper`, `lip.card`, `body` w600 |
| 4 | CTA | y493 h66 | `AppButton` primary xl «العبه» (27) with a `sun` pill «أول محاولة من غير بنزين» (h30, padding 0 10, 13/700 `ink`) | `button.xl`, `lip.primary` |
| 5 | Share panel | y573, flex fills the rest (h247 here), radius 22, padding 12, gap 14 | `AppCard` with an inset 2-px `outline` ring. On the right, the share-card preview: 128×128, radius 20, `sun`. It holds «تحدي ٢٣ أكتوبر» (Marhey 13), stars «★★☆» 22 `ink`, `clock` + «٢:١٤», `speech` + «٠» (12/700), and «وصّل الأجرة» 12/700. On the left: «بعد ما تلعب» 14/700, a description 12/500 `ink.2` with line-height 1.5, and `AppButton` sun m «شارك» (h44, radius 14, lip 3–4 `sun.lip`, `share` 18) | `paper`, inset ring 2 `outline`, `radius.card`, `sun`, `lip.sun` |

**Dynamic data.**
- Challenge description, trip, seed and rewards come from `GET /v1/daily-challenge` (`trip`, `params`, `rewards`).
- Countdown to the next challenge: next game day minus server time, shown as H:MM:SS and ticking every second.
- Best stars and time come from `daily_state` (challenge attempts) or `DailyAttempt` (verified result). Time is shown as M:SS.
- The free-attempt pill is shown only when `next_attempt_cost.fuel == 0`.
- Share card fields: the date from `game_date` with Arabic month names, plus stars, time and fights from the best verified attempt.
- The hero art is specific to the challenge (see Notes).

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| Back | tap | Pops back to `/home`. |
| «العبه» | tap | Opens `/home/pre-trip/:tripId` with `tripId` = `challenge_id`. When the attempt costs fuel and fuel is 0, it opens `/shop/fuel`. After the trip, the result is posted to `/v1/daily-challenge/result` for replay verification. |
| «شارك» | tap | Renders the square share card (same pipeline as `ShareCard`) and opens `share_plus`. Logs analytics `share` with `kind=daily_challenge`. |

**States & edge cases.**
- **Not played yet:** proposal. Hide the best-result row and disable «شارك». The share panel then works as an explainer.
- **First attempt used:** hide the pill. The CTA shows the fuel cost, like Home's «−١» badge. The retry cost is still open (backend Q 11).
- **Offline:** the challenge needs the network (§11). On Home the circle is disabled with «محتاج نت» (`HomeStates`). If the screen is opened anyway, use the offline pattern in `States`.
- **Loading:** use the `States` loading pattern inside the hero card.
- **Countdown reaches 0:** refetch the challenge and reset attempts.
- **Locked by driver level** (product spec: «الدرجة تفتح التحدي اليومي»): not drawn.
- **Long description:** at most 2 lines at Marhey 20, then ellipsis. The sub-line is at most 2 lines.

**Motion.** Buttons use `press`. The countdown updates its text only, with no animation. The share card can fade in after the first verified result (≤150 ms).

**Accessibility.**
- The back button is labelled «رجوع». The share card is `role=img` with the label «كارت المشاركة: نجمتين، دقيقتين و١٤ ثانية، صفر خناقات»; generate it from the data.
- The countdown is not live-announced. Its label reads «التحدي الجاي بعد {h} ساعة و{m} دقيقة».
- Stars are read as a number («نجمتين من تلاتة»).
- Reading order: header → description → best result → «العبه» → share panel.

**Strings.**
```
challenge.back: "رجوع"
challenge.title: "تحدي النهارده"
challenge.nextIn: "الجاي بعد"
challenge.fairLine: "نفس الركاب ونفس الفكة لكل اللاعبين النهارده. مين فيكم أشطر؟"
challenge.best: "أحسن نتيجة ليك"
challenge.bestTime: "في {time}"
challenge.cta: "العبه"
challenge.freeAttempt: "أول محاولة من غير بنزين"
challenge.shareCardTitle: "تحدي {date}"
challenge.shareCardBrand: "وصّل الأجرة"
challenge.shareHeading: "بعد ما تلعب"
challenge.shareBody: "كارت بالنجوم والوقت والخناقات بس، من غير ما يكشف المشوار."
challenge.share: "شارك"
challenge.a11yShareCard: "كارت المشاركة: {stars}، {time}، {fights}"
```
The title «فيه أفندي معاه ٢٠٠ ونايمين اتنين» is challenge data, not a static string.

**Notes.**
- The artboard shows «أحسن نتيجة ليك» and «أول محاولة من غير بنزين» together. A best result means the free attempt is already used, so both can't be true at once. Apply the visibility rules above.
- The hero art depicts today's specific passengers. Either compose it from `PassengerAvatar`s plus a `MoneyNote`, or ship generic art. Needs a decision.
- `GET /v1/daily-challenge` returns `rewards` per star count, but the design doesn't show rewards anywhere.
- `trip_id` is defined as `<line_id>.<nn>`. The pre-trip route must also accept a `challenge_id`.
- In the HTML, «شارك» uses the browser's default black text. Use `ink`.

---

#### الإعدادات — `Settings`

| | |
| --- | --- |
| Route | `/settings` (full screen, scrolls; the artboard is 1420 tall) |
| Feature folder | `features/settings/` |
| Phase | MVP |
| Files | `screens/Settings.html` · `png/Settings.png` |

**Purpose.** Shows the driver's profile card with simple stats, plus the sound, play, notification, account and about settings.

**Layout, top to bottom.** One vertical scroll. Padding 36/16/24, gap 12. The header scrolls with the content, as drawn. Each group is a section `h2` (13/700 `ink.muted`, padding 0 6) above a `paper` card (radius 22, padding 0 14, no lip). Rows are 52 tall with a 2-px `track` divider; the last row has no divider.

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 1 | `ScreenHeader` | y36 h52 | Back + «الإعدادات» | `display.m` (26) |
| 2 | Profile `AppCard` | y100 h158, radius 24, padding 14, gap 12 | Row: avatar 64 (`sun` circle, lip 4 `sun.lip`, driver face from `characters/usta.svg`), name in Marhey 700 20, «درجة ٣» 13/600 `primary`, and `IconCircleButton` edit 44 (drawn as a square with radius 14, `ground` fill, label «غيّر الاسم»). Stats: 3 tiles 105×54 at y190 (radius 16, `ground`), each with a value 18/700 and a label 12/500 `ink.muted` | `paper`, `lip.card`, `radius.xl` |
| 3 | الصوت | y270, card y292 h160 | 3 `ListRow`s, each with an `AppSwitch`: المزيكا (on), المؤثرات (on), أصوات الركاب (off) | `row` w500 |
| 4 | اللعب | y464, card y486 h246 | الاهتزاز with `AppSwitch`. «كارت ما قبل المشوار» (y540 h97) with a label plus a `Segmented` row: يظهر دايمًا / في الجديد بس. «شكل الأرقام» (y637 h95) with a `Segmented` row: عربية ١٢٣ / غربية 123 | Segmented: `ground` track, radius 14, padding 4. Segments are h40, radius 10. The active one is `paper` with lip 2 `ground.lip`, 13–14/700. Inactive ones are transparent, `ink.2`, w600 |
| 5 | الإشعارات | y744, card y766 h214 | 4 switch rows: البنزين اتملى, تحدي اليوم, رسايل سلمى (all on), ملك الخط (off) | |
| 6 | الحساب | y992, card y1014 h160 | «اربط حسابك» (h56: `google` 22 + title 15/600 + sub 12/500 `ink.muted` + chevron). «استرجاع المشتريات» (h52 + chevron). «حذف الحساب» (h52, 15/600 `danger.ink`, chevron `danger.ink`) | chevron = `chevron_back_soft` tinted `icon.off` |
| 7 | عن اللعبة | y1186, card y1208 h160 | سياسة الخصوصية, الشروط, كلّمنا, each with a chevron | `row` w500 `ink` |
| 8 | Version | y1380 h15, centred | «وصّل الأجرة · نسخة ١٫٠» | `label` w500 `ink.muted` |

`AppSwitch` is 52×30 with a 24 knob. On: `primary` track, knob at the end side (left in RTL). Off: `ground.lip` track, knob at the start side.

**Dynamic data.**
- The name comes from `profile.display_name` (sample «أسطى أحمد»; how the «أسطى» prefix is handled is defined on `Name`). The level comes from `profile.driver_level`.
- Stats:
  - Trips: total trips played. There is no named field yet; see Notes.
  - Stars: the sum of `trip_progress.best_stars`.
  - Longest streak: missing field; see Notes.
- Switches and segments come from `profile.settings` JSON. Each change is saved locally and sent as the sync op `settings_update`.
- The pre-trip card default comes from Remote Config `pre_trip_card_mode` (`always`) until the player changes it.
- Notification switches also update `POST /v1/push-tokens` categories: تحدي اليوم → `daily`, رسايل سلمى → `story`, ملك الخط → `league`. «البنزين اتملى» is a local notification and only toggles local scheduling.
- The version comes from package info.

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| Back | tap | Pops back to `/home`. |
| Edit «غيّر الاسم» | tap | Opens name editing. The UI is not drawn; see Notes. |
| Switch rows | tap anywhere on the row | Toggle and save. Sound and haptics apply immediately. |
| Segmented | tap | Select. Digit shape re-renders the whole app at once. |
| «اربط حسابك» | tap | Starts Google/Apple linking (`POST /v1/auth/link`). On `409 provider_in_use`, show the two progress summaries so the player can choose (§16). §9 route `/settings/account` has no artboard. |
| «استرجاع المشتريات» | tap | Store restore, then `/v1/purchases/verify` for each purchase (§15.2.5). Needs the network. |
| «حذف الحساب» | tap | Opens `/settings/account/delete` **(new route)**, step 1 (`DeleteStep1`). |
| Privacy / Terms | tap | Open the external URL in the in-app browser. |
| «كلّمنا» | tap | The target is not specified. |

**States & edge cases.**
- **Not linked** (drawn): the link row shows the sub-line. When linked, the linked state is not drawn. Proposal: show the provider name with a `StatusChip`.
- **Offline:** the link and restore rows show the `StatusChip` «محتاج نت» and do nothing. Everything else works.
- **Long name:** 1 line with an ellipsis before the edit button. Stats values must fit in 105 px; use the compact digits formatter (for example ١٬٢٤٨).
- **Restore in progress:** use the `States` loading pattern in the row. Results are not drawn.

**Motion.** The switch knob slides (component default). Rows use `press` on tap. No screen-level motion.

**Accessibility.**
- Labels from the HTML: back «رجوع», edit «غيّر الاسم». Switches are `role=switch` with `aria-label` equal to the row text. The two segmented rows are radiogroups labelled «كارت ما قبل المشوار» and «شكل الأرقام».
- Group headings are headers (h2).
- The whole 52-px row is the switch's hit target; the visual switch is only 30 tall.
- Reading order: header → profile → groups top to bottom → version.

**Strings.**
```
settings.back: "رجوع"
settings.title: "الإعدادات"
settings.level: "درجة {n}"
settings.editName: "غيّر الاسم"
settings.statTrips: "مشوار"
settings.statStars: "نجمة"
settings.statStreakValue: "{n} يوم"
settings.statStreak: "أطول سلسلة"
settings.groupSound: "الصوت"
settings.music: "المزيكا"
settings.sfx: "المؤثرات"
settings.voices: "أصوات الركاب"
settings.groupPlay: "اللعب"
settings.haptics: "الاهتزاز"
settings.preTrip: "كارت ما قبل المشوار"
settings.preTripAlways: "يظهر دايمًا"
settings.preTripNewOnly: "في الجديد بس"
settings.digits: "شكل الأرقام"
settings.digitsArabic: "عربية ١٢٣"
settings.digitsWestern: "غربية 123"
settings.groupNotif: "الإشعارات"
settings.notifFuel: "البنزين اتملى"
settings.notifChallenge: "تحدي اليوم"
settings.notifSalma: "رسايل سلمى"
settings.notifLeague: "ملك الخط"
settings.groupAccount: "الحساب"
settings.link: "اربط حسابك"
settings.linkSub: "بجوجل أو أبل عشان تقدّمك ما يضيعش"
settings.restore: "استرجاع المشتريات"
settings.delete: "حذف الحساب"
settings.groupAbout: "عن اللعبة"
settings.privacy: "سياسة الخصوصية"
settings.terms: "الشروط"
settings.contact: "كلّمنا"
settings.version: "وصّل الأجرة · نسخة {version}"
```
«غربية 123» keeps Western digits in both digit modes.

**Notes.**
- The «ملك الخط» notification switch belongs to the public launch. Hide it in MVP.
- «أطول سلسلة» needs a longest-streak value. `daily_state` and `DailyState` only store the current streak. The trip count has no named field either.
- Backend §14.1 says Settings shows a support code for deleting the account on the web. It isn't drawn.
- UX puts an «ادعي صاحبك» card in Settings. It isn't on this (MVP) artboard; add an entry to `/settings/referral` at the public launch.
- The name-editing UI is not drawn. Proposal: a `Sheet` reusing the `AppTextField` and validation from `Name`.
- The segmented style here (active `paper` segment on a `ground` track) matches neither `Segmented` variant (sun | primary): **(new variant `paper`)**.
- The edit button is a 44 square with radius 14 rather than a circle.

---

#### حذف الحساب: خطوة ٢ — `DeleteAccount`

| | |
| --- | --- |
| Route | `/settings/account/delete/confirm` **(new route)** (full screen, after step 1 `DeleteStep1`) |
| Feature folder | `features/settings/` |
| Phase | MVP |
| Files | `screens/DeleteAccount.html` · `png/DeleteAccount.png` |

**Purpose.** A store-required account deletion that can never happen with a single tap. The screen spells out what will be lost, and the player must type «امسح» before the danger button becomes active.

**Layout, top to bottom.** Padding 36/16/28, gap 14.

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 1 | `ScreenHeader` | y36 h52 | Back (→ Settings). Title «حذف الحساب». Trailing `StatusChip` «خطوة ٢ من ٢» (`paper`, 12/700, padding 2 10) | `display.m` (26), `label` w700 |
| 2 | Loss card | y102 h149, radius 24, padding 16, gap 12 | `AppCard` with the heading «اللي هيتمسح ومش هيرجع:» 15/700, then 3 lines (14/500, gap 10), each starting with `x_circle` 22 | `paper`, `lip.card`, `row` w700, `body` |
| 3 | Confirm field | y265 h82 | Label «اكتب كلمة «امسح» عشان تأكد» 14/600. `AppTextField` h56 (y291): `paper`, inset 2-px `ground.lip` ring, radius 16, 20/600 `ink`, placeholder «امسح», autocomplete off. Focus: 3-px `danger.ink` outline with offset 2 | `body` w600, `radius.m` |
| — | Spacer | flex | | |
| 4 | Danger CTA | y690 h60 | `AppButton` danger «امسح حسابي» (Marhey 22, radius 20, `ink` text). Disabled: 45 % opacity, no lip | `danger`, `lip.danger` (when enabled) |
| 5 | Safe CTA | y760 h56 | `AppButton` primary l «لأ، رجّعني» (Marhey 21, radius 18, lip 5) | `button.l`, `lip.primary.m` |

**Dynamic data.** Nothing on screen is dynamic. The only input is the typed value; the enabled state is derived from it.

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| Back, «لأ، رجّعني» | tap | Pops back to `/settings`. |
| Field | type | Enables the danger CTA when the trimmed text equals «امسح» exactly. |
| «امسح حسابي» | tap (enabled) | Calls `DELETE /v1/account` (needs the network). On 202: clear tokens (secure storage), the drift DB and scheduled notifications, unregister the push token, then `go('/boot')` as a fresh install. |

**States & edge cases.**
- **Disabled** (drawn): any other text, including an empty field.
- **Request in flight:** the button shows the loading pattern and both buttons are blocked.
- **Offline or error:** keep the screen and show the `StatusChip` «محتاج نت», or the error copy (not drawn).
- **Keyboard open:** the layout resizes so both buttons stay above the keyboard. The loss card can scroll.

**Motion.** `press` on the buttons. The disabled → enabled change cross-fades opacity in 150 ms and the lip appears.

**Accessibility.**
- Labels from the HTML: back «رجوع»; the field is labelled by its `<label>`. Use `aria-disabled` for the danger button.
- When the button becomes enabled, announce «زرار امسح حسابي بقى متاح».
- Reading order: title → step chip → loss list → field → danger → safe.

**Strings.**
```
deleteAccount.back: "رجوع"
deleteAccount.title: "حذف الحساب"
deleteAccount.step: "خطوة {n} من {total}"
deleteAccount.lossHeading: "اللي هيتمسح ومش هيرجع:"
deleteAccount.lossProgress: "كل الخطوط والنجوم ودرجة الأسطى"
deleteAccount.lossApartment: "الشقة والعفش والمشاهد اللي اتفتحت"
deleteAccount.lossMoney: "الجنيهات والبونات، وأي حاجة اشتريتها"
deleteAccount.confirmLabel: "اكتب كلمة «امسح» عشان تأكد"
deleteAccount.confirmWord: "امسح"
deleteAccount.cta: "امسح حسابي"
deleteAccount.cancel: "لأ، رجّعني"
```

**Notes.**
- Step 1 is now drawn: `DeleteStep1` (new-screens section). Back from step 2 returns to step 1.
- Backend deletion is pending for 7 days (§14.1), but the copy doesn't say so. Not drawn: whether a confirmation screen shows the deletion date, and whether the player can cancel by signing in again.
- Placeholder colour isn't set in the HTML (browser grey). Use `ink.muted`.

---

#### رجوع الغايب — `Returning`

| | |
| --- | --- |
| Route | `/welcome-back` **(new route)** (full-screen dialog at launch, before `/home`) |
| Feature folder | `features/settings/` (§5: "welcome back") |
| Phase | MVP |
| Files | `screens/Returning.html` · `png/Returning.png` |

**Purpose.** Greets a player who has been away for 7 days or more with a word from المعلم, a comeback gift (full tank and a change bag), and a reminder of where they stopped in the story.

**Layout, top to bottom.**

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 0 | Background | 390×844 | `sun` with 2 circles: r110 at (330,110) and r130 at (40,760) | `sun`, `sun.glow` |
| 1 | Dialog card | x16 y120 w358 h471, radius 28, padding 100/18/18, gap 14 | `AppDialog` (`role=dialog`) with lip 6 `sun.lip` | `paper`, `radius.sheet` |
| 2 | Character | 150×150 at y50 (overlaps the card top by 70), centred | `CharacterAvatar` المعلم on a `sun.soft` disc. Static art: `illustrations/screens/Returning_01.svg` | `sun.soft` |
| 3 | Speaker | y220 h16 | «المعلم» | `caption` w600 `ink.muted` |
| 4 | Line | y250 h70, centred, 2 lines | «إنت فين يا أسطى؟ الموقف كان واحشك» with line-height 1.35 | `display.m` (26) |
| 5 | Gift tiles | y334 h88 | 2 columns, gap 10. Each tile is 156×88, radius 20, `ground`, padding 12, gap 6: icon 40 (`fuel`, `booster_change_bag`) + label 14/700 | `ground`, `radius.l` |
| 6 | Where-you-stopped strip | y436 h59, radius 18, padding 10 12 | `house_filled` 22 `primary` + text 13/600 with line-height 1.5 (up to 2 lines) | `sun.soft`, `radius.bubble` |
| 7 | CTA | y509 h64 | `AppButton` primary xl «خدها» (Marhey 26) | `button.xl`, `lip.primary` |

**Dynamic data.**
- The trigger is the last session date versus server time, at 7 days or more (UX and product spec).
- The gift is static per spec (`refuel_full` + 1 `change_bag`). Proposal: put the contents in Remote Config.
- The strip text comes from the current chapter in `story_state` and the missing items of the current room from content plus `ownership`. Shape: «كنت واقف في الفصل {n}: فاضلك {items}.» Show it only when the player is mid-chapter. Name at most 2 items, joined with «و».

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| «خدها» | tap | Grants the gift: fuel to max and inventory `change_bag` +1. The icons fly to the fuel `CurrencyPill` on Home. Then `go('/home')`, or `/daily/reward` if that is still claimable (see Notes). |
| System back | press | Same as «خدها». The gift is never lost. |

**States & edge cases.**
- **Not mid-chapter:** hide row 6. The card height shrinks.
- **Fuel already full:** still show the tile. The grant is a no-op for fuel.
- **Offline:** grant locally and sync later (same as other grants; see Notes).

**Motion.** The card enters with `dialogIn`. المعلم's `CharacterAvatar` plays idle, then talk once. The gift icons fly out on claim. Reduced motion: fade only.

**Accessibility.** The dialog is labelled by the line text (`aria-labelledby=rtTitle`). Reading order: «المعلم» → line → gifts («خزان مليان»، «كيس فكة») → reminder → «خدها». The CTA is 322×64.

**Strings.**
```
returning.speaker: "المعلم"
returning.line: "إنت فين يا أسطى؟ الموقف كان واحشك"
returning.giftFuel: "خزان مليان"
returning.giftChangeBag: "كيس فكة"
returning.whereYouStopped: "كنت واقف في الفصل {n}: فاضلك {items}."
returning.cta: "خدها"
```

**Notes.**
- The order relative to `Daily` at launch isn't specified. Proposal: `Returning` first, then `Daily` if it is claimable.
- Backend has no grant path for this gift: there is no comeback reason in the ledger `reason` enum and no matching sync op (backend §7.4). One must be added.
- §9 has no route for this screen, hence the proposed `/welcome-back`.
- The card lip uses `sun.lip` at 6 px; the `lip.sun` token is 4.

---

#### الحالات العامة — `States`

| | |
| --- | --- |
| Route | none. This is a catalogue of shared states, used inside other routes. |
| Feature folder | shared widgets. Triggers live in `core/network`, `core/ads`, `core/iap`, `core/economy`, `core/sync`. |
| Phase | MVP |
| Files | `screens/States.html` · `png/States.png` (390×1400; the blocks are stacked for reference only) |

**Purpose.** Each message says what happened and what the player can do now, in colloquial Egyptian and without long apologies (UX «الحالات العامة»). Every state below is a reusable component.

**Layout, top to bottom (catalogue positions).**

| # | State | y / h | Component |
| --- | --- | --- | --- |
| 1 | Offline | y36 h40 | `OfflineBanner` |
| 2 | Ad not ready | y92 h64 | `AppCard` row + BONAT alternative |
| 3 | Daily ad limit reached | y172 h56 | disabled `RewardedAdButton` + secondary `AppButton` |
| 4 | Spend confirmation | y244 h222 | `AppDialog` (alertdialog) |
| 5 | Undo toast | y482 h56 | `UndoToast` |
| 6 | Payment failed | y554 h166 | alert card **(new component `InlineAlert`)** |
| 7 | Update required | y736 h134 | `AppDialog` content |
| 8 | Maintenance | y886 h104 | dark status card **(new component `StatusCard`)** |
| 9 | Empty state | y1006 h182 | **(new component `EmptyState`)** |
| 10 | Loading | y1204 h64 | **(new component `MicrobusLoader`)** |

##### 1. Offline — `OfflineBanner`

| | |
| --- | --- |
| Where | Top of `/home` (see `HomeStates`), shown while there is no network. Features that need the network show the `StatusChip` «محتاج نت» (Shop, daily challenge, leagues, rewarded ads, real-money buys, link/restore). |
| Component | h40, radius 14, padding 0 12, gap 8, `dashboard.bg`. Icon `wifi_off` 20 tinted `sun`. Text 12.5/500 white. `role=status`. |
| Copy | «انت أوفلاين، المشاوير شغالة والتقدم هيتحفظ لما النت يرجع» |
| Actions | None. It hides by itself when the network is back and `/v1/bootstrap` + sync succeed. |

##### 2. Ad not ready

| | |
| --- | --- |
| Where | Replaces a `RewardedAdButton` in place when `AdsGateway.isReady(placement)` is false: Result ×2, Fuel, Fail revive, morning piggy. In a trip, the traffic-jam booster button switches to its price state instead. |
| Component | `AppCard` row: padding 10 12, radius 18, lip 5 `ground.lip`. Icon `ad_not_ready` 26, text 13/600 with line-height 1.5 (2 lines), BONAT alternative button h44, radius 14, `primary.soft` fill, `primary` text 13/700. `role=status`. |
| Copy | «الإعلان مش جاهز دلوقتي، جرّب كمان شوية» · alternative «بـ{n} بونات». The price comes from the placement's booster (§3.3): traffic_jam 8, revive 20, refuel_full 30. |
| Actions | The alternative runs the BONAT path for that booster: undo toast if under 50, confirmation if 50 or more. `result_double` and `morning_piggy` have no BONAT price, so they show the text only. Re-check `isReady` when the screen resumes. |

##### 3. Daily ad limit reached

| | |
| --- | --- |
| Where | Any capped placement once its cap is used (§3.4), mainly the Fuel sheet (`fuel_refill` 3 per day). |
| Component | Two equal buttons, gap 10, h56, radius 18. Disabled ad button: `ground.lip` fill, `ink` 15/700, `ad_screen` 20, no lip, `aria-disabled`. Next to it, `AppButton` secondary: `paper`, inset 2 `ground.lip`, lip 4. |
| Copy | «خلصت النهارده» · «فوّل بـ{n} بون» |
| Actions | The disabled button does nothing. The BONAT button buys the booster (confirmation if 50 or more). |

##### 4. Spend confirmation

| | |
| --- | --- |
| Where | Any BONAT spend of 50 or more (UX «الشرا»), for example `fuel_unlimited_1h` 80. Centred over a `Scrim` (the scrim isn't drawn on the board). |
| Component | `AppDialog` `role=alertdialog`: radius 24, padding 18, gap 12, centred. Icon `bonat_alt` 44. Title `display.m` (22). Meta 13/500 `ink.muted`. Buttons row, gap 10: `AppButton` primary (flex 2, h52, radius 18, lip 5, Marhey 19) and tertiary (flex 1, `ground`, 15/700). |
| Copy | «هتصرف {n} بون؟» · «{item} · معاك {balance} بون» · «أيوه» · «لأ» |
| Actions | «أيوه»: `EconomyService.apply(spend_bonat)`, close, play the reward motion. «لأ», scrim tap or back: close with no change. |

##### 5. Undo toast — `UndoToast`

| | |
| --- | --- |
| Where | BONAT purchases under 50, at the bottom of the screen above the CTA area (Shop, Fuel, pre-trip boosters). Never during a running trip (that uses its own 1-second undo, `trip_undo_window_ms`). |
| Component | h56, radius 18, padding 0 8 0 14, gap 10, `dashboard.bg`. Item icon 22 (for example `booster_change_bag`), text 13/600 white, `sun` button h40, radius 12, 14/700 `ink` with a countdown 3→1. `role=status`. |
| Copy | «اتشرى {item} بـ{price} بون» · «رجّع {s}» |
| Actions | Apply the op locally but hold back the sync op for 3 s. «رجّع» removes the local op and restores the balance. When the timer ends, the op is committed. |

##### 6. Payment failed

| | |
| --- | --- |
| Where | After a real-money purchase fails or verification returns `invalid` (not a user cancel): Shop, Starter, Event pass. |
| Component | `role=alert`, `danger.soft` fill, radius 22, padding 14, gap 10. Title row: `warning` 22 + Marhey 18 (`display.s`). Body 13/500 with line-height 1.6. Buttons h44, radius 14, 14/700: primary «جرّب تاني» (no lip drawn) and `paper` «طريقة تانية». |
| Copy | «الدفع ما تمّش» · «وما اتخصمش منك حاجة. جرّب تاني أو اختار طريقة دفع تانية.» · «جرّب تاني» · «طريقة تانية» |
| Actions | Both relaunch the store purchase for the same `product_id` (the store sheet lets the player change method). Close it by tapping elsewhere or by navigating away. |

##### 7. Update required

| | |
| --- | --- |
| Where | `/v1/bootstrap` returns `client.force_update: true`, or any call returns `426 client_outdated`. Blocking overlay over `/boot` or `/home`. |
| Component | `AppDialog` content: radius 24, padding 16, gap 12, lip 5 `ground.lip`. Icon tile 64 (`primary.soft`, radius 18, microbus plus a `sun` star; inline SVG). Title Marhey 17 (≈`display.s`). Body 13/500 `ink.2`. `AppButton` primary m «حدّث من المتجر» (h44, radius 14, lip 4). |
| Copy | «فيه نسخة جديدة» · «فيها خطوط جديدة. حدّث عشان تكمّل.» · «حدّث من المتجر» |
| Actions | Opens the store listing. When the update is forced, there is no close button and system back does nothing. An optional update (`latest_version` > current, not forced) gets a close button per UX, but that variant isn't drawn. |

##### 8. Maintenance

| | |
| --- | --- |
| Where | The API returns `503 maintenance` (writes blocked). Shown on `/home` in place of the banner area. Offline trips keep working. |
| Component | `role=status`, `dashboard.bg`, radius 24, padding 16, gap 12. المعلم with a wrench at 72 (`illustrations/screens/States_01.svg`). Title Marhey 17 `sun`. Body 13/500 `dashboard.text`. |
| Copy | «الموقف بيتصلّح» · «راجعين الساعة {time}. المشاوير شغالة أوفلاين.» |
| Actions | None. Retry bootstrap on the next resume. |

##### 9. Empty state

| | |
| --- | --- |
| Where | Any empty list. Drawn for the Invite friends list. |
| Component | `paper`, inset 2 `outline` ring, radius 24, padding 18, gap 10, centred. Illustration 80×60 (a friend next to a dashed "missing friend" in `ground.lip`). Text 14/600. `AppButton` sun m (h48, radius 16, lip 4 `sun.lip`, 15/700). |
| Copy | «لسه ما دعيتش حد. ابعت كودك لصاحبك.» · «ابعت الكود» |
| Actions | The button runs the action that fills the list (here, Invite share). |

##### 10. Loading

| | |
| --- | --- |
| Where | In-app loads (content pack swap, line load, restore, challenge fetch). Never a white screen. |
| Component | `role=progressbar` labelled «بيحمّل», h64. A road track 200×16 pill in `scene.road`, with a microbus block 36×24, radius 10, `primary`, lip 3 `primary.lip`, riding over it. Caption 13/600 `ink.2` under it. |
| Copy | «بنحمّل الخط..». The context word changes per use; only this one is drawn. |
| Actions | None. |

**Dynamic data.** Prices, item names and balances come from the catalog and wallet (§13). The maintenance return time and the update flag come from the API. The undo countdown is local.

**Interactions.** Listed per state above.

**States & edge cases.**
- **Several states at once:** the Offline banner wins over Maintenance. Update required blocks everything.
- **Long item names** in the toast and dialog meta: 1 line with an ellipsis. The price never truncates.

**Motion.**
- Banners and cards fade in ≤150 ms.
- The dialog uses `dialogIn`.
- The toast uses `toast` (200 ms in, holds 3000 ms).
- The loader microbus loops from right to left across the track. Proposal: 1200 ms easeInOut. Under reduced motion, show a static vehicle.

**Accessibility.**
- Roles come from the HTML: `status` (offline, ad not ready, undo, maintenance), `alert` (payment failed), `alertdialog` (spend), `dialog` (update), `progressbar` «بيحمّل».
- Announce the toast and payment failures once. Never announce the countdown ticks.
- The undo button must have a hit area of at least 44 (it is drawn 40 tall).

**Strings.**
```
states.offline: "انت أوفلاين، المشاوير شغالة والتقدم هيتحفظ لما النت يرجع"
states.needsNet: "محتاج نت"
states.adNotReady: "الإعلان مش جاهز دلوقتي، جرّب كمان شوية"
states.adAltBonat: "بـ{n, plural, few{{n} بونات} other{{n} بون}}"
states.adLimitReached: "خلصت النهارده"
states.refuelBonat: "فوّل بـ{n} بون"
states.spendTitle: "هتصرف {n} بون؟"
states.spendMeta: "{item} · معاك {balance} بون"
states.spendYes: "أيوه"
states.spendNo: "لأ"
states.undoText: "اتشرى {item} بـ{price} بون"
states.undoButton: "رجّع {s}"
states.payFailTitle: "الدفع ما تمّش"
states.payFailBody: "وما اتخصمش منك حاجة. جرّب تاني أو اختار طريقة دفع تانية."
states.payRetry: "جرّب تاني"
states.payOtherMethod: "طريقة تانية"
states.updateTitle: "فيه نسخة جديدة"
states.updateBody: "فيها خطوط جديدة. حدّث عشان تكمّل."
states.updateCta: "حدّث من المتجر"
states.maintTitle: "الموقف بيتصلّح"
states.maintBody: "راجعين الساعة {time}. المشاوير شغالة أوفلاين."
states.emptyInvite: "لسه ما دعيتش حد. ابعت كودك لصاحبك."
states.emptyInviteCta: "ابعت الكود"
states.loadingA11y: "بيحمّل"
states.loadingLine: "بنحمّل الخط.."
```
`states.needsNet` is taken from the `Components` and `HomeStates` artboards. It isn't drawn on this board.

**Notes.**
- **Offline banner:** the copy wraps to 2 lines inside a fixed 40-px banner, at 12.5 px (not a token size). Either use `label` and let the banner grow (minimum 40, padding 6), or use the short Components copy «انت أوفلاين، المشاوير شغالة».
- **Daily-limit button:** the disabled ad button is drawn with a `ground.lip` fill at full opacity. The token rule says disabled = 45 % opacity with no lip. Pick one.
- **Undo button:** drawn h40, below the 44 minimum.
- **Non-token styling:**
  - The spend dialog lip is rgba(0,0,0,.18).
  - «جرّب تاني» has no lip.
  - The update and maintenance titles are Marhey 17 (between `display.s` and `quote`).
- **Maintenance time:** «راجعين الساعة ٤» needs a return time from the API. The `503 maintenance` response has no such field.
- **Plural:** this board writes «بـ١٠ بون», but Daily and Tasks write «١٠ بونات». Use one ICU plural rule everywhere.
- **Interruption:** the UX «مقاطعة» state (call or leaving the app) is handled by the `Pause` artboard, not here.

---

#### الجراج — `Garage`

| | |
| --- | --- |
| Route | `/garage` (full screen). Opened from the Home vehicle «الجراج: زوّق عربيتك» and from the Shop link «شوف الزينة». |
| Feature folder | `features/garage/` |
| Phase | Phase 2 |
| Files | `screens/Garage.html` · `png/Garage.png` |

**Purpose.** Permanent vehicle upgrades bought with JENEHAT, shown on a big preview of the player's vehicle. A second tab holds cosmetics bought with BONAT.

**Layout, top to bottom.** Padding 36/16/24, gap 12.

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 1 | `ScreenHeader` | y36 h52 | Back. Title «الجراج». Trailing `CurrencyPill` coins (h40, `coin_plain` 22, «١٬٢٤٠» 15/700, lip 4) | `display.m` (26), `lip.card.small` |
| 2 | Vehicle preview | y100 h210, radius 26, lip 6 `ground.lip` | `VehicleSprite` for the current vehicle with its cosmetics, on a garage backdrop (`illustrations/screens/Garage_01.svg`: wall **non-token #C9C0E6** with #BDB3DD stripes, floor **non-token #8A84A0**). Name chip at top 12 / right 12: `paper` pill, 12/700 | `radius.scene`, `lip.card.big` |
| 3 | Tabs | y322 h56 | `Segmented` primary inside a `paper` track (padding 4, radius 16, lip 4). Tabs h48, radius 12. Active: `primary` with white 14/700. Inactive: `ink.2` 14/600 | `primary`, `lip.card.small` |
| 4 | Upgrades grid | y390 h430 | 2×2 grid, gap 10. Cards 174×210, radius 22, lip 5, padding 12, gap 6. Top row: upgrade icon 34 (`upgrade_drawer`, `upgrade_cassette`, `upgrade_mirror`, `upgrade_folding_seat`) with a level chip («مستوى ١/٣», 12/700, `ground` pill) at the end. Name 15/700. Effect 12/500 `ink.2`, line-height 1.5. Price button at the bottom (`margin-top:auto`), h44, radius 14, 14/700 «{price} ج» | `paper`, `lip.card`, `radius.card` |
| 4a | Price button · highlighted | 150×44 | `AppButton` primary m: `primary`, lip 4 `primary.lip`, white | `lip.primary.s` |
| 4b | Price button · plain | 150×44 | `ground` fill, `ink`, no lip | `ground` |

**Dynamic data.**
- The JENEHAT balance comes from `wallet.jenehat`.
- The vehicle name and preview come from the selected owned vehicle (`ownership` vehicles + content `vehicles[]`).
- Upgrade name, effect text, max level and price per level come from the content pack (vehicle upgrades + catalog prices).
- The current level comes from `ownership` (kind `upgrade`).
- Static: title, tab labels.

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| Back | tap | Pops to the previous route (`/home` or `/shop`). |
| Tabs | tap | Switch panels. The «الزينة · بالبونات» panel isn't drawn. |
| Price button | tap | Buy the next level: `spend_jenehat {sku_kind: upgrade}`. The level chip increments and the preview reacts. |
| Cosmetic item (UX) | tap | Try it on the `VehicleSprite` right away; a horn plays its sound (UX). Not drawn. |

**States & edge cases.**
- **Not enough JENEHAT:** not drawn. Proposal, matching `BuyVehicle` and `Piece`: show «ناقصك {n}» in the button instead of the price.
- **Max level:** not drawn. Proposal: a `StatusChip` «آخر مستوى» in place of the button.
- **Only the tuk-tuk** (no owned vehicle): Garage should be unreachable. It is Phase 2 and comes after the microbus purchase.
- **Long effect text:** at most 3 lines, then ellipsis. Names take 1 line.
- **Offline:** JENEHAT purchases work offline (§11).

**Motion.** Tabs: the active pill slides (`press` timing). Buy: `press`, the coins pill counts down, and the preview plays a short upgrade flourish on the `VehicleSprite`.

**Accessibility.**
- Labels from the HTML: back «رجوع», tablist «الجراج» with `role=tab` / `aria-selected`.
- Each card reads as: name, level, effect, price button «اشتري {name} بـ{price} جنيه».
- Reading order: header → preview name → tabs → cards in RTL order.

**Strings.**
```
garage.back: "رجوع"
garage.title: "الجراج"
garage.tabUpgrades: "الترقيات · بالجنيهات"
garage.tabCosmetics: "الزينة · بالبونات"
garage.level: "مستوى {level}/{max}"
garage.price: "{price} ج"
```
Upgrade names and effects are content. Samples: «درج أوسع» / «المشوار يبدأ بنص جنيه وجنيه زيادة», «كاسيت» / «المزيكا بتهدّي الركاب، فصبرهم يخلص أبطأ», «مراية كبيرة» / «تلمّح مين فعلًا دفع», «كرسي قلّاب» / «كرسي زيادة: أجرة أكتر وسلسلة أطول».

**Notes.**
- **Price button styling is ambiguous.** Only «٨٠٠ ج» is primary. «١٬٢٠٠ ج» is plain, yet the player can afford it with a balance of ١٬٢٤٠. A rule is needed: affordable vs not affordable, or "recommended".
- **Not drawn:** the cosmetics tab, purchase confirmation for JENEHAT upgrades, and max level.
- **Non-token colours:** the backdrop colours.

---

#### عرض باقة البداية — `Starter`

| | |
| --- | --- |
| Route | `/shop/starter` **(new route)** (dialog over the current route, shown once) |
| Feature folder | `features/shop/` |
| Phase | Phase 2 |
| Files | `screens/Starter.html` · `png/Starter.png` |

**Purpose.** A one-time starter-pack offer shown at the happy moment after chapter 1. After that it stays at the top of the Shop until day 7 since install.

**Layout, top to bottom.**

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 0 | `Scrim` | full screen | rgba(29,26,43,.70) | **non-token** (the `scrim` token is .60) |
| 1 | `AppDialog` | x16 y90 w358 h645, radius 28, clips its children | Lip 6, **non-token** rgba(0,0,0,.25) | `paper`, `radius.sheet` |
| 2 | Art header | y90 h244 | `sun` with a `sun.glow` disc r110. Illustration `illustrations/screens/Starter_01.svg` (BONAT ticket «٣٠٠», gold curtains, unlimited-fuel badge, sparkles). Countdown pill at the bottom centre: `danger` fill with `ink` text 12/700, padding 2 10 | `sun`, `danger` |
| 3 | Title | y352 h49 | «باقة البداية», centred | `display.l` (28) |
| 4 | Subtitle | y413 h18 | Centred | `body` `ink.2` |
| 5 | Contents | y443 h142 | 3 `ListRow`s, each h42, radius 16, `ground`, padding 10 12, gap 10, 14/600. Icons 22: `bonat_alt`, `curtains`, `fuel_unlimited_alt` | `radius.m` |
| 6 | Buy CTA | y597 h64 | `AppButton` primary xl «اشتريها · [سعر المتجر]» (Marhey 23) | `lip.primary`, `radius.card` |
| 7 | Dismiss | y673 h44 | `AppButton` tertiary «مش دلوقتي» 14/600 `ink.muted` | `ink.muted` |

**Dynamic data.**
- Offer eligibility and display data come from `GET /v1/offers`: after chapter 1, until day 7 since install, not already bought.
- The countdown is the time until install + 7 days, using server time. Shape: «فاضل {d} أيام و{h} ساعة».
- The BONAT amount (sample ٣٠٠) comes from the product grants (backend open Q 10).
- The price comes from the store `product_id` `starter_pack` («[سعر المتجر]» is filled at runtime).
- The subtitle's achievement text comes from the chapter-1 goal (sample «خلّصت خط الحي»).

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| «اشتريها · …» | tap | `PurchaseGateway` `starter_pack` → `POST /v1/purchases/verify` → `PurchaseDone`. Logs `iap_view` on open and `iap_purchase` on success. |
| «مش دلوقتي», system back | tap | Close. Mark the offer as shown so it never pops up again; it stays as the Shop offer card. |
| Scrim | tap | No action (an explicit choice is needed). |

**States & edge cases.**
- **Purchase pending or failed:** see `States` (payment failed). The dialog stays open.
- **Offline:** the CTA shows the `StatusChip` «محتاج نت» and is disabled.
- **Under one day left:** not drawn. Proposal: «فاضل {h} ساعة و{m} دقيقة».
- **Store price missing:** keep the CTA disabled with no price, and never show a hardcoded price.

**Motion.** The dialog uses `dialogIn`. The sparkles twinkle (illustration Lottie, optional). Under reduced motion, everything is static.

**Accessibility.** The dialog is labelled by «باقة البداية». Read the list items in order. The countdown label is read once. Targets: CTA 322×64, dismiss 322×44.

**Strings.**
```
starter.countdown: "فاضل {d} أيام و{h} ساعة"
starter.title: "باقة البداية"
starter.subtitle: "مبروك خلّصت خط الحي! هدية مرة واحدة بس."
starter.itemBonat: "{n} بون"
starter.itemCurtains: "ستاير دهبي حصرية للعربية"
starter.itemFuel: "بنزين مفتوح ساعتين"
starter.cta: "اشتريها · {price}"
starter.dismiss: "مش دلوقتي"
```

**Notes.**
- The scrim opacity (.70) and the dialog lip are not tokens.
- There is no ✕ button; «مش دلوقتي» is the only dismiss.
- If the chapter-1 goal changes, the subtitle must come from data.

---

#### ملك الخط — `King`

| | |
| --- | --- |
| Route | `/leagues` (full screen, entered from Lines) |
| Feature folder | `features/leagues/` |
| Phase | Public launch |
| Files | `screens/King.html` · `png/King.png` |

**Purpose.** A weekly league of 30 drivers on one line. The top 5 go up, the bottom 5 go down, and the player's own row is always pinned and visible.

**Layout, top to bottom.** Padding 36/16/20, gap 10.

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 1 | `ScreenHeader` | y36 h52 | Back (→ `/lines`). Title «ملك الخط» with the sub-line «دوري الموقف · خط الجامعة» (12/600 `ink.muted`). Trailing: «بيخلص بعد» 12/600 `ink.muted` over «٢ يوم ٥ س» 14/700 | `display.m` (24) |
| 2 | Zone chips | y98 h36 | 2 equal chips, gap 8, radius 12, padding 0 10, 12/700. Promotion: **non-token #E4F2DF** with `chevron_up` 16 in **non-token #2F6B22**. Demotion: `danger.soft` with `chevron_down` `danger.ink` | `danger.soft`, `danger.ink` |
| 3 | Standings | y144 h604, scrolls | `ol`. Rows h54, gap 6, radius 16, padding 0 12, gap 10: rank, avatar 36 (`paper` circle with a face), name 14/700 over «درجة {n}» 12/500 `ink.2` (flex), points 15/700, and a trophy 22 for the top 3 | `radius.m` |
| 3a | Rank badge top 3 | 28 circle, 13/700 | 1 `gold`, 2 `dashboard.text` (#D9D4E2), 3 `character.blush` (#E9967A). Trophies: `trophy_gold`, `trophy_silver`, bronze (= `trophy_silver` tinted #E9967A) | |
| 3b | Rank plain | w28, 14/700 centred | Ranks 4 and below | |
| 3c | Row background | — | Ranks 1–5: promotion green (non-token). Middle: `paper` (avatar disc `ground`). Ranks 26–30: `danger.soft` | |
| 3d | Gap marker | h20 | «· · ·» 16/700, `aria-hidden` | `icon.off` (see Notes) |
| 4 | Pinned «ترتيبك» | y758 h66, radius 20, padding 0 12 | `primary`, lip 5 `primary.lip`. Rank in Marhey 20 white (w32). Avatar 42 on a `sun` circle. «انت · {name}» 15/700. Sub-line 12/500 `primary.soft`. Points 16/700 | `lip.primary.m` |

**Dynamic data.**
- From `GET /v1/leagues/current`: league tier name («دوري الموقف»), the next tier for the chip («دوري الحي»), line name, end time (shown as «{d} يوم {h} س»), the 30 members (rank, display name, driver level, avatar, points), the player's rank and points, and top-3 rewards.
- «فاضلك {n} نقطة للمركز الخامس» is computed as the points of rank 5 minus the player's points.
- Zone sizes (5 / 5) come from the league config.

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| Back | tap | Pops back to `/lines`. |
| Standings | scroll | The list scrolls. Row 4 stays pinned. |
| Rows, pinned row | — | Not interactive in the design. |

**States & edge cases.**
- **Offline:** leagues need the network. Show the offline pattern; on Lines the entry shows «محتاج نت».
- **Loading:** use the `States` loader in the list area.
- **Player inside the list viewport:** not drawn. Proposal: also highlight their list row with the `ring.selected` inset.
- **Player in the promotion zone:** the sub-line copy isn't drawn. Proposal: «انت في منطقة الصعود».
- **Player in the demotion zone:** the sub-line copy isn't drawn either.
- **Week rollover** (`league_rollover`): the result screen isn't drawn.
- **Flagged players** are excluded server-side.
- **Long names:** 1 line with an ellipsis. Points never truncate. The rank is at most 2 digits (max 30).

**Motion.** Rows fade in with a stagger (≤150 ms each). The pinned row is static. Rank changes are not animated (not specified).

**Accessibility.**
- Labels from the HTML: back «رجوع». The pinned row is labelled «ترتيبك».
- Each row reads «المركز {rank}، {name}، درجة {n}، {points} نقطة», plus «منطقة الصعود» or «منطقة النزول».
- The gap marker is `aria-hidden`.
- Reading order: header → chips → list → pinned row.

**Strings.**
```
king.back: "رجوع"
king.title: "ملك الخط"
king.subtitle: "{league} · {line}"
king.endsIn: "بيخلص بعد"
king.endsInValue: "{d} يوم {h} س"
king.promote: "أول {n} يطلعوا {nextLeague}"
king.demote: "آخر {n} ينزلوا"
king.level: "درجة {n}"
king.you: "انت · {name}"
king.toRank: "فاضلك {pts} نقطة للمركز الخامس"
king.a11yYourRank: "ترتيبك"
```

**Notes.**
- The promotion chip copy wraps to 2 lines inside the fixed 36-px chip. Let the chip grow, or shorten the copy.
- The promotion green (#E4F2DF, #2F6B22) needs tokens.
- UX says the top 3 show their BONAT and cosmetic rewards; the rows only show trophies. Avatars for ranks 4 and below are drawn as blank circles; confirm that real avatars appear.
- «· · ·» uses `icon.off` as a text colour, which `color_rules` forbids (it is `aria-hidden`, but still).
- Product spec gates leagues by driver level; there is no locked state.
- «للمركز الخامس» uses an ordinal word. If zone sizes come from config, this string needs an ordinal list.

---

#### المناسبة وتذكرة الموسم — `Event`

| | |
| --- | --- |
| Route | `/events/:seasonKey` (full screen, scrolls; the artboard is 1200 tall and the content ends at y920). Opened from the Home `DailyCircle` «مناسبة {name}». |
| Feature folder | `features/events/` |
| Phase | Public launch |
| Files | `screens/Event.html` · `png/Event.png` |

**Purpose.** The landing page for a seasonal event (Ramadan here). It shows the event's rules, a play button for the event line, and the two-track season pass: free at the bottom, paid on top.

**Layout, top to bottom.** One vertical scroll. Padding 36/16/24, gap 14.

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 1 | `ScreenHeader` | y36 h52 | Back. Title «رمضان في الموقف». Trailing: «بيخلص بعد» 12/600 `ink.muted` over «١٢ يوم» 14/700 | `display.m` (24) |
| 2 | Hero | y102 h260, radius 26, lip 6 **non-token #2A2050** | Background `station[1].bg` #3B2A6B. Art `illustrations/screens/Event_01.svg`: night sky, crescent, lantern string, and the microbus with event cosmetics on the road (ideally a `VehicleSprite`). Event-mechanic chip at top 12 / right 12: `paper` pill h32, padding 0 12, `clock` 16 + 13/700 | `radius.scene` |
| 3 | Rule chips | y376 h52 (wraps) | Wrap row, gap 6. Pills 12/700, padding 4 10: rules on `paper`, the cosmetic reward on `sun.soft` | `label` w700 |
| 4 | Play CTA | y442 h64 | `AppButton` primary xl «العب خط المناسبة» (Marhey 24) with a `sun` pill «−١ لتر» (h28, 13/700) | `button.xl`, `lip.primary` |
| 5 | Season pass `AppCard` | y520 h400, radius 26, lip 6, padding 16, gap 14 | | `paper`, `lip.card.big` |
| 5a | Pass header | y536 h38 | «تذكرة الموسم» (`display.m` 22) + `StatusChip` (`ground` fill) «٣٢٠ نقطة · الخطوة ٤» 13/700 | |
| 5b | Paid track | y588: label h16 + cells y610 h72 | `star_ink` (gold) + «المسار المدفوع» 13/700. 5 cells 60×72, gap 6, radius 16, `sun.soft`: reward icon 26 + label 12/700, `lock` 14 `ink.muted` at top 4 / left 4. The current step's cell has a 3-px inset `gold` ring | `sun.soft`, `gold` |
| 5c | Step rail | y696 h26 | Track 4 px `track` from 10 % to 90 %. Fill `primary` from the start (right) up to the current step. Nodes 26: done = `primary` with white 12/700. Current = 30 `sun` with a 4-px `primary.soft` ring, 13/700. Future = `track` with `ink` | `primary`, `sun`, `track` |
| 5d | Free track | y736: label h16 + cells y758 h72 | «المسار المجاني» 13/700. Cells: claimed = `primary.soft` with `check` 20 `primary` + label. Claimable = a button with `primary` fill, lip 4 `primary.lip`, a gift glyph 22 and white 12/700 «خد الستيكر». Future = `ground` with `ink.2` label and the icon in a muted tint | `primary.soft`, `lip.primary.s` |
| 5e | Pass CTA | y844 h60 | `AppButton` sun l «افتح المسار المدفوع · [سعر المتجر]» (Marhey 20, radius 20, lip 5 `sun.lip`) | `button.l`, `sun` |

**Dynamic data.**
- From `GET /v1/events/active` (`Season`): title, end time, theme art and cosmetics, the event-mechanic chip (Ramadan: «المغرب بعد {h:mm}», the countdown to iftar time), the rule chips, the event line or trip id, pass points, current step, and both reward tracks (icon, amount or name per step).
- Claimed and claimable state per step comes from the player's grants.
- Pass ownership comes from `entitlements.season_passes` and product `season_pass_<season_key>`. The price comes from the store.
- Static: «تذكرة الموسم», track labels, CTA verbs.

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| Back | tap | Pops back to `/home`. |
| «العب خط المناسبة» | tap | Opens `/home/pre-trip/:tripId` for the next event-line trip (−1 fuel; fuel at 0 opens `/shop/fuel`). |
| Claimable free cell | tap | Grants the reward (`season_reward`). The cell becomes claimed and the item flies to its pill or garage. |
| Locked paid cell | tap | Proposal: scroll to the pass CTA, or nothing. Not specified. |
| «افتح المسار المدفوع» | tap | `PurchaseGateway` `season_pass_<season_key>` → verify → paid cells unlock. On failure, show `States` payment failed. |

**States & edge cases.**
- **Pass owned:** not drawn. The paid cells lose the lock and get claim buttons like the free track, and the CTA is hidden.
- **More than 5 steps:** not drawn. UX describes the tracks as horizontal, so proposal: the paid row, rail and free row scroll horizontally together, auto-scrolled to the current step.
- **Event over:** the Home circle disappears. If the screen is open, show the final state (not drawn).
- **Offline:** the play button works if the event line is downloaded. Claims and purchases need the network.
- **Long reward labels** in 60-wide cells: at most 2 lines at 12 px, ellipsis, and keep clear of the lock glyph (see Notes).
- **Long event title:** 1 line with an ellipsis.

**Motion.** The current rail node pulses gently (proposal: `hotTagPulse` timing, scale ≤1.06). Claim uses `press`, then the reward flies. The hero lanterns sway (optional Lottie; static under reduced motion).

**Accessibility.**
- The back button is labelled «رجوع». The pass section is labelled by «تذكرة الموسم».
- Each cell reads «الخطوة {n}، {reward}، {مقفولة|اتاخدت|جاهزة}».
- The rail reads as a progressbar «الخطوة {n} من {total}».
- Reading order: header → hero chip → rules → play → pass header → paid → rail → free → CTA.
- The paid cells (60×72) are larger than 44.

**Strings.**
```
event.back: "رجوع"
event.endsIn: "بيخلص بعد"
event.endsInDays: "{n} يوم"
event.play: "العب خط المناسبة"
event.fuelCost: "−{n} لتر"
event.passTitle: "تذكرة الموسم"
event.passProgress: "{pts} نقطة · الخطوة {n}"
event.paidTrack: "المسار المدفوع"
event.freeTrack: "المسار المجاني"
event.claimSticker: "خد الستيكر"
event.unlockPaid: "افتح المسار المدفوع · {price}"
```
Event-specific copy is season data. Samples: «رمضان في الموقف», «المغرب بعد ٠:٤٢», «الكل عايز يلحق الفطار», «صبر أقل», «بقشيش أكتر», «زينة رمضان للعربية», and the cell labels «فانوس», «بنزين ساعة», «بوية رمضان», «كيس فكة», «{n} بون».

**Notes.**
- **Locked paid cells** use `sun.soft` plus a lock glyph instead of the locked rule (`locked.bg` + 2-px `outline` ring + `ink.2` text). Is this a deliberate premium tease, or should it follow the rule?
- **Overflowing labels:** «بوية رمضان» and «بنزين ساعة» wrap and overlap the lock icon in the 60-px cells.
- **Pass points:** how players earn them isn't specified (backend `Season.reward_track` only).
- **Plural:** the free cell «١٠ بون» conflicts with Daily's «١٠ بونات».
- **Non-token colour:** the hero lip #2A2050. The future free cell's icon tint (#7CA7D8) should use `icon.off`.
- **Fuel badge copy:** «−١ لتر» here vs «−١» on Home and PreTrip. Unify.

---

#### ادعي صاحبك — `Invite`

| | |
| --- | --- |
| Route | `/settings/referral` (full screen) |
| Feature folder | `features/settings/` |
| Phase | Public launch |
| Files | `screens/Invite.html` · `png/Invite.png` |

**Purpose.** The player shares a personal code. When a friend finishes خط الحي, both get BONAT. The screen also lists the friends who joined and how far along each one is.

**Layout, top to bottom.** Padding 36/16/24, gap 14.

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 1 | `ScreenHeader` | y36 h52 | Back (→ `/settings`) + «ادعي صاحبك» | `display.m` (26) |
| 2 | Hero card | y102 h318, radius 26, padding 18, gap 12, centred | `sun` with lip 6 `sun.lip`. Illustration `illustrations/screens/Invite_01.svg` 150×80 (two drivers + a star). Headline Marhey 20 with line-height 1.4 (2 lines) | `sun`, `radius.scene` |
| 2a | Code row | y280 h52, gap 8 | Code field (flex, `paper`, radius 16, 20/700, letter-spacing 2, LTR) + copy button 52×52 (`paper`, radius 16, `copy` 22) | `paper`, `radius.m` |
| 2b | Share | y344 h58 | `AppButton` primary l «شارك» with `share` 22 white (Marhey 21, radius 20, lip 5) | `button.l`, `lip.primary.m` |
| 3 | Section title | y434 h18 | «صحابك اللي دخلوا» 14/700, padding 0 4 | `body` w700 `ink.2` |
| 4 | Friend row · finished | y460 h70, radius 20, padding 0 12, gap 12 | `ListRow` card with lip 5: avatar 44 (`primary.soft` placeholder), name 15/700, status 12/600 `primary` «خلّص خط الحي», `AppButton` primary m «خد ٥٠ بون» (h44, radius 14, lip 4) | `paper`, `lip.card`, `radius.l` |
| 5 | Friend row · in progress | y538 h70 | Avatar 44 (`sun.soft`). Name 15/700 with «المشوار ٨ من ٢٠» 12/600 `ink.muted` at the end. `ProgressBar` primary h8 on a `track` background | `track`, `primary` |

**Dynamic data.**
- From `GET /v1/referrals/me`: the player's code (sample `AHMD-7K2Q`), and the referees with display name, avatar, progress on `line_hay` (`n` of 20 trips) and reward state (pending, claimable, claimed).
- The reward amount (sample ٥٠ بون) comes from config. The product spec doesn't give a number.
- The goal line («خط الحي») and its trip count come from content (`line_hay`, 20 trips).

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| Back | tap | Pops back to `/settings`. |
| Copy «انسخ الكود» | tap | Copies the code to the clipboard. The feedback isn't drawn (proposal: an `UndoToast`-style status toast without an action). |
| «شارك» | tap | `share_plus` with a share text and link containing the code. The text isn't specified. Logs analytics `share` with `kind=referral`. |
| «خد ٥٠ بون» | tap | Claims the referral reward (ledger `referral_reward`). The row switches to claimed (not drawn). |

**States & edge cases.**
- **No friends yet:** the `States` empty pattern replaces rows 3–5: «لسه ما دعيتش حد. ابعت كودك لصاحبك.» + «ابعت الكود» (= share).
- **Offline:** the code shows from cache. Share still works. The claim needs the network.
- **Many friends:** the list scrolls under the hero. There is no cap in the design.
- **Long friend names:** 1 line with an ellipsis. The code never wraps; it is a monospace-like LTR isolate.

**Motion.** `press` on the buttons. Claim: the BONAT flies to the pill. The progress bar fills from the start side.

**Accessibility.**
- Labels from the HTML: back «رجوع», copy «انسخ الكود».
- The code is read character by character with an LTR isolate.
- Friend rows read «{name}، {status}».
- Announce "copied" and claims politely.
- Reading order: headline → code → copy → share → friends.

**Strings.**
```
invite.back: "رجوع"
invite.title: "ادعي صاحبك"
invite.headline: "ابعت لصاحبك، ولما يخلّص خط الحي تاخدوا {n} بون انتو الاتنين"
invite.copy: "انسخ الكود"
invite.share: "شارك"
invite.friendsTitle: "صحابك اللي دخلوا"
invite.friendDone: "خلّص خط الحي"
invite.claim: "خد {n} بون"
invite.friendProgress: "المشوار {n} من {total}"
```

**Notes.**
- The invited friend has nowhere to enter a code (`POST /v1/referrals/redeem`); it isn't drawn.
- UX places Invite cards in both Settings and Shop. Neither entry is drawn.
- The copy button is a 52 square with radius 16, not the 44 circle of `IconCircleButton`. The hero lip uses `sun.lip` at 6 px (the `lip.sun` token is 4).

### Screens: states added during handoff

These four artboards were drawn after the per-screen review found them missing. Same template as above.

#### الشقة: الهدف جاهز — `AptGoalReady`

| | |
| --- | --- |
| Route | `/apartment` (state of `AptGoal` when the balance covers the chapter goal) |
| Feature folder | `features/apartment/` |
| Phase | MVP (chapters 1–3) |
| Files | `screens/AptGoalReady.html` · `png/AptGoalReady.png` |

**Purpose.** The moment the player can afford the chapter's goal (here: the ring «الشبكة», chapter 3). Buying it plays the chapter's scene.

**Layout, top to bottom.** Identical to `AptGoal` except:

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 1 | Header pill | h 40 | `CurrencyPill(coins)` shows the balance (sample ٦٬٢٤٠) | as AptGoal |
| 2 | Goal amount line | — | «جاهزة!» chip (12/700, `station[2]` green fill, ink text, radius 999) before «٦٬٠٠٠ / ٦٬٠٠٠ ج» | `station[2]`, `ink` |
| 3 | Progress | h 14 | `ProgressBar(gold)` at 100% | `gold`, `track` |
| 4 | Quote | — | أم العروسة: «يعني جاهز؟ وريني بقى ذوقك يا ابني» | `quote` |
| 5 | **CTA (new)** | h 64, below the goal card | `AppButton.primary(xl)` «اشتري الشبكة» + sun chip «−٦٬٠٠٠ ج» (h 32, 14/700) | `primary`, `lip.primary`, `sun` |
| 6 | Locked apartment teaser | flex | unchanged, shrinks to fit | `outline` ring |

**Dynamic data.** Goal name, price and art from the chapter content; balance from the wallet. The CTA price chip = goal price.

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| «اشتري الشبكة» | tap | spends the price (wallet ledger `chapter_goal`), marks the chapter done, opens `/story/:chapterId` (`SceneViewer`) on its first panel |
| chapter bar | tap | `/apartment/chapters` |

**States & edge cases.** Shown only while `balance >= goalPrice` and the goal isn't bought. Offline: buying works offline (local wallet) and syncs later. Chapter 1–2 goals (tuktuk key, old microbus) use the same layout with their own art; chapter 2's goal is bought through `BuyVehicle`, so its CTA opens that sheet instead.

**Motion.** `ui/ring_shine` loops on the goal art; on buy: `ui/coins_burst` from the CTA, then the route change.

**Accessibility.** CTA label «اشتري الشبكة بستة آلاف جنيه». Announce «الشبكة جاهزة» when the screen opens in this state.

**Strings.**
- `apartment.goalReady: "جاهزة!"`
- `apartment.buyGoal: "اشتري {goal}"`
- `apartment.goalReadyQuote.ch3: "«يعني جاهز؟ وريني بقى ذوقك يا ابني»"`

#### الغرفة خلصت — `RoomDone`

| | |
| --- | --- |
| Route | dialog over `/apartment`, pushed by the purchase flow when a room's last item is bought (no own route) |
| Feature folder | `features/apartment/` |
| Phase | MVP (chapter 4 on) |
| Files | `screens/RoomDone.html` · `png/RoomDone.png` |

**Purpose.** Short celebration for finishing a room, the BONAT reward, and the way into the chapter scene (UX «إكمال الغرفة»).

**Layout, top to bottom.** `Scrim` (`scrim`) over the dimmed Apartment screen; `AppDialog` at x 16–374, top 168, radius 26, padding 20 18 18, lip `lip.dialog`, items centred with gap 12:

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 1 | Room art | 260×130 | the finished room (from content) inside confetti and sparkles | `scene.room`, `scene.floor` |
| 2 | Chapter chip | h ~22 | «الفصل ٤ · ٤ من ٤ قطع» 13/700 | `primary.soft`, `primary` |
| 3 | Title | 30 | «الصالة خلصت!» Marhey 700 30 | `ink` |
| 4 | Reward pill | h 40 | bonat icon + «+٥٠ بون مكافأة» 16/700 | `sun.soft`, `lip.sun.soft` |
| 5 | Quote card | — | Salma avatar 46 + «تحفة يا أسطى! ماما هتفرح أوي يوم الخميس» (`quote`) + «سلمى» (12/600 `ink.muted`) | `ground` |
| 6 | CTA | h 60 | `AppButton.primary` play icon + «شوف المشهد» (Marhey 24) | `primary` |
| 7 | Later | h 44 | `AppButton.tertiary` «بعدين» | `primary` |

**Dynamic data.** Room name and art, chapter number and piece count, reward amount (content), quote (content, per room).

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| «شوف المشهد» | tap | `/story/:chapterId` |
| «بعدين» | tap | closes; the scene stays unlocked in `Album` and the chapter bar shows «شوف المشهد» |
| scrim / back | — | same as «بعدين» (the reward is already granted) |

**States & edge cases.** Reward is granted when the dialog opens (ledger `room_complete`), not on a button. If the next room is locked behind a chapter, the Apartment screen updates its tabs after the dialog closes.

**Motion.** Dialog in (`dialogIn`), `ui/confetti` once behind the dialog, `ui/bonat_burst` from the reward pill to the header pill.

**Accessibility.** Announce «الصالة خلصت، كسبت خمسين بون». Focus starts on the CTA.

**Strings.**
- `roomDone.title: "{room} خلصت!"`
- `roomDone.chip: "الفصل {n} · {done} من {total} قطع"`
- `roomDone.reward: "+{n} بون مكافأة"`
- `roomDone.cta: "شوف المشهد"`
- `roomDone.later: "بعدين"`

#### ألبوم المشاهد — `Album`

| | |
| --- | --- |
| Route | `/story/album` **(new route)**, from «ألبوم المشاهد» in `Chapters` |
| Feature folder | `features/story/` |
| Phase | MVP |
| Files | `screens/Album.html` · `png/Album.png` |

**Purpose.** Re-watch and share every unlocked chapter scene.

**Layout, top to bottom.** Padding 36 16 20, gap 14, scrolls.

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 1 | Header | h 52 | `ScreenHeader`: back → `Chapters`, title «ألبوم المشاهد» Marhey 26, count chip «٣ من ٧» (12/700, white, radius 999) | `display.l` |
| 2 | Intro line | — | «كل مشهد بيتفتح لما تخلّص فصله. تقدر تتفرج عليه تاني وتشاركه.» 13/500 | `ink.2` |
| 3 | Grid | 2 columns, gap 12 | one card per chapter (7), in chapter order, RTL (chapter 1 top-right) | — |
| 3a | Unlocked card | ~171 wide | `AppCard` padding 8, gap 6: thumbnail h 96 radius 16 (first panel of the scene), «الفصل ١» 12/600 `ink.muted`, title Marhey 17, button h 36 radius 12 `primary.soft` «اتفرج تاني» with play icon (13/700 `primary`) | `card` |
| 3b | Locked card | same | `locked.bg` + 2 px `outline` ring, grey thumbnail with `lock_outline` icon, chapter + title in `ink.2`, line «بيتفتح لما الفصل يخلص» 12/600 | locked rule |

**Dynamic data.** Unlocked scenes from progress; titles and thumbnails from chapter content. Count chip = unlocked / total.

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| unlocked card | tap | `/story/:chapterId` (SceneViewer, starts at panel 1; «شارك» on the last panel as usual) |
| locked card | tap | nothing (no toast) |
| back | tap | `/apartment/chapters` |

**States & edge cases.** Scenes whose content isn't downloaded yet show the unlocked card with a «محتاج نت» `StatusChip` over the thumbnail and open only when online. Titles wrap to two lines.

**Accessibility.** Card labels: «الفصل ١: سلمى في الموقف، اتفرج تاني» / «الفصل ٤: زيارة أهل العروسة، لسه مقفول».

**Strings.**
- `album.title: "ألبوم المشاهد"`
- `album.count: "{n} من {total}"`
- `album.intro: "كل مشهد بيتفتح لما تخلّص فصله. تقدر تتفرج عليه تاني وتشاركه."`
- `album.watchAgain: "اتفرج تاني"`
- `album.locked: "بيتفتح لما الفصل يخلص"`
- `album.scene.ch1: "سلمى في الموقف"`, `album.scene.ch2: "«بتشتغل إيه؟»"`, `album.scene.ch3: "قراءة الفاتحة"`, `album.scene.ch4: "زيارة أهل العروسة"`, `album.scene.ch5: "أول عزومة"`, `album.scene.ch6: "كتب الكتاب"`, `album.scene.ch7: "الفرح"`

#### حذف الحساب: خطوة ١ — `DeleteStep1`

| | |
| --- | --- |
| Route | `/settings/account/delete` **(new route)**, from «حذف الحساب» in `Settings` |
| Feature folder | `features/settings/` |
| Phase | MVP |
| Files | `screens/DeleteStep1.html` · `png/DeleteStep1.png` |

**Purpose.** First of two steps (UX «حذف الحساب»): explain what deleting means and offer the safer option (linking the account) before the typed confirmation in `DeleteAccount`.

**Layout, top to bottom.** Padding 36 16 28, gap 14.

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 1 | Header | h 52 | `ScreenHeader`: back → Settings, «حذف الحساب» Marhey 26, chip «خطوة ١ من ٢» | `display.l` |
| 2 | Explainer card | — | `AppCard` (radius 26, lip `card.big`), centred: sad الأسطى (rig, frown) 120×104, title «هتسيب الموقف يا أسطى؟» Marhey 24, body 14/500 line-height 1.6 | `ink.2` |
| 3 | Link-instead card | — | `sun.soft` card radius 22, lip `lip.sun.soft`, padding 14: `info_filled` icon 26, title «بتغيّر موبايلك بس؟» 15/700, body 13/500, button h 44 radius 14 `primary` «اربط حسابك» | `sun.soft` |
| 4 | Note | — | «الفلوس اللي دفعتها في المحل ما بترجعش بالحذف. لو عندك اشتراك، الغيه من متجر جوجل الأول.» 13/500 | `ink.2` |
| 5 | Actions (bottom) | 60 + 56 | `AppButton.danger` «كمّل للحذف» (ink text, lip `danger.ink`) · `AppButton.primary` «لأ، رجّعني» | `danger`, `primary` |

**Dynamic data.** If the account is already linked, hide card 3. On iOS the note says «متجر أبل» instead of «متجر جوجل».

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| «اربط حسابك» | tap | starts Google / Apple sign-in (architecture §16); on success returns to Settings with a toast «حسابك اتربط» |
| «كمّل للحذف» | tap | `/settings/account/delete/confirm` (`DeleteAccount`) |
| «لأ، رجّعني» / back | tap | `/settings` |

**States & edge cases.** Offline: «كمّل للحذف» still works but step 2 needs the network to finish (it shows the `States` offline banner and keeps the delete button disabled).

**Accessibility.** The danger button keeps ink text (contrast). Focus starts on «لأ، رجّعني» so a blind tap doesn't advance.

**Strings.**
- `deleteAccount.step: "خطوة {n} من ٢"`
- `deleteAccount.step1Title: "هتسيب الموقف يا أسطى؟"`
- `deleteAccount.step1Body: "لو مسحت حسابك، تقدمك ومشترياتك هيتمسحوا من على موبايلك ومن عندنا، ومش هنقدر نرجّعهم تاني."`
- `deleteAccount.linkTitle: "بتغيّر موبايلك بس؟"`
- `deleteAccount.linkBody: "اربط حسابك بجوجل وتقدمك هيفضل معاك على أي موبايل، من غير ما تمسح حاجة."`
- `deleteAccount.linkCta: "اربط حسابك"`
- `deleteAccount.storeNote: "الفلوس اللي دفعتها في المحل ما بترجعش بالحذف. لو عندك اشتراك، الغيه من {store} الأول."`
- `deleteAccount.continue: "كمّل للحذف"`
- `deleteAccount.cancel: "لأ، رجّعني"`

