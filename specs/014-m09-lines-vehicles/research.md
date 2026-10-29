# Research: Lines Map, Line Details and Vehicle Purchase (M09)

Phase 0 of [plan.md](./plan.md). Each entry gives the decision, why, and what was rejected. Spec
references are to [spec.md](./spec.md). M08's merged code is cited from master at 68f7ec5.

## R1. The phone-only rules (FR-002, FR-003, FR-006, FR-007, FR-011, FR-013)

**Decision.** A new pure file beside M08's port, `lib/core/progress/domain/playable.dart`
([contracts/progress-rules.md](./contracts/progress-rules.md)). `unlocks.dart` stays a one-to-one
copy of `unlocks.py` and is not edited.

- `bool tripPlayable(ContentSource c, PlayerProgress p, String tripId)`:
  - a **story** trip that a chapter names (`Chapter.storyTripId`): its line unlocked
    (`lineUnlocked`), its vehicle the player's (`vehicleOwned`), and its chapter complete
    (`chapterComplete`);
  - any other trip: `tripUnlocked`, unchanged.
- `Vehicle? currentVehicle(ContentSource c, PlayerProgress p)`: the last of the player's vehicles by
  `order` (FR-002).
- `VehicleSale vehicleSale(ContentSource c, PlayerProgress p, VehicleId id)`, a sealed result:
  `Owned`, `ForSale(price)`, `NeedsFirst(VehicleId)` (the first earlier vehicle not owned), `NoPrice`
  (FR-003, FR-035). The economy itself refuses a starter as `notForSale` and accepts any order
  (`spend_rules.dart:43-91`), and so does the server (`spending.py:70-92`), so this is the only
  vehicle-order check there is.
- Unknown ids answer false, `NoPrice` or null; nothing throws (FR-013).

**Never more permissive (FR-011).** `test/core/progress/playable_test.dart` proves, over every state
reachable by finishing playable trips and buying for-sale vehicles in the sample pack and in a
synthetic pack shaped like the release draft (three chapters with story trips at `line_hay.20`,
`line_gamaa.01`, `line_gamaa.18`; depth 8):

- `tripPlayable ⇒ tripUnlocked` for every trip. For a story trip this holds because
  `chapterComplete(n)` implies `chapterUnlocked(n)`, which is all the server's rule asks.
- `vehicleSale is ForSale ⇒` the economy's `validateBuy` accepts it with enough JENEHAT.
- The cases of US5 (scenarios 1–5) by name.

M08's `unlocks_test.dart` keeps porting the server's cases one to one and doesn't change.

**Rejected.**

- Editing `tripUnlocked`: it would stop being a port of `unlocks.py`, and the comment at the top of
  both files says they move together.
- Changing the server's rule as well: B03 is merged and the server only needs to be no stricter than
  the phone. A stricter server would refuse starts that M08's merged builds still make. The shared
  fixture M08 handed to M10 can carry the rule to the server later if the owner wants it there.

## R2. Switching M08's callers to the playable rule (FR-012, US5 scenario 5)

**Decision.** Every way into a trip outside the debug list reads `tripPlayable`:

| Where (master) | Change |
| --- | --- |
| `features/home/domain/next_trip.dart:67` (`startable`) | `tripUnlocked` → `tripPlayable`. Home's next trip and the result's «مشوار تاني» (both through `homeNextTrip`) follow. |
| `features/pre_trip/presentation/pre_trip_card.dart:88` (opening check) | `tripUnlocked` → `tripPlayable` |
| `features/home/application/start_next_trip.dart` | **New first step:** a trip that isn't `tripPlayable` returns false and goes nowhere. Defence in depth: the direct-to-trip path checked nothing until now. |

`lineUnlocked` at `next_trip.dart:86` stays. The paths that start a trip without the rules stay as
they are, since none of them can reach a locked story trip:

- the debug list (allowed by FR-012);
- the boot resume of an unfinished trip, which was playable when it started;
- M07's first-session paths, which start only tutorial trips, all regular.

Tests that change with it: `next_trip_test.dart` (a story trip waiting for its chapter's goal),
`sample_sweep_test.dart` (its expected table for the sample's story trip `line_hay.03`),
`pre_trip_card_test.dart` (a locked story trip pops), and a new `start_next_trip_test.dart` case.

**Rejected.** Checking inside the economy's `startTrip`: M08's research R2 rejected it (unlock order
is progression, not economy), and a refusal there comes after the screen already offered the trip.

## R3. Lines' standings and the map (FR-008–FR-010, FR-014–FR-022, US1)

**Decision.** A pure `lib/features/lines/domain/` with derived values
([data-model.md](./data-model.md)):

- `LineStanding`: `locked(reason)` / `current(next)` / `done`, with the stars earned and possible
  (`3 × trips`), `allThree`, and the fare and what's new from content. The reason is
  `NeedsVehicle(VehicleId)` or `AfterLine(LineId)`, from `Line.unlock`.
- `VehicleTile`: `done` / `current` / `forSale(price)` / `notForSale`, from R1.
- `LinesModel` (application, `lines_model_provider.dart`): the tiles, the cards in pack order, the
  balances, `focusLine` and `online`. It is rebuilt from `contentSourceProvider`,
  `playerProgressProvider` and `economyViewProvider`, so a sync or rollback redraws every open
  screen (FR-022).
- **The focus line (FR-010):** the line of `homeNextTrip(...)` (M08's `home_model.dart`, the same
  call Home makes, with M07's tutorial trip first) or, with none, the last `current` line, else the
  last unlocked one.

**Layout.**

- The map is a `CustomScrollView` whose cards sit bottom-up: the first line by order is at the
  bottom. The road is a painter behind the cards, as tall as the content, never shorter than the
  map.
- On first frame the focus card is brought into view with `Scrollable.ensureVisible`, without
  animation under reduced motion.
- How two cards sit in the 540 pt map, and where the road ends, is one of the owner's boards
  (R12, `LinesFirst`). Until then the column is bottom-aligned with the drawn 12 pt gap.

**«كمّل» (FR-019, Clarifications Q3).** It is its own `Pressable` inside the current card's
`Pressable`, 63×44 as drawn (box 51), with its own label «كمّل المشوار {n}». Its tap calls R5's
start; the rest of the card opens the details. In the layout test the card's box (43) pairs with
the card, and «كمّل» pairs with box 51 (a text box in the board) through `pairings`, as the
expected difference "«كمّل» is its own button".

**Rejected.** A `ListView(reverse: true)`, which reverses the reading order too: screen readers must
read the lines top to bottom (FR-049).

## R4. The trip grid (FR-023–FR-029, US2)

**Decision.**

- `TripCell` states: `done(stars)`, `storyDone(stars)`, `next` (with «كمّل»), `playable` (a second
  playable, undone trip: drawn as next without «كمّل», FR-024), `locked`, `storyLocked`. A trip
  shows as a story cell when `kind == story`.
- **The next trip** is the first trip by number that is `tripPlayable` and has no star (FR-008).
- **Visible range** (FR-025):
  - rows = `max(4, nextRow + 2)`, capped at the line's rows, five cells to a row;
  - a done line (no next trip) shows every row: every cell is a replay;
  - a locked line shows four rows.
  - The hint «والمشاوير من {from} لـ {to} بتظهر لما تقرّب» names the first and last hidden trip and
    hides when none is hidden.

  This reproduces the drawn sample (next 12, rows 1–4, hint 21–30) and HANDOFF's 20-trip line.
- **The button** reads «العب المشوار {n}» for the next trip. A done line has none (FR-027). A locked
  line shows the reason in its place (FR-028).
- The grid scrolls above the pinned button. The summary uses the plural strings of R14.
- **Sample data note.** The board's header says 27 stars while its cells sum to 25. The sample builder
  gives the header 25, and the golden's difference is listed (R12).

## R5. Starting from Lines, and where the card returns (FR-019, FR-026, US2)

**Decision.**

- **One start path.** «كمّل», a cell and the details' button call M08's
  `startNextTrip(context, ref, tripId:, from: StartFrom.lines)`. `StartFrom` gains `lines` (M15
  reads it later).
- **A card route under the line's details:** `/lines/:lineId/pre-trip/:tripId` (`RouteNames.linePreTrip`),
  a child of `lineDetail` in the lines branch. It builds the same `PreTripCard`. Its location is
  chosen in `startNextTrip`:
  - `home` and `result` keep `/home/pre-trip/<id>`;
  - `lines` goes to `/lines/<line wire>/pre-trip/<id>`. The line comes from the trip's own `lineId`,
    not from the caller.
- **Return to the opener.** The card's ✕, swipe, scrim and back already pop. Under the new route the
  pop lands on the line's details. So does a «كمّل» start from the map, since going to the card's
  location stacks the details under it. That is FR-019's "exactly as the details' button does".
- **Leaving an unopenable card.** `PreTripCard` gains `leaveTo` (`/home` by default, `/lines/<line>`
  under Lines) for its unknown-or-locked `_leave()`.
- **The lines tab opens at its root.** Today `ShellScaffold` taps call
  `goBranch(i, initialLocation: i == currentIndex)`, so a branch reopens where it was left. A trip
  started from a Lines card leaves the branch at the card's location, and the next visit would rebuild
  that card. The lines tab therefore always opens at `/lines`; every other tab keeps M03's behaviour.
  A test covers card → «اطلع» → result → Home → «الخطوط».
- The empty-tank and checkpoint steps are M08's, unchanged. A tutorial trip in the first session
  goes straight to `/trip/<id>`, where M07's redirects apply.

**Rejected.**

- A separate `/lines/pre-trip/:tripId` for «كمّل» that would close to the map: one more route and
  one more `ParamValidators` ordering trap (`pre-trip` would match `:lineId`), for a difference the
  spec doesn't ask for.
- Switching to Home for the card, as `startNextTrip` does today: the close would land on Home, which
  US2 scenario 2 forbids.
- Resetting the lines branch from the card's «اطلع»: go_router has no public way to rewrite another
  branch's stack. Opening the tab at its root is one line in the shell.

## R6. The vehicle sheet and the purchase (FR-030–FR-040, US3, US4)

**Decision.**

- **`VehicleOffer`** (pure, `features/lines/domain/vehicle_offer.dart`), built from content, R1 and
  the economy view:
  - the name, and `look` for the preview;
  - the seats as `seats.length`, against the current vehicle's;
  - `opensLine`: the first line by `order` whose unlock is this vehicle;
  - the sale state (R1), the price and the balance;
  - `shortfall` (price − balance when > 0);
  - the impact (R7).
- **`VehiclePurchase`** (`features/lines/application/vehicle_purchase.dart`) copies M08's
  `BoosterPurchase`:
  - It holds one `TxnId` per intent (`_id ??= economy.newRequestId()`), and is busy while a call is
    in flight.
  - It checks `vehicleSale is ForSale` before calling
    `economy.buy(id, kind: SkuKind.vehicle, skuId: vehicleWire[id]!)`.
  - The price is read by the economy from the catalog when it applies (M05). The caller never passes
    one.
- **Outcomes** (FR-037, FR-038):

  | Outcome | Sheet |
  | --- | --- |
  | `OpApplied` (or `repeated`) | `NavGuard.go('/lines')`; announce «اشتريت {vehicle}! خط {line} اتفتح.» through `SemanticsService.announce`. The id is cleared. |
  | `OpRefused(insufficientFunds)` | stays. The view already shows the shortfall from the balance. The id is kept. |
  | `OpRefused(alreadyOwned)` | stays. The view redraws as owned. The id is cleared. |
  | `OpRefused(notForSale \| unknownSku \| catalogMismatch)` | closes to `/lines` with `showAppToast` «العربية دي مش للبيع دلوقتي». |
  | `OpWriteFailed` | stays, with M08's inline retry line (`tripRetryPurchase` «ما عرفناش نكمّل الشرا.» under the buttons). The id is kept, so a retry stays one intent. |

- **Offline and rollback (FR-039).** Nothing extra. The purchase is a local op that M06 syncs. A
  refused op drops out when M06 rebases (`applyAnswer`), the view updates, the screens redraw, and
  M06's `syncBalanceCorrected` toast says so.
- **Owned and not-for-sale sheets (FR-034, FR-035).** The same sheet without the price card, the
  impact or the buy button, with a status line and one close button. Their layout is an owner board
  (R12).
- **No confirmation** before the buy (spec Assumptions). The sheet is the confirmation, as drawn.

**Rejected.** Reusing M08's `BuyDialog`: it is a BONAT booster dialog, and the vehicle sheet is
itself the confirmation step.

## R7. The impact line (FR-032, Clarifications Q4)

**Decision.**

- `impactAfterPurchase(c, p, jenehat, vehicle)` (pure) calls M08's
  `savingsTarget(c, p', jenehat − price)`. `p'` is `p` with `(vehicle, wire)` added to `owned`, a new
  `PlayerProgress`: the class is a plain value with public fields.
- **The goal and its price:**

  | Target | Goal | Price |
  | --- | --- | --- |
  | `ChapterGoalTarget` with `Amount` | `subjectName` | its `of` |
  | `ApartmentPieceTarget` | `itemName` | `priceJenehat` |
  | `Count` (finish a line), `NoTarget` | none: hidden | — |

- **The amount** is the price − (jenehat − vehicle price), shown when > 0 (FR-032).
- **Wording:** «بعد الشرا، فاضل {amount} ج على {goal}». No prefix is joined to the name, so no
  content field and no Arabic in code (the guard). With the draft, buying the microbus in chapter 2
  shows chapter 3's «الشبكة».
- The impact is hidden in the shortfall state, because the sum would be negative (spec FR-032: hidden
  when nothing is missing). Whether the shortfall board keeps the line is the owner's call (R12).
- `features/lines/domain/` may import `features/home/domain/savings_target.dart`. The import guard
  gets a `lines` entry (R18).

**Rejected.** Moving `savingsTarget` into `core/progress/domain/`: it is M08's, uses M08's titles, and
M10 owns its next change. Importing it is enough.

## R8. The «new» dot (FR-041, US6)

**Decision.**

- **News** is a set of keys derived by `linesNews(c, p, jenehat)` (pure):
  - `line:<id>` for each unlocked line, except `start` lines;
  - `story:<tripId>` for each `tripPlayable` story trip without a star;
  - `vehicle:<id>` for each `ForSale` vehicle the balance covers.
- **Seen** is the set the player has looked at, kept in the device preference `pref.lines_seen`:
  sorted, comma-joined keys, like `pref.trip_hints_seen`. It is added to
  `SharedPrefsSettingsStore.keys` and to the test store's list. It is a read marker, not game state:
  losing it only shows the dot once more.
- **The dot** shows when `news − seen` isn't empty.
  - `LinesDotWatcher` is created in `bootstrap/app.dart`'s `_afterStartup` beside M08's
    `HomeArrivalQueue`. It listens to both providers and calls `newDotProvider(Section.lines)` `show()`
    or `clear()`.
  - `LinesScreen` marks the current news seen when it opens, and again whenever the news changes
    while it is on screen. So a purchase made on Lines raises no dot (US6 scenario 3).
- **First read.** With no stored value, the current news becomes the seen set without a dot. A new
  install, or an update from M08, doesn't greet the player with a dot for things they already had.

**Rejected.**

- A drift table: a schema version and migration for a read marker.
- Keeping it in memory, as M03's dot is: FR-041 requires it to survive a restart.
- A listener on Home, as M08 does for the apartment dot: a sync can make news on any tab.

## R9. The content fields (FR-042–FR-044)

**Decision.** Three required fields, named in the schemas' style
([contracts/content-fields.md](./contracts/content-fields.md)):

| Schema | Field | Type | Sample (product spec) |
| --- | --- | --- | --- |
| `line.schema.json` | `whats_new` | `LocalizedText` | خط الحي «تعلّم اللمّ والباقي، الحاجة، النايم، المستعجل»; خط الجامعة «نص الأجرة، الدفع الجماعي، "أنا دافع!"، أبو سمّاعة» |
| `line.schema.json` | `display_fare_piasters` | `PositivePiasters` (≥ 50, × 50) | 700, 850 |
| `vehicle.schema.json` | `short_name` | `LocalizedText` | «توكتوك», «قديم» |

- **No new content-kit rule.** V-X1 already refuses digits and edge spaces in every `LocalizedText`
  of lines and vehicles. `PositivePiasters` brings the fare's checks.
- **The pipeline**, following M01's `no_fights_required` (commit `23b0550`) and M07's `plays`
  (`126badf`):
  - the schema copies and generated models (`codegen`, `build_runner`);
  - the valid and invalid examples. Every invalid line and vehicle example gains the fields, so each
    still reports only its own error;
  - the sample, its golden and the dev bundle;
  - B04's models and a migration (`0010`, defaults for existing rows), the importer, the snapshot and
    the admin, with their tests;
  - two mobile test fixtures: `wire_test.dart`'s literal vehicle and the tutorial `line_hay.json`.
  - New invalid examples: a 475-piaster fare, a vehicle without `short_name`, and a digit in
    `whats_new` (V-X1).
- **Free to change.** `content/source/pack.json` doesn't exist, so `schema-diff` doesn't apply and
  `schema-set.json` stays at 1.0.
- **Required, not optional.** An optional field would need a fallback string in code for every
  reader (constitution VII). The cost is that a pack built before this change no longer reads: M04
  refuses it as unreadable and falls back to the bundled pack. No pack is promoted yet. Staging
  rebuilds and publishes a fresh pack after the deploy (owner action).
- **The release draft.** The `content-core-r1` worktree's `pack/lines/*.json` and
  `pack/vehicles/*.json` gain the fields, with the product spec's texts. Claude does it there,
  uncommitted like the rest of the draft, as for M07's item 4.
- FR-043: no engine, solver or fixture reads the fields. `solver_fingerprint` doesn't change.

## R10. The vehicle preview (FR-031)

**Decision.**

- **The preview** is `VehicleSprite(vehicle:, fallback:)` (`wassal.riv`'s `Vehicle` by `look`), on
  the drawn sky with the sun, in a 358×190 card.
- **«بزينتك»** never shows: no cosmetics exist before M16.
- **Static fallbacks.** Only `tuktuk.svg` and `microbus_old.svg` are bundled today.
  `tool/design/sync_assets.dart` gains `microbus_new.svg` and `microbus_travel.svg` from
  `docs/design/illustrations/vehicles/`, so every vehicle has its own fallback. The board's sample
  is `micro_new`, and later packs will sell it. `design_assets_test` follows the tool.
- **The tiles** use the same art at 64×40 inside the 83.5×96 tile. The node glyph on the current
  card is the route icon (`route_bold`), as drawn.

## R11. Looks and components (FR-045–FR-047, FR-051)

**Decision.**

- **Feature widgets** in `features/lines/presentation/`, built from the tokens and the shared
  components:
  - `VehicleTile`, `LineCard`, `FareChip`, `RoadPainter`, `TripCell`, `TripGrid`;
  - `BenefitTile`, `PriceCard`, `ImpactLine`;
  - all of it inside `Pressable`, `AppCard`, `AppButton`, `StatusChip`, `Stars`, `ProgressBar`,
    `CurrencyPill`, `IconCircleButton` and the `AppSheetPage` route.
- **The locked look** follows HANDOFF §9.1 #6:
  - a line card is `AppCard(locked: true)`;
  - tiles and cells use the same tokens (`lockedBg`, the 2 pt locked ring, `ink2`, the `lock` icon)
    through a small `LockedFill` decoration in the feature;
  - no opacity anywhere.

  The drawn dashed tiles and cells are expected differences until the owner's boards draw the
  locked look on them (R12).
- **Disabled** «اشتريها» follows §9.1 #5 (45%, no lip): `AppButton(enabled: false)`.
- **Long text wraps** (§9.1 #10 wins over HANDOFF's one-line ellipsis): cards and cells grow. The
  story chip sits above the cell.
- **Motion.**
  - Cards, tiles, cells and buttons press with `Pressable`.
  - The sheets use `AppSheetPage`'s slide.
  - After a purchase the tile changes state with no animation, as drawn.
  - Reduced motion leaves only the state changes.

**Rejected.** Shared components in `core/theme/components/` for the tile, card and cell: only Lines
uses them. M16 can move the tile when the garage needs it.

## R12. Design checks and the owner's boards (FR-045, the owner's instruction)

**Decision.**

- **The three drawn artboards** get their checks now: a sample (`test/design/samples/{lines,
  line_details,buy_vehicle}.dart`), a golden in both digit styles, and a layout test against
  `boxes/<Artboard>.json`.
  - The samples lay a synthetic pack over the sample, M08's `editPack` way. That pack has the
    artboards' four vehicles (`micro_new` at 5,000, `micro_safar` at 12,000) and five lines (`souq`,
    `masyaf` after `souq`, `safar`), and the state as drawn.
  - **Expected differences**, listed at the top of each golden test and in the PR:
    - the real Lines under the scrim, where the boards draw placeholder blocks;
    - the locked look on the tiles and the cells (R11);
    - «كمّل» as its own button (R3);
    - the reworded impact line (R7);
    - the plain preview with no «بزينتك» (R10);
    - LineDetails' summary (25, not 27);
    - the ✕ labelled «قفل» against the board's «اقفل» (M08's pairing).
- **What the boards don't draw is the owner's to draw**, not Claude's. The brief is
  [contracts/design-briefs.md](./contracts/design-briefs.md), in the shape of a HANDOFF §11 section,
  as M07's `FuelLesson` was. The owner draws on the Claude Design canvas «وصّل الأجرة — Design» and
  exports with `docs/design/tools` into `screens/`, `png/` and `boxes/`. Each board is 390×844, one
  state per board, so it has its own boxes.

  **Needed by the first release** (each reachable with the draft):

  | Board | State |
  | --- | --- |
  | `LinesFirst` | Chapter 1: the tuktuk current and the microbus for sale (the locked tile look); خط الحي current with its own «كمّل»; خط الجامعة locked behind the microbus. Two tiles and two cards: the strip's width, where the cards and the road sit. |
  | `LinesOwned` | After the microbus: the tuktuk done and the microbus current; خط الحي done; خط الجامعة current. |
  | `LineDetailsStory` | خط الجامعة after the shabka is bought: the story trip `.18` as the next cell («قصة» on a next cell), a later playable trip without «كمّل», and locked cells in the §9.1 #6 look. |
  | `LineDetailsDone` | A finished line: every cell a replay, no play button, and the note's second sentence gone. |
  | `BuyVehicleShort` | The microbus with too little saved: the plain preview, the disabled «اشتريها», «ناقصك {n} ج» and the gold bar, and whether the impact line stays. |
  | `BuyVehicleOwned` | A vehicle that's already the player's: the tuktuk («عربية المعلم») and the microbus. What replaces the price card and the buttons. |

  **Only with later packs or test content** (built from the brief and approved on the goldens if
  never drawn):

  | Board | State |
  | --- | --- |
  | `LineDetailsLocked` | A line locked behind another line: the reason in the button's place. |
  | `BuyVehicleNotForSale` | A vehicle after one the player lacks, and one with no price. The sheet with two benefits (no «بيفتح»). |

- **States composed from drawn parts** need no board. The owner approves their goldens:
  - a done card with every trip at three stars (no «عيد عشان النجوم»);
  - a line under 20 trips (fewer rows, no hint);
  - the sheet with the impact line hidden;
  - the affordable microbus with the plain preview;
  - Lines offline (the BONAT pill as `HomeStates` draws it);
  - 360 pt and 1.3× text.
- **Order of work, M07's way (T079/T080).** Claude builds every state from the brief, so nothing
  waits. Only the new boards' samples, goldens and layout tests wait for the export. The owner's
  boards decide; Claude then aligns the widgets to them. `docs/delivery-plan.md`'s "Design sources"
  row for M09 gains the boards when they land.
- **The owner's boards are listed now** in `docs/owner-actions.md` (section 014), so they can be
  drawn while the code is built.

**Rejected.**

- Claude designing the undrawn states: the owner asked to draw them.
- Approving every undrawn state from goldens alone, as M07's compact trip did: these are whole
  layouts the first release shows on every visit, not a compression of a drawn screen.

## R13. Accessibility (FR-047–FR-050, SC-006, SC-007)

**Decision.**

- **Labels:**
  - the vehicle tiles' labels as the boards («توكتوك المعلم، خلصته»);
  - line cards «{line}، {standing}، {detail}», for example «خط الجامعة، الحالي، ٢٧ من ٩٠ نجمة،
    المشوار ١٢ من ٣٠»;
  - «كمّل المشوار {n}» as its own button after its card;
  - cells «المشوار {n}، {state}» (`aria-current` → `selected` on the next cell);
  - the price card as one node «السعر {price} جنيه، معاك {balance} جنيه»;
  - the preview excluded from semantics.
- **Order:** the header, the vehicles right to left, the lines top to bottom, then the nav. Each
  sheet's focus starts on its title (`AppSheet` does).
- **Sizes.** Every tappable is at least 44×44: the tile, the card, «كمّل», a 65×62 cell, the close
  button. a11y tests at 360×640, 360×800 and 390×844, text 1.0 and 1.3, as M08's.
- **Agreement.** ICU plurals in `app_ar.arb` for مشوار, كرسي and نجمة, in both digit styles (R14).

## R14. Copy (FR-044, FR-052)

**Decision.**

- **The artboards' strings are used as given** (HANDOFF's `lines.*`, `lineDetails.*`,
  `buyVehicle.*`), renamed to the ARB's camelCase. Every name comes from the pack and every price
  from the catalog.
- **New strings, drafted for the owner** (most of them also appear on the boards, where the owner may
  change them):

  | Key | Draft |
  | --- | --- |
  | `linesContinueA11y` | «كمّل المشوار {n}» |
  | `linesCardA11y` | «{line}، {standing}، {detail}» |
  | `linesStandingCurrent` / `Done` / `Locked` | «الحالي» / «خلص» / «مقفول» |
  | `lineDetailsLockedReason` | «بعد {line}» / «محتاج {vehicle}» (as the cards) |
  | `buyVehicleImpact` | «بعد الشرا، فاضل {amount} ج على {goal}» |
  | `buyVehicleOwnedStarter` | «دي عربية المعلم، وانت شغال عليها» |
  | `buyVehicleOwned` | «دي عربيتك» |
  | `buyVehicleNeedsFirst` | «اشتري {vehicle} الأول» |
  | `buyVehicleNoPrice` | «العربية دي مش للبيع دلوقتي» |
  | `buyVehicleDone` (close) | «تمام» |
  | `buyVehicleBoughtA11y` | «اشتريت {vehicle}! {line} اتفتح.» |
  | `lineDetailsSummary` | «{stars} من {max} نجمة · {done} مشوار خلص», with plurals |
  | `buyVehicleSeats` | «{n} كرسي بدل {m}», with plurals |

- The owner approves the drafts before merge (owner action).

## R15. Navigation and links (FR-053, FR-054)

**Decision.**

- **The routes exist** (M03): `/lines`, `/lines/:lineId`, `/lines/vehicle/:vehicleId`. This feature
  adds `/lines/:lineId/pre-trip/:tripId` (R5) and replaces the three placeholders in
  `router.dart:_page` with `LinesScreen`, `LineDetailsSheet` and `VehicleSheet`.
- **Unknown ids.** A malformed id already redirects (the validators). An id the active pack lacks
  is well-formed but missing: the sheet doesn't render and goes to `/lines` after the frame, the way
  M08's card leaves.
- **The all-destinations goldens** for these routes (`test/goldens/goldens/all/{lines,lineDetail,
  vehiclePurchase}_*.png`) and the routing tests that name them are regenerated, and the change is
  reviewed in the PR.

## R16. Tests and coverage (SC-001–SC-008, constitution XIII)

**Decision.** Tests first for the pure parts.

- **Unit:**
  - `playable_test.dart`, with R1's sweep;
  - the lines domain: standings, the focus line, cells and range, `VehicleOffer`, the impact, news;
  - `VehiclePurchase` against a fake `Economy`: every outcome, a double tap, a retry.
- **Widget:**
  - Lines, LineDetails and the vehicle sheet in every state;
  - `startNextTrip` from Lines, and the card's return;
  - the lines tab opening at its root;
  - the dot: shows, clears, survives a restart, no dot for a purchase made on Lines;
  - a sync rollback redrawing an open sheet.
- **Design:** three artboards now, six to eight boards when exported (R12).
- **a11y sizes** (R13).
- **Integration** (`integration_test/lines_loop_test.dart`, headless like M08's): offline, a scripted
  chapter-2 player buys the microbus on Lines, then «كمّل» on خط الجامعة, then the card, the trip
  `line_gamaa.01`, the result, and back to Lines with the microbus current. This also proves SC-002.
- **Against the dev stack** (`backend` tag, the `sync-e2e` job): a new case in
  `test/backend/` syncs that purchase and that trip start. Both are accepted, with no
  `not_unlocked` (SC-003).
- **Content:** content-kit examples and rules, the content_models round trip, the backend content
  app (import/export byte check, admin forms, build), and the golden and dev bundle checks.
- Coverage ≥ 80% on the app (`check_coverage.dart`), on content_kit and on the backend.

## R17. Performance (SC-008)

**Decision.**

- **Every derivation is O(lines × trips)** over at most about 140 trips in the full game, computed
  once per new view in a provider and not per frame.
- **The sheets open from memory**, with no I/O and no loading state.
- **Previews.** The Rive `Vehicle` artboard is already decoded at boot (step `art`). The tile strip
  draws four small instances; if a device pass shows a cost, tiles fall back to the static SVGs.
- **Measured** in the device pass: Lines, details and the sheet within 0.5 s of the tap on the
  reference device.

## R18. Guards, docs and agent context

**Decision.**

- **`domain_imports_test.dart`.** `lib/features/lines/domain/` gets its own list: content models,
  the content source, the economy's wire, the progress domain, and M08's `home/domain/savings_target.dart`
  and `next_trip.dart`. `playable.dart` lives under the existing progress entry.
- **Other guards apply unchanged**: no Arabic literals, no raw style values, integer money, no ink.
- **Docs:**
  - `docs/architecture-mobile.md` §13: the phone-only rules beside the port.
  - `docs/architecture-mobile.md` §9: the card's route under Lines and the lines tab's root.
  - `docs/architecture-backend.md` §9: the three fields.
  - `content/README.md`; B04's `contracts/content-schemas.md` and `data-model.md` rows.
  - `docs/runbooks/content-publishing.md`: rebuild after a schema change.
  - `docs/delivery-plan.md`: Design sources (the boards), Progress.
  - `docs/owner-actions.md`: section 014, created at plan time for the boards and completed at
    implement time.
- **CLAUDE.md** is edited by hand at implement time (the agent-context script isn't run):
  - M09 in the project status;
  - `pref.lines_seen`;
  - the lines domain in the guards line;
  - the synced vehicle art.

## R19. Handed to later features

- **M10:**
  - the chapter-2 goal card opens `/lines/vehicle/micro_old`;
  - the scene after the microbus purchase (`what_do_you_do`) is an arrival item on Home;
  - its story screens start trips through `startNextTrip`, so they get `tripPlayable`;
  - the shared unlock fixture may carry FR-007 to the server.
- **M11:** the checkpoint already covers starts from Lines.
- **M12:** the fuel sheet behind an empty tank from Lines, and the shop behind the BONAT pill.
- **M15:**
  - `StartFrom.lines`;
  - a `vehicle_purchase` event at `VehiclePurchase`'s applied outcome;
  - a line opened, from the news keys.
- **M16:** owned tiles open the garage; the preview wears cosmetics with «بزينتك».
