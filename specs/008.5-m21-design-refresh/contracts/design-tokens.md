# Contract: Design Tokens («كرتون ناعم»)

The only source of visual values in the app, generated from `docs/design/tokens.json`. Spec FR-005 –
FR-008, research R2, R3 and R21. **Supersedes** M03's
[design-tokens.md](../../001-m03-app-shell/contracts/design-tokens.md) and the `fare`, `bubble*` and
`shirt*` tokens M02 added to it.

## Generation

| Item | Value |
| --- | --- |
| Input | `docs/design/tokens.json` (read-only here; the design owner rebuilds it) |
| Tool | `apps/mobile/tool/design/gen_tokens.dart`, run as `fvm dart run tool/design/gen_tokens.dart` |
| Output | `apps/mobile/lib/core/theme/tokens/design_tokens.dart`, committed, with a "generated, do not edit" header |
| Check | `test/repo/design_tokens_test.dart`: runs the generator in memory, compares the output with the committed file, and fails on any difference with the command to run |
| Determinism | Keys are emitted in file order, numbers as written, colours as `Color(0xAARRGGBB)`; `dart format` is applied to the output |

## Names

Dotted keys become camelCase, with the group as the class:

| `tokens.json` | Dart |
| --- | --- |
| `color.primary.lip` | `ColorTokens.primaryLip` |
| `color.ink.2` | `ColorTokens.ink2` |
| `dashboard.raised` | `ColorTokens.dashboardRaised` |
| `money_note.fare` | `ColorTokens.noteFare` (fill), `ColorTokens.noteFareLip` |
| `denomination.0.5`, `denomination.200` | `ColorTokens.denom050`, `ColorTokens.denom200` |
| `scene.seat.hi` | `ColorTokens.sceneSeatHi` |
| `character.skin[2]` | `ColorTokens.characterSkin[2]` |
| `station[i]` | `StationColors.all[i]`: `(bg, letter)` |
| `type.display.l` | `TypeTokens.displayL` |
| `radius.card` | `RadiusTokens.card` |
| `lip.primary.m` | `LipTokens.primaryM` (a `BoxShadow`), `LipTokens.primaryMDepth` (its y) |
| `ring.hot` | `RingTokens.hot` (`width`, `color`, `inside`, `dashed`) |
| `space.12` | `SpaceTokens.s12` |
| `layout.trip.faces.near` | `LayoutTokens.tripNear` (`r`, `scale`, `y`, `x`, `tag`) |
| `motion.sheetIn` | `MotionTokens.sheetIn` (`Duration`), `MotionTokens.sheetInCurve` |

A key with a range or a note (such as `display.m` "22–26 (24)") uses its bracketed value. The
generator fails on a value it can't read, naming the key, so a design change never passes silently.

## Text styles

- Each `TypeTokens` style sets `fontFamily` (`Marhey` or `ReadexPro`), `fontWeight`, `fontSize`,
  `height` (the line height), and `leadingDistribution: TextLeadingDistribution.even`.
- Colour is not part of a type token: widgets pick it from `ColorTokens`.
- `label` (12) is the smallest size anywhere. A test fails on any token under 12.

## Theme

- `app_theme.dart` builds `ThemeData` from the tokens:
  - `scaffoldBackgroundColor: ground`;
  - `splashFactory: NoSplash.splashFactory`, with highlight and hover colours transparent;
  - `textTheme` mapped from `TypeTokens`;
  - `extensions: [WassalTokens.standard]`.
- Light and dark brightness get the same theme (M03 FR-009).
- `WassalTokens` is generated too: one field per colour, `stations`, and `lerp`. Widgets read
  `context.tokens`.

## Not generated

| Key | Why |
| --- | --- |
| `motion.moneyHop` | The engine's `trip_hop_ms_<line_id>` tunables decide hop times (constitution VIII). |
| `digits` | `NumberFormatter` (M03) owns digits and separators. |
| `font` | The families are registered in `pubspec.yaml`. |
| `*_rules`, `*_note`, `$schema_note`, `use` fields | Documentation. `station_rules` is overridden by spec FR-009 (alighting order). |

## Extras

`lib/core/theme/tokens/design_extras.dart` holds the values an artboard uses between tokens, in
`abstract final class DesignExtras`. It is hand-written, and each constant has a comment naming its
artboard and element. Among them:

- `loadingWordmark` (Marhey 700 60) and its `sun.lip` shadow;
- `pauseButtonLabel` (23), `failTitle` (30), `hudTitle` (Marhey 700 18 on a 1.1 line);
- `dialogRadius` (26) and `dialogPadding` (18);
- `bannerTitle` (Marhey 700 17);
- `minTopInset` (24, HANDOFF §2.4);
- the labels and sizes the `Components` board draws between tokens (the compact 14/700 label, the
  pill numbers, chips, segments, tabs, the sheet title, station-tag letters, bubble padding, notes).

The bubble and popover lips and the coach scrim are tokens (`lip.bubble`, `lip.bubble.warn`,
`lip.popover`, `color.scrim.coach`), so they aren't extras. `TextStyleWeight.weight(n)` sets a
style's weight both ways, for the type tokens' alternative weights (`row` at 700, a segment at 700).

The list grows only from the artboards' HTML. A new screen adds its own in its feature.

## Fonts

| Family | File | Weights used | Licence |
| --- | --- | --- | --- |
| `Marhey` | `assets/fonts/Marhey-VariableFont_wght.ttf` | 500, 600, 700 | `assets/fonts/OFL-Marhey.txt` |
| `ReadexPro` | `assets/fonts/ReadexPro-VariableFont_HEXP_wght.ttf` | 400, 500, 600, 700 | `assets/fonts/OFL-ReadexPro.txt` |

Both files come from `github.com/google/fonts` (`ofl/marhey`, `ofl/readexpro`), at the commit recorded
in the PR. Their licence files sit beside them, as M03's fonts' do.

## Palette checks

`test/core/theme/design_palette_test.dart` (research R21). Each row must hold for every pair:

| Text | On | Minimum |
| --- | --- | --- |
| `ink`, `ink2`, `inkMuted` | `paper`, `ground`, `lockedBg`, `track` | 4.5:1 |
| white | `primary`, `primaryLip`, `dashboardBg`, `station[0]`, `station[1]` | 4.5:1 |
| `ink` | `sun`, `sunSoft`, `danger`, `dangerSoft`, `primarySoft`, `station[2]`, `station[3]` | 4.5:1 |
| `primary` | `primarySoft`, `paper` | 4.5:1 |
| `dangerInk` | `paper` | 4.5:1 |
| `dashboardText`, `dashboardMuted` | `dashboardBg`, `dashboardRaised` | 4.5:1 |
| each note's digits | its `money_note` fill | 4.5:1 |
| Marhey ≥ 18 bold | its background | 3:1 |

And:

- `dangerInk` on `dangerSoft` is only 4.1:1, so no text uses that pair (no artboard does); on
  `dangerSoft`, text is `ink`;
- the four station colours, pairwise at least 18 L* apart, and `primary` against `danger`
  (colour-blind separation, M03);
- a scan of `lib/core/theme/components/` and `lib/features/trip/presentation/` finds no white text on
  `danger` or `sun`.

M02's shirt-pair check is removed with the shirts (research R14).
