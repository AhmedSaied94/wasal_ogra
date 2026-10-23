# Contract: Shared Components

The component set of HANDOFF §3, built once (spec FR-010 – FR-013, research R4). Sizes, fills, lips
and type are HANDOFF §3's and the `Components` artboard's, and they are not repeated here. This page
fixes what the code promises: where each component lives, its variants and states, and how it behaves.

## Rules for every component

- **Values.** Only tokens and `design_extras.dart`. M03's raw-value guard covers
  `lib/core/theme/components/`.
- **Taps.** Every tappable is a `Pressable` (`lib/core/theme/components/pressable.dart`):
  - press: translate down by the lip, lip to 0, `MotionTokens.press` (80 ms ease-out), then
    `Haptics.selection()` unless vibration is off;
  - release: reverse;
  - disabled: 45% opacity, no lip, no press, `Semantics(enabled: false)`;
  - the hit area is at least 44×44 even when the drawing is smaller (a `CountBadge`, a chip).

  No `InkWell`, `InkResponse` or Material button anywhere in `lib/`. A repo test checks it, and its
  allow-list is empty.
- **Semantics.** Every tappable takes a `semanticLabel`. Screens pass the artboard's `aria-label`
  text from the ARB file. The layout tests find controls by it ([design-checks.md](./design-checks.md)).
- **Direction.** Built with `EdgeInsetsDirectional`, `AlignmentDirectional` and
  `PositionedDirectional`. Children are in the HTML's order (HANDOFF §2.5).
- **Numbers.** Every number arrives formatted (`NumberFormatter`). Components take `String`s for
  amounts, never `int` or `double`.
- **Text.** Long text: a title ellipsizes on one line; chips, banners and cells wrap to two centred
  lines (HANDOFF §9.1 #10).
- **Reduced motion.** Components read `MediaQuery.disableAnimations` (M02 R19's flag): no pop, pulse,
  shake or entrance, and fades of at most 150 ms.

## The set

`lib/core/theme/components/`:

| File | Component | Variants and states |
| --- | --- | --- |
| `pressable.dart` | `Pressable` | lip depth, enabled, `onTap`, `semanticLabel` |
| `buttons.dart` | `AppButton` | `primary(size: xl \| l)`, `secondary`, `sun`, `danger`, `tertiary`; default, pressed, disabled, loading; optional trailing cost chip (`CostChip`, the sun pill with «−١» and the fuel icon) |
| | `RewardedAdButton` | ready, not ready («الإعلان مش جاهز»). Built and in the gallery; no screen shows it until M11 (spec FR-029) |
| | `IconCircleButton` | on `ground` (white, lip) or in a sheet (`ground` fill); icons `close`, `back`, `pause`, `edit`, `copy` |
| `pills.dart` | `CurrencyPill` | `coin`, `bonat`, `fuel` (with the timer line; empty = `danger.soft`); 44 or 40 tall |
| | `CountBadge`, `NewDot`, `PriceTag`, `Stars` (0–3 earned) | |
| | `StatusChip` | `new`, `story`, `done`, `offline` |
| `controls.dart` | `AppSwitch` | on, off, disabled; the whole row toggles |
| | `Segmented` | `sun` or `primary` active style; 2–4 segments |
| | `AppTextField` | idle, focused |
| `containers.dart` | `AppCard`, `ListRow` (trailing chevron, switch or price), `ProgressBar` (`primary`, `gold`, `sun`), `ScreenHeader`, `EmptyState` | `AppCard`: normal or locked (`locked.bg`, 2 pt `outline` ring, no opacity) |
| `overlays.dart` | `AppSheet` | grabber, title, close; dismissal and motion as research R5 |
| | `AppDialog` | dismissed only by its buttons when `barrierDismissible: false` (spend confirmations, the failure card) |
| | `EventBanner`, `OfflineBanner`, `UndoToast`, `AppToast`, `InlineAlert`, `StatusCard` | `UndoToast` built for M12; not used in the trip (spec FR-028) |
| `nav.dart` | `BottomNav` | four tabs, active pill, new-dots; cross-fade 150 ms |
| | `DailyCircle` | normal, event; optional `NewDot` or `CountBadge` |
| `story.dart` | `ComicPanel`, `CoachMark` (hole, ring, hand, character bubble; only the target takes taps), `MicrobusLoader` | `CoachMark` built for M07 |

`lib/features/trip/presentation/` (HANDOFF §3.4; research R10 maps them to M02's widgets):

| Component | Variants and states |
| --- | --- |
| `TripHud`, `ReputationBar` | reputation under 40%: `danger` fill and the «تحت ٤٠٪» chip; story chip |
| `StationStrip` | research R9 |
| `StationTag` | sizes 24, 26, 30; `hot`; `alightHere` (star); hidden while a `LedgerBadge` shows |
| `SpeechBubble` | `normal`, `warn`, `fight`, `thanks`, `character` (name over `quote` text) |
| `MoneyNote` | `fare`, `change`, `blocked` («؟»), `fallen` (sun ring), `inHand` |
| `LedgerBadge` | `paid` «دافع», `notYet` «لسه», `onFriend` «على صاحبه» |
| `ChoicePopover` | two answers, 44 tall |
| `Dashboard`, `HandSlot` (with the «رجّع» undo pill), `CallChangeButton`, `ChangeTray`, `TrayCell` (full, empty, breakable, pressed), `BoosterButton` (count, price, ad hidden until M11, active timer), `LastWordsLog` | break mode |
| `PassengerAvatar`, `CharacterAvatar`, `VehicleSprite` | Rive or static art ([rive-characters.md](./rive-characters.md)) |

## What goes

- `sticker_button.dart`, `sticker_card.dart`, `primary_button.dart`, `secondary_button.dart`,
  `wassal_bottom_bar.dart`.
- `sticker_page.dart`, which becomes `app_page.dart`.
- `new_dot.dart`, which is rewritten into `pills.dart`.

Their tests move to the new components. `no_retired_design_test.dart` fails if `lib/` names any of
them.

## The gallery

`lib/features/dev/gallery/` (research R4):

- **Components page.** One section per component above, in every variant and state, on `ground` and,
  where the design uses it, on `paper` and `dashboard.bg`.
- **Tokens page.** Every colour swatch with its name and hex, the 13 type styles in Arabic sample text
  from the ARB file, radii, lips, rings and motion (each playable).
- **Controls.** The digit style, reduced motion, and text scale 1.0, 1.15 or 1.3.
- **Builds.** It is opened only on dev and staging builds. A prod-flavor test checks that it can't be
  reached.

## Tests

| Test | Checks |
| --- | --- |
| `test/core/theme/components/*_test.dart` | each component's states, its press (lip and offset at mid-press), disabled, semantics label, 44×44 hit area, RTL order, and reduced motion |
| `test/goldens/components/` | the gallery's components page, section by section, at 390 wide, RTL, both digit styles |
| `test/repo/no_ink_test.dart` | no `InkWell`, `InkResponse`, `ElevatedButton`, `TextButton`, `OutlinedButton` or `FilledButton` in `lib/` |
| `test/repo/no_retired_design_test.dart` | the retired names (above, plus the old fonts and `passenger.riv`) |
