# Quickstart: Trip Engine (M01)

How to build, test and check this feature by hand. The rules are in
[contracts/rules.md](./contracts/rules.md), the API in
[contracts/engine-api.md](./contracts/engine-api.md), and the fixture formats in
[contracts/replay-and-fixtures.md](./contracts/replay-and-fixtures.md).

## Prerequisites

- FVM with the repo's pinned Flutter (`.fvmrc`, 3.47.7). Every Dart command below runs through `fvm`.
- `uv`, for `tools/content_kit` and the backend.
- For the backend checks, the local stack: `docker compose -f docker/compose.yml -f
  docker/compose.dev.yml up -d --wait` in `backend/`.

## Set up

```bash
# The generated content models (their parts are gitignored)
cd packages/content_models && fvm dart pub get && fvm dart run build_runner build -d

# The engine
cd ../trip_engine && fvm dart pub get
```

## Run the engine's checks (what CI runs)

In `packages/trip_engine`:

```bash
fvm dart format --output=none --set-exit-if-changed $(git ls-files '*.dart')
fvm dart analyze --fatal-infos
fvm dart test --coverage=coverage
fvm dart run coverage:format_coverage --lcov --report-on=lib --in=coverage --out=coverage/lcov.info
fvm dart run ../../apps/mobile/tool/check_coverage.dart --min 90 --lcov coverage/lcov.info
```

Expected: everything passes, and coverage is ≥ 90%. Run only the fixtures with
`fvm dart test test/fixtures`, or only the perf budget with `fvm dart test test/perf`.

## Work with fixtures

```bash
fvm dart run tool/fixtures.dart check                                  # all fixtures, exit 1 on a difference
fvm dart run tool/fixtures.dart show ../../fixtures/parity/archetype__sleeper_missed_stop.json
fvm dart run tool/fixtures.dart update ../../fixtures/parity/<new>.json # fill expected_result, then review the diff
```

To add a fixture:

1. Write `definition`, `seed`, `params` (the bundled defaults for the line) and `command_log` by
   hand.
2. Run `update`.
3. Read the `show` output.
4. Add the rule the fixture pins to `fixture_expectations_test.dart`.

Then check its definition on the Python side, against the trip schema and V-T8 and V-T9:

```bash
cd tools/content_kit && uv run pytest tests/test_parity_fixture_definitions.py
```

## Scenarios to check by hand

Each one is also an automated test. Use them to see the rules work end to end, through `show`.

| # | Story | Do | Expect |
| --- | --- | --- | --- |
| 1 | US1 | `show` `sample__line_hay_01_three_stars.json` | Fares hop seat by seat to `DRIVER`. Every `ChangeDelivered` is `exact`. `TripFinished` has 3 stars and the expected earnings. |
| 2 | US1 | `show` `core__fight_at_stop.json` | `ReputationChanged{-30, fight}`, then `PassengerAlighted{fight}` (rules §9.3). The result has 1 star and one `unreturned` mistake. |
| 3 | US2 | `fvm dart test test/replay` | Pacing invariance and rebuild at 10 cuts pass for every fixture. |
| 4 | US3 | `show` `archetype__sleeper_blocks_chain.json`, then `archetype__sleeper_missed_stop.json` | First `TokenBlocked{by: sleeper}` until `PassengerWoke` and `TokenUnblocked`. Then `PassengerWoke`, `PassengerFellAsleep` 15 s later, and `missed_stop` at his station. |
| 5 | US3 | `show` `archetype__hurry_impatient.json` | `PatienceRanOut` after 10 s of being owed, once. |
| 6 | US4 | `show` `archetype__false_claimer_caught.json` | `ClaimRaised`, `ResolveClaim(insist)`, `LiarCaught`, then `FareSent`. |
| 7 | US4 | `show` `archetype__group_payer_redirect.json` | Change to a member is redirected to the payer with a 600 ms hop. |
| 8 | US5 | `show` `event__bump_collect_and_lose.json` | Two `MoneyDropped`: one `DroppedCollected`, one `DroppedLost` after 3 s. |
| 9 | US5 | `show` `event__open_road_clamped.json` | `ScheduleShifted` by less than asked: the next station stays 8 s away. |
| 10 | US6 | `show` `command__request_break.json` | `BreakCompleted` 1.5 s later with 500 + 100×4 + 50×2. A third request is rejected and absent from the log. |
| 11 | US6 | `show` `ending__revived.json` | `TripFailed`, then `Revive`, then `TripRevived{40}`, then `TripFinished` with `revived: true`. |
| 12 | US6 | `show` `ending__story_fight_fails.json` | The first fight gives `TripFailed{revivable: false}`, and `Revive` is rejected. |
| 13 | US7 | `fvm dart test test/replay/rebuild_test.dart` | Each rebuilt state equals the original at the same step, and the rebuilt trip is paused. |

## Check the content and app side

```bash
# Schemas, models, the packaged capabilities file, the new rules and the sample golden
cd tools/content_kit
uv run wassal-content codegen --check
uv run wassal-content validate-source ../../content/examples/sample
uv run wassal-content golden
uv run ruff check . && uv run ruff format --check . && uv run mypy . && uv run pytest --cov --cov-fail-under=80

# The app's tunables registry (50 keys, hints mode)
cd ../../apps/mobile && fvm flutter test test/core/config

# The backend: the new field, its migration, and packs with every engine pool
cd ../../backend
uv run manage.py makemigrations --check --dry-run
uv run pytest --cov --cov-fail-under=80   # the whole suite: coverage counts every app
```

Expected:

- `validate-source` reports no findings on the sample pack.
- Removing one engine pool from `content/examples/sample/speech/` makes it report V-T10.
- Adding `"seconds": 5` to a `bump` event makes it report V-T8.
- Changing a passenger to `bags_lady` makes it report V-T9.

## Done when

- The engine's checks pass, with ≥ 90% coverage.
- Every scenario above holds.
- The content, app and backend checks pass.
- `docs/architecture-mobile.md` §7, §10, §14.3 and §24.4 match the contracts.
- `packages/trip_engine/RULES.md` holds every rule in `contracts/rules.md` plus every rule clarified
  during implementation, each with its fixture or test, and `contracts/rules.md` points to it.
