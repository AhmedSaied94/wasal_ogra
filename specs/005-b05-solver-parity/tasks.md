---

description: "Task list for B05 Solver and Parity"
---

# Tasks: Solver and Parity (B05)

**Input**: Design documents from `specs/005-b05-solver-parity/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**:

- **Mandatory, and first.** Tests are required (constitution XIII). Every phase writes its tests
  first, and they must fail before the implementation tasks start. The mirror's rules are red, then
  green, then refactor (FR-049).
- **Coverage.** At least 90% of lines in `tools/solver/src/wassal_solver/engine/`, and at least 80%
  in the rest of `wassal_solver` and in the backend (FR-051).
- **Real services.** Backend tests run against the local stack's PostgreSQL and Valkey, never mocks.

**Organization**:

- **Paths** are from the repository root. `uv` commands run in `tools/solver/` or `backend/`, and
  `fvm` commands in `packages/trip_engine/`.
- **"§n"** means a section of `packages/trip_engine/RULES.md`. "M01 data-model" and "M01 §n of
  replay-and-fixtures" mean `specs/004-m01-trip-engine/data-model.md` and
  `specs/004-m01-trip-engine/contracts/replay-and-fixtures.md`.
- **The Dart engine is the reference.** Every mirror test ports the cases of the named Dart test file
  in `packages/trip_engine/test/`. Where the Dart test asserts an event, the Python test asserts the
  state change that event reports (the mirror has no events, research R3).
- **Mirror modules match Dart files.** `engine/rules/<name>.py` matches
  `packages/trip_engine/lib/src/rules/<name>.dart`. Three modules beyond plan.md's tree match Dart
  files too: `engine/clock.py` (`clock.dart`), `engine/commands.py` (`commands.dart`) and
  `engine/trip.py` (`engine.dart`). There is no `speech.py` and no `transition.py`.
- **Shared files, edited by one task at a time:** `engine/rules/step.py`,
  `engine/rules/command_handlers.py`, `src/wassal_solver/cli.py`,
  `backend/apps/content/services/build.py` and `.github/workflows/backend.yml`.
- **Fixtures.**
  - Never type an `expected_result`. Never let Python rewrite an existing fixture: that stays with
    Dart's `fvm dart run tool/fixtures.dart update` (FR-012).
  - A parity mismatch is fixed in the mirror. If the Dart engine is the one that disagrees with
    `RULES.md`, stop and raise it: the fix edits `RULES.md`, both engines and the fixtures in one
    change (constitution III, FR-014).
- **Integers only** (constitution II): no `float`, no `/`, `//` and `%` only on non-negative
  values, in the mirror, the solver and the score.
- **One PR.** This feature merges as one PR.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story the task belongs to (US1–US7 from spec.md)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: The `tools/solver` project, its wiring into the backend and the image, and the CI job
(research R1, R16; contracts/ci-checks.md).

- [X] T001 Create the uv project `tools/solver/`, laid out like `tools/content_kit/` (research R1):
  - **`pyproject.toml`:**
    - `name = "wassal-solver"`, `version = "0.1.0"`, `requires-python = "==3.13.*"`,
      `dependencies = ["wassal-content"]`, and `[tool.uv.sources]`
      `wassal-content = { path = "../content_kit" }`;
    - `[project.scripts]` `wassal-solver = "wassal_solver.cli:main"`;
    - hatchling, `[tool.hatch.build.targets.wheel]` `packages = ["src/wassal_solver"]` and
      `artifacts = ["src/wassal_solver/data/*.json", "src/wassal_solver/data/bench/*.json"]`, with
      the content kit's comment on why;
    - the dev group: `ruff==0.17.1`, `mypy==1.19.1`, `pytest==9.1.1`, `pytest-cov==7.1.0`,
      `pytest-xdist==3.8.0` and `hypothesis==6.170.1`;
    - ruff, mypy (strict, `plugins = ["pydantic.mypy"]`, `mypy_path = "src"`), pytest
      (`testpaths = ["tests"]`, `--strict-markers`) and coverage (`source = ["wassal_solver"]`)
      configured as in `tools/content_kit/pyproject.toml`.
  - **`.python-version`:** `3.13`.
  - **Skeleton:**
    - `src/wassal_solver/__init__.py` (a module docstring only), `py.typed`, `cli.py` with a
      `main()` that prints usage and exits 2;
    - the empty packages `engine/`, `engine/rules/`, `solver/`, `scoring/` and `report/`, each with
      an `__init__.py` docstring naming its contract;
    - `src/wassal_solver/data/` and `data/bench/` with a `.gitkeep`;
    - `tests/` with `__init__.py` in every test directory, as the content kit does;
    - a `README.md` that says what the package is and links the contracts. T121 completes it.
  - **Resolve:** run `uv sync` and commit `uv.lock`.
- [X] T002 [P] Create the test support files:
  - `tools/solver/tests/paths.py`: `REPO`, `FIXTURES` (`fixtures/parity`), `SAMPLE`
    (`content/examples/sample`), `SOURCE` (`content/source`), `APP_TUNABLES`
    (`apps/mobile/assets/config/tunables.json`) and `DART_TESTS` (`packages/trip_engine/test`);
  - `tools/solver/tests/conftest.py`: a Hypothesis profile `ci` with `derandomize=True` and
    `deadline=None`, loaded by default, so property tests are the same on every run.
- [X] T003 [P] Wire `wassal-solver` into the backend and its image (contracts/ci-checks.md "The
  image"):
  - `backend/pyproject.toml`: add `"wassal-solver"` to `dependencies` and
    `wassal-solver = { path = "../tools/solver" }` to `[tool.uv.sources]`, next to
    `wassal-content`. Run `uv lock` in `backend/` and commit `backend/uv.lock`;
  - `.dockerignore`: add `!tools/solver/` after `!tools/content_kit/`, and `tools/solver/tests` at
    the end. Update its header comment;
  - `backend/docker/Dockerfile`: add
    `--mount=type=bind,source=tools/solver,target=/tools/solver` to the builder's `uv sync`, and
    mention it in the comment above;
  - check: `uv sync` in `backend/`, then `uv run python -c "import wassal_solver"`.
- [X] T004 [P] Add the `solver` job to `.github/workflows/backend.yml` (contracts/ci-checks.md):
  - the `changes` regex becomes the one in contracts/ci-checks.md, adding `tools/solver/`,
    `packages/trip_engine/` and `apps/mobile/assets/config/tunables\.json$`;
  - a new `solver` job: `needs: changes`, the same `if` as `content-kit`, `ubuntu-24.04`,
    `timeout-minutes: 20`, `working-directory: tools/solver`, setup-uv 0.13.1 with its cache on
    `tools/solver/uv.lock`, then `uv sync --locked`, `uv run ruff check .`,
    `uv run ruff format --check .`, `uv run mypy .`, `uv run pytest -n 4 --cov
    --cov-fail-under=80` and `uv run coverage report --include='*/wassal_solver/engine/*'
    --fail-under=90`;
  - the `backend` summary job adds `solver` to `needs`.

  T051, T109 and T115 add the remaining steps.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The mirror's frame, which every story builds on: integer money, params, the command
codec, the supported set, validation and the state types, and the trip shell that steps and applies
commands (contracts/mirror.md §1–§2; research R2, R5).

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Tests for the frame ⚠️ (write first, must fail)

- [X] T005 [P] Write `tools/solver/tests/engine/test_guards.py` (research R2, constitution I and
  II). Parse every `.py` file under `src/wassal_solver/engine/`, `solver/` and `scoring/` with `ast`,
  and fail on:
  - a float literal, a call to `float`, the `/` operator (`ast.Div`) or `**`;
  - an import of `random`, `math`, `time`, `datetime`, `os`, `io`, `pathlib`, `socket` or `json`,
    and a call to `open`, `hash` or `id`.

  The one allowed exception is `time.monotonic` in `solver/search.py`, for the safety cap. Each
  violation names the file and the line. `engine/fixture.py` is scanned like every other module:
  fixture files are read and written in `src/wassal_solver/fixture_files.py`, outside the scan
  (T048, T106).
- [X] T006 [P] Write `tools/solver/tests/engine/test_money.py`, porting
  `packages/trip_engine/test/money_test.dart` (§14.3, glossary §3.2):
  - the denominations in glossary order;
  - the fewest-pieces greedy decomposition, including the amounts the Dart test names;
  - `scale(x, pct) == x * pct // 100`;
  - the break-down table of §14.
- [X] T007 [P] Write `tools/solver/tests/engine/test_params.py`, porting
  `test/params/params_test.dart` and `test/params/params_tunables_test.dart` (M01 data-model
  "TripParams", research R5):
  - the 28 fields, by name;
  - `TripParams.from_json` refuses an unknown key, a missing key and a non-integer, `bool` included;
  - every bound, at the edge and one past it, gives `bad_params` at `start`;
  - `TripParams.from_tunables(values, line_id)` reads `trip_hop_ms_<line_id>` into `trip_hop_ms`
    and every other field under its own name, from `tests/paths.APP_TUNABLES`, and refuses a
    missing or non-integer field;
  - `to_json()` has the same keys and values as the `params` of every fixture in `fixtures/parity/`.
- [X] T008 [P] Write `tools/solver/tests/engine/test_commands.py`, porting
  `test/commands/command_codec_test.dart` (M01 §1 of replay-and-fixtures):
  - the 13 command names and their arguments;
  - encode, then decode, gives the same entry for an example of each;
  - a wrong argument count, a wrong type, a `bool` where an `int` is due, and a denomination outside
    glossary §3.2 are each refused.
- [X] T009 [P] Write `tools/solver/tests/engine/test_validation.py`, porting
  `test/validation/validation_test.dart` (M01 data-model "Validation"). One case per code, and each
  refusal is `{code, path, message}`:
  - `bad_seed` ("Seed outside 1..2^32−1"), `bad_params`, `duplicate_id`, `unknown_seat`,
    `unknown_station`, `stations_out_of_order`, `board_after_dest`, `seat_taken_at_start`,
    `unknown_passenger`, `group_mismatch`, `unsupported_archetype` (a `bags_lady` passenger),
    `unsupported_event`, `event_param` and `pickup_conflict`;
  - every problem is reported, not only the first, in the same order and with the same paths as
    the Dart test expects.
- [X] T010 [P] Write `tools/solver/tests/engine/test_capabilities.py` (spec FR-003, US1 scenario 5):
  - the mirror's `SUPPORTED` archetypes, events and event parameter rules equal those of
    `wassal_content.engine.capabilities()` (speech slots aren't mirrored, so they're not
    compared);
  - an archetype or an event added to one side only makes the test fail. Check this with a copy of
    `SUPPORTED` edited in the test.
- [X] T011 [P] Write `tools/solver/tests/engine/test_model.py` (data-model.md "Mirror state"):
  - every state class is a `@dataclass(slots=True)`;
  - `Trip.clone()` equals the original, and changing the clone's tray, hand, a passenger, a token, a
    station, an open choice or a counter leaves the original unchanged;
  - `TripResult.to_json()` has exactly the keys of M01 data-model "TripResult".
- [X] T012 [P] Write `tools/solver/tests/engine/test_trip_shell.py`, porting
  `test/engine/engine_shell_test.dart` (§2, §3.1, §4):
  - **start:** `t_ms = 0`, `running`, reputation 100, the tray, who is aboard or waiting, and the
    initial alertness (§2.3, §2.4);
  - **step:** `t_ms += 33` while running, and nothing at all once not running;
  - **step_to(t):** stops at the first step with `t_ms >= t`, or when the trip leaves `running`;
  - **apply:** an accepted command is logged as `[t_ms, *command]`, and a rejected one leaves the
    state unchanged (compare the canonical state before and after) and isn't logged;
  - the 1,201st accepted command is rejected with `command_limit`, and any command after the end
    with `wrong_status`.

### Implementation for the frame

- [X] T013 [P] Implement `tools/solver/src/wassal_solver/engine/clock.py` (`STEP_MS = 33`) and
  `engine/money.py` (denominations, fewest pieces, `scale`, the break-down table) to pass T006.
- [X] T014 [P] Implement `tools/solver/src/wassal_solver/engine/params.py`: a frozen `TripParams`
  dataclass with the 28 fields, `from_json`, `from_tunables(values, line_id)`, `to_json()` and the
  bounds check used by validation, to pass T007. Every bound is copied from M01 data-model
  "TripParams", with a comment naming it.
- [X] T015 [P] Implement `tools/solver/src/wassal_solver/engine/commands.py` (the 13 commands as
  frozen dataclasses, `encode` and `decode` of `[t_ms, "Name", …args]`) and `engine/wire.py` (the
  wire names of enums, as `wire.dart`), to pass T008.
- [X] T016 [P] Implement `tools/solver/src/wassal_solver/engine/capabilities.py`: `SUPPORTED`, the
  mirror's own table of the 12 archetypes, the 8 events and their parameter rules, written out in
  code (not read from the file), to pass T010.
- [X] T017 Implement `tools/solver/src/wassal_solver/engine/model.py` (after T013): the
  `@dataclass(slots=True)` classes `TripState`, `PassengerState`, `MoneyToken`, `StationState`, the
  open choices, the counters and `Mistake`, with the fields of M01 data-model "State", minus events
  and the PRNG state; `TripResult` with `to_json()`; and field-by-field `clone()` methods with no
  `copy.deepcopy`. Passes T011 once T019 exists.
- [X] T018 Implement `tools/solver/src/wassal_solver/engine/rules/course.py` (the indexes, seats and
  groups worked out once at start, as `course.dart`) and `engine/validation.py` (every check of M01
  data-model "Validation", raising `TripRefused(refusals)`), after T014, T016 and T017, to pass
  T009.
- [X] T019 Implement the trip shell, after T015, T017 and T018:
  - `tools/solver/src/wassal_solver/engine/trip.py`: `start(definition, params, seed)` and the
    `Trip` class (`step`, `step_to`, `apply`, `clone`, `status`, `t_ms`, `state`, `result`,
    `command_log`);
  - `engine/rules/step.py`: the §3 phase order as calls to stub functions, so later tasks fill each
    phase;
  - `engine/rules/command_handlers.py`: the dispatch of the 13 commands, the 1,200-command cap and
    `wrong_status`. Each handler checks everything before it changes anything, so a rejected
    command changes nothing (Dart drops its transition instead);
  - `engine/__init__.py`: the exports of contracts/mirror.md §1.

  Passes T011 and T012.
- [X] T020 [P] Write `tools/solver/tests/support/builders.py` and `tests/support/scripts.py` (after
  T014), porting `packages/trip_engine/test/support/builders.dart`, `default_params.dart` and
  `scripts.dart`:
  - small trip definitions that pass `document_findings("trip", …)` and are parsed with
    `wassal_content.models.parse("trip", …)`;
  - `default_params(line_id)` from `tests/paths.APP_TUNABLES`;
  - `play(trip, [(t_ms, command), …])` and readers such as `passenger(trip, "p1")` and
    `balance(trip, "p1")`;
  - setters that put a passenger in a state directly (asleep, muted, holding a token), for unit
    tests only.

**Checkpoint**: The frame is ready. Starting, stepping and applying commands work, and every story
can begin.

---

## Phase 3: User Story 1 - The mirror reproduces every parity fixture (Priority: P1) 🎯 MVP

**Goal**: Every result-deciding rule of `RULES.md` in Python, the replay and the untrusted replay,
the parity check as a test and a command, and parity in the required backend workflow (spec US1,
FR-001 to FR-014; contracts/mirror.md).

**Independent Test**: `uv run wassal-solver parity ../../fixtures/parity` prints `ok 55` on the
fixtures of `master`, the stress fixture included. A mirror-only change to the exact-change reward
makes it fail, naming each fixture, the first differing path and both values. A Dart-only change
makes `fvm dart run tool/fixtures.dart check` fail instead (quickstart §1).

### Tests for User Story 1 ⚠️ (write first, must fail)

- [X] T021 [P] [US1] Write `tools/solver/tests/parity/test_fixtures.py` (research R4, FR-010,
  SC-001):
  - one case per `fixtures/parity/*.json` (README.md excluded), in sorted order, read with
    `wassal_content.loader.load_json_bytes`;
  - `replay(definition, seed, params, command_log).to_json() == expected_result`, and on a
    difference the message gives the fixture, the first differing JSON path (by key order, then
    index) and both values, from `wassal_solver.engine.fixture.first_difference`;
  - at least 55 fixtures are found;
  - every fixture replayed 100 times gives the same result and `command_log_hash` every time
    (`stress__longest_trip.json` 10 times, for time);
  - unit cases of `first_difference`: equal values, a changed leaf, a missing key, a longer list.
- [X] T022 [P] [US1] Write `tools/solver/tests/engine/rules/test_chain.py`, porting
  `test/rules/chain_test.dart` (§5): routing toward the driver and toward a passenger, skipping
  empty seats, hop timing from `trip_hop_ms`, blocking by an unable holder, the next holder
  recomputed when a seat empties or fills, and tokens on getting off.
- [X] T023 [P] [US1] Write `tools/solver/tests/engine/rules/test_fares.py`, porting
  `test/rules/fares_test.dart` (§6.1–§6.4): fares, the student discount rounded up, payments and
  `balance`, tapping to pay the rest in the fewest pieces, and `fares_collected`.
- [X] T024 [P] [US1] Write `tools/solver/tests/engine/rules/test_change.py`, porting
  `test/rules/change_test.dart` (§6.5): exact (`rep_exact_change`, capped at 100), short, over (the
  `over` mistake, and the honest passenger's return), change to someone not owed, two tokens judged
  in arrival order, and group members' change going on to their payer.
- [X] T025 [P] [US1] Write `tools/solver/tests/engine/rules/test_stations.py`, porting
  `test/rules/stations_test.dart` (§9, §11): the warning time and its lists, getting off thanked,
  in a fight (`fights += 1`, an `unreturned` mistake) or unpaid (`lost_fares += 1`), boarding, and
  settling at the end.
- [X] T026 [P] [US1] Write `tools/solver/tests/engine/rules/test_scoring.py`, porting
  `test/rules/scoring_test.dart` (§11): stars by fights and mistakes, `star_flags`, earnings
  `min(max(0, fares − overpaid + tips) // 100, max_earnings_jenehat)`, `duration_ms`, `reputation`
  and `outcome`.
- [X] T027 [P] [US1] Write `tools/solver/tests/engine/rules/test_fail_revive.py`, porting
  `test/rules/fail_revive_test.dart` (§10, §4.10): reputation changes and their causes, failing,
  `Revive` and its limit (`not_revivable`).
- [X] T028 [P] [US1] Write the command tests in `tools/solver/tests/engine/commands/`, one module per
  Dart file of `test/commands/` (§4): `test_hand_commands.py`, `test_tap_pay.py`,
  `test_request_break.py`, `test_boosters.py`, `test_undo.py` and `test_abandon.py`. Each port
  keeps every rejection code its Dart file checks (`tray_empty`, `hand_empty`, `not_aboard`,
  `no_effect`, `no_choice`, `bad_argument`, `undo_unavailable`, `break_limit`, `booster_limit`,
  `cannot_make_change`). `abandon_pause_test.dart`'s pause and resume cases aren't ported (research
  R3).
- [X] T029 [P] [US1] Write the passenger tests in `tools/solver/tests/engine/archetypes/`, one module
  per Dart file of `test/archetypes/` (§7): `test_sleeper.py`, `test_headphones.py`,
  `test_patience.py`, `test_hajja.py`, `test_group.py`, `test_claims.py`, `test_chatty.py` and
  `test_regular_customer.py`. `hurry`, `big_note`, `student` and `honest` are covered where the Dart
  tests cover them.
- [X] T030 [P] [US1] Write the event tests in `tools/solver/tests/engine/events/`, one module per
  Dart file of `test/events/` except `event_json_test.dart` (§8): `test_bump.py`,
  `test_schedule_shift.py` (traffic and open road), `test_fare_increase.py`,
  `test_drop_me_here.py`, `test_dispute.py`, `test_change_request.py` and
  `test_roadside_pickup.py`.
- [X] T031 [P] [US1] Write `tools/solver/tests/engine/test_replay.py` and
  `tests/engine/test_command_log_hash.py`, porting `test/replay/replay_test.dart` and
  `test/replay/fingerprint_test.dart` (contracts/mirror.md §3; M01 §2–§3 of replay-and-fixtures):
  - the three refusals, `the trip is refused` (with the start codes), `t_ms goes down along the
    log` (with `index`) and `an entry is rejected` (with `index` and the rejection code), on the
    same inputs as the Dart test (US1 scenario 4);
  - `command_log_hash` is `lowercase_hex(sha256(utf8(canonical_json(log))))` and equals the
    `command_log_hash` in three named fixtures, computed from their `command_log` alone.
- [X] T032 [P] [US1] Write the property tests (Hypothesis, FR-050):
  - `tools/solver/tests/engine/test_replay_properties.py`: random logs over the five sample trips,
    each command drawn among those the trip accepts in its current state; replaying a log twice
    gives the same result;
  - `tools/solver/tests/engine/test_integer_rules.py` (§15): after every step of those logs, every
    money and time field of the state is an `int` and not a `bool`, and money is conserved: the
    tray, the hand, money in transit or on the floor, and money passengers kept or lost add up to
    the initial tray plus every payment, break and booster (as the Dart fuzz test checks).
- [X] T033 [P] [US1] Write `tools/solver/tests/cli/test_parity_sync.py` (contracts/cli.md):
  - `parity` on `fixtures/parity` prints `ok <n>` and exits 0; on a directory holding a copy of one
    fixture with an edited `expected_result`, it prints one block (fixture, path, expected,
    actual) and exits 1; on an unreadable fixture, it exits 1; with a bad option, it exits 2;
  - `sync --check` exits 0 when `src/wassal_solver/data/tunables.json` equals the app's file, and 1
    when they differ (use a temporary copy); `sync` rewrites the copy byte for byte.

### Implementation for User Story 1

- [X] T034 [P] [US1] Implement `tools/solver/src/wassal_solver/engine/rules/chain.py` (§5) to pass
  T022.
- [X] T035 [P] [US1] Implement `tools/solver/src/wassal_solver/engine/rules/fares.py` (§6.1–§6.4) to
  pass T023.
- [X] T036 [P] [US1] Implement `tools/solver/src/wassal_solver/engine/rules/change.py` (§6.5) to pass
  T024.
- [X] T037 [P] [US1] Implement `tools/solver/src/wassal_solver/engine/rules/reputation.py` (§10): add
  capped at 100, subtract with its cause, and the failure check.
- [X] T038 [P] [US1] Implement `tools/solver/src/wassal_solver/engine/rules/passengers.py` (§3 step
  2, §4.5, §7.3): alertness timers in passenger order, and patience.
- [X] T039 [P] [US1] Implement `tools/solver/src/wassal_solver/engine/rules/claims.py` (§4.6, §7.4,
  §10.1).
- [X] T040 [P] [US1] Implement `tools/solver/src/wassal_solver/engine/rules/requests.py` (§4.7,
  §4.8): payment disputes and change requests.
- [X] T041 [P] [US1] Implement `tools/solver/src/wassal_solver/engine/rules/authored_events.py`
  (§8): each event fires once at its `at_seconds`, in definition order, and shifts never move it.
- [X] T042 [P] [US1] Implement `tools/solver/src/wassal_solver/engine/rules/aids.py` (§4.4, §4.9,
  §4.11): undo, the break request and the four boosters.
- [X] T043 [P] [US1] Implement `tools/solver/src/wassal_solver/engine/rules/scoring.py` (§11): the
  result of every end, `finished`, `failed` or `abandoned`.
- [X] T044 [US1] Implement `tools/solver/src/wassal_solver/engine/rules/stations.py` (§9, §11), after
  T034–T037 and T043, to pass T025.
- [X] T045 [US1] Fill `tools/solver/src/wassal_solver/engine/rules/step.py` with every phase of §3 in
  order, calling T034–T044, to pass T026, T027, T029 and T030. Speech is skipped: it changes nothing
  but the PRNG (§12, §13).
- [X] T046 [US1] Fill `tools/solver/src/wassal_solver/engine/rules/command_handlers.py` with the 13
  commands, each with its checks in the order of §4, after T045, to pass T028.
- [X] T047 [US1] Implement `tools/solver/src/wassal_solver/engine/replay.py`: `replay(definition,
  seed, params, command_log)` with the algorithm of contracts/mirror.md §3, `ReplayRefused` with its
  three reasons, and `command_log_hash`, to pass T031 and T032.
- [X] T048 [US1] Implement the fixture check, with the I/O kept out of the engine
  (contracts/mirror.md §5), to pass T021:
  - `tools/solver/src/wassal_solver/engine/fixture.py`, with no I/O: `parse_fixture(document)`
    (strict, the five keys), `first_difference(expected, actual)` and `check_fixture(document)`,
    which returns the mismatch or `None`;
  - `tools/solver/src/wassal_solver/fixture_files.py`: `load_fixture(path)`, which reads the bytes
    and parses them with `wassal_content.loader.load_json_bytes`, and `check_fixtures(paths)`, which
    returns the mismatches.
- [X] T049 [US1] Implement `sync [--check]` and `parity [PATH…]` in
  `tools/solver/src/wassal_solver/cli.py` (contracts/cli.md), with exit codes 0, 1 and 2. Run
  `uv run wassal-solver sync` to create `src/wassal_solver/data/tunables.json`, a byte-for-byte copy
  of `apps/mobile/assets/config/tunables.json` (research R5). Passes T033.
- [X] T050 [US1] Make every fixture pass: `uv run pytest tests/parity -q` and
  `uv run wassal-solver parity ../../fixtures/parity`, which prints `ok 55`. Each mismatch is fixed
  in the mirror (see Organization, "Fixtures"). Then run the whole suite: every test of T005–T033
  passes.
- [X] T051 [US1] Add the steps `uv run wassal-solver sync --check` and
  `uv run wassal-solver parity ../../fixtures/parity` to the `solver` job in
  `.github/workflows/backend.yml`, after the coverage step (contracts/ci-checks.md).

### Untrusted replay (FR-007 to FR-009, SC-009)

- [X] T052 [P] [US1] Write `tools/solver/tests/engine/test_replay_untrusted.py` (contracts/mirror.md
  §4, research R6):
  - **One case per refusal**, in check order:
    - `bad_input`: not an object, a key missing, an extra key, a float, `NaN`, a duplicate key;
    - `bad_definition`: a definition that fails `document_findings("trip", …)`, with its findings
      attached;
    - `bad_params`: an unknown key, a missing key, a value past a bound;
    - `bad_log`: not a list, 1,202 entries, an entry that isn't an array, a negative `t_ms`, a
      `t_ms` that isn't a multiple of 33 or is over 1,500,000, an unknown name, a wrong argument
      count or type, and a denomination outside glossary §3.2, each with its `index`;
    - then `replay`'s three reasons.
  - **A valid tuple** (every sample fixture) gives the same result as `replay`.
  - **Hypothesis:** random JSON values and random mutations of a valid tuple never raise anything
    but `ReplayRefused`, and never apply more than 1,201 commands or step more than 45,500 times
    (count them through a test hook on `Trip`).
- [X] T053 [US1] Implement `replay_untrusted(document)` in
  `tools/solver/src/wassal_solver/engine/replay.py`, after T047, with the checks of
  contracts/mirror.md §4 in that order, every check before any stepping, to pass T052. Export it
  from `engine/__init__.py`.
- [X] T054 [US1] Update the opening of `packages/trip_engine/RULES.md` (FR-006, research R3):
  - the first paragraph: B05's mirror reproduces every rule that decides state and results;
  - the paragraph on events: the Dart tests alone check event order and speech (§12, §13), and the
    mirror leaves them out, because no result depends on them (B05 spec FR-006).

  No rule changes, so no fixture changes.
- [X] T055 [US1] Check SC-002 locally, as in quickstart §1:
  - change the exact-change reward in `engine/rules/change.py` only: `parity` fails, naming the
    fixtures, the path and both values;
  - revert it, then make the same change in `packages/trip_engine/lib/src/rules/change.dart` only:
    `fvm dart run tool/fixtures.dart check` fails;
  - revert both, and note the outcome for the PR description.

**Checkpoint**: The mirror reproduces all 55 fixtures, refuses malformed tuples, and CI checks it.
B08 could already verify results.

---

## Phase 4: User Story 2 - Prove a trip can be played to 3 stars (Priority: P2)

**Goal**: The settings and fingerprints, the idealized player, the depth-first search with its
ends, the best run and the confirmation, and `wassal-solver solve` (spec US2, FR-015 to FR-022,
FR-045, FR-046; contracts/solver.md §1–§4; research R7–R10, R12).

**Independent Test**: `uv run wassal-solver solve ../../content/examples/sample` solves all five
trips, and each run replays to 3 stars. `tests/data/faults/change_impossible.json` is not solved
and names the passenger. `too_fast.json` is not solved at 600 ms and solved with
`--reaction-ms 100` (quickstart §2).

### Tests for User Story 2 ⚠️ (write first, must fail)

- [X] T056 [P] [US2] Write `tools/solver/tests/test_settings.py` (data-model.md "SolverSettings"):
  - `load_settings()` reads `data/settings.json` into a frozen `SolverSettings` with
    `reaction_ms` 600, `tap_ms` 198, `effort_budget_steps` 1,000,000, `safety_cap_seconds` 180,
    `transposition_cap` 100,000, `report_reaction_ms` `[900, 1200]` and the `score` table;
  - "Loading refuses unknown keys, missing keys, non-integers, and a `reaction_ms` or `tap_ms` that
    is negative", each a case, with a temporary file;
  - `settings_version` is "the first 16 hex digits of the SHA-256 of the record's canonical JSON",
    and changes when any field changes;
  - `bundled_params(line_id)` equals `TripParams.from_tunables(<the packaged copy>, line_id)` for
    both MVP lines.
- [X] T057 [P] [US2] Write `tools/solver/tests/test_fingerprints.py` (data-model.md "Fingerprints"):
  - `solver_fingerprint()` is 16 hex digits, the same on two calls, and different when a file under
    a temporary copy of the package changes (the function takes the package root, for testing);
  - `params_fingerprint(params)` is 16 hex digits of the canonical params;
  - `input_key(definition, params)` is 64 hex digits, identical for `rev` 1 and `rev` 7, and
    different when the definition, the params or the solver fingerprint changes.
- [X] T058 [P] [US2] Write `tools/solver/tests/solver/test_decisions.py` (contracts/solver.md §2):
  - one case per row of the decisions table: when it is possible, and the commands it becomes;
  - `give_change` builds only exact change from the tray, with the hand empty, and never for a
    passenger who isn't owed;
  - compositions are ordered by the fewest pieces, then the most 50s and 100s left in the tray,
    then the largest pieces first;
  - `answer_claim` insists exactly when the claim is false, and `answer_dispute` names the
    passenger who sent their fare;
  - timing: `R = ceil(reaction_ms / 33) × 33` (600 → 627) and `T = ceil(tap_ms / 33) × 33`
    (198 → 198); a decision's first command is at `t ≥ max(end_of_last_decision + R,
    became_possible + R)`, and each further command `T` after the one before;
  - a command rejected partway through a decision drops the branch;
  - no decision ever produces `UseBooster`, `Revive`, `UndoLastSend` or `Abandon` (FR-016).
- [X] T059 [P] [US2] Add the crafted trips of SC-004 under `tools/solver/tests/data/faults/`, each
  passing `document_findings("trip", …)` unless its kind is a refusal, and write
  `tools/solver/tests/solver/test_faults.py`:
  - `change_impossible.json`: the tray can never make one passenger's change, and no break helps.
    Not solved, `exhausted`, and `first_loss` names that passenger, their station and the time;
  - `too_fast.json`: two deliveries due less than 600 ms apart. Not solved at the default settings,
    solved with `reaction_ms = 100` (US2 Independent Test);
  - `aid_only.json`: 3 stars only with a booster, an undo or a revive. Not solved (US2 scenario 2);
  - `break_needed.json`: 3 stars need one `RequestBreak`. Solved, and the run has a
    `request_break` decision (US2 scenario 3);
  - `change_request.json`: a change request that either answer survives. Solved;
  - `refused_definition.json` (`stations_out_of_order`) and `unsupported_type.json` (a
    `bags_lady` passenger): `refused`, with the refusal codes (US2 scenario 6).
- [X] T060 [P] [US2] Write `tools/solver/tests/solver/test_search.py` (contracts/solver.md §3–§4):
  - each of the five sample trips is `solved` with `end = found` and `stars = 3`, and
    `replay(…, run)` gives 3 stars (US2 scenario 1);
  - the ends: `exhausted` (a tiny unsolvable trip), `budget_spent` (`effort_budget_steps = 50`, with
    the best run reported, US2 scenario 5), `safety_cap` (`safety_cap_seconds = 0`), `refused`, and
    `internal_error` both when the mirror raises (monkeypatched) and when the confirming replay
    gives 2 stars (monkeypatched): never `solved` (FR-020);
  - the visited table never holds more than `transposition_cap` entries;
  - the best run has the most stars, then the latest `first_loss.t_ms`;
  - `effort_steps` counts the mirror steps, and every run's command names are among the nine of
    FR-016;
  - `solve` never raises, and logs the exception for `internal_error` (`caplog`).
- [X] T061 [P] [US2] Write `tools/solver/tests/solver/test_determinism.py` (research R9, FR-021):
  - each sample trip solved twice in one process gives byte-identical canonical results;
  - `wassal-solver solve <sample> --json` run in two subprocesses with `PYTHONHASHSEED=1` and
    `PYTHONHASHSEED=2` prints identical bytes.
- [X] T062 [P] [US2] Write `tools/solver/tests/solver/test_properties.py` (Hypothesis, FR-050):
  over sample trips with drawn changes (tray counts, `pays_at_seconds`, a passenger removed),
  `solve` never raises with a small budget, and every `found` run replays to 3 stars.
- [X] T063 [P] [US2] Write `tools/solver/tests/cli/test_solve.py` (contracts/cli.md): `solve
  TRIP.json`, `solve LAYOUT`, `solve LAYOUT --trip ID`, `--json` (canonical `SolverResult`s) and
  `--reaction-ms N`; the output names the verdict, the end, the stars and the timeline; the exit
  code is 0 for every verdict and 2 for a usage error.

### Implementation for User Story 2

- [X] T064 [P] [US2] Create `tools/solver/src/wassal_solver/data/settings.json` with the initial
  values of data-model.md "SolverSettings" and the score table of contracts/solver.md §5, and
  implement `tools/solver/src/wassal_solver/settings.py`: `SolverSettings` (frozen),
  `load_settings()`, `settings_version` and `bundled_params(line_id)`, reading package data through
  `importlib.resources`. Passes T056.
- [X] T065 [P] [US2] Implement `tools/solver/src/wassal_solver/fingerprint.py`:
  `solver_fingerprint(root=None)` over every `.py` and `.json` file of the installed package in
  sorted path order plus the packaged `capabilities.json`, `params_fingerprint(params)` and
  `input_key(definition, params)` over canonical `{"definition": <with rev = 0>, "params": …,
  "solver": solver_fingerprint}`. Passes T057.
- [X] T066 [US2] Implement `tools/solver/src/wassal_solver/solver/decisions.py`: the `Decision`
  type of data-model.md "Decision", the possible decisions of a state, their commands and the
  timing rule. Passes T058.
- [X] T067 [US2] Implement `tools/solver/src/wassal_solver/solver/timeline.py`, after T066:
  `TimelineEntry` (`{t_ms, decision, passenger_id?, amount_piasters?, pieces?, note?}`) built from a
  run's decisions and the mirror state, with a last `lost_star` entry for a run that isn't solved
  (research R10).
- [X] T068 [US2] Implement `tools/solver/src/wassal_solver/solver/result.py`, after T067:
  `SolverResult` with the fields of data-model.md "SolverResult" and `to_json()`, `first_loss`
  (`{kind, t_ms, passenger_id?, station_id?, detail}`, `kind` ∈ `fight`, `mistake`, `failed`, read
  from the mirror's counters), and the confirmation of contracts/solver.md §4.
- [X] T069 [US2] Implement `tools/solver/src/wassal_solver/solver/search.py`, after T068: the
  depth-first search of contracts/solver.md §3 (ordering, wait points with the timing points of
  sleepers and headphones, pruning at the first star loss, the BLAKE2b-16 visited table capped at
  `transposition_cap`, the step budget, the safety cap checked every 1,024 steps with
  `time.monotonic`, and the best run, played on to its end). Passes T059 and T060.
- [X] T070 [US2] Implement `solve(definition, params, settings)` in
  `tools/solver/src/wassal_solver/solver/__init__.py` (it never raises: a refused start gives
  `refused`, any exception gives `internal_error` after `logger.exception`), and export `solve`,
  `SolverSettings`, `load_settings` and `bundled_params` from
  `tools/solver/src/wassal_solver/__init__.py`. Passes T061 and T062.
- [X] T071 [US2] Implement `solve TRIP.json | LAYOUT [--trip ID] [--json] [--reaction-ms N]` in
  `tools/solver/src/wassal_solver/cli.py`, reading a layout with `wassal_content.source.read_layout`
  and its trips with `parse("trip", …)`. Passes T063.
- [X] T072 [US2] Solve the sample pack (`uv run wassal-solver solve ../../content/examples/sample`):
  - every trip is `solved` (FR-042, first half). If one isn't, correct the trip in
    `content/examples/sample/trips/`, then update everything that copies it, in this change: the
    sample's golden checksums (`uv run wassal-content golden --update` in `tools/content_kit`, then
    review), its `sample__` fixture (Dart `update`, then review its `show` output and its
    expectation), and any Dart, content-kit or backend test that names its values;
  - record each trip's `effort_steps` and time in the PR description, for T117.

**Checkpoint**: The solver proves the sample pack 3-star solvable and catches every flawed trip of
SC-004 except the band cases, which US3 adds.

---

## Phase 5: User Story 3 - Score a trip's difficulty against its line's band (Priority: P3)

**Goal**: The integer score from six run-based inputs, its band check, and `check-source`, which
re-solves a layout (spec US3, FR-023 to FR-027; contracts/solver.md §5; research R11).

**Independent Test**: `uv run wassal-solver check-source ../../content/examples/sample --bands
error` exits 0, with every `line_hay` trip in 0–30 and every `line_gamaa` trip in 20–55.
`tests/data/faults/hay_too_hard.json` scores above 30 and gets a `V-Z5` warning (quickstart §3).

### Tests for User Story 3 ⚠️ (write first, must fail)

- [X] T073 [P] [US3] Write `tools/solver/tests/scoring/test_difficulty.py` (contracts/solver.md §5):
  - each input on small built trips and hand-written runs: `owed_at_once`, `change_pieces`,
    `blockers` (sleepers and headphones passengers on a payer's §5 chain to the driver),
    `breaks`, `tightness_ms = max(0, slack_ref_ms − min slack)` (0 with no change in the run) and
    `variety` (distinct archetypes plus distinct `event_id`s);
  - `points_i = min(cap_i, max(0, value_i − free_i) × per_i // unit_i)` and
    `score = min(100, Σ points_i)`, with the table of settings.json;
  - the `Score` JSON has the shape of data-model.md "Score": every input's `value` and `points`,
    and no band;
  - `in_band(score, band)` is `band.min ≤ score ≤ band.max`, both ends included (contracts/solver.md
    §5);
  - a trip with nothing to do scores near 0 (spec Edge Cases);
  - a `not_solved` or `refused` result has no score (US3 scenario 4).
- [X] T074 [P] [US3] Write `tools/solver/tests/scoring/test_monotonic.py` (Hypothesis, FR-025,
  FR-026): for random tables and input values, raising one input never lowers the score, the score
  is an `int` in 0..100, and the same inputs always give the same score.
- [X] T075 [P] [US3] Write `tools/solver/tests/scoring/test_sample_bands.py` (FR-042, SC-003): every
  sample trip is solved and scores inside its line's `difficulty_band`, read from
  `content/examples/sample/lines/<line>.json`: `line_hay` 0–30, `line_gamaa` 20–55.
- [X] T076 [P] [US3] Add `tools/solver/tests/data/faults/hay_too_hard.json` (a `line_hay` trip with
  four passengers owed at once and little slack, solvable) and `gamaa_too_easy.json` (a
  `line_gamaa` trip that is solvable and scores below 20), and write
  `tools/solver/tests/scoring/test_band_warnings.py` (SC-004, US3 scenario 3): each is `solved`
  and `in_band(score, band)` is false for its line's band, with the score above or below it.
- [X] T077 [P] [US3] Write `tools/solver/tests/cli/test_check_source.py` (contracts/cli.md,
  FR-039, FR-040):
  - the sample with `--bands error` exits 0;
  - a temporary layout with `hay_too_hard.json` exits 1 with `--bands error`, and 0 with
    `--bands warning`, printing the score, the band and the inputs that contribute most;
  - a layout with an unsolvable trip exits 1 with either option, naming the trip, the pack version
    and the file;
  - an `end` of `safety_cap` or `internal_error` exits 1 (monkeypatched);
  - a layout with no `pack.json` prints `no pack in <LAYOUT>` and exits 0 (US6 scenario 4);
  - `--json` prints the canonical results.

### Implementation for User Story 3

- [X] T078 [US3] Implement `tools/solver/src/wassal_solver/scoring/difficulty.py`: `score_trip(
  definition, run, params, settings)` (no band: the caller checks it). The inputs are read by stepping a fresh `Trip` through
  the confirmed run and observing its state after each step (who is owed, when each change
  arrives), since the mirror has no events (FR-006). Export `score_trip` from
  `wassal_solver/__init__.py`. Passes T073 and T074.
- [X] T079 [US3] Attach the score and add the band check, to pass T076:
  - `solve` (`tools/solver/src/wassal_solver/solver/__init__.py`) sets `score` only when `solved`,
    with no band;
  - `in_band(score, band)` goes in `tools/solver/src/wassal_solver/scoring/difficulty.py`, exported
    from `wassal_solver/__init__.py`;
  - the `solve` command reads the band from the trip's line file and prints the check;
  - `solve` takes no band: a reused result is always checked against the line's current band
    (contracts/solver.md §5).
- [X] T080 [US3] Implement `check-source LAYOUT [--bands error|warning] [--json]` in
  `tools/solver/src/wassal_solver/cli.py`, with the exit rules of contracts/cli.md, re-solving
  every trip with `bundled_params` and the default settings. Passes T077.
- [X] T081 [US3] Calibrate the score table (research R11):
  - run `uv run wassal-solver solve ../../content/examples/sample --json` and read each trip's
    inputs;
  - adjust only the `score` table in `src/wassal_solver/data/settings.json` until T075 and T076
    pass with margin, keeping every term monotonic;
  - copy the final table into `specs/005-b05-solver-parity/contracts/solver.md` §5 ("Initial
    table") and the example in data-model.md "Score";
  - if no table fits a sample trip, correct the trip or its line's band instead, with everything
    that copies it, as in T072 (FR-042, second half).

**Checkpoint**: Every solved trip has a score and a band check, and the sample pack is inside its
bands.

---

## Phase 6: User Story 4 - Staging builds run the real solver stage, and publishing opens (Priority: P4)

**Goal**: The real stage at B04's plug-in point, the `SolverRun` table and reuse, the heartbeat,
the report and release-record additions, guards that accept a solver warning, and `solver` as the
strict default (spec US4, FR-028 to FR-033, FR-047; contracts/content-pipeline.md §1–§5, §7–§8;
research R13, R14).

**Independent Test**: On the local stack with `CONTENT_SOLVER_STAGE=solver`, building the sample
gives a `passed` solver stage with five solved trips, and Publish works. A rebuild with no change
reports `reused = 5` and is otherwise identical. An unsolvable trip fails the stage with `V-Z1`, and
Publish is refused. An out-of-band trip gives `warning` with `V-Z5`, and Publish works (quickstart
§6).

### Tests for User Story 4 ⚠️ (write first, must fail)

- [X] T082 [P] [US4] Write `backend/apps/content/tests/test_solver_models.py` (data-model.md
  "SolverRun"):
  - the `id` is a UUIDv7;
  - `solverrun_one_active_preview`: a second `preview` run for the same `trip` while one is
    `queued` or `running` raises `IntegrityError`, and is allowed once the first is `done` or
    `failed`; `build` runs are never limited;
  - `solverrun_finished_has_time`: `finished_at` must be set exactly when `status` is `done` or
    `failed`;
  - deleting the `Trip` keeps its runs, with `trip = NULL`.
- [X] T083 [P] [US4] Write `backend/apps/content/tests/test_solver_stage.py` (contracts/
  content-pipeline.md §2–§3, §5), with `settings.CONTENT_SOLVER_STAGE = "solver"` over the sample
  content (the existing `sample_reviewed` fixture):
  - the stage is `passed`, `stages.solver.trips` has five entries in pack order with the fields of
    data-model.md "Validation report additions" (the six input values in `inputs` included,
    FR-030), `meta` has `solver_fingerprint`, `settings_version`, `solved = 5` and `reused = 0`, and
    Publish works (US4 scenario 1);
  - a second build with nothing changed has `reused = 5`, `solved = 0`, and otherwise the same
    `stages.solver` (FR-031);
  - after those builds, narrowing `line_hay`'s band so one of its trips falls outside gives
    `reused = 5`, a `warning` stage and a `V-Z5` finding for that trip. Restoring the band clears
    the warning. The band is checked at each build, never read from a stored result;
  - a trip whose change can't be made: `failed`, one `V-Z1` finding with `stage="solver"`,
    `entity="trip"`, the `trip_id` and `path="$.trips[<i>]"`, the other trips still reported, and
    Publish refused (US4 scenario 2);
  - a line band that leaves one trip outside: `warning`, a `V-Z5` finding, and Publish works (US4
    scenario 3);
  - `V-Z2` for a refused trip, `V-Z3` for a `safety_cap` end and `V-Z4` for an `internal_error`
    end (monkeypatched `solve`), each with the message of data-model.md "Finding codes"; `V-Z4`
    also logs the exception with the trip id, and its message carries no exception text (FR-033);
  - `safety_cap` and `internal_error` results are stored `failed`, so the next build solves those
    trips again (`finish_run`, T090);
  - `progress` is called once per trip, and `content_build --dry-run` changes no `updated_at`.
- [X] T084 [P] [US4] Update `backend/apps/content/tests/test_build.py`:
  - its `FailingSolver` and the stand-in cases use the new protocol,
    `run(pack, progress) -> SolverOutput | None`;
  - a build whose `updated_at` keeps being refreshed by the heartbeat isn't swept after 30 minutes;
  - a build with no progress for 30 minutes is failed with "the build stopped: no progress for 30
    minutes";
  - `queued` or `running` `SolverRun`s with `updated_at` older than 30 minutes become `failed`,
    with `result = {"error": "stopped: no progress for 30 minutes"}` and `finished_at` set
    (US4 scenario 6).
- [X] T085 [P] [US4] Update `backend/apps/content/tests/test_publish.py` and
  `backend/apps/content/tests/test_promotion.py` (contracts/content-pipeline.md §4):
  - publish accepts a solver stage of `passed` or `warning`, and still refuses `failed` and
    `not_available`, with the same messages as before;
  - promotion's step 3 accepts a record whose `stages.solver` is `warning`, keeps refusing any
    other stage's `warning` except `size`, and still refuses a missing or `not_available` solver
    (US4 scenario 7).
- [X] T086 [P] [US4] Write `backend/apps/content/tests/test_release_record.py` (data-model.md
  "Release record addition", FR-030):
  - the record's `solver` object has `solver_fingerprint`, `settings_version` and, per trip, only
    `trip_id`, `rev`, `verdict`, `stars`, `score`, `band`, `params_fingerprint` and `run_hash`: no
    runs, no timelines, no score inputs and no staff names (US4 scenario 5, FR-030);
  - `warnings` lists the `V-Z5` findings;
  - a record built from a 200-trip solver summary stays under `MAX_RELEASE_BYTES` (64 KB).
- [X] T087 [P] [US4] Update `backend/tests/test_settings_guards.py` (contracts/content-pipeline.md
  §7): the strict default of `CONTENT_SOLVER_STAGE` is `solver` on staging and prod, `stand_in` is
  still refused there, `solver` passes `SOLVER_STAGE_PATTERN`, and dev and test still default to
  `stand_in` (US4 scenario 4).

### Implementation for User Story 4

- [X] T088 [US4] Add `backend/apps/content/models/solver.py` with `SolverRun`, export it from
  `models/__init__.py`, and create `backend/apps/content/migrations/0007_solverrun.py`
  (expand-only, `uv run manage.py makemigrations content`). The fields of data-model.md
  "SolverRun":
  - `id` UUIDv7 primary key, as the other content models;
  - `kind`: `build` · `preview`; `status`: `queued` · `running` · `done` · `failed`;
  - `input_key` char(64), indexed; `trip_id` char(40);
  - `trip`: FK `content.Trip`, null, `SET_NULL`, previews only;
  - `requested_by` char(150), blank, previews only: "A staff name, which never leaves the
    database";
  - `result` jsonb; `created_at`, `updated_at` (the heartbeat the sweep reads) and `finished_at`;
  - the constraints `solverrun_one_active_preview` (unique `trip` where `kind = 'preview'` and
    `status` is `queued` or `running`) and `solverrun_finished_has_time`.

  `status` follows data-model.md "SolverRun": a result whose `end` is `safety_cap` or
  `internal_error` is stored `failed`, so it is never reused (the safety cap reads the clock).
  T090's `finish_run` applies that rule. Passes T082.
- [X] T089 [US4] Widen `backend/apps/content/services/stages.py` (contracts/content-pipeline.md §1):
  `SolverOutput(findings, trips, meta)`, the protocol
  `run(pack, progress) -> SolverOutput | None`, `NoSolver` returning `None`, `StandInSolver`
  returning `SolverOutput([], [], {"stand_in": True})`, and `load_solver_stage()` mapping
  `solver` to `apps.content.services.solver_stage.SolverStage`.
- [X] T090 [US4] Create `backend/apps/content/services/solver_stage.py`, to pass T083 with T091:
  - `finish_run(run, result)` (contracts/content-pipeline.md §5): it saves `result` and
    `finished_at`, with `status` `failed` for an `end` of `safety_cap` or `internal_error` and
    `done` otherwise. T099's preview job uses it too;
  - `SolverStage`, with the steps of contracts/content-pipeline.md §2 in order:
    1. the line and `bundled_params`;
    2. `input_key`;
    3. reuse of the newest `done` run of either kind, or else a `build` run created `running`,
       then `solve(…)` and `finish_run`;
    4. `progress()` after each trip;
    5. the result-to-finding table, with the messages of data-model.md "Finding codes";
  - the band check uses `in_band` with this pack's line, never a band stored with a run;
  - each trip's summary has the fields of data-model.md "Validation report additions", the
    score's input values included (FR-030).
- [X] T091 [US4] Update `backend/apps/content/services/build.py`, after T089 and T090:
  - `produce()` takes `progress: Callable[[], None]` and passes it to the stage; `run_build` passes
    `lambda: ContentPack.objects.filter(pk=pack.pk).update(updated_at=timezone.now())`, and the
    `content_build --dry-run` path a no-op;
  - `report_dict` writes `stages.solver.trips` and `stages.solver.meta` next to `result`;
  - `sweep_stuck_builds` keeps its 30-minute cut-off, says "the build stopped: no progress for 30
    minutes", and also fails stale `SolverRun`s (contracts/content-pipeline.md §5);
  - `is_green` is unchanged.

  Passes T084.
- [X] T092 [P] [US4] Update `backend/apps/content/services/release.py`: `release_record` adds the
  `solver` object of data-model.md "Release record addition", built from `stages.solver` with the
  listed fields only. With the stand-in, it is `{"stand_in": true, "trips": []}`. Passes T086.
- [X] T093 [P] [US4] Update the guards (contracts/content-pipeline.md §4):
  - `backend/apps/content/services/publish.py`: `solver in ("passed", "warning")`, and the module
    docstring's step 1;
  - `backend/apps/content/services/promote.py` `_passed`: the solver may be `passed` or `warning`,
    and the other stages keep their rule (`passed`, or `size` with `warning`). Update the module
    docstring's step 3.

  Passes T085.
- [X] T094 [P] [US4] Update `backend/config/env.py` (contracts/content-pipeline.md §7):
  `SOLVER_STAGE_PATTERN` gains `solver`, the strict default becomes `solver`, and the comment above
  it says so. Check that `backend/docker/env/staging.env`, `backend/docker/env/prod.env` and
  `backend/.env.example` don't set `CONTENT_SOLVER_STAGE` to anything else, and update the
  `.env.example` comment. Passes T087.
- [X] T095 [US4] Show the solver stage on the pack's admin page: in
  `backend/apps/content/admin/reports.py` and
  `backend/apps/content/templates/admin/content/contentpack/change_form.html`, a table of
  `stages.solver.trips` (trip, verdict, end, stars, score, the six inputs, band, in band, reused)
  and the `meta` line, under the existing stage results. Add an assertion to
  `backend/apps/content/tests/test_admin_packs.py` that the table renders.
- [X] T096 [US4] Edit B04's contracts, each edit marked "(B05)" (contracts/content-pipeline.md §8):
  - `specs/003-b04-content-pipeline/contracts/environment.md`: the `CONTENT_SOLVER_STAGE` row gets
    `solver` and the strict default;
  - `specs/003-b04-content-pipeline/contracts/pack-delivery.md` "Release record": a stage may be
    `warning` for `size` or `solver`, the record has a `solver` object, and "Publish on staging"
    step 1 reads "its solver stage `passed` or `warning`";
  - `specs/003-b04-content-pipeline/contracts/admin.md` "Validation report": the solver must be
    `passed` or `warning` before a publish;
  - `specs/003-b04-content-pipeline/contracts/content-schemas.md`: the `V-Z1` row points to
    `specs/005-b05-solver-parity/contracts/content-pipeline.md` for `V-Z1` to `V-Z5`.
- [X] T097 [US4] Run quickstart §6 on the local stack, then the backend gates in `backend/`:
  `uv run pytest -n 4 --cov --cov-fail-under=80`, `uv run mypy .`, `uv run ruff check . && uv run
  ruff format --check .`, `uv run manage.py makemigrations --check --dry-run`, and the OpenAPI
  regeneration, whose diff must be empty.

**Checkpoint**: Staging can build and publish with the real stage. B04's live checks are unblocked
once this is deployed.

---

## Phase 7: User Story 5 - Preview one trip in the admin while writing it (Priority: P5)

**Goal**: The "Run the solver" button, the `solve_trip` job and the "Solver preview" panel on
staging's trip page, one preview per trip at a time, and no change to any content (spec US5, FR-034
to FR-038; contracts/content-pipeline.md §6).

**Independent Test**: On the local stack, preview `line_hay.01`: solved, a score within 0–30, and a
timeline with each delivery. Empty its tray and preview again: not solved, naming the passenger and
the station. The trip, its `rev` and the pack list are unchanged (quickstart §7).

### Tests for User Story 5 ⚠️ (write first, must fail)

- [X] T098 [P] [US5] Write `backend/apps/content/tests/test_solver_preview.py` (contracts/
  content-pipeline.md §6), running the job eagerly:
  - **who:** a staff user with `content.change_trip` sees the button and can POST
    `admin/content/trip/<pk>/solve/`; one without it sees no button and gets 403; a POST without a
    CSRF token is refused (US5 scenario 1);
  - **where:** with `CONTENT_ROLE=target`, there's no button and no panel, and the POST is refused
    (US5 scenario 4, FR-038);
  - **one at a time:** a second POST while a preview is `queued` or `running` creates no run and
    redirects with "A preview is already running." (US5 scenario 3);
  - **checks first:** a trip that fails `document_findings("trip", …)` gives a `failed` run with
    `{"findings": […]}`, and `solve` isn't called (monkeypatched to fail if it is; US5 scenario 2);
  - **the panel:** for a done run, the verdict and end, the stars, each input's value and points,
    the line's current band and whether the score is in it, `settings_version` and the timeline
    rows; for a failed one, the findings or the stop reason; and "This preview is for an earlier
    version of the trip." once the trip's `input_key` differs. Changing only the line's band
    changes the panel's band check without a new preview;
  - **no clock-dependent reuse:** a preview whose `solve` ends `safety_cap` (monkeypatched) is
    stored `failed`, and a build afterwards solves that trip again instead of reusing it;
  - **nothing changes:** the `Trip` row and its `rev`, every authoring model, the `ContentPack`
    count and the audit log are the same before and after (US5 scenario 5, FR-037);
  - **the job:** a redelivered `solve_trip` on a `running` or finished run changes nothing; the
    task is on the `content` queue with `bind=True`, `acks_late=True`,
    `reject_on_worker_lost=True`, `autoretry_for=(OperationalError,)`, `retry_backoff=True` and
    `max_retries=3`;
  - `requested_by` appears nowhere but the run's row.

### Implementation for User Story 5

- [X] T099 [US5] Create `backend/apps/content/services/preview.py`:
  - `request_preview(trip, user)` creates `SolverRun(kind=preview, status=queued, trip=…,
    requested_by=…)` with `input_key` from `snapshot.trip_part(trip)` and the line's
    `bundled_params`, and queues `content.tasks.solve_trip` on commit; an `IntegrityError` from
    `solverrun_one_active_preview` returns the running preview instead;
  - `run_preview(run_pk)` refuses a run that isn't `queued`, sets `running`, and runs
    `document_findings("trip", …)`. It then saves `failed` with the findings and `finished_at`, or
    the `solve(…)` result through `finish_run` (T090), so a `safety_cap` or `internal_error` result
    is stored `failed`, as in builds.
- [X] T100 [US5] Add `solve_trip(self, run_pk)` to `backend/apps/content/tasks.py`, with the options
  of contracts/content-pipeline.md §6, calling `preview.run_preview`.
- [X] T101 [US5] Update `TripAdmin` in `backend/apps/content/admin/authoring.py`:
  - `get_urls()` adds `<pk>/solve/` (POST only, `admin_site.admin_view`, `on_source()` and
    `content.change_trip` checked again);
  - the view calls `request_preview` and redirects back with "The solver is running. Reload this
    page in a minute." or "A preview is already running.";
  - `change_view` puts the latest preview, whether it is active, and whether its `input_key` is
    still current into the context; `change_form_template` points to T102's template.
- [X] T102 [US5] Create `backend/apps/content/templates/admin/content/trip/change_form.html`,
  extending the admin's change form: the "Run the solver" button in the object tools (disabled
  with "Running since HH:MM" while a preview is active), and the "Solver preview" panel of
  contracts/content-pipeline.md §6. Amounts are integer piasters, and the text is English. Passes
  T098 with T099–T101.
- [X] T103 [US5] Run quickstart §7 on the local stack.

**Checkpoint**: Authors see a trip's verdict, score and timeline without building a pack.

---

## Phase 8: User Story 6 - CI re-solves published and sample content, and the engine replays the solver's runs (Priority: P6)

**Goal**: The Python fixture writer, the five `solver__` fixtures and their Dart expectations, and
the CI steps that re-solve the sample and `content/source` (spec US6, FR-012, FR-013, FR-039 to
FR-041; contracts/mirror.md §6; research R4, R16).

**Independent Test**: `fvm dart run tool/fixtures.dart check` and `fvm dart test test/fixtures`
pass with the five `solver__` fixtures, and `uv run wassal-solver parity ../../fixtures/parity`
prints `ok 60`. Raising `trip_hop_ms_line_hay` to 30000, then `sync`, makes `check-source` fail
on a sample trip (quickstart §4, §5).

### Tests for User Story 6 ⚠️ (write first, must fail)

- [X] T104 [P] [US6] Write the fixture-writer tests (contracts/mirror.md §5–§6, contracts/cli.md):
  - `tools/solver/tests/engine/test_fixture_build.py`: `build_fixture` gives exactly the five keys;
    its `seed` is the trip's own, its `params` are `bundled_params(line_id).to_json()`, its
    `command_log` is the solver's run, and its `expected_result` equals `replay(…).to_json()`;
  - `tools/solver/tests/test_fixture_files.py`: `write_fixture` writes the keys sorted, with a
    two-space indent, `ensure_ascii=False` and a trailing newline, and refuses an existing file;
  - `tools/solver/tests/cli/test_fixture.py`: `fixture <trip.json> --out <tmp>` writes
    `solver__<trip_id with "." → "_">.json`; an existing file is never overwritten (exit 1); a
    trip that isn't solved writes nothing (exit 1).
- [X] T105 [P] [US6] Write the Dart side first (FR-013), in `packages/trip_engine/test/fixtures/`:
  - `expectations/solver.dart` with `solverExpectations`, one entry per
    `solver__line_hay_01.json` … `solver__line_gamaa_02.json`, each asserting 3 stars,
    `fights == 0`, no mistakes and no boosters used;
  - `fixture_expectations_test.dart` imports it and spreads `...solverExpectations`;
  - `fixture_coverage_test.dart` adds: each of the 5 sample trips has a `solver__` fixture with 3
    stars.

  `fvm dart test test/fixtures` must fail until T107 (expectations without files).

### Implementation for User Story 6

- [X] T106 [US6] Implement the writer, to pass T104:
  - `build_fixture(definition, params, run)` in
    `tools/solver/src/wassal_solver/engine/fixture.py`, with no I/O;
  - `write_fixture(path, document)` in `tools/solver/src/wassal_solver/fixture_files.py`;
  - the `fixture TRIP.json… [--out DIR]` command in `tools/solver/src/wassal_solver/cli.py`, with
    `DIR` defaulting to `../../fixtures/parity`.
- [X] T107 [US6] Write the solver fixtures: `uv run wassal-solver fixture
  ../../content/examples/sample/trips/*/*.json` writes the five `fixtures/parity/solver__*.json`.
  Then, in `packages/trip_engine`, `fvm dart run tool/fixtures.dart check`, `fvm dart run
  tool/fixtures.dart show` on each (read it before committing) and `fvm dart test test/fixtures`
  all pass, and in `tools/solver`, `parity` prints `ok 60`. A Dart mismatch is a mirror or engine
  bug, handled as in Organization, "Fixtures".
- [X] T108 [P] [US6] Document the `solver` area:
  - `fixtures/parity/README.md`: the `solver__<trip>` row in the area table, the Python commands
    (`wassal-solver parity`, `wassal-solver fixture`), and that only Dart's `update` rewrites an
    existing `expected_result`;
  - `specs/004-m01-trip-engine/contracts/replay-and-fixtures.md` §5: the `solver` row, marked
    "(B05)".
- [X] T109 [US6] Add the steps `uv run wassal-solver check-source ../../content/examples/sample
  --bands error` and `uv run wassal-solver check-source ../../content/source --bands warning` to the
  `solver` job in `.github/workflows/backend.yml`, after `parity` (contracts/ci-checks.md).
- [X] T110 [US6] Check FR-039 once, as in quickstart §5: raise `trip_hop_ms_line_hay` in
  `apps/mobile/assets/config/tunables.json` to 30000, run `uv run wassal-solver sync`, then the
  sample `check-source`: a trip is `not_solved` and the command exits 1, naming it. Revert both
  files and confirm `sync --check` passes.

**Checkpoint**: CI re-solves everything on any change that could break a trip, and both engines
replay runs the solver found.

---

## Phase 9: User Story 7 - A balancing report for the designer (Priority: P7)

**Goal**: `wassal-solver report`, with slower players at 900 and 1,200 ms, as a table and as CSV
(spec US7, FR-043, FR-044; contracts/solver.md §6; research R17).

**Independent Test**: `uv run wassal-solver report ../../content/examples/sample --csv
/tmp/balance.csv` prints five rows in pack order with every column, and a second run gives
identical output (quickstart §8).

### Tests for User Story 7 ⚠️ (write first, must fail)

- [X] T111 [P] [US7] Write `tools/solver/tests/report/test_balancing.py` and
  `tools/solver/tests/cli/test_report.py` (data-model.md "Balancing report row"):
  - over the sample layout and over a `pack.json.gz` built from it with
    `wassal_content.packfile.build_pack_file`: one row per trip in pack order, with the columns
    `trip_id, verdict, stars, score, owed_at_once, change_pieces, blockers, breaks, tightness_ms,
    variety, slack_ms (station:ms;…), r900_stars, r900_fights, r900_mistakes, r1200_stars,
    r1200_fights, r1200_mistakes` (US7 scenario 1);
  - the `r<ms>_*` columns follow `report_reaction_ms`: with `[700]` there are only `r700_*`
    columns (US7 scenario 2);
  - two runs give byte-identical table output and CSV files (US7 scenario 3);
  - `report_reaction_ms` is read nowhere outside `src/wassal_solver/report/` and `settings.py` (an
    `ast` scan), so slower players stay out of builds, previews and CI (FR-043);
  - the command always exits 0, and 2 on a usage error.

### Implementation for User Story 7

- [X] T112 [US7] Implement `tools/solver/src/wassal_solver/report/balancing.py`: `report(trips,
  settings)` returning the rows of contracts/solver.md §6, each slower player a fresh
  `solve` with `dataclasses.replace(settings, reaction_ms=…)`, plus a fixed-width table renderer
  and a CSV writer (`csv` module, `lineterminator="\n"`).
- [X] T113 [US7] Implement `report LAYOUT | PACK.json.gz [--csv FILE]` in
  `tools/solver/src/wassal_solver/cli.py`, reading a pack file with
  `wassal_content.packfile.decompress_capped` and `wassal_content.loader.load_json_bytes`. Passes
  T111.

**Checkpoint**: The owner can order a line's trips by score and see how slower players fare.

---

## Phase 10: Polish & Cross-Cutting Concerns

**Purpose**: The bench corpus and its digest (SC-005, SC-007), the performance and memory budgets
(SC-008, FR-047), the coverage gates, the documents and owner actions (FR-052), and the final
checks.

- [X] T114 [P] Create the bench corpus (research R17):
  - `tools/solver/scripts/make_bench.py` (not packaged) derives 50 trips from the five sample trips
    with seeded variations (more passengers, tighter trays, shifted stations), 25 per MVP line;
  - the ids are `line_hay.51` to `line_hay.75` and `line_gamaa.51` to `line_gamaa.75`. Trip ids
    must match `<line_id>.<nn>` (`TripId` in `content/schemas/common.schema.json`), and 51 and up
    stay clear of the sample's ids;
  - run it once and commit `tools/solver/src/wassal_solver/data/bench/*.json`;
  - write `tools/solver/tests/test_bench.py`: there are exactly 50 files, both lines appear, every
    file passes `document_findings("trip", …)`, no id is also a sample trip's id, and running the
    script again rewrites identical bytes.
- [X] T115 Implement `bench [--digest]` in `tools/solver/src/wassal_solver/cli.py` (each trip's time
  and the total, then `digest <sha256>` over the canonical results in corpus order), with a test in
  `tools/solver/tests/cli/test_bench.py` that the digest is identical across two runs. Add
  `uv run wassal-solver bench --digest` as the last step of the `solver` job in
  `.github/workflows/backend.yml`. If the PR's `solver` job then takes over 10 minutes (SC-011),
  move that step to a `workflow_dispatch`-only job, as contracts/ci-checks.md "Timing" allows.
- [X] T116 [P] Write `tools/solver/tests/perf/test_budgets.py` (SC-008, FR-047, research R14):
  - `fixtures/parity/stress__longest_trip.json` replays in under 5 s;
  - a 90-second sample trip replays in under 0.5 s;
  - `tracemalloc` peak during a full-budget solve of `tests/data/faults/change_impossible.json`
    stays under 64 MB.
- [X] T117 Calibrate the effort budget (research R8, R19): from T072's numbers and `bench`, set
  `effort_budget_steps` in `src/wassal_solver/data/settings.json` so that a full-budget search costs
  about 30 s on the staging host (estimated from the CI runner's speed until the owner measures it),
  and every sample and bench trip that is solvable is still solved. Update the estimates in
  research.md R19 if they moved.
- [X] T118 Run the coverage gates: in `tools/solver`, `uv run pytest -n 4 --cov --cov-fail-under=80`
  then `uv run coverage report --include='*/wassal_solver/engine/*' --fail-under=90`; in `backend`,
  `uv run pytest -n 4 --cov --cov-fail-under=80`. Add tests for any uncovered branch until both
  pass. Don't exclude files.
- [X] T119 [P] Update the architecture docs (FR-052, research R18):
  - `docs/architecture-backend.md` §10: what the mirror covers (state and results, not events or
    speech), the idealized player and its timing, the search and its ends, the score's inputs, the
    stage with `V-Z1` to `V-Z5` and reuse, the preview, and §10.3's Dart fallback now for replay
    only;
  - `docs/architecture-backend.md` §9.1: a solver warning doesn't block publishing or promotion;
  - `docs/architecture-mobile.md` §7.10: `tools/solver` exists, and the Dart and Python suites are
    both required.
- [X] T120 [P] Update `CLAUDE.md`:
  - "Project status" adds `tools/solver/` (B05), and the architecture tree no longer says
    `tools/solver/` arrives with B05;
  - a "Solver commands" table (in `tools/solver`): `uv sync`, lint and types, tests with both
    coverage gates, `sync [--check]`, `parity`, `fixture`, `solve`, `check-source`, `report` and
    `bench`;
  - a rule change now edits `RULES.md`, both engines and the fixtures, and the parity bullet no
    longer says "until B05 creates `tools/solver`";
  - the backend notes: `CONTENT_SOLVER_STAGE` defaults to `solver` on staging and prod.
- [X] T121 [P] Update `content/source/README.md` (CI re-solves every trip on each change, FR-039) and
  complete `tools/solver/README.md` (what it is, the commands, the settings file, the
  fingerprints, and that a solver change changes `solver_fingerprint`, so nothing stale is
  reused).
- [X] T122 [P] Add the B05 section to `docs/owner-actions.md` (research R18):
  - **Before merge:** none;
  - **After merge:**
    1. deploy production with this release before the first promotion of a pack that carries a
       solver warning;
    2. on staging, run `docker compose … exec worker wassal-solver bench --digest`: the digest
       equals the one in the CI log of the merge commit (SC-005), and the total is under 30
       minutes (SC-007);
    3. preview `line_hay.01` on staging: the result appears within 60 s (SC-006);
    4. build and publish the sample pack on staging, with a `passed` or `warning` solver stage and
       a result for every trip (SC-012), then walk B04's T107 items 3–7;
  - add the B05 row to the "Open now" table, and point B04's "After B05" section to step 4;
  - in `docs/delivery-plan.md`'s Progress, note under `005-b05-solver-parity` what it resolved.
    Tick it when the PR merges.
- [X] T123 Run every check in [quickstart.md](./quickstart.md), §1–§9:
  - `tools/solver`: ruff, the format check, mypy, pytest with both gates, `sync --check`, `parity`
    (`ok 60`) and both `check-source` runs;
  - `packages/trip_engine`: format, `analyze --fatal-infos`, tests and the 90% gate, and
    `tool/fixtures.dart check`;
  - `tools/content_kit`: `codegen --check`, `validate-source`, `golden`, ruff, mypy and pytest;
  - `backend`: the gates of T097.

  All pass.
- [X] T124 Review:
  - run the `code-reviewer` agent on the whole diff and the `python-reviewer` on `tools/solver`
    and `backend`;
  - run the `security-reviewer` on `replay_untrusted` (B08 will feed it player input) and on the
    preview's POST view;
  - check every changed file against constitution I, II, III, VI, VII, VIII and XIII;
  - fix every CRITICAL and HIGH finding.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies. T001 comes first, then T002–T004 in parallel.
- **Foundational (Phase 2)**: Depends on Setup, and blocks every story.
  - T005–T012 (tests) are parallel.
  - T013–T016 are parallel. T017 needs T013. T018 needs T014, T016 and T017. T019 needs T015, T017
    and T018. T020 needs T014.
- **US1 (Phase 3)**: After Foundational.
  - T021–T033 (tests) are parallel.
  - T034–T043 are parallel. Then T044, T045 and T046 in that order, then T047, T048, T049, T050 and
    T051.
  - T052 can be written any time in the phase. T053 needs T047. T054 and T055 come last.
- **US2 (Phase 4)**: After US1. The solver plays trips through the mirror.
  - T056–T063 (tests) are parallel.
  - T064 and T065 are parallel. Then T066, T067, T068, T069, T070, T071 and T072 in order.
- **US3 (Phase 5)**: After US2. The score is computed from a solved run.
- **US4 (Phase 6)**: After US3. The stage needs `solve` with the band check.
  - T082–T087 (tests) are parallel.
  - T088, then T089, T090 and T091 in order. T092, T093 and T094 are parallel with them. T095
    needs T091. T096 any time. T097 last.
- **US5 (Phase 7)**: After US4, which adds `SolverRun`.
- **US6 (Phase 8)**: After US3, which adds `check-source`. It can run in parallel with US4 and US5.
- **US7 (Phase 9)**: After US3. It can run in parallel with US4, US5 and US6.
- **Polish (Phase 10)**: After every story. T115 needs T114. T117 needs T072 and T115. T118 after
  every test exists. T123 and T124 come last.

### User Story Dependencies

```text
Setup → Foundational → US1 → US2 → US3 ─┬─> US4 → US5
                                        ├─> US6
                                        └─> US7
```

Each story is still testable on its own once its predecessors exist: US1 by `parity`, US2 by
`solve`, US3 by `check-source`, US4 by a local build, US5 by a preview, US6 by the Dart fixture
check, and US7 by `report`.

### Within Each User Story

- Tests are written first and must fail, then implementation.
- `engine/rules/step.py`, `engine/rules/command_handlers.py`, `cli.py`,
  `backend/apps/content/services/build.py` and `.github/workflows/backend.yml` are edited by one task
  at a time.
- A sample trip that has to change (T072, T081) is changed with every file that copies it, in the
  same commit.

### Parallel Opportunities

- Setup: T002–T004.
- Foundational: T005–T012, then T013–T016, and T020.
- US1: T021–T033, then the ten rules modules T034–T043, and T052 at any time.
- US2: T056–T063, then T064 and T065.
- US3: T073–T077.
- US4: T082–T087, then T092–T094 next to T088–T091.
- After US3, three tracks: US4 then US5 (backend), US6 (fixtures and CI), and US7 (report).
- Polish: T114, T116 and T119–T122.

---

## Parallel Example: User Story 1

```bash
# Write the US1 tests together (all different files):
Task: "Write tools/solver/tests/parity/test_fixtures.py"
Task: "Write tools/solver/tests/engine/rules/test_chain.py (§5)"
Task: "Write tools/solver/tests/engine/rules/test_fares.py (§6.1–§6.4)"
Task: "Write tools/solver/tests/engine/rules/test_change.py (§6.5)"
Task: "Write tools/solver/tests/engine/rules/test_stations.py (§9, §11)"
Task: "Write tools/solver/tests/engine/commands/ (one module per Dart file)"
Task: "Write tools/solver/tests/engine/archetypes/ (one module per Dart file)"
Task: "Write tools/solver/tests/engine/events/ (one module per Dart file)"
Task: "Write tools/solver/tests/engine/test_replay_untrusted.py"

# Then the independent rules modules together:
Task: "Implement engine/rules/chain.py"
Task: "Implement engine/rules/fares.py"
Task: "Implement engine/rules/change.py"
Task: "Implement engine/rules/reputation.py"
Task: "Implement engine/rules/passengers.py"
Task: "Implement engine/rules/aids.py"
```

## Parallel Example: After User Story 3

```bash
# Three tracks at once:
Task: "US4 T082–T097: SolverRun, the real stage, reuse, heartbeat, guards (backend)"
Task: "US6 T104–T110: fixture writer, solver__ fixtures, Dart expectations, CI re-solve"
Task: "US7 T111–T113: the balancing report"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1 (Setup), then Phase 2 (Foundational).
2. Phase 3 (US1): the mirror reproduces all 55 fixtures, and CI checks parity in both languages.
3. **Stop and validate**: `uv run wassal-solver parity ../../fixtures/parity` prints `ok 55`, and
   the SC-002 check of T055 turns each engine red. This alone meets the first half of the delivery
   plan's "done when".

### Incremental Delivery

1. Add US2 and US3: the solver and the score, checked from the command line.
2. Add US4: staging can build and publish, the second half of "done when".
3. Add US5: the authors' preview.
4. Add US6 and US7: the solver fixtures, CI's re-solve, and the balancing report.
5. Polish: the bench, the budgets, coverage, documents, owner actions and review. Then the one PR.

### Notes

- `[P]` tasks touch different files and have no unfinished dependencies.
- Never write a balancing number in the mirror: every number comes from `TripParams`. Every solver
  number comes from `data/settings.json` (FR-045).
- Never edit a generated file, and never hand-edit `src/wassal_solver/data/tunables.json`: run
  `wassal-solver sync`.
- When a rule turns out ambiguous while porting, read the Dart code and its fixture. If they
  disagree with `RULES.md`, settle it in `RULES.md` first, then fix both engines (constitution III).
