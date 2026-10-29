# Implementation Plan: Lines Map, Line Details and Vehicle Purchase (M09)

**Branch**: `014-m09-lines-vehicles` | **Date**: 2026-10-29, against master after M07, M22 and M08
merged | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/014-m09-lines-vehicles/spec.md`

## Summary

M09 replaces the three Lines placeholders with the design's screens and the rules behind them.

- **Phone-only rules** beside M08's port of the server's rules (R1, R2):
  - a story trip opens once its chapter's goal is met (Clarifications Q1);
  - vehicles are sold in pack order.

  Home's next trip, the pre-trip card and `startNextTrip` switch to the new `tripPlayable`, so no
  screen offers the shabka trip before the shabka is bought. A sweep proves the phone never allows
  what the server refuses.
- **Lines** (`Lines`, R3):
  - the balances (BONAT disabled offline);
  - the vehicle strip;
  - the line map bottom-up on a dashed road, opening on Home's line;
  - current, done and locked cards. A current card's «كمّل» starts its next trip (Clarifications Q3).
- **A line's details** (`LineDetails`, R4):
  - the trip grid with done, story, next, playable and locked cells;
  - the visible-range rule and its hint;
  - the play button, or none for a done line, or the reason for a locked one.
- **Starting from Lines** goes through M08's `startNextTrip` (fuel, checkpoint, card or trip). The
  card opens at a new `/lines/:lineId/pre-trip/:tripId`, so closing it returns to the line's
  details, and the lines tab always opens at its root (R5).
- **Buying a vehicle** (`BuyVehicle`, R6, R7):
  - the offer: seats, the line it opens, price against balance, the shortfall;
  - the impact line from M08's savings target after the purchase, reworded to
    «بعد الشرا، فاضل {amount} ج على {goal}» (Clarifications Q4);
  - the owned and not-for-sale sheets;
  - one held request id per intent through M05's `buy`. Offline, with M06's rollback.
- **The «new» dot** on «الخطوط», from news keys against a seen set kept in `pref.lines_seen` (R8).
- **Content** (R9): three required fields, the line's `whats_new` and `display_fare_piasters` and
  the vehicle's `short_name`, through the schemas, codegen, examples, sample, golden, dev bundle,
  B04's models and migration, importer, snapshot and admin, and the release draft.
- **The owner draws the undrawn states** (R12, the owner's instruction). Six boards are needed by
  the first release, two only by later packs, briefed in
  [contracts/design-briefs.md](./contracts/design-briefs.md) and listed in `docs/owner-actions.md`
  now. Claude builds every state from the brief meanwhile. Only the new boards' design checks wait
  for the export.

Technical decisions and their rationale: [research.md](./research.md).

## Technical Context

**Language/Version**:

- Dart 3.13 with the FVM-pinned Flutter 3.47.7 (`.fvmrc`);
- Python 3.13 with uv for `tools/content_kit` and `backend/`.

**Primary Dependencies**:

- **No new package.**
- **Mobile, existing:**
  - Riverpod 3 with its generator, `go_router`, `content_models`;
  - `rive` 0.14 (`Vehicle` artboard), `flutter_svg`;
  - `shared_preferences` behind `SettingsStore`.
- **Backend:** Django 5.2 (B04's content app), `wassal-content`.

**Storage**:

- **No database change on the phone** (the schema version stays).
- **One device preference:** `pref.lines_seen`.
- **One backend migration** (`content.0010`): five columns on `Line` and `Vehicle`.
- **Three content fields** (schema set stays 1.0).

**Testing**:

- `flutter_test` with fakes and in-memory SQLite, tests first for the pure parts:
  - `tripPlayable` and `vehicleSale` with the never-more-permissive sweep;
  - the lines domain: standings, cells and range, offer, impact, news;
  - `VehiclePurchase`.
- **Widget tests** for every state and transition.
- **Design checks** for `Lines`, `LineDetails` and `BuyVehicle` now, and for the owner's boards once
  exported.
- **a11y sizes** at 360×640, 360×800 and 390×844, scale 1.0 and 1.3.
- **A headless offline integration test** of the purchase and the loop from Lines.
- **A `backend`-tagged sync case** against the dev stack (SC-003).
- **Content:** content-kit pytest, the content_models round trip, backend pytest on real Postgres and
  Valkey.
- Coverage ≥ 80% everywhere (R16).

**Target Platform**:

- **Android:** `minSdk 24`, all three flavors.
- **iOS 15.0:** on Codemagic; no new plugin.
- **Linux:** CI and goldens.
- **Backend:** the ARM64 VMs (content app only).

**Project Type**: A mobile feature with a content-schema change in the `wassal` monorepo:

- new `apps/mobile/lib/features/lines/`, and `lib/core/progress/domain/playable.dart`;
- small changes to M08's `next_trip.dart`, `pre_trip_card.dart` and `start_next_trip.dart`, the
  router, `ShellScaffold` and `bootstrap/app.dart`;
- `content/schemas`, `tools/content_kit`, `packages/content_models`, `content/examples`;
- `backend/apps/content`.

**Performance Goals**:

- Lines, a line's details and the vehicle sheet show full content within 0.5 s of the tap on the
  reference device, with no loading state (SC-008).
- Derivations are O(lines × trips), once per new view (R17).

**Constraints**:

- Offline-first: everything works with no network. Only the BONAT pill's link to the shop needs it.
- Integer money (fares in piasters, prices and balances in JENEHAT), formatted only at the edge.
- Every string in `app_ar.arb`, every name from the pack, every price from the catalog.
- Every style value from the tokens; shared components only.
- The phone never more permissive than the server; no change to the server's rules, M05's operations
  or M06's sync.
- No ad call.

**Scale/Scope**:

- 3 artboards now and 6–8 owner boards.
- 1 new feature folder and 1 new progress file.
- About 30 new `lib/` files and 30 test files; about 45 strings.
- 1 new route, 1 preference, 3 content fields, 1 backend migration.
- 0 tables, 0 operations, 0 tunables.
- About 8 docs updated, plus `CLAUDE.md` by hand.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**Before Phase 0:** PASS. Nothing in the spec asks for an exception, and principles I, II, III, IV
and VI need none.

**After Phase 1 design:** PASS, as below.

| Principle | How M09 satisfies it |
| --- | --- |
| I. Engine purity | No trip rule is touched. The new rules are progression rules (which trip may start), not trip rules, in a pure domain that imports only content models, the content source and the economy's wire. The new `features/lines/domain/` folder gets its own entry in the imports guard (R18). |
| II. Integer money | `display_fare_piasters` is an integer (≥ 50, × 50) in the schema, Pydantic, Dart and a Postgres `PositiveIntegerField` with a check. Prices, balances, shortfall and impact are integer JENEHAT; formatting is at the edge (`NumberFormatter.piasters`, `.integer`). The integer-money guard covers the new folder. |
| III. Parity | No engine, scoring, parameter or PRNG change. The new fields are read by no engine, and `solver_fingerprint` is unchanged. Parity fixtures are untouched. |
| IV. Server authority | The vehicle purchase is a JENEHAT spend through `EconomyService.buy`, optimistic and rolled back by M06 on refusal; the price is the catalog's, read when it applies. The phone's rules are only ever stricter than the server's (R1's sweep), so the server still decides. No BONAT ↔ JENEHAT path. |
| V. Offline-first | Lines, details, starts and the purchase work offline; the BONAT pill's shop link is the only network item, disabled with M08's label. |
| VI. Idempotency | One `TxnId` per purchase intent, kept across a write failure, cleared on success. A double tap or a retry spends once (SC-004). No time logic. |
| VII. Content, not code | Names, what's new, fares and short names come from the pack (three new schema fields through the whole pipeline, generated models only); prices from the catalog; UI strings in ARB. The impact line is reworded so no Arabic grammar lives in code (Clarifications Q4). |
| VIII. Tunables | No balancing number. Layout values are design tokens. The grid's range rule and the dot's keys are UI rules, not balancing. |
| IX. No ads in a trip | No ad SDK or call. Starts from Lines pass M08's checkpoint, which runs before the card, never in a trip. |
| X. RTL and Arabic first | Every screen RTL; the strip and the grid from the right; goldens in both digit styles for three artboards and every owner board. |
| XI. Accessible minimums | 44×44 targets («كمّل» 63×44, cells 65×62), 12 pt text, at 360 and 390 wide and 1.3×. Labels per R13; the locked look without opacity (§9.1 #6); text wraps instead of clipping. |
| XII. No runtime LLM | None. |
| XIII. Small, testable | One spec folder; tests first for the rules and the purchase; unit, widget, golden, layout, a11y, integration and the `backend`-tagged sync; coverage ≥ 80% on mobile, content_kit and backend. |
| Platform constraints | Riverpod with its generator, `go_router`, drift untouched. No plugin. The backend change is in `apps/content` only: thin admin, logic in services, an expand-only migration with defaults. |

## Project Structure

### Documentation (this feature)

```text
specs/014-m09-lines-vehicles/
├── spec.md
├── plan.md              # This file
├── research.md          # R1–R19
├── data-model.md        # content fields, the preference, derived values, state diagrams
├── quickstart.md        # validation guide
├── contracts/
│   ├── progress-rules.md   # tripPlayable, vehicleSale, currentVehicle; M08's callers switched
│   ├── content-fields.md   # whats_new, display_fare_piasters, short_name through the pipeline
│   ├── lines.md            # the Lines tab, the model, the «new» dot
│   ├── line-details.md     # the grid, the range, starting a trip, the card's route
│   ├── buy-vehicle.md      # the offer, the impact, the purchase and its outcomes
│   └── design-briefs.md    # the boards the owner draws
├── checklists/requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
apps/mobile/
├── lib/
│   ├── bootstrap/app.dart                          # + LinesDotWatcher beside HomeArrivalQueue
│   ├── core/
│   │   ├── progress/domain/playable.dart           # NEW: tripPlayable, vehicleSale, currentVehicle
│   │   ├── preferences/shared_prefs_settings_store.dart   # + 'pref.lines_seen'
│   │   └── routing/
│   │       ├── routes.dart                         # + linePreTrip (/lines/:lineId/pre-trip/:tripId)
│   │       ├── router.dart                         # the three screens; the new card route
│   │       └── shell_scaffold.dart                 # the lines tab opens at its root
│   ├── features/
│   │   ├── lines/{domain,application,presentation}/   # NEW (contracts/lines.md, line-details.md, buy-vehicle.md)
│   │   ├── home/
│   │   │   ├── domain/next_trip.dart               # startable → tripPlayable
│   │   │   └── application/start_next_trip.dart    # StartFrom.lines; playable guard; card location by `from`
│   │   └── pre_trip/presentation/pre_trip_card.dart   # tripPlayable; leaveTo
│   └── l10n/app_ar.arb                             # ~45 keys (R14)
├── assets/illustrations/vehicles/                  # + microbus_new.svg, microbus_travel.svg (synced)
├── tool/design/sync_assets.dart                    # + the two vehicles
├── test/
│   ├── core/progress/playable_test.dart            # NEW; sample_sweep_test updated
│   ├── features/lines/                             # unit + widget
│   ├── features/home/, features/pre_trip/          # next trip, startNextTrip, card return
│   ├── core/routing/                               # the new route, the lines tab root, all-destination goldens
│   ├── a11y/{lines,line_details,buy_vehicle}_minimum_sizes_test.dart
│   ├── design/samples/{lines,line_details,buy_vehicle}.dart   # + one per owner board on export
│   ├── design/*_layout_test.dart, goldens/design/*_goldens_test.dart
│   ├── helpers/synthetic_packs.dart                # + draftShaped, + the artboards' 4×5 pack
│   ├── helpers/memory_settings_store.dart          # + 'pref.lines_seen'
│   ├── repo/domain_imports_test.dart               # + lib/features/lines/domain
│   ├── core/economy/domain/wire_test.dart          # short_name
│   ├── fixtures/tutorial/lines/line_hay.json       # the new fields
│   └── backend/                                    # + the Lines purchase and start case
└── integration_test/lines_loop_test.dart           # NEW, headless
content/schemas/{line,vehicle}.schema.json          # the three fields
content/examples/{valid,invalid,sample}/…, sample.golden.json
apps/mobile/assets/content/dev/{core-1.json.gz,bundled.json}
tools/content_kit/src/wassal_content/{schemas/*.json,models/_generated.py}, tests/
packages/content_models/lib/src/generated/{line,vehicle}.dart
backend/apps/content/{models/{base,lines,trips}.py, migrations/0010_*.py,
                      services/{importer,snapshot}.py, admin/authoring.py, tests/}
docs/architecture-mobile.md                         # §9 (the card route, the lines tab), §13 (phone-only rules)
docs/architecture-backend.md                        # §9 (the fields)
docs/delivery-plan.md                               # Design sources (the boards), Progress
docs/runbooks/content-publishing.md                 # rebuild after a schema change
docs/owner-actions.md                               # section 014 (the boards now; the rest at implement)
content/README.md; specs/003-b04-content-pipeline/{contracts/content-schemas.md,data-model.md}
```

**Structure Decision**: The mobile feature-first layout of mobile §5, with `domain/` (pure),
`application/` (Riverpod) and `presentation/` in `features/lines/`, the folder mobile §5 already
names for "lines map, line detail, vehicle purchase".

- **The rules** go in `core/progress/domain/`, beside M08's port, because Home, the card, the
  result, Lines and M10 share them.
- **The lines domain** imports M08's `savingsTarget` and the next-trip function rather than moving
  them (R7).
- **The tile, card and cell widgets** stay in the feature until another feature needs them (R11).
- **The content change** follows M01's and M07's precedent end to end.

## Complexity Tracking

No constitution deviation: the table is empty.

Some decisions depart from the design or the ux-spec rather than the constitution. They are listed
for the PR and the owner's review (README override 3):

- **«كمّل» is its own button** that starts the next trip, against HANDOFF's action table
  (Clarifications Q3).
- **The impact line is reworded**, «فاضل {amount} ج على {goal}» (Clarifications Q4).
- **The locked look on the tiles and cells** follows HANDOFF §9.1 #6, not the drawn dashed tiles and
  cells (until the owner's boards draw it).
- **Long text wraps** (§9.1 #10), not HANDOFF's one-line ellipsis.
- **The plain preview with no «بزينتك»**, against the drawn cosmetics.
- **A locked line behind another line opens its locked details**, against the ux-spec's «يفتح
  نافذة العربية المطلوبة», which only fits a vehicle rule.
- **The lines tab always opens at its root** (R5).

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |

## What changes in M08's merged code

| Area | Change in this feature |
| --- | --- |
| Next trip | `next_trip.dart`'s `startable` reads `tripPlayable`. Home and the result's «مشوار تاني» stop offering a story trip before its chapter's goal is met. `next_trip_test.dart` and `sample_sweep_test.dart` gain those cases. |
| Pre-trip card | Its opening check reads `tripPlayable`. It gains `leaveTo` for an unopenable trip. The same widget is built by the new `/lines/:lineId/pre-trip/:tripId`, where its close lands on the line's details. `pre_trip_card_test.dart` gains the Lines cases; the Home cases are unchanged. |
| `startNextTrip` | `StartFrom.lines`; a first step that refuses a trip that isn't `tripPlayable`; the card's location from `from` (Home and the result unchanged). |
| Shell | The lines tab always opens at `/lines`. Other tabs keep M03's behaviour. |
| Untouched | `unlocks.dart` (the port), `savingsTarget`, Home's line card (still `/lines`), the arrival queue, the result. |

M07 and M22 get no change: M07's tutorial trips reach Lines' start path through `startNextTrip`'s
existing first-session step, and M22's scenes are M10's to open.

## Owner design tasks (now)

The owner asked to draw every state the design doesn't. They are in `docs/owner-actions.md`
(section 014, "Before the new boards' design checks"), briefed in
[contracts/design-briefs.md](./contracts/design-briefs.md):

- **Needed by the first release:** `LinesFirst`, `LinesOwned`, `LineDetailsStory`, `LineDetailsDone`,
  `BuyVehicleShort`, `BuyVehicleOwned`.
- **Only with later packs** (optional; approved from goldens if never drawn): `LineDetailsLocked`,
  `BuyVehicleNotForSale`.

Each board decides its open questions (the brief lists them) and may change the copy drafts.
Nothing else waits on them: Claude builds every state from the brief, and only each board's sample,
golden and layout test is added after its export.

## Owner approvals and actions

**Approvals** (before merge):

1. The strings drafted in research R14, and any copy the boards change.
2. The departures listed under Complexity Tracking.
3. The expected golden differences of the three drawn artboards (R12), and the goldens of the
   composed states: a done card at all three stars, a short line, the impact hidden, the plain
   affordable sheet, Lines offline, 360 pt and 1.3×.
4. The two content texts for the release draft's lines, and the short names (R9).

**Actions:**

- **Before merge:**
  1. Draw the six boards (above).
  2. Review the side-by-side images (quickstart §3).
- **After merge:**
  1. Deploy, then rebuild and publish a fresh pack on staging, since packs without the new fields no
     longer read (R9, `docs/runbooks/content-publishing.md`).
  2. The device pass of quickstart §6 on the Redmi Note 7, or the Galaxy A06 when available. It
     covers SC-008.
  3. The moderated playtest for SC-009: after opening Lines once, can four of five new players say
     what the next vehicle costs and which line it opens?

`/speckit-implement` completes section 014 of `docs/owner-actions.md` with these, each with its task
ID.

## Agent context

The template's agent-context script was not run. `CLAUDE.md` is maintained by hand at implement time
(R18):

- M09 in the project status;
- `pref.lines_seen`;
- the lines domain in the guards line;
- the synced vehicle art;
- the content fields in the content notes.
