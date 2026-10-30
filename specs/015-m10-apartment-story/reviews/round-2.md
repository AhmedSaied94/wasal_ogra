# Implementation review: 015-m10-apartment-story, round 2

- Date: 2026-10-30 · Reviewer: Claude Code (Sonnet 5.5); every round-1 fix re-opened and re-run here
- Branch: 015-m10-apartment-story · Base: origin/master (merge base 90051b0) · Head: 90051b0, plus 211 uncommitted files (nothing committed yet)
- Change: 0 commits, 211 files, +20,315 −173 (about 8,000 added lines are generated drift schema code and goldens)
- Verdict: **APPROVE WITH NOTES** · CRITICAL 0 · HIGH 0 · MEDIUM 1 · LOW 9

**State of the build.** 33 of 156 tasks are ticked: T001–T023, T032–T035 and the six review fixes T151–T156.
Phases 3–12 (the screens, the integration tests, the owner's boards) are still unbuilt, as in round 1. This review
judges what exists; its verdict is about the built part, not the feature.

## Checks

| Check | Command | Result |
| --- | --- | --- |
| Content kit: codegen matches schemas | `uv run wassal-content codegen --check` (tools/content_kit) | exit 0 |
| Sample validates / golden / dev bundle | `validate-source ../../content/examples/sample`, `golden`, `bundle dev --check --out ../../apps/mobile/assets/content/dev` | exit 0 each (0 errors; checksums match; bundle matches) |
| Content kit lint | `uv run ruff check . && uv run ruff format --check .` | exit 0 |
| Content kit types | `uv run mypy .` | exit 0 (was exit 1, R1-2) |
| Content kit tests | `uv run pytest --cov --cov-fail-under=80` | exit 0, 615 passed, 96.62% |
| Backend deps refreshed | `uv sync --reinstall-package wassal-content --reinstall-package wassal-solver` | exit 0 |
| Backend lint and types | `uv run ruff check . && uv run ruff format --check .`, `uv run mypy .` | exit 0; 340 files formatted, 339 source files clean |
| Missing migrations | `uv run manage.py makemigrations --check --dry-run` | exit 0, no changes |
| OpenAPI | `uv run manage.py spectacular --file <scratch> --validate --fail-on-warn`, `diff` against `contracts/openapi.yaml` | exit 0, identical |
| Backend tests | `uv run pytest -n 4 --cov --cov-fail-under=80` | exit 0, 2019 passed, 95.60%, 917 s (round 1's `auth/link` flake did not recur) |
| New backend tests alone | `uv run pytest apps/content/tests/test_migrations.py apps/content/tests/test_story_fields.py` | exit 0, 22 passed |
| App deps, codegen, format, analyze | `fvm flutter pub get`, `build_runner build -d`, `dart format --output=none --set-exit-if-changed $(git ls-files '*.dart')`, `fvm flutter analyze --fatal-infos` | exit 0 each; "No issues found" |
| App tests and goldens | `fvm flutter test --coverage --exclude-tags backend` | 5,094 passed, 6 skipped, 1 failed: `quote_test.dart` "the longest trip replays within 150 ms" |
| That test alone, with the four tests of this round's fixes | `fvm flutter test quote_test.dart story_overrides_test.dart arb_keys_test.dart start_next_trip_test.dart` | exit 0, 24 passed. The same 150 ms budget under load as in round 1, not this change. |
| App coverage ≥ 80% | `fvm dart run tool/check_coverage.dart --min 80` | exit 0, 90.74% |
| Ways around the checks | `git diff HEAD -U0` scanned for `@Skip`, `skip:`, `xfail`, `# noqa`, `# type: ignore`, `// ignore`, `ignore_for_file`, `--exclude-tags`; the lint, mypy and coverage config and `.github/` | none added; no config or CI file changed |
| Home design goldens | read `test/goldens/design/goldens/C-Home_western.png` beside `docs/design/png/C-Home.png`; `git status` on `*.png` | the golden draws the savings bar again. 28 modified goldens remain (round 1: 78); the Home, HomeStates, `dot_*` and `server_states_*` goldens are back to HEAD |
| content_models, trip_engine, solver parity, engine fixtures | | not re-run: no file in `packages/`, `tools/solver/` or `fixtures/` changed since round 1 (find `-newer round-1.md`), and all passed then |
| Property tests at 10,000 examples (economy) | `HYPOTHESIS_PROFILE=thorough …/economy/tests/test_properties.py` | NOT RUN: the backend's economy is untouched (no backend change outside `apps/content`) |
| Phone sync against the dev stack (`sync-e2e`, `backend`-tagged) | | NOT RUN: the dev stack's `api` and `admin` containers are still restarting (old image after the schema change), and this feature's `backend` case belongs to unbuilt tasks |
| Headless integration tests | `integration_test/*` | NOT RUN: this feature's loops are unbuilt (Phase 3 on) |

## Previous round

| Finding | Now |
| --- | --- |
| R1-1 migration 0011's slot CHECK fails on populated `Item` | **Fixed.** `0011` and `Item.Meta` now allow `0` or `>= 24` (`migrations/0011_m10_story_fields.py:285-286`, `models/story.py:313-314`). `tests/test_migrations.py` migrates from `0010` with an `Item` row, asserts the row survives with `(0,0,0,0)`, and asserts a too-small slot is still refused. |
| R1-2 kit `mypy` fails | **Fixed.** `mypy .` exits 0. |
| R1-3 waiting-scene slot on Home | **Fixed.** `seenScenesOf` (`features/story/story_overrides.dart`) now counts M07's `first_session` record of the opening and the scenes it played, so the sample's opening doesn't read as waiting. The samples seed `scenesSeen`; the Home goldens are back to HEAD and match the artboard; `story_overrides_test.dart` pins nothing-waiting, the M07-only opening and a waiting scene, and the new `home_waiting` golden holds the text. |
| R1-4 duplicate `destPreTrip` | **Fixed.** One key (`app_ar.arb:59`); `routes.dart:165,220,274` reuse it. `test/repo/arb_keys_test.dart` fails on a repeated top-level key and has its own check of the scan. |
| R1-5 apartment pre-trip is a bare `Scaffold` | **Still open, now CONFIRMED** (R2-1 below). |
| R1-6 snapshot drops story fields without a title | **Fixed.** `Chapter.clean` requires the title when a condition, a fail reason or a rider exists (`models/story.py:124-132`), and `snapshot.py:206-221` emits the half-written shape so the schema refuses it. `test_story_fields.py` has a test for each direction. |
| R1-7 no «due scene first» test | **Fixed.** `start_next_trip_test.dart:198-223` seeds M07's due scene and asserts `/onboarding/scene/the_stand?then=/trip/line_gamaa.12`. The empty-tank case still runs before the `from` switch (its comment now says so). |
| R1-8 B04 re-import and `IntegrityError` tests | Still open (LOW). |
| R1-9 migration `0012` in no task or contract | Still open (LOW). |
| R1-10 `claimRequestStillValid` leniency undocumented | Still open (LOW). |
| R1-11 no-variant `claim_request` untested | Still open (LOW). |
| R1-12 `0xDEADBEEF` not pinned | Still open (LOW). |
| R1-13 `ch4_mother_looks`, `ApartmentArt` and route-order tests | Still open (LOW). |
| R1-14 `Loading_*` goldens rewritten | Still open (LOW): both files still differ from HEAD. |
| R1-15 small nits | Still open (LOW). |

## Findings

### CRITICAL

None.

### HIGH

None.

### MEDIUM

#### R2-1: The apartment pre-trip page is a bare `Scaffold`, so the card runs edge to edge (carried from R1-5)
- Layer: ui · Source: FR-060 (shared components, the design), T034 and `contracts/apartment.md` ("M09's `linePreTrip` pattern") · `apps/mobile/lib/core/routing/router.dart:275-284` · CONFIRMED
- Problem: `linePreTrip` builds `PreTripCard` directly and the router gives it the sheet treatment. `apartmentPreTrip` wraps it in `Scaffold(body: SafeArea(…))`. I opened `test/goldens/goldens/all/apartmentPreTrip_western.png` beside `linePreTrip_western.png`: the apartment's card has no sheet surface and no side insets. The stop cards, the stars and the «اطلع» button touch both screen edges, and the star hints («لسه») sit at x = 0.
- Failure scenario: the player taps the shabka's CTA or «اطلع» on the apartment and gets a card that looks unlike every other pre-trip card, with text against the screen edge. The golden pins the wrong look, so no test fails.
- Fix direction: build `PreTripCard` the way `linePreTrip` does (no `Scaffold` wrapper), keeping `leaveTo` and `closeTo: '/apartment'`, and check the golden against `linePreTrip`'s layout. Pin it with a layout assertion that the card's content has the sheet's side inset.

### LOW

- **R1-8 to R1-15**: still open, unchanged (see "Previous round"; the text of each is in `round-1.md`). R1-14 is the one a reviewer can check at once: `git status` still lists `Loading_{western,arabicIndic}.png` as modified, with no UI change behind them.
- **R2-2** `backend/apps/content/models/story.py:128`: `riders = self.pk is not None and self.riders.exists()`. On a new chapter the admin saves its riders inline after `clean()`, so a new chapter with riders and no title passes `clean`. The snapshot now refuses the shape at build time (R1-6's second layer), so nothing is lost silently. Only the early error is missing. PLAUSIBLE (by reading, no run).

## Requirements

Only what the built tasks cover is judged. «Not yet built» is the plan's order, not a defect.

| Requirement | Built in | Proven by | Status |
| --- | --- | --- | --- |
| FR-056 content fields, sample carries them | schemas, kit, generated models, sample, golden, dev bundle, B04 models/migration/importer/snapshot/admin | kit 615 tests, content_models 63, backend 2019, `codegen --check`, `bundle --check`, `test_migrations.py` | Built (R1-1 and R1-6 fixed) |
| FR-057 content validation (V-C6–V-C12, V-R3, V-R4) | `rules/references.py` | `test_rules.py`, invalid examples, `mypy` clean | Built |
| FR-052 `story_progress` op, once per scene | `story_rules.dart`, `op.dart`, `economy.dart`, `economy_service.dart`, wire | `story_rules_test`, `idempotency_test`, `op_wire_test` | Built (phone side) |
| FR-053 `claim_request` op with content version | same | same | Built; R1-10, R1-11 (LOW) |
| FR-054 server state replaces seen scenes and claims | `_takeServerState`, `StateStory`, `stateFromSnapshot` | `state_snapshot_test`, `confirmed_view_test` | Built |
| FR-055 refusal rolls back through M06 | existing M06 path, ops in `contentVersionTypes` | `op_wire_test` | Built |
| FR-024, SC-003 phone never adds BONAT; pending rewards | `ConfirmedState`, `EconomyView.confirmed`; `rewards.dart`, `pending_rewards_provider.dart` (T029 unticked) | `confirmed_view_test`, `rewards_test` | Built |
| FR-050 / SC-004 server rules first | `story_rules.dart` against `backend/apps/economy/services/ops/story.py` | `story_rules_test` | Built |
| FR-031 «مشهد جديد مستنيك» on Home | `story_overrides.dart` | `story_overrides_test`, `home_waiting` golden | Built (R1-3 fixed) |
| FR-051 derived unlocks and completions | `story.dart`, `requests.dart`, `rewards.dart` | `story_test`, `requests_test`, `rewards_test` | Built, unticked |
| Schema 5 (drift) | `app_database.dart` `_toV5`, `tables.dart`, `drift_schema_v5.json`, generated steps | `schema_v5_test`, `test/drift`, schema tests | Built |
| Routes `/story/scene/:sceneId`, `/story/album`, `/apartment/pre-trip/:tripId` | `routes.dart`, `router.dart` | `route_table_test`, all-destination goldens, `arb_keys_test` | Built; R2-1, R1-13 |
| `StartFrom.apartment` | `start_next_trip.dart` | `start_next_trip_test` (the location, the close, the dry tank, the due scene) | Built (R1-7 fixed) |
| FR-001–FR-023, FR-025–FR-030, FR-032–FR-049, FR-058–FR-061, SC-001, SC-002, SC-005–SC-010 | not yet built (Phases 3–12) | | Not yet built |

## Task audit

Ticked 33, verified 33 (T151–T156 re-checked this round), not done 0. Unticked tasks with finished work: 6.

| Task | Mismatch |
| --- | --- |
| T024–T029 (unticked) | Still unticked, though `story.dart`, `requests.dart`, `rewards.dart`, `pending_rewards_provider.dart` and their three test files exist and pass. Tick them. |
| T030 (unticked) | Partly done: `_storyAllowed` exists in `domain_imports_test.dart` but isn't used by `_domains`. |
| T031 (unticked) | Not done: `test/helpers/synthetic_packs.dart` has no `artboardSalon()` or `storyShaped()`. |
| T033 (ticked) | Its `destPreTrip` duplicate is gone. `ParamValidators.sceneId` already existed (M07). |
| T034 (ticked) | Its «due scene first» test exists now. The apartment page's look is R2-1. |
| T002 (ticked) | The `0xDEADBEEF` value is still not pinned (R1-12, LOW). |

## Outside this change

- `Loading_*.png` goldens still rewritten with no UI change (R1-14; listed there because the change set touches them).
- The dev stack's `api` and `admin` containers are still restarting, likely the old image after the schema change. `backend/CLAUDE.md` says to rebuild it (`uv sync --reinstall-package …`, then `docker compose … build` and `up -d --wait`). Not touched.
- `quote_test.dart`'s 150 ms replay budget fails under a loaded full run (round 1 and round 2) and passes alone. It predates this change.
- No `CLAUDE.md` guide, `AGENTS.md` or `docs/owner-actions.md` "Open now" rows were updated beyond the planning section; the plan assigns that to the last phase, so it isn't a finding yet.

## Not reviewed

- Everything in Phases 3–12 (the apartment, story and trip-rider screens, goldens and design checks for the nine artboards, the integration tests, the `backend`-tagged sync case, SC-007–SC-010). It isn't built.
- Property tests at 10,000 examples and the `sync-e2e` run (see Checks). The solver's own pytest suite, `content_models`, `trip_engine` and the fixtures check were not re-run this round (no change since round 1).
- The goldens' pixel contents beyond the Home ones, `apartmentPreTrip` and `linePreTrip` named above. Not compared by pixel diff (the image-compare tool is off the shell allowlist).
- iOS, Rive contract checks and `integration_test/*`.
