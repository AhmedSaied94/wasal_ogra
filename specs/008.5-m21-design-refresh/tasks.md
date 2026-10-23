---

description: "Task list for M21 Design Refresh"
---

# Tasks: Design Refresh (M21)

**Input**: Design documents from `specs/008.5-m21-design-refresh/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**:

- **Mandatory, and first.** Constitution XIII requires tests. Every phase writes its tests first, and
  they must fail before its implementation tasks start. Tests come first in particular for
  `SceneLayout`'s minimum sizes, the look fallback (no hidden archetype picks a look), the pose table,
  and the token check.
- **Behaviour stays.** Every M02 and M03 behaviour test keeps its assertions (spec FR-042). When an
  existing test finds a widget by a type this feature retires (`StickerButton`, `WassalBottomBar`,
  `StandInPassengerArt`, …), only the finder changes, to the replacement type or to the semantics label.
  The PR lists each such change.
- **Real engine, real database, static art.** Trip tests keep M02's setup: the real `TripEngine`, a
  drift database, M05's in-memory economy, and fakes only at the platform edges. Goldens draw passengers
  with the static SVG art (research R17); only the tests tagged `rive` use the owner's files.
- **Coverage.** At least 80% of lines in `apps/mobile` (`tool/check_coverage.dart --min 80`).

**Organization**:

- **Paths** are from the repository root. Dart commands run with `fvm` in `apps/mobile/`.
- **Codegen.** After adding or changing a `@riverpod` provider, run `fvm dart run build_runner build -d`
  in `apps/mobile`. Before any Rive test, run `fvm dart run rive_native:setup --verbose --clean
  --platform linux`. After any change to `docs/design/tokens.json`, run `fvm dart run
  tool/design/gen_tokens.dart`; after any change to the design's SVGs, `fvm dart run
  tool/design/sync_assets.dart`.
- **Exactness.** Every number comes from `tokens.json` (through the generated tokens), from
  `design_extras.dart` (which names its artboard), or from the contracts: the zones 114, 8, 258 and 16;
  the 36 pt crop; the threshold `inset + 764`; the seat tables; the ±2 pt tolerance; the 1.15 clamp.
  No bare literal in a widget.
- **Text.** Every player-visible string is an ARB key in `apps/mobile/lib/l10n/app_ar.arb`, with an
  `@key` description in English, and its text from HANDOFF's strings for the artboard. No Arabic in
  `lib/` code. Sample data for goldens lives in `test/design/samples/`, where Arabic is allowed.
- **Shared files** grow story by story, so tasks that touch them run in order, never in parallel:
  - `apps/mobile/lib/l10n/app_ar.arb`;
  - `apps/mobile/lib/core/theme/app_theme.dart`;
  - `apps/mobile/lib/features/trip/presentation/trip_screen.dart`;
  - `apps/mobile/lib/features/trip/domain/projection.dart` and `cues.dart`;
  - `apps/mobile/test/helpers/trip.dart`;
  - `apps/mobile/pubspec.yaml` and `.github/workflows/mobile.yml`.
- **Goldens.** Each story regenerates the goldens its changes move (`fvm flutter test --update-goldens
  <files>`). The author reviews every changed PNG before committing it. CI on Linux is the reference.
- **One PR.** This feature merges as one PR, and only with the owner's Rive file (`wassal.riv`)
  committed.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story the task belongs to (US1–US7 from spec.md)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: The new dependency, the fonts, the design's files in the app, and CI (research R2, R3,
R19).

- [X] T001 Update `apps/mobile/pubspec.yaml` (plan "Primary Dependencies", data-model.md "Assets"):
  - dependency `flutter_svg: ^2.3.0`;
  - font families `Marhey` (`- asset: assets/fonts/Marhey-VariableFont_wght.ttf`) and `ReadexPro`
    (`- asset: assets/fonts/ReadexPro-VariableFont_HEXP_wght.ttf`). The files drop google/fonts' brackets, which the asset bundle URL-encodes. Keep
    `Lalezar` and `BalooBhaijaan2` until T117 removes them;
  - asset folders `assets/icons/`, `assets/illustrations/passengers/`,
    `assets/illustrations/characters/`, `assets/illustrations/vehicles/`,
    `assets/illustrations/screens/` (all flavors; Flutter asset folders aren't recursive).

  Run `fvm flutter pub get` and commit `pubspec.lock`.
- [X] T002 [P] Add the fonts (research R3, contracts/design-tokens.md "Fonts"). Download from
  `github.com/google/fonts` at its current `main` commit:
  - `ofl/marhey/Marhey[wght].ttf` → `apps/mobile/assets/fonts/Marhey-VariableFont_wght.ttf`;
  - `ofl/marhey/OFL.txt` → `apps/mobile/assets/fonts/OFL-Marhey.txt`;
  - `ofl/readexpro/ReadexPro[HEXP,wght].ttf` → `apps/mobile/assets/fonts/ReadexPro-VariableFont_HEXP_wght.ttf`;
  - `ofl/readexpro/OFL.txt` → `apps/mobile/assets/fonts/OFL-ReadexPro.txt`.

  Record the commit hash in `apps/mobile/assets/fonts/README.md` (create it in English: which files,
  where they come from, their licence). It is quoted in the PR.
- [X] T003 [P] Create `apps/mobile/tool/design/sync_assets.dart` (research R19). It copies byte for byte
  from `docs/design/` (path resolved from the script's location, `../../../docs/design/`) into
  `apps/mobile/assets/`:
  - every `docs/design/icons/*.svg` (92 files) → `assets/icons/`;
  - `illustrations/passengers/{regular,hagga,sleeper,hurried,effendi_200,student,headphones,claimer,group_payer,chatterbox,regular_customer,honest}.svg`
    → `assets/illustrations/passengers/`;
  - `illustrations/characters/{usta,salma,bride_father,bride_mother,moallem,belya}.svg` →
    `assets/illustrations/characters/`;
  - `illustrations/vehicles/{tuktuk,microbus_old}.svg` → `assets/illustrations/vehicles/`;
  - `illustrations/screens/Loading_01.svg` → `assets/illustrations/screens/`.

  The list is a `const` map in the script, which `test/repo/design_assets_test.dart` (T010) imports. A
  missing source fails with its path. It deletes nothing it didn't copy. Run it and commit the copies.
- [X] T004 [P] Update `.github/workflows/mobile.yml`: in the `changes` job's `grep -qE` pattern, add
  `docs/design/` to the alternatives, so it reads
  `'^(apps/mobile/|packages/|content/|fixtures/|docs/design/|\.fvmrc$|\.github/workflows/mobile\.yml$)'`
  (research R2).
- [X] T005 [P] Rewrite `apps/mobile/assets/rive/README.md` in English: this folder holds the owner's
  file, `wassal.riv` (revised 2026-10-23 from four files when the owner delivered one), made to
  `specs/008.5-m21-design-refresh/contracts/rive-characters.md` and exported from a paid Rive plan.
  Add that `passenger.riv` (M02) stays only until T109 removes it.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Free the token names, build the design-check harness, the press haptic and the two
asset guards. Every story uses them.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T006 Move M03's tokens aside so the generated ones can take their names (research R2). This is
  a mechanical change, with no visual change:
  - `git mv` `apps/mobile/lib/core/theme/tokens/{colors,typography,shape,space,motion}.dart` to
    `apps/mobile/lib/core/theme/tokens/legacy/`;
  - rename `ColorTokens` → `StickerColors`, `TypeTokens` → `StickerType`, `ShapeTokens` →
    `StickerShape`, `SpaceTokens` → `StickerSpace`, `MotionTokens` → `StickerMotion`;
  - in `apps/mobile/lib/core/theme/app_theme.dart`, rename `WassalTokens` → `StickerTokens` and the
    `context.tokens` getter → `context.stickerTokens` (extension `StickerTokensContext`);
  - update every user in `apps/mobile/lib/` and `apps/mobile/test/` (61 files today: find them with
    `grep -rlE "ColorTokens|TypeTokens|SpaceTokens|MotionTokens|ShapeTokens|context\.tokens|WassalTokens"`);
  - rename `apps/mobile/test/core/theme/palette_test.dart` → `legacy_palette_test.dart` and
    `tokens_test.dart` → `legacy_tokens_test.dart`.

  `no_raw_style_values_test.dart` already excludes `lib/core/theme/tokens/`, which covers `legacy/`.
  Run `fvm flutter analyze --fatal-infos` and `fvm flutter test`: everything passes with **no golden
  change**. Commit this on its own.
- [X] T007 [P] Create the box reader `apps/mobile/test/design/boxes.dart` (contracts/design-checks.md):
  - `final class DesignBox { int id; String tag; String role; double x, y, w, h; String? label; String? text; }`;
  - `final class DesignBoard { String artboard; double w, h; List<DesignBox> boxes; Iterable<DesignBox> get taps; }`;
  - `DesignBoard loadBoard(String artboard)`, which reads `../../docs/design/boxes/<artboard>.json`
    relative to `apps/mobile`, and `DesignBoard parseBoard(String json)`.

  Test it in `apps/mobile/test/design/boxes_test.dart`:
  - `C-Trip` has 26 taps, the first being «إيقاف مؤقت» at (330, 36, 44, 44);
  - `Fail`'s first tap has no label;
  - `Tokens` has none;
  - a malformed file throws, naming the artboard.
- [X] T008 Create the check harness `apps/mobile/test/design/design_check.dart`
  (contracts/design-checks.md "Matching a box", "Surfaces"):
  - `void applyDesignSurface(WidgetTester tester, Size size, {required double topInset})`: physical
    size, DPR 1, and `tester.view.padding`/`viewPadding` with `top: topInset`, reset on tear-down;
  - `Future<void> expectLayoutMatches(WidgetTester tester, String artboard, {Map<int, String> skip =
    const {}, Map<int, String> pairings = const {}, Set<String> appOnly = const {}, double tolerance
    = 2})`:
    - it walks the semantics tree;
    - for each tap box, it applies skip (printing the reason), then pairing, then `label`, then
      `text`;
    - it expects exactly one node whose rect is within the tolerance on every side;
    - it then fails on any tappable semantics node in the tree that no box and no `appOnly` label
      matched;
    - its failure message names the artboard, the box id, the label and both rects;
  - `Future<void> expectDesignGolden(Finder finder, String artboard, DigitStyle digits)`: `matchesGoldenFile('goldens/$artboard_${digits.name}.png')`.
    When `const bool.fromEnvironment('DESIGN_COMPARE')` is true, it also writes
    `apps/mobile/build/design_compare/<artboard>_<digits>.png`: the design's
    `docs/design/png/<artboard>.png` and the render side by side, at the artboard's size.

  Self-test it in `apps/mobile/test/design/design_check_test.dart` with a small widget and a board
  from `parseBoard`:
  - a matching rect passes;
  - one moved by 3 pt fails with that message;
  - a skipped box is not looked up;
  - a pairing is used;
  - an unmatched extra button fails.
- [X] T009 [P] Add the press haptic (research R4):
  - in `apps/mobile/lib/core/audio_haptics/haptics.dart`, add `void selection();` to `Haptics` and
    implement it in `SystemHaptics` with `unawaited(HapticFeedback.selectionClick())`;
  - create `apps/mobile/lib/core/audio_haptics/vibration_setting.dart`:
    - `const vibrationKey = 'pref.trip_haptics'`;
    - a `@riverpod bool vibrationEnabled(Ref ref)` reading it from the settings store, with
      `TripSettings`' current default;
    - a `@riverpod void Function() pressFeedback(Ref ref)` that calls `haptics.selection()` only when
      vibration is on;
  - make `apps/mobile/lib/features/trip/application/trip_settings.dart` use `vibrationKey` instead of
    its own `tripHapticsKey` constant (same string, so no stored value changes);
  - in `apps/mobile/test/helpers/trip.dart`, make `FakeHaptics.selection` record `'selection'`.

  Test in `apps/mobile/test/core/audio_haptics/vibration_setting_test.dart`: the key's string is
  unchanged; `pressFeedback` calls `selection` when on and not when off.
- [X] T010 [P] Create `apps/mobile/test/repo/design_assets_test.dart` (research R19). For each entry
  of `sync_assets.dart`'s map, the source exists and the copy is byte-identical. Every file under
  `apps/mobile/assets/icons/` and `assets/illustrations/` is in the map. Self-test: a temp copy with
  one changed byte is reported by its path.
- [X] T011 [P] Create `apps/mobile/test/repo/no_ink_test.dart` (contracts/components.md "Rules"). No
  file in `apps/mobile/lib/` names `InkWell`, `InkResponse`, `ElevatedButton`, `TextButton`,
  `OutlinedButton`, `FilledButton` or `SnackBar`, except a `const _allowed` list. The list starts as
  `{'lib/core/routing/back_to_exit.dart'}`, and T053 empties it. Self-test: a source string with
  `InkWell(` is caught.

**Checkpoint**: Legacy tokens are renamed, nothing has moved on screen, and the harness and guards
pass.

---

## Phase 3: User Story 1 - One source for the new look (Priority: P1) 🎯 MVP

**Goal**: Tokens generated from `tokens.json`, the HANDOFF §3 component set built once on a
lip-press `Pressable`, and a gallery on internal builds (spec FR-005 – FR-013).

**Independent Test**: Open the gallery on a dev build and compare it with `Components.png` and
`Tokens.png`. Change a value in `tokens.json` without regenerating: `design_tokens_test.dart` fails.

### Tests for User Story 1 (write first, must fail)

- [X] T012 [P] [US1] Create `apps/mobile/test/tool/token_generator_test.dart` for the pure function
  `String generateTokens(Map<String, Object?> json)` in `apps/mobile/tool/design/token_generator.dart`
  (contracts/design-tokens.md "Names", "Not generated"):
  - the name table's examples map as written (`color.primary.lip` → `ColorTokens.primaryLip`,
    `color.ink.2` → `ink2`, `denomination.0.5` → `denom050`, `lip.primary.m` → `LipTokens.primaryM`
    and `primaryMDepth`, `layout.trip.faces.near` → `LayoutTokens.tripNear`, `motion.sheetIn` →
    `MotionTokens.sheetIn` and `sheetInCurve`);
  - `#RRGGBB` and `rgba(r,g,b,a)` become `Color(0xAARRGGBB)`;
  - `"22–26 (24)"` gives 24;
  - `easeOutBack(1.2)` becomes `EaseOutBack(1.2)`, a curve class in the hand-written
    `lib/core/theme/tokens/curves.dart` with the standard back-out formula
    `1 + (k + 1)(t − 1)³ + k(t − 1)²`: 0 at t = 0, 1 at t = 1, and overshooting in between;
  - `motion.moneyHop`, `digits`, `font` and every `*_rules`/`*_note`/`use` key are not emitted;
  - an unreadable value throws, naming its key;
  - two runs give identical output;
  - every type style has `leadingDistribution: TextLeadingDistribution.even` and a size ≥ 12.
- [X] T013 [P] [US1] Create `apps/mobile/test/repo/design_tokens_test.dart`. It reads
  `../../docs/design/tokens.json`, runs `generateTokens` and formats the result with the `dart_style`
  formatter. It compares the result with `lib/core/theme/tokens/design_tokens.dart` and, on a
  difference, fails with the first differing line and the command `fvm dart run
  tool/design/gen_tokens.dart`.
- [X] T014 [P] [US1] Create `apps/mobile/test/core/theme/design_palette_test.dart` with every row of
  contracts/design-tokens.md "Palette checks", using M03's contrast and L* helpers from
  `legacy_palette_test.dart` (move them to `apps/mobile/test/helpers/color_math.dart`):
  - 4.5:1 for each listed pair, and 3:1 for Marhey ≥ 18 bold;
  - the four station colours pairwise ≥ 18 L* apart, and `primary` against `danger`;
  - a scan of `lib/core/theme/components/` and `lib/features/trip/presentation/` sources finds no
    `ColorTokens.paper`/`Colors.white` text style on a `danger` or `sun` fill in the same widget.
- [X] T015 [P] [US1] Create `apps/mobile/test/core/theme/components/pressable_test.dart`:
  - at mid-press (40 ms), the child is offset down by half the lip, and the lip shadow is reduced;
  - after release it returns;
  - `pressFeedback` is called once per press;
  - disabled: 45% opacity, no shadow, no offset, no callback, `Semantics(enabled: false)`;
  - the hit area is ≥ 44×44 for a 20×20 child;
  - reduced motion still presses (presses aren't decorative motion).
- [X] T016 [P] [US1] Create `apps/mobile/test/core/theme/components/buttons_test.dart`:
  - `AppButton` primary xl (64 tall, radius 22, lip 6) and l (54–58, lip 5), secondary, sun, danger
    (ink label, never white) and tertiary (pressed = 70% opacity);
  - loading replaces the label with the 3-dot pulse and isn't tappable;
  - `CostChip` («−١» with the fuel icon) as trailing;
  - `RewardedAdButton` ready and not-ready («الإعلان مش جاهز», disabled look);
  - `IconCircleButton` on ground (white with lip) and in a sheet (`ground` fill, no lip), each icon;
  - every button's semantics label.
- [X] T017 [P] [US1] Create `apps/mobile/test/core/theme/components/pills_test.dart`:
  - `CurrencyPill`: coin, bonat, fuel with its timer line, fuel 0 on `danger.soft`, and the 44 and 40
    heights;
  - `CountBadge` (min 22×18, but a 44×44 hit area when tappable);
  - `NewDot` (12, `danger`, 2 pt `ink` ring);
  - `StatusChip`: new, story, done, offline;
  - `PriceTag`;
  - `Stars` 0–3.

  Numbers arrive as formatted strings; the widget never formats.
- [X] T018 [P] [US1] Create `apps/mobile/test/core/theme/components/controls_test.dart`:
  - `AppSwitch`: on, off, disabled; the knob at the end side when on in RTL; a tap anywhere on its row
    toggles;
  - `Segmented`: `sun` and `primary` active styles, 2–4 segments, and the semantics of the selected
    one;
  - `AppTextField`: idle ring 2 pt `ground.lip`, focused `primary`.
- [X] T019 [P] [US1] Create `apps/mobile/test/core/theme/components/containers_test.dart`:
  - `AppCard`, normal and locked (`locked.bg`, 2 pt `outline` ring, `ink.2` text, a lock icon, never
    opacity; spec FR-012);
  - `ListRow` with chevron, switch and price;
  - `ProgressBar` in `primary`, `gold` and `sun`, its 500 ms width tween, and none under reduced
    motion;
  - `ScreenHeader` (back control on the start side in RTL);
  - `EmptyState`.
- [X] T020 [P] [US1] Create `apps/mobile/test/core/theme/components/overlays_test.dart`:
  - **`AppSheet`:** dismissed by a drag of more than 25%, a fling, ✕, system back or the scrim; not by
    a drag of less; in over 280 ms, out over 200 ms.
  - **`AppDialog`:** scale 0.92 → 1 over 220 ms. With `barrierDismissible: false`, the scrim and back
    do nothing.
  - **`EventBanner`:** auto-hides after 4 s, and is announced once (`SemanticsService.announce`
    called once).
  - **`UndoToast`:** shows its seconds left and holds 3 s.
  - **`AppToast`:** no action.
  - **The rest:** `OfflineBanner`, `InlineAlert`, `StatusCard`.
  - **Reduced motion:** no scale or slide, fades ≤ 150 ms.
- [X] T021 [P] [US1] Create `apps/mobile/test/core/theme/components/nav_story_test.dart`:
  - **`BottomNav`:** 4 equal tabs; the active one in a 60×34 `primary` pill with a white glyph; the
    new-dot on the icon's top-end corner; labels 13 pt.
  - **`DailyCircle`:** normal and event.
  - **`ComicPanel`.**
  - **`CoachMark`:** only the target inside the hole takes a tap; a tap outside does nothing.
  - **`MicrobusLoader`.**
- [X] T022 [P] [US1] Create `apps/mobile/test/features/dev/gallery_test.dart`:
  - on a dev flavor, Home's placeholder shows a gallery button that opens `GalleryScreen`;
  - its components page lists a section per component of contracts/components.md "The set";
  - the tokens page lists every `ColorTokens` swatch by name;
  - the digit switch changes the numbers shown;
  - on the prod flavor, there is no gallery button and `GalleryScreen` is unreachable from the route
    table.
- [X] T023 [P] [US1] Create the artboard checks for the design-system boards
  (contracts/design-checks.md "Surfaces"):
  - `apps/mobile/test/design/samples/components.dart`: a 1200×1700 composition placing the shared
    components where `docs/design/screens/Components.html` places them;
  - `apps/mobile/test/design/samples/tokens.dart`: a 1200×1220 composition of the token swatches;
  - `apps/mobile/test/goldens/design/components_goldens_test.dart` and `tokens_goldens_test.dart`:
    both digit styles;
  - `apps/mobile/test/design/components_layout_test.dart`: its 8 tap boxes, with no skips.
- [X] T024 [P] [US1] Create `apps/mobile/test/goldens/components/components_goldens_test.dart`: the
  gallery's components page, one golden per section, at 390 wide, RTL, both digit styles.

### Implementation for User Story 1

- [X] T025 [US1] Create `apps/mobile/tool/design/token_generator.dart` (`generateTokens`, pure, no
  `dart:io`) and the CLI `apps/mobile/tool/design/gen_tokens.dart`. Create
  `apps/mobile/lib/core/theme/tokens/curves.dart` with `final class EaseOutBack extends Curve`, which the
  generated motion tokens use. The CLI reads
  `../../docs/design/tokens.json`, formats the output with `dart_style` and writes
  `lib/core/theme/tokens/design_tokens.dart` with the header `// GENERATED by
  tool/design/gen_tokens.dart from docs/design/tokens.json. Do not edit.`.
  - **Classes:** `ColorTokens`, `StationColors` (`all`, four `(bg, letter)` records), `TypeTokens`,
    `RadiusTokens`, `LipTokens`, `RingTokens` (a `RingSpec` class with `width`, `color`, `inside`,
    `dashed`), `SpaceTokens`, `LayoutTokens` and `MotionTokens`.
  - **The theme extension:** `WassalTokens extends ThemeExtension<WassalTokens>`, with a field per
    colour, `stations`, `copyWith`, `lerp`, `standard`, and `extension WassalTokensContext on
    BuildContext { WassalTokens get tokens; }`.

  Add `dart_style` as a dev dependency if it isn't one already (in `apps/mobile/pubspec.yaml`, after
  T001). T012 passes.
- [X] T026 [US1] Run `fvm dart run tool/design/gen_tokens.dart` and commit
  `apps/mobile/lib/core/theme/tokens/design_tokens.dart`. T013 and T014 pass.
- [X] T027 [P] [US1] Create `apps/mobile/lib/core/theme/tokens/design_extras.dart`
  (contracts/design-tokens.md "Extras"). Each constant has a `///` comment naming its artboard and
  element, with values from the artboard HTML:
  - `loadingWordmark` (Marhey 700 60, height 1.1);
  - `pauseButtonLabel` (23);
  - `failTitle` (30);
  - `hudTitleSize`;
  - the bubble and choice lips and the coach scrim are tokens (`LipTokens.bubble`, `bubbleWarn`,
    `popover`; `ColorTokens.scrimCoach`), so they are not repeated here;
  - `dialogRadius` (26);
  - `bannerTitle` (Marhey 700 17);
  - `minTopInset` (24), citing HANDOFF §2.4: the least top inset a screen keeps when the phone reports
    a smaller status bar.
- [X] T028 [US1] In `apps/mobile/lib/core/theme/app_theme.dart`, register `WassalTokens.standard`
  beside `StickerTokens.standard` in `extensions`. Change nothing else (US2 switches the theme). All
  existing goldens unchanged.
- [X] T029 [US1] Create `apps/mobile/lib/core/theme/components/pressable.dart`, a
  `ConsumerStatefulWidget` (contracts/components.md "Rules"):
  - inputs `child`, `onTap`, `lip` (`LipSpec`: shadow and depth), `enabled`, `semanticLabel`, and
    optional `pressedOpacity` for tertiary;
  - on press: translate down by the lip's depth and animate the shadow to 0 over
    `MotionTokens.press` with its curve; call `ref.read(pressFeedbackProvider)()`; reverse on release
    or cancel;
  - disabled: 45% opacity, no shadow, no gesture;
  - a hit area padded to ≥ 44×44;
  - `Semantics(button: true, label:, enabled:)`; `GestureDetector`, never `InkWell`.

  T015 passes.
- [X] T030 [P] [US1] Create `apps/mobile/lib/core/theme/components/buttons.dart` on `Pressable`:
  `AppButton` (named constructors `primary({AppButtonSize size})`, `secondary`, `sun`, `danger`,
  `tertiary`; `loading`; `trailing`), `CostChip`, `RewardedAdButton({required bool ready})` and
  `IconCircleButton({required String icon, bool inSheet})`. Icons via `SvgPicture.asset(
  'assets/icons/<name>.svg', colorFilter: ColorFilter.mode(color, BlendMode.srcIn))`. T016 passes.
- [X] T031 [P] [US1] Create `apps/mobile/lib/core/theme/components/pills.dart`: `CurrencyPill`
  (`kind`, `value`, optional `timer`, `empty`, `height` 44 or 40), `CountBadge`, `NewDot`,
  `StatusChip` (`new_`, `story`, `done`, `offline`), `PriceTag` and `Stars`. T017 passes.
- [X] T032 [P] [US1] Create `apps/mobile/lib/core/theme/components/controls.dart`: `AppSwitch` (its
  own row: the label and the track, the whole row toggling), `Segmented<T>` (`style: sun | primary`)
  and `AppTextField`. T018 passes.
- [X] T033 [P] [US1] Create `apps/mobile/lib/core/theme/components/containers.dart`: `AppCard`
  (`locked`), `ListRow`, `ProgressBar` (`color`, a 500 ms easeOutCubic tween), `ScreenHeader` and
  `EmptyState`. Add `double screenTopInset(BuildContext context)` =
  `max(MediaQuery.viewPaddingOf(context).top, minTopInset)` (spec FR-018). `ScreenHeader` sits below it,
  never below the design's fixed 36. T019 passes.
- [X] T034 [P] [US1] Create `apps/mobile/lib/core/theme/components/overlays.dart`:
  - `AppSheetPage` (a `Page` for go_router) and `showAppSheet`;
  - `AppDialog` and `showAppDialog({bool barrierDismissible})`;
  - `EventBanner`, `OfflineBanner`, `UndoToast`;
  - `AppToast` and `showAppToast(BuildContext, String)`, through an `OverlayEntry` that holds 3 s;
  - `InlineAlert`, `StatusCard`.

  Motion is from `MotionTokens`, and reduced motion comes from `MediaQuery.disableAnimationsOf`. The
  sheet adds `MediaQuery.viewPaddingOf(context).bottom` under its buttons (spec FR-018). T020 passes.
- [X] T035 [P] [US1] Create `apps/mobile/lib/core/theme/components/nav.dart`: `BottomNav` (tabs
  `nav_home`, `nav_lines`, `nav_apartment`, `nav_shop` with their `_active` icons, labels from M03's
  `tab*` ARB keys, new-dots as inputs) and `DailyCircle`.
- [X] T036 [P] [US1] Create `apps/mobile/lib/core/theme/components/story.dart`: `ComicPanel`,
  `CoachMark` (the hole is `targetRect` + 6 padding, radius 18, a 4 pt `sun` ring, scrim
  `ColorTokens.scrimCoach`; it absorbs taps outside the hole) and `MicrobusLoader`. T021 passes.
- [X] T037 [US1] Create the gallery in `apps/mobile/lib/features/dev/gallery/` (research R4):
  - `gallery_screen.dart`: two tabs, the components and the tokens; top controls for the digit style
    (overriding `digitStyleProvider` locally), reduced motion and text scale 1.0, 1.15 or 1.3;
  - `components_page.dart`: one section per component, in every variant and state;
  - `tokens_page.dart`: swatches with name and hex, the type styles on a sample line, radii, lips,
    rings, and motion previews you can tap to play;
  - `gallery_entry.dart`: `GalleryEntry`, a button that pushes `GalleryScreen` with
    `Navigator.of(context).push`.

  Labels are English developer text. Sample Arabic for the type styles comes from existing ARB keys
  (`appName`, `tripBreakButton`).
- [X] T038 [US1] In `apps/mobile/lib/core/routing/router.dart`, change the `RouteNames.home when
  playtest` case's `extra` to a `Column` of `TripList` and `GalleryEntry`. Add no route. T022 passes,
  and `test/core/routing/route_table_test.dart` stays unchanged and passes.
- [X] T039 [US1] Generate the US1 goldens: `fvm flutter test --update-goldens
  test/goldens/components test/goldens/design/components_goldens_test.dart
  test/goldens/design/tokens_goldens_test.dart`. Compare each with `docs/design/png/Components.png`
  and `Tokens.png` (or with `--dart-define=DESIGN_COMPARE=true`), and fix components, not goldens,
  until they agree. T023 and T024 pass.

**Checkpoint**: Tokens are generated and checked, every component is tested and in the gallery, and no
existing screen has changed yet.

---

## Phase 4: User Story 2 - The app's frame in the new look (Priority: P1)

**Goal**: `Loading`, the `BottomNav`, the placeholders, sheets, dialogs, the exit toast and settings'
digit control in the new look; the app's theme switches to the new tokens (spec FR-014 – FR-018).

**Independent Test**: Cold-start a dev build (no white frame, the road bar following the boot steps),
visit each section, a placeholder, a sheet and settings, and compare the goldens with the PNGs.

### Tests for User Story 2 (write first, must fail)

- [X] T040 [P] [US2] Create `apps/mobile/test/bootstrap/boot_progress_test.dart` (data-model.md
  "BootProgress"):
  - with fake providers completing in a set order, `bootProgressProvider` reports `settings`,
    `tunables`, `content`, `database` and `economy` as they finish;
  - `value` = done / 5;
  - a failing step sets `failed` to it;
  - `retryAppStartup` resets `done`.
- [X] T041 [P] [US2] Create `apps/mobile/test/features/boot/loading_test.dart`:
  - the screen has the `sun` ground, the wordmark (`appName`), the tagline, the vehicle (static SVG),
    the roof sign (`destHome`), the road bar and a line from `loadingLines`;
  - at `value` 0.62 the marker's centre sits 62% of the way from the bar's right edge;
  - updates tween linearly for at most 150 ms, and jump under reduced motion;
  - on failure, an `InlineAlert` with `bootErrorMessage` and `bootRetry`;
  - the screen hands over as soon as startup completes.

  `boot_screen_test.dart` and `boot_resume_test.dart` keep their assertions.
- [X] T042 [P] [US2] Create the `Loading` checks:
  - `apps/mobile/test/design/samples/loading.dart`: `BootScreen` with a fake `BootProgress` at 0.62
    and `loadingLine1`;
  - `apps/mobile/test/design/loading_layout_test.dart`: `expectLayoutMatches` with the full-screen link
    «كمّل» skipped (prototype navigation), which leaves no tap. Also check, with `tester.getRect` on
    keyed widgets and ±2 pt, the road bar at (45, 668, 300, 24) and the wordmark at y 210, 289×66,
    centred (HANDOFF `Loading` blocks 1 and 4);
  - `apps/mobile/test/goldens/design/loading_goldens_test.dart`.
- [X] T043 [P] [US2] Create `apps/mobile/test/core/routing/frame_design_test.dart`:
  - **Bottom bar.** The four sections show `BottomNav` and no other screen does; the active tab's
    pill; new-dots from `new_dot_providers`; tabs cross-fade over 150 ms, with none under reduced
    motion.
  - **Placeholders.** A later feature's placeholder shows `ScreenHeader` with a working back control
    and `EmptyState` with `placeholderNote`.
  - **Sheets.** A sheet route uses `AppSheetPage` and closes by drag, ✕, back and scrim.
  - **Exit toast.** Back on Home shows an `AppToast` (no `SnackBar`), and a second back within its
    window leaves (M03's `back_behavior_test.dart` assertions unchanged).
  - **Insets.** Screens use `max(viewPadding.top, 24)` at the top.
- [X] T044 [P] [US2] Create `apps/mobile/test/features/settings/settings_design_test.dart`: the digit
  style is a `Segmented` (`primary` style) in a `ListRow` card. Choosing «Western» changes a number on
  the settings screen and on Home's placeholder at once. `settings_screen_test.dart` keeps its
  assertions.

### Implementation for User Story 2

- [X] T045 [US2] Add to `apps/mobile/lib/l10n/app_ar.arb`:
  - `loadingLine1`: «بنعدّ الفكة..»;
  - `loadingTagline`: «لمّ الأجرة صح، والباقي يرجع لصاحبه»;

  each with its `@` description. Run `fvm flutter pub get` to regenerate l10n.
- [X] T046 [US2] Switch the theme in `apps/mobile/lib/core/theme/app_theme.dart` (research R2,
  contracts/design-tokens.md "Theme"):
  - `scaffoldBackgroundColor: ColorTokens.ground`;
  - a `textTheme` from `TypeTokens`;
  - `splashFactory: NoSplash.splashFactory`, with transparent `highlightColor` and `hoverColor`;
  - `extensions: [WassalTokens.standard, StickerTokens.standard]`, the second only until T117;
  - the same theme for light and dark.
- [X] T047 [US2] Add boot progress in `apps/mobile/lib/bootstrap/startup.dart`:
  - a `@Riverpod(keepAlive: true) class BootProgressNotifier` exposing `BootProgress`
    (`lib/bootstrap/boot_progress.dart`: `steps`, `done`, `value`, `failed`);
  - `appStartup` awaits the five futures (`settingsStoreProvider`, `tunableLayersProvider`,
    `activeContentProvider`, `appDatabaseProvider`, `economyProvider`) and marks each step as it
    completes, and its failure;
  - `retryAppStartup` also resets the notifier.

  T040 passes.
- [X] T048 [US2] Rebuild `apps/mobile/lib/features/boot/boot_screen.dart` as `Loading` (research R6,
  HANDOFF `Loading` blocks 0–5):
  - the `sun` ground with the two `sun.glow` circles and the cloud;
  - the wordmark (`design_extras.loadingWordmark`, a `sun.lip` text shadow at (0, 5));
  - the tagline;
  - the vehicle, `SvgPicture.asset('assets/illustrations/vehicles/microbus_old.svg')` at 300×170 for
    now (US6 swaps in Rive), entering from the right over 600 ms (none under reduced motion);
  - the roof sign: a pill with `destHome`, Marhey 15 `sun` on `ink`;
  - the road bar, a `ProgressBar.road` variant added to `containers.dart`: `scene.road`, a `sun.lip`
    lip, the dashed lane line, and the 44×30 `primary` marker travelling right to left;
  - the line under it: `loadingLines(l10n)` (in this file, `[l10n.loadingLine1]`), picked once per
    launch with `Random()`;
  - on failure, the `InlineAlert` with retry.

  T041 passes.
- [X] T049 [US2] Create `apps/mobile/lib/core/routing/app_page.dart` from `sticker_page.dart`
  (`StickerPage` → `AppPage`, same transitions and reduced-motion rule, durations from `MotionTokens`).
  Update `router.dart`, and delete `sticker_page.dart`.
- [X] T050 [US2] Restyle `apps/mobile/lib/core/routing/sheet_page.dart` to build `AppSheetPage`, and
  `apps/mobile/lib/core/routing/placeholder_screen.dart` to use `ScreenHeader`, the `ground` page and
  `EmptyState`. Keep the destination's name, its links and its `extra`. The top inset comes from
  `ScreenHeader` (`screenTopInset`), with no fixed padding of its own.
- [X] T051 [US2] Restyle `apps/mobile/lib/core/routing/shell_scaffold.dart` to use `BottomNav`, with
  the 150 ms cross-fade (`AnimatedSwitcher`, none under reduced motion) and `viewPadding.bottom`
  under it. Stop importing `wassal_bottom_bar.dart` (deleted in T117).
- [X] T052 [US2] Restyle `apps/mobile/lib/features/settings/settings_screen.dart`: the digit-style row
  is a `ListRow` card holding a `Segmented<DigitStyle>` in the `primary` style, on the `ground` page
  with a `ScreenHeader`, which sets its top inset. T044 passes.
- [X] T053 [US2] Change `apps/mobile/lib/core/routing/back_to_exit.dart` to show the hint with
  `showAppToast` instead of a `SnackBar`. Empty `no_ink_test.dart`'s `_allowed` list. T043 and T011
  pass.
- [X] T054 [US2] Check the native splash: `apps/mobile/flutter_native_splash.yaml` (or its section in
  `pubspec.yaml`) uses `#FFD23F`, which equals `ColorTokens.sun`. Add that assertion to
  `apps/mobile/test/features/boot/loading_test.dart`. Don't regenerate the splash.
- [X] T055 [US2] Regenerate the frame's goldens: `fvm flutter test --update-goldens
  test/goldens/all_destinations_goldens_test.dart test/goldens/navigation_goldens_test.dart
  test/goldens/shell_goldens_test.dart test/goldens/design/loading_goldens_test.dart`.
  - **Review** each PNG; T042 passes.
  - **Trip goldens.** If the theme switch moved any of them (`fvm flutter test test/goldens/trip`),
    regenerate them too and note it in the PR.
  - **Sizes.** Run `test/a11y/minimum_sizes_test.dart` (M03): it passes with its assertions
    unchanged. At both text scales, `tester.takeException()` is null after each pump on the frame's
    screens, and no `RenderParagraph` other than a title has `didExceedMaxLines` (SC-004); add these
    two checks to that file.

**Checkpoint**: The app opens and navigates in the new look, and the trip still plays in M02's.

---

## Phase 5: User Story 3 - Playing a trip in the new look (Priority: P1)

**Goal**: The trip's zones, cabin, seats, strip, tags, notes, bubbles and dashboard in the design's
look and geometry, with every minimum kept and every command unchanged (spec FR-019 – FR-024, FR-036).

**Independent Test**: Play every sample trip on a dev build and compare with `C-Trip.png`. The scripted
player's 58 fixtures pass through the restyled controls.

### Test helpers for User Story 3

- [X] T056 [US3] Update `apps/mobile/test/helpers/trip.dart` (contracts/trip-layout.md "Golden
  surfaces"):
  - replace `enum TripSurface` with `reference(Size(390, 844), inset: 36, compliant: true)`,
    `a06(Size(360, 800), inset: 24, compliant: true)` and
    `small(Size(360, 640), inset: 24, compliant: false)`;
  - make `pumpTrip` apply the inset through `applyDesignSurface`.

  Delete the `*_compact_*` PNGs under `apps/mobile/test/goldens/trip/goldens/` (T075 regenerates the
  set). The test overrides keep M02's stand-in art until T068 replaces it.

### Tests for User Story 3 (write first, must fail)

- [X] T057 [P] [US3] Rewrite `apps/mobile/test/features/trip/domain/scene_layout_test.dart` from
  contracts/trip-layout.md:
  - **The room.** `S0 = H − T − 114 − 258 + 16`, with each row of the height table: 390×844 at T 36
    gives gap 8, scene 444, crop 0; 360×800 at T 24 gives gap 0, scene 420, crop 24; S0 448 gives
    gap 4; S0 400 gives crop 36 and scale 400/408.
  - **The threshold** `T + 764`.
  - **Width.** `xFactor` = w/390. The front seat at `w − 40`. Over 430 pt the zones keep 390, centred.
  - **The `micro_old` seat table:** face centres, rig scales, face widths 84, 67.2 and 52.5, tags at
    `face + (−38, +46) × scale` and the front's at (−32, +18), and the hit rects from the table.
  - **The `tuktuk` row:** x 62, 195 and 328 at scale 1.15.
  - **Hit areas.** At 360 they narrow to the seat spacing, are never under 44×44, and never overlap;
    the front seat wins over `A_r`.
  - **Minimums.** On both compliant sizes, every face is ≥ its minimum.
  - **Tokens.** `scene_layout.dart`'s seat-table constants equal `LayoutTokens.trip*`, so a design change
    to the seat table fails here.
- [X] T058 [P] [US3] Create `apps/mobile/test/features/trip/domain/looks_test.dart`, replacing
  `skin_looks_test.dart` (data-model.md "Looks"):
  - the 12 looks, each with an existing `apps/mobile/assets/illustrations/passengers/<id>.svg` and an
    ARB key;
  - the alias table exactly as written;
  - an unknown skin with archetype `hajja`, `student`, `headphones`, `sleeper`, `hurry` or `big_note`
    gets `hagga`, `student`, `headphones`, `sleeper`, `hurried` or `effendi_200`, with the label
    `tripLookPassenger`;
  - an unknown skin with any other archetype, including every hidden one (`claimer`, `honest`,
    `regular_customer`, `group_payer`, `changer`, `dodger`), gets `regular`;
  - only `hagga`, `effendi_200`, `student` and `headphones` have their own label.
- [X] T059 [P] [US3] Update `apps/mobile/test/a11y/trip_minimum_sizes_test.dart`
  (contracts/trip-layout.md "Guaranteed sizes", "Text scale"):
  - on the compliant surfaces at text scales 1.0 and 1.3: faces, hit areas (≥ 44×44, no overlap),
    notes (≥ 40×24, digits ≥ 15), bubble text 16 and unscaled, dashboard targets, and all text ≥ 12;
  - text in `TripHud`, `StationStrip`, `Dashboard`, `StationTag` and `MoneyNote` renders at 1.15× when
    the system scale is 1.3;
  - on `small`: the HUD's, the dashboard's and every hit area's sizes are unchanged, and only faces
    shrink;
  - nothing overlaps or clips (SC-004), on every surface and at both scales:
    - after each pump `tester.takeException()` is null, so no `RenderFlex` overflow;
    - no `RenderParagraph` except the HUD title and the player's name has `didExceedMaxLines`;
    - no two text boxes in the HUD, strip or dashboard intersect;
  - the bottom-third rule as before.
- [X] T060 [P] [US3] Create the `C-Trip` checks:
  - `apps/mobile/test/design/samples/c_trip.dart`: a scripted `micro_old` trip reproducing `C-Trip`'s
    sample state (HANDOFF §11 `C-Trip`): the passengers and their stops, the notes in flight, the
    hand at «١٥ ونص», the tray counts, the bubbles, the strip at the drawn moment;
  - `apps/mobile/test/design/c_trip_layout_test.dart`:
    - skip «للنموذج بس: افتح شاشة النتيجة»;
    - pair the 10 passenger boxes (ids 36–45) with the app's FR-036 labels for those seats;
    - pair box 55 (the hand, «في إيدك ١٥ ونص…») with the app's label, since the shared formatter writes
      amounts as numbers, not «ونص»;
    - `appOnly` holds the debug icon's label;
  - `apps/mobile/test/goldens/design/c_trip_goldens_test.dart`.
- [X] T061 [P] [US3] Create `apps/mobile/test/features/trip/presentation/trip_design_test.dart`:
  - **`TripHud`:** pause is an `IconCircleButton`; the title is one line with an ellipsis;
    `ReputationBar` turns `danger` under 40% with `tripReputationLow`.
  - **`StationStrip`:**
    - dots placed by `at_ms`, colours and letters by alighting order;
    - the next stop's 3 pt ring and countdown chip, pulsing under 8 s (steady under reduced motion);
    - a passed stop at 35% with `tripStationPassed`;
    - a raised fare struck through with the new chip.
  - **`StationTag`:** sizes 24, 26 and 30 by row; `hot` while the stop is next and change is owed.
  - **`MoneyNote`:** each kind's colours.
  - **`SpeechBubble`:** each variant, at most 2, the tail 8 pt above the head, clamped 10 pt inside.
  - **`HandSlot`:** «فاضية», the chips and total, and the «رجّع» pill (≥ 44×44) only during the undo
    window.
  - **`TrayCell`:** full, empty (dashed, not tappable), breakable (3 pt `danger` ring in break mode),
    pressed.
  - **`BoosterButton`:** the count, price («N بون», `tripBoosterPriceBadge`) and active-timer badges;
    the ad badge never shows.
  - **Labels.** A passenger's semantics label is their look and stop, plus «ليه باقي» only while hot.
  - **Commands.** Each control sends the same command as before, checked against the fake
    controller's log.

### Implementation for User Story 3

- [X] T062 [US3] Add to `apps/mobile/lib/l10n/app_ar.arb`:
  - `tripReputationLabel`: «السمعة»;
  - `tripReputationLow`: «تحت {pct}٪», where `pct` is a preformatted String;
  - `tripStationPassed`: «عدّت»;
  - `tripLookHeadphones`: «أبو سمّاعة».

  Remove `tripLookWorker` and `tripLookYoung`. Regenerate l10n.
- [X] T063 [US3] Align the trip's screen-reader labels with `C-Trip`'s `aria-label`s (spec FR-036).
  In `apps/mobile/lib/l10n/app_ar.arb`, keep the keys and change only these values:
  - `tripTrayEmptySlot` to «{amount} جنيه، مفيش»;
  - `tripTraySlot`'s one-pound case to read «جنيه، معاك {count}», through a `select` or plural on the
    amount;
  - the pause button's label to «إيقاف مؤقت»;
  - the boosters' labels to the design's names («كيس فكة», «الدفتر», «صحّي النايم», «زحمة +١٠ث», with the
    seconds preformatted).

  Where an existing test asserts one of these texts, it builds the expected text through
  `AppLocalizations`, so the assertion's meaning is unchanged; list each in the PR.
- [X] T064 [US3] Apply HANDOFF §9.1 #3's BONAT wording (spec FR-012) in
  `apps/mobile/lib/l10n/app_ar.arb`:
  - **Tags, chips and badges always say «بون».** Add `tripBoosterPriceBadge`: «{price} بون» for the
    booster's price badge, and change `tripBoosterCardPrice` to «بـ{price} بون».
  - **Sentences agree with the number.** Change `tripBoosterForSale`, `tripBoosterCardBalance` and
    `tripBoosterShort` to ICU plurals on a new `count` placeholder (int), keeping their preformatted
    String placeholders for the digits, like M02's `tripCause*` keys:
    `=1{بون واحد} =2{بونين} few{{n} بونات} other{{n} بون}`.
  - **Call sites.** Pass `count` where these keys are used.

  `tripFailRevive` («صالح بـ{price} بون») already follows the rule. Regenerate l10n. Where an existing
  test asserts one of these texts, it builds the expected text through `AppLocalizations` (FR-042).
- [X] T065 [US3] Rebase the trip's presentation constants on tokens:
  - **`apps/mobile/lib/features/trip/presentation/trip_colors.dart`** maps the trip's roles to
    `ColorTokens` and the `money_note`, `scene` and `dashboard` groups. It drops the `Sticker*`
    imports, and the shirt colours go.
  - **`trip_text.dart`** adds `TripTextScale.clamp(context)`: the system scale clamped to 1.0–1.15,
    for the HUD, strip, dashboard, tags and notes. Bubbles stay unscaled.
  - **`trip_motion.dart`** takes its durations from `MotionTokens` (bubble pop 180 ms, hot pulse
    600 ms, countdown pulse 500 ms, alight 600 ms, shake 300 ms with 6 pt). It keeps M02's constants
    that tokens don't cover, and adds `reputationLowPercent = 40` and `countdownPulseBelow =
    Duration(seconds: 8)`.
- [X] T066 [US3] Rewrite `apps/mobile/lib/features/trip/domain/scene_layout.dart`
  (contracts/trip-layout.md, data-model.md "TripZones", "SceneLayout", "SeatLayout"):
  - pure, numbers only, under the domain import guard. The generated tokens import Flutter, so the
    domain can't read them: the seat table is copied into `scene_layout.dart` as constants, and T057
    checks them against `LayoutTokens`;
  - `tuktuk`'s row and the hit-rect table as constants named after the contract.

  T057 passes.
- [X] T067 [US3] Create `apps/mobile/lib/features/trip/domain/looks.dart` (`Look`, `looks`,
  `skinAliases`, `lookFor(String skin, Archetype archetype)`), and delete `skin_looks.dart`:
  - change `PassengerView.look` to `Look` in `trip_view.dart`, and `projection.dart` to call `lookFor`;
  - change the talk log's speaker labels in `talk_log.dart` to `look.labelKey` (the group label
    `tripLookGroup` unchanged);
  - delete `skin_looks_test.dart`.

  T058 passes. `projection_test.dart`, `talk_log_test.dart` and `who_paid_test.dart` keep their
  assertions; only `SkinLook` constructions in their fixtures change to `Look`.
- [X] T068 [US3] Create `apps/mobile/lib/features/trip/presentation/scene/svg_passenger_art.dart`
  (research R17):
  - `SvgPassengerArtFactory implements PassengerArtFactory` loads each look's SVG once
    (`vg.loadPicture(SvgAssetLoader(look.svg), null)`) and caches the `PictureInfo`;
  - `SvgPassengerArt implements PassengerArt` draws it scaled to the seat (head centre at
    (100, 100) of 200×240, × rig scale), with code motion:
    - an idle bob of 2 pt every 1.2 s;
    - asleep: tilted 18° with «z» marks;
    - mood 2–3: the sweat drop and red tint;
    - headphones: music notes;
    - boarding: sliding in from the end side;
    - getting off: rising 12 pt and fading over 600 ms;
    - a fight: a 6 pt shake;
    - the marks are painted from tokens, with no text in the canvas;
  - under reduced motion, no bob, shake or slide, and the marks hold still.

  Make it the `passengerArtProvider` default in `apps/mobile/lib/features/trip/trip_providers.dart`
  while `passengerRiveProvider` is null. In the same change, switch `tripTestOverrides` in
  `apps/mobile/test/helpers/trip.dart` to `SvgPassengerArtFactory`, then delete
  `StandInPassengerArtFactory` and `StandInPassengerArt` from `passenger_art.dart`, keeping the
  interfaces. Every test compiles at each step.
- [X] T069 [US3] Redraw the cabin in `apps/mobile/lib/features/trip/presentation/scene/cabin_component.dart`
  and `windows_component.dart` (HANDOFF §4.1, `C-Trip`, `Tutorial`):
  - `scene.wall`, `scene.floor`, the back window, the side windows with the street moving at M02's
    speeds (one layer, no parallax, under reduced motion), the next station's sign in its colour, and
    the benches in `scene.seat` and `scene.seat.hi`;
  - the tuktuk's single bench;
  - all drawn from the bottom up, so the `crop` cuts the wall first;
  - static parts cached as one picture per size;
  - no garland.
- [X] T070 [P] [US3] Redraw the driver's hand in
  `apps/mobile/lib/features/trip/presentation/scene/hand_component.dart` (sleeve, forearm, palm,
  thumb), at `SceneLayout.hand`.
- [X] T071 [US3] Restyle the top in `apps/mobile/lib/features/trip/presentation/top_bar/`:
  - **`top_bar.dart` → `TripHud`:** a 44 pt row with the pause `IconCircleButton`, the title in
    `TypeTokens.displayS` (one line, ellipsis, with a slot above it for the story chip) and
    `ReputationBar` (90×10, `tripReputationLabel`, `danger` and `tripReputationLow` under
    `reputationLowPercent`).
  - **`station_strip_bar.dart` → `StationStrip`** (research R9):
    - a 64 pt white card, the 6 pt `track` with `primary` fill from the start end;
    - the depot dot and `destHome`;
    - dots at `302 × at_ms / last at_ms`, with the shifted `at_ms`;
    - the next stop's `ring.hot` and countdown chip;
    - passed stops at 35% with `tripStationPassed`;
    - raised fares;
    - the `sun` vehicle marker, 28×26.

  Text clamps through `TripTextScale`.
- [X] T072 [US3] Restyle the scene's overlays in `apps/mobile/lib/features/trip/presentation/overlays/`:
  - **`patches_layer.dart`:** `StationTag` at `SeatLayout.tag`, with `hot`, the pulse and the
    `alightHere` star (`tripPatchHere`).
  - **`token_layer.dart`:** `MoneyNote` (h 26, min-w 42, radius 7, digits 16/700), in its kind's
    `money_note` colours, along the hop on a slight arc.
  - **`bubbles_layer.dart`:** `SpeechBubble`, with its variants, tail, lips from `design_extras`, the
    clamp, at most 2, and kept out of the top 56 pt in story trips.
  - **`hit_areas.dart`:** hit rects from `SeatLayout.hit`, and the FR-036 labels.

  `banner.dart`, `choices_layer.dart`, `story_strip.dart` and `hint_layer.dart` are US4's.
- [X] T073 [US3] Restyle the dashboard in `apps/mobile/lib/features/trip/presentation/dashboard/`:
  - **`dashboard.dart`:** 258 tall, radius 28 at the top, `dashboard.bg`, rows at 12, 62, 112, 162 and
    212.
  - **`hand_slot.dart`:** `HandSlot` with its dashed `sun` ring, mini notes and coins, `= total`,
    «فاضية» and break mode, the `sun` «رجّع» pill at its end side for the engine's undo window, and
    `CallChangeButton` (`AppButton.sun` 44 with `tripBreakButton` and «×٢»; disabled at 0).
  - **`tray.dart`:** `ChangeTray`, 4×2 `TrayCell`s with their four states.
  - **`boosters_row.dart`:** four `BoosterButton`s with their badges. The ad badge isn't drawn
    (FR-029).
  - **`talk_log_view.dart`:** `LastWordsLog`, two lines, still the only live region.

  Text clamps through `TripTextScale`.
- [X] T074 [US3] Lay out the zones in `apps/mobile/lib/features/trip/presentation/trip_screen.dart`:
  - `T = screenTopInset(context)`, the same helper as every other screen;
  - `TripHud` 114, the gap and the scene from `TripZones`, and the dashboard over the scene's last
    16 pt;
  - centred at 390 over 430 pt wide, with the cabin drawn to the full width behind;
  - `scene/trip_game.dart` reads the new `SceneLayout`.

  T059, T060 and T061 pass.
- [X] T075 [US3] Regenerate the trip goldens: `fvm flutter test --update-goldens test/goldens/trip
  test/goldens/design/c_trip_goldens_test.dart`. Review each against `C-Trip.png` and fix widgets
  until only research R1's expected differences remain.
- [X] T076 [US3] Run the behaviour gates unchanged:
  - `fvm flutter test test/features/trip/scripted_player_test.dart` (58 fixtures, SC-003);
  - `test/features/trip/kill_rebuild_test.dart`;
  - `test/features/trip/who_paid_frames_test.dart`;
  - `test/features/trip/dispute_screen_way_test.dart`;
  - `test/features/trip/channels_test.dart`;
  - all of `test/features/trip/presentation/`.

  Any failure is fixed in `lib/`, never in an assertion.

**Checkpoint**: A full trip plays in the new look on both phone sizes, with every outcome unchanged.

---

## Phase 6: User Story 4 - Events, choices, story trips and hints in the new look (Priority: P2)

**Goal**: Banners, the fare increase, the ledger badges, claims and the dispute, fallen notes, story
trips and بلية's hints in the design's look (spec FR-021, FR-023, FR-025, FR-026).

**Independent Test**: Play `line_gamaa.01` (the bump), `line_hay.02` (traffic and the dispute),
`line_hay.03` (the story) and M02's event test trips. Compare with `TripEvents.png`, `StoryTrip.png`
and `Tutorial.png`'s hint.

### Tests for User Story 4 (write first, must fail)

- [X] T077 [P] [US4] Create `apps/mobile/test/features/trip/presentation/trip_events_design_test.dart`:
  - **`EventBanner`:** it slides down over the back window, is announced once, and hides after 4 s;
    under reduced motion it fades.
  - **The ledger peek.** The tags are replaced by `LedgerBadge`s («دافع» `primary`/white, «لسه»
    `danger`/ink, «على صاحبه» white/ink) for the whole `booster_ledger_peek_ms`. The booster shows its
    seconds-left badge. The front seat's badge sits where its tag sits.
  - **«أنا دافع!».** A `ChoicePopover` next to the passenger, two 44 pt buttons, and the engine keeps
    running.
  - **The dispute.** Two 56 pt faces, and the trip pauses (M02 unchanged).
  - **A fallen note.** Its `sun` ring and a 44×44 hit area; tapping within the window collects it.
  - **«نزّلني هنا».** The star tag.
  - **A story trip.** The `StatusChip` «مشوار قصة» above the title, and the dark condition strip with
    `shield_check` and `tripStoryNoFights`, for the whole trip; no bubble enters its 56 pt.
  - **A hint.**
    - بلية's head at the bottom-end corner (96×110, overlapping the dashboard by about 30 pt);
    - a `SpeechBubble.character` with `tripHintSpeaker` and the hint;
    - the hand at the target rect;
    - no scrim, and taps reach the controls under it.
- [X] T078 [P] [US4] Create the artboard checks (contracts/design-checks.md "Skips and pairings"):
  - **`TripEvents`:** `apps/mobile/test/design/samples/trip_events.dart`,
    `test/design/trip_events_layout_test.dart` and `test/goldens/design/trip_events_goldens_test.dart`.
    Pair the tray cells labelled «×N» with the app's «<denomination>، معاك N» labels. The passengers
    aren't taps in this artboard, so their labels go in `appOnly`.
  - **`StoryTrip`:** the same three files, for `line_hay.03`-like content at the drawn moment, with the
    same pairings and `appOnly`.
  - **`Tutorial`:** `test/design/samples/tutorial_hint.dart` and `test/design/tutorial_layout_test.dart`.
    Only the 11 HUD and dashboard taps, plus بلية's head, his bubble and the hand checked as rects
    against HANDOFF `Tutorial` blocks 5–7. The scrim, the hole and the locked-boosters bar are M07's,
    so the four boosters and the two riders go in `appOnly`. Plus
    `test/goldens/design/tutorial_goldens_test.dart`.

### Implementation for User Story 4

- [X] T079 [US4] Add to `apps/mobile/lib/l10n/app_ar.arb`: `tripStoryChip` («مشوار قصة») and
  `tripHintSpeaker` («بلية»). Regenerate l10n.
- [X] T080 [US4] Restyle `apps/mobile/lib/features/trip/presentation/overlays/banner.dart` to use
  `EventBanner` over the back window (`danger`, the warning icon, `design_extras.bannerTitle`), with
  M02's text and timing rules.
- [X] T081 [US4] Add the ledger badges to `apps/mobile/lib/features/trip/presentation/overlays/patches_layer.dart`:
  while `PassengerView.ledgerBadge` is set, draw `LedgerBadge` in place of the `StationTag`. Make
  `boosters_row.dart`'s active badge count down the peek's seconds.
- [X] T082 [US4] Restyle `apps/mobile/lib/features/trip/presentation/overlays/choices_layer.dart` to
  `ChoicePopover` (white, radius 18, `LipTokens.popover`, «ماشي» on `ground` and «لأ، ما
  دفعتش!» on `danger` with ink text) placed beside the passenger. Restyle the dispute's two faces in
  `cards/dispute_card.dart` at 56 pt.
- [X] T083 [US4] Draw fallen notes in `token_layer.dart` (`MoneyNote.fallen` with its `sun` ring, a
  44×44 hit) and the `alightHere` star in `patches_layer.dart`.
- [X] T084 [US4] Story trips (research R11):
  - in `top_bar.dart`, show `StatusChip.story(tripStoryChip)` above the title when
    `TripView.storyCondition != null`;
  - restyle `overlays/story_strip.dart` as the dark strip (`dashboard.bg`, `shield_check` icon,
    `tripStoryNoFights`, white text), 56 pt, at the scene's top;
  - make `bubbles_layer.dart` keep bubbles below it.
- [X] T085 [US4] Restyle `apps/mobile/lib/features/trip/presentation/overlays/hint_layer.dart`
  (research R12, contracts/trip-layout.md "The hint"):
  - `CharacterAvatar` (new, `apps/mobile/lib/features/trip/presentation/scene/character_avatar.dart`,
    a Flutter widget drawing `assets/illustrations/characters/belya.svg` for now; US6 adds Rive) at
    `x = w − 102`;
  - a `SpeechBubble.character` with `tripHintSpeaker` over the hint text in `TypeTokens.quote`;
  - `assets/icons/hand.svg` at 56×64 pointing at the hint's target rect from the live layout;
  - wrapped in `IgnorePointer`.

  When and what M02's hints say is unchanged.
- [X] T086 [US4] Regenerate the trip and US4 artboard goldens: `fvm flutter test --update-goldens
  test/goldens/trip test/goldens/design/trip_events_goldens_test.dart
  test/goldens/design/story_trip_goldens_test.dart test/goldens/design/tutorial_goldens_test.dart`.
  Review against the PNGs. T077 and T078 pass, and T076's gates still pass.

**Checkpoint**: Every event, choice, story trip and hint shows in the new look; behaviour unchanged.

---

## Phase 7: User Story 5 - Pausing and failing in the new look (Priority: P2)

**Goal**: `Pause`, `Fail` and M02's other cards as the design's dialogs, with M02's behaviour (spec
FR-027 – FR-029).

**Independent Test**: Pause and fail sample trips with a test economy, revive once, fail again, and
compare with `Pause.png`, `Fail.png` and `States.png`.

### Tests for User Story 5 (write first, must fail)

- [X] T087 [P] [US5] Extend `apps/mobile/test/features/trip/domain/fail_summary_test.dart`
  (data-model.md "FailSummary"):
  - `brokeStoryRule` is true only for a story trip with `no_fights_required` that failed with
    `fights > 0`;
  - `angryFaces` holds up to 3 ids: `outcome == fight` first, then `missedStop`, then those aboard by
    seat order (`A_r` first);
  - the existing cause assertions are unchanged.
- [X] T088 [P] [US5] Create `apps/mobile/test/features/trip/presentation/cards_design_test.dart`:
  - **`Pause`:**
    - title and subtitle;
    - «كمّل المشوار» (60);
    - «عيد المشوار» with the fuel chip: a `sun` pill with «−١» and the fuel icon, whose screen-reader
      label is `tripPauseRestartCost` (HANDOFF §9.1 #4; no «لتر»);
    - «ارجع الموقف»;
    - two `AppSwitch`es that change `pref.trip_sound` and `pref.trip_haptics` at once;
    - back resumes.
  - **`Fail`:**
    - **Faces and title:** up to 3 angry faces in their looks, and the title.
    - **The reason chip:** M02's two causes joined, or `tripFailStoryRule` first for a broken story
      rule.
    - **The revive:** «صالح بـ{price} بون» and `tripReviveOnce` only when a revive is offered; after a
      revive or at the cap, both are hidden.
    - **The tiles:** both present.
    - **Dismissal:** back and the scrim do nothing.
    - **The ad slot:** the empty 66 pt slot above keeps the revive at y 398 on the reference frame.
  - **The other cards:** the booster purchase, the empty tank, the failed save and the dispute are
    `AppDialog`s in the spend-confirmation layout, with M02's buttons. The booster card's price says
    «بـN بون», and its balance and shortfall lines agree with the number («٣ بونات», «١٢ بون»).
  - **Behaviour:** `pause_card_test.dart` and `failure_card_test.dart` keep their assertions.
- [X] T089 [P] [US5] Create the artboard checks:
  - `apps/mobile/test/design/samples/{pause,fail,states}.dart`;
  - `test/design/{pause,fail,states}_layout_test.dart`. `Fail` skips the unlabelled 322×66 box at
    y 320 (the ad revive, M11). `States` composes every component of the artboard at 390×1400 and
    checks its 10 taps;
  - `test/goldens/design/{pause,fail,states}_goldens_test.dart`.

### Implementation for User Story 5

- [X] T090 [US5] Add `brokeStoryRule` and `angryFaces` to `FailSummary` and `failSummary(...)` in
  `apps/mobile/lib/features/trip/domain/fail_summary.dart`, from `TripFacts.storyNoFights`,
  `state.counters.fights` and the passengers' `outcome` and `presence`. T087 passes.
- [X] T091 [US5] Add to `apps/mobile/lib/l10n/app_ar.arb`:
  - `pauseSubtitle`: «الوقت واقف. الركاب مستنيينك.»;
  - `tripFuelChip`: «−{n}», with `n` a preformatted String. The chip shows it beside the fuel icon,
    never with «لتر» (HANDOFF §9.1 #4, which overrides the artboards' «−١ لتر»);
  - `tripReviveOnce`: «الصلح مرة واحدة في المشوار»;
  - `tripFailStoryRule`: «حصلت خناقة، والمشوار ده من غير خناقات».

  Regenerate l10n.
- [X] T092 [US5] Restyle `apps/mobile/lib/features/trip/presentation/cards/pause_card.dart` and
  `restart_button.dart` as `Pause` (research R13):
  - a 72×56 crop of `vehicles/microbus_old.svg`, `pauseTitle`, `pauseSubtitle`;
  - `AppButton.primary` with `pauseResume` (`design_extras.pauseButtonLabel`);
  - `AppButton.secondary` with `tripPauseRestart` and a `CostChip`: the `sun` pill with `tripFuelChip`
    and the fuel icon, labelled `tripPauseRestartCost` for screen readers. With an empty tank it shows
    `tripPauseRestartEmpty`, as M02 does;
  - `AppButton.tertiary` with `pauseHome`;
  - two `AppSwitch` rows, `tripPauseSound` and `tripPauseHaptics`.

  Every callback is M02's.
- [X] T093 [US5] Restyle `apps/mobile/lib/features/trip/presentation/cards/failure_card.dart` as `Fail`:
  - the `angryFaces` in `impatient_2` art;
  - `tripFailTitle` (`design_extras.failTitle`);
  - the reason chip;
  - an empty `SizedBox` of `RewardedAdButton`'s height where the ad revive goes (M11);
  - the BONAT revive (`AppButton.primary` with `tripFailRevive`) and `tripReviveOnce` when
    `FailSummary.revive != null`;
  - the two tiles: «عيد المشوار» with the same `CostChip` as `Pause`, and «ارجع الموقف»;
  - shown with `barrierDismissible: false` and back blocked, as M02.
- [X] T094 [US5] Restyle `apps/mobile/lib/features/trip/presentation/cards/trip_card.dart` on
  `AppDialog` (radius `design_extras.dialogRadius`, padding 20), and with it `booster_card.dart`,
  `no_fuel_card.dart`, `retry_card.dart` and `dispute_card.dart`'s frame in the `States`
  spend-confirmation layout. Their actions are unchanged, and their texts change only by the BONAT
  wording task in US3.
- [X] T095 [US5] Regenerate the trip and US5 artboard goldens: `fvm flutter test --update-goldens
  test/goldens/trip test/goldens/design/pause_goldens_test.dart
  test/goldens/design/fail_goldens_test.dart test/goldens/design/states_goldens_test.dart`. Review
  against the PNGs. T088 and T089 pass, and T076's gates still pass.

**Checkpoint**: Every trip card is in the new look; pause, revive and failure behave as before.

---

## Phase 8: User Story 6 - Passengers and characters in the new art (Priority: P2)

**Goal**: The owner's Rive file (`wassal.riv`) drawn to the new contract, with one pose per passenger, triggers
from the engine's events, the static art as fallback, and an art tier for performance (spec FR-030 –
FR-035).

**Independent Test**: With the owner's files, the contract test and the Rive goldens pass; renaming a
file falls back to static art and the trip plays the same; the A06 run meets the budget.

### Tests for User Story 6 (write first, must fail)

- [X] T096 [P] [US6] Create `apps/mobile/test/features/trip/domain/poses_test.dart`
  (contracts/rive-characters.md "Poses"): each of the 9 rows picks its pose, and a view matching
  several rows takes the first. Examples: asleep and talking → `sleep`; `claimOpen` and mood 2 →
  `claim`; a failed trip → `impatient_2`; waking → `sleep`.
- [X] T097 [P] [US6] Extend `apps/mobile/test/features/trip/domain/cues_test.dart`: `mapCues` adds a
  `CharacterCue` for each event:
  - `PassengerBoarded` → `board`;
  - `PassengerAlighted` → `alight`;
  - `PassengerCalled` → `call`, but none when `PassengerAttentive` is in the same batch;
  - `PassengerWoke` and `PassengerAttentive` → none (the file plays them from the view);
  - `ChangeDelivered` with `exact` → `happy`;
  - and beside each `HighlightCue`, `targeted`.

  Existing cue assertions are unchanged.
- [X] T098 [P] [US6] Extend `apps/mobile/test/features/trip/domain/passenger_view_test.dart`:
  `claimOpen` is true exactly while `state.claims` holds the passenger. Every other field is
  unchanged.
- [X] T099 [P] [US6] Rewrite `apps/mobile/test/features/trip/presentation/passenger_art_test.dart`
  against a fake `CharacterInstance`:
  - `look` is set once, from `Look.rive`;
  - on every view change, the pose's one input is set and the others cleared, as
    contracts/rive-characters.md "From a pose to the inputs" lists (`asleep` false while waking), and
    `headphones` follows the view;
  - each `CharacterCue` fires its trigger once;
  - without `Person` in `RiveArt.usable`, and under reduced motion, passengers use `SvgPassengerArt`;
  - `ArtTier.nearRive` makes rows B and C static, and `static` makes every seat static.
- [X] T100 [P] [US6] Create the Rive tests (tag `rive`), replacing
  `apps/mobile/test/features/trip/rive_character_contract_test.dart` and
  `rive_character_goldens_test.dart`:
  - **`apps/mobile/test/features/trip/rive_art_contract_test.dart`:** every artboard of
    contracts/rive-characters.md with its size and state machine, and each view model as the
    artboard's default with every property and type.
  - **`apps/mobile/test/features/trip/rive_art_goldens_test.dart`:**
    - one sheet per MVP look: `idle`, `talk`, `impatient_2`, `sleep`, `headphones`, `fight` and
      `claim`, at 84 and 52.5 pt;
    - one sheet of the six characters in `idle` and `talk`;
    - one of the four vehicles in `idle`.

  Images go in `apps/mobile/test/features/trip/goldens/`, drawn with `Factory.flutter`.
- [X] T101 [P] [US6] Extend `apps/mobile/test/bootstrap/boot_progress_test.dart`: the `art` step comes
  last, `value` = done / 6, and a missing Rive file doesn't fail boot (it records a problem).

### Implementation for User Story 6

- [X] T102 [US6] Create `apps/mobile/lib/features/trip/domain/poses.dart`: `enum CharacterPose`,
  `enum CharacterTrigger` (the file's triggers: `board`, `alight`, `call`, `happy`, `targeted`), and
  `CharacterPose poseFor(PassengerView view, {required bool failed})`. T096 passes.
- [X] T103 [US6] In `apps/mobile/lib/features/trip/domain/cues.dart`, add `final class CharacterCue
  extends TripCue { String passengerId; CharacterTrigger trigger; }` and produce it in `mapCues` as
  T097 lists. T097 passes.
- [X] T104 [US6] Add `final bool claimOpen` to `PassengerView` in
  `apps/mobile/lib/features/trip/domain/trip_view.dart` (with its `fields` entry), and set it in
  `projection.dart` from `state.claims.containsKey(p.passengerId)`. T098 passes.
- [X] T105 [US6] Create `apps/mobile/lib/features/trip/presentation/scene/rive_art.dart`:
  - `RiveArt` (data-model.md) and `@Riverpod(keepAlive: true) Future<RiveArt> riveArt(Ref ref)`;
  - it loads `assets/rive/wassal.riv` with `File.asset(…, riveFactory: Factory.flutter)`;
  - each artboard is checked against the contract's size, state machine and view-model properties;
    those that pass go in `usable`, and each problem is added to `problems`;
  - a file that fails to load becomes null.

  Add the `art` step to `appStartup` and `BootProgress` in `apps/mobile/lib/bootstrap/startup.dart`,
  awaiting `riveArtProvider.future` (it never throws). T101 passes.
- [X] T106 [US6] Rewrite `apps/mobile/lib/features/trip/presentation/scene/rive_passenger_art.dart`
  as `RivePassengerArtFactory implements PassengerArtFactory` over `RiveArt.file`:
  - per passenger, an instance of `Person`, its `Passenger` state machine, and a bound `Passenger`
    view-model instance;
  - `look` set once from `Look.rive`;
  - on each view change, the inputs of `poseFor`'s pose (the contract's table) and `headphones`;
  - triggers on each `CharacterCue`;
  - everything disposed on leaving;
  - a seat the tier makes static delegates to `SvgPassengerArtFactory`.

  In `apps/mobile/lib/features/trip/trip_providers.dart`, replace `passengerRiveProvider` with
  `riveArtProvider`. `passengerArtProvider` picks the Rive factory when `Person` is in
  `RiveArt.usable` and reduced motion is off, and the SVG one otherwise. Route `CharacterCue`s from `scene/trip_game.dart` to the passenger's art.
  T099 passes.
- [X] T107 [US6] Create `apps/mobile/lib/features/trip/application/art_tier.dart`:
  - `enum ArtTier { rive, nearRive, static }`;
  - a `@riverpod class ArtTierSetting`, defaulting to `rive` (or `nearRive` if T111 says so),
    session-only;
  - in `apps/mobile/lib/features/trip/presentation/playtest/debug_panel.dart`, the tier switch and
    the `RiveArt.problems` list, dev and staging only.
- [X] T108 [US6] Add Rive to the other art, with the SVG kept as fallback:
  - `CharacterAvatar` (`character_avatar.dart`): `Person` with the character's `look`, `talking` off
    or on;
  - `VehicleSprite` (new `apps/mobile/lib/core/theme/components/vehicle_sprite.dart`): `Vehicle` with
    its `look` and `driving` on. `boot_screen.dart` uses it for the loading vehicle;
  - the hint's pointer uses `CoachHand`;
  - `MicrobusLoader` uses `LoadingWheel`.

  Rive widgets use `RiveWidget` with `Factory.flutter`.
- [X] T109 [US6] Retire M02's single file:
  - delete `apps/mobile/assets/rive/passenger.riv`, `passengerRiveAsset` and the old view-model code
    in `rive_passenger_art.dart`, `test/features/trip/rive_character_contract_test.dart`,
    `rive_character_goldens_test.dart` and their PNGs;
  - in `.github/workflows/mobile.yml`'s `update-goldens` job, run
    `test/features/trip/rive_art_goldens_test.dart` in place of `rive_character_goldens_test.dart`.
- [ ] T110 [US6] **Owner:** `apps/mobile/assets/rive/wassal.riv` was delivered on 2026-10-23 and the
  contract revised to it. Still to do (contracts/rive-characters.md "Open"):
  - add the `reducedMotion` Boolean to `Passenger`, and decide on `skinTone`;
  - review the Rive goldens (generated on Linux with `fvm flutter test --update-goldens
    test/features/trip/rive_art_goldens_test.dart`);
  - the export stays on the free plan (the owner's decision of 2026-10-23, research R15); the file
    is 86 KB.

  T100 passes.
- [ ] T111 [US6] **Owner, on the Galaxy A06:** run `tool/perf/trip_fps.sh com.wassalogra.app.dev
  line_gamaa.02` on the `rive` tier (quickstart "Owner checks" 2), and record the average fps, the
  worst one-second window, memory and p90 frame time in research.md R18. If it misses the gate, run it
  on `nearRive`, record that too, and set `ArtTierSetting`'s default to `nearRive`.

**Checkpoint**: Every passenger and character is drawn by Rive in the new style, falls back cleanly,
and meets the A06 budget.

---

## Phase 9: User Story 7 - The design stays the reference (Priority: P3)

**Goal**: The checks catch any drift between the app and the design, and later features follow the
same routine (spec US7, FR-039 – FR-041).

**Independent Test**: Move one box in a copy of a `boxes/` file and see the layout test fail; change a
token and see the goldens move.

- [X] T112 [P] [US7] Create `apps/mobile/test/design/drift_detection_test.dart`:
  - load `C-Trip`'s boxes with `parseBoard`, move box 1 (pause) by 3 pt, and check that
    `expectLayoutMatches` over the `C-Trip` sample fails naming box 1;
  - remove a box and check that the now-unmatched control fails;
  - generate tokens from a copy of `tokens.json` with `color.primary` changed, and check that the
    output differs from the committed file in exactly the `primary` lines.
- [X] T113 [P] [US7] Add a "Checking a screen against the design" section to `docs/design/README.md`:
  the sample builder, the golden under `test/goldens/design/`, the layout test with its skips and
  pairings, `--dart-define=DESIGN_COMPARE=true`, and the expected-differences list in the PR. Link to
  `specs/008.5-m21-design-refresh/contracts/design-checks.md`.
- [X] T114 [US7] Run `fvm flutter test test/design --dart-define=DESIGN_COMPARE=true`, and check that
  `apps/mobile/build/design_compare/` holds one image per artboard in scope: `Loading`, `C-Trip`,
  `TripEvents`, `StoryTrip`, `Tutorial`, `Pause`, `Fail`, `States`, `Components` and `Tokens`, in
  both digit styles. `apps/mobile/.gitignore` already ignores `/build/`, so nothing is committed.

**Checkpoint**: Every in-scope artboard has a golden, a layout test and a compare image.

---

## Phase 10: Polish & Cross-Cutting Concerns

**Purpose**: Remove what this feature retires, update the docs, and run every gate.

- [X] T115 Create `apps/mobile/test/repo/no_retired_design_test.dart` (spec SC-008). No file in
  `apps/mobile/lib/`, `apps/mobile/pubspec.yaml` or `apps/mobile/assets/` names `Lalezar`,
  `BalooBhaijaan2`, `StickerButton`, `StickerCard`, `PrimaryButton`, `SecondaryButton`,
  `WassalBottomBar`, `StickerPage`, `StickerColors`, `StickerType`, `StickerShape`, `StickerSpace`,
  `StickerMotion`, `StickerTokens`, `stickerTokens`, `StandInPassenger`, `passenger.riv` or `SkinLook`.
  It must fail now.
- [X] T116 Extend `apps/mobile/test/repo/no_raw_style_values_test.dart` (spec SC-002) with these rules
  for UI code (`lib/core/theme/components/`, `lib/core/routing/`, `lib/features/*/presentation/`,
  `lib/features/boot/`, `lib/features/settings/`, `lib/features/dev/`):
  - `'numeric font size': RegExp(r'fontSize:\s*[0-9.]')`;
  - `'literal shadow': RegExp(r'BoxShadow\(')`, since lips come from `LipTokens`;
  - the radius rule widened to `RegExp(r'(Border)?Radius\.circular\(\s*[0-9.]')`;
  - `'literal animation duration': RegExp(r'duration:\s*(const\s+)?Duration\(')`;
  - `'literal curve': RegExp(r'curve:\s*Curves\.')`.

  `lib/core/theme/tokens/` and `lib/l10n/generated/` stay excluded. The trip's named motion constants
  in `lib/features/trip/presentation/trip_motion.dart` are allowed, since they're named, not inline.
  Plain `Duration` values that aren't motion (timers, countdown samples, the exit window) aren't
  matched. Self-tests: one sample line per rule is caught, and `MotionTokens.press` is not. Fix every
  hit in `lib/` by moving the value to a token, an extra or `trip_motion.dart`.
- [X] T117 Delete what T115 names:
  - `apps/mobile/lib/core/theme/tokens/legacy/`;
  - `lib/core/theme/components/{sticker_button,sticker_card,primary_button,secondary_button,wassal_bottom_bar,new_dot}.dart`,
    after moving any remaining user to its replacement;
  - `StickerTokens` and its registration in `app_theme.dart`;
  - `test/core/theme/{components_test,legacy_palette_test,legacy_tokens_test}.dart`, and
    `test/core/routing/new_dot_test.dart` after moving its assertions to `pills_test.dart`;
  - the `Lalezar` and `BalooBhaijaan2` families in `pubspec.yaml`, and
    `assets/fonts/{Lalezar-Regular.ttf,BalooBhaijaan2-VariableFont_wght.ttf,OFL-Lalezar.txt,OFL-BalooBhaijaan2.txt}`.

  T115 passes.
- [X] T118 Run the guards: `no_raw_style_values_test.dart`, `no_ink_test.dart` (empty allow-list),
  `no_arabic_literals_test.dart`, `trip_text_in_canvas_test.dart`, `no_ads_in_trip_test.dart`,
  `domain_imports_test.dart`, `integer_money_test.dart`, `design_tokens_test.dart` and
  `design_assets_test.dart`. Fix `lib/` until all pass.
- [X] T119 [P] Update `docs/architecture-mobile.md` (spec FR-043):
  - **§2:** `flutter_svg`.
  - **§5:** `assets/{fonts,rive,icons,illustrations}`, `tool/design/`, `lib/core/theme/{tokens,components}`
    and `lib/features/dev/gallery/`.
  - **§8:**
    - the zones and geometry: the crop, the front seat at the edge, the threshold `inset + 764` and
      the continued exception;
    - the Rive file, its `Person` artboard and `look` numbers, poses from the view set as one input,
      and triggers from events;
    - the static fallback and the art tiers.
  - **§20:** the artboard goldens and layout tests, and the design guards.
- [X] T120 [P] Update `CLAUDE.md`:
  - **Rive.** Replace the `passenger.riv` bullet with `wassal.riv`, its contract
    (`specs/008.5-m21-design-refresh/contracts/rive-characters.md`), `fvm flutter test --tags rive`
    and the Rive golden command.
  - **Commands.** Add `fvm dart run tool/design/gen_tokens.dart` and `fvm dart run
    tool/design/sync_assets.dart` to the mobile commands table.
  - **Guards.** Add the design guards to the guard list.
  - **UI rules.** Change "which the app keeps until 008.5" to past tense.
- [X] T121 [P] Add a first line to `specs/008-m02-trip-screen/contracts/scene-layout.md`,
  `specs/008-m02-trip-screen/contracts/rive-character.md` and
  `specs/001-m03-app-shell/contracts/design-tokens.md`: `> **Superseded by**` the matching contract in
  `specs/008.5-m21-design-refresh/contracts/` (trip-layout.md, rive-characters.md, design-tokens.md),
  "from M21".
- [ ] T122 [P] Update `docs/delivery-plan.md`: tick Step 5.5 in the Progress list with the PR number
  once merged. Under M07's "Handed over" item, add the new threshold (`inset + 764` pt) and the 360×640
  golden to aim for.
- [X] T123 [P] Add the M21 section to `docs/owner-actions.md`, split into before and after merge, each
  with its task ID: T110 (the Rive files), T111 (A06 frame rate), T124 (cold start), T125 (download
  size), T126 (side-by-side review). Update the "Open now" table.
- [ ] T124 **Owner, on the Galaxy A06:** `tool/perf/cold_start.sh com.wassalogra.app.dev 10`: no white
  frame, and Home in under 3 s (SC-006). Paste the output in the PR.
- [ ] T125 **Owner:** build the release app bundle (`fvm flutter build appbundle --flavor prod
  --release`, written to `apps/mobile/build/app/outputs/bundle/prodRelease/`) and check the arm64
  download with `bundletool get-size total`: under 80 MB (SC-009). Paste the output in the PR.
- [ ] T126 **Owner:** review each compare image in `apps/mobile/build/design_compare/` (from T114)
  against its `docs/design/png/<Artboard>.png`, and accept it or list changes (SC-010).
  `specs/008.5-m21-design-refresh/contracts/design-checks.md` "What a golden may differ in" lists the
  expected differences.
- [X] T127 Run the full mobile gate from `apps/mobile`, in CI's order:
  - `fvm flutter pub get`;
  - `fvm dart run build_runner build -d`;
  - the format check;
  - `fvm flutter analyze --fatal-infos`;
  - `fvm dart run rive_native:setup --verbose --clean --platform linux`;
  - `fvm flutter test --coverage`;
  - `fvm dart run tool/check_coverage.dart --min 80`.

  Then run quickstart.md's scenarios 1–9 on a dev build.
- [X] T128 Write the PR description:
  - the conflict table from `specs/008.5-m21-design-refresh/research.md` R1 (FR-004);
  - each existing test whose finder changed (Tests note above);
  - the expected golden differences;
  - the compare images;
  - the measurements from T110, T111, T124 and T125.

**Added during implementation (2026-10-23): the brand.** The owner added the brand page «العلامة
والأيقونة» to the design canvas (artboards `IconOptions`, `IconKit`, `Logo`, `FeatureGraphic`). The
app still shipped Flutter's default launcher icon. Run T127's gate again after these.

- [X] T129 [P] Snapshot the brand into `docs/design/brand/`: the four artboards' HTML (as `export.py`
  writes artboards), the icon kit's layers as SVG (`icon_master`, `adaptive_background`,
  `adaptive_foreground` without the board's guides, `monochrome` as a single-colour shape on
  transparent, `notification`), the logo's mark, and a `README.md` naming direction أ as the chosen
  icon and the logo's rules (clear space, smallest sizes, don'ts). Link it from `docs/design/README.md`.
- [X] T130 The launcher icon from `docs/design/brand/` (direction أ):
  - Android: `mipmap-anydpi-v26/ic_launcher.xml` with the background, foreground and monochrome
    layers (108 dp, PNG per density), and the legacy `ic_launcher.png` per density from the master;
  - iOS: every size in `ios/Runner/Assets.xcassets/AppIcon.appiconset/` from the master, opaque;
  - a repo test that each density's files exist at their sizes and that the adaptive icon names its
    three layers;
  - the notification glyph stays in `docs/design/brand/` until the push feature (M14) wires it.
- [X] T131 [P] Add to the M21 section of `docs/owner-actions.md`: upload the 512×512 store icon and
  the 1024×500 feature graphic (`docs/design/brand/`) to the Play Console listing, and check the
  launcher icon on the A06's home screen in each of its shapes.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1):** no dependencies. T002–T005 run in parallel after T001.
- **Foundational (Phase 2):** after Setup. T006 first, alone, because it touches 61 files. Then
  T007–T011 in parallel, except T008, which needs T007.
- **US1 (Phase 3):** after Foundational. **Every later story depends on US1**: it creates the tokens
  and components they use.
- **US2 (Phase 4):** after US1. It switches the app's theme.
- **US3 (Phase 5):** after US1. It can run alongside US2, except for the shared files (`app_ar.arb`,
  `app_theme.dart`); if both run, US3's goldens are regenerated after T046.
- **US4 (Phase 6) and US5 (Phase 7):** after US3, since they restyle widgets inside the trip screen US3
  lays out. US4 and US5 touch different files, except `app_ar.arb` and `dispute_card.dart` (T082, then
  T094).
- **US6 (Phase 8):**
  - T096–T104 after US3;
  - T105 after US2 (`startup.dart`);
  - T108 after US2 and US4 (the loading vehicle, the hint);
  - T110 needs the owner's files;
  - T111 needs T110.
- **US7 (Phase 9):** after US3 (it uses the `C-Trip` sample).
- **Polish (Phase 10):** after all stories. T115 before T117, and T116 before T118 (the guard run).

### Within Each User Story

- Tests are written first and fail, then the implementation makes them pass.
- ARB keys before the widgets that use them.
- Domain (`scene_layout`, `looks`, `poses`, `fail_summary`) before the widgets that read it.
- Goldens are regenerated last in each story, and reviewed.

### Parallel Opportunities

- Setup: T002, T003, T004, T005.
- Foundational: T007, T009, T010, T011.
- US1: every test task T012–T024; then the component files T030–T036 after T029.
- US2: T040–T044.
- US3: T057–T061; T070 alongside T069.
- US4: T077, T078. US5: T087–T089. US6: T096–T101.
- US7: T112, T113.
- Polish: T119–T123.

---

## Parallel Example: User Story 1

```bash
# The tests, all at once (different files):
T012 test/tool/token_generator_test.dart
T013 test/repo/design_tokens_test.dart
T014 test/core/theme/design_palette_test.dart
T015–T021 test/core/theme/components/*_test.dart
T022 test/features/dev/gallery_test.dart
T023 test/design/samples/{components,tokens}.dart + their goldens and layout test
T024 test/goldens/components/components_goldens_test.dart

# After T029 (Pressable), the component files, all at once:
T030 buttons.dart   T031 pills.dart   T032 controls.dart   T033 containers.dart
T034 overlays.dart  T035 nav.dart     T036 story.dart
```

## Parallel Example: User Story 3

```bash
# After T056 (helpers), the tests, all at once:
T057 scene_layout_test.dart   T058 looks_test.dart   T059 trip_minimum_sizes_test.dart
T060 C-Trip sample, layout test, golden test        T061 trip_design_test.dart
```

---

## Implementation Strategy

### MVP First (User Stories 1–3)

1. Setup and Foundational: the legacy rename changes nothing on screen.
2. US1: the tokens and components, visible in the gallery. Stop and validate: the gallery against
   `Components.png`.
3. US2: the frame. Stop and validate: cold start and navigation.
4. US3: the trip. Stop and validate: the scripted fixtures and the `C-Trip` golden.

At this point the app is fully in the new look on the static art, and every behaviour test passes.

### Incremental Delivery

1. US4, then US5: every trip moment and card.
2. US6 when the owner's files arrive: Rive in every seat, the A06 run.
3. US7: the drift checks and the routine for later features.
4. Polish: removals, docs, owner checks, then the PR.

### Notes

- Tasks marked [P] touch different files and don't depend on unfinished tasks.
- Commit after each task or a small group of them; T006 is a commit on its own.
- A golden is never regenerated to make a failing behaviour test pass.
- The feature merges as one PR, after T110 (the Rive files) and the owner checks T111, T124–T126.
