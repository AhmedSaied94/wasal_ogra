# Quickstart: Solver and Parity (B05)

How to check that B05 works, from a fresh checkout to the live checks on staging. The commands
follow `CLAUDE.md`. The formats are in [contracts/](./contracts/).

## Setup

```bash
cd tools/solver && uv sync                      # Python 3.13 from .python-version
cd ../../backend && uv sync                     # picks up wassal-solver as a path dependency
```

The local stack is optional, for the backend scenarios:
`docker compose -f docker/compose.yml -f docker/compose.dev.yml up -d --wait`, run in `backend/`.

## 1. Parity (US1, SC-001, SC-002)

```bash
cd tools/solver
uv run wassal-solver parity ../../fixtures/parity     # → ok 60 (55 from M01 + 5 solver fixtures)
uv run pytest tests/parity -q                         # the same, as tests
uv run pytest tests/engine/test_capabilities.py -q    # the mirror == capabilities.json
```

To check that CI catches a one-sided change (SC-002, done once before merge):

1. Change `rep_exact_change` handling in `src/wassal_solver/engine/rules/change.py`. `parity` then
   fails, naming the fixtures, the path and both values.
2. Revert it, then make the same change in `packages/trip_engine/lib/src/rules/change.py`.
   `fvm dart run tool/fixtures.dart check` now fails instead.
3. Revert both.

Untrusted replay (SC-009):

```bash
uv run pytest tests/engine/test_replay_untrusted.py -q
```

Every malformed input is refused with its reason, and the property test finds no exception that
escapes.

## 2. Solve a trip (US2, SC-003, SC-004)

```bash
uv run wassal-solver solve ../../content/examples/sample --trip line_gamaa.02
#   solved (found) · 3 stars · score 34 in 20–55 · timeline:
#   3.1 s  give_change  p1  100 (100×1)
#   …
uv run wassal-solver solve tests/data/faults/change_impossible.json
#   not_solved (exhausted) · best 2 stars · first fight at 70.0 s (p3, mostashfa)
uv run wassal-solver solve tests/data/faults/too_fast.json                     # not_solved
uv run wassal-solver solve tests/data/faults/too_fast.json --reaction-ms 100   # solved
uv run pytest tests/solver -q    # every fault kind, the ends, determinism, confirmation
```

## 3. Difficulty (US3)

```bash
uv run wassal-solver check-source ../../content/examples/sample --bands error   # exit 0
uv run wassal-solver solve tests/data/faults/hay_too_hard.json                   # score > 30, V-Z5
uv run pytest tests/scoring -q          # integer 0–100, monotonic, sample in band
```

## 4. Solver fixtures (US6, FR-041)

```bash
uv run wassal-solver fixture ../../content/examples/sample/trips/*/*.json   # writes 5 files once
cd ../../packages/trip_engine && fvm dart run tool/fixtures.dart check      # Dart replays them
fvm dart test test/fixtures                                                 # solver.dart expectations
```

## 5. CI's re-solve (US6, FR-039, FR-040)

```bash
cd tools/solver
uv run wassal-solver check-source ../../content/source --bands warning   # "no pack in …" today
```

To see it fail, temporarily raise `trip_hop_ms_line_hay` in `apps/mobile/assets/config/tunables.json`
to 30000, then run `uv run wassal-solver sync`, then the `check-source` of §3. `line_hay.01` is now
`not_solved`, and the command exits 1. Revert both files. (The `line_hay` sample trips are one hop
long with stops 30 s or more away, so they still solve with hops of 20 s.)

## 6. The stage in a build (US4, local stack)

```bash
cd backend
export CONTENT_SOLVER_STAGE=solver        # dev defaults to stand_in
uv run manage.py content_import ../content/examples/sample --actor <author>
# mark the sample's speech lines reviewed in the admin, or the review stage fails (B04)
uv run manage.py content_build --actor <builder>
```

On the pack's page:

- the solver stage `passed`, with five trips, each `solved` with its score;
- `meta.reused = 0`.

Build again: the report is identical, except for `reused = 5`. Publish works.

Then add a trip whose change can't be made, and build: the solver stage is `failed`, `V-Z1` names
the trip, and Publish is refused. Change a band so one trip is outside it: the stage is `warning`
with `V-Z5`, and Publish and the release record both work, with the warning listed. The unchanged
trips' results are reused, but the band is checked again at every build.

```bash
uv run pytest apps/content/tests/test_solver_stage.py apps/content/tests/test_solver_preview.py -q
```

## 7. The preview (US5, SC-006)

In the local admin (<http://localhost:8001/admin/>), open `line_hay.01` and click **Run the
solver**. Reload after a few seconds: the panel shows `solved`, the score within 0–30, and the
timeline. Change the tray to `100: 0, 50: 0` and `max_break_requests` to `0` (with a break left,
the player breaks a note and still solves it), save, and preview again: the panel shows
`not_solved`, naming the passenger and the station (`p1`, `madrasa`). The trip's `rev` and the pack list are
unchanged.

## 8. The balancing report (US7)

```bash
cd tools/solver
uv run wassal-solver report ../../content/examples/sample --csv /tmp/balance.csv
#   five rows, the r900_* and r1200_* columns included; running it twice gives identical output
```

## 9. Performance (SC-007, SC-008)

```bash
uv run pytest tests/perf -q         # longest replay < 5 s, 90 s trip < 0.5 s, memory < 64 MB
uv run wassal-solver bench --digest # time per trip, the total, and the digest
```

## After merge (owner actions, `docs/owner-actions.md` "005 B05")

1. Deploy production with this release before the first promotion of a pack that carries a solver
   warning.
2. On staging, run `docker compose … exec worker wassal-solver bench --digest`:
   - the digest equals the one in the CI log of the merge commit (SC-005);
   - the total is under 30 minutes (SC-007).
3. Import the sample on staging, if it isn't there yet, and preview `line_hay.01`. The result
   appears within 60 s (SC-006).
4. Build and publish the sample pack on staging. Its solver stage is `passed` or `warning`, with a
   result for every trip (SC-012). Then walk B04's T107 items 3–7.

## Done when (delivery plan, step 3)

- The Python suite reproduces every fixture, and CI fails on a mismatch (§1).
- Staging publishes only packs whose every trip was proven 3-star solvable (§6, and After merge 4).
