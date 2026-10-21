# Data Model: Solver and Parity (B05)

Every number below is an integer (constitution II). JSON is written in the canonical form of
`wassal_content.canonical`. Field names are snake_case on the wire and in Python.

## Inputs (unchanged, from M01)

| Type | Where it is defined | Notes for the mirror |
| --- | --- | --- |
| `TripDefinition` | `wassal_content.models` (generated) | Read with `parse("trip", …)` after `document_findings` passes. |
| `TripParams` | M01 data-model "TripParams" | Same 28 fields and bounds. Built by `from_json` (wire) or `from_tunables(values, line_id)`. |
| Command log | M01 replay-and-fixtures.md §1–§2 | `[t_ms, "Name", …args]`, at most 1,201 entries. |
| Parity fixture | M01 replay-and-fixtures.md §5 | Five keys. The new `solver` area is described below. |

## Mirror state

The mirror keeps the same fields as M01 data-model "State": `TripState`, `PassengerState`,
`MoneyToken`, `StationState`, the open choices and the counters. They live in
`@dataclass(slots=True)` classes that a step changes in place (research R2). Two things differ:

- **No event list and no PRNG state.** Events and speech are not mirrored (research R3).
- **`Trip.clone()`** returns an independent copy, field by field, for the solver's branches.

`TripResult` is M01's, field for field. `to_json()` gives the same JSON as Dart's
`TripResult.toJson()`, and that is what the parity check compares.

## Refusals

| Raised by | Type | Content |
| --- | --- | --- |
| `start` | `TripRefused` | `refusals: [{code, path, message}]`, with M01 data-model "Validation" codes (`bad_seed`, `bad_params`, `duplicate_id`, …). |
| `replay` | `ReplayRefused` | `reason` ∈ `trip_refused` (plus `refusals`), `t_ms_goes_down`, `clock_stopped` and `entry_rejected` (plus `index`, and `rejection` for the last), with Dart's messages (contracts/mirror.md §3). |
| `replay_untrusted` | `ReplayRefused` | Also `bad_input`, `bad_definition` (plus `findings`), `bad_params` and `bad_log` (plus `index`) (research R6). |

A rejection is one of M01's codes (`tray_empty`, `hand_empty`, `not_aboard`, `no_effect`,
`no_choice`, `bad_argument`, `undo_unavailable`, `break_limit`, `booster_limit`, `not_revivable`,
`cannot_make_change`, `wrong_status` and `command_limit`).

## SolverSettings (`wassal_solver/data/settings.json`)

| Field | Initial value | Meaning |
| --- | --- | --- |
| `reaction_ms` | 600 | The time before each decision, rounded up to the next step (research R7). |
| `tap_ms` | 198 | The gap between the commands of one decision. |
| `effort_budget_steps` | 1,500,000 | The mirror steps the search may simulate per trip. |
| `safety_cap_seconds` | 180 | The wall-time cap per trip. |
| `transposition_cap` | 100,000 | The most entries in the visited table. |
| `report_reaction_ms` | `[900, 1200]` | The balancing report's slower players. |
| `score` | contracts/solver.md §5 | `slack_ref_ms`, plus `{free, per, unit, cap}` for each input. |

- `settings_version` is the first 16 hex digits of the SHA-256 of the record's canonical JSON.
- Loading refuses unknown keys, missing keys, non-integers, and a `reaction_ms` or `tap_ms` that is
  negative.

## Fingerprints

| Name | Over | Form |
| --- | --- | --- |
| `solver_fingerprint` | Every `.py` and `.json` file in the installed `wassal_solver`, in sorted path order, plus the packaged `capabilities.json` | 16 hex digits |
| `params_fingerprint` | Canonical params JSON | 16 hex digits |
| `input_key` | Canonical `{"definition": <with rev = 0>, "params": …, "solver": solver_fingerprint}` | 64 hex digits |
| `run_hash` | The run's command log | `command_log_hash` (M01 §3) |

## Decision

One player move (research R7). It is used inside the search, and it is written into the timeline.

| Field | Type | Present for |
| --- | --- | --- |
| `kind` | `collect_fare` · `collect_rest` · `wake` · `call` · `give_change` · `request_break` · `pick_up` · `answer_claim` · `answer_dispute` · `answer_change_request` | all |
| `passenger_id` | str | every kind except `request_break` and `pick_up` |
| `pieces` | `{denomination: count}` | `give_change` |
| `denomination` | int | `request_break` |
| `token_id` | int | `pick_up` |
| `dispute_id` | int | `answer_dispute` |
| `answer` | bool, or the paid passenger's id | the three `answer_*` kinds |
| `commands` | list of logged commands | all, as applied, one tap time apart |

`wait` is not recorded. It only advances the clock.

## SolverResult

What `solve(definition, params, settings)` returns, and what `SolverRun.result` stores.

| Field | Type | Notes |
| --- | --- | --- |
| `trip_id`, `rev` | str, int | From the definition. |
| `verdict` | `solved` · `not_solved` · `refused` | |
| `end` | `found` · `exhausted` · `budget_spent` · `safety_cap` · `internal_error` · `refused` | Research R8. |
| `stars` | 0..3 | Of the run, or of the best run. |
| `run` | command log or absent | When `solved`. |
| `best_run` | command log or absent | When `not_solved` and some branch was played. |
| `run_hash` | str | Of `run`, or of `best_run`. |
| `first_loss` | `{kind, t_ms, passenger_id?, station_id?, detail}` or absent | `kind` ∈ `fight`, `mistake`, `failed`. |
| `timeline` | list of `TimelineEntry` | |
| `score` | `Score` or absent | When `solved`. |
| `refusals` | list or absent | When `refused`: `{code, path, message}`. |
| `effort_steps` | int | The steps simulated. |
| `settings_version`, `solver_fingerprint`, `params_fingerprint` | str | |

**TimelineEntry**: `{t_ms, decision, passenger_id?, amount_piasters?, pieces?, note?}`. For a run that
isn't solved, the last entry is `{t_ms, decision: "lost_star", passenger_id?, note}`.

**Score**:

```json
{
  "value": 44,
  "inputs": {
    "owed_at_once": {"value": 3, "points": 16},
    "change_pieces": {"value": 8, "points": 6},
    "blockers": {"value": 1, "points": 6},
    "breaks": {"value": 0, "points": 0},
    "tightness_ms": {"value": 2100, "points": 4},
    "variety": {"value": 4, "points": 12}
  }
}
```

`value = min(100, sum of points)`. The score holds no band. Every user of a result checks the score
against the line's current band (`in_band`, contracts/solver.md §5), because a reused result would
otherwise keep an old band.

## SolverRun (`content.SolverRun`, new table)

| Field | Type | Rule |
| --- | --- | --- |
| `id` | UUIDv7 | Primary key (constitution). |
| `kind` | `build` · `preview` | |
| `status` | `queued` · `running` · `done` · `failed` | `done` when the search ended `found`, `exhausted`, `budget_spent` or `refused`. `failed` for checks that failed before solving, an `end` of `safety_cap` or `internal_error`, and runs the sweep stopped. |
| `input_key` | char(64) | Indexed. |
| `trip_identifier` | char(40) | The trip's `trip_id`. Not named `trip_id`, which is the `trip` FK's column. |
| `trip` | FK `content.Trip`, null, `SET_NULL` | Previews only. |
| `requested_by` | char(150), blank | Previews only. A staff name, which never leaves the database. |
| `result` | jsonb | A `SolverResult`, or `{"findings": […]}` when the checks failed. |
| `created_at`, `updated_at`, `finished_at` | timestamps | `updated_at` is the heartbeat the sweep reads. |

**Constraints.**

- `solverrun_one_active_preview`: unique `trip` where `kind = 'preview'` and `status` is `queued` or
  `running`.
- `solverrun_finished_has_time`: `finished_at` is set exactly when `status` is `done` or `failed`.

**Transitions.**

```text
queued ──job starts──> running ──finish_run──> done | failed
running ──no update for 30 min (sweep)──> failed
```

- A `build` run is created `running` inside the build and finished in the same job.
- Both kinds finish through `finish_run(run, result)` (contracts/content-pipeline.md §5), which
  picks `done` or `failed` by the rule in `status`. A `safety_cap` result depends on the clock, so
  it must never be reused, whichever kind made it.
- Reuse reads `status = done` rows by `input_key`, of either kind (research R14).
- The migration only adds the table (expand-only).

## Validation report additions (`ContentPack.validation_report`)

```json
"solver": {
  "result": "warning",
  "meta": {"solver_fingerprint": "9c1e…", "settings_version": "41aa…", "solved": 3, "reused": 47},
  "trips": [
    {"trip_id": "line_hay.01", "rev": 1, "verdict": "solved", "end": "found", "stars": 3,
     "score": 12,
     "inputs": {"owed_at_once": 1, "change_pieces": 2, "blockers": 0, "breaks": 0,
                "tightness_ms": 4000, "variety": 2},
     "band": [0, 30], "in_band": true, "run_hash": "…", "reused": true,
     "params_fingerprint": "…"}
  ]
}
```

- `trips` is in pack order, and each finding of the stage is in `findings` as usual (V-Z1 to V-Z5).
- `inputs` holds each input's value (spec FR-030). Its points follow from the settings that
  `settings_version` names.
- `band` and `in_band` come from this pack's line, checked at this build, even when the result was
  reused.

## Release record addition

```json
"solver": {
  "solver_fingerprint": "9c1e…",
  "settings_version": "41aa…",
  "trips": [{"trip_id": "line_hay.01", "rev": 1, "verdict": "solved", "stars": 3, "score": 12,
             "band": [0, 30], "params_fingerprint": "…", "run_hash": "…"}]
}
```

- There are no runs, no timelines, no score inputs and no staff names in it. The inputs stay in the
  validation report (spec FR-030).
- The settings, the solver and the params are named by their fingerprints.
- `stages.solver` may be `passed` or `warning`.

## Finding codes (solver stage)

| Code | Severity | Message (English, for staff) |
| --- | --- | --- |
| `V-Z1` | error | `not 3-star solvable: best run <n> stars, first <kind> at <t> s (<passenger>, <station>); search <end>` |
| `V-Z2` | error | `the trip is refused: <code>: <message>` (first refusal, plus a count), or `the trip is refused: the app's tunables have no params for <line_id> (<reason>)` |
| `V-Z3` | error | `the solver stopped at its safety cap after <s> s` |
| `V-Z4` | error | `internal solver error; see the error monitor` |
| `V-Z5` | warning | `difficulty <score> is outside the line's band <min>–<max>; most from <input>, <input>` |

## Balancing report row

`trip_id, verdict, stars, score, owed_at_once, change_pieces, blockers, breaks, tightness_ms,
variety, slack_ms (station:ms;…), r900_stars, r900_fights, r900_mistakes, r1200_stars, r1200_fights,
r1200_mistakes`. The `r<ms>_*` columns follow `report_reaction_ms`.

## Solver fixture

A parity fixture named `solver__<trip_id with "." → "_">.json`. Its `command_log` is the solver's
run, its `seed` is the trip's own seed, and its params are the bundled ones for the trip's line. A
matching entry in `packages/trip_engine/test/fixtures/expectations/solver.dart` asserts 3 stars,
`fights == 0`, no mistakes and no boosters.
