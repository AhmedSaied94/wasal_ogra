# Implementation Plan: Apartment, Story Chapters, Scenes and Family Requests (M10)

**Branch**: `015-m10-apartment-story` | **Date**: 2026-10-29, against master after M09 (014) merged |
**Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/015-m10-apartment-story/spec.md`

## Summary

M10 replaces the apartment and story placeholders with the design's screens and the rules behind
them.

- **The tab's two views** (R1, R8, R9; Clarifications Q1):
  - **Goal view** for chapters 1–3: the goal art, the amount or the trips, the bar, the character's
    line and the teaser. When ready, «اشتري الشبكة» buys the shabka; chapter 2's CTA opens M09's
    vehicle sheet.
  - **Rooms view** from chapter 4: the room drawn with each owned piece in its content-given slot,
    the room tabs, the piece grid, the requests button, the chapter bar and the next-scene strip.
- **The piece sheet** (R10, Q4): styles with سلمى's line, a mark on the style a request names, and a
  warning line before a request would be missed. «اشتري», or «ناقصك» with «اطلع مشوار».
- **Purchases** (R7): `PiecePurchase` and `GoalPurchase` on M09's held-id pattern, rules first.
  - After a piece: the drop-in, سلمى's comment, and `RoomDone` when the room just finished.
  - After the shabka: its story trip's card, at the new `/apartment/pre-trip/:tripId`.
- **Rewards on their way** (R6): the phone never adds BONAT (constitution IV). A room's, chapter's or
  request's reward shows «في الطريق» until the confirmed base has it. `EconomyView` gains
  `confirmed`, and a pure `pendingRewards` compares the two.
- **Scenes** (R2–R4, Q5):
  - a third moment, "the chapter's goal met", for scenes without `plays`;
  - seen recorded through a new `story_progress` operation;
  - goal scenes made due by a watcher that tells a local completion from a restored one.
  - First-session scenes keep M07's look; every later scene and every replay plays in the new
    `SceneViewer`, with share.
- **The timeline and the album** (R13, Q3): seven chapter rows, done, current or locked; one album
  card per scene, with the count of unlocked out of the pack's scenes.
- **Family requests** (R11): open, done, missed and claimed states that follow the server's rule
  exactly. «خد» records a new `claim_request` operation, and the server grants the BONAT.
- **Story trips' riders** (R15, Q2): from the chapter's new `story_trip_info`:
  - a story character drawn in a seat the trip leaves empty;
  - the story title on the HUD, the condition on the strip, a story failure reason;
  - comments on a mistake, picked deterministically from the trip seed.
  - Over-change stays silent (constitution XI), and the engine is untouched.
- **The end of the available story** (R14): a `StoryEndTarget` keeps Home's card, and the rooms view
  and timeline say more is coming.
- **Content** (R16): thirteen fields (three required: a scene's `title`, an item's `slot`, a request's
  `character`) and nine reference rules, through the schemas, codegen, examples, sample, golden, dev
  bundle, B04's models, migration `0011`, importer, snapshot and admin, and the release draft.
- **The owner draws the undrawn states** (R18). Ten boards, briefed in
  [contracts/design-briefs.md](./contracts/design-briefs.md), are listed in `docs/owner-actions.md`
  now. Claude builds every state from its brief meanwhile, and only the new boards' design checks
  wait for the export.

Technical decisions and their rationale: [research.md](./research.md).

## Technical Context

**Language/Version**:

- Dart 3.13 with the FVM-pinned Flutter 3.47.7 (`.fvmrc`);
- Python 3.13 with uv for `tools/content_kit` and `backend/`.

**Primary Dependencies**:

- **No new package.**
- **Mobile, existing:**
  - Riverpod 3 with its generator, `go_router`, drift;
  - `content_models`, `trip_engine` (one new export: `Xorshift32`);
  - `rive` 0.14 (`Person`, the panels), `flutter_svg`, Flame (the rider component);
  - `share_plus` behind M08's `ShareGateway`.
- **Backend:** Django 5.2 (B04's content app), `wassal-content`. B03's sync and story operations are
  used as they are.

**Storage**:

- **Drift schema 5** (from 4):
  - `ledger_ops`' type check admits `story_progress` and `claim_request` (table rebuilt, rows kept);
  - `player_state` gains `scenes_seen` and `requests_claimed`.
- **M07's `first_session` lists:** used as they are, with new callers.
- **No preference**, and in-memory only: the remembered style, the selected tab, the bar's last value.
- **One backend migration** (`content.0011_m10_story_fields`): columns on six models and a
  `StoryRider` table, expand-only.
- **Thirteen content fields** (schema set stays 1.0).

**Testing**:

- **Tests first** (constitution XIII):
  - the two operations' rules, the state mapping, the wire and the v5 migration;
  - then the story, request and reward rules.
- **Unit tests:** the apartment and story domains, the purchases and the claim, `StoryService`,
  `StoryDueWatcher`, the rider comments.
- **Widget tests** for every state and transition.
- **Design checks** for the nine artboards now, and the owner's ten boards once exported.
- **a11y sizes** at 360×640, 360×800 and 390×844, scale 1.0 and 1.3.
- **Two headless offline integration tests:** the apartment loop and the story trip.
- **A `backend`-tagged sync case** against the dev stack (SC-003, SC-004, SC-006).
- **Content:** content-kit pytest, the content_models round trip, backend pytest on real Postgres and
  Valkey; the engine's tests and the parity run unchanged.
- **Coverage** ≥ 80% on mobile, content_kit and backend (R21).

**Target Platform**:

- **Android:** `minSdk 24`, all three flavors.
- **iOS 15.0:** on Codemagic; no new plugin.
- **Linux:** CI and goldens.
- **Backend:** the ARM64 VMs (content app only).

**Project Type**: A mobile feature with an economy-operation and content-schema change in the
`wassal` monorepo:

- new `apps/mobile/lib/features/apartment/` and `lib/features/story/`;
- new `lib/core/progress/domain/{story,requests,rewards}.dart`;
- small changes to M05/M06's economy and sync, M07's arrival and scene page, M08's savings target,
  card, `startNextTrip` and share render, M02's trip screen, the router, and `bootstrap/app.dart`;
- `content/schemas`, `tools/content_kit`, `packages/content_models`, `content/examples`;
- `packages/trip_engine` (one export line);
- `backend/apps/content`.

**Performance Goals**:

- The tab, a piece's sheet and the timeline show their full content within 0.5 s of the tap, and a
  scene's first panel within 1 s, on the reference device with no network (SC-009).
- Derivations are O(chapters × scenes + items + requests), once per new view.
- The room scene is one `FittedBox` of SVGs, with no per-frame work.

**Constraints**:

- Offline-first: everything works with no network. Claims and scene records queue; their rewards
  wait for the server.
- **Integer money:** prices and balances in JENEHAT, rewards in BONAT, formatted only at the edge.
- **Server authority:** the phone never adds BONAT, and its rules are never more permissive than the
  server's.
- **Text:** every string in `app_ar.arb`; every name, line and title from the pack.
- **Style:** every value from the tokens; shared components only.
- **No ad call.** No engine, solver, parity or tunable change.

**Scale/Scope**:

- **Design:** 9 artboards now and 10 owner boards.
- **Code:** 2 new feature folders and 3 new progress files; about 60 new `lib/` files and 55 test
  files; about 75 strings.
- **Routes and data:** 3 new routes, 2 economy operations, 2 storage columns, 13 content fields,
  9 content rules, 1 backend migration with 1 table.
- **None:** 0 tunables, 0 preferences.
- **Docs:** about 10 updated, plus the `CLAUDE.md` guides by hand.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**Before Phase 0:** PASS. Nothing in the spec asks for an exception. The spec's FR-048 had riders
commenting on over-change, which would break XI. It was corrected during planning, before any design
depended on it.

**After Phase 1 design:** PASS, as below.

| Principle | How M10 satisfies it |
| --- | --- |
| I. Engine purity | No trip rule, event or definition field changes. Riders live on the chapter (`story_trip_info`), in seats no passenger names (V-C7), so the engine never sees them. Rider comments read `ReputationChanged` events after the fact, in a pure trip-domain file, and use a fresh `Xorshift32`, never the engine's PRNG state. The one engine change is an export line. The new domain folders get their entries in the imports guard (R20). |
| II. Integer money | Prices, balances, shortfalls and rewards are integers (JENEHAT, BONAT). The slot's geometry is integers too. Formatting is at the edge. The integer-money guard covers the new folders. |
| III. Parity | No engine, scoring, parameter or PRNG change. The trip definitions, the parity fixtures and `solver_fingerprint` are unchanged, and `wassal-solver parity` passes as on master. |
| IV. Server authority | Piece and goal purchases are JENEHAT spends through `EconomyService.buy`, rolled back by M06 on refusal. Room, chapter and request BONAT is never added on the phone. It shows as on its way until the confirmed base carries the server's grant (R6). `claim_request`'s local rule is the server's, so the phone never offers a claim the server refuses. No BONAT → JENEHAT path. |
| V. Offline-first | The tab, purchases, scenes, the timeline, the album and share work offline. `story_progress` and `claim_request` queue in `ledger_ops` and sync later; only the rewards wait. |
| VI. Idempotency | One `TxnId` per intent (a piece, a goal, a claim, a scene), held across write failures and cleared on success. A repeat scene or claim is refused locally without storing a row, and the server treats a repeat as a no-op (B03). A double tap spends or claims once (SC-002). |
| VII. Content, not code | Scene titles, character lines, room lines, style comments, rider info, slots and askers come from the pack through thirteen schema fields and generated models. UI strings are in ARB. Templates are worded so no Arabic grammar lives in code (R11). Locked teaser names for chapters and rooms not yet in the pack are ARB interface text, replaced by the pack's title once present (R13). |
| VIII. Tunables | No balancing number. Rider comment spacing reuses `trip_bubble_min_ms_<line>`. Layout and motion values are design tokens. |
| IX. No ads in a trip | No ad SDK or call. Riders and comments add none; starts from the apartment pass M08's checkpoint before the card. |
| X. RTL and Arabic first | Every screen RTL; the viewer slides in the reading direction and its dots start on the right; goldens in both digit styles for the nine artboards and every owner board. |
| XI. Accessible minimums | 44×44 targets (tabs extended to the 44 row, chips 44 high), 12 pt text, at 360 and 390 wide and 1.3×. At most two bubbles in a trip, the rider's slot counted as بلية's is. Over-change stays silent: no rider comments on it. Reduced motion drops the drop-in, the pops and the panel slide. Announcements per contract. |
| XII. No runtime LLM | None. Rider lines are written content, picked deterministically from the trip seed. |
| XIII. Small, testable | One spec folder; tests first for the economy's validators, the state mapping and the wire; unit, widget, golden, layout, a11y, two integration tests and the `backend`-tagged sync; coverage ≥ 80% on mobile, content_kit and backend. |
| Platform constraints | Riverpod with its generator, `go_router`, drift (a generated `make-migrations` step). No plugin. The backend change is in `apps/content` only: thin admin, logic in services, an expand-only migration with defaults. B03 is used unchanged. |

## Project Structure

### Documentation (this feature)

```text
specs/015-m10-apartment-story/
├── spec.md
├── plan.md              # This file
├── research.md          # R1–R23
├── data-model.md        # content fields, the economy's state, schema 5, derived values, state diagrams
├── quickstart.md        # validation guide
├── contracts/
│   ├── content-fields.md   # the thirteen fields, nine rules, B04 and the sample
│   ├── economy-ops.md      # story_progress, claim_request, the confirmed view, schema 5, pending rewards
│   ├── story-flow.md       # scene moments and states, StoryService, StoryDueWatcher, where scenes play
│   ├── apartment.md        # the tab, the piece sheet, purchases, RoomDone, requests, the story's end
│   ├── scene-viewer.md     # the viewer, share, the timeline, the album
│   ├── story-trip.md       # riders, title, condition, failure reason, comments
│   └── design-briefs.md    # the boards the owner draws
├── checklists/requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
apps/mobile/
├── lib/
│   ├── bootstrap/app.dart                          # + StoryDueWatcher; StoryService.backfill once ready
│   ├── core/
│   │   ├── economy/
│   │   │   ├── domain/{op,economy_state,story_rules}.dart   # 2 ops; scenesSeen, requestsClaimed; NEW story_rules
│   │   │   ├── economy.dart                        # recordScene, claimRequest; EconomyView.confirmed
│   │   │   └── drift_economy_store.dart            # the two columns; takeServerState
│   │   ├── storage/app_database.dart               # schemaVersion 5, _toV5
│   │   ├── sync/domain/{op_wire,state_snapshot}.dart       # contentVersionTypes; StateStory mapping
│   │   ├── progress/domain/{story,requests,rewards}.dart   # NEW, pure
│   │   ├── art/{apartment_art,panel_art}.dart      # NEW apartment art; + ch4_mother_looks panel
│   │   ├── platform/offscreen_render.dart          # renderOffscreenPng (moved from result)
│   │   └── routing/{routes,router}.dart            # + storyScene, storyAlbum, apartmentPreTrip; the screens
│   ├── features/
│   │   ├── apartment/{domain,application,presentation}/   # NEW (contracts/apartment.md; chapters_page)
│   │   ├── story/{domain,application,presentation}/       # NEW (contracts/story-flow.md, scene-viewer.md)
│   │   ├── home/
│   │   │   ├── domain/savings_target.dart          # StoryEndTarget; nextPiece exported
│   │   │   ├── application/start_next_trip.dart    # StartFrom.apartment
│   │   │   └── presentation/savings_card.dart      # tap to a waiting scene; StoryEndTarget
│   │   ├── onboarding/presentation/{arrival_items,scene_page}.dart   # location by inFirstSession; recordSeen
│   │   ├── result/presentation/share_action.dart   # uses renderOffscreenPng
│   │   └── trip/
│   │       ├── domain/{trip_facts,trip_view,fail_summary,presentation_memory,rider_comments}.dart
│   │       └── presentation/{top_bar/top_bar,overlays/*,scene/rider_component,cards/failure_card}.dart
│   └── l10n/app_ar.arb                             # ~75 keys (R19)
├── assets/illustrations/apartment/{rooms,pieces,goals}/   # synced (R17)
├── assets/illustrations/panels/ch4_mother_looks.svg       # synced
├── tool/design/sync_assets.dart                    # + the apartment art
├── drift_schemas/app/drift_schema_v5.json          # generated
├── test/
│   ├── core/economy/, core/sync/, core/progress/, drift/app/   # tests first
│   ├── features/{apartment,story}/                 # unit + widget
│   ├── features/{home,onboarding,result,trip}/     # the changed seams
│   ├── core/routing/                               # the new routes, redirects, all-destination goldens
│   ├── a11y/*_minimum_sizes_test.dart              # the new screens
│   ├── design/samples/*.dart, design/*_layout_test.dart, goldens/design/*_goldens_test.dart
│   ├── helpers/synthetic_packs.dart                # + the artboards' salon pack
│   ├── repo/domain_imports_test.dart               # + the new domain folders
│   └── backend/story_sync_test.dart                # tag backend
└── integration_test/{apartment_loop_test,story_trip_test}.dart   # NEW, headless
packages/trip_engine/lib/trip_engine.dart           # export Xorshift32
content/schemas/{common,chapter,room,item,family_request}.schema.json
content/examples/{valid,invalid,sample}/…, sample.golden.json
apps/mobile/assets/content/dev/{core-1.json.gz,bundled.json}
tools/content_kit/src/wassal_content/{schemas/*.json,models/_generated.py,rules/references.py}, tests/
packages/content_models/lib/src/generated/{common,chapter,room,item,family_request}.dart
backend/apps/content/{models/story.py, migrations/0011_m10_story_fields.py,
                      services/{importer,snapshot}.py, admin/authoring.py, tests/}
docs/architecture-mobile.md, docs/architecture-backend.md, docs/delivery-plan.md,
docs/runbooks/content-publishing.md, docs/owner-actions.md, content/README.md,
specs/003-b04-content-pipeline/contracts/content-schemas.md
```

**Structure Decision**: The mobile feature-first layout of mobile §5:

- `features/apartment/` for the tab, the piece sheet, `RoomDone`, the requests and the timeline (the
  folder HANDOFF names for `Chapters`);
- `features/story/` for the viewer, the album and the story's services.

Each has `domain/` (pure), `application/` (Riverpod) and `presentation/`.

- **The scene, request and reward rules** go in `core/progress/domain/`, beside M08's port and M09's
  playable rules, because Home, the result, the apartment and the story share them.
- **The two operations** extend M05's economy and M06's wire, as M07's operations did, so there is
  one log, one sync and one rollback.
- **The trip changes** stay in `features/trip/`, all presentation, and the engine stays untouched.
- **The content change** follows M07's and M09's precedent end to end.

## Complexity Tracking

No constitution deviation: the table is empty.

Some decisions depart from the design or the ux-spec rather than the constitution. They are listed
for the PR and the owner's review (README override 3):

- **Rewards show «في الطريق»** until the server confirms them, against HANDOFF `RoomDone`'s "granted
  when the dialog opens" and its `bonat_burst` (constitution IV, R6).
- **After the shabka, its story trip's card opens**, not the scene (HANDOFF `AptGoalReady`). The
  scene follows the trip (owner, 2026-10-27; R7).
- **First-session scenes keep M07's look** (Clarifications Q5); the viewer serves every other scene
  and every replay.
- **The album has one card per scene**, opening that scene, not one per chapter (Clarifications Q3).
- **Riders in story trips** (Clarifications Q2), which no artboard draws, with comments from content.
- **The request mark and the warning line** on the piece sheet (Clarifications Q4), undrawn.
- **The requests list follows the server's rule:**
  - the counted row («٣ مشاوير بتلات نجوم») isn't built;
  - claims queue offline instead of «محتاج نت»;
  - the badge counts open + done, in `primary`/white (§9.1 #8).
- **The condition is a template** «{item} بشكل «{variant}»», not HANDOFF's «اختار شكل «كريستال»
  للنجفة», so no preposition joins a name in code (R11).
- **The chapter bar's trailing «شوف المشهد»** while a room's scene waits, with the rest still opening
  the timeline (R9).
- **سلمى's bubble after a purchase** stays until the next tap or scroll, with no timer (R9).
- **Chapters and rooms not in the pack** take ARB names in the timeline and the tabs (R13).
- **Long text wraps** (§9.1 #10), not HANDOFF's one-line ellipsis.

| Violation | Why Needed | Simpler Alternative Rejected Because |
| --- | --- | --- |
| — | — | — |

## What changes in merged code

| Feature | Change |
| --- | --- |
| M05 economy | `OpType` gains `story_progress` and `claim_request`, with requests, rules (`story_rules.dart`), two calls and two state fields. `EconomyView.confirmed`. Schema 5 (`ledger_ops` check rebuilt, two `player_state` columns). The store stays the only writer. |
| M06 sync | `contentVersionTypes` gains both. `StateSnapshot.story` is typed and mapped into `scenesSeen` and `requestsClaimed`. Rollback, batching and the state replacement are unchanged. |
| M07 onboarding | `DueSceneArrival` and the `/trip` redirect choose M07's scene page inside the first session and the viewer after it. `ScenePage._finished` calls `StoryService.recordSeen`. The first-session test and M07's goldens are unchanged. |
| M08 Home, card, result | `savingsTarget` gains `StoryEndTarget`, and `_nextPiece` is exported as `nextPiece`. `HomeSavingsCard` taps to a waiting scene and draws the end. `startNextTrip` gains `StartFrom.apartment` (the card at `/apartment/pre-trip/:tripId`). `renderSharePicture` moves to `core/platform` as `renderOffscreenPng`, with output unchanged. `storySceneWaitingProvider` and `storyAfterResultProvider` are overridden by M10, not edited. |
| M09 lines | None. The goal view links to its `/lines/vehicle/:vehicleId` sheet, and `tripPlayable` already gates the story trips. |
| M02 trip screen | `TripFacts.storyInfo`; `TripView.storyStrip`, with the five layout checks moved to it; `TripTitle`, `StoryStrip` and `failSummary` read the content when present; `RiderComponent`; `PresentationMemory`'s بلية slot generalised to a character slot with rider comments. Untouched otherwise, for a trip with no `story_trip_info`. |
| M22 scenes | `PanelArt` gains the `ch4_mother_looks` drawing. Its Rive panels and turns are reused by the viewer. |
| M01 engine | `export 'src/prng.dart' show Xorshift32;`, with no rule, fixture or parity change. |
| B04 content | Columns, `StoryRider`, migration `0011`, importer, snapshot and admin (contracts/content-fields.md). |
| B03 ledger and sync | None: `story_progress` and `claim_request` exist and are used as they are. |

## Owner design tasks (now)

The owner draws every state the design doesn't (the owner's standing instruction, as for M09). The
boards are in `docs/owner-actions.md` (section 015, "Before the new boards' design checks"), briefed
in [contracts/design-briefs.md](./contracts/design-briefs.md):

- `AptGoalLine`
- `AptGoalVehicle`
- `AptRoomsAffordable`
- `AptRoomsBought`
- `AptRoomsDone`
- `PieceAffordable`
- `RoomDonePending`
- `ChaptersGoal`
- `RequestsEmpty`
- `HomeStoryEnd`

Each board decides its open questions (the brief lists them) and may change the copy drafts. Nothing
else waits on them: Claude builds every state from its brief, and only each board's sample, golden
and layout test is added after its export.

## Owner approvals and actions

**Approvals** (before merge):

1. The strings drafted in research R19, and any copy the boards change.
2. The departures listed under Complexity Tracking.
3. The expected golden differences of the nine drawn artboards (R18), and the goldens of the composed
   states: offline, 360 pt and 1.3×.
4. The release draft's new texts (R23): scene titles, character, ready and room lines, style comments,
   taglines, the riders' `story_trip_info`, comment pools and failure reasons, and the requests'
   askers.

**Actions:**

- **Before merge:**
  1. Draw the ten boards (above).
  2. Review the side-by-side images (quickstart §4).
- **After merge:**
  1. Deploy, then rebuild and publish a fresh pack on staging, since packs without the required fields
     no longer read (R16, `docs/runbooks/content-publishing.md`).
  2. The device pass of quickstart §7 on the Redmi Note 7, or the Galaxy A06 when available. It covers
     SC-009.
  3. The moderated playtest for SC-010.
  4. The art list of R17: the empty salon, the twelve style drawings, chapters 1–4's undrawn panels and
     the goal drawings. These are not blocking, since the fallbacks ship.

`/speckit-implement` completes section 015 of `docs/owner-actions.md` with these, each with its task
ID.

## Agent context

The template's agent-context script was not run. The `CLAUDE.md` guides are maintained by hand at
implement time (R22):

- **`apps/mobile/CLAUDE.md`:** M10 in the area's features, the two operations and schema 5, the new
  domain folders in the guards line, the synced apartment art, the routes.
- **`tools/content_kit/CLAUDE.md`:** the fields and the rules V-C6–V-C12, V-R3, V-R4.
- **`backend/CLAUDE.md`:** migration `0011` and `StoryRider`.
- **The root `CLAUDE.md`:** "015 M10 apartment and story" in the feature list.
