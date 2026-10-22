# Contract: Operations

What each request becomes when it applies: the wire payload M06 sends in `POST /v1/sync` (backend
§7.3, §7.4), its effects, its reason (backend §7.2) and its refusals. All amounts are integers, and
every payload's keys are snake case. The stored `payload` is canonical JSON: keys in UTF-16 order,
no whitespace, integers only (the same form as `content_models`' `canonicalJson`).

Common to every operation: it is first regenerated to its `occurred_at` (contracts/fuel-and-time.md),
and its row records `txn_id`, `occurred_at_ms`, `content_version`, `fuel_max` and
`fuel_regen_minutes` (data-model.md).

## `trip_start`

| | |
| --- | --- |
| Request | `startTrip(id, tripId)` |
| Payload | `{"trip_id": "line_hay.03", "content_version": 1, "fuel_mode": "fuel"}`, or `"fuel_mode": "unlimited"` inside a window |
| Effects | `fuel_delta = −1` in `fuel` mode, 0 in `unlimited` mode. Sets `unfinished`. |
| Reason, ref | none, none |
| Local column | `max_earnings_jenehat` from the active pack's definition |
| Refusals | `unknown_trip`, `trip_unfinished`, `no_fuel` |

`fuel_mode: challenge` (the daily challenge's free attempt) is M13's.

## `trip_result`

| | |
| --- | --- |
| Request | `recordResult(id, start, result)` |
| Payload | `{"trip_start_txn": "<uuid>", "result": <TripResult.toJson()>}` |
| Effects | `jenehat_delta = result.earnings_jenehat` (0 for failed or abandoned). `trip_progress` updated. Clears `unfinished` and sets `lastResult`. |
| Reason, ref | `trip_earnings`, the start |
| Refusals | `result_exists` (`start` is the latest result's start), `no_trip_start` (`start` isn't the unfinished start), `trip_mismatch`, `stars_out_of_bounds`, `earnings_out_of_bounds` |

## `ad_reward`

Payload `{"ad_placement": "<placement>", "ref": "<uuid>"}`. `ref` is omitted for `fuel_refill`,
which belongs to no trip. Backend §7.4 lists `ref` for every `ad_reward`, so this PR records the
exception there (research R21), and B03 accepts a `fuel_refill` without one.

| Placement | Effects | Reason | Ref | Refusals |
| --- | --- | --- | --- | --- |
| `result_double` | `jenehat_delta = lastResult.earnings`. Marks it doubled. | `ad_result_double` | the latest result's start | `no_result`, `not_doublable`, `already_doubled` |
| `fuel_refill` | fuel to the maximum; `fuel_delta = max − liters` | none | none | `tank_full` |
| `trip_revive` | sets `unfinished.revived` | none | the unfinished start | `no_trip`, `already_revived` |
| `traffic_jam` | `unfinished.trafficJamAds` + 1 | none | the unfinished start | `no_trip`, `cap_reached` |
| `morning_piggy` | never applied on the device | — | — | `server_only` |

## `spend_jenehat`

Payload `{"sku_kind": "item", "sku_id": "salon.nish", "variant": "classic", "price": 400}`, with
`variant` only for items.

| `sku_kind` | Effects | Reason |
| --- | --- | --- |
| `item` | `jenehat_delta = −price`; ownership with the variant | `item_purchase` |
| `vehicle` | `jenehat_delta = −price`; ownership | `vehicle_purchase` |
| `chapter` | `jenehat_delta = −price`; ownership | `chapter_purchase` (new, research R7) |

Refusals: `not_for_sale`, `catalog_mismatch`, `unknown_sku`, `unknown_variant`, `already_owned`,
`insufficient_funds`.

## `spend_bonat`

Payload `{"sku_kind": "booster", "sku_id": "change_bag", "price": 10}`. A revive adds
`"ref": "<uuid>"` (research R7, hand-over to B03).

| `sku_kind` / `sku_id` | Effects | Reason | Extra refusals |
| --- | --- | --- | --- |
| `booster` / one of `change_bag`, `wake_all`, `ledger_peek`, `traffic_jam` | `bonat_delta = −price`; inventory + 1 | `booster_purchase` | — |
| `fuel` / `refuel_full` | `bonat_delta = −price`; fuel to the maximum | `fuel_purchase` | `tank_full` |
| `fuel_unlimited` / `fuel_unlimited_1h` | `bonat_delta = −price`; window + 60 min from `max(now, end)` | `fuel_unlimited_purchase` (new) | — |
| `revive` / `revive` | `bonat_delta = −price`; sets `unfinished.revived` | `revive_purchase` | `no_trip`, `already_revived` |

Refusals for all: `not_for_sale`, `catalog_mismatch`, `unknown_sku`, `insufficient_funds`.

## `use_booster`

| | |
| --- | --- |
| Request | `useBooster(id, booster)` |
| Payload | `{"booster_id": "wake_all", "ref": "<uuid>"}` |
| Effects | inventory − 1 |
| Reason, ref | none, the unfinished start |
| Refusals | `no_trip`, `unknown_sku` (not one of the four), `none_left` |

## Validation order

Each request checks its refusals in the order listed above, and the first that applies is
returned. Common checks come first: a repeated id returns the stored outcome before anything else
(FR-016).

A purchase checks `not_for_sale`, `catalog_mismatch` (the wrong currency for the kind, or a price
below 0), `unknown_sku`, `unknown_variant` and `already_owned`, then the kind's own state
(`tank_full`; `no_trip`, `already_revived`), and `insufficient_funds` last, so a purchase that
couldn't apply is never reported as unaffordable.

## In the fold (research R6)

Validation against content and the catalog isn't repeated: the row records what applied. Balance,
ownership, inventory and trip-linkage checks are repeated, and an operation that fails one is left
out of the projection. Its row and its `pending` status stay. Fuel is lenient: an empty tank holds
at 0, and a refill on a full tank adds nothing.

## What M06 sends

`pendingOps()` returns rows with `sync_status = pending` in `seq` order. M06 maps each to
`{client_txn_id, op_type, occurred_at (ISO 8601 UTC from occurred_at_ms), payload}`. The local
columns (`max_earnings_jenehat`, the deltas, `fuel_max`, `fuel_regen_minutes`, `reason`) aren't
sent: the server computes its own.

## The direction rule (FR-012)

No operation in this table has `bonat_delta > 0`, and none pairs `bonat_delta < 0` with
`jenehat_delta > 0`. `test/core/economy/domain/direction_test.dart` builds every operation type and
placement and checks both.
