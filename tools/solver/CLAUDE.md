# tools/solver/CLAUDE.md

The Python solver from **B05** (`specs/005-b05-solver-parity/`): a mirror of the trip rules (`src/wassal_solver/engine/`), the solver (an idealized player that must earn 3 stars), the difficulty score, the balancing report and the bench. The backend runs it as the content pipeline's solver stage and the admin's trip preview. The project-wide rules are in the root `CLAUDE.md`; the engine it mirrors is `packages/trip_engine/` (its `RULES.md`).

## Commands

`tools/solver` is the uv project `wassal-solver` (Python pinned by its `.python-version`). Run everything from `tools/solver`. CI runs the same commands in the backend workflow's `solver` job.

| Purpose | Command (in `tools/solver`) |
| --- | --- |
| First setup | `uv sync` |
| Lint, format check, types | `uv run ruff check . && uv run ruff format --check . && uv run mypy .` |
| Tests + both coverage gates (80%, and 90% for the mirror) | `uv run pytest -n 4 --cov --cov-fail-under=80 && uv run coverage report --include='*/wassal_solver/engine/*' --fail-under=90` |
| Time and memory budgets (skipped under coverage) | `uv run pytest tests/perf -q` |
| Copy the app's tunables / check the copy | `uv run wassal-solver sync` / `uv run wassal-solver sync --check` |
| Replay every parity fixture through the mirror | `uv run wassal-solver parity` |
| Write a solver fixture from a trip's 3-star run | `uv run wassal-solver fixture <trip.json>... [--out DIR]` |
| Solve a trip or a layout | `uv run wassal-solver solve <trip.json \| layout> [--trip ID] [--json] [--reaction-ms N]` |
| Re-solve every trip of a layout | `uv run wassal-solver check-source <layout> [--bands error\|warning]` |
| Balancing report | `uv run wassal-solver report <layout \| pack.json.gz> [--csv FILE]` |
| Bench corpus and its digest | `uv run wassal-solver bench --digest` |

- The solver's settings (reaction and tap times, the effort budget, the safety cap, the score's table) are in `src/wassal_solver/data/settings.json`. Changing them changes `settings_version`.
- Any change to the package's code or data changes `solver_fingerprint`, so the backend solves every trip again instead of reusing a stale result.
- `fixture` never overwrites a file, and Python never rewrites an `expected_result`: only Dart's `tool/fixtures.dart update` does.
- After a `tools/solver` change, run `uv sync --reinstall-package wassal-solver` in `backend/` (and rebuild the dev image) so the backend uses it.
