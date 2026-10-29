---

description: "Task list for M09 Lines Map, Line Details and Vehicle Purchase"
---

# Tasks: Lines Map, Line Details and Vehicle Purchase (M09)

**Input**: Design documents from `specs/014-m09-lines-vehicles/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**:

- **Mandatory, and first** (constitution XIII). Write the tests first for every pure function and
  for the purchase:
  - `tripPlayable`, `vehicleSale`, `currentVehicle`, with the never-more-permissive sweep;
  - the lines domain: standings, tiles, the focus line, cells and range, the offer, the impact,
    the news;
  - `VehiclePurchase`.

  Every phase writes its tests first, and they must fail before its implementation tasks start.
- **Real economy.** Economy-backed tests use the real `EconomyService` over in-memory drift
  (`test/helpers/economy.dart`). `VehiclePurchase`'s outcome table also runs against a fake
  `Economy`.
- **Packs.**
  - The sample pack;
  - `synthetic_packs.dart`'s new `draftShaped()`: the release draft's shape, with story trips
    `line_hay.20`, `line_gamaa.01` and `line_gamaa.18`;
  - `artboardLines()`: the artboards' four vehicles and five lines;
  - M07's `tutorial_content.dart` for first-session states.
- **Coverage.** At least 80% of lines in `apps/mobile`, `tools/content_kit` and `backend`.

**Organization**:

- **Paths and commands.** Paths are from the repository root. Dart commands run with `fvm` in
  `apps/mobile/` (or the package named). Python commands run with `uv` in the folder named.
- **Codegen.**
  - After a `@riverpod` provider: `fvm dart run build_runner build -d`.
  - After ARB keys: `fvm flutter pub get`.
  - After a schema change: `uv run wassal-content codegen` in `tools/content_kit`, then
    `build_runner` in `packages/content_models`.
- **Exactness.** Every number is from the contracts and HANDOFF. Name each as a constant in `lib/`,
  never a bare literal. Radii, colours, type and shadows come from the tokens (the raw-style guard).
  The list:
  - **Strip:** height 96; tiles 83.5×96, gap 8, four columns at most; vehicle art 64×40 in a tile.
  - **Map:**
    - cards 324 wide and 92 tall at least, gap 12;
    - the road 6 wide, dashes 10 on and 8 off, inset 20;
    - nodes 32 (current) and 24 (done, locked);
    - «كمّل» 63×44.
  - **Grid:**
    - cells ≈65×62, gap 8, five per row;
    - rows `max(4, nextRow + 2)`, capped at the line's rows;
    - every row for a done line; four for a locked line.
  - **Sheet:** the preview 358×190; the benefit tiles about 114×79.
  - **Rules:** the never-more-permissive sweep's depth is 8. A fare is "integer ≥ 50, multiple
    of 50".
  - **Checks:** the layout tests' tolerance ±2 pt; SC-008's 0.5 s.
- **Names** are the contracts', spelled exactly:
  - `tripPlayable`, `currentVehicle`, `vehicleSale` with `Owned` | `ForSale` | `NeedsFirst` |
    `NoPrice`;
  - `LineStanding`, `VehicleTile`, `TripCell`, `VehicleOffer`, `Impact`, `LinesNews`;
  - `LinesModel`, `LinesSeenNotifier`, `LinesDotWatcher`, `VehiclePurchase`;
  - `StartFrom.lines`, `RouteNames.linePreTrip` (`/lines/:lineId/pre-trip/:tripId`), the card's
    `leaveTo`;
  - `pref.lines_seen`;
  - the content fields `whats_new`, `display_fare_piasters`, `short_name` (Dart `whatsNew`,
    `displayFarePiasters`, `shortName`).
- **Shared files.** These grow story by story, so tasks that touch them run in order:
  - `apps/mobile/lib/core/routing/{routes.dart,router.dart,shell_scaffold.dart}`;
  - `apps/mobile/lib/l10n/app_ar.arb`;
  - `apps/mobile/lib/features/home/application/start_next_trip.dart`;
  - `apps/mobile/lib/features/pre_trip/presentation/pre_trip_card.dart`;
  - `apps/mobile/lib/features/lines/presentation/{lines_screen.dart,line_card.dart,line_details_sheet.dart,vehicle_sheet.dart}`;
  - `apps/mobile/lib/bootstrap/app.dart`;
  - `apps/mobile/test/helpers/synthetic_packs.dart`;
  - `apps/mobile/test/repo/domain_imports_test.dart`.
- **No phone database, engine, operation, tunable or server-rule change** (plan). The only backend
  change is B04's content app. A task that seems to need more is wrong; stop and ask.
- **One PR.** Its description lists:
  - the departures from the design (plan "Complexity Tracking");
  - the changes to M08's merged code (plan "What changes in M08's merged code");
  - the expected golden differences (research R12);
  - the staging rebuild after deploy (research R9).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story the task belongs to (US1–US6 from spec.md)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: The vehicle fallbacks and the one preference key.

- [X] T001 [P] Add `microbus_new.svg` and `microbus_travel.svg` (from
  `docs/design/illustrations/vehicles/`) to the vehicle list in
  `apps/mobile/tool/design/sync_assets.dart`, with a comment naming research R10. Run
  `fvm dart run tool/design/sync_assets.dart` so `apps/mobile/assets/illustrations/vehicles/` holds
  all four. Run `test/repo/design_assets_test.dart`, updating its expectations only where they pin
  the vehicle files.
- [X] T002 [P] Add `'pref.lines_seen'` to `SharedPrefsSettingsStore.keys` in
  `apps/mobile/lib/core/preferences/shared_prefs_settings_store.dart` and to the allowed list in
  `apps/mobile/test/helpers/memory_settings_store.dart`, with a comment naming research R8: a read
  marker, not game state. Run `test/repo/no_secret_logging_test.dart`.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The three content fields end to end, the phone-only rules, the test packs and the
imports guard.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### The content fields ([contracts/content-fields.md](./contracts/content-fields.md))

- [X] T003 Edit `content/schemas/line.schema.json` and add both new properties to `required` and
  `properties`:
  - `whats_new`: `{"$ref": "common.schema.json#/$defs/LocalizedText"}` (`ar-EG` required, `ar`
    optional);
  - `display_fare_piasters`: `{"$ref": "common.schema.json#/$defs/PositivePiasters"}` (integer ≥ 50,
    multiple of 50).

  Edit `content/schemas/vehicle.schema.json`: `short_name` →
  `{"$ref": "common.schema.json#/$defs/LocalizedText"}`, required.

  Then, in `tools/content_kit`:
  1. `uv run wassal-content codegen`, then commit
     `tools/content_kit/src/wassal_content/schemas/{line,vehicle}.schema.json` and
     `models/_generated.py`;
  2. `uv run wassal-content codegen --check`;
  3. confirm `uv run wassal-content schema-diff --base origin/master` reports nothing blocking (no
     `content/source/pack.json`).

  `content/schemas/schema-set.json` stays `1.0`.
- [X] T004 In `packages/content_models` run `fvm dart pub get && fvm dart run build_runner build -d`.
  Confirm `lib/src/generated/line.dart` has `LocalizedText whatsNew` and `int displayFarePiasters`,
  and `vehicle.dart` has `LocalizedText shortName`. Commit the two generated files. (Depends on
  T003.)
- [X] T005 [P] Update the examples so each still reports only its own error (contracts/content-fields.md
  "Examples and the sample"):
  - **Add the fields** to `content/examples/valid/line/{line_hay,line_gamaa}.json`,
    `valid/vehicle/micro_old.json`, `valid/pack/core.json`, and every
    `content/examples/invalid/line/*.json` and `invalid/vehicle/*.json`.
  - **New invalid examples:**
    - `invalid/line/display_fare_475.json` → `$.display_fare_piasters`;
    - `invalid/vehicle/no_short_name.json` → `$.short_name`;
    - `invalid/line/whats_new_digit.json` → rule `V-X1` at `$.whats_new.ar-EG`.

    List all three in `invalid/expected.json`.
  - **Rule test:** add a V-X1 case for `whats_new` to `tools/content_kit/tests/test_rules.py`.

  Run `uv run pytest` in `tools/content_kit`, then `fvm dart test` in `packages/content_models` (the
  round trip reads the fields). (Depends on T003, T004.)
- [X] T006 Update the sample in the export format (sorted keys, 2-space indent, trailing newline):
  - `content/examples/sample/lines/line_hay.json`: `display_fare_piasters: 700`, `whats_new`
    `{"ar-EG": "تعلّم اللمّ والباقي، الحاجة، النايم، المستعجل"}`;
  - `content/examples/sample/lines/line_gamaa.json`: `display_fare_piasters: 850`, `whats_new`
    `{"ar-EG": "نص الأجرة، الدفع الجماعي، \"أنا دافع!\"، أبو سمّاعة"}`;
  - `content/examples/sample/vehicles/tuktuk.json`: `short_name` `{"ar-EG": "توكتوك"}`;
  - `content/examples/sample/vehicles/micro_old.json`: `short_name` `{"ar-EG": "قديم"}`.

  Then, in `tools/content_kit`:
  1. `uv run wassal-content validate-source ../../content/examples/sample`;
  2. `uv run wassal-content golden --update`, then review `content/examples/sample.golden.json`;
  3. `uv run wassal-content bundle dev --out ../../apps/mobile/assets/content/dev`.

  Commit `apps/mobile/assets/content/dev/{core-1.json.gz,bundled.json}`. (Depends on T003.)
- [X] T007 [P] Fix the mobile fixtures that build lines or vehicles by hand:
  - the literal `Vehicle.fromJson` in `apps/mobile/test/core/economy/domain/wire_test.dart` gains
    `'short_name': {'ar-EG': 'x'}`;
  - `apps/mobile/test/fixtures/tutorial/lines/line_hay.json` gains `display_fare_piasters: 700` and
    the sample's `whats_new`;
  - `apps/mobile/test/fixtures/tutorial/README.md`'s provenance note says the fields were added here
    ahead of the draft.

  Run `test/repo/bundled_pack_test.dart` and `test/features/onboarding/`. (Depends on T004, T006.)
- [X] T008 Backend models, in `backend/`:
  - **Move** `COIN_PIASTERS` and `multiple_of_coin()` from `apps/content/models/trips.py` to
    `apps/content/models/base.py` (`trips.py` imports `lines.py`, so `lines.py` can't import from
    it). Import them back in `trips.py`.
  - **`Line`** in `apps/content/models/lines.py`:
    - `whats_new_ar_eg = TextField()`, `whats_new_ar = TextField(blank=True)`;
    - `display_fare_piasters = PositiveIntegerField(validators=[MinValueValidator(50)])`;
    - a `CheckConstraint` for "≥ 50 and a multiple of 50", and the same check in `clean()`.
  - **`Vehicle`:** `short_name_ar_eg = TextField()`, `short_name_ar = TextField(blank=True)`.
  - **Migration:** `uv run manage.py makemigrations content -n line_vehicle_display_fields`
    (`0010`). Give existing rows `default`/`db_default`: fare 50, texts `''`, as
    `0006_trip_no_fights_required.py` did.
  - **Reinstall:** `uv sync --reinstall-package wassal-content` here and in `tools/solver`.
  - **Check:** `uv run manage.py makemigrations --check --dry-run`. (Depends on T003.)
- [X] T009 Backend services and tests, in `backend/`:
  - **Services:**
    - `apps/content/services/importer.py`: `vehicle()` reads `short_name` through `_text`, and
      `line()` reads `whats_new` and `display_fare_piasters`;
    - `apps/content/services/snapshot.py`: `line_part()` and `vehicle_part()` write them;
    - `apps/content/admin/authoring.py`: `LineAdmin.fields` gains the three line columns, and
      `list_display` the fare; `VehicleAdmin.fields` gains the two vehicle columns.
  - **Tests:**
    - `tests/factories.py` defaults;
    - the POST data in `tests/test_admin_authoring.py` and `tests/test_history.py`;
    - `tests/test_import_export.py`: the fields round-trip byte for byte;
    - `tests/test_models.py`: a 475 fare and a 0 fare are refused.
  - **Run:** `uv run ruff check . && uv run ruff format --check . && uv run mypy . && uv run pytest
    -n 4 --cov --cov-fail-under=80`. (Depends on T008, T006.)
- [ ] T010 Update the release draft in the `content-core-r1` worktree, uncommitted like the rest of
  the draft (research R9):
  - `../wasal_ogra-core-r1/content/drafts/core-r1/pack/lines/{line_hay,line_gamaa}.json` gain T006's
    fares and texts;
  - `pack/vehicles/{tuktuk,micro_old}.json` gain the short names.

  Run `uv run wassal-content validate-source` on the draft from this branch's `tools/content_kit`.
  Note the change in `docs/owner-actions.md` section 014 (T089 asks the owner to confirm the texts).
  (Depends on T003.)

### The rules and the test packs: tests first

- [X] T011 [P] Extend `apps/mobile/test/repo/domain_imports_test.dart` with
  `lib/features/lines/domain`, which may import only:
  - `package:content_models/`;
  - `lib/core/content/domain/content_source.dart`;
  - `lib/core/economy/domain/wire.dart`;
  - `lib/core/progress/domain/`;
  - `lib/features/home/domain/{savings_target.dart,next_trip.dart}`;
  - its own folder.

  The progress entry is unchanged (`playable.dart` fits it).
- [X] T012 [P] Add two packs to `apps/mobile/test/helpers/synthetic_packs.dart`, over the sample, with
  the new fields filled:
  - **`draftShaped()`:**
    - `line_hay`: 19 regular trips and story `.20`;
    - `line_gamaa`: 30 trips, with story `.01` and `.18`;
    - chapters `ch1_first_job` (`complete_line line_hay`, story `line_hay.20`), `ch2_her_father`
      (`own_vehicle micro_old`, story `line_gamaa.01`) and `ch3_shabka` (`purchase`, story
      `line_gamaa.18`), with catalog prices `micro_old` 3,200 and `ch3_shabka` as the draft;
  - **`artboardLines()`:**
    - vehicles `tuktuk`, `micro_old`, `micro_new` (5,000) and `micro_safar` (12,000);
    - lines `line_hay`, `line_gamaa`, `line_souq` (vehicle `micro_new`), `line_masyaf`
      (`line_complete line_souq`) and `line_safar` (vehicle `micro_safar`);
    - the boards' fares (٧, ٨٫٥, ١٣, ١١, ٤٣ ج) and texts.
- [X] T013 Write `apps/mobile/test/core/progress/playable_test.dart`
  ([contracts/progress-rules.md](./contracts/progress-rules.md) "Guarantees"). It must fail.
  - **Never more permissive:** sweep the sample and `draftShaped()` at depth 8, finishing playable
    trips and buying for-sale vehicles:
    - `tripPlayable ⇒ tripUnlocked` for every trip;
    - `vehicleSale is ForSale ⇒` M05's `validateBuy` accepts the vehicle with enough JENEHAT.
  - **The US5 cases by name:**
    - `line_gamaa.01` is locked without the microbus in every chapter;
    - `line_hay.20` becomes playable exactly when `.01`–`.19` have a star;
    - `.18` is locked after `.17` until `ch3_shabka` is owned, while `.19` is playable;
    - after the shabka, `.18` is playable with `.19`–`.22` done.
  - **Vehicles:**
    - `NeedsFirst(micro_old)` for `micro_new` in `artboardLines()`;
    - `NoPrice` for the starter and for a BONAT price;
    - `Owned` for the starter.
  - **`currentVehicle`;** unknown ids.
- [X] T014 Implement `apps/mobile/lib/core/progress/domain/playable.dart` exactly as
  contracts/progress-rules.md "Functions": `tripPlayable`, `currentVehicle` and `vehicleSale`, with
  the sealed `VehicleSale`. Leave `unlocks.dart` untouched. Make T013 pass, then run
  `test/core/progress/` and `test/repo/domain_imports_test.dart`.

**Checkpoint**: The fields are in every model and pack, and the rules are proven never more
permissive. Stories can start.

---

## Phase 3: User Story 1 - See where I stand: my vehicles and the lines (Priority: P1) 🎯 MVP

**Goal**: The Lines tab shows the balances, the vehicle strip and the line map in pack order,
opening on Home's line ([contracts/lines.md](./contracts/lines.md)).

**Independent Test**: With the sample and a scripted state, offline, open Lines. Check that:

- the tiles, each card's standing, fare, stars and next trip match the state;
- the map shows Home's line;
- the same holds for the first-session state and for a finished first line.

### Tests for User Story 1 ⚠️

- [X] T015 [P] [US1] Write `apps/mobile/test/features/lines/domain/line_standing_test.dart`:
  - locked by a vehicle (`NeedsVehicle`) and by a line (`AfterLine`);
  - current with its next trip `(id, number, total)`;
  - done;
  - stars earned out of `3 × trips`; `allThree`; `doneCount`;
  - a newer pack adding trips to a done line makes it current;
  - ids the pack lacks are skipped.
- [X] T016 [P] [US1] Write `apps/mobile/test/features/lines/domain/vehicle_tiles_test.dart`:
  - done, current (the last owned by order), `forSale(price)`, `notForSale`;
  - the starter always the player's;
  - a rollback (the vehicle no longer owned) makes it `forSale` again.
- [X] T017 [P] [US1] Write `apps/mobile/test/features/lines/domain/focus_line_test.dart`:
  - the line of `homeNextTrip` (M07's tutorial trip in the first session);
  - with none, the last current line, else the last unlocked one;
  - two current lines (the microbus bought early).
- [X] T018 [P] [US1] Write `apps/mobile/test/features/lines/lines_screen_test.dart`:
  - the header: the coins pill without a tap, BONAT → `/shop`, and BONAT disabled offline with
    `homeA11yBonatOffline`;
  - every tile and card state;
  - a tile → `/lines/vehicle/<id>`; a current or done card outside «كمّل» → `/lines/<line>`;
  - «كمّل» present as its own 63×44 button with `linesContinueA11y`;
  - cards bottom-up in reading order top to bottom;
  - the focus card in view on first frame;
  - five lines at text scale 1.3 scroll;
  - a sync that changes the balance or progress redraws without reopening.

### Implementation for User Story 1

- [X] T019 [P] [US1] Implement `apps/mobile/lib/features/lines/domain/line_standing.dart` (data-model
  `LineStanding`). The next trip is the first trip by number that is `tripPlayable` with no star.
- [X] T020 [P] [US1] Implement `apps/mobile/lib/features/lines/domain/vehicle_tiles.dart` (data-model
  `VehicleTile`) from `currentVehicle` and `vehicleSale`.
- [X] T021 [P] [US1] Implement `apps/mobile/lib/features/lines/domain/focus_line.dart`
  (`focusLine(c, p, next)`).
- [X] T022 [US1] Implement `apps/mobile/lib/features/lines/application/lines_model.dart`
  (`linesModelProvider`, contracts/lines.md "The model"). It watches:
  - `contentSourceProvider`, `playerProgressProvider` and `economyViewProvider`;
  - `firstSessionProvider` and `lastFinishedTripProvider`, for `homeNextTrip`;
  - reachability, for `online`.

  Run build_runner. Make T015–T017 pass.
- [X] T023 [P] [US1] Create `apps/mobile/lib/features/lines/presentation/locked_fill.dart`: the
  §9.1 #6 decoration for tiles and cells (`lockedBg`, the 2 pt locked ring, `ink2`, the `lock`
  icon, no opacity), from the tokens. Create `fare_chip.dart`, which formats with
  `NumberFormatter.piasters` + «ج».
- [X] T024 [P] [US1] Create `apps/mobile/lib/features/lines/presentation/vehicle_art.dart` (each
  `VehicleId` → its synced SVG, as the static fallback) and `vehicle_strip.dart`:
  - `role=list` «العربيات», tiles from the right;
  - done (tick badge), current («{short} · عربيتك», `sun` with lip), for sale (the locked fill with
    the price), not for sale (the locked fill);
  - each a `Pressable` with the board's label.
- [X] T025 [P] [US1] Create `apps/mobile/lib/features/lines/presentation/line_card.dart`:
  - **current:** `AppCard` with the 3 pt `primary` ring, the name with `FareChip`, what's new, the
    star line, and «كمّل» as its own `Pressable` (`onContinue` callback);
  - **done:** `StatusChip.done`, «عيد عشان النجوم» unless `allThree`;
  - **locked:** `AppCard(locked: true)`, the reason + « · {what's new}», the fare.

  Labels per `linesCardA11y`. Text wraps and the card grows.
- [X] T026 [US1] Create `apps/mobile/lib/features/lines/presentation/line_map.dart`:
  - a scroll view with the cards bottom-up and a gap of 12;
  - `RoadPainter`: 6 wide, 10 on / 8 off, `icon.off`, as tall as the content and never shorter than
    the map;
  - the nodes;
  - `ensureVisible` on the focus card after the first frame, with no animation under reduced motion.
- [X] T027 [US1] Create `apps/mobile/lib/features/lines/presentation/lines_screen.dart`:
  - the header: «الخطوط» with `CurrencyPill.coin` and `CurrencyPill.bonat` (disabled offline, as
    M08's Home header);
  - the strip and the map;
  - tile and card taps through `NavGuard.go` (the `onContinue` stays unwired until T044).
- [X] T028 [US1] Add the Lines strings to `apps/mobile/lib/l10n/app_ar.arb` (HANDOFF `lines.*` and
  research R14), then run `fvm flutter pub get`:
  - `linesTitle`, `linesVehiclesA11y`, `linesTileCurrent`;
  - `linesTileA11yDone`, `linesTileA11yCurrent`, `linesTileA11yPrice`;
  - `linesStars`, `linesTripOf`, `linesReplay`;
  - `linesNeedsVehicle`, `linesAfterLine`;
  - `linesCardA11y`, `linesStandingCurrent`, `linesStandingDone`, `linesStandingLocked`;
  - `linesContinue`, `linesContinueA11y`.
- [X] T029 [US1] In `apps/mobile/lib/core/routing/router.dart`'s `_page`, build `LinesScreen()` for
  `RouteNames.lines` in place of `PlaceholderScreen`. Regenerate and review
  `test/goldens/goldens/all/lines_*.png` and the shell's `lines_*`/`dot_lines_*` goldens. Update
  `test/core/routing/{navigation,frame_design}_test.dart` where they expect the placeholder. Make
  T018 pass.
- [X] T030 [P] [US1] Add the `Lines` design checks:
  - `apps/mobile/test/design/samples/lines.dart` (`pumpLines`, `artboardLines()` with the board's
    state: coins 1,240, BONAT 85, خط الجامعة current at 12 of 30 with 27/90, خط الحي done 54/60);
  - `test/design/lines_layout_test.dart` (`expectLayoutMatches(tester, 'Lines', …)`): pair the five
    unlabelled cards (boxes 25, 31, 37, 43, 52), and pair «كمّل» with box 51;
  - `test/goldens/design/lines_goldens_test.dart`, in both digit styles.

  List the expected differences (research R12) at the top of both tests.
- [X] T031 [P] [US1] Write `apps/mobile/test/a11y/lines_minimum_sizes_test.dart`: every tappable
  ≥ 44×44 and every text ≥ 12 pt, at 360×640, 360×800 and 390×844, scale 1.0 and 1.3.

**Checkpoint**: Lines shows where the player stands, offline.

---

## Phase 4: User Story 2 - Play the next trip of a line, or replay one for stars (Priority: P1)

**Goal**: A line's details sheet with the trip grid, and every start from Lines through M08's start
path, with the card closing back to the details
([contracts/line-details.md](./contracts/line-details.md)).

**Independent Test**: For trips 1–11 done with mixed stars, trip 10 a story trip, and the card
setting on «always»:

- cells 1–11 show their stars, and 10 shows «قصة»;
- 12 is next, and 13 onward are locked;
- the button reads «العب المشوار ١٢»;
- cells 3 and 12 and the button each open the card for that trip, and its close returns to the
  details;
- cell 13 does nothing.

### Tests for User Story 2 ⚠️

- [X] T032 [P] [US2] Write `apps/mobile/test/features/lines/domain/trip_cells_test.dart`:
  - every state: done, storyDone, next, playable, locked, storyLocked;
  - a story cell keeping its chip when next or playable;
  - the next trip with an earlier locked story cell;
  - two playable cells after the shabka (`draftShaped()`);
  - `visibleRange` for 3, 20, 30 and 40 trips with next at 1, 12 and 19, and for none;
  - a done line (every row) and a locked line (four rows);
  - the hint's `(from, to)`.
- [X] T033 [P] [US2] Write `apps/mobile/test/features/lines/line_details_sheet_test.dart`:
  - the header and its plural summary;
  - the grid five per row from the right;
  - the hint shown and hidden;
  - the note;
  - the pinned button, and no button for a done line;
  - each cell's tap;
  - a locked cell inert, with no button semantics;
  - closing with ✕, swipe, scrim and back to `/lines`;
  - the grid scrolling above the button at 1.3.
- [X] T034 [P] [US2] Extend `apps/mobile/test/features/home/application/start_next_trip_test.dart`:
  - `from: StartFrom.lines` opens `/lines/<line>/pre-trip/<id>`;
  - a trip that isn't `tripPlayable` returns false and goes nowhere;
  - a tutorial trip in the first session goes to `/trip/<id>`;
  - an empty tank goes to the fuel sheet;
  - a second tap while the checkpoint waits does nothing;
  - `home` and `result` still open `/home/pre-trip/<id>`.
- [X] T035 [P] [US2] Extend `apps/mobile/test/features/pre_trip/pre_trip_card_test.dart`:
  - under `/lines/<line>/pre-trip/<id>`, the four closes land on `/lines/<line>`;
  - an unknown or unplayable trip leaves to `leaveTo`;
  - the Home cases keep `/home`.
- [X] T036 [P] [US2] Extend `apps/mobile/test/core/routing/{shell,route_table}_test.dart`:
  - the new route and its two validators;
  - card → «اطلع» → result → Home → «الخطوط» shows `/lines`, not the card;
  - the other tabs keep M03's restore.

### Implementation for User Story 2

- [X] T037 [P] [US2] Implement `apps/mobile/lib/features/lines/domain/trip_cells.dart` (`tripCells`,
  `visibleRange`, contracts/line-details.md "The cells"). Make T032 pass.
- [X] T038 [US2] Create `apps/mobile/lib/features/lines/presentation/trip_grid.dart` with the
  `TripCell` widget and the grid:
  - ≈65×62 cells, gap 8, `role=list` «مشاوير الخط»;
  - done in `ground` with `Stars` 12; storyDone in `sun.soft` with the «قصة» chip above;
  - next in `primary` with lip, the number and «كمّل», marked `selected`; playable without «كمّل»;
  - locked and storyLocked through `locked_fill.dart`;
  - labels `lineDetailsCellA11y`.
- [X] T039 [US2] Create `apps/mobile/lib/features/lines/presentation/line_details_sheet.dart`:
  - the header (name, plural summary, `IconCircleButton` close);
  - the grid in a scroll view;
  - the hint and the note (first sentence only for a done line);
  - `AppButton.primary(xl)` «العب المشوار {n}», pinned; none for a done line.

  Cell and button taps call `startNextTrip(..., from: StartFrom.lines)`.
- [X] T040 [US2] Change `apps/mobile/lib/features/home/application/start_next_trip.dart`:
  - `StartFrom` gains `lines`;
  - a new first step returns false unless `tripPlayable(content, progress, tripId)`;
  - the card's location follows `from`: `home` and `result` → `/home/pre-trip/<id>`; `lines` →
    `/lines/<line wire>/pre-trip/<id>`, with the line from the trip's own `lineId` (`toGlossaryLine`).

  Make T034 pass.
- [X] T041 [US2] Add `RouteNames.linePreTrip` to `apps/mobile/lib/core/routing/routes.dart`:
  `/lines/:lineId/pre-trip/:tripId`, a sheet in `Section.lines` with both validators, linked from
  `lineDetail`. In `router.dart`:
  - nest it under `lineDetail`;
  - build `PreTripCard(key: ValueKey(tripId), tripId:, leaveTo: '/lines/<lineId>')` with
    `ownHeader`;
  - build `LineDetailsSheet(lineId)` for `RouteNames.lineDetail`.
- [X] T042 [US2] Add `leaveTo` (default `'/home'`) to
  `apps/mobile/lib/features/pre_trip/presentation/pre_trip_card.dart`. Its `_leave()` goes there;
  its close still pops. Make T035 pass.
- [X] T043 [US2] In `apps/mobile/lib/core/routing/shell_scaffold.dart`, the tab tap passes
  `initialLocation: true` for `Section.lines`, and `index == shell.currentIndex` for the others,
  with a comment naming research R5. Make T036 pass.
- [X] T044 [US2] Wire «كمّل» in `apps/mobile/lib/features/lines/presentation/lines_screen.dart`
  (`LineCard.onContinue`) to `startNextTrip(context, ref, tripId: next, from: StartFrom.lines)`.
  Extend T018's test: «كمّل» opens the card, and its close lands on the line's details.
- [X] T045 [US2] Add the details strings to `apps/mobile/lib/l10n/app_ar.arb`, then run
  `fvm flutter pub get`:
  - `lineDetailsSummary`, with plurals for stars and trips;
  - `lineDetailsTripsA11y`, `lineDetailsHint`;
  - `lineDetailsNote1`, `lineDetailsNote2`;
  - `lineDetailsPlay`;
  - `lineDetailsCellA11y`, with its states and the story suffix.

  Make T033 pass.
- [X] T046 [P] [US2] Add the `LineDetails` design checks:
  - `apps/mobile/test/design/samples/line_details.dart`: `artboardLines()`, خط الجامعة with next
    12, the board's stars per cell, trip 10 story done, trip 20 story locked;
  - `test/design/line_details_layout_test.dart` (close paired to «قفل», as M08);
  - `test/goldens/design/line_details_goldens_test.dart`.

  Expected differences: the locked fill, the summary 25 against 27, and the real Lines under the
  scrim.
- [X] T047 [P] [US2] Write `apps/mobile/test/a11y/line_details_minimum_sizes_test.dart` (the same
  surfaces and scales as T031).

**Checkpoint**: A player can choose, play and replay any open trip from Lines, and the card closes
back to the line.

---

## Phase 5: User Story 3 - Buy the next vehicle and open its line (Priority: P1)

**Goal**: The vehicle sheet with the offer, the shortfall and the impact line, and one purchase per
intent through M05's `buy`, offline ([contracts/buy-vehicle.md](./contracts/buy-vehicle.md)).

**Independent Test**: Offline, with coins above the microbus's catalog price:

- open the sheet and check the facts and the impact line;
- «اشتريها»: the coins drop by the price once, the microbus is current, and خط الجامعة opens and
  can start;
- below the price: the shortfall shows and nothing can be bought;
- a double tap spends once.

### Tests for User Story 3 ⚠️

- [X] T048 [P] [US3] Write `apps/mobile/test/features/lines/domain/vehicle_offer_test.dart`:
  - the seats against the current vehicle's;
  - `opensLine`, the first by order, and null with none;
  - each `VehicleSale`;
  - the shortfall; exactly enough leaves 0 and no shortfall.
- [X] T049 [P] [US3] Write `apps/mobile/test/features/lines/domain/impact_test.dart`:
  - `micro_old` in ch2 of `draftShaped()` → «الشبكة» and `chapterPrice − (jenehat − 3200)`;
  - an apartment-piece target;
  - a line goal (`Count`) → null; `NoTarget` → null;
  - nothing missing → null; not affordable → null.
- [X] T050 [P] [US3] Write `apps/mobile/test/features/lines/application/vehicle_purchase_test.dart`
  against a fake `Economy`, covering every row of contracts/buy-vehicle.md "Buying":
  - a double tap makes one `buy`;
  - a retry after `OpWriteFailed` reuses the id;
  - busy returns null;
  - not `ForSale` makes no `buy`.

  Then the same against the real `EconomyService`: the price is spent once, and ownership is
  written.
- [X] T051 [P] [US3] Write `apps/mobile/test/features/lines/vehicle_sheet_test.dart`:
  - **Affordable:** the name, the preview (decorative), the three benefits, the price card as one
    label, the impact line and the two buttons.
  - **Short:** «ناقصك {n} ج», the gold bar, «اشتريها» disabled, no impact.
  - **Outcomes:**
    - applied → `/lines` with the announcement;
    - refused, write-failed and not-for-sale, each with its result;
    - a sync flipping short ↔ affordable while open;
    - a rollback after a purchase.
  - **Closing:** «لسه», ✕, swipe and back, with nothing spent.
  - **An id the pack lacks** goes to `/lines`.

### Implementation for User Story 3

- [X] T052 [P] [US3] Implement `apps/mobile/lib/features/lines/domain/impact.dart`
  (`impactAfterPurchase`, contracts/buy-vehicle.md "The offer"). Use M08's `savingsTarget` with `p`
  plus `(SkuKind.vehicle, wire)` and `jenehat − price`. Make T049 pass.
- [X] T053 [US3] Implement `apps/mobile/lib/features/lines/domain/vehicle_offer.dart`
  (`vehicleOffer`, data-model `VehicleOffer`). Make T048 pass.
- [X] T054 [US3] Implement `apps/mobile/lib/features/lines/application/vehicle_offer_provider.dart`
  and `vehicle_purchase.dart`:
  - `VehiclePurchase(Economy)`: `_id ??= newRequestId()`, a busy flag, the `ForSale` check, then
    `buy(kind: SkuKind.vehicle, skuId: vehicleWire[id]!)`;
  - the id cleared on applied and `alreadyOwned`, kept otherwise.

  Run build_runner. Make T050 pass.
- [X] T055 [P] [US3] Create the sheet's parts in `apps/mobile/lib/features/lines/presentation/`:
  - `vehicle_preview.dart`: `VehicleSprite` with `vehicle_art.dart`'s fallback on `scene.sky` with
    the sun, 358×190, excluded from semantics, no «بزينتك»;
  - `benefits_row.dart`: three tiles, two without `opensLine`;
  - `price_card.dart`: one semantics node;
  - `impact_line.dart`.
- [X] T056 [US3] Create `apps/mobile/lib/features/lines/presentation/vehicle_sheet.dart`:
  - the affordable and short states (contracts/buy-vehicle.md "Layout");
  - «اشتريها» calls `VehiclePurchase`; each outcome handled as the contract's table;
  - the applied outcome does `NavGuard.go('/lines')` and `SemanticsService.announce`
    (`buyVehicleBoughtA11y`);
  - write-failed shows `tripRetryPurchase` above the buttons;
  - not-for-sale refusals close with `showAppToast`.
- [X] T057 [US3] In `apps/mobile/lib/core/routing/router.dart`, build `VehicleSheet(vehicleId)` for
  `RouteNames.vehiclePurchase`. Add the sheet's strings to `app_ar.arb` (HANDOFF `buyVehicle.*`,
  research R14) and run `fvm flutter pub get`:
  - `buyVehicleSeats`, with plurals;
  - `buyVehicleOpens`, `buyVehicleMorePay`;
  - `buyVehiclePrice`, `buyVehicleHave`, `buyVehiclePriceA11y`;
  - `buyVehicleImpact` «بعد الشرا، فاضل {amount} ج على {goal}»;
  - `buyVehicleShortfall`, `buyVehicleBuy`, `buyVehicleLater`;
  - `buyVehicleBoughtA11y`, `buyVehicleNotForSaleToast`.

  Regenerate `test/goldens/goldens/all/{lineDetail,vehiclePurchase}_*.png`. Make T051 pass.
- [X] T058 [P] [US3] Add the `BuyVehicle` design checks:
  - `apps/mobile/test/design/samples/buy_vehicle.dart`: `micro_new` in `artboardLines()`, coins
    6,100, a piece target giving the board's 2,400;
  - `test/design/buy_vehicle_layout_test.dart`: boxes 9, 32, 33;
  - `test/goldens/design/buy_vehicle_goldens_test.dart`.

  Expected differences: the plain preview without «بزينتك», the reworded impact line, and the real
  Lines under the scrim. Write `apps/mobile/test/a11y/buy_vehicle_minimum_sizes_test.dart`.

**Checkpoint**: US1–US3, the MVP: see, play and buy, all offline.

---

## Phase 6: User Story 4 - Locked things explain themselves (Priority: P2)

**Goal**: Locked cards lead somewhere, and the owned and not-for-sale sheets say why there is
nothing to buy.

**Independent Test**: With `artboardLines()`, tap:

- `line_souq` (vehicle rule) → the `micro_new` sheet;
- `line_masyaf` (line rule) → its locked details;
- the tuktuk and an owned microbus → the owned sheet;
- `micro_new` without the old microbus → the needs-first sheet.

### Tests for User Story 4 ⚠️

- [X] T059 [P] [US4] Extend the widget tests:
  - `lines_screen_test.dart`: a locked card with a `vehicle` rule → `/lines/vehicle/<v>`, and with
    `line_complete` → `/lines/<line>`;
  - `line_details_sheet_test.dart`: the locked state, with every cell locked, four rows with the
    hint, a zero summary, the reason in the button's place and nothing to start;
  - `vehicle_sheet_test.dart`: owned (the starter's line and a bought vehicle's line, one «تمام»,
    no price card, impact or buy), `NeedsFirst` (its status) and `NoPrice` (its status, and a tile
    without a price).

### Implementation for User Story 4

- [X] T060 [US4] In `apps/mobile/lib/features/lines/presentation/lines_screen.dart`, route a locked
  card's tap by its rule (contracts/lines.md "Actions").
- [X] T061 [US4] In `apps/mobile/lib/features/lines/presentation/line_details_sheet.dart`, add the
  locked state (FR-028): every cell `locked`, four rows, and the reason («بعد {line}» / «محتاج
  {vehicle}») as text in the button's place.
- [X] T062 [US4] In `apps/mobile/lib/features/lines/presentation/vehicle_sheet.dart`, add the owned,
  `NeedsFirst` and `NoPrice` states (contracts/buy-vehicle.md "Layout"). Each has a status line, no
  price card for owned, no buy button, and one close button «تمام». In `vehicle_strip.dart`, a
  `NoPrice` tile shows no price.
- [X] T063 [US4] Add these strings to `apps/mobile/lib/l10n/app_ar.arb` and run
  `fvm flutter pub get`:
  - `buyVehicleOwned` «دي عربيتك»;
  - `buyVehicleOwnedStarter` «دي عربية المعلم، وانت شغال عليها»;
  - `buyVehicleNeedsFirst` «اشتري {vehicle} الأول»;
  - `buyVehicleNoPrice` «العربية دي مش للبيع دلوقتي»;
  - `buyVehicleDone` «تمام»;
  - `lineDetailsLockedA11y`.

  Make T059 pass.

**Checkpoint**: Every locked thing names what opens it.

---

## Phase 7: User Story 5 - Story trips come at their moment in the line (Priority: P2)

**Goal**: Home, the card and the result treat story trips exactly as the grid does (FR-007,
FR-012).

**Independent Test**: With `draftShaped()`, script the US5 states and check that:

- each story cell, and the line's next trip, are as expected;
- Home's next trip agrees with the grid;
- the card refuses a story trip whose chapter isn't complete.

### Tests for User Story 5 ⚠️

- [X] T064 [P] [US5] Extend `apps/mobile/test/features/home/domain/next_trip_test.dart` and
  `apps/mobile/test/core/progress/sample_sweep_test.dart`:
  - Home never offers `line_gamaa.18` before `ch3_shabka` is owned (it offers `.19`);
  - `line_hay.20` comes only after `.01`–`.19`;
  - the sample's story trip `line_hay.03` waits for ch1's goal.

  Update the sweep's expected table.
- [X] T065 [P] [US5] Write `apps/mobile/test/features/lines/story_agreement_test.dart` over
  `draftShaped()`, for US5 scenarios 1–5:
  - the grid's cells;
  - Home's `homeNextTrip` and the grid's next trip on the line Home follows;
  - the card's opening check: a locked story trip pops to `leaveTo`;
  - `startNextTrip` refusing it.

### Implementation for User Story 5

- [X] T066 [US5] In `apps/mobile/lib/features/home/domain/next_trip.dart`, `startable` reads
  `tripPlayable` instead of `tripUnlocked`. `lineUnlocked` at the earliest-open-line step stays.
  Make T064 pass.
- [X] T067 [US5] In `apps/mobile/lib/features/pre_trip/presentation/pre_trip_card.dart`, the opening
  check reads `tripPlayable`. Make T065 pass, and rerun `test/features/{home,pre_trip,result}/`
  unchanged.

**Checkpoint**: No screen offers a story trip before the story reaches it.

---

## Phase 8: User Story 6 - The Lines tab says when something new is there (Priority: P3)

**Goal**: The «new» dot on «الخطوط», from news against a seen set that survives a restart
([contracts/lines.md](./contracts/lines.md) "The «new» dot").

**Independent Test**:

- finish a trip that makes the microbus affordable: the dot shows;
- open Lines: it clears;
- restart: it stays cleared;
- buy on Lines: no dot.

### Tests for User Story 6 ⚠️

- [X] T068 [P] [US6] Write `apps/mobile/test/features/lines/domain/lines_news_test.dart` and
  `test/features/lines/application/lines_seen_test.dart`:
  - **News:**
    - `line:<id>` for unlocked non-`start` lines;
    - `story:<tripId>` for playable unstarred story trips;
    - `vehicle:<id>` for affordable `ForSale` vehicles.
  - **The pref's round trip:** sorted and comma-joined.
  - **The first read with no value** takes the news as seen.
- [X] T069 [P] [US6] Write `apps/mobile/test/features/lines/lines_dot_test.dart`:
  - the dot shows after news appears while away;
  - it clears when Lines opens;
  - it stays cleared after a restart (a new container over the same `MemorySettingsStore`);
  - no dot for a purchase made on Lines;
  - no dot on a fresh install's first read.

### Implementation for User Story 6

- [X] T070 [P] [US6] Implement `apps/mobile/lib/features/lines/domain/lines_news.dart` (`linesNews`).
- [X] T071 [US6] Implement `apps/mobile/lib/features/lines/application/lines_seen.dart`:
  `LinesSeenNotifier`, keepAlive, reading and writing `pref.lines_seen` through
  `settingsStoreProvider` as M08's `PreTripCardModeNotifier`; `markSeen(news)`; the first-read
  baseline. Run build_runner. Make T068 pass.
- [X] T072 [US6] Implement `apps/mobile/lib/features/lines/application/lines_dot_watcher.dart`
  (`LinesDotWatcher(ref)`, listening to the news and seen providers and setting
  `newDotProvider(Section.lines)`). Create it in `apps/mobile/lib/bootstrap/app.dart`'s
  `_afterStartup` after `ContentLifecycle`, beside `HomeArrivalQueue`, and dispose it with it.
- [X] T073 [US6] In `apps/mobile/lib/features/lines/presentation/lines_screen.dart`, call
  `markSeen` after the first frame and on every news change while the screen is current. Make T069
  pass.

**Checkpoint**: All six stories work.

---

## Phase 9: The Owner's Boards

**Purpose**: The states the artboards don't draw, drawn by the owner
([contracts/design-briefs.md](./contracts/design-briefs.md)). Phases 3–8 build every state from the
brief, so only these checks wait for the export.

- [ ] T074 **Owner:** draw the six boards the first release needs, on the Claude Design canvas:
  `LinesFirst`, `LinesOwned`, `LineDetailsStory`, `LineDetailsDone`, `BuyVehicleShort`,
  `BuyVehicleOwned`. Export them with `docs/design/tools` into `docs/design/{screens,png,boxes}/`,
  or hand the export to Claude (`docs/owner-actions.md` section 014, item 1).
- [ ] T075 **Owner, optional:** draw `LineDetailsLocked` and `BuyVehicleNotForSale` (item 2). If they
  aren't drawn, T088 approves those states' goldens instead.
- [ ] T076 After T074's Lines boards land:
  - align `vehicle_strip.dart`, `line_map.dart` and `line_card.dart` to `LinesFirst` and
    `LinesOwned` (the two-tile strip, two-card placement, the road's ends, the locked tile);
  - add `test/design/samples/{lines_first,lines_owned}.dart` (`draftShaped()` states) with their
    layout tests and goldens;
  - move the boards' copy into `app_ar.arb`.
- [ ] T077 After T074's LineDetails boards land, align `trip_grid.dart` and `line_details_sheet.dart`
  to `LineDetailsStory` and `LineDetailsDone` (the story next cell, the playable cell, the locked
  cell, the done line's bottom). Add their samples, layout tests and goldens; also for
  `LineDetailsLocked` if drawn.
- [ ] T078 After T074's BuyVehicle boards land, align `vehicle_sheet.dart` to `BuyVehicleShort` and
  `BuyVehicleOwned` (the shortfall label, the bar, the disabled button, the impact line's fate, the
  owned sheet). Add their samples, layout tests and goldens; also for `BuyVehicleNotForSale` if
  drawn.
- [ ] T079 Write "As drawn (date)" notes in `specs/014-m09-lines-vehicles/contracts/design-briefs.md`
  for each board, as `fuel-lesson.md` has. Add the boards to M09's row of `docs/delivery-plan.md`
  "Design sources".

---

## Phase 10: Polish & Cross-Cutting Concerns

**Purpose**: The integration tests, the documents, the full checks, the reviews and the owner's list.

- [X] T080 Write `apps/mobile/integration_test/lines_loop_test.dart`, headless like M08's
  (`-d flutter-tester`), offline, for a scripted chapter-2 player with enough coins and the card
  setting on «always» (quickstart §4):
  1. «الخطوط» shows Home's line;
  2. the microbus tile → «اشتريها» spends once, and the microbus is current (SC-002);
  3. «كمّل» on خط الجامعة opens the card, and its close lands on the details;
  4. «العب المشوار ١» → «اطلع» → the trip by M02's scripted player → the result → Home →
     «الخطوط» shows the map.

  Also time SC-008 with a `Stopwatch`: tap to full content for Lines, the details and the sheet,
  each under 0.5 s on CI. M07's and M08's integration tests still pass.
- [X] T081 Add a `backend`-tagged case to `apps/mobile/test/backend/` (and its seed in
  `seed_backend.py` if needed): through Lines' path, buy the microbus offline, start the first
  trip on خط الجامعة, then sync. Both ops are accepted and none is `not_unlocked` (SC-003).
- [X] T082 [P] Update `docs/architecture-mobile.md`:
  - §5: the `features/lines/` tree;
  - §9: `/lines/:lineId/pre-trip/:tripId`, and the lines tab opening at its root;
  - §13: the phone-only rules (`tripPlayable`, `vehicleSale`) beside the port, stricter only.
- [X] T083 [P] Update the content docs:
  - `docs/architecture-backend.md` §9: the three fields;
  - `content/README.md`;
  - `specs/003-b04-content-pipeline/contracts/content-schemas.md`: the Line and Vehicle rows;
  - `specs/003-b04-content-pipeline/data-model.md`: the `content.Line` and `content.Vehicle`
    tables;
  - `docs/runbooks/content-publishing.md`: a schema change requires a fresh staging build after
    deploy.
- [ ] T084 [P] Update `docs/delivery-plan.md`: the Progress line for `014-m09-lines-vehicles` when
  it merges. T079 does the Design sources row.
- [X] T085 [P] Update `CLAUDE.md`:
  - "Project status": M09's line;
  - the guards line: `lib/features/lines/domain`'s list;
  - `pref.lines_seen`;
  - the synced vehicle art;
  - the content fields in the content notes;
  - the mobile commands table: `fvm flutter test integration_test/lines_loop_test.dart -d
    flutter-tester`.
- [X] T086 Complete section 014 of `docs/owner-actions.md`, each item with its task ID, and update
  "Open now":
  - **before merge:** T074 (and T075), T087–T089, T092;
  - **after merge:** T093–T095;
  - T010's change to the release draft.
- [ ] T087 **Owner approval** of the strings drafted in research R14, and of any copy the boards
  changed. Apply changes in `apps/mobile/lib/l10n/app_ar.arb` and regenerate the goldens they touch.
- [ ] T088 **Owner approval** of:
  - the departures (plan "Complexity Tracking");
  - the expected golden differences of the three artboards (research R12);
  - the goldens of the composed states:
    - a done card at all three stars;
    - a line under 20 trips;
    - the impact line hidden;
    - the plain affordable sheet;
    - Lines offline;
    - 360 pt and 1.3×;
    - T075's two states if not drawn.
- [ ] T089 **Owner approval** of the release draft's line texts and short names (T010), the product
  spec's wording unless rewritten.
- [X] T090 Run every CI check and fix anything found:
  - **`tools/content_kit`:** `uv run ruff check . && uv run ruff format --check . && uv run mypy .
    && uv run pytest --cov --cov-fail-under=80`, `codegen --check`, `golden`,
    `bundle dev --check --out ../../apps/mobile/assets/content/dev`.
  - **`packages/content_models`:** analyze, test, coverage.
  - **`backend`:** ruff, mypy, `pytest -n 4 --cov --cov-fail-under=80`,
    `makemigrations --check --dry-run`, and `spectacular` unchanged.
  - **`tools/solver`:** ruff, mypy, `pytest -n 4`, `wassal-solver parity`.
  - **`apps/mobile`,** in CLAUDE.md's order: pub get, build_runner, Rive setup, format, analyze,
    `flutter test --coverage --exclude-tags backend`, `check_coverage --min 80`, the three
    integration tests headless, `flutter test --tags rive`.
- [X] T091 Run the reviews, fix CRITICAL and HIGH findings, then rerun T090:
  - `flutter-reviewer` over the Dart diff: rebuild scope, `mounted` after awaits in the purchase and
    in `startNextTrip`, the watcher's disposal, the shell change;
  - `python-reviewer` over `backend/apps/content` and `tools/content_kit`;
  - `security-reviewer` over the purchase path (one intent, no client price, rollback) and the
    new preference (no game state or ids of value).
- [ ] T092 **Owner, before merge:** review the side-by-side images of the three artboards and every
  exported board (quickstart §3).
- [ ] T093 **Owner, after merge:** deploy, then rebuild and publish a fresh pack on staging. Packs
  without the new fields no longer read (research R9, `docs/runbooks/content-publishing.md`).
- [ ] T094 **Owner, after merge:** the device pass of quickstart §6 on the Redmi Note 7, or the Galaxy
  A06 when available, covering SC-008 and the dot across a restart. Claude asks before connecting to
  the phone.
- [ ] T095 **Owner, after merge:** the moderated playtest for SC-009. After opening Lines once, can
  four of five new players say what the next vehicle costs and which line it opens?

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: none.
- **Foundational (Phase 2)**: after Setup. Blocks every story. Within it:
  - T003 → T004 → T005;
  - T006 after T003; T007 after T004 and T006;
  - T008 after T003; T009 after T008 and T006;
  - T010 after T003;
  - T011–T014 are independent of the content tasks, with T013 before T014.
- **US1 (Phase 3)**: after Foundational.
- **US2 (Phase 4)**: after Foundational. T044 edits US1's `lines_screen.dart` (T027), and T046's
  sample opens over US1's Lines.
- **US3 (Phase 5)**: after Foundational. The sheet is reached by its route, so it doesn't wait for
  US1, but its sample opens over US1's Lines (T058 after T029).
- **US4 (Phase 6)**: after US1, US2 and US3 (it extends their screens).
- **US5 (Phase 7)**: after Foundational and US2's `trip_cells.dart` (T037) and `pre_trip_card.dart`
  change (T042). Its M08 switches T066–T067 can start after T014.
- **US6 (Phase 8)**: after US1 (T027) and US3 (T056, for the purchase-on-Lines case).
- **Owner's boards (Phase 9)**: T074 and T075 can start now. T076–T079 wait for the export and for
  US1–US4.
- **Polish (Phase 10)**: after the stories. T080 needs US1–US3; T087–T089 can start as soon as their
  strings and goldens exist.

### Within Each User Story

- Tests first, and failing, before implementation.
- Domain (pure), then application (providers), then presentation, then the router.
- Shared files (Organization) in task order.

### Parallel Opportunities

- **Setup:** T001 and T002.
- **Foundational:**
  - T005, T007 and T010 once their inputs exist;
  - T011 and T012 at any time;
  - T008 beside T005 and T006.
- **US1:** the tests T015–T018; then T019, T020, T021, T023, T024 and T025; then T030 and T031.
- **US2:** the tests T032–T036; then T037; then T046 and T047 at the end.
- **US3:** the tests T048–T051; then T052 and T055; then T058.
- **US1, US2 and US3** can run side by side after Foundational, in different files. Their shared
  files are `router.dart` (T029 → T041 → T057) and `app_ar.arb` (T028 → T045 → T057), done in
  order.
- **US5's** T064 and T065 beside US4.
- **Polish:** the documents T082–T085.

---

## Parallel Example: Foundational

```text
T005 content/examples/** + tools/content_kit/tests/test_rules.py
T008 backend/apps/content/models/** + migrations/0010_*.py
T011 apps/mobile/test/repo/domain_imports_test.dart
T012 apps/mobile/test/helpers/synthetic_packs.dart
T013 apps/mobile/test/core/progress/playable_test.dart
```

## Parallel Example: User Story 1

```text
T015 test/features/lines/domain/line_standing_test.dart
T016 test/features/lines/domain/vehicle_tiles_test.dart
T017 test/features/lines/domain/focus_line_test.dart
T018 test/features/lines/lines_screen_test.dart
```

## Parallel Example: User Story 3

```text
T048 test/features/lines/domain/vehicle_offer_test.dart
T049 test/features/lines/domain/impact_test.dart
T050 test/features/lines/application/vehicle_purchase_test.dart
T051 test/features/lines/vehicle_sheet_test.dart
```

---

## Implementation Strategy

### MVP First (User Stories 1–3)

1. Phase 1 and Phase 2: the content fields everywhere, and the proven rules.
2. Phase 3 (US1): Lines.
3. Phase 4 (US2): the details and starting from Lines.
4. Phase 5 (US3): buying the microbus.
5. **Stop and validate**: on a dev build, offline, play خط الحي from Lines, buy the microbus, and
   start خط الجامعة from «كمّل».

### Incremental Delivery

1. US1–US3: see, play, buy. The MVP.
2. US4: locked things explain themselves.
3. US5: story trips held back everywhere, M08's screens included. Required before the PR, since
   the release draft's shabka trip depends on it.
4. US6: the «new» dot.
5. The owner's boards as they land (Phase 9). Each board aligns its state and adds its checks.
6. Polish: the integration tests, the documents, the checks, the reviews and the owner's approvals.
