# docs/design/brand: the app icon and the logo

A snapshot of the design canvas's brand page («العلامة والأيقونة»), added to 008.5 (M21) as tasks
T129–T131. The app's launcher icons are generated from these files (T130). Change them on the canvas
first, then snapshot them here again.

## Files

| File | What it is |
| --- | --- |
| `IconOptions.html` | The three directions the canvas explored: أ the microbus, ب the change, ج the letter و |
| `IconKit.html` | Direction أ in every form the stores and the systems ask for (below) |
| `Logo.html` | The logo: the mark and the wordmark «وصّل الأجرة», its lockups and its rules |
| `FeatureGraphic.html` | Google Play's 1024×500 feature graphic, with the tagline «لمّ الأجرة صح، والباقي يرجع لصاحبه» |
| `icon_master.svg` | The master icon, 1024×1024, opaque, square corners: iOS and the stores round them. It is also the logo's mark in colour. |
| `adaptive_background.svg` | Android's background layer, 108 dp |
| `adaptive_foreground.svg` | Android's foreground layer, 108 dp, the drawing inside the 66 dp safe circle (the canvas's guides removed) |
| `monochrome.svg` | Android 13's themed icon: one colour on transparent |
| `mark_mono.svg` | The logo's mark in one colour (`ink`), for print and stamps |
| `notification.svg` | The notification glyph: the letter و, white on transparent, 24 dp. The push feature (M14) wires it. |
| `store_icon_512.png` | Google Play's listing icon, 512×512, opaque: written by `apps/mobile/tool/design/gen_launcher_icons.sh` with the launcher icons |
| `feature_graphic_1024x500.png` | `FeatureGraphic.html` rendered at 1024×500 for the Play listing: `chromium --headless=new --hide-scrollbars --force-device-scale-factor=1 --window-size=1024,500 --virtual-time-budget=5000 --screenshot=feature_graphic_1024x500.png "file://$PWD/FeatureGraphic.html"` |

The HTML pages use the design's fonts through `../screens/fonts.css`. Open them at their own width.

## The icon: direction أ

The microbus. It is the chosen direction; ب and ج stay in `IconOptions.html` for the record.

| Where | What |
| --- | --- |
| App Store and iOS | `icon_master.svg` at 1024×1024, PNG, no transparency, no rounded corners. iOS rounds them. |
| Google Play | 512×512 from the master. Play rounds the corners. |
| Android launcher | the adaptive icon: background, foreground and monochrome layers. Check it as a circle, a squircle and a rounded square. |
| Small sizes | the kit shows it at 120, 87, 60 and 40 |

The app's icons are written from these files by `apps/mobile/tool/design/gen_launcher_icons.sh`
(Android's legacy icon and adaptive layers per density, every iOS size, opaque), and
`apps/mobile/test/repo/launcher_icons_test.dart` checks them. Run it again after a change here.

## The logo

The mark and the wordmark «وصّل الأجرة», in four lockups: on white, on the blue (`primary`), on the
dark (`dashboard.bg`), and in one colour for print, stamps and faxes.

- **Clear space.** Call half the mark's width «س». Leave at least «س» empty around the logo on every
  side.
- **Smallest sizes.** The mark at 32 px, the wordmark at 20 px high. Smaller than that, use the mark
  alone.
- **Don't:**
  - stretch or squeeze the wordmark;
  - outline the letters in black;
  - set the wordmark in any font but Marhey;
  - change its colours.
