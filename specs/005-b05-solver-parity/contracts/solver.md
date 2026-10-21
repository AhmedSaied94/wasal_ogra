# Contract: The Solver and the Difficulty Score (`wassal_solver.solver`, `wassal_solver.scoring`)

How the idealized player plays, how the search ends, what a result holds, and how the score is
computed. The research behind each part is R7 to R12. The result's types are in
[data-model.md](../data-model.md).

## 1. Entry points

```python
from wassal_solver import SolverSettings, solve, score_trip, in_band, load_settings, bundled_params

settings = load_settings()                       # data/settings.json, validated
params = bundled_params(definition.line_id)      # from data/tunables.json (research R5)
result = solve(definition, params, settings)     # SolverResult (data-model.md); never raises
result.to_json()                                 # canonical-ready dict
in_band(result.score.value, line.difficulty_band)  # the band check, made by the caller (§5)
```

- `solve` takes no band, and its result carries no band check (§5).
- `solve` catches every exception in the search. It logs it and returns `end: internal_error`.
- `solve` with a definition the mirror refuses returns `verdict: refused`, with the `refusals`.
- `settings` may be replaced, for example `dataclasses.replace(settings, reaction_ms=100)` in tests,
  or the balancing report's slower players. The result records the `settings_version` it ran with.

## 2. The idealized player

**What it knows.** The whole mirror state at every step.

**What it may do.** The decisions of data-model.md "Decision", mapped to commands as follows:

| Decision | Possible when | Commands |
| --- | --- | --- |
| `collect_fare(p)` | `p` aboard and able, fare not sent, no open claim, not a group member, not a passenger who never pays | `Tap p` |
| `collect_rest(p)` | `p` aboard and able, fare sent, `balance < 0`, no open claim | `Tap p` |
| `wake(p)` | `p` aboard and `asleep` | `Tap p` |
| `call(p)` | `p` aboard and `muted` | `Tap p`, `Tap p` |
| `give_change(p, pieces)` | `p` aboard and owed `b > 0`, with no change on its way to them; `pieces` from the tray, totalling exactly `b`; hand empty | `PickFromTray d` per piece, largest first, then `SendHand p` |
| `request_break(d)` | `RequestBreak d` would be accepted, no break is pending, and the tray can't make some owed passenger's change or an open change request | `RequestBreak d` |
| `pick_up(token)` | the token is dropped | `CollectDropped id` |
| `answer_claim(p, insist)` | a claim is open for `p` | `ResolveClaim p insist`, where `insist` is true exactly when the claim is false |
| `answer_dispute(id, paid)` | dispute `id` is open, and exactly one of its two passengers sent their fare | `ResolveDispute id paid`, where `paid` is that passenger |
| `answer_change_request(p, agree)` | a request is open for `p`; agreeing also needs the tray to make the note | `ResolveChangeRequest p agree`. Both values are searched. |

**What it never does.** It never builds over-change, short change, or change for someone who isn't
owed. It never uses `UseBooster`, `Revive`, `UndoLastSend` or `Abandon`, and never watches an ad
(spec FR-016).

**Timing.** Let `R = ceil(reaction_ms / 33) × 33` and `T = ceil(tap_ms / 33) × 33`.

- A decision's first command is at `t ≥ max(end_of_last_decision + R, became_possible + R)`.
  - `became_possible` is the first step at which the decision's row above was true.
  - `end_of_last_decision` is the `t_ms` of the previous decision's last command, or `0` at the
    start.
- Each further command of the decision is applied `T` after the one before it. The mirror steps in
  between.
- If a command is rejected partway through, the branch is dropped.

## 3. The search

- **Order at each decision point**:
  1. forced answers: `answer_claim`, `answer_dispute` and `pick_up`;
  2. per passenger, by the soonest stop: `wake`, `call`, `collect_fare`, `collect_rest`,
     `give_change`;
  3. compositions by the fewest pieces, then by the most 50s and 100s left in the tray, then by the
     largest pieces first;
  4. `request_break` (larger notes first);
  5. `answer_change_request` (agree first);
  6. `wait`.
- **`wait`** jumps to the next step at which the set of ready decisions changes, or to a timing
  point. A decision is ready once its first command may come (§2).
  - If nothing is ready there, the branch moves on to the next step at which something is. A timing point is the latest step at which `wake(p)` or `call(p)` still makes `p` able when
  their next token reaches them, or when their stop comes.
- **Pruning.** The branch is cut at the first step with `fights > 0`, a mistake, or
  `status != running` other than `finished`. A branch that reaches `finished` with 3 stars ends the
  search as `found`.
  - It is also cut once a star loss is certain: a passenger is owed change the tray can't make,
    and nothing can bring the tray new pieces. That means no break left to ask for or pending, no
    money in transit or in the hand, nobody left to pay or owing the rest, and no authored event
    still to fire. Short or over-change would cost a star too. Such a branch can leave at most
    2 stars, with its first loss at that passenger's stop at the latest.
- **Visited table.** At every decision point, the solver computes
  `blake2b(canonical([state, [[decision, ready_at], …]]), digest_size=16)`: the state, plus each
  possible decision with the earliest step its first command may come. A digest already in the
  table cuts the branch. The table holds at most `transposition_cap` entries.
- **Ends:**

  | End | When |
  | --- | --- |
  | `found` | A 3-star run was found, and it confirmed (§4). |
  | `exhausted` | Every ordered branch was tried. |
  | `budget_spent` | The mirror steps simulated reached `effort_budget_steps`. |
  | `safety_cap` | Wall time passed `safety_cap_seconds`. This is checked every 1,024 steps. |
  | `internal_error` | An exception, or a found run that didn't replay to 3 stars. |
  | `refused` | `start` refused the trip. |

- **The best run.** It is the branch with the most final stars, then the latest `first_loss.t_ms`,
  then the first found. A cut branch is played on to the end with the same ordering, to learn its
  stars, but that tail doesn't count toward the search's exhaustion.
  - A cut branch that can't beat the best run is not played on. A fight leaves at most 1 star, a
    mistake at most 2, and a failure 0.
  - The tail's steps count in `effort_steps`, but the budget doesn't stop a tail.
  - When the budget runs out before any branch has ended, the deepest decision point is played on
    to its end, and that is the best run.

## 4. Confirmation

A found run is replayed with `engine.replay(definition, seed, params, run)`. Its result must have
`stars == 3`. If it doesn't, the end is `internal_error`, and the verdict is `not_solved`, never
`solved`.

## 5. The difficulty score

**Inputs**, all integers, from the trip and its confirmed run:

| Input | Value |
| --- | --- |
| `owed_at_once` | The highest number of passengers owed at the same step during the run. |
| `change_pieces` | The pieces in every `give_change` of the run. |
| `blockers` | For each passenger who pays, the sleepers and headphones passengers on their chain to the driver (`RULES.md` §5), summed. |
| `breaks` | The `request_break` decisions in the run. |
| `tightness_ms` | `max(0, slack_ref_ms − min slack)`. A change's slack is its passenger's stop time minus the change's arrival time. With no change in the run, it is 0. |
| `variety` | Distinct archetypes in `passengers`, plus distinct `event_id`s in `events`. |

**Points.** `points_i = min(cap_i, max(0, value_i − free_i) × per_i // unit_i)`, and
`score = min(100, Σ points_i)`.

**Initial table** (`settings.json`, calibrated during implementation, research R11):

```json
"score": {
  "slack_ref_ms": 12000,
  "owed_at_once":  {"free": 1, "per": 8, "unit": 1,    "cap": 24},
  "change_pieces": {"free": 2, "per": 1, "unit": 1,    "cap": 16},
  "blockers":      {"free": 0, "per": 6, "unit": 1,    "cap": 18},
  "breaks":        {"free": 0, "per": 8, "unit": 1,    "cap": 16},
  "tightness_ms":  {"free": 0, "per": 2, "unit": 1000, "cap": 20},
  "variety":       {"free": 1, "per": 4, "unit": 1,    "cap": 16}
}
```

**The band check** isn't part of the result. `in_band(score, band)` is
`band.min ≤ score ≤ band.max`, both ends included, with the line's `difficulty_band`.

- Whoever uses a result checks it against the band as it is now:
  - the stage, with the line in the pack;
  - the preview panel, with the trip's line;
  - `solve`, `check-source` and `report`, with the layout's line file.
- A result is reused by `input_key`, which doesn't cover the band. A band stored with the result
  would go stale when only the line's band changes.
- A lone trip with no line available has no band check.

**Properties**, checked by tests:

- the score is an integer in 0..100;
- raising one input never lowers the score;
- the same run always gives the same score;
- the sample pack's trips score inside their bands (spec FR-042).

## 6. The balancing report

`report(trips, settings)` returns one row per trip (data-model.md "Balancing report row"):

- the default-settings result;
- `slack_ms` per station in the run;
- for each `report_reaction_ms` value, the stars, fights and mistakes of the best run found with
  `reaction_ms` set to that value.

Slower-player results appear nowhere else (Clarifications Q3).
