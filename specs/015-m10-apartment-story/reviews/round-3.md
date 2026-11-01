# Implementation review: 015-m10-apartment-story, round 3

- Date: 2026-11-01 · Reviewer: Claude Code (Sonnet 5.5) with six layer subagents (Sonnet); every finding re-opened here
- Branch: 015-m10-apartment-story · Base: origin/master (merge base 90051b0) · Head: 6931dcf, plus 8 uncommitted files (the review extension's own reinstall; outside this change)
- Change: 8 commits, 517 files, +42,470 −537 (generated drift code, goldens and the owner's design boards are most of it)
- Verdict: **CHANGES REQUESTED** · CRITICAL 0 · HIGH 2

**State of the build.** 148 of 157 tasks are ticked. The nine open ones are T098 (needs a fresh dev stack) and the
owner tasks T141–T143 and T146–T150. All phases 3–12 are now built. This round reviews the whole feature, from the
spec's eight user stories down to the tests. This round runs under the new rule that only CRITICAL and HIGH
findings are reported, so the LOW items of rounds 1 and 2 are not re-checked.

## Checks

| Check | Command | Result |
| --- | --- | --- |
| Content kit: codegen | `uv run wassal-content codegen --check` (tools/content_kit) | exit 0, 33 files up to date |
| Sample, dev bundle | `validate-source ../../content/examples/sample`, `bundle dev --check --out ../../apps/mobile/assets/content/dev` | exit 0 each (0 errors, 0 warnings; bundle matches a fresh build) |
| Kit lint and types | `uv run ruff check . && uv run ruff format --check .`; `uv run mypy .` | exit 0; exit 0 (46 files) |
| Kit tests | `uv run pytest --cov --cov-fail-under=80` | exit 0, 615 passed, 96.62% |
| Backend deps refreshed | `uv sync --reinstall-package wassal-content --reinstall-package wassal-solver` | exit 0 |
| Backend lint and types | `uv run ruff check . && uv run ruff format --check .`; `uv run mypy .` | exit 0 (340 files formatted); exit 0 (339 files) |
| Missing migrations | `uv run manage.py makemigrations --check --dry-run` | exit 0, no changes |
| OpenAPI | `spectacular --file <scratch> --validate --fail-on-warn`, `diff` against `contracts/openapi.yaml` | exit 0, identical |
| Backend tests | `uv run pytest -n 4 --cov --cov-fail-under=80` | exit 0, 2020 passed, 95.62%, 478 s |
| App deps, codegen, format | `fvm flutter pub get`, `fvm dart run build_runner build -d`, `fvm dart format --output=none --set-exit-if-changed $(git ls-files '*.dart')` | exit 0 each; 864 files, 0 changed |
| App analyze | `fvm flutter analyze --fatal-infos` | **exit 1**, one info: `last_finished_trip.dart:13` `avoid_public_notifier_properties`. The file and its callers are unchanged since M08 (`git diff 90051b0..HEAD` is empty for them), so it is listed under "Outside this change" |
| App tests and goldens | `RTEST_HOST=flutter-tests rtest --exclude-tags backend` (apps/mobile, on the test box) | exit 0, 5470 passed, 7 skipped, 0 failed (the 150 ms `quote_test` passed this time) |
| trip_engine | `RTEST_HOST=flutter-tests rtest` (packages/trip_engine) | exit 0, 1134 passed |
| content_models | `RTEST_HOST=flutter-tests rtest` (packages/content_models) | exit 0, 63 passed |
| Ways around the checks | `git diff 90051b0..HEAD -U0` scanned for `@Skip`, `skip:`, `xfail`, `# noqa`, `# type: ignore`, `// ignore`, `ignore_for_file`, `--exclude-tags`, config and `.github/` changes | none added except the drift generator's own `ignore_for_file` header and `story_run_test.dart`'s documented `skip:` (no `STORY_RUN_PACK`, owner action 7); no config or CI file changed |
| App coverage ≥ 80% | `fvm dart run tool/check_coverage.dart --min 80` | NOT RUN: it needs a local `flutter test --coverage`, which the project's rule sends to the test box only |
| Solver pytest, parity replay, fixtures check | | NOT RUN: nothing under `tools/solver/` or `fixtures/` changed; the engine's one change is an export |
| Property tests at 10,000 examples (economy) | `HYPOTHESIS_PROFILE=thorough …/economy/tests/test_properties.py` | NOT RUN: the only economy change is a payload bound (`grants.py`) |
| Phone sync against the dev stack (`story_sync_test`, T098) | | NOT RUN: the dev database has no pack at version 1, so all 15 ops were refused (disclosed in `tasks.md`, owner action 6; CI's `sync-e2e` on a fresh stack runs it) |
| Headless integration tests | `integration_test/*` | NOT RUN: the `flutter-tester` device runs from the app package and the project's rule keeps Flutter tests on the box; the test box run above covers `test/` only |

## Previous round

| Finding | Now |
| --- | --- |
| R2-1 apartment pre-trip page is a bare `Scaffold` | **Fixed.** `router.dart:370` builds `PreTripCard` with no `Scaffold`; the apartment branch gives it the sheet treatment (T157, goldens regenerated, `pre_trip_card_test`) |
| R2-2 and R1-8 to R1-15 (LOW) | Not re-checked: below this round's bar. `Loading_{western,arabicIndic}.png` are still modified with no UI change behind them (the tests-and-ops reviewer confirmed it) |

## Findings

### CRITICAL

None.

### HIGH

#### R3-1: A room tab changes only its own highlight; the room, the grid and the strip never change
- Layer: ui, spec · Source: FR-010, FR-015 (US2, P1), T054 and T062 (ticked) · `apps/mobile/lib/features/apartment/presentation/rooms_view.dart:379,411-413`, `apps/mobile/lib/features/apartment/domain/room_model.dart:150` · CONFIRMED
- Problem: `roomTabIdProvider` is read in exactly two places, both in `_TabsRow`: the highlight (`:379`) and the tap that writes it (`:412`). The model is built from the current chapter's room (`_roomOf(c, chapter)`, `room_model.dart:150`) and never reads it. There is no crossfade either: the only `FadeTransition` under `features/apartment/presentation` is in the requests sheet. T054 lists «the crossfade on a tab switch» and is ticked, but no test taps a second tab (`grep roomTabId` in `test/` finds only `room_model_test.dart:50`, which checks the tab is a `SelectableTab`).
- Failure scenario: a pack with a kitchen chapter current. The salon tab is selectable because its chapter has started. The player taps «الصالة»: the highlight moves to it and the screen still shows the kitchen. The provider is `keepAlive` and never reset, so when the story moves on to the bedroom the salon tab stays highlighted over the bedroom. A tab looks selected for a room that is not shown. Latent with the sample (one room), live with the planned three rooms (`synthetic_packs.dart:617` already has a kitchen).
- Fix direction: build the displayed `RoomModel` from the selected room (`roomTabIdProvider` falling back to the current chapter's), reset the selection when the current chapter changes, crossfade `RoomScene` in at most 150 ms (a fade only under reduced motion), and add the widget test T054 names: tap a second selectable tab, assert the scene, grid and chapter bar change.

#### R3-2: A due scene that becomes locked or missing sends every trip start round in a redirect loop
- Layer: mobile · Source: FR-030, FR-055, FR-051 (unlocks are derived, never stored) · `apps/mobile/lib/features/onboarding/domain/first_session.dart:193-198`, `apps/mobile/lib/core/routing/router.dart:208-216,288-308`, `apps/mobile/lib/features/story/application/story_due_watcher.dart:35-50` · CONFIRMED by reading (the redirect limit itself was not run)
- Problem: `dueScene` returns any id in `scenesDue` that is not in `scenesSeen`; it never checks that the scene exists in the pack or is unlocked. Nothing removes an id from `scenesDue` except seeing the scene (`grep scenesDue` in `lib/`: only `addSceneDue` and the store's add). Before M10 every due id was an after-trip scene, which is unlocked by definition. `StoryDueWatcher.onView` now adds goal scenes, whose unlock is derived from progress and can revert. A locked or unknown scene is redirected by `_storyRedirect` (`router.dart:306-307`) to its `then`.
- Failure scenario: the player buys the microbus while offline. The projection completes the chapter, `onView` adds `father_visit` to `scenesDue`. The server refuses the purchase and M06 rolls it back (FR-055), so the chapter is no longer complete and the scene is locked. Starting any trip goes to `/trip/X`, the `/trip` redirect (`router.dart:208`) sends it to `/story/scene/father_visit?then=/trip/X`, `_storyRedirect` finds nothing to play and returns `/trip/X`, and the `/trip` redirect sends it to the scene again. The loop runs until go_router's redirect limit, so no trip can start until the chapter is completed again. A restore that replaces the base, or a pack update that drops the scene, does the same. At Home's arrival, `DueSceneArrival.open` pushes the viewer, which redirects away; the path `/story/scene/S` never shows, so `untilLeft` never completes and the arrival queue (the name sheet, later items) stops.
- Fix direction: have `dueScene` and the Home arrival ignore ids whose scene is not currently `waiting` in the active pack (give `firstSessionProvider` a predicate built from the content and the derived progress), or have the watcher drop a due id when its chapter stops being complete. Add a test with a due id whose scene is locked and one whose id is absent from the pack: both give no due scene, a trip starts, and Home's arrival queue continues.

### MEDIUM and LOW

Not reported in this round (the review keeps to CRITICAL and HIGH).

## Requirements

| Requirement | Built in | Proven by | Status |
| --- | --- | --- | --- |
| FR-056, FR-057 content fields and validation | schemas, kit rules, generated models, sample, importer, snapshot, admin, migrations 0011 and 0012 | kit 615, backend 2020, `test_migrations.py`, `test_story_fields.py`, codegen and bundle checks | Built |
| FR-050 to FR-055, FR-024, SC-003, SC-004 (rules, ops, state, rollback) | `story_rules.dart`, `op_wire.dart`, `state_snapshot.dart`, `rewards.dart`, drift schema 5 | `story_rules_test`, `confirmed_view_test`, `schema_v5_test`, `op_wire_test`; the real-server half of SC-004 awaits T098 on a fresh stack | Built; end-to-end proof owner/CI |
| FR-005 to FR-009, FR-011 to FR-014, FR-017 to FR-027 (US1 to US3: goal, rooms, pieces, finished room) | `features/apartment/**`, `savings_target.dart`, `savings_card.dart` | `goal_view_test`, `goal_purchase_test`, `rooms_view_test`, `piece_sheet_test`, `room_done_dialog_test`, golden and minimum-size tests | Built |
| FR-010 (switch rooms), FR-015 (crossfade) | `rooms_view.dart` (highlight only) | no test | **Not met: R3-1** |
| FR-029 to FR-036 (US4: scenes at their moments, viewer, share) | `features/story/**`, `scene_page.dart`, `story_overrides.dart` | `story_after_result_test`, `story_due_watcher_test`, `scene_viewer_page_test`, `scene_share_test` | Built; R3-2 for a due scene that locks |
| FR-052, FR-054 (US5: backfill and restore) | `StoryService.backfill`, `seenScenesOf` | `story_service_test`, `restore_test`; `story_sync_test` (T098) not yet run on a clean stack | Built |
| FR-037 to FR-039 (US6: timeline and album) | `chapter_rows.dart`, `album.dart`, `album_page.dart`, `chapters_page.dart` | `album_test`, `album_page_test`, `chapter_rows_test` | Built |
| FR-040 to FR-045 (US7: family requests) | `request_claim.dart`, `requests_sheet.dart` | `request_claim_test`, `requests_sheet_test` | Built |
| FR-046 to FR-049 (US8: riders) | `rider_comments.dart`, `rider_component.dart`, `trip_controller.dart`, the engine's `Xorshift32` export | `rider_comments_test`, `story_trip_presentation_test`, `story_trip_test.dart` | Built |
| FR-058 to FR-061, SC-001, SC-002, SC-005 to SC-009 | the above, goldens, design layout tests, `apartment_loop_test.dart` | the app suite and goldens pass; the integration tests and SC-010 were not run | Built; owner checks pending |

## Task audit

Ticked 148, verified about 90 by file and content (the tests-and-ops reviewer sampled T001–T157 across all phases and a stub scan found nothing), not done 2, partly done 0.

| Task | Mismatch |
| --- | --- |
| T054 (ticked) | Lists «the crossfade on a tab switch»; no test and no crossfade exist (R3-1) |
| T062 (ticked) | The tabs do not switch the room (R3-1) |
| T098 (unticked) | Written, not yet green: needs a clean dev stack; documented in `tasks.md` and owner action 6 |

## Outside this change

- `lib/features/home/application/last_finished_trip.dart:13` fails `analyze --fatal-infos` (`avoid_public_notifier_properties`). Unchanged since M08, and round 2's analyze run was clean with the same lockfile, so I could not tell why it fires now (a different local lint version is possible). The area guide's analyze command uses `--fatal-infos`: check it against CI's result before the PR.
- `Loading_{western,arabicIndic}.png` goldens still differ from HEAD with no UI change behind them (R1-14).

## Not reviewed

- Pixel contents of the goldens beyond the explanation of which commit changed each group; the image-compare tool is off the shell allowlist.
- Checks marked `NOT RUN` above: the coverage gate, the headless integration tests, the 10,000-example property tests, the solver and parity replay, and T098.
- iOS, the Rive contract checks and the owner's tasks (T141–T143, T146–T150).
- Everything below HIGH, by this round's rule.
