# wassal-solver

The solver and parity package of B05 (`specs/005-b05-solver-parity/`):

- **the mirror** (`engine/`): the Python copy of the trip rules in `packages/trip_engine/RULES.md`.
  It reproduces every step's state and the `TripResult` exactly, but emits no events or speech;
- **the solver** (`solver/`): an idealized player who reacts in 600 ms, taps 198 ms apart, gives
  exact change only and uses no aids. It searches for a 3-star run, or reports why there is none:
  who lost a star, where and when;
- **the difficulty score** (`scoring/`): 0–100, from six inputs of the 3-star run;
- **the balancing report** (`report/`) and the bench corpus (`data/bench/`).

The backend installs it as a path dependency and calls it in-process: the content pipeline's
solver stage and the admin's trip preview (`backend/apps/content`). It depends only on the standard
library and the content kit, so CI runs it without a database.

The contracts are in [specs/005-b05-solver-parity/contracts/](../../specs/005-b05-solver-parity/contracts/):
`mirror.md`, `solver.md`, `cli.md`, `content-pipeline.md` and `ci-checks.md`.

## Commands

Run from `tools/solver`, after `uv sync`.

| Purpose | Command |
| --- | --- |
| Lint, format check, types | `uv run ruff check . && uv run ruff format --check . && uv run mypy .` |
| Tests and both coverage gates | `uv run pytest -n 4 --cov --cov-fail-under=80 && uv run coverage report --include='*/wassal_solver/engine/*' --fail-under=90` |
| Time and memory budgets | `uv run pytest tests/perf -q` (skipped under coverage, which slows the mirror) |
| Copy the app's tunables, or check the copy | `uv run wassal-solver sync [--check]` |
| Replay the parity fixtures | `uv run wassal-solver parity [PATH...]` |
| Write `solver__<trip>.json` fixtures | `uv run wassal-solver fixture TRIP.json... [--out DIR]` |
| Solve a trip, or every trip of a layout | `uv run wassal-solver solve TRIP.json \| LAYOUT [--trip ID] [--json] [--reaction-ms N]` |
| Re-solve a layout, as CI does | `uv run wassal-solver check-source LAYOUT [--bands error\|warning]` |
| The balancing report | `uv run wassal-solver report LAYOUT \| PACK.json.gz [--csv FILE]` |
| Solve and time the bench corpus | `uv run wassal-solver bench [--digest]` |

`scripts/make_bench.py` rewrites the bench corpus. It is seeded, so running it again gives the
same bytes.

## Settings

`src/wassal_solver/data/settings.json` holds every number the solver uses:

- the player's `reaction_ms` and `tap_ms`;
- the search's `effort_budget_steps` (mirror steps per trip, so verdicts don't depend on the
  host's speed), `safety_cap_seconds` (a wall-time guard) and `transposition_cap`;
- `report_reaction_ms`, the slower players of the balancing report, used nowhere else;
- `score`, the table of the difficulty score.

`src/wassal_solver/data/tunables.json` is a copy of the app's tunables, for the bundled params.
`sync` writes it, and CI fails if it differs from the app's.

## Fingerprints

Every result carries three:

- `settings_version`: a hash of the settings;
- `solver_fingerprint`: a hash of the package's code and data, and of the content kit's
  `capabilities.json`;
- `params_fingerprint`: a hash of the params the trip was solved with.

The backend reuses a stored result only when the `input_key` matches, a hash of the trip
(without its `rev`), the params and `solver_fingerprint`. So any change to the solver, even a
comment, gives a new fingerprint, and nothing stale is reused: the next build solves every trip
again.

## Fixtures

`fixture` never overwrites a file, and Python never rewrites an existing fixture. Only Dart's
`fvm dart run tool/fixtures.dart update` recomputes an `expected_result`
(`fixtures/parity/README.md`).
