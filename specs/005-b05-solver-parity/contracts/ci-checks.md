# Contract: CI Changes (B05)

The pattern is the one B04 and M01 used: new steps inside the two required workflows, so branch
protection doesn't change (research R16).

## `.github/workflows/backend.yml`

**`changes` filter.** It adds `tools/solver/`, `packages/trip_engine/` and
`apps/mobile/assets/config/tunables.json`:

```text
^(backend/|contracts/|content/|fixtures/|tools/content_kit/|tools/solver/|packages/content_models/|packages/trip_engine/|apps/mobile/assets/config/tunables\.json$|\.dockerignore$|\.github/workflows/backend[^/]*\.yml$)
```

**New job `solver`** (`needs: changes`, runs when the filter matches, `ubuntu-24.04`, 20 minutes,
`working-directory: tools/solver`). Its steps:

| Step | Command |
| --- | --- |
| Install | `uv sync --locked` (setup-uv 0.13.1, cache on `tools/solver/uv.lock`) |
| Lint and format | `uv run ruff check .` and `uv run ruff format --check .` |
| Types | `uv run mypy .` (strict) |
| Tests and package coverage | `uv run pytest -n 4 --cov --cov-fail-under=80` |
| Mirror coverage | `uv run coverage report --include='*/wassal_solver/engine/*' --fail-under=90` |
| Time and memory budgets (SC-008, FR-047) | `uv run pytest tests/perf -q`, without coverage |
| The tunables copy | `uv run wassal-solver sync --check` |
| Parity | `uv run wassal-solver parity ../../fixtures/parity` |
| The sample solves inside its bands | `uv run wassal-solver check-source ../../content/examples/sample --bands error` |
| Published content still solves | `uv run wassal-solver check-source ../../content/source --bands warning` |
| The bench digest (SC-005) | `uv run wassal-solver bench --digest` |

- `pytest-xdist` joins the solver's dev group, with the backend's pin `pytest-xdist==3.8.0`.
- `tests/perf` skips itself while a tracer is active, because coverage makes the mirror about five
  times slower: the budgets are checked in their own step.
- The bench step's digest is printed to the log. The owner compares it with the staging host's
  (owner actions). It doesn't gate the merge.

**The `backend` summary job** adds `solver` to `needs`.

**The `test` job** is unchanged. `uv sync` now also installs `wassal-solver` through the path
dependency, and the backend tests that use the real stage run there.

## The image

- **`.dockerignore`** adds `!tools/solver/` and `tools/solver/tests`.
- **`backend/docker/Dockerfile`** adds a second bind mount to the builder's `uv sync`:
  `--mount=type=bind,source=tools/solver,target=/tools/solver`.
- **`backend/pyproject.toml`** adds `"wassal-solver"` to `dependencies` and
  `wassal-solver = { path = "../tools/solver" }` to `[tool.uv.sources]`, with the lock regenerated.
- **`tools/solver/pyproject.toml`** lists `data/*.json` and `data/bench/*.json` as hatch
  `artifacts`, as the content kit lists its copies, so the wheel ships them.

## `.github/workflows/mobile.yml`

Nothing changes:

- its filter already includes `fixtures/` and `packages/`;
- the Dart `packages` job replays the new `solver__` fixtures;
- the Dart `packages` job runs the `solver.dart` expectations.

## Timing (SC-011)

The `solver` job runs in parallel with `test`, `content-kit` and `image`. The budget is under 10
minutes:

| Part | Estimate |
| --- | --- |
| Install and lint | 1–2 min |
| Tests (property tests included) | 3–4 min, with 4 workers (2.5 min measured on an i5-10500H) |
| Time and memory budgets | 1.5–2 min (1.4 min measured: the full-budget solve under `tracemalloc`) |
| Parity | under 30 s |
| Re-solve the sample | under 1 min |
| Bench | under 1 min (20 s measured) |

If the bench pushes the job past 10 minutes, it moves to a `workflow_dispatch`-only job, and the
owner runs it by hand for SC-005.
