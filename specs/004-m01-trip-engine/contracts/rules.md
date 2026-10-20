# Contract: Trip Rules Reference

> The living copy is [`packages/trip_engine/RULES.md`](../../../packages/trip_engine/RULES.md). Edit
> that one; this file records the rules as planned.

The exact rules of a trip (spec FR-063). The Dart engine implements them, and B05's Python mirror
reproduces them. During implementation this file is copied to `packages/trip_engine/RULES.md`, which
then becomes the living source. Every later rule change edits that copy, in the same PR as the code
and the fixtures (constitution III). The design reasons are in [research.md](../research.md), and
the types are in [data-model.md](../data-model.md).

Wording: *reached* means "at the first step whose clock is ≥ the time". *Fewest pieces* means the
greedy decomposition of §14.3. A passenger is *able* when they are aboard and `awake` or `attentive`.

## 1. Conventions

1. **Integers only.** Money is piasters, in glossary §3.2 denominations. Time is milliseconds. The
   only operations are `+`, `−`, `×`, comparison and floor division `~/` on non-negative operands
   (§15).
2. **Fixed orders.** Passengers are visited in definition order, authored events in definition
   order, stations in trip order, tokens in id order, and open disputes in event-index order.
3. **Percent.** `scale(x, pct) = x * pct ~/ 100`.
4. **Params.** Every number not fixed here comes from `TripParams` (data-model.md). The constants in
   this document are rules, not balancing numbers: the 33 ms step, the 100 reputation scale, the
   break-down table, the `change_bag` contents, the 1,200-command cap, and the params' upper
   bounds that keep the longest trip at 1,500 s (data-model.md "TripParams").

## 2. Starting a trip

1. **Validation.** Validate the definition and params (data-model.md "Validation"). Any problem
   throws `TripRefused` with all of them.
2. **Initial state:**
   - `t_ms = 0`, `status = running` and `reputation = 100`;
   - `tray` is `initial_tray` and the hand is empty;
   - `prng` is the seed, the definition's or the caller's;
   - each station's `at_ms` is `at_seconds × 1000`.
3. **Who is aboard.** A passenger is `aboard` at the start unless they have a `board_station_id` or
   are listed by a `roadside_pickup`. Those passengers start `waiting`.
4. **Initial alertness:** `asleep` for `sleeper`, `muted` (taps 0) for `headphones`, and `awake` for
   everyone else.
5. **No events at the start.** The first `step` takes the clock to 33.

## 3. One step, in order

1. If `status` isn't `running`, the step does nothing: the clock doesn't move and no events are
   emitted. Otherwise, `t_ms += 33`.
2. **Timers**, each by passenger order unless stated:
   1. `waking` with `alert_until_ms ≤ t`: becomes `awake` until `t + trip_sleeper_awake_ms`.
      Emits `PassengerWoke`, and the passenger says `woke`.
   2. A sleeper who is `awake` with `alert_until_ms ≤ t` becomes `asleep` (`PassengerFellAsleep`).
   3. `attentive` with `alert_until_ms ≤ t` becomes `muted` with taps 0 (`PassengerMuted`).
   4. When `ledger_peek_until_ms ≤ t`, it is cleared (`LedgerPeekEnded`).
   5. Dropped tokens with `dropped_until_ms ≤ t`, in id order, are lost (§5.7).
   6. Pending breaks with `completes_at_ms ≤ t`, in list order, complete (§4.9).
3. **Authored events** not yet fired, with `at_seconds × 1000 ≤ t`, in definition order, fire (§8).
4. **Scheduled payments.** For each passenger with `pays_at_seconds × 1000 ≤ t`, who is able, whose
   fare isn't sent, who has no open claim, isn't `never_pays` and isn't a group member: they pay
   (§6.2). A false claimer claims instead (§7.4). A passenger who wasn't able when their time came
   pays at the first later step at which they are able.
5. **Tokens.** Visit the tokens that exist at the start of this phase, in id order. Tokens created
   during this phase start moving at the next step.
   1. A dropped token is skipped.
   2. If it is hopping: `elapsed += 33`. When `elapsed ≥ duration`, it arrives at `hop.to`
      (`holder = hop.to`, `hops_done += 1`, `hop = null`). If that is its target, it is delivered
      (§5.5).
   3. If it is held and not delivered, try to start its next hop (§5.3).
6. **Patience.** For each owed passenger with patience left: subtract 33, or
   `scale(33, trip_patience_drain_pct_traffic)` while `traffic_active` (§7.3).
7. **Station warning.** If the next station isn't warned and `t ≥ at_ms − trip_station_warning_ms`,
   it is warned (§9.2).
8. **Deadlines and stations:**
   1. Passengers with `deadline_ms ≤ t`, in passenger order, get off (§9.3).
   2. While the next station is reached: process it (§9.4), then `next_station += 1`.
9. **Failure check** (§10.2).
10. **End check.** If `status` is `running` and every station is processed, the trip finishes (§11).

## 4. Commands

Every command applies at the current `t_ms`, between steps. A rejected command changes nothing and
isn't logged. An accepted one increments `commands_accepted`, is appended to the log, and is followed
by the failure check (§10.2). Every command is rejected with `command_limit` once
`commands_accepted == 1200`, and with `wrong_status` outside the statuses data-model.md allows.

1. **`PickFromTray(d)`.** Requires `tray[d] ≥ 1` (`tray_empty`). Moves one `d` from the tray to the
   hand.
2. **`ReturnHand()`.** Requires a non-empty hand (`hand_empty`). Moves the hand into the tray.
3. **`SendHand(p)`.** Requires a non-empty hand (`hand_empty`) and `p` aboard (`not_aboard`).
   - Creates a `change` token: pieces = the hand, owner and target `p`, holder `DRIVER`.
   - Clears the hand and sets `last_send = {token_id, until_ms: t + trip_undo_window_ms}`.
   - Emits `ChangeSent`.
4. **`UndoLastSend()`.** Requires `last_send`, `t ≤ until_ms`, and the token still alive, not
   dropped, with `hops_done == 0` (`undo_unavailable`).
   - Removes the token and adds its pieces to the hand.
   - Clears `last_send` and emits `SendUndone`.
5. **`Tap(p)`.** Requires `p` aboard (`not_aboard`). Cases 1 to 3 apply to `p`. For cases 4 to 7,
   a group member stands for the group's payer, who must be aboard (`not_aboard`). The first case
   that applies wins:
   1. `asleep`: becomes `waking` until `t + trip_wake_ms` (`PassengerWaking`).
   2. `waking`: rejected (`no_effect`).
   3. `muted`: `taps += 1`.
      - If `taps == 2`: `attentive` until `t + trip_headphones_attentive_ms`, with taps 0.
        Emits `PassengerAttentive`, and they say `attentive`.
      - Otherwise: `PassengerCalled{taps}`.
   4. Fare not sent, and no open claim:
      - a `never_pays` passenger says `claims_paid`, and nothing else happens;
      - a false claimer without `claim_resolved` opens a claim (§7.4);
      - anyone else pays now (§6.2).
   5. An open claim: rejected (`no_effect`).
   6. Fare sent and `balance < 0`: pays the rest (§6.4).
   7. Fare sent and `balance ≥ 0`:
      - without `claim_resolved`, opens a truthful claim (§7.4);
      - with it, they only say `claims_paid`.
6. **`ResolveClaim(p, insist)`.** Requires an open claim for `p` (`no_choice`). Closes it, and sets
   `claim_resolved`.
   - `insist`, truthful claim: a false accusation (§10.1, `rep_false_accusation`, fights +1, a
     fight in the sense of FR-057). Emits `FalseAccusation`, and `p` says `accused`.
   - `insist`, false claim: the liar is caught. Reputation rises by `rep_liar_caught`
     (`caught_liars += 1`, `LiarCaught`), `p` says `caught`, and `p` pays now (§6.2).
   - Not `insist`: `ClaimAccepted`. A false claimer becomes `never_pays`.
7. **`ResolveDispute(id, paid)`.** Requires an open dispute `id` (`no_choice`) and `paid ∈ {a, b}`
   (`bad_argument`). Let `other` be the other passenger. The answer is right when `paid` has sent
   their fare and `other` hasn't.
   - Right: `other` pays now (§6.2), the liar is caught (`rep_liar_caught`, `caught_liars += 1`),
     and `other` says `caught`.
   - Wrong: a false accusation against `other`, and `other` says `accused`.
   - Either way, the dispute closes and `DisputeResolved{right}` is emitted.
8. **`ResolveChangeRequest(p, agree)`.** Requires an open request for `p` (`no_choice`).
   - `agree`: choose pieces for `note` from the tray (§14.4). If none exists, the command is
     rejected (`cannot_make_change`) and the request stays open. Otherwise those pieces leave the
     tray in a `break_out` token from `DRIVER` to `p`.
   - Not `agree`: reputation drops by `rep_change_request_declined`, and `p` says
     `change_request_declined`.
   - Either way, the request closes and `ChangeRequestResolved{agreed}` is emitted.
9. **`RequestBreak(d)`.** Requires `d ≥ trip_break_min_piasters` with a row in the table of §14.1,
   `tray[d] ≥ 1` (`tray_empty`), and `breaks_used < rules.max_break_requests` (`break_limit`).
   - Removes one `d` from the tray, adds `{d, completes_at_ms: t + trip_break_delay_ms}` to the
     pending breaks, and sets `breaks_used += 1` (`BreakRequested`).
   - On completion (§3, step 2.6), the table's pieces for `d` enter the tray (`BreakCompleted`).
10. **`CollectDropped(id)`.** Requires token `id` to be dropped (`no_effect`). Collects it (§5.7).
11. **`UseBooster(b)`.** Requires `b` to be one of the four in-trip boosters (`bad_argument`). A
    `traffic_jam` also requires fewer than `booster_traffic_jam_max_per_trip` earlier
    `traffic_jam` entries in `boosters_used` (`booster_limit`). Appends `b` to `boosters_used` and
    emits `BoosterUsed`.
    - `change_bag`: the tray gains 50×2, 100×3 and 500×2.
    - `wake_all`: every `asleep` or `waking` sleeper becomes `awake` until
      `t + trip_sleeper_awake_ms` (`PassengerWoke`, and each says `woke`).
    - `ledger_peek`: `ledger_peek_until_ms = t + booster_ledger_peek_ms` (`LedgerPeekStarted`).
    - `traffic_jam`: shifts the schedule by `+booster_traffic_jam_ms` (§9.1).
12. **`Revive()`.** Requires `status == failed` and `revivable` (`not_revivable`).
    - Sets `reputation = rep_revive_to`, `status = running`, `revived = true` and
      `revivable = false`.
    - Emits `ReputationChanged{cause: revive}` and `TripRevived`.
13. **`Abandon()`.** Sets `status = abandoned` and builds the result (§11), with `TripAbandoned`.

## 5. Money tokens and the passing chain

1. **Rows.** Each column goes, from the driver backwards: `A`, `B`, `C`, `D`. `front_*` and `A_*`
   seats are one hop from the driver. A seat is *occupied* when a passenger aboard sits in it,
   whatever their alertness.
2. **The next holder** is computed each time a hop is about to start:
   - **Toward `DRIVER`** (`fare`, `return`, `break_in`): from a passenger in row `front` or `A`, the
     driver. From a passenger in row `R` behind `A`, the occupied seat in the same column nearest to
     the driver among the rows between `A` and `R`; if there is none, the driver.
   - **Toward passenger `p`** (`change`, `break_out`): from `DRIVER`, if `p` sits in `front` or `A`,
     then `p`. Otherwise the occupied seat in `p`'s column nearest to the driver among the rows from
     `A` up to `p`'s row (not including it); if none, `p`. From a passenger `h` in that column, the
     next occupied seat between `h`'s row and `p`'s row; if none, `p`.
   - **`redirect`**: from the member who received it straight to the group's payer.
3. **Starting a hop.** A hop from holder `h` to next holder `n` can start only if `h` is the driver
   or able, and `n` is the driver or able.
   - If not: set `blocked_by` to `h` if `h` isn't able, otherwise `n`. Emit
     `TokenBlocked{token, by}` when `blocked_by` changes from null.
   - If yes: clear `blocked_by`, emitting `TokenUnblocked` if it was set. Then set
     `hop = {to: n, elapsed: 0, duration}` and emit `TokenHopStarted`.
4. **Duration:**
   - `redirect`: `trip_group_redirect_hop_ms`;
   - otherwise `d = trip_hop_ms`;
     - if `h` is a passenger with archetype `hajja`, `d = scale(d, trip_hop_pct_hajja)`;
     - if `h` is a passenger whose row also holds an able `chatty` passenger (themselves included),
       `d = scale(d, trip_hop_pct_chatty_row)`.
5. **Delivery** at the target:
   - `fare` at `DRIVER`: the pieces enter the tray, and `paid_in` of the owner increases by the
     total (`MoneyArrivedAtDriver`).
   - `return` at `DRIVER`: the pieces enter the tray (`ExcessReturned`).
   - `break_in` at `DRIVER`: the pieces enter the tray (`ChangeRequestCompleted`).
   - `change` or `redirect` at a passenger: judged (§6.5).
   - `break_out` at `p`: `p` sends a `break_in` token holding one piece of the request's note.
6. **Undo** is §4.4.
7. **Dropped tokens** (bump, §8). On `CollectDropped` before `dropped_until_ms`:
   - `fare`: as delivered at the driver (§5.5);
   - `return`: into the tray;
   - `break_in`: into the tray, and the request completes;
   - `change`, `redirect` and `break_out`: into the tray. The passenger is still owed, and a
     `break_out` cancels its request with no penalty.

   `DroppedCollected` is emitted. When the deadline passes uncollected, the token is lost
   (`DroppedLost`):
   - `fare`: the money never reaches the driver. The owner still has `fare_sent`, and their balance
     stands.
   - `return`: its total is added to `overpaid_piasters`.
   - anything else: the money is gone, and a `break_out` or `break_in` ends its request with no
     penalty.
8. **When a passenger `p` gets off** (§9.3):
   - Every token whose `holder` is `p`, or whose current hop goes to `p`, and whose target isn't
     `p`, is handed to the driver: a `fare` is delivered at the driver (§5.5), and any other token
     goes into the tray.
   - Every token whose target is `p` goes into the tray.
   - Tokens are visited in id order.

## 6. Fares, payments and change

1. **Fare of passenger `q`:**
   - `base` = the destination station's `fare_piasters + fare_increase_piasters`;
   - a `student` pays `(base × (100 − student_discount_pct) + 4999) ~/ 5000 × 50`;
   - anyone else pays `base`.

   A group payer's fare is the payer's own fare, plus each listed member's fare (computed the same
   way), plus `(group_size − 1 − listed members)` × the payer's base fare.
2. **Paying now** (passenger `q`, not a member):
   - Start from `payment`, the authored pieces. If any `fare_increase` has fired, `q` isn't in
     `old_fare_payers`, and `payment.total < fare`, add the fewest pieces for `fare − total`.
   - Fix `fare_piasters = fare`, `balance = total − fare` and `fare_sent = true`.
   - Create a `fare` token from `q` to `DRIVER`, and emit `FareSent`.
   - `q` says:
     - `pays_group` if they are a group payer;
     - `pays_old_fare` if they are in `old_fare_payers` and `total < fare`;
     - otherwise `pays`.

     The `amount` placeholder is the total.
   - If `balance > 0`, patience starts (§7.3).
3. **`never_pays`** passengers never pay, by schedule, tap or dispute, except when caught (§4.6,
   §4.7), which clears `never_pays`.
4. **Paying the rest.** For `balance = −r`, `q` sends a `fare` token of the fewest pieces for `r` and
   says `pays_rest` (amount `r`). The balance becomes 0.
5. **Judging change** from a `change` or `redirect` token of total `A`, at passenger `p`:
   1. If `p` is a group member and the token is `change`, it is re-sent as a `redirect` token to the
      payer. No judgment yet.
   2. If `p`'s fare isn't sent, or `balance ≤ 0`, the change is **not owed**:
      - add the mistake `{p, not_owed, A}`, emit `ChangeDelivered{not_owed}` and `MistakeMade`;
      - an `honest` `p` sends the same pieces back as a `return` token and says `returns_excess`
        (amount `A`);
      - otherwise `overpaid_piasters += A`.
   3. If `A == balance`, the change is **exact**:
      - `balance = 0`, and reputation rises by `rep_exact_change`, capped at 100;
      - `p` says `thanks`, and `ChangeDelivered{exact}` is emitted.
   4. If `A < balance`, the change is **short**:
      - `balance −= A`, and reputation drops by `rep_short_change`;
      - `p` says `short_change` (amount = the new balance), and `ChangeDelivered{short}` is emitted.
   5. If `A > balance`, the change is **over**:
      - let `E = A − balance`; then `balance = 0`;
      - add the mistake `{p, over, E}`, emit `ChangeDelivered{over}` and `MistakeMade`;
      - an `honest` `p` sends the fewest pieces for `E` as a `return` token and says
        `returns_excess` (amount `E`);
      - otherwise `overpaid_piasters += E`.

## 7. Passengers

1. **Types.** Each supported archetype's rule:

   | Archetype | Rule |
   | --- | --- |
   | `regular` | Base rules. |
   | `honest` | Returns excess and change it wasn't owed (§6.5). |
   | `hajja` | Hops she passes on take `trip_hop_pct_hajja` (§5.4). |
   | `sleeper` | Starts asleep. After waking, awake for `trip_sleeper_awake_ms`, then asleep again (§3, step 2). |
   | `hurry` | Patience starts at `scale(trip_patience_ms, trip_patience_pct_hurry)`. |
   | `big_note` | Base rules. |
   | `student` | Discounted fare (§6.1). |
   | `headphones` | Starts muted. Called twice, attentive for `trip_headphones_attentive_ms`. |
   | `false_claimer` | Claims instead of paying (§7.4). |
   | `group_payer` | Pays for the group (§6.1). Receives the group's change. |
   | `chatty` | While able, slows hops out of seats in their row (§5.4). |
   | `regular_customer` | Tips `trip_tip_piasters_regular_customer` when thanked and not impatient (§9.3). |

2. **Group members** never pay or claim themselves. Taps act on the payer (§4.5), and change to them
   is redirected (§6.5).
3. **Patience** starts when the balance first becomes above 0:
   `trip_patience_ms`, or the `hurry` value of §7.1. While the passenger is owed and aboard, it
   drains per §3, step 6.
   - When it first falls to half its starting value or below, they say `wants_change` (amount = the
     balance).
   - When it reaches 0:
     - patience is set to 0 and `impatient` to true, and `counters.impatient += 1`;
     - reputation drops by `rep_impatient`;
     - `PatienceRanOut` is emitted, and they say `impatient`.

     This happens once. Patience never refills.
4. **Claims.** A claim opens with `ClaimRaised`, and the passenger says `claims_paid`.
   - It is *false* when a false claimer raises it instead of paying (§3, step 4, or a tap).
   - It is *truthful* when it comes from a tap on a passenger who has sent their fare.

   A passenger has at most one open claim, and once `claim_resolved` is set, never opens another.

## 8. Authored events

An event fires at `at_seconds × 1000` on the trip clock, which is never shifted. It needs every
passenger it names to be aboard, except for `roadside_pickup`, which needs them `waiting`. A
`payment_dispute` never names a group member (validated at start).
Otherwise it is skipped (`EventSkipped{index}`). An event that fires emits `EventStarted{index,
event_id}` first. Its parameters were validated at start (content-contract.md §2).

| Event | Effect |
| --- | --- |
| `bump` | Every token whose `hop` is set becomes dropped: `hop = null`, `dropped_until_ms = t + trip_bump_collect_ms` (`MoneyDropped`). |
| `traffic` | Shift by `+seconds × 1000` (§9.1). `traffic_active = true`. |
| `open_road` | Shift by `−seconds × 1000`, clamped (§9.1). |
| `fare_increase` | `fare_increase_piasters += amount_piasters`. The listed passengers join `old_fare_payers` (`FareIncreased`). |
| `drop_me_here` | `deadline_ms = t + seconds × 1000`, or `t + trip_station_warning_ms` without `seconds` (`StopChanged`). The passenger says `drop_me_here`. |
| `payment_dispute` | Opens dispute `index` between the two passengers (`DisputeRaised`). Both say `dispute`. |
| `change_request` | Opens a request for the passenger with `note = amount_piasters` (`ChangeRequestRaised`). They say `change_request` (amount = the note). |
| `roadside_pickup` | Each listed passenger boards now if their seat is free, and otherwise as soon as it is (§9.5). |

Open choices close by themselves when a passenger involved gets off (§9.3).

## 9. Stations

1. **Shifting** by `δ`, from the next unprocessed station `i` (when one remains):
   - **Positive `δ`:** every station `j ≥ i` gets `at_ms += δ`.
   - **Negative `δ`:** let `target = max(at_ms[i] + δ, t + trip_station_warning_ms)`, and
     `δ' = min(0, target − at_ms[i])`. Every station `j ≥ i` gets `at_ms += δ'`.

   `ScheduleShifted{delta: δ'}` is emitted, with `δ' = δ` when positive.
2. **Warning.** Station `i` is marked warned, and `StationWarning{station_id, at_ms, alighting,
   owed}` is emitted:
   - `alighting` lists the aboard passengers whose destination is the station and who have no
     earlier `deadline_ms`;
   - `owed` is the owed subset of `alighting`.

   The first passenger in `alighting` says `stop_near` (station = the station).
3. **Getting off** (passenger `p`, at a station or at their deadline):
   1. **Open choices close:**
      - `p`'s claim is accepted (§4.6, without the speech), and a false claimer becomes
        `never_pays`;
      - `p`'s change request is declined (§4.8, with its penalty);
      - disputes naming `p` close with no effect.
   2. **Outcome.** The first case that applies:
      - **missed stop:** `p` is `asleep` or `waking`.
        - Reputation drops by `rep_missed_stop`, and `missed_stops += 1`.
        - If `p` is owed, add the mistake `{p, unreturned, balance}`.
        - If `p`'s fare isn't sent and `p` isn't a member, `lost_fares += 1`.
        - `p` says `missed_stop` (station = `p`'s destination).
      - **fight:** `p` is owed. Reputation drops by `rep_fight`, `fights += 1`, the mistake
        `{p, unreturned, balance}` is added, and `p` says `fight` (amount = the balance). In a `no_fights_required` trip,
        `revivable = false` and the trip fails (§10.2).
      - **left unpaid:** `p`'s fare isn't sent and `p` isn't a member. `lost_fares += 1`.
      - **thanked:** anyone else. A balance below 0 is left unpaid, and §11 counts it out. A
        `regular_customer` who isn't impatient adds `trip_tip_piasters_regular_customer` to
        `tips_piasters` and says `tip` (amount = the tip).
   3. **Tokens** follow §5.8.
   4. **Leaving.** `p` becomes `gone` with that outcome (`PassengerAlighted{outcome}`), and the seat
      is freed.
   5. **Boarding.** Any `waiting` passenger whose pickup has come (§9.5) and whose seat this frees
      boards now.
4. **Processing station `i`:**
   1. Emit `StationReached`.
   2. Every aboard passenger whose destination is the station gets off (§9.3), in passenger order.
   3. Every `waiting` passenger with this `board_station_id` boards if their seat is free (§9.5).
   4. `traffic_active = false`.
5. **Boarding** passenger `q`:
   - `presence = aboard`, with the initial alertness of §2.4 (`PassengerBoarded`), and `q` says
     `boards`.
   - A pickup or boarding station that has come while `q`'s seat is taken leaves `q` waiting. `q`
     boards at the moment the seat is freed (§9.3, step 5).

## 10. Reputation, failing, reviving

1. **Changes.**
   - A gain adds and caps the result at 100.
   - A loss subtracts and adds the full penalty to `reputation_lost[cause]`.
   - Each change emits `ReputationChanged{delta, cause, value}`.
2. **Failure check** (after each step and each accepted command). If `status` is `running` or
   `paused`, and either `reputation ≤ 0` or `rules.no_fights_required && fights > 0`:
   - false accusations count as fights here (§4.6);
   - when `rules.no_fights_required && fights > 0`, the failure sets `revivable = false`. A
     reputation failure with no fight keeps `revivable` as it was;
   - `status = failed`, and the clock stops;
   - `TripFailed{reputation_lost, revivable}` is emitted.

   Tokens, timers and choices stay where they are.

   A command accepted while paused (an answer to a choice, or a booster) can fail the trip. It then
   goes from `paused` straight to `failed`, and `resume()` does nothing. A replay applies the same
   command while running, at the same `t_ms`, so it fails at the same point and the results agree.
3. **Revive** is §4.12, and **abandon** is §4.13.

## 11. Ending and the result

When the trip finishes (§3, step 10):

1. Tokens still alive are settled, in id order:
   - a dropped token is lost (§5.7);
   - an undropped `fare` is delivered at the driver (§5.5);
   - any other undropped token goes into the tray.
2. `status = finished`.

Then, for every end (finished, failed or abandoned), the result is built:

- `fares_collected_piasters` = the sum, over passengers with `fare_sent`, of `min(fare_piasters,
  paid_in)`.
- `earnings_piasters = fares_collected − overpaid_piasters + tips_piasters`.
- `star_flags`:
  - `reached = (outcome == finished)`;
  - `no_fights = (fights == 0)`;
  - `no_mistakes = (mistakes is empty)`.
- `stars` = 0 unless finished. Otherwise 1, then 2 if no fights, then 3 if also no mistakes.
- `earnings_jenehat` = 0 unless finished. Otherwise
  `min(max(0, earnings_piasters) ~/ 100, max_earnings_jenehat)`.
- `reputation = max(0, reputation)`.
- `duration_ms = t_ms`.
- `command_log_hash` is per replay-and-fixtures.md §3.

The result goes in `TripFinished`, `TripAbandoned`, or the state of a failed trip.

## 12. Speech

`p says s` emits `PassengerSpeaks{passenger_id, slot: s, speech_key, variant, amount_piasters?,
station_id?}`:

- `speech_key = p.speech_keys[s]` if set, otherwise `passenger.<s>`;
- `variant = next()` (§13);
- the placeholder fields are present only for slots that declare them (content-contract.md §2).

Speech never changes state other than the PRNG.

## 13. PRNG

`xorshift32`, on an unsigned 32-bit `x`, starting from the seed:

```text
x ^= (x << 13) & 0xFFFFFFFF
x ^= x >> 17
x ^= (x << 5) & 0xFFFFFFFF
return x
```

It is drawn only by §12, once per speech, in emission order.

## 14. Tables and selection rules

1. **Break-down** for `RequestBreak` (clarification 4):

   | Note | Comes back as |
   | --- | --- |
   | 1000 | 500, 100×4, 50×2 |
   | 2000 | 1000, 500, 100×4, 50×2 |
   | 5000 | 2000×2, 500, 100×4, 50×2 |
   | 10000 | 5000, 2000×2, 500, 100×4, 50×2 |
   | 20000 | 10000, 5000, 2000×2, 500, 100×4, 50×2 |

2. **`change_bag`:** 50×2, 100×3, 500×2 (glossary §3.3).
3. **Fewest pieces** for an amount `r`, which is a multiple of 50: for each denomination from 20000
   down to 50, take `r ~/ d` of it and continue with `r % d`. There is unlimited supply, because the
   pieces come from the passenger, not the tray.
4. **Change-request pieces** for note `N` from the tray. A depth-first search over the denominations
   below `N`, from largest to smallest. For each one, try counts from `min(tray[d], remaining ~/ d)`
   down to 0. The first combination whose total is exactly `N` is used. If there is none, there is no
   selection.

## 15. Integer rules for both languages

- `~/` (Dart) and `//` (Python) are used only on non-negative operands, where they agree. `%` is
  used only on non-negative operands.
- No value exceeds 2^53 − 1 (research R3).
- Booleans and integers are never mixed in arithmetic.
- Every list the engine iterates has a fixed order (§1.2). Maps are iterated only through those
  orders, never by hash order.
