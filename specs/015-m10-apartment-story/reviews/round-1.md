# Implementation review: 015-m10-apartment-story, round 1

- Date: 2026-10-30 · Reviewer: Claude Code (Sonnet 5.5), layer passes by Sonnet 5.5 subagents; every finding re-opened here
- Branch: 015-m10-apartment-story · Base: origin/master (merge base 90051b0) · Head: 90051b0, plus 253 uncommitted files (nothing committed yet)
- Change: 0 commits, 253 files, +19,810 −172 (about 8,100 of the added lines are generated drift schema code and goldens)
- Verdict: **CHANGES REQUESTED** · CRITICAL 0 · HIGH 3 · MEDIUM 4 · LOW 8

**State of the build.** 27 of 150 tasks are ticked (T001–T023, T032–T035). Phase 2 («Foundational») is
mostly built; the user stories (Phases 3–10), the owner's boards and polish are not started. This review
judges what exists. Missing screens are not findings. Requirements that depend on unbuilt tasks are marked
"not yet built" in the table below.

## Checks

| Check | Command | Result |
| --- | --- | --- |
| Content kit: codegen matches schemas | `uv run wassal-content codegen --check` (tools/content_kit) | exit 0, 33 files up to date |
| Sample validates | `uv run wassal-content validate-source ../../content/examples/sample` | exit 0, 0 errors |
| Sample golden | `uv run wassal-content golden` | exit 0, checksums match |
| Dev bundle matches | `uv run wassal-content bundle dev --check --out ../../apps/mobile/assets/content/dev` | exit 0 |
| Content kit lint | `uv run ruff check . && uv run ruff format --check .` | exit 0 |
| Content kit types | `uv run mypy .` | **exit 1**: `tests/test_rules.py:107` no-any-return (R1-2) |
| Content kit tests | `uv run pytest --cov --cov-fail-under=80` | exit 0, 615 passed, 96.6% |
| Solver parity | `uv run wassal-solver parity` (tools/solver) | exit 0, ok 62 (unchanged) |
| Release draft validates (T012) | `uv run wassal-content validate-source …/wasal_ogra-core-r1/content/drafts/core-r1/pack` | exit 0, 0 errors |
| Backend deps refreshed | `uv sync --reinstall-package wassal-content --reinstall-package wassal-solver` (backend) | exit 0 |
| Backend lint | `uv run ruff check . && uv run ruff format --check .` | exit 0 |
| Backend types | `uv run mypy .` | exit 0, 338 files |
| Missing migrations | `uv run manage.py makemigrations --check --dry-run` | exit 0, no changes |
| OpenAPI | `uv run manage.py spectacular … --validate --fail-on-warn`, diff against `contracts/openapi.yaml` | exit 0, identical |
| Backend tests | `uv run pytest -n 4 --cov --cov-fail-under=80` | 2015 passed, 1 failed (`test_contract.py::test_operation_conforms[POST /v1/auth/link]`), 606 s |
| That test alone | `uv run pytest tests/test_contract.py -k "auth/link"` | exit 0, passed. Not a finding: it passes alone, and this change doesn't touch auth. Treated as a load flake. |
| content_models | `fvm dart run build_runner build -d`, `dart analyze --fatal-infos`, `dart test --coverage` | exit 0, 63 passed |
| trip_engine | `fvm dart format --set-exit-if-changed`, `dart analyze --fatal-infos`, `dart test --coverage` | exit 0 |
| trip_engine coverage ≥ 90% | `format_coverage` + `check_coverage.dart --min 90` | exit 0 |
| Engine fixtures | `fvm dart run tool/fixtures.dart check` | exit 0 |
| App deps and codegen | `fvm flutter pub get`, `fvm dart run build_runner build -d` | exit 0 |
| App format | `fvm dart format --output=none --set-exit-if-changed $(git ls-files '*.dart')` | exit 0 |
| App analyze | `fvm flutter analyze --fatal-infos` | exit 0 |
| App tests and goldens | `fvm flutter test --coverage --exclude-tags backend` | 5,088 passed, 6 skipped, 1 failed (`quote_test.dart` "the longest trip replays within 150 ms") |
| That test alone | `fvm flutter test test/features/result/domain/quote_test.dart` | exit 0, 8 passed. A 150 ms budget under a loaded run, not this change. |
| App coverage ≥ 80% | `fvm dart run tool/check_coverage.dart --min 80` | exit 0, 90.75% |
| Ways around the checks | `git diff HEAD` scanned for `@Skip`, `skip:`, `xfail`, `# noqa`, `# type: ignore`, `// ignore`, `ignore_for_file`, `--exclude-tags`; analysis, ruff, mypy and coverage config and `.github/` | none added; no config or CI file changed |
| Property tests at 10,000 examples (economy) | `HYPOTHESIS_PROFILE=thorough uv run pytest apps/economy/tests/test_properties.py` | NOT RUN: the backend's economy is untouched (no backend change outside `apps/content`) |
| Phone sync against the dev stack (`sync-e2e`, `backend`-tagged) | | NOT RUN: the api and admin containers of the dev stack were restarting; this feature's `backend` case (SC-003, SC-004, SC-006) belongs to unbuilt tasks |
| Headless integration tests | `integration_test/*` | NOT RUN: this feature's loops are unbuilt (Phase 3 on) |

## Previous round

First round.

## Findings

### CRITICAL

None.

### HIGH

#### R1-1: Migration 0011's slot CHECK constraints fail on any database that already has items
- Layer: db · Source: constitution platform constraint (expand/contract, backend `CLAUDE.md` "Migrations are expand/contract"), T011 ("expand-only, every column with `db_default`") · `backend/apps/content/migrations/0011_m10_story_fields.py:199-215` and `:281-292` (model: `backend/apps/content/models/story.py:291-294`) · CONFIRMED
- Problem: `slot_x/y/w/h` are added with `db_default=0`, so every existing `Item` row gets `slot_w = 0` and `slot_h = 0`. The same migration then adds `content_item_slot_minimum` (`slot_w >= 24 AND slot_h >= 24`). Postgres checks a new CHECK constraint against the rows already there.
- Failure scenario: dev, staging or prod already has the sample or the release pack imported, so `Item` has rows. `manage.py migrate` aborts on `0011` with a check violation, and the deploy stops. The tests migrate an empty database, so nothing catches it.
- Fix direction: keep the migration expand-only. Either add the minimum-size constraint in a later migration after the rows are authored or backfilled, or write it so the not-yet-authored `0` passes (for example `slot_w = 0 OR slot_w >= 24`), and keep the build-time rule V-R3 in the kit. Add a migration test that migrates from `0010` with an `Item` row in place.

#### R1-2: `mypy` fails in the content kit
- Layer: tests/engine · Source: `tools/content_kit/CLAUDE.md` command table (CI's content-kit job runs `mypy .`), step 3 (a failing check) · `tools/content_kit/tests/test_rules.py:107` · CONFIRMED
- Problem: `_riders` returns `pack["chapters"][…]["story_trip_info"]["riders"]`, which is `Any`, from a function declared `-> list[dict[str, Any]]`: `no-any-return`.
- Failure scenario: the `content-kit` CI job goes red on `mypy .` (exit 1), so the PR can't merge.
- Fix direction: type the intermediate value (for example `riders: list[dict[str, Any]] = …; return riders`). Don't add an ignore.

#### R1-3: M10's «waiting scene» slot is live before anything records a scene, so Home shows it permanently, and the Home design goldens were rewritten to match
- Layer: mobile/ui · Source: T035 and research R3 (the backfill and `StoryService.recordSeen` are later tasks), `apps/mobile/CLAUDE.md` "Checking a screen against the design", FR-031 · `apps/mobile/lib/features/story/story_overrides.dart:14-21`, `apps/mobile/lib/bootstrap/bootstrap.dart:15`, `apps/mobile/test/helpers/pump_app.dart:83-84` · CONFIRMED
- Problem: `storyOverrides()` computes «a scene is waiting» from `economyViewProvider.scenesSeen` alone, and it is wired into the real app (`bootstrap.dart`) and into every `pumpWassalApp`. Nothing outside `lib/core/economy/` calls `recordScene`, and M07 records its opening in `first_session`, not in `scenesSeen`. The sample pack's opening scene is therefore always unseen.
- Failure scenario: a player who already saw the opening gets «مشهد جديد مستنيك» on the savings card instead of the gold progress bar, and it never clears. In the tests, every fixture that doesn't seed `scenesSeen` renders that text. `C-Home_*`, `HomeStates_*`, `dot_*`, `server_states_*` and the `all/home` goldens were regenerated with it. I opened `test/goldens/design/goldens/C-Home_western.png` beside `docs/design/png/C-Home.png`: the artboard draws the bar, the golden now draws the text. `c_home_layout_test` still passes because the boxes are within tolerance, so no check caught it.
- Fix direction: keep the override out of the real app until `StoryService.backfill` and `recordSeen` exist (or have the slot also count M07's `first_session` scenes). In the design samples and fixtures treat the opening as seen, so the Home goldens match the artboards again. Keep the waiting text in its own golden. Revert the Home goldens' unrelated changes.

### MEDIUM

#### R1-4: A second `destPreTrip` key in `app_ar.arb` silently changes two existing titles
- Layer: ui · Source: T033 (it asks for `destPreTrip`; the key already existed), `apps/mobile/CLAUDE.md` (every string in `app_ar.arb`) · `apps/mobile/lib/l10n/app_ar.arb:59` and `:103` · CONFIRMED
- Problem: HEAD already has `"destPreTrip": "كارت ما قبل المشوار"` (line 59, used by `RouteNames.preTrip` and `linePreTrip`, `routes.dart:165`, `:220`). The change adds a second `"destPreTrip": "قبل المشوار"` and its `@` entry at line 103.
- Failure scenario: a JSON decoder keeps the last duplicate, so Home's and Lines' pre-trip page titles change to the new wording with no one deciding it (the regenerated placeholder goldens show it). A stricter `gen_l10n` would fail `pub get` for everyone.
- Fix direction: delete the new pair and reuse the existing key, or give the apartment route its own key. Add a repo test that fails on duplicate ARB keys.

#### R1-5: The apartment pre-trip page is a bare `Scaffold` around a sheet-style card
- Layer: ui · Source: FR-060 (shared components, the design), T034 · `apps/mobile/lib/core/routing/router.dart:275-284` · PLAUSIBLE (from the code and the regenerated `apartmentPreTrip_western.png`; I did not measure it)
- Problem: `linePreTrip` (`router.dart:268`) builds `PreTripCard` the way Lines opens it. `apartmentPreTrip` wraps it in `Scaffold(body: SafeArea(…))` with no side insets, `SystemBars` or sheet surface.
- Failure scenario: the stop cards and the «اطلع» button run edge to edge, unlike every other pre-trip card.
- Fix direction: give it the same page treatment as `linePreTrip`, and pin it with a golden or layout check when its story builds the screen.

#### R1-6: The snapshot drops a chapter's story-trip fields when its title is empty
- Layer: api/db · Source: FR-056, FR-057, contracts/content-fields.md "B04" · `backend/apps/content/services/snapshot.py:208-221` · CONFIRMED
- Problem: `chapter_part` writes `story_trip_info` only `if chapter.story_title_ar_eg`. The admin lets an author save riders, a condition or a fail reason with no title. `Chapter.clean` and the DB constraint only check the reverse direction.
- Failure scenario: an author fills in the riders and the condition and forgets the title. The pack builds and publishes green and the riders are gone. Nobody is told.
- Fix direction: require the title whenever any story field or rider exists (in `clean`), and let the snapshot emit the invalid shape so the schema refuses it instead of dropping data. Test both.

#### R1-7: T034 is ticked but its «due scene first» test isn't there
- Layer: tests · Source: T034 ("the apartment's location, the fuel sheet on an empty tank, a due scene first") · `apps/mobile/test/features/home/application/start_next_trip_test.dart` · CONFIRMED
- Problem: the diff adds two tests, the location with the close and the empty-tank fuel sheet. Nothing covers a due scene taking the start. The empty-tank case runs before the `from` switch, so it doesn't exercise apartment-specific code either.
- Failure scenario: a change that stops a due scene from taking precedence on the apartment's start passes every test.
- Fix direction: add the test when a scene is due (it needs T088's service, or a seeded due scene through the slot), or move the unmet part into the story that builds it and say so in `tasks.md`.

### LOW

- **R1-8** `backend/apps/content/tests/test_story_fields.py`: no test re-imports a pack that changes, reorders or drops riders (the delete-and-recreate path), and no `IntegrityError` test covers the DB constraints (`content_rider_order_range`, the slot bounds, `content_chapter_goal_line_speaker`, `content_chapter_story_fields_need_trip`). Only the first import and `full_clean` are tested. CONFIRMED (reading).
- **R1-9** `backend/apps/content/migrations/0012_rider_permissions.py` is in no task, plan, research or contract (only a comment in `tests/conftest.py` mentions it). The code is correct (it grants `content_author` the rider permissions, as `0003` does for the others). Add it to T011 and the contract's B04 table so it isn't silent scope. CONFIRMED.
- **R1-10** `apps/mobile/lib/core/economy/domain/story_rules.dart` (`claimRequestStillValid`): the contract says a claim no longer eligible is dropped on a new base. The code only drops one already claimed, because the payload carries no item id. Harmless (the server refuses and M06 rolls back, no BONAT moves) but undocumented. `apps/mobile/test/core/economy/domain/story_rules_test.dart:233-249` asserts the lenient behaviour. Record the departure in the contract or `research.md`. CONFIRMED (subagent, from code and test).
- **R1-11** `story_rules_test.dart:209-219`: the «request names no style» branch of `claim_request` has no test. The server accepts it (`backend/apps/content/services/lookups.py:209-215` maps a missing variant to `""`). Add a request with no variant, or an item owned in another style. CONFIRMED (subagent).
- **R1-12** `packages/trip_engine/test/prng_export_test.dart:17-22`: T002 asks that `Xorshift32(0xDEADBEEF)` equal the value `src/prng.dart`'s own test pins. The test only asserts a range. CONFIRMED.
- **R1-13** `apps/mobile/test/core/art/panel_art_test.dart:49` doesn't pin `ch4_mother_looks` (T001 says to update the expectations pinning these files), and `ApartmentArt` (null for unknown slugs, asset paths exist) has no test. No route test covers `/story/album` and `/story/scene/:id` resolving before `/story/:chapterId`. CONFIRMED (subagent, by reading).
- **R1-14** `Loading_{western,arabicIndic}.png` were rewritten with no UI change (`BootScreen` is untouched; same byte size, a slight tone difference in the driver's face). Revert them unless deliberately regenerated. PLAUSIBLE.
- **R1-15** Small: `FamilyRequest.character`, `Scene.title_*` and `Item.comment_*` may be blank in the DB, so a missing required field fails only at build time (consider required admin fields); V-R3 has no exact-edge valid case (`x=334, w=24`), so `>` → `>=` would go unnoticed; `EconomyState.toJson` now always writes `scenes_seen`/`requests_claimed` (no stored text is compared, `fromJson` accepts old bases); `_storyAllowed` in `domain_imports_test.dart` has a redundant `content_source.dart` line; a comment at the end of `schema_v5_test.dart` overstates what the test checks; `state_snapshot_test.dart` uses `status` values the server doesn't (`'complete'`, `'locked'` vs `open|completed`); two lines in the schema JSON and `round_trip_test.dart` lost a newline (`dart format` would reflow the latter; the app's format check doesn't cover `content_models`).

## Requirements

Only what the built tasks cover is judged. «Not yet built» is the plan's order, not a defect.

| Requirement | Built in | Proven by | Status |
| --- | --- | --- | --- |
| FR-056 content fields, sample carries them (13 fields) | schemas, kit, generated models, sample, golden, dev bundle, B04 models/migration/importer/snapshot/admin | kit 615 tests, content_models 63, backend tests, `codegen --check`, `bundle --check` | Built; R1-1, R1-6 |
| FR-057 content validation (V-C6–V-C12, V-R3, V-R4) | `rules/references.py` | `test_rules.py` cases, invalid examples (each reports only its own error) | Built; R1-2 (types), R1-15 |
| FR-052 `story_progress` op, once per scene | `story_rules.dart`, `op.dart`, `economy.dart`, `economy_service.dart`, wire | `story_rules_test`, `idempotency_test`, `op_wire_test` | Built (phone side); sending from the viewer not yet built |
| FR-053 `claim_request` op with content version | same | same | Built; R1-10, R1-11 |
| FR-054 server state replaces seen scenes and claims | `_takeServerState`, `StateStory`, `stateFromSnapshot` | `state_snapshot_test`, `confirmed_view_test` | Built |
| FR-055 refusal rolls back through M06 | existing M06 path, ops registered in `contentVersionTypes` | `op_wire_test` | Built (no new test of the rollback itself) |
| FR-024, SC-003 phone never adds BONAT; pending rewards | `ConfirmedState`, `EconomyView.confirmed`; `rewards.dart`, `pending_rewards_provider.dart` exist but are unticked | `confirmed_view_test`, `rewards_test` | Built (T029 not ticked) |
| FR-050 / SC-004 server rules first | `story_rules.dart` against `backend/apps/economy/services/ops/story.py` | `story_rules_test`; matches line by line except R1-10 | Built (the purchases themselves not yet built) |
| FR-031 «مشهد جديد مستنيك» on Home | `story_overrides.dart` | `story_overrides_test` | Built wrongly for the app: R1-3 |
| FR-051 derived unlocks and completions | `story.dart`, `requests.dart`, `rewards.dart` | `story_test`, `requests_test`, `rewards_test` | Built, unticked |
| Schema 5 (drift) | `app_database.dart` `_toV5`, `tables.dart`, `drift_schema_v5.json`, generated steps | `schema_v5_test`, `test/drift`, schema tests | Built |
| Routes `/story/scene/:sceneId`, `/story/album`, `/apartment/pre-trip/:tripId` | `routes.dart`, `router.dart` | `route_table_test`, all-destination goldens | Built; R1-4, R1-5, R1-13 |
| `StartFrom.apartment` | `start_next_trip.dart` | `start_next_trip_test` | Partly: R1-7 |
| FR-001–FR-023, FR-025–FR-030, FR-032–FR-049, FR-058–FR-061, SC-001, SC-002, SC-005–SC-010 | not yet built (Phases 3–12) | | Not yet built |

## Task audit

Ticked 27, verified 24, partly done 3. Unticked tasks with finished work: 7.

| Task | Mismatch |
| --- | --- |
| T033 (ticked) | `ParamValidators.sceneId` and `sampleParams['sceneId']` already existed (M07). The new `destPreTrip` key duplicates an existing one (R1-4). |
| T034 (ticked) | The «due scene first» test is missing (R1-7). |
| T035 (ticked) | Wired into the app and the test harness before its backfill exists (R1-3). It also depends on T027, which is not ticked, though `story.dart` exists. |
| T002 (ticked) | The `0xDEADBEEF` value is not pinned (R1-12). |
| T024–T029 (unticked) | Done: `story.dart`, `requests.dart`, `rewards.dart`, `pending_rewards_provider.dart` and their three test files exist, and the suite passes. Tick them. |
| T030 (unticked) | Partly done: `_storyAllowed` exists in `domain_imports_test.dart` but isn't yet used by `_domains`. |
| T031 (unticked) | Not done: `test/helpers/synthetic_packs.dart` is unchanged, with no `artboardSalon()` or `storyShaped()`. |
| T012 (ticked) | Verified in the `content-core-r1` worktree: the draft carries the fields and `validate-source` reports 0 errors. |

## Outside this change

- `Loading_*.png` goldens rewritten with no UI change (R1-14; listed there because the change set touched them).
- The dev stack's `api` and `admin` containers were restarting at review time (likely the old image after the schema change). `backend/CLAUDE.md` says to rebuild it. Not touched.
- No `CLAUDE.md` guide, `AGENTS.md` or `docs/owner-actions.md` "Open now" rows were updated beyond the planning section; the plan assigns that to the last phase, so it isn't a finding yet.

## Not reviewed

- Everything in Phases 3–12 (the apartment, story, trip-rider screens, goldens and design checks for the nine artboards, the integration tests, the `backend`-tagged sync case, SC-007–SC-010). It isn't built.
- Property tests at 10,000 examples and the `sync-e2e` run (see Checks). `tools/solver` parity ran; the solver's own pytest suite did not.
- `unlocks.dart` (M08's port) and the generated `*.g.dart` and `test/drift/app/generated/` files beyond their presence.
- The goldens' pixel contents beyond the ones named above. The 78 modified goldens were compared by eye, not by pixel diff (the image-compare tool is off the shell allowlist).
- iOS, Rive contract checks and `integration_test/*`.
