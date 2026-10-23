# Research: Design Refresh (M21)

Phase 0 of the plan. Each section gives the decision, why it was made, and what was rejected.
Versions were checked on pub.dev and the Google Fonts repository on 2026-10-23. Flutter is 3.47.7
(`.fvmrc`).

| Dependency | Version | Kind | Why |
| --- | --- | --- | --- |
| `flutter_svg` | `^2.3.0` | runtime (new) | The design's icons and illustrations, and the static art fallback (R17). Needs Flutter ≥ 3.35. |
| `rive` / `flame_rive` | unchanged (`^0.14.11` / `^1.11.2`) | runtime | The owner's new files, as M02's research R1 set up. |
| Marhey | `Marhey-VariableFont_wght.ttf` (variable, 300–700) | font (new) | Display and buttons (R3). OFL. |
| Readex Pro | `ReadexPro-VariableFont_HEXP_wght.ttf` (variable, 160–700) | font (new) | Text and numbers (R3). OFL. |

Nothing is removed from the dependency list. Lalezar, Baloo Bhaijaan 2 and `passenger.riv` leave the
assets (R22).

## R1. What wins when the handoff and the project disagree

**Decision.** `docs/design/README.md`'s overrides, applied as follows. Each row is a conflict found
while planning, with its outcome. The PR description repeats this table (spec FR-004).

| Topic | Handoff | Outcome | Why |
| --- | --- | --- | --- |
| Animation runtime | Lottie (§6) | Rive (R15) | Constitution, locked stack |
| Vehicle and passenger ids | `microbus_old`, `hagga`, … | Art names; glossary ids stay (R14) | Glossary §3.6 |
| Choices pausing the trip | Pause on every popover | Only the dispute pauses | M02 clarification |
| «عيد المشوار» | Via the pre-trip card | Restart directly for a liter | M02 FR-011; the pre-trip card is M08's |
| Buying a booster with none left | Spend, then a 3 s undo toast | M02's confirmation card | 008.5 clarification |
| Ledger badges | 5 s | The whole peek, 10 s | 008.5 clarification |
| Ad revive, «زحمة» ad badge | Drawn | Not shown until M11 | Constitution IX, M02 FR-047 |
| Station colours | By order on the line | By alighting order in the trip | M02 FR-020; spec FR-009 |
| Station letters | First letter of the name | أ ب ج د by alighting order | M02 R16: never two stops with one letter (المستشفى, المدرسة) |
| Trip scene | 390×444, scaled to fit | Points; x spreads, sizes don't scale (R7) | Constitution XI on 360-wide phones |
| Text scale in the trip | 1.15 in HUD, dashboard, tags | Adopted (R8) | Fixed cells; 1.3 elsewhere (M03) |
| Short screens | Crop the wall, then scale | Crop up to 36 pt; below, M02's exception until M07 | 008.5 clarification |
| Story trips | Front-seat character, story title, «أبو العروسة شاف خناقة» | Chip and condition strip only (R11) | Content has no character or title (no schema change, FR-003) |
| Abandoned trip's fuel | "Refund is open" | No refund | M05 spec, M02 US2 |
| Tutorial coach, locked boosters bar | Drawn | M07's | Delivery plan |
| Light garland | Drawn | Not drawn | A phase 2 cosmetic |
| Passengers' screen-reader labels | The type and who owes («المستعجل، … ليه باقي», «الشلة») | The look and the stop; «ليه باقي» only while the tag is hot (spec FR-036) | M02 FR-033: hidden types and payments stay hidden |

**Rejected.** Following the handoff on behaviour, as its §0 says ("this document wins"). It was
written against the architecture docs as they stood before M01, so its behaviour notes undo decisions
the merged features made with the owner.

## R2. Tokens from `tokens.json`

**Decision.**

- **A generator in Dart**, `apps/mobile/tool/design/gen_tokens.dart`, reads `docs/design/tokens.json`
  and writes `lib/core/theme/tokens/design_tokens.dart`, which is committed with a "generated, do not
  edit" header. A repo test, `test/repo/design_tokens_test.dart`, runs the generator in memory and
  fails on any difference, like `codegen --check` does for content. It runs in `flutter test`, so no
  job is added. The one CI change: the mobile workflow's path rule (its `changes` job) adds
  `docs/design/`, so a rebuilt design runs the token, asset and layout tests.
- **Names map one to one**, dotted keys in camelCase, into the project's token classes (M03's naming,
  not the handoff's `AppColors`):

  | `tokens.json` group | Dart |
  | --- | --- |
  | `color`, `dashboard`, `money_note`, `denomination`, `scene`, `character`, `station` | `ColorTokens` constants and the `WassalTokens` theme extension (`context.tokens.primaryLip`, `context.tokens.stations[0].bg`) |
  | `type` | `TypeTokens` (`TextStyle`s with family, weight, size, height and `leadingDistribution: even`) |
  | `radius` | `RadiusTokens` |
  | `lip`, `ring` | `LipTokens` (`BoxShadow`s, blur 0) and `RingTokens` (width, colour, inset, dashed) |
  | `space`, `layout` | `SpaceTokens`, `LayoutTokens` (frame, gutter, nav, the trip's zones and design seat table) |
  | `motion` | `MotionTokens` (`Duration` and `Curve`; `easeOutBack(k)` as an `EaseOutBack(k)` curve from the hand-written `tokens/curves.dart`) |

- **Skipped on purpose:**
  - `motion.moneyHop`, because hop times are the engine's `trip_hop_ms_<line_id>` tunables
    (constitution VIII);
  - `digits`, because the formatter owns digits (M03);
  - `font`, because the families are registered in `pubspec.yaml` (R3);
  - the `*_rules` and `*_note` strings, which are documentation.
- **Values between tokens** (the 60 pt wordmark, Pause's 23 pt button label, Fail's 30 pt title, the
  translucent bubble and tag lips, the dialog lip) go in a hand-written
  `lib/core/theme/tokens/design_extras.dart`. Each constant names its artboard, so no screen holds a
  raw value (spec FR-002). M03's guard, extended to font sizes, shadows, radii, animation durations
  and curves in UI code, finds none outside `tokens/` and the trip's named motion constants (SC-002).
- `colors.dart`, `typography.dart`, `shape.dart`, `space.dart` and `motion.dart` are replaced by the
  generated file and the extras. `app_theme.dart` builds `ThemeData` from them, with
  `splashFactory: NoSplash.splashFactory` (R4).

**Rationale.** Committing the output keeps `flutter analyze` and the IDE working on a fresh checkout,
without a build step, and the test stops drift. Keeping the `WassalTokens` extension keeps M03's
`context.tokens` pattern and its tests.

**Rejected.**

- `build_runner` generation into `*.g.dart`: those files are gitignored here, so CI would need a new
  step, and the IDE shows errors until it runs.
- The handoff's `AppColors`/`AppText` names: the project already uses the `*Tokens` names in 44 files.

## R3. Fonts

**Decision.** Bundle `Marhey[wght].ttf` as family `Marhey` and `ReadexPro[HEXP,wght].ttf` as family
`ReadexPro`, from `github.com/google/fonts` (`ofl/marhey`, `ofl/readexpro`), each with its `OFL.txt`,
as M03 did for its fonts. In the app they are named `Marhey-VariableFont_wght.ttf` and
`ReadexPro-VariableFont_HEXP_wght.ttf`: the asset bundle URL-encodes brackets in a file name, and the
test font loader can't find them that way. Both are variable fonts. Since Flutter 3.41, `FontWeight` drives the `wght`
axis (M03 research R6), so one file per family covers Marhey's 500–700 and Readex Pro's 400–700.
Readex Pro's `HEXP` axis stays at its default. Every `TextStyle` sets
`leadingDistribution: TextLeadingDistribution.even` (HANDOFF §2.2). Remove `Lalezar-Regular.ttf`,
`BalooBhaijaan2-VariableFont_wght.ttf` and their licences.

**Rationale.** Variable files are the smallest way to ship every weight the design uses. The fonts are
OFL, like the ones they replace. Without even leading, Marhey sits low inside buttons.

**Rejected.** The `screens/fonts/` woff2 subsets, which are browser-only and miss glyphs.
`google_fonts`, which downloads at runtime and breaks offline-first play (constitution V).

## R4. The component set

**Decision.**

- **Where.** `lib/core/theme/components/`, M03's folder (the handoff suggests `lib/core/ui/`), one file
  per family:
  - `buttons.dart`: `AppButton` in the variants `primary` (xl, l), `secondary`, `sun`, `danger` and
    `tertiary`, plus `RewardedAdButton` and `IconCircleButton`;
  - `pills.dart`: `CurrencyPill`, `CountBadge`, `NewDot`, `StatusChip`, `PriceTag`, `Stars`;
  - `controls.dart`: `AppSwitch`, `Segmented`, `AppTextField`;
  - `containers.dart`: `AppCard`, `ListRow`, `ProgressBar`, `ScreenHeader`, `EmptyState`;
  - `overlays.dart`: `AppSheet`, `AppDialog`, `EventBanner`, `OfflineBanner`, `UndoToast`, `AppToast`,
    `InlineAlert`, `StatusCard`;
  - `nav.dart`: `BottomNav`, `DailyCircle`;
  - `story.dart`: `ComicPanel`, `CoachMark`, `MicrobusLoader`.

  The trip's own components (HANDOFF §3.4) live in `lib/features/trip/presentation/`, next to what uses
  them (R10). M03's `sticker_button.dart`, `sticker_card.dart`, `primary_button.dart`,
  `secondary_button.dart` and `wassal_bottom_bar.dart` are deleted, and `new_dot.dart` is rewritten.
- **One press behaviour.** A `Pressable` base handles every tappable with a lip: it translates down by
  the lip while the lip goes to 0 over 80 ms (ease-out), and reverses on release. On press it calls
  `Haptics.selection()`, a new method on M02's interface (`HapticFeedback.selectionClick`), as
  HANDOFF §2.3 asks. It is silent when `pref.trip_haptics` is off, which is the app's only vibration
  switch until M14's settings screen.
  Disabled is 45% opacity, with no lip and no press. The theme sets `NoSplash`, and new components use
  `GestureDetector` plus `Semantics`, never `InkWell`.
- **Only tokens.** Components read `context.tokens`, `TypeTokens`, `RadiusTokens`, `LipTokens` and
  `MotionTokens`, and nothing else. Numbers from HANDOFF §3 come in through `LayoutTokens` or
  `design_extras.dart`.
- **Components that later features need are built now** (`RewardedAdButton`, `CurrencyPill`,
  `ComicPanel`, `DailyCircle` and the rest), with gallery entries and widget tests. A component no
  screen uses yet still has its gallery golden, so its features start from a tested part (spec US1).
- **The gallery** is `lib/features/dev/gallery/`. It is opened like M02's playtest tools: on dev and
  staging (`flavor != prod`), a button in the Home placeholder's playtest section pushes it as a plain
  page. It adds no route, so M03's route table and its test stay unchanged. It has two pages:
  - the components, each in every state, with RTL and a digit-style switch;
  - the tokens: swatches, the type scale, radii, lips, rings and motion.

  Its labels are English developer text, which the no-Arabic guard allows.

**Rationale.** It keeps M03's layout and guard, so later features have one place to look. A single
`Pressable` gives every button the same feel, and lets one test cover it.

**Rejected.**

- Restyling Material widgets through `ThemeData` alone: ripples, elevation and shapes keep leaking,
  and the lip press can't be expressed.
- A widgetbook package: it adds a dependency and a second app for something two pages cover.

## R5. The app's frame (what M03 built)

**Decision.**

- **`BottomNav`** replaces `WassalBottomBar`. It uses the icons `nav_home`, `nav_lines`,
  `nav_apartment` and `nav_shop`, tinted `icon.off`, and white in the active `primary` pill (60×34).
  Labels are 13 pt. The new-dots come from M03's `new_dot_providers`. Tabs cross-fade over 150 ms.
- **Placeholders** (`placeholder_screen.dart`) get a `ScreenHeader` (back control on the start side),
  the `ground` page and an `EmptyState` with the destination's name. Section placeholders show the
  bottom nav.
- **Sheets** (`sheet_page.dart`) become `AppSheet`: radius 28 top, a grabber, `close` at the end side,
  dismissal by dragging more than 25% down, flinging, ✕, system back or the scrim, entering over
  280 ms easeOutCubic and leaving over 200 ms easeInCubic. **Dialogs** become `AppDialog` (scale 0.92 →
  1 with a fade, 220 ms easeOutBack(1.2)). `sticker_page.dart` becomes `app_page.dart`, which keeps
  M03's under-⅓ s transitions and their reduced-motion rule.
- **The back-to-exit hint** becomes an `AppToast` (the `UndoToast` look without its action), shown in
  an overlay instead of a `SnackBar`.
- **Insets.** Screens use `max(MediaQuery.viewPadding.top, 24)` at the top, and the real bottom padding
  under the nav and sheet buttons (HANDOFF §2.4).
- **Settings** keeps M03's digit-style control as a `Segmented` in `primary`, inside a `ListRow` card,
  in the `Settings` artboard's look for that row. The rest of the artboard is M14's.

## R6. The loading screen

**Decision.**

- `BootScreen` becomes the `Loading` artboard: the `sun` ground with its two `sun.glow` circles and the
  cloud, the wordmark (Marhey 60 from `design_extras`) with its `sun.lip` text shadow, the tagline, the
  vehicle with its roof-sign overlay «الموقف», and the road-shaped `ProgressBar` with its line.
- **Progress** counts the boot steps that exist: the settings store, the tunables, the content pack, the
  database, the economy (`appStartup`'s `Future.wait`), then the art files (R15). Each finished step adds
  its share. The marker travels right to left, tweening linearly for at most 150 ms per update, and
  jumps under reduced motion. M06 adds its bootstrap call as one more step.
- **The vehicle** is `vehicles.riv`'s `microbus_old` in `drive`, entering from the right, with
  `illustrations/vehicles/microbus_old.svg` as its fallback (R17). The handoff's separate
  `ui/splash_drive` is not needed.
- **The line under the bar** is picked at random from a pool of ARB keys (`loadingLine1`, …), which
  starts with the one written line, «بنعدّ الفكة..». More lines are copy for the owner.
- **A failed boot** keeps M03's retry, shown as an `InlineAlert` (the `States` look) under the bar.
- **The native splash** stays `sun` (M03 FR-012), so the first frames match. Since 2026-10-24 its image
  is the launcher icon (direction أ) instead of M03's placeholder circle, written by
  `tool/design/gen_launcher_icons.sh` from `docs/design/brand/`, and Android shows it in portrait.

## R7. The trip's geometry

**Decision.** The design's coordinates become `SceneLayout`'s at the design size, and M02's rule stays:
scene units are points, so faces, tags and targets never scale on ordinary phones
([contracts/trip-layout.md](./contracts/trip-layout.md)).

- **Zones.** The top inset is `max(viewPadding.top, 24)` (in immersive mode that is the cutout),
  then the `TripHud` (114 pt), a gap (8 pt), the scene, and the `Dashboard` (258 pt, drawn over the
  scene's last 16 pt).
- **Height.** The scene is laid out from its bottom edge, so the near row stays by the dashboard.
  - A taller scene grows the cabin wall at the top.
  - A shorter one first loses the 8 pt gap, then crops the top of the cabin, by up to 36 pt. That
    cuts into the back window and the wall, never a face or a tag.
  - Under 408 pt (444 − 36), a scene of a screen shorter than about `inset + 764` pt (788 pt with a
    24 pt inset), the cropped scene scales down evenly. That is M02's approved exception, continued
    until M07 (Complexity Tracking).
  - The Galaxy A06 (360×800) gets a 420 pt scene with a 24 pt crop and no scaling, since its cutout is
    under 24 pt. An inset of up to 36 pt would still fit.
- **Width.** Seat anchors keep their y and spread in x by `w / 390`, where w is the scene's width,
  between 320 and 430 pt. Sizes don't change. The front seat is the exception: its x is kept from the
  end edge (`w − 40`), since its face already touches that edge in the design, and scaling it would
  push it off. At 360 pt it would show only 79 pt of face.
  - At 360 pt the near row's faces (84 pt, the rig's head at scale 1.0) sit 105 pt apart, and the back
    row's (52 pt, at 0.625) 64 pt apart.
  - Hit areas narrow to their seat spacing (never below 44 pt), and the front seat's wins over `A_r`
    as in M02.
  - Over 430 pt, the trip keeps the 390 design width, centred, with the cabin drawn wider behind it.
- **The seat table** is the handoff's §4.2 and `C-Trip` geometry, through `LayoutTokens.trip`:
  - `micro_old`: back `C` at y 92 (scale 0.625), middle `B` at 196 (0.8), near `A` at 308 (1.0), the
    front seat at (350, 392), and the driver's hand at (162, 398);
  - `tuktuk`: one near row at the `Tutorial` artboard's scale, 1.15, with its 3 seats (HANDOFF §5.5)
    at x 62, 195 and 328. Seats don't move with the number of riders, so `Tutorial`'s 2-rider drawing
    (x 118 and 270) isn't matched; that artboard's checks are M07's;
  - tags at `anchor + (−38, +46) × scale` (the front seat at (−32, +18));
  - the `C-Trip` table's hit areas.
- **Bubbles** sit with their tail tip 8 pt above the head, clamped 10 pt inside the scene. When the
  scene's top is cropped, a back-row bubble may overlap the top of its speaker's hair, but never the
  eyes. The condition strip's 56 pt top band is kept clear in story trips.

**Rationale.** It keeps every constitution XI minimum on the reference frame and the A06. Scaling the
390-wide scene to 360 would shrink faces to 48 and 77 pt. It also follows the design everywhere it
can. A 36 pt crop is the largest that cuts only wall and window. Laying out from the bottom matches
how the design stacks the zones.

**Rejected.**

- The design's uniform scaling (`s = min(w/390, h/444)`), which breaks XI on the reference device.
- M02's 110/230 bands, which no longer match the design's components.
- Dropping the HUD's inner gap or the station strip on short screens: that is a short-screen design,
  which is M07's (clarification).

## R8. Text scale

**Decision.**

- The trip's HUD, dashboard and station tags clamp text at **1.15×**, as HANDOFF §2.2 says.
- Every other text in the app, including the trip's cards, banners and dialogs, follows M03's 1.0–1.3×.
- Bubbles keep M02's fixed 16 pt, which is not scaled, so it never drops below the 15 pt minimum.
- Goldens run at 1.0 and 1.3, and check the clamp at 1.3.

**Rationale.** The station strip's labels sit at positions set by time, and the tray and booster cells
are 44 pt tall in a fixed grid. At 1.3× the strip's 12 pt names collide and the booster labels wrap
out of their cells, while at 1.15× they fit. Every text is still at least 12 pt at 1.0×. This narrows
M02 R15's trip-wide 1.3, as the spec's edge case allows.

**Rejected.** 1.3 across the trip, which overflows the drawn cells. A trip-wide 1.15, which would also
cap cards and dialogs that have room to grow.

## R9. The station strip

**Decision.**

- **M02's rules stay** (R16): colours by alighting order, the letters أ ب ج د, the fares with a raised
  fare, the countdown from `trip_station_warning_ms`, and the marker moving by the shifted `at_ms`.
- **What is redrawn is the design's look:**
  - the 6 pt `track` with its `primary` fill from the start end;
  - the depot dot and «الموقف»;
  - the 24 pt dots placed at `302 × at_ms / last at_ms` of the inner width;
  - the next stop's 3 pt `danger` ring (`ring.hot`) and its countdown chip, pulsing under 8 s;
  - passed stops at 35% with «عدّت»;
  - a raised fare drawn as the old price struck through, with the new price's `danger.soft` chip;
  - the vehicle marker (28×26, `sun`).
- **Long names.** Labels don't wrap, so a name too long for its slot is cut by the content rule the
  handoff notes. The app shows names as they come.

## R10. From M02's widgets to the design's components

**Decision.** The trip's structure, `TripScope`, `TripController` and the commands stay. Each widget
is redrawn as its design component:

| M02 | Becomes |
| --- | --- |
| `top_bar.dart`, `station_strip_bar.dart` | `TripHud` (`IconCircleButton` pause, title, `ReputationBar`), `StationStrip` (R9) |
| `scene/cabin_component.dart`, `windows_component.dart` | the `C-Trip` cabin: wall, floor, back window, side windows with the moving street, the next-station sign, benches (cached picture) |
| `scene/passenger_component.dart`, `passenger_art.dart`, `rive_passenger_art.dart` | `PassengerAvatar` with Rive art (R15) or static art (R17) |
| `scene/hand_component.dart` | the design's driver hand (sleeve, forearm, palm, thumb) |
| `overlays/token_layer.dart` | `MoneyNote` (fare, change, blocked with «؟», fallen with its ring, in hand) |
| `overlays/patches_layer.dart` | `StationTag` (sizes 24/26/30, `hot` ring and pulse, the «هنا» star) |
| `overlays/bubbles_layer.dart` | `SpeechBubble` (normal, warn, fight, thanks, character) |
| `overlays/choices_layer.dart` | `ChoicePopover`; the dispute's two 56 pt faces |
| `overlays/banner.dart` | `EventBanner` |
| `overlays/story_strip.dart` | the condition strip (R11) |
| `overlays/hint_layer.dart` | the coach hint (R12) |
| `dashboard/*` | `HandSlot` with the «رجّع» pill, `CallChangeButton`, `ChangeTray`/`TrayCell`, `BoosterButton`, `LastWordsLog` |
| `cards/pause_card.dart`, `failure_card.dart` | `Pause`, `Fail` (R13) |
| `cards/booster_card.dart`, `no_fuel_card.dart`, `retry_card.dart`, `dispute_card.dart`, `trip_card.dart` | `AppDialog` content in the spend-confirmation look |
| `trip_colors.dart`, `trip_text.dart`, `trip_motion.dart` | token-based, with the trip's motion constants from `MotionTokens` |
| `playtest/*` | shared components only |

The light garland is not drawn (a phase 2 cosmetic). Text never goes into the Flame canvas (M02's
guard stays).

## R11. Story trips (a correction to the spec)

**Finding.** Content gives a story trip only `kind: story` and `rules.no_fights_required`. There is no
character, title or condition text, and M02 handed the story character's comments to "story content
(M10 or the content pipeline)" (M02 research). The spec's FR-025, US4 scenario 6 and FR-027 assumed
more, which would need the schema change FR-003 forbids.

**Decision.** The spec is corrected:

- the HUD shows the `StatusChip` «مشوار قصة» above the trip's usual title;
- the dark condition strip at the top of the scene carries the shield icon and M02's ARB line «أي خناقة
  والمشوار يتعاد»;
- the front seat holds whoever the trip seats there;
- a failure under the rule reads «حصلت خناقة، والمشوار ده من غير خناقات» (a new ARB line,
  `tripFailStoryRule`), with no revive: the engine sets `revivable = false` (RULES §5).

The character's art (`characters.riv`) and the character bubble are built, and the gallery shows them,
so the story feature only has to fill them in. The hand-over stays M02's.

## R12. بلية's hints

**Decision.**

- Hints take the `Tutorial` artboard's coach look, without the scrim: بلية's head (`characters.riv`'s
  `belya`, or its SVG) at the scene's bottom-end corner, overlapping the dashboard's top edge by about
  30 pt; a `SpeechBubble.character` with his name «بلية» and the hint in `quote` type; and the pointing
  hand (`ui.riv`'s `coach_hand`, or `icons/hand.svg`) at what the hint is about.
- When hints show and what they say stay M02's (`trip_hints_mode_<line_id>`, hint memory). M07 adds
  the scrim, the hole and the step sequence with `CoachMark`.
- The hint takes no touch, so the controls under it stay usable.

## R13. Pause, failure and the other cards

**Decision.**

- **`Pause`:**
  - the static microbus art (`illustrations/screens/` has no Pause art, so a 72×56 crop of
    `vehicles/microbus_old.svg`), the title, the subtitle;
  - «كمّل المشوار» (60 pt);
  - «عيد المشوار» with the fuel chip (a `sun` pill with «−١» and the fuel icon, HANDOFF §9.1 #4);
  - «ارجع الموقف»;
  - the two `AppSwitch`es on `pref.trip_sound` and `pref.trip_haptics`.

  What the buttons do is M02's. Back resumes the trip, as the handoff proposes and M02 does.
- **`Fail`:**
  - **Faces:** up to three angry faces from the trip, in this order: those who fought, those who
    missed their stop, then the rest by seat.
  - **The title.**
  - **The reason chip:** M02's failure summary, unchanged (the two causes that cost the most
    reputation, in their existing plural lines, joined by `tripFailCauses`). When a story trip broke
    its rule, R11's line `tripFailStoryRule` leads instead, from a new `brokeStoryRule` flag on the
    summary.
  - **The revive:** the BONAT revive «صالح بـ{price} بون» and the once-per-trip caption, only when the
    engine reports the trip revivable and under the command cap (M02 FR-040).
  - **The tiles:** «عيد المشوار» with the fuel chip, and «ارجع الموقف».

  Back and the scrim don't dismiss it. The `RewardedAdButton` slot sits above the BONAT button and is
  hidden until M11.
- **The other cards** use `AppDialog` with the `States` spend-confirmation layout. Their buttons and
  economy calls are M02's.
  - **The booster purchase:** the price, «اشتريها واستعملها» and «لأ» (clarification).
  - **The empty tank, the failed save, the dispute:** M02's.

## R14. Skins and looks

**Decision.**

- **A look** is one of the design's passenger types (HANDOFF §5.3), named by its art id: `regular`,
  `hagga`, `sleeper`, `hurried`, `effendi_200`, `student`, `headphones`, `claimer`, `group_payer`,
  `chatterbox`, `regular_customer` and `honest` for the MVP lines. The six later ones arrive with their
  lines. The `Look` table (data-model.md) replaces M02's `SkinLook`.
- **Each look has** its ARB label, its Rive artboard and its SVG. A label names what the player sees:
  only `hagga`, `effendi_200`, `student` and `headphones` have their own («الحاجة», «الأفندي»,
  «الطالب», «أبو سمّاعة»). Every other look takes the neutral «راكب», because its design name describes
  a behaviour (`claimer`, `honest`, `hurried`, …) or a state the art already shows (`sleeper`).
- **A `skin` picks its look,** in this order:
  - a skin equal to a look id takes that look;
  - M02's sample slugs map through a small alias table (`effendi_suit` and `effendi_tie` →
    `effendi_200`, `hajja_black` → `hagga`, `student_cap` → `student`, `worker_blue` → `regular`,
    `young_cap` → `group_payer`);
  - an unknown skin keeps M02's fallback (`lookFor`): the look of a type the player can see anyway
    (`hajja` → `hagga`, `student` → `student`, `headphones` → `headphones`, `sleeper` → `sleeper`,
    `hurry` → `hurried`, `big_note` → `effendi_200`), otherwise `regular`, always with the neutral
    label.
- **No look comes from a hidden type.** In the sample pack, `honest` shares `effendi_suit` with
  `regular` and `chatty`, so nothing is revealed. The `claimer` and `honest` looks are content's to use
  freely, decoys included. The content authors get that note (Handed to later features).
- **M02's shirts and accessories go.** Each look is its own drawing, so `Shirt`, `Accessory`, their
  colour tokens and the shirt-pair palette check are removed.

**Rationale.** No content change: the sample pack, its golden checksums, the parity fixtures (which
embed definitions) and the solver bench stay as they are. New content can name looks directly.

**Rejected.** Renaming the sample pack's skins, which would touch the fixtures and checksums for no
player-visible gain.

## R15. The owner's Rive files

**Decision** ([contracts/rive-characters.md](./contracts/rive-characters.md)).

- **Four files**, each decoded once at boot:

  | File | Artboards |
  | --- | --- |
  | `passengers.riv` | one per look |
  | `characters.riv` | `usta`, `salma`, `bride_father`, `bride_mother`, `moallem`, `belya` |
  | `vehicles.riv` | `tuktuk`, `microbus_old` |
  | `ui.riv` | `coach_hand`, `stars`, `coins_burst`, `bonat_burst`, `fuel_fill`, `gift_open`, `sparkle_place`, `ring_shine`, `confetti`, `loading_wheel`, `notif_bell` |

  The later vehicles and passengers join their files in their phases.
- **People share one rig.** Every person artboard is 200×240, with the head centre at (100, 100),
  drawn at near-row size (head radius 42), so the app places it by the head and scales it by the row.
  Its state machine `Main` is bound to a view model `Character` with:
  - `pose`, an enum of the looping states of HANDOFF §5.4 and §6.2;
  - triggers for the one-shot states, which return to the current `pose`;
  - `skinTone` (colour) and `headphonesOn` (bool).
- **Vehicles and UI.**
  - **Vehicles:** 236×150, view model `Vehicle` with `motion` (`idle`, `drive`, `brake`) and a `honk`
    trigger.
  - **UI animations:** each has the inputs its use needs (the contract's table).
- **The design's Lottie files are the motion reference:** the timings and what moves in each state
  (`docs/design/lottie/index.html`). The SVGs in `illustrations/` are the art.
- **Export and runtime.** Exported with Rive's data binding, as M02's R1 set up. **From the free
  plan, by the owner's decision of 2026-10-23**, not a paid seat as M02's R1 asked.
  - **Where the splash is.** The free export's splash ("Free exports play a Rive splash screen",
    rive.app/pricing) is a set of artboards in the file: `Watermark`, `NuRiveBrandmark01` and
    `NuRiveWordmark01`. The runtimes (`rive` 0.14.11, `rive_native` 0.1.11) have no splash code.
  - **Why players never see it.** The app opens every artboard by name, so it never draws these, and
    `checkRiveArt` accepts them.
  - **Not checked.** Whether Rive's terms allow shipping a free export whose splash the app never
    plays. The owner was told and chose the free plan.
- **Drawing.** They are drawn with `Factory.flutter` in Flame and in Flutter widgets alike, so the Linux
  tests render them.
- **Budget:** about 3 MB for the four files together.
- **`passenger.riv` is retired.** Its contract, `passengerRiveProvider` and the `rive`-tagged tests
  are replaced by the new contract, a `riveArtProvider` that loads all four files, and new tests with
  the same tag.

**Rationale.** One file per family loads once and instances cheaply, as M02's single file did. One
shared rig and view model means the app has one mapping (R16), and the owner can build every look from
one template. Triggers for one-shots and an enum for loops match how the design splits its segments.

**Rejected.**

- One file per look: 12 to 18 decodes at boot and 12 to 18 contract checks.
- Per-state boolean inputs, M02's style: they allow combinations the design never draws, such as
  sleeping and talking.
- The handoff's `ui/splash_drive`: the vehicle file covers the loading screen (R6).

**Revised 2026-10-23: the owner's file.** The owner delivered one file, `wassal.riv`, instead of four,
and the contract now describes it ([contracts/rive-characters.md](./contracts/rive-characters.md)):

- One `Person` artboard draws all 24 people (the 18 passengers and the 6 characters), picked by a
  `look` number. One `Vehicle` artboard draws all four vehicles the same way. The UI animations are
  artboards of their own, each with a state machine named after it.
- People take M02-style inputs: a `mood` number (0–4) and booleans for the other states, with
  `board`, `alight`, `call`, `happy` and `targeted` as triggers. Waking and taking the headphones off
  play when `asleep` and `headphones` turn false.
- The objection to booleans above still holds, so the app keeps R16's single pose and sets only that
  pose's input. Combinations the design never draws never reach the file.
- Not in the file yet: `reducedMotion` (people use the static art under reduced motion until it is
  added) and `skinTone` (each look keeps its drawn skin). The file also carries four artboards the
  app never draws, to be removed before the final export. All three are owner actions.
- The budget is met easily: the file is 86 KB.

## R16. From the trip to a pose

**Decision.** For each passenger, the app picks one `pose` from its `PassengerView`, first match wins
([contracts/rive-characters.md](./contracts/rive-characters.md#poses)):

| # | When | Pose |
| --- | --- | --- |
| 1 | They are getting off with a fight (`outcome`) | `fight` |
| 2 | Their «أنا دافع!» claim is open | `claim` |
| 3 | Their stop is next and they are still owed change (`nearStopPulse`) | `change_due` |
| 4 | Asleep or waking | `sleep` |
| 5 | Headphones on (muted) | `headphones` |
| 6 | `mood` 2 or 3 (frowning, patience gone, or the trip failed) | `impatient_2` |
| 7 | `mood` 1 | `impatient_1` |
| 8 | Talking | `talk` |
| 9 | Otherwise | `idle` |

Triggers come from the engine's events, through a new `CharacterCue(passengerId, trigger)` that M02's
`mapCues` adds beside its other cues:

| Event or cue | Trigger |
| --- | --- |
| `PassengerBoarded` | `board` |
| `PassengerAlighted` | `alight` |
| `PassengerWoke` (until then the pose stays `sleep`) | `wake` |
| `PassengerCalled` with no `PassengerAttentive` in the same step | `call_1` |
| `PassengerAttentive` (and `headphonesOn` goes false until `PassengerMuted`) | `call_2` |
| `ChangeDelivered{exact}` | `happy` |
| M02's `HighlightCue`, the 500 ms glow before a send | `targeted` |

**Revised 2026-10-23.** With the owner's file (R15, "Revised"), the pose sets one input, as the
contract's "From a pose to the inputs" lists. The triggers are `board`, `alight`, `call`, `happy` and
`targeted`. `PassengerWoke` and `PassengerAttentive` need none: the view's `asleep` and `headphones`
turn false, and the file plays `wake` and the take-off itself.

`PassengerView` gains one field, `claimOpen`, read from the engine's open claims. It is a presentation
field with no rule, and it reveals nothing the claim's popover doesn't show already. The pose function
and the cue mapping are pure, in `features/trip/domain/`, and tested for every row.

## R17. The static art

**Decision.**

- **What draws it.** `flutter_svg` 2.3.0 loads each SVG once with `vg.loadPicture`. In Flame,
  `PassengerAvatar` draws the cached `Picture` scaled to the seat. In widgets, `SvgPicture.asset` draws
  icons, tinted with `ColorFilter.mode(…, srcIn)` when they are one colour.
- **It moves in code:**
  - an idle bob of 2 pt every 1.2 s;
  - a sleep tilt of 18°;
  - rising 12 pt and fading over 600 ms to get off;
  - sliding in from the door side to board;
  - a 6 pt shake for a fight;
  - the state marks of HANDOFF §5.4 painted from tokens: «z», the sweat drop, music notes and a red
    tint.
- **It is used**
  - when a file or an artboard is missing or fails its contract check;
  - for rows B and C at the last performance tier (R18);
  - in every trip golden, so goldens don't depend on the native Rive library, as M02's used the
    stand-in. The Rive files have their own goldens, tagged `rive`.
- **The two stand-ins go:** M02's sticker-style stand-in painter is deleted, and this replaces it
  behind the same `PassengerArtFactory` seam.

**Rejected.** `flame_svg`, an extra package for what `vg.loadPicture` already gives. Rasterizing SVGs
at build time, which would need images per density for no gain at these sizes.

## R18. Performance

**Decision.**

- **The gate** is M02's, on the Galaxy A06 with `tool/perf/trip_fps.sh`, now with every `micro_old`
  seat drawn by Rive, two bubbles and three notes moving:
  - an average of at least 55 fps;
  - no one-second window under 45 fps;
  - memory under 300 MB;
  - the p90 frame time recorded against HANDOFF §6.4's 16 ms.
- **The art tier** is one setting, `ArtTier` (dev builds can change it from the debug panel):
  - `rive`: every seat in Rive (the default);
  - `near_rive`: rows A and the front seat in Rive, rows B and C static (§6.4 step 3);
  - `static`.

  If the A06 misses the gate on `rive`, the default becomes `near_rive`, and the measurement goes in
  this file.
- **Not built:** §6.4 step 2 (caching each state as a sprite animation). It is built only if
  `near_rive` also misses.

## R19. The design's files in the app

**Decision.**

- **What is copied.** A sync tool, `tool/design/sync_assets.dart`, copies from `docs/design/` into
  `apps/mobile/assets/`:
  - `icons/` (all 92 SVGs, which later features use);
  - `illustrations/passengers/` (the 12 MVP looks), `characters/` (all 6) and `vehicles/` (`tuktuk`,
    `microbus_old`);
  - the in-scope screen art: `Loading_01.svg`.
- **A drift check.** `test/repo/design_assets_test.dart` fails when a copied file differs from its
  source, or when a source on the list is missing.
- **Fonts** are downloaded once (R3), not synced.

**Rationale.** Flutter only bundles files under the package. The test keeps the copies honest when the
design is rebuilt.

## R20. Testing against the design

**Decision** ([contracts/design-checks.md](./contracts/design-checks.md)).

- **Sample states.** `test/design/samples/` holds one builder per artboard. It reproduces the
  artboard's sample data: for the trip, a fake `TripModel` matching `C-Trip`, `TripEvents`, `StoryTrip`,
  `Pause`, `Fail` and the `Tutorial` hint; for the frame, `Loading` at progress 62. M02's scripted-model
  helpers build them.
- **Goldens** of each artboard go to `test/goldens/design/<Artboard>_<digits>.png`, at 390×844 with a
  36 pt top inset (the design's status bar), in RTL, in both digit styles.
- **Layout tests** read `docs/design/boxes/<Artboard>.json`. For each box with `role: "tap"`, they find
  the widget whose semantics label equals the box's `label` (or contains its `text`) and check its rect
  within ±2 pt.
  - Boxes marked «للنموذج بس» are skipped.
  - So are boxes of things this feature doesn't build, each with its reason: the ad revive and the ad
    badge (M11), and the garland.
- **A side-by-side image** of the design PNG and the golden is written to `build/design_compare/` when
  the tests run with `--dart-define=DESIGN_COMPARE=true`, for the PR (HANDOFF §10).
- **Surfaces:**

  | Surface | Size | Runs |
  | --- | --- | --- |
  | reference | 390×844 | artboard goldens and layout tests; M03's and M02's goldens |
  | a06 | 360×800 | the trip's goldens and every minimum size |
  | small | 360×640 | M03's checks, and the trip's exception check (bands keep their targets and text) |

  M02's 360×744 surface is dropped: under the design's bands it is no longer compliant, so it falls
  under the exception.
- **All existing goldens** (M03's matrix, M02's trip states) are regenerated in the new look. Every
  behaviour test stays as it is.

## R21. Palette checks

**Decision.** `test/core/theme/palette_test.dart` is rewritten for the new palette:

- **Contrast:** at least 4.5:1 for `ink`, `ink.2` and `ink.muted` on `paper`, `ground` and
  `locked.bg`; for white on `primary`, `primary.lip`, `station[0..1]` and `dashboard.bg`; and for `ink`
  on `danger`, `sun`, `sun.soft`, `danger.soft`, `primary.soft` and `station[2..3]`.
- **Exceptions:** large text (Marhey ≥ 18 pt bold) needs 3:1, and the dashboard's `dashboard.text` and
  `dashboard.muted` on `dashboard.bg` and `dashboard.raised` are checked too.
- **Never white text** on `danger` or `sun`: no widget pairs them, which a scan of the components
  checks.
- **Lightness:** the station colours, and `primary` against `danger`, at least 18 L* apart.

## R22. What goes, and the docs

**Decision.**

- **Removed:**
  - the old fonts;
  - the sticker components;
  - `passenger.riv` and `assets/rive/README.md` (rewritten for the four files);
  - the stand-in painter;
  - M02's `rive_character_*` tests;
  - the old token files.

  A repo test checks that `lib/` names none of them (SC-008).
- **Docs:**
  - **`docs/architecture-mobile.md`:** §2 (`flutter_svg`), §5 (assets), §8 (zones, geometry, the
    character files, static art) and §20 (artboard goldens, layout tests).
  - **`CLAUDE.md`:** the Rive files and their contract instead of `passenger.riv`; the token and asset
    commands; the guards.
  - **Superseded contracts:** M02's `scene-layout.md` and `rive-character.md`, and M03's
    `design-tokens.md`, each get a first line pointing to their replacement here.
  - **`docs/delivery-plan.md`:** the progress list.

## Handed to later features

- **M07:**
  - the tutorial's `CoachMark` (built here, in the gallery) and the locked-boosters bar;
  - the short-screen layout below `inset + 764` pt, which ends the continued exception.
- **M08:** whether «عيد المشوار» goes through the pre-trip card (the handoff's flow).
- **M10, or story content:** the story character in the front seat, its comments, the story title, and
  the character's name in the failure line. They need a schema and capability change. The art and the
  character bubble are ready.
- **M11:** show the `RewardedAdButton` on `Fail` and the ad badge on «زحمة» (their slots are laid out).
- **Content authors (B04 docs):**
  - name looks by their design ids in new content;
  - the `claimer` and `honest` looks are not tied to those archetypes, so use them freely, decoys
    included;
  - keep station names short enough for the strip.
- **Every later screen:** its artboard's sample builder, golden and layout test, as in
  [design-checks.md](./contracts/design-checks.md).
