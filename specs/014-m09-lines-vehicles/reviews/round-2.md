# Implementation review: 014-m09-lines-vehicles, round 2

- Date: 2026-10-29 · Reviewer: Claude Code (Opus 5.5), `/speckit-review-implementation`, no subagents: the committed code is unchanged since round 1 (same HEAD), and the reviewer read the whole round-1 fix set
- Branch: 014-m09-lines-vehicles · Base: origin/master (merge base 68f7ec5) · Head: a69714c, plus the uncommitted round-1 fixes (62 modified files, 21 new) and the spec-kit/opencode setup (not part of the feature)
- Change: 5 commits, 212 feature files, +13,704 −132; of which the round-1 fixes are 62 files +1,627 −212 and 21 new files (18 goldens, the Rive preview golden and its test, `round-1.md`)
- Verdict: **APPROVE WITH NOTES** · CRITICAL 0 · HIGH 0 · MEDIUM 4 · LOW 3

The round-1 fixes hold. R1-1, the one HIGH finding, is closed: the vehicle sheet's refusals, rollback, both flips and
the announcement are tested against the real economy. A starred trip the rules refuse is now inert,
the first session asks `tripPlayable`, the grid reaches every played row, the seen set forgets news
that went away, the Rive vehicle keeps its aspect, and the release draft has its fields. Four
MEDIUM findings remain. The new map scroll jumps back to the focus line whenever a sheet closes.
The `LinesSmall` golden is taken after a resize, so it shows a state no phone shows. T106 left out
the long names. T099 left research and the contracts on the old FR-025 rule.

## Checks

The lean-ctx shell allowlist on this machine blocks `fvm` and `docker`. The Flutter commands ran
with the SDK FVM pins (`~/fvm/versions/3.47.7/bin`, Flutter 3.47.7, the `.fvmrc` version), which is
what `fvm` resolves to. The dev stack was already up (5432, 6379, 8000 and 8001 answered).

| Check | Command | Result |
| --- | --- | --- |
| App deps and codegen | `flutter pub get && dart run build_runner build -d` (apps/mobile) | exit 0 |
| App format | `dart format --output=none --set-exit-if-changed` over tracked and new `*.dart` | exit 0 |
| App analyze | `flutter analyze --fatal-infos` | exit 0 |
| App tests and goldens (repo guards, `rive` tag included) | `flutter test --coverage --exclude-tags backend` | exit 0: 4,949 passed, 6 skipped (the same pre-existing conditional skips) |
| App coverage | `dart run tool/check_coverage.dart --min 80` | exit 0: 90.95% |
| Rive | `flutter test --tags rive` | exit 0: 75 passed, `rive_vehicle_preview_goldens_test` among them |
| Integration: the Lines loop | `flutter test integration_test/lines_loop_test.dart -d flutter-tester` | exit 0 |
| Integration: the Home loop | `… integration_test/home_loop_test.dart -d flutter-tester` | exit 0 |
| Integration: the first session | `… integration_test/first_session_test.dart -d flutter-tester` | exit 0 |
| Reviewer's probe (scratchpad, not in the repo) | `flutter test <scratchpad>/probe/sheet_close_scroll_test.dart`: 360×640 at 1.3×, scroll to خط المصيف, open its details, close them | exit 1: the map's offset goes from 204.0 to 577.5, and خط المصيف's card ends at y 50.5 above a map that starts at 254 (R2-1). Outside `test/`, the probe misses `flutter_test_config.dart`'s fonts, so its two overflow logs are artefacts of the test font and were dropped |
| Release draft | `uv run wassal-content validate-source <core-r1 worktree>/content/drafts/core-r1/pack` | exit 0: 0 errors, 0 warnings; the tutorial fixture's `line_hay.json` equals the draft's |
| Backend lint and format | `uv run ruff check . && uv run ruff format --check .` | exit 0 |
| Backend types | `uv run mypy .` | exit 0 |
| Missing migrations | `uv run manage.py makemigrations --check --dry-run` | exit 0 |
| OpenAPI contract | `spectacular --validate --fail-on-warn` to a temp file, `diff -u` with `contracts/openapi.yaml` | exit 0, no diff |
| Backend tests | `uv run pytest -n 4 --cov --cov-fail-under=80` | exit 0: 1,988 passed, 95.40% |
| Content kit lint, types, tests | `ruff`, `ruff format --check`, `mypy`, `pytest --cov --cov-fail-under=80` | exit 0: 587 passed, 96.59% |
| Codegen | `uv run wassal-content codegen --check` | exit 0 |
| Layouts validate | `validate-source` on the sample and `content/source` | exit 0 (`content/source` has no `pack.json` yet) |
| Sample golden | `uv run wassal-content golden` | exit 0 |
| Bundled packs | `bundle dev --check`, `bundle release --check` | exit 0: both match a fresh build |
| Schema diff | `uv run wassal-content schema-diff --base 68f7ec5` | exit 0: the three newly required fields reported as breaking, allowed while nothing is promoted |
| Solver lint and types | `ruff`, `ruff format --check`, `mypy` (tools/solver) | exit 0 |
| Solver checks | `sync --check`, `parity`, `check-source` on the sample | exit 0: tunables in step, 62 fixtures ok, 5 trips solved |
| Solver tests and bench, `content_models`, `trip_engine` | — | NOT RUN this round: no change under `tools/solver/` or `packages/` since round 1 (same HEAD, nothing uncommitted there), and round 1 ran them green on this code |
| sync-e2e seed and `backend`-tagged tests | — | NOT RUN: the dev DB still holds round 1's pack version 11 and the seed needs a fresh stack (`down -v` wipes the dev data, the owner's call); `docker` is blocked for the reviewer here. CI's `sync-e2e` job runs them |

## Previous round

| Finding | Now |
| --- | --- |
| R1-1 (HIGH) vehicle sheet outcomes untested | fixed: `vehicle_sheet_test.dart` group "refusals and rollback": `insufficientFunds`, `alreadyOwned`, the catalog change's toast, a rollback through `applyAnswer`, both flips through `replaceFromServer`, the announcement captured on the accessibility channel, both live regions |
| R1-2 dead button on a starred unplayable cell | fixed: `TripCell.playable`, `startable` follows it (`trip_cells.dart:51`); the cell is drawn locked and isn't a button (`trip_grid.dart:92,163-178`); unit and widget tests |
| R1-3 first session skips `tripPlayable` | fixed: `homeNextTrip` (`home_model.dart:140-145`) and `nextAfterResult` (`first_session.dart:235-244`) ask it; research R2 corrected. The content-rule half of T098 was declined with a reason (see R2-7) |
| R1-4 grid hides finished trips | fixed in code and spec (FR-025 amended with the owner's choice); research and the contract still state the old rule (R2-4) |
| R1-5 focus scroll on first mount only | fixed for the tab and Home's line card (`lines_screen_test` T100), but the fix scrolls on every return to `/lines`, sheets included (R2-1) |
| R1-6 seen set only grows | fixed: `_prune` keeps `seen ∩ news` (`lines_seen.dart:34,52-57`); recurrence test in `lines_dot_test` |
| R1-7 Rive vehicle stretched | fixed: `Fit.contain` for the preview (`vehicle_preview.dart:62-64`), other callers keep `Fit.fill`; `rive`-tagged golden added and passing |
| R1-8 silent retry line and shortfall | fixed: both are live regions (`vehicle_sheet.dart:181-211`), tested |
| R1-9 goldens for the undrawn states missing | fixed: nine states × two digit styles under `test/goldens/design/goldens/`; T088 names them. `LinesSmall` shows a state no phone shows (R2-2) |
| R1-10 unlisted differences from `Lines` | fixed: the bus marker (`MicrobusGlyph`), the lock at the card's start (`AppCard.lockInline`), titles 18, tick 12; boxes 43 and 52 back to ±2; the pill's ±5 listed in R12 and the test header |
| R1-11 a11y only on the artboard states | partly fixed: shortfall, owned, not-for-sale, failed write, done and locked details, Lines done and offline now checked on three phones at 1.0 and 1.3; long names not (R2-3) |
| R1-12 T034's Lines cases | fixed: the tutorial trip, the held checkpoint's second tap, and `line_gamaa.18` after `.17` (the port accepts, `tripPlayable` refuses, no fuel spent) |
| R1-13 five tests that couldn't fail | fixed: (a) Home's line beats the fallback; (b) the dot asserted on Home; (c) disabled semantics and the bar at 1,200 ÷ 1,500; (d) all-locked cells and a 30-trip locked line's four rows; (e) `line_gamaa.01` starred and the next trip 2 (asserted on the model, not on «كمّل»'s text) |
| R1-14 release draft lacks the fields | fixed: the worktree's four files carry them (uncommitted there, as T010 says) and the draft validates; owner-actions item 1 rewritten |
| R1-15 runbook misses the schema change's consequences | fixed: `content-publishing.md` §1 and §4, `contracts/content-fields.md` "Deployment" and owner-actions after-merge 1; the fare-of-50 claim corrected. The optional build warning isn't built, and the contract says so |
| R1-16 – R1-30, R1-32, R1-33 (LOW) | still open, untouched by the fixes (R1-16's wrong benefits now visible in `BuyVehicleOwned_*.png`: «١٠ كراسي بدل ١٠») |
| R1-31 (LOW) tagged tests not run | `rive` part fixed (run here, owner-actions updated); the `backend` part is still open (Checks) |

## Findings

### MEDIUM

#### R2-1: Closing any sheet over Lines scrolls the map back to the focus line

- Layer: ui · Source: FR-029 ("close … back to Lines"), FR-020 ("on opening"), US1; introduced by T100 · Location: `apps/mobile/lib/features/lines/presentation/lines_screen.dart:67-73` (`_routeChanged` bumps `_revision` whenever the path becomes `/lines` from any other path, `/lines/<line>` and `/lines/vehicle/<id>` included); `apps/mobile/lib/features/lines/presentation/line_map.dart:64-70` (`didUpdateWidget` re-runs `ensureVisible` on a new revision) · CONFIRMED (probe in Checks)
- Problem: the sheets live under `/lines` (`routes.dart:199,210,222`), so closing a line's details or a vehicle's sheet counts as "Lines shown again". The map jumps to centre the focus line, away from the card the player opened.
- Failure scenario: 360×640 at 1.3×, the board's player. Scroll to خط المصيف and open its locked details: offset 204. Close them: offset 577.5, and the card the player was reading is off the map. No test covers closing a sheet.
- Fix direction: bump the revision only when Lines is entered from outside its branch (the previous path doesn't start with `/lines`), or when the focus changes; add a test that closing the details and the vehicle sheet keeps the offset, beside T100's two.

#### R2-2: The `LinesSmall` golden is taken after a resize, so the focus line sits half under the bar

- Layer: tests, ui · Source: FR-020, FR-045, T104, T088 (the owner approves this image) · Location: `apps/mobile/test/design/samples/lines.dart:63-68` (`pumpLinesBoard` pumps and settles at 390×844 inside `pumpLinesApp`, where the focus scroll runs, then calls `applySurfaceSize`); `apps/mobile/test/goldens/design/lines_goldens_test.dart` `LinesSmall`; `apps/mobile/test/goldens/design/goldens/LinesSmall_*.png` · CONFIRMED
- Problem: the map keeps the offset it got at 390×844. A phone that opens at 360×640 centres the focus line, as T100's test shows for `Surface.small`. The golden shows خط الجامعة cut by the bottom bar, with «كمّل» hidden. The a11y tests' `size:` variants go through the same sample, so they also check a scroll position no phone shows.
- Failure scenario: the owner approves `LinesSmall_*.png` either as a defect or, wrongly, as the expected look. A regression in the small-screen focus scroll leaves the golden unchanged.
- Fix direction: apply the size before the first frame (give `pumpLinesApp` a `Size`, or apply the surface before calling it), regenerate `LinesSmall_*`, and assert in the golden test that the focus card is fully inside the map.

#### R2-3: T106 is ticked, but long line and vehicle names are never checked

- Layer: tests, ui · Source: T106, R1-11, FR-047 ("long names and reasons wrap"), FR-048, SC-006 · Location: `apps/mobile/test/a11y/{lines,line_details,buy_vehicle}_minimum_sizes_test.dart` (their states: artboard, done at three, offline; artboard, short, done, locked; artboard, short, plain, owned, not for sale, failed write). No test under `apps/mobile/test/features/lines/` uses a long name. · CONFIRMED
- Problem: every checked state uses the artboard pack's names. A long `name`, a long `short_name` in the fixed 83.5-wide tile (`vehicle_strip.dart:27,106`), a long `whats_new`, and a five-digit price in the tile's one-line price row (`vehicle_strip.dart:134-146`) are never laid out at 360 pt and 1.3×.
- Failure scenario: a content author adds a line named «خط الكورنيش والمعادي الجديدة» or a vehicle called «ميكروباص سفر مكيّف». The card or tile overflows or clips at 1.3×, and nothing in CI notices.
- Fix direction: a synthetic pack with long line names and texts, a long vehicle short name and a five-digit price, run through `expectMinimumSizes` for Lines, LineDetails and BuyVehicle on the three phones at 1.0 and 1.3; fix what overflows.

#### R2-4: Research, the contracts and the data model still describe the rules round 1 changed

- Layer: ops, spec · Source: T099 ("Record the answer in spec.md FR-025 and research.md"), T097, T100, T105 · Location: `specs/014-m09-lines-vehicles/research.md:118-121` and `contracts/line-details.md:39` (`rows = max(4, nextRow + 2)`, no mention of the last done or playable cell or the owner's 2026-10-29 choice); `contracts/line-details.md:25-33` and `data-model.md:70,116` (`TripCell` without `playable`, no starred-but-unplayable cell, `storyDone` with no way back to locked); `contracts/lines.md:48` ("current 32 `sun` with the route glyph", now `MicrobusGlyph`) and `:67` ("On first frame", now on every return) · CONFIRMED
- Problem: spec.md was amended (FR-025, FR-026, Clarifications), but the design documents that M10 and later features read were not.
- Failure scenario: a later feature or the owner's board alignment (T077) implements the grid from `contracts/line-details.md` and brings back the hidden-rows bug R1-4 fixed, or treats the inert cell as a defect.
- Fix direction: update those five places to the code as built, and record the owner's FR-025 answer in research beside the visible-range rule.

### LOW

- **R2-5** An inert done cell reads only as done: `trip_grid.dart:79-87` labels it with `lineDetailsStateDone(stars)` while it's drawn locked (`:163-168`) and isn't a button (`:171-178`). A TalkBack player hears "finished, 2 stars" and can't tell why a tap does nothing. FR-049, SC-007. CONFIRMED.
- **R2-6** `FirstSessionContinue`'s new `playable:` argument (`first_session_continue.dart:34-41`) has no widget test. `first_session_test.dart` passes the callback to the domain method directly, and the integration test's tutorial trips are all regular, so dropping the argument fails nothing. CONFIRMED.
- **R2-7** T098 declined both content-side options (keep story trips out of `tutorialTripsOf`, or a content-kit rule), because the sample's `line_hay.03` is itself a tutorial story trip. In a pack whose tutorial story trip isn't playable when reached, `tutorialDone` stays false (`first_session.dart:258`), so the boosters stay locked (`:273`) and the first session doesn't end until the chapter opens. Neither the sample (ch1 met at `.03`) nor the release draft (its first five trips are regular; its only `line_hay` story trip is `.20`) can reach it. A narrower rule would cover it: a tutorial story trip's chapter goal must be met by the tutorial trips before it. CONFIRMED (code path), future content only.

## Requirements

| Requirement | Built in | Proven by | Status |
| --- | --- | --- | --- |
| FR-001 | `lines_model.dart` | `lines_screen_test` redraw | met |
| FR-002, FR-003 | `core/progress/domain/playable.dart` | `playable_test`, sweep, `vehicle_tiles_test`, `vehicle_purchase_test` | met |
| FR-004, FR-005 | `unlocks.dart` (port) | `unlocks_test`, `line_standing_test` | met |
| FR-006, FR-007 | `playable.dart` | `playable_test`, `story_agreement_test`, `sample_sweep_test` | met |
| FR-008, FR-009 | `line_standing.dart` | `line_standing_test`, `trip_cells_test` | met (R1-30 open) |
| FR-010 | `focus_line.dart` | `focus_line_test` (now separates Home's line from the fallback) | met |
| FR-011 | `playable.dart` | never-more-permissive sweep | met |
| FR-012 | `next_trip.dart`, `pre_trip_card.dart`, `start_next_trip.dart`, `home_model.dart:140`, `first_session.dart:235` | `start_next_trip_test`, `next_trip_test` (T098 case), `first_session_test` | met (R2-6) |
| FR-013 | `core/progress/domain/playable.dart`, `trip_cells.dart` | `domain_imports_test`, `trip_cells_test` | met (R1-30 open) |
| FR-014 – FR-016 | `lines_screen.dart`, `vehicle_tiles.dart` | `lines_screen_test`, `shell_test`, `vehicle_tiles_test` | met |
| FR-017 | `vehicle_tiles.dart`, `vehicle_strip.dart` | `lines_screen_test` | partial (R1-16) |
| FR-018, FR-019 | `line_card.dart`, `line_map.dart` | `lines_screen_test`, `Lines` layout test | met |
| FR-020 | `line_map.dart`, `lines_screen.dart` | `lines_screen_test` T100 (tab and Home's card) | met, with R2-1 and R2-2 |
| FR-021 | `fare_chip.dart` | `lines_screen_test` | met |
| FR-022 | providers | `vehicle_sheet_test` rollback and flips, `lines_screen_test` | met |
| FR-023, FR-024 | `line_details_sheet.dart`, `trip_cells.dart`, `trip_grid.dart` | `line_details_sheet_test`, `trip_cells_test` | met |
| FR-025 (amended) | `trip_cells.dart:153-176` | `trip_cells_test` (story behind, extended line, all locked), 30-trip locked widget test | met (docs R2-4) |
| FR-026 (amended) | `trip_cells.dart`, `trip_grid.dart`, `start_next_trip.dart` | `trip_cells_test`, `line_details_sheet_test` inert cell, `start_next_trip_test` | met (R2-5) |
| FR-027, FR-028 | `line_details_sheet.dart` | `line_details_sheet_test` | met |
| FR-029 | sheet pages | `line_details_sheet_test` closing | met; the map jumps after it (R2-1) |
| FR-030, FR-032 | `vehicle_sheet.dart` and parts, `impact.dart` | `vehicle_sheet_test`, `impact_test` | met |
| FR-031 | `vehicle_preview.dart` (`Fit.contain`) | `rive_vehicle_preview_goldens_test`, BuyVehicle goldens | met |
| FR-033 | `vehicle_sheet.dart` | `vehicle_sheet_test` (disabled semantics, bar 0.8) | met |
| FR-034, FR-035 | `vehicle_sheet.dart`, `playable.dart` | `vehicle_sheet_test` | met (copy R1-16) |
| FR-036 – FR-040 | `vehicle_purchase.dart`, `vehicle_sheet.dart`, M06 rollback | `vehicle_purchase_test`, `vehicle_sheet_test` refusals and rollback group | met |
| FR-041 | `lines_news.dart`, `lines_seen.dart`, `lines_dot_watcher.dart` | `lines_dot_test` (dot on Home, recurrence) | met |
| FR-042 – FR-044 | schemas, models, examples, sample, bundle, `content.0010`, admin; release draft | content kit and backend tests; draft validated | met |
| FR-045 | three artboards plus nine undrawn states | design goldens and layout tests | met (R2-2) |
| FR-046 | `locked_fill.dart`, `AppCard(locked, lockInline)` | goldens | met (approval T088) |
| FR-047, FR-048 | wrapping, sizes | a11y tests on three phones, 1.0 and 1.3, nine states | partial (R2-3) |
| FR-049 | labels | `labelled(...)` checks, live regions | met (R2-5) |
| FR-050 | ARB plurals | goldens | partial (R1-17) |
| FR-051 | `Pressable` | — | met (R1-19) |
| FR-052 | research R14 | — | owner (T087) |
| FR-053, FR-054 | `routes.dart`, `router.dart`, `shell_scaffold.dart` | `route_table_test`, `navigation_test`, `shell_test` | met |
| SC-001 | «كمّل», cells | `lines_loop_test`, `line_details_sheet_test` | met |
| SC-002 | tile → sheet → buy | `lines_loop_test` | met |
| SC-003 | sweep; backend e2e | `playable_test`; `lines_purchase_sync_test` not run here | met in unit tests; e2e in CI |
| SC-003a | `tripPlayable` everywhere, first session included | `story_agreement_test`, `next_trip_test` | met (R1-30) |
| SC-004 | busy flag, held id | `vehicle_purchase_test` | met |
| SC-005 | layout tests | ±2 everywhere but the pill's listed ±5 | met (approval T088) |
| SC-006 | a11y tests | nine states | partial (R2-3) |
| SC-007 | labels, announcement, live regions | `vehicle_sheet_test` | met (R2-5) |
| SC-008 | no loading state | `lines_loop_test` stopwatch | owner (T094) |
| SC-009 | — | — | owner (T095) |
| US1 1–8 | as FR-014 – FR-022 | `lines_screen_test` | met (R2-1 after a sheet) |
| US2 1–7 | as FR-023 – FR-029 | `line_details_sheet_test`, `start_next_trip_test` | met |
| US3 1–8 | as FR-030 – FR-040 | `vehicle_sheet_test`, `vehicle_purchase_test` | met |
| US4 1–4 | locked routes and sheets | `lines_screen_test`, `vehicle_sheet_test` | met |
| US5 1–5 | `playable.dart` and callers | `story_agreement_test`, `trip_cells_test` | met |
| US6 1–3 | watcher, seen set | `lines_dot_test` | met (R1-24 open) |

## Task audit

Ticked 96 (round 1's 80, T010 and T096–T110): verified 93, partly done 2 (T099, T106), unverifiable
1 (T099's "ask the owner first": spec.md records "On 2026-10-29 the owner chose", with no other
artefact). Round 1's partly done T017, T034, T051, T059 and T069 are now complete through T096,
T107 and T108. Unticked 14 (T074–T079, T084, T087–T089, T092–T095): the owner's boards, approvals
and after-merge steps, genuinely not done.

| Task | Claim | Actual |
| --- | --- | --- |
| T099 | the owner's answer recorded in spec.md FR-025 and research.md, then the code | spec.md and the code done; research.md:119 and `contracts/line-details.md:39` still state `max(4, nextRow + 2)` (R2-4) |
| T106 | the extra states "and long line and vehicle names" at three phones and two scales | every state but the long names (R2-3) |
| T100 | scroll on every return to Lines | done as written, but a sheet's close counts as a return (R2-1) |
| T104 | goldens of the undrawn states | done; `LinesSmall` taken after a resize (R2-2) |
| T098 | the guard, then one of two content-side options | the guard done and tested; both content-side options declined, with research R2 explaining why (R2-7) |

## Outside this change

- The spec-kit and opencode setup (`.opencode/`, `.specify/` integration and the `review` extension, `tools/speckit-extensions/review/`, `AGENTS.md`, `CLAUDE.md`'s spec-kit lines) and the untracked `apps/mobile/AGENTS.md` and `apps/mobile/LEAN-CTX.md`, which lean-ctx wrote and which belong to no feature.
- No CI workflow runs `integration_test/` (as in round 1).
- The release draft lives untracked in the `wasal_ogra-core-r1` worktree (`content/drafts/` is `??` there), so T010's change exists only on this machine until that branch commits it.

## Not reviewed

- The `backend`-tagged sync tests: the dev DB's state doesn't match the seed's (Checks); CI's `sync-e2e` runs them.
- The solver's tests and bench and the two Dart packages: unchanged since round 1, which ran them green.
- The Android APK build, the backend image and smoke jobs, and iOS (Codemagic): nothing in the change touches Gradle, Docker, the edge or Xcode.
- On-device behaviour: TalkBack's reading of the new live regions and the inert cell, the scroll with more lines, SC-008's timing (T094).
- The side-by-side comparison against the design PNGs beyond reading the `Lines` golden: the owner's review (T092).
