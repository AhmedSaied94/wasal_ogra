# Implementation review: 014-m09-lines-vehicles, round 1

- Date: 2026-10-29 · Reviewer: Claude Code (Opus 5.5), `/speckit-review-implementation`, with six layer subagents (two spec-conformance, UI/design, mobile/economy, backend/content/docs/security, tests); every finding below re-checked by the reviewer
- Branch: 014-m09-lines-vehicles · Base: origin/master (merge base 68f7ec5) · Head: a69714c, plus 32 uncommitted files (spec-kit and opencode setup, not part of the feature)
- Change: 5 commits (the spec commit f80cb91, then 2ac7adb, cf1c1ac, 0ac7239, a69714c), 184 committed files, +11,916 −98
- Verdict: **CHANGES REQUESTED** · CRITICAL 0 · HIGH 1 · MEDIUM 14 · LOW 18

The core holds. `tripPlayable` is only ever stricter than the server (a chapter complete implies it
unlocked, and the server's whole rule for a story trip is the chapter unlocked; regular trips are the
port's rule unchanged). The purchase goes through `EconomyService.buy` with one held request id, the
catalog price read when it applies, and nothing half-applied on any outcome (a refusal is never
stored, so keeping the id after `insufficientFunds` is safe). Migration `content.0010` is expand-only
with `db_default`s. No test, guard, threshold or CI step was weakened, and every changed golden is
explained by a UI change in the diff. What needs work: one ticked test task that skips the purchase's
outcomes, two places where a cell or Home offers a trip the start path then silently refuses, and a
set of test gaps and owner-facing documents.

## Checks

| Check | Command | Result |
| --- | --- | --- |
| Backend lint | `uv run ruff check . && uv run ruff format --check .` (backend) | exit 0 |
| Backend types | `uv run mypy .` (backend) | exit 0 |
| Missing migrations | `uv run manage.py makemigrations --check --dry-run` | exit 0 |
| OpenAPI contract | `spectacular --validate --fail-on-warn` to a temp file, `diff -u` with `contracts/openapi.yaml` | exit 0, no diff |
| Backend tests | `uv run pytest -n 4 --cov --cov-fail-under=80` | exit 0 after `uv sync --locked --reinstall-package wassal-content --reinstall-package wassal-solver`: 1,988 passed, coverage 95.40% (the first run's 18 failures and 405 errors were `ImportRefused` from the venv's stale non-editable `wassal-content`) |
| Content kit lint and types | `ruff`, `ruff format --check`, `mypy` (tools/content_kit) | exit 0 |
| Content kit tests | `uv run pytest --cov --cov-fail-under=80` | exit 0 |
| Codegen | `uv run wassal-content codegen --check` | exit 0 |
| Layouts validate | `validate-source ../../content/source` and `../../content/examples/sample` | exit 0 |
| Sample golden | `uv run wassal-content golden` | exit 0 |
| Bundled packs | `bundle dev --check`, `bundle release --check` | exit 0 |
| Schema diff | `uv run wassal-content schema-diff --base 68f7ec5` | exit 0 |
| Solver lint and types | `ruff`, `ruff format --check`, `mypy` (tools/solver) | exit 0 |
| Solver tests | `uv run pytest -n 4 --cov --cov-fail-under=80` + engine coverage 90 | exit 0 after `uv sync --locked --reinstall-package wassal-content`: 1,000 passed, 3 skipped, coverage 98.13%, engine 99% (the first run's 17 failures were the same stale `wassal-content`) |
| Solver checks | `sync --check`, `parity`, `check-source` sample and source, `bench --digest` | exit 0: tunables in step, 62 parity fixtures ok, sample and source solved, bench 50/50 solved |
| content_models | `pub get`, `build_runner`, format, `analyze --fatal-infos`, tests, coverage ≥ 80 | exit 0 |
| trip_engine | `pub get`, format, `analyze --fatal-infos`, tests, coverage ≥ 90 | exit 0 |
| App deps and codegen | `fvm flutter pub get && fvm dart run build_runner build -d` | exit 0 |
| App format | `fvm dart format --output=none --set-exit-if-changed $(git ls-files '*.dart')` | exit 0 |
| App analyze | `fvm flutter analyze --fatal-infos` | exit 0 |
| App tests and goldens (repo guards included) | `fvm flutter test --coverage --exclude-tags backend` | exit 0: 4,848 passed, 6 skipped (all pre-existing conditional skips: no release pack bundled, nothing promoted) |
| App coverage | `fvm dart run tool/check_coverage.dart --min 80` | exit 0: 90.91% |
| Integration: the Lines loop | `fvm flutter test integration_test/lines_loop_test.dart -d flutter-tester` | exit 0 |
| Integration: the Home loop | `… integration_test/home_loop_test.dart -d flutter-tester` | exit 0 |
| Integration: the first session | `… integration_test/first_session_test.dart -d flutter-tester` | exit 0 |
| sync-e2e seed | `uv run manage.py shell < ../apps/mobile/test/backend/seed_backend.py` (after `migrate content` applied 0010 to the dev DB) | NOT RUN in effect: exit 1, the dev DB's current pack is version 11 and the seed leaves a stack with a current pack as it is (it needs version 1) |
| sync-e2e tests | `WASSAL_E2E_API=http://localhost:8000 fvm flutter test --tags backend test/backend` | NOT RUN in effect: exit 1, every op `unknown_content_version` against this dev DB, and the pre-M09 `offline_sync_test` and `stale_state_test` fail the same way; a fresh stack (`down -v`, which wipes the dev data) is the owner's call, and CI's `sync-e2e` job runs it on one |

## Findings

### HIGH

#### R1-1: T051 is ticked, but the vehicle sheet's refusals, rollback and announcement have no test

- Layer: tests, spec · Source: T051, FR-037, FR-038, FR-039, constitution XIII (purchases are test-first) · Location: `apps/mobile/test/features/lines/vehicle_sheet_test.dart:1-223`; the code it leaves untested at `apps/mobile/lib/features/lines/presentation/vehicle_sheet.dart:88-113` · CONFIRMED
- Problem: T051 lists "refused, write-failed and not-for-sale, each with its result", "a sync flipping short ↔ affordable", "a rollback after a purchase" and "applied → `/lines` with the announcement". The file has the applied path (location only), the write failure, one direction of the flip (affordable → short, via a local chapter purchase, not a sync) and the closes. There is no case for `insufficientFunds` (shortfall shown, id kept), `alreadyOwned` (owned sheet), the other refusals (toast and `/lines`), a rollback, or the announcement. `vehicle_purchase_test.dart` checks only how the request id is kept or cleared, against a fake.
- Failure scenario: change the `OpRefused()` branch to close without the toast, delete `SemanticsService.sendAnnouncement`, or stop the sheet following M06's rollback: every test still passes.
- Fix direction: widget cases against the real economy for each refusal, a rollback driven through `EconomySync.applyAnswer`, the flip in both directions through a balance change, and an assertion that the announcement is sent.

### MEDIUM

#### R1-2: A finished trip that is no longer playable is drawn and announced as a button, and a tap does nothing

- Layer: mobile, spec · Source: FR-026 ("a locked cell MUST do nothing and MUST NOT present itself as tappable"), FR-013, FR-012 · Location: `apps/mobile/lib/features/lines/domain/trip_cells.dart:76-77` (stars ≥ 1 → `done` before `tripPlayable` is asked) and `:46` (`startable` = not locked); `trip_grid.dart:157-176`; the refusal at `apps/mobile/lib/features/home/application/start_next_trip.dart:54-59` · CONFIRMED
- Problem: the grid decides a cell can start on its own, apart from the shared rule. `startNextTrip`'s step 0 then returns false with no feedback.
- Failure scenario: (a) the player buys the shabka offline and plays `line_gamaa.18`; the server refuses the shabka but accepts the trip (it needs only ch3 unlocked); after the rollback `.18` keeps its stars while ch3 is incomplete. (b) The spec's edge case "a newer pack adds trips to a line the player had finished": `lineComplete(line_hay)` turns false, so ch1 and every later chapter are incomplete, and the done story trips `line_hay.20` and `line_gamaa.01` become dead buttons. The test fixtures already hold this state (`line_details_sheet_test.dart` `_board` stars `line_gamaa.10` with ch1 incomplete) and no test taps it.
- Fix direction: base a done cell's tap on `tripPlayable` too: show the stars, but no tap and no button semantics when it can't start (a "done, locked" look); add a test that taps such a cell.

#### R1-3: The first session's next trip skips `tripPlayable`, so Home's start button can do nothing

- Layer: mobile · Source: FR-012, SC-003a; research.md:61 claims M07's tutorial trips are "all regular" · Location: `apps/mobile/lib/features/home/application/home_model.dart:138-140` (`homeNextTrip` returns `nextTutorialTrip` unchecked); `apps/mobile/lib/features/onboarding/presentation/first_session_continue.dart:31` (goes straight to `/trip/<id>`); `apps/mobile/lib/features/onboarding/domain/first_session.dart:296` (`tutorialTripsOf` takes the start line's first five trips of any kind) · CONFIRMED
- Problem: the sample pack's tutorial trips include the story trip `line_hay.03` (research.md:65 says so itself). It works only because the sample's ch1 goal is met exactly when `.03` comes up. Nothing in the content kit keeps a story trip out of the first five.
- Failure scenario: a pack whose start line has a story trip among its first five, with a chapter goal the earlier tutorial trips don't meet. Home shows it as the next trip; «يلا نطلع» calls `startNextTrip`, which refuses, and nothing happens (the first session is stuck from Home after a restart). The result's continue button meanwhile starts the same trip directly, which Lines draws locked.
- Fix direction: check `tripPlayable` for the tutorial trip in `homeNextTrip` and `nextAfterResult`, and either keep story trips out of `tutorialTripsOf` or add a content-kit rule that the start line's first five trips are regular; correct research R2's text.

#### R1-4: The grid can hide finished trips once a story trip opens behind the player (FR-025 needs a decision)

- Layer: spec, mobile · Source: FR-025 vs US2 ("tapping a finished trip replays it"), SC-001, `contracts/design-briefs.md` §3 (`LineDetailsStory`: "30 trips, 6 rows") · Location: `apps/mobile/lib/features/lines/domain/trip_cells.dart:124-146` · CONFIRMED
- Problem: rows are `max(4, next row + 2)` from the `next` cell only, as FR-025 is written. When a story trip opens behind trips the player already finished, `next` jumps back and the finished trips past it fall into the hidden range, under the hint «بتظهر لما تقرّب».
- Failure scenario: the release draft's `line_gamaa` (30 trips): the player plays `.19`–`.30` while `.18` waits, then buys the shabka. `next` = `.18` → 5 rows; trips 26–30, all finished, are hidden and can't be replayed until `.18` is played. The owner's brief for that very state expects 6 rows.
- Fix direction: an owner decision on FR-025 (recommended: show rows through the last done or playable cell, at least four, plus one row past the next trip), then the code and a `visibleRange` test for the `LineDetailsStory` state.

#### R1-5: The map scrolls to the focus line only on its first mount

- Layer: ui · Source: FR-020 ("on opening, the line of FR-010 MUST be in view"), FR-010, US1 acceptance 6 and 7 · Location: `apps/mobile/lib/features/lines/presentation/line_map.dart:51-60` (the only `ensureVisible`, in an `initState` post-frame callback) · CONFIRMED
- Problem: the Lines branch stays mounted (`lines_screen.dart` listens to the router while away; commit 0ac7239), so returning to the tab, arriving from Home's line card, or the focus changing after a purchase never scrolls again.
- Failure scenario: with three or more lines, or at 360×640 and 1.3×: open Lines, scroll to the top, go Home, tap Home's line card; Lines reappears at the old offset and the line Home shows is out of view. Latent with the first release's two cards.
- Fix direction: re-run the focus scroll when the location becomes `/lines` and when `focus` changes; test scroll away → Home → back by the tab and by Home's line card.

#### R1-6: The seen set only grows, so news that comes back never raises the dot again

- Layer: mobile · Source: FR-041, US6 acceptance 1 and 2 ("until the next such event") · Location: `apps/mobile/lib/features/lines/application/lines_seen.dart:40-44` (`state = {...state, ...news}`, never pruned) · CONFIRMED
- Failure scenario: the player opens Lines at exactly the microbus's price (`vehicle:micro_old` seen), buys a piece (the key leaves the news), earns the price back on Home: no dot. The same for `line:line_gamaa` after a refused offline purchase is rolled back and bought again from outside Lines.
- Fix direction: keep only seen keys that are still news (`seen ∩ news`) whenever the news changes, and persist that; test the recurrence.

#### R1-7: The Rive vehicle preview is stretched 1.36× horizontally

- Layer: ui · Source: FR-031, HANDOFF §6.4 (the `Vehicle` artboard is 236×150) · Location: `apps/mobile/lib/features/lines/presentation/vehicle_preview.dart:21` (`Size(322, 150)`) and `:55-62`; `apps/mobile/lib/core/theme/components/vehicle_sprite.dart:27,40` (`Fit.fill`) · CONFIRMED
- Problem: a 236×150 artboard drawn with `Fit.fill` into a 322×150 box. Only the static fallback (`BoxFit.contain`) is covered by goldens, so CI can't see it.
- Failure scenario: on a device where `wassal.riv` loads, the BuyVehicle sheet shows a distorted vehicle.
- Fix direction: keep the artboard's aspect (a 236×150 box, scaled uniformly, or a uniform fit for this caller), and add a `rive`-tagged golden of the preview.

#### R1-8: A failed write and the shortfall appear silently to a screen reader

- Layer: ui · Source: SC-007 ("every purchase announces its result"), FR-038, FR-049, constitution XI · Location: `apps/mobile/lib/features/lines/presentation/vehicle_sheet.dart:104-109` and `:178-205` · CONFIRMED
- Problem: only the status line is a live region. The retry line «ما عرفناش نكمّل الشرا.» and the shortfall after an `insufficientFunds` refusal appear with no announcement.
- Failure scenario: a TalkBack player taps «اشتريها», the disk is full, and hears nothing; they can't tell whether anything was spent.
- Fix direction: make both texts live regions or announce them, and test it.

#### R1-9: The goldens for the undrawn and composed states don't exist, yet T088 asks the owner to approve them

- Layer: tests, ui · Source: FR-045 ("the states the artboards don't draw … MUST have goldens too"), research R12, T088 · Location: `apps/mobile/test/goldens/design/` (only `lines_`, `line_details_` and `buy_vehicle_goldens_test.dart`); `specs/014-m09-lines-vehicles/tasks.md:810-820` · CONFIRMED
- Problem: the composed states R12 says need no board (a done card at three stars, a line under 20 trips, the impact hidden, the plain affordable sheet, Lines offline, 360 pt at 1.3×) and the undrawn states (a done line's details, a locked line's details, the owned sheet, the not-for-sale sheet) have widget tests but no golden. No task built them; T076–T078 cover only the states the owner's boards will draw.
- Failure scenario: the owner is asked to approve images that don't exist, and a visual regression in these states passes CI.
- Fix direction: add samples and goldens (both digit styles) for R12's composed states and the four undrawn states now; T076–T078 later align them to the boards.

#### R1-10: Visible differences from the `Lines` board and widened layout tolerances aren't listed for the owner

- Layer: ui · Source: `docs/design/README.md` ("any other visible difference is a bug, unless the owner accepts it"), FR-045, FR-046, SC-005 (±2 pt), research R12 · Location: `apps/mobile/test/design/lines_layout_test.dart:36-40` (`tolerances: {4: 5, 43: 3, 52: 3}`); `apps/mobile/lib/features/lines/presentation/line_map.dart:132` (the `route_bold` glyph for the current marker, where `Lines.html` draws a microbus; research R10 says "the route icon, as drawn"); `line_card.dart:75` with `AppCard(locked: true)` (the lock at the card's top end, the board has it at the start side, centred); current and done card titles at 17 pt (boxes 46 and 55 are 18); the done node's tick 14 pt (board 12) · CONFIRMED
- Problem: none of these is in R12's expected differences, the golden test headers' lists or T088. The tolerance note's reason ("the bottom bar starts 3 pt lower") doesn't fit the nav boxes 61–69 and the upper cards passing at ±2.
- Failure scenario: a real 3–5 pt drift of the BONAT pill or the two line cards passes silently, and the owner reviewing the side-by-side either treats the differences as bugs or never sees them.
- Fix direction: match the board (marker, lock position, title 18, tick 12) or list each difference in R12, the golden and layout test headers and T088; find the cause of the 3 pt offset or state the measured value, keeping only the pill's widening (its 44 pt hit area).

#### R1-11: The minimum-size tests cover only the artboard state of each screen

- Layer: ui, tests · Source: FR-048, SC-006, constitution XI · Location: `apps/mobile/test/a11y/{lines,line_details,buy_vehicle}_minimum_sizes_test.dart` (each builds only `test/design/samples/<artboard>.dart`) · CONFIRMED
- Problem: not checked at 360×640 and 1.3×: the shortfall sheet (the «ناقصك» line, the bar and the disabled button sit outside the scroll area of a 486 pt sheet), the owned and not-for-sale sheets, the retry line, a done or locked line's details with the reason panel, long names.
- Failure scenario: an overflow or an unreachable control on a small phone at large text, in the shortfall state a short player is most likely to see.
- Fix direction: run the same a11y checks over those states.

#### R1-12: T034 is ticked, but `start_next_trip_test` lacks two of its six cases for a start from Lines

- Layer: tests · Source: T034, FR-026, the spec's edge cases "the first session" and "a start already under way" · Location: `apps/mobile/test/features/home/application/start_next_trip_test.dart` · CONFIRMED
- Problem: "a tutorial trip in the first session goes to `/trip/<id>`" and "a second tap while the checkpoint waits does nothing" are absent for `StartFrom.lines` (they are covered only from Home, in `home_screen_test.dart`). The story case (`line_gamaa.20` with ch1 incomplete) doesn't separate `tripPlayable` from the port's rule, since both refuse it.
- Failure scenario: a Lines-only path that bypasses `startUnderWayProvider` or mishandles a tutorial trip ships green.
- Fix direction: add both cases from Lines, and a story case the port accepts but `tripPlayable` refuses (`line_gamaa.18` after `.17`, shabka not bought).

#### R1-13: Five behaviours have tests that can't fail when the behaviour breaks

- Layer: tests · Source: FR-010, FR-041/T069, FR-033, FR-025/FR-028, SC-002 · CONFIRMED
- `apps/mobile/test/features/lines/domain/focus_line_test.dart:13-23`: in every case Home's line equals the fallback's pick, so deleting `focus_line.dart:13` (Home's next trip first) fails nothing. Add a state where they differ (`player({'line_hay.01': 1}, {microOld})` with next `line_hay.02`: Home's line is hay, the fallback gives gamaa).
- `apps/mobile/test/features/lines/lines_dot_test.dart:78-111`: the news-while-away test never asserts the dot is on before the return; the only "dot on" case comes from a store seeded at launch. Assert `_dot(container)` is true right after the purchase on Home.
- `apps/mobile/test/features/lines/vehicle_sheet_test.dart:53`: the short test taps «اشتريها» and checks nothing was spent, which `VehiclePurchase` guarantees anyway; the disabled state and the progress bar aren't asserted. Assert the button's semantics are disabled and the `ProgressBar` value.
- `apps/mobile/test/features/lines/domain/trip_cells_test.dart:165` passes cells with a next trip, which give four rows without `locked: true` too; the widget test uses the 2-trip `line_masyaf`. Call `visibleRange` with all-locked cells and add a widget test for a locked line of more than 20 trips.
- `apps/mobile/integration_test/lines_loop_test.dart:191-198`: step 5 claims خط الجامعة's next trip is now its second but only checks «كمّل» can be tapped. Assert `line_gamaa.01` is starred and «كمّل» names trip ٢.

#### R1-14: The release draft still lacks the three new fields (T010), though its worktree is on this machine

- Layer: engine/content, ops · Source: T010, FR-042, research R9 · Location: `/mnt/endeavour/home/saied-dev/Work/wasal_ogra-core-r1/content/drafts/core-r1/pack/lines/{line_hay,line_gamaa}.json`, `pack/vehicles/{tuktuk,micro_old}.json`; `docs/owner-actions.md:1085-1087` · CONFIRMED
- Problem: `git worktree list` shows `wasal_ogra-core-r1` on `content-core-r1`; none of the four files has `whats_new`, `display_fare_piasters` or `short_name`. owner-actions says the worktree "wasn't on the machine that built M09", true of the implementing session's machine but not of this one.
- Failure scenario: `validate-source` or `content_import` of the draft fails at the schema stage, blocking the core-r1 build and promotion.
- Fix direction: do T010 in the worktree (uncommitted there, as T010 says), with the sample's values (fares 700 and 850 match the draft's trip fares); then rewrite owner-actions' item 1 as the owner's approval of the texts (T089).

#### R1-15: The runbook misses four consequences of a required-field schema change, and misstates the fare default

- Layer: ops, db · Source: constitution (migrations expand/contract: the previous release keeps working), B04 FR-028 (rollback), CLAUDE.md "Owner actions" · Location: `docs/runbooks/content-publishing.md:46-51` and §4 `:137-145`; `backend/apps/content/services/build.py:252` (a rollback build reads the old pack's parts) then `produce` → `validate_pack` against today's schema; `backend/apps/content/services/promote.py:179-185` (production validates with its own schemas, which are closed objects); `backend/apps/content/services/publish.py:88` (no schema re-check); `backend/apps/content/models/lines.py:50` (default 50) · CONFIRMED
- Problems: (a) after the deploy, "Roll back to this" on any pack built before `0010` fails at the schema stage, while §4 says any published or retired pack can be rolled back to; (b) promoting the first M09 pack needs production on an M09 release first, or production refuses the unknown properties; (c) a draft validated before the deploy can still be published after it, and every M09 app refuses it; (d) `content_export` of a pre-M09 version no longer imports; (e) the runbook says rows from before the migration hold "a fare of 50 and empty texts, which a build refuses", but 50 is a valid fare, so a forgotten fare publishes and shows ٠٫٥ ج.
- Failure scenario: the first M09 pack on staging has a bad trip; the owner rolls back to the previous pack and the build is refused, with nothing in the runbook explaining why.
- Fix direction: document (a)–(d) in the runbook (§1's paragraph and §4), `contracts/content-fields.md` "Deployment" and owner-actions' after-merge item 1, and correct (e) to say the fare must be checked by hand (optionally a build warning when a fare equals the migration default).

### LOW

- **R1-16** Owned and needs-first sheets say wrong things (pending T078): `vehicle_sheet.dart:157` shows `BenefitsRow` in every state, so the current vehicle reads «١٠ كراسي بدل ١٠» and the tuktuk after the microbus claims «قبض أكتر في كل مشوار»; the starter's «وانت شغال عليها» shows after the microbus is current (`:127`); the `NeedsFirst` sheet hides the price card against brief §8. Related: `NeedsFirst` tiles show no price (`vehicle_tiles.dart:113-117`), against FR-017 and the board's «ميكروباص سفر، بـ١٢٬٠٠٠ جنيه»; listed for the owner in owner-actions but not in the plan's Complexity Tracking. Can't occur in the first release (two vehicles). CONFIRMED.
- **R1-17** Screen-reader stars lack number agreement for lines with 3–10 stars: `app_ar.arb:2925,2939` «{earned} من {max} نجمة» (used at `line_card.dart:109,140`); the sample's 2- and 3-trip lines read «من ٦ نجمة», «من ٩ نجمة». Release lines (60, 90) are correct. FR-050. CONFIRMED.
- **R1-18** «كمّل» is a hand-rolled `Pressable` + `Container` (`line_card.dart:184-212`) where `AppButton.primary` fits, and the current/done cards rebuild `AppCard` by hand for want of a ring option. FR-045, R11. CONFIRMED.
- **R1-19** A pressed done cell fades to `Pressable.disabledOpacity` (`trip_grid.dart:171`), the disabled look of HANDOFF §9.1 #5. FR-051. CONFIRMED.
- **R1-20** The retry line stays after the sheet changes state (owned or not for sale after a sync): `_writeFailed` is reset only by the next purchase outcome (`vehicle_sheet.dart:68,105,109,194`). CONFIRMED.
- **R1-21** `LineDetailsSheet` and `VehicleSheet` aren't keyed by id (`router.dart:254-261`; go_router's `pageKey` is the pattern), so a reused state can carry `_leaving`, the held TxnId or `_writeFailed` to another id; reachable only by a crafted or stale location. PLAUSIBLE.
- **R1-22** `startNextTrip` checks playability only before `await betweenTripsCheckpoint.pass()` (`start_next_trip.dart:54-76`); once M11's interstitial exists, a rollback during the ad could start an unplayable trip on the direct path. CONFIRMED (future risk).
- **R1-23** `pref.lines_seen` takes its baseline before M06's restore and belongs to the device, not the player (`lines_seen.dart:29-37`): a reinstall shows the dot for things already owned; an account switch hides news. CONFIRMED.
- **R1-24** The dot may show for one frame when news arrives while the bare Lines tab is showing (`lines_dot_watcher.dart:22-30` shows synchronously; seen-marking runs after the frame). US6 acceptance 3. PLAUSIBLE.
- **R1-25** `_linesAllowed` in `test/repo/domain_imports_test.dart:100-108` has no allow/refuse scan test of its own, unlike the other lists. CONFIRMED.
- **R1-26** The `sync` path filter (`.github/workflows/mobile.yml:70`) doesn't include `apps/mobile/lib/features/lines/` or `lib/core/progress/`, so later changes there won't rerun `lines_purchase_sync_test.dart`. CONFIRMED.
- **R1-27** `next_trip_test.dart:133-136` "the line played last first" no longer distinguishes by the last trip (FR-007 leaves one candidate); the rule is covered only by the new draft case. CONFIRMED.
- **R1-28** `test/helpers/synthetic_packs.dart:290-299,372-376`: `artboardLines()` gives line_souq, line_masyaf and line_safar trips micro_old's 10 seats while their vehicles have 12–13, breaking content rule V-T3; latent (no test plays them). CONFIRMED.
- **R1-29** `pre_trip_card_test.dart:229-233` "a trip of another line" uses `line_gamaa.01`, locked for the default player, so it passes with or without the `linePreTrip` redirect. CONFIRMED.
- **R1-30** SC-003a's agreement is shown by five hand-picked states (`story_agreement_test.dart:26-61`), and "a line's next trip" is computed twice (`line_standing.dart:221` `nextInLine`, `next_trip.dart:83,90`), both outside `core/progress/domain/` (FR-013's one set of rules). CONFIRMED.
- **R1-31** T090 is ticked though the `rive`- and `backend`-tagged tests didn't run in the implementing session (disclosed in owner-actions §014, whose "no Docker" doesn't describe this machine). This review couldn't run the backend-tagged ones against the dev stack either (Checks); CI's `sync-e2e` job settles them. CONFIRMED.
- **R1-32** The grid and the map build every cell and card eagerly (`trip_grid.dart`, `line_map.dart:82`), each `Pressable` with an `AnimationController`; strip tiles align to the start, so at 1.3× the tuktuk tile is taller than the rest. CONFIRMED.
- **R1-33** `design_extras.dart` (+213) adds 25 `TextStyle`s, several near-duplicates of `TypeTokens` entries (12/600, 12/700, 14/600). Legitimate in the tokens folder; a maintenance note. CONFIRMED.

## Requirements

| Requirement | Built in | Proven by | Status |
| --- | --- | --- | --- |
| FR-001 | `features/lines/application/lines_model.dart` (derived each view) | `lines_screen_test` redraw | met |
| FR-002 | `core/progress/domain/playable.dart:32` | `playable_test`, `vehicle_tiles_test` | met |
| FR-003 | `playable.dart:110-128` | `playable_test` vehicles, sweep; `vehicle_purchase_test` | met |
| FR-004, FR-005 | `unlocks.dart` (port, unchanged) | `unlocks_test`, `line_standing_test` | met |
| FR-006 | `playable.dart:27` | `playable_test` | met |
| FR-007 | `playable.dart:19-25` | `playable_test` US5, `story_agreement_test`, `sample_sweep_test` | met |
| FR-008 | `line_standing.dart:221` | `line_standing_test`, `trip_cells_test` | met (R1-30) |
| FR-009 | `line_standing.dart:197-248` | `line_standing_test` | met |
| FR-010 | `focus_line.dart`, `lines_model.dart:80` | `focus_line_test` can't fail (R1-13) | partial |
| FR-011 | `playable.dart` | `playable_test` never-more-permissive sweep (depth 8) | met |
| FR-012 | `next_trip.dart:70`, `pre_trip_card.dart:93`, `start_next_trip.dart:54-59` | `start_next_trip_test`, `pre_trip_card_test`, `next_trip_test` | partial (R1-2, R1-3) |
| FR-013 | `core/progress/domain/playable.dart` | `domain_imports_test` | partial (R1-2, R1-30) |
| FR-014, FR-015 | `lines_screen.dart` | `lines_screen_test`, `shell_test` | met |
| FR-016 | `vehicle_tiles.dart`, `line_standing.dart` | `vehicle_tiles_test` | met |
| FR-017 | `vehicle_tiles.dart:103`, `vehicle_strip.dart` | `lines_screen_test` | partial (R1-16) |
| FR-018, FR-019 | `line_card.dart`, `lines_screen.dart:133-146` | `lines_screen_test` | met |
| FR-020 | `line_map.dart:51-101` | first-frame test only | partial (R1-5) |
| FR-021 | `fare_chip.dart` | `lines_screen_test` | met |
| FR-022 | providers | `lines_screen_test`, `vehicle_tiles_test` | met (sheet rollback untested, R1-1) |
| FR-023 | `line_details_sheet.dart` | `line_details_sheet_test` | met |
| FR-024 | `trip_cells.dart`, `trip_grid.dart` | `trip_cells_test` | met |
| FR-025 | `trip_cells.dart:124-146` | `trip_cells_test` | partial (R1-4, R1-13) |
| FR-026 | `start_next_trip.dart`, `line_details_sheet.dart:61`, `router.dart` `linePreTrip`, `pre_trip_card.dart` | `line_details_sheet_test`, `pre_trip_card_test` | partial (R1-2, R1-12) |
| FR-027 | `line_details_sheet.dart:127-183` | `line_details_sheet_test` | met |
| FR-028 | `line_details_sheet.dart:137-182` | `line_details_sheet_test` (2-trip line) | met (four rows untested, R1-13) |
| FR-029 | sheet page | `line_details_sheet_test` closing | met |
| FR-030 | `vehicle_sheet.dart`, `benefits_row.dart`, `price_card.dart`, `impact_line.dart` | `vehicle_sheet_test` | met |
| FR-031 | `vehicle_preview.dart` | BuyVehicle golden (fallback only) | partial (R1-7) |
| FR-032 | `features/lines/domain/impact.dart` | `impact_test` | met |
| FR-033 | `vehicle_sheet.dart:178-193,218` | `vehicle_sheet_test` (text only) | met (disabled, bar unasserted: R1-13) |
| FR-034, FR-035 | `vehicle_sheet.dart`, `playable.dart` | `vehicle_sheet_test` US4 | met (copy R1-16) |
| FR-036 | `vehicle_purchase.dart`, M05 `validateBuy` | `vehicle_purchase_test`, `vehicle_sheet_test` | met |
| FR-037 | `vehicle_sheet.dart:89-103` | location only | partial (R1-1) |
| FR-038 | `vehicle_sheet.dart:88-113` | id handling only | partial (R1-1, R1-8) |
| FR-039 | M06 rollback, providers | `lines_purchase_sync_test` (accepted case) | partial (R1-1) |
| FR-040 | `_close` | `vehicle_sheet_test` closing | met |
| FR-041 | `lines_news`, `lines_seen`, `lines_dot_watcher`, `app.dart` | `lines_dot_test` | partial (R1-6, R1-13) |
| FR-042, FR-043, FR-044 | schemas, models, examples, sample, dev bundle, `content.0010`, importer, snapshot, admin | content kit and backend tests; no engine reader | met (release draft R1-14) |
| FR-045 | three artboards' samples, goldens and layout tests | design tests | partial (R1-9, R1-10) |
| FR-046, FR-047 | `locked_fill.dart`, `AppCard(locked)`, wrapping | goldens, a11y | met (approval T088) |
| FR-048 | sizes | a11y tests, artboard states only | partial (R1-11) |
| FR-049 | labels per the boards | `labelled(...)` checks | partial (focus and order unasserted; R1-8) |
| FR-050 | ARB plurals | goldens | partial (R1-17) |
| FR-051 | `Pressable` | none specific | met (R1-19) |
| FR-052 | research R14, owner-actions | — | met (approval T087) |
| FR-053, FR-054 | `routes.dart`, `router.dart`, `shell_scaffold.dart`, the sheets' leaves | `route_table_test`, `navigation_test`, `shell_test`, id-the-pack-lacks tests | met |
| SC-001 | «كمّل», cells | `lines_loop_test`, `line_details_sheet_test` | met (R1-4) |
| SC-002 | tile → sheet → buy | `lines_loop_test` | met |
| SC-003 | sweep; backend e2e | `playable_test`; `lines_purchase_sync_test` (not run here, Checks) | met in unit tests; e2e unproven until CI's `sync-e2e` |
| SC-003a | everything reads `tripPlayable` | `story_agreement_test` (5 states) | partial (R1-3, R1-30) |
| SC-004 | busy flag, held id, `findOp` | `vehicle_purchase_test` | met |
| SC-005 | layout tests | ±2 except three widened boxes | partial (R1-10) |
| SC-006 | a11y tests | artboard states | partial (R1-11) |
| SC-007 | labels, purchase announcement | unasserted announcement | partial (R1-1, R1-8) |
| SC-008 | no loading state | `lines_loop_test` stopwatch (local); device pass T094 | owner |
| US1 1–8 | as FR-014–FR-022 | `lines_screen_test` | met except 6, 7 (R1-5) |
| US2 1–7 | as FR-023–FR-029 | `line_details_sheet_test`, `start_next_trip_test` | met except R1-2, R1-4, R1-12 |
| US3 1–8 | as FR-030–FR-040 | `vehicle_sheet_test`, `vehicle_purchase_test` | met except 2 (announcement), 5 (rollback) (R1-1) |
| US4 1–4 | `lines_screen.dart:133-138`, sheets | `lines_screen_test`, `vehicle_sheet_test` | met |
| US5 1–5 | `playable.dart` and callers | `story_agreement_test`, `trip_cells_test` | met (R1-2 after a rollback) |
| US6 1–3 | watcher, seen set | `lines_dot_test` | partial (R1-6, R1-13) |

## Task audit

Ticked 80, verified 71, partly done 7 (T017, T034, T051, T059, T069, T081, T090), not done 0,
unverifiable 2 (T013's test-first order: test and code landed in one commit, cf1c1ac; T091's reviews:
no artifact). Unticked 15: T010 (doable now, R1-14), T074–T079 (the owner's boards), T084, T087–T089,
T092–T095 (owner approvals and after-merge steps), all genuinely not done.

| Task | Claim | Actual |
| --- | --- | --- |
| T017 | `focus_line_test` covers M07's tutorial trip in the first session | a plain `NextTrip` is passed; no first-session state, and no case separates Home's line from the fallback (R1-13) |
| T034 | six start-path cases | the tutorial-from-Lines and second-tap cases are missing; the story case doesn't separate the rules (R1-12) |
| T051 | every sheet outcome, the sync flip, a rollback, the announcement | refusals, rollback and announcement untested; the flip one way only (R1-1) |
| T059 | locked details with four rows and the hint; owned sheet without price, impact and button; a no-price tile | 2-trip fixture, so four rows never run at widget level; absences unasserted; no no-price tile test (R1-13) |
| T069 | the dot shows after news appears while away | only a store seeded at launch shows the dot (R1-13) |
| T081 | a `backend`-tagged Lines purchase and start case | written and tagged; starts the trip with `economy.startTrip`, not Lines' path; not run here (Checks) |
| T090 | every CI check run | `rive`- and `backend`-tagged tests not run in the implementing session (R1-31) |

## Outside this change

- The 32 uncommitted files (`.opencode/`, `.specify/` integration and the `review` extension, `AGENTS.md`, `CLAUDE.md`'s spec-kit lines): spec-kit setup, not M09.
- The local `backend/.venv` and `tools/solver/.venv` held a stale non-editable `wassal-content`, as `backend/pyproject.toml:53-54` warns; CI builds fresh environments, so the first runs' failures were local only (reinstalled for the reruns).
- No CI workflow runs `integration_test/` (M07's and M08's are the same): the Lines loop and its 0.5 s budget are checked locally only.
- The dev stack's database hadn't applied `content.0010`; the review applied it (`uv run manage.py migrate content`) before the sync-e2e run.

## Not reviewed

- The backend-tagged sync tests (`sync-e2e`): the dev DB's state doesn't match the seed's (see Checks); CI runs them on a fresh stack.
- The Android APK build (`build-android`) and the backend image and smoke jobs (`image`, `smoke`): not run; nothing in the change touches Gradle, Docker or the edge.
- On-device behaviour: the Rive preview's stretch (R1-7), TalkBack announcements and focus (R1-8, FR-049), the scroll geometry with more lines (R1-5), SC-008's timing (owner's device pass, T094).
- The side-by-side comparison against the design PNGs beyond the reviewers' reading of the three artboards: the owner's review (T092).
- iOS (Codemagic).
