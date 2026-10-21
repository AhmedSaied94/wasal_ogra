# Contract: The Solver Stage, Reuse and the Trip Preview (`backend/apps/content`)

How B05 plugs into B04's pipeline (research R13, R14). B04's own contracts are in
`specs/003-b04-content-pipeline/contracts/`. The edits made to them are listed in §8.

## 1. The stage interface (`services/stages.py`)

```python
@dataclass(frozen=True)
class SolverOutput:
    findings: list[Finding]          # V-Z1..V-Z5, stage "solver"
    trips: list[dict[str, Any]]      # one summary per trip, pack order (§3)
    meta: dict[str, Any]             # solver_fingerprint, settings_version, solved, reused

class SolverStage(Protocol):
    def run(self, pack: Mapping[str, Any], progress: Callable[[], None]) -> SolverOutput | None: ...
```

| Stage | `CONTENT_SOLVER_STAGE` | Returns |
| --- | --- | --- |
| `NoSolver` | `none` | `None`, so the stage is `not_available` |
| `StandInSolver` | `stand_in` (dev and test only) | `SolverOutput([], [], {"stand_in": True})` |
| `apps.content.services.solver_stage.SolverStage` | `solver`, or that dotted path | The real results |

`produce()` passes a `progress` callback. During a real build it runs
`ContentPack.objects.filter(pk=…).update(updated_at=now())`. During `content_build --dry-run`, it
does nothing.

## 2. The real stage

For each trip of `pack["trips"]`, in order:

1. `line = pack line with line_id`, `params = bundled_params(trip.line_id)`.
2. `key = input_key(trip, params)` (data-model.md "Fingerprints").
3. If a `SolverRun` with `input_key = key` and `status = done` exists, reuse its `result`
   (`reused: true`). Otherwise, create a `SolverRun(kind=build, status=running)`, call `solve(…)`,
   and save the result with `finish_run` (§5).
4. Call `progress()`.
5. Map the result to findings:

   | Result | Finding |
   | --- | --- |
   | `verdict = not_solved`, `end` ∈ `exhausted`, `budget_spent` | `V-Z1` error |
   | `verdict = refused` | `V-Z2` error |
   | The line has no params in the bundled tunables (a new line the app doesn't ship yet); the trip isn't solved | `V-Z2` error: "the trip is refused: the app's tunables have no params for `<line_id>` (…)" |
   | `end = safety_cap` | `V-Z3` error |
   | `end = internal_error` | `V-Z4` error, plus `logger.exception` with the trip id |
   | `solved` and `in_band(score.value, line.difficulty_band)` is false | `V-Z5` warning |

   Every finding has `stage="solver"`, `entity="trip"`, `id=trip_id` and `path="$.trips[<i>]"`.
   The messages are in data-model.md "Finding codes".

   The band check always uses the line in this pack, even for a reused result. `input_key` doesn't
   cover the band, so a rebuild after a band change reuses every result and checks them all against
   the new band.

`Report.add_stage("solver", findings)` then derives the result:

- `failed` with any error;
- `warning` with only `V-Z5` findings;
- `passed` otherwise.

## 3. The validation report and the release record

- **The validation report.** `report_dict` writes `stages.solver.trips` and `stages.solver.meta`
  next to `result`. The trip summary is in data-model.md "Validation report additions", with the
  score's six input values (spec FR-030).
- **The release record.** `services/release.release_record` adds a `solver` object (data-model.md
  "Release record addition"), built from `stages.solver` with these fields only: `trip_id`, `rev`,
  `verdict`, `stars`, `score`, `band`, `params_fingerprint` and `run_hash`. The score's inputs
  stay in the report.
  - The record stays under `MAX_RELEASE_BYTES` (64 KB). A test builds a 200-trip summary and checks
    it fits.
  - `warnings` lists the `V-Z5` findings, as it lists `size` warnings today.

## 4. Publish and promotion guards

| Where | Before (B04) | Now (B05) |
| --- | --- | --- |
| `services/publish.check` | solver `== "passed"` | solver `in ("passed", "warning")` |
| `services/promote._passed` | solver `== "passed"`, others `passed` or `size: warning` | solver `in ("passed", "warning")`, others unchanged |
| `services/build.is_green` | unchanged | unchanged: `warning` already counts as green |

A pack whose solver stage is `failed` or `not_available` is still refused at both. The refusal
messages are unchanged.

## 5. Reuse and the heartbeat

- **Reuse** reads `SolverRun.objects.filter(input_key=key, status="done")
  .order_by("-finished_at", "-created_at")`, taking the first row, whether it came from a build, a
  dry run or a preview. A dry run saves no pack, but keeps its runs, so the next build reuses them.
- **Finishing a run.** `finish_run(run, result)` in `services/solver_stage.py` saves `result` and
  `finished_at`, and sets `status`:
  - `failed` when `end` is `safety_cap` or `internal_error`;
  - `done` otherwise.

  The stage and the preview job both finish runs through it. So reuse, which reads only `done`,
  never picks up a result that depended on the clock (the safety cap) or on a bug.
- **The first end saved stays.** A run ends with one conditional update on a row that is still
  `queued` or `running` (`end_run`). If the sweep failed it first, it stays failed, and a finished
  run is never swept. Postgres's row lock orders the two updates.
- **The sweep.** `sweep_stuck_builds` keeps its 30-minute `updated_at` cut-off, which the heartbeat
  now refreshes. Its message becomes `the build stopped: no progress for 30 minutes`.
- **The sweep also stops runs.** `SolverRun`s still `running` or `queued` with `updated_at` older
  than 30 minutes become `failed`, with `result = {"error": "stopped: no progress for 30
  minutes"}`.

## 6. The trip preview (admin)

**Where.** On the `Trip` change page in staging's admin. Not offered when `CONTENT_ROLE=target`.

| Element | Shown when | Behavior |
| --- | --- | --- |
| **"Run the solver"** button (object tools) | `on_source()` and `user.has_perm("content.change_trip")` | A POST to `admin/content/trip/<pk>/solve/` (CSRF-protected, staff-only, the same checks) creates `SolverRun(kind=preview, status=queued, trip=…, requested_by=…)` from `snapshot.trip_part(trip)` and the line's bundled params, queues `content.tasks.solve_trip`, and redirects back with the message "The solver is running. Reload this page in a minute." |
| Button disabled, "Running since HH:MM" | an active preview exists for this trip | A second POST makes no new run (the unique constraint), and redirects with "A preview is already running." |
| **"Solver preview"** panel | the trip's latest preview, on `source` | The status. When done: the verdict and end, the stars, the score with each input's value and points, the trip's line band as it is now (and whether the score is in it), `settings_version`, and the timeline table (`t`, decision, passenger, amount and pieces, note). When failed: the findings, or the stop reason. When the trip's current `input_key` differs: the note "This preview is for an earlier version of the trip." |

**The job** `content.tasks.solve_trip(run_pk)`:

- runs on the `content` queue, with `bind=True`, `acks_late=True`, `reject_on_worker_lost=True`,
  `autoretry_for=(OperationalError,)`, `retry_backoff=True` and `max_retries=3`;
- refuses a run that isn't `queued`;
- sets `running`;
- runs `document_findings("trip", definition)`. If there are errors, it saves `failed` with
  `{"findings": […]}`;
- if the line has no params in the bundled tunables, it saves `failed` with
  `{"error": "the app's tunables have no params for <line_id> (…)"}`;
- otherwise it calls `solve(…)` and saves the result with `finish_run` (§5).

A redelivered job finds the run `running` or finished, and changes nothing. Anything that stops the
job after it set `running` saves `failed`, so the trip can be previewed again at once: a trip
deleted meanwhile gives `{"error": "the trip no longer exists"}`, and anything else is logged and
gives `{"error": "the preview stopped on an internal error"}`. If the broker refuses the job, the
queued run is saved `failed` with `{"error": "the preview could not be queued"}`.

**Guarantees.**

- A preview never writes to `Trip`, any authoring model, `ContentPack` or the audit log.
- Amounts are shown in piasters, as integers, like the trip form. The page text is English, for
  staff.

## 7. Environment (`config/env.py`)

| Variable | Values | Default |
| --- | --- | --- |
| `CONTENT_SOLVER_STAGE` | `none`, `stand_in`, `solver`, or a dotted path | `solver` in strict environments (staging, prod), `stand_in` in dev and test |

- The settings check still refuses `stand_in` when strict.
- `SOLVER_STAGE_PATTERN` gains `solver`.
- Staging's and production's env files leave the variable unset.

## 8. Edits to B04's contracts (each marked "(B05)")

- `environment.md`: the `CONTENT_SOLVER_STAGE` row gets the `solver` value and the new strict
  default.
- `pack-delivery.md` "Release record":
  - a stage value may be `warning` for `size` or `solver`;
  - the record has a `solver` object;
  - "Publish on staging" step 1 reads "its solver stage `passed` or `warning`".
- `admin.md` "Validation report": the solver must be `passed` or `warning` before a publish.
- `content-schemas.md`: the `V-Z1` row points to this file for `V-Z1` to `V-Z5`.
