# Contract: Operations

What each operation of `POST /v1/sync` must carry, what the server checks (in this order, the first
that fails is the reason), and what it does. It refines backend §7.4 and agrees with M05's
`contracts/operations.md`, whose wire payloads M06 sends. All amounts are integers: a float, a
boolean or a string where an integer is expected is `validation_error`. Every payload is a closed
object: a key not listed is `validation_error` with `details.field = "payload"` (the key itself is
never named: the phone chose it, and the answer is stored), except inside `result` (below). A string
may not hold NUL or a lone surrogate (`validation_error` for that field), and a count or revision
that is stored is at most 2³¹ − 1.

## The envelope

```json
{ "client_txn_id": "<uuidv7>", "op_type": "trip_start", "occurred_at": "2026-10-17T09:12:03Z", "payload": { } }
```

`occurred_at` is UTC, ISO-8601 with `Z`. It is informational except for the fuel timeline
(contracts/fuel.md). `op_type` matches `^[a-z][a-z0-9_]{0,39}$`; anything else makes the whole
batch a 400 (contracts/api.md), since it is not an operation any version could know.

## Order of checks common to every operation

1. **Stored.** The id was processed: return the stored outcome (a changed type or payload hash also
   raises `txn_payload_mismatch`). The same id twice in one batch: the second returns the first.
2. **`op_expired`.** The id's embedded time is older than `SYNC_OP_RETENTION_DAYS` or more than one
   day ahead.
3. **`unknown_op_type`.** The type is not in the tables below (`claim_daily_reward`, `claim_task`
   and anything else).
4. **`validation_error`.** The payload's shape.
5. **Content version**, for the operations that declare one: `unknown_content_version`, then
   `content_version_unsupported` (research R2).
6. The operation's own checks, as listed.

A rejected operation changes nothing. Its outcome is stored, so a repeat returns it.

`content_version` is a **payload** field of every operation that reads the pack: `trip_start`,
`spend_jenehat`, `spend_bonat`, `story_progress` and `claim_request`. M06 adds it from the
operation's recorded column (M05 stores `content_version` on every row).

## The answer for one operation

```json
{ "client_txn_id": "…", "status": "accepted" }
{ "client_txn_id": "…", "status": "rejected", "reason": "insufficient_funds" }
{ "client_txn_id": "…", "status": "accepted", "granted": [ {"kind": "room", "id": "salon", "currency": "BONAT", "amount": 10} ] }
```

`granted` appears only when the server granted something the phone did not propose: a room or
chapter reward, a request reward, or a gift's contents. For a fill or a booster it lists
`{"kind": "gift", "id": "comeback", "fuel": "max", "booster": "change_bag"}`.

## `trip_start`

Payload `{"trip_id", "content_version", "fuel_mode"}`, `fuel_mode` in `fuel`, `unlimited`, `challenge`.

| # | Check | Reason |
| --- | --- | --- |
| 1 | the trip is in the declared pack | `unknown_trip` |
| 2 | `fuel_mode` is `unlimited` and `t < fuel_unlimited_until`; `challenge` is not available yet | `not_eligible` |
| 3 | the trip is unlocked (research R6) | `not_unlocked` |
| 4 | `fuel` mode with no liters: the third overdraft of the game day | `cap_reached` |

Effects: if a start is open, it is closed as abandoned first (a `TripRun` with outcome `abandoned`,
0 stars, 0 earnings, `plays` + 1). Then the fuel moves (contracts/fuel.md: −1 in `fuel` mode with a
liter, an overdraft flag with none), `trips_started` + 1 (flag `trip_rate` over the threshold), and
the start is open: the trip's `max_earnings_jenehat` and last station time are copied from the pack
of the declared version.

## `trip_result`

Payload `{"trip_start_txn": "<uuid>", "result": {…}}`. `result` is M01's `TripResult.toJson()`. The
server reads only: `trip_id`, `rev`, `outcome` (`finished`, `failed`, `abandoned`), `stars`,
`earnings_jenehat`, `fights`, `mistakes` (counted), `duration_ms`, `revived`, `boosters_used`,
`command_log_hash`; other keys are ignored. `result` is at most 8 KB.

| # | Check | Reason |
| --- | --- | --- |
| 1 | the start was rejected | `dependency_rejected` |
| 2 | a result for this start exists (including the abandoned one a later start made) | `result_exists` |
| 3 | the start is the open one | `no_trip_start` |
| 4 | `result.trip_id` equals the start's | `trip_mismatch` |
| 5 | `stars` is 0–3, and 0 unless `finished` | `stars_out_of_bounds` |
| 6 | `0 ≤ earnings_jenehat ≤` the start's `max_earnings_jenehat`, and 0 unless `finished` | `earnings_out_of_bounds` |
| 7 | for `finished`: `duration_ms ≥ SYNC_MIN_DURATION_PERCENT` % of the last station time | `duration_out_of_bounds` |

Effects: JENEHAT + `earnings_jenehat` (reason `trip_earnings`, ref the start); `TripProgress`
(`plays` + 1; for `finished`: `best_stars` is the maximum, `best_time_ms` the minimum over runs with
at least 1 star, `first_completed_at` once); a `TripRun`; the open trip is closed and becomes the
last result; flag `fast_three_star` when it applies; then the completion rewards (research R6).

## `ad_reward`

Payload `{"ad_placement", "ref"?}`.

| Placement | `ref` | Checks (in order) | Effects |
| --- | --- | --- | --- |
| `result_double` | the last result's start | `no_result` (`ref` is not `last_start`); `not_doublable` (not `finished`, or 0 earnings); `already_doubled` | JENEHAT + `last_earnings` (reason `ad_result_double`); `last_doubled` |
| `fuel_refill` | none | `tank_full`; `cap_reached` (3 a game day) | fuel to the maximum; `fuel_refill_ad` counter + 1 |
| `trip_revive` | the open start | `dependency_rejected`; `no_trip`; `already_revived` | `open_revived` |
| `traffic_jam` | the open start | `dependency_rejected`; `no_trip`; `cap_reached` (`ECONOMY_TRAFFIC_JAM_ADS_PER_TRIP`, 1) | `open_traffic_jam_ads` + 1 |
| `morning_piggy` | — | always `server_only` | — |
| anything else | — | `unknown_sku` | — |

## `spend_jenehat`

Payload `{"sku_kind", "sku_id", "variant"?, "price", "content_version"}`, `sku_kind` in `item`,
`vehicle`, `chapter`, `upgrade`. `variant` is required for an item and refused otherwise.

| # | Check | Reason |
| --- | --- | --- |
| 1 | the id is known in the pack (rules or catalog) | `unknown_sku` |
| 2 | the catalog has a JENEHAT price for it | `not_for_sale` |
| 3 | `price` equals the catalog price | `price_mismatch` |
| 4 | the variant is one of the item's | `unknown_variant` |
| 5 | not already owned | `already_owned` |
| 6 | unlocked: an item needs its room's chapter unlocked; a chapter needs its predecessor complete | `not_unlocked` |
| 7 | the balance covers the price | `insufficient_funds` |

Effects: JENEHAT − price (reasons `item_purchase`, `vehicle_purchase`, `chapter_purchase`,
`upgrade_purchase`); an `Ownership` row (with the variant); then the completion rewards.

## `spend_bonat`

Payload `{"sku_kind", "sku_id", "price", "content_version", "ref"?}`.

| `sku_kind` / `sku_id` | Checks before the balance | Effects (reason) |
| --- | --- | --- |
| `booster` / `change_bag`, `wake_all`, `ledger_peek`, `traffic_jam` | — | inventory + 1 (`booster_purchase`) |
| `fuel` / `refuel_full` | `tank_full` | fuel to the maximum (`fuel_purchase`) |
| `fuel_unlimited` / `fuel_unlimited_1h` | — | window + 60 min (`fuel_unlimited_purchase`) |
| `revive` / `revive` | `ref` is the open start: `dependency_rejected`, `no_trip`, `already_revived` | `open_revived` (`revive_purchase`, ref the start) |
| `cosmetic` / a catalog id | `already_owned` | `Ownership` (`cosmetic_purchase`) |

Common order: `unknown_sku` (the id is not one listed), `not_for_sale` (no BONAT price),
`price_mismatch`, the row's own checks, then `insufficient_funds` last, so a purchase that could
not apply is never reported as unaffordable. The balance check uses the **server's** balance.
Effects: BONAT − price.

## `use_booster`

Payload `{"booster_id", "ref"}`. Checks: `dependency_rejected`; `no_trip` (`ref` is not the open
start); `unknown_sku` (not one of the four); `none_left`. Effect: inventory − 1. No ledger entry.

## `story_progress`

Payload `{"chapter_id", "scene_id", "content_version"}`. Checks: `unknown_sku` (chapter or scene not
in the pack); `not_unlocked` (the chapter is locked). Effect: the scene is added to `scenes_seen`
(a repeat is accepted and changes nothing, so `state_version` stays), then the completion rewards.

## `settings_update`

Payload `{"display_name"?, "settings"?}`, at least one (neither: `validation_error` with
`details.field = "payload"`). Rules: research R10. A refused name or setting is `validation_error`
with `details.field` (`display_name` or `settings`), never the value. Effect: `Player.display_name`
(stored trimmed, NFKC) and `Player.settings` (the keys sent, merged into the stored ones).

## `tutorial_gift`

Payload `{}`. Checks: `already_granted`. Effect: fuel to the maximum (a full tank is accepted and
unchanged), a `GrantRecord(tutorial)`. No ledger entry.

## `comeback_gift`

Payload `{}`. Checks, in order: `not_eligible` (no `comeback_return_at`); `already_granted` (this
return already has a `GrantRecord`); `not_eligible` (a comeback gift within
`SYNC_COMEBACK_COOLDOWN_DAYS`). Effect: fuel to the maximum (a full tank is accepted and unchanged),
`change_bag` + 1, a `GrantRecord(comeback, <return_at ISO>)`. The return stays on the wallet: its
grant record is what marks it claimed, and a later return replaces it (research R13). No ledger
entry.

## `claim_request`

Payload `{"request_id", "content_version"}`. Checks: `unknown_sku` (not a request of the pack);
`already_granted`; `not_eligible` (the item, and the variant when the request names one, is not
owned). Effect: BONAT + `reward_bonat` of the declared version (reason `request_reward`, ref the
request id, source `system`: the amount is the pack's), a `GrantRecord(request)`.

## Completion rewards (not an operation)

After an accepted `spend_jenehat`, `trip_result` or `story_progress`, every room that is now complete and every chapter
whose goal is now met, and has no `GrantRecord`, pays its `completion_bonat` once: BONAT +
(reason `story_reward`, ref the room or chapter), a `GrantRecord`, and, for a chapter, its
`StoryState` row marked `completed`. They appear in the triggering operation's `granted`. Rooms come
before chapters, in `order`.

## Reasons

| Reason | Operations | Meaning |
| --- | --- | --- |
| `validation_error` | all | the payload's shape, or a refused name |
| `unknown_op_type` | — | not an operation this version knows |
| `op_expired` | all | the id is older than the retention |
| `unknown_content_version`, `content_version_unsupported` | those that declare one | R2 |
| `dependency_rejected` | result, revive, in-trip ads, booster use | the start it names was rejected |
| `unknown_trip`, `unknown_sku`, `unknown_variant`, `not_for_sale` | trips, spends, claims | not in the pack, or not sold |
| `price_mismatch` | spends | the price differs from the catalog's |
| `not_unlocked` | trips, spends, story | the unlock rules of R6 |
| `already_owned`, `already_revived`, `already_doubled`, `already_granted`, `result_exists` | as named | done before |
| `insufficient_funds` | spends | the server's balance is lower |
| `tank_full`, `none_left`, `no_trip`, `no_trip_start`, `no_result`, `not_doublable`, `trip_mismatch` | as named | M05's codes, same meaning |
| `stars_out_of_bounds`, `earnings_out_of_bounds`, `duration_out_of_bounds` | `trip_result` | hard bounds |
| `cap_reached` | trips, ads | the overdraft limit, the daily refill cap, the per-trip ad cap |
| `not_eligible` | modes, gifts, claims | the condition for it is not met |
| `server_only` | `ad_reward` | `morning_piggy` |

Codes are stable lowercase snake case with no content or personal data. M05's own codes keep their
meaning (`specs/007-m05-local-economy/contracts/economy-api.md`); `catalog_mismatch` is M05's alone.

## The direction rule

No accepted operation has `bonat_delta > 0` except `claim_request` and the completion rewards, which
are the server's, and none pairs a BONAT decrease with a JENEHAT increase. The property test checks
both for every operation type.
