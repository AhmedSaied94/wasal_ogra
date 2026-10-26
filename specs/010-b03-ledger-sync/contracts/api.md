# Contract: The Three Endpoints

`GET /v1/bootstrap`, `GET /v1/state` and `POST /v1/sync`. Shared with M06 (the client of all three)
and committed as `contracts/openapi.yaml`. Conventions are backend §6.1: JSON, `snake_case`,
integers for money and counts, ISO-8601 UTC timestamps.

## Access (all three)

- `Authorization: Bearer <access>` (B02), `X-Client-Version` and `X-Platform` required, else
  `validation_error` (headers) or the B02 token errors.
- A player pending deletion or deleted: `403 account_deleted`. No endpoint takes a player id.
- Throttles: the player default (120/min) on all three; `POST /v1/sync` also 60/min per player.
  `429 rate_limited` carries `Retry-After`.
- Every answer carries `X-Request-ID` (B01). Error bodies are the envelope.
- The first call of any of the three creates the player's wallet if it does not exist (FR-011).

## `GET /v1/bootstrap`

Starts or continues a session (research R13) and answers where the player stands. It always answers
200 for a valid player, even to an app below the minimum version.

```json
{
  "server_time": "2026-10-17T09:00:00Z",
  "player": { "player_id": "…", "display_name": "الأسطى حمادة", "driver_level": 4, "country": "EG",
              "providers": ["google"] },
  "wallet": { "jenehat": 1240, "bonat": 35, "fuel": 3, "fuel_max": 5,
              "fuel_updated_at": "2026-10-17T08:41:00Z", "fuel_unlimited_until": null },
  "entitlements": { "remove_ads": false, "subscription": null, "season_passes": [],
                    "flags": { "no_interstitials": false, "fuel_max_bonus": 0 } },
  "state_version": 42,
  "content": { "version": 7, "manifest_url": "/v1/content/manifest" },
  "client": { "min_version": "1.0.0", "latest_version": "1.0.0", "force_update": false },
  "daily": { "game_date": "2026-10-17", "challenge_available": false, "reward_claimable": false },
  "comeback": { "claimable": false }
}
```

- `wallet.fuel` is the liters **now** (recounted to the server's time); `fuel_updated_at` is the
  countdown anchor (M05's `countedFrom`), so the app can rebuild its countdown.
- `entitlements` is neutral until B06 (`remove_ads: false`, `subscription: null`, no passes).
- `content.version` is the current published version of the `core` pack (the manifest's).
- `client.force_update` is true when `X-Client-Version` is below `min_version` (B10 makes the
  values live).
- `daily` is neutral until B08 and M13.
- `comeback.claimable` is true while `comeback_return_at` is set, no gift was granted for that
  return, and the cooldown has passed (research R9). It stays true until the claim is synced.

Errors: the access errors, `429`, `503 dependency_unavailable`.

## `GET /v1/state`

A full snapshot at one `state_version`. It is read under a shared lock on the wallet row, so no
batch applies in the middle.

```json
{
  "state_version": 42,
  "server_time": "2026-10-17T09:00:00Z",
  "player": { "display_name": "…", "driver_level": 4, "settings": { "digits": "arabic" } },
  "wallet": { "jenehat": 1240, "bonat": 35, "fuel": 3, "fuel_max": 5,
              "fuel_updated_at": "…", "fuel_unlimited_until": null },
  "inventory": { "change_bag": 2, "wake_all": 0, "ledger_peek": 1, "traffic_jam": 0 },
  "ownership": [ { "kind": "vehicle", "sku_id": "micro_old", "variant": "" },
                 { "kind": "item", "sku_id": "salon.nish", "variant": "classic" } ],
  "trips": [ { "trip_id": "line_hay.01", "best_stars": 3, "best_time_ms": 91200, "plays": 4 } ],
  "open_trip": { "start_txn": "…", "trip_id": "line_hay.05", "content_version": 7,
                 "revived": false, "traffic_jam_ads": 0 },
  "last_result": { "start_txn": "…", "outcome": "finished", "earnings_jenehat": 46, "doubled": false },
  "story": { "chapters": [ { "chapter_id": "ch1_first_job", "status": "open", "scenes_seen": ["intro"] } ],
             "requests_claimed": ["req_chandelier"] },
  "grants": { "tutorial": true },
  "stats": { "trips_played": 31, "stars_total": 58, "longest_streak": 0 },
  "comeback": { "claimable": false }
}
```

- `open_trip` and `last_result` are `null` when there is none.
- The shape is what M05's `replaceBase` needs, plus the profile. It holds nothing about any other
  player, and nothing that identifies the player beyond their own chosen name (FR-039).
- `ownership` and `trips` may name ids the active pack lacks; readers skip them (M04 hand-over).

## `POST /v1/sync`

```json
{
  "base_state_version": 41,
  "ops": [
    { "client_txn_id": "0192f1d0-…", "op_type": "trip_start", "occurred_at": "2026-10-17T09:12:03Z",
      "payload": { "trip_id": "line_gamaa.12", "content_version": 7, "fuel_mode": "fuel" } }
  ]
}
```

Limits: at most 100 operations, at most 256 KB of body (the edge stops 512 KB first). The operations
are processed in array order in one transaction (research R5). Payloads are in
[operations.md](./operations.md).

```json
{
  "state_version": 42,
  "state_stale": false,
  "results": [
    { "client_txn_id": "0192f1d0-…", "status": "accepted" },
    { "client_txn_id": "0192f1d9-…", "status": "rejected", "reason": "insufficient_funds" }
  ],
  "wallet": { "jenehat": 1286, "bonat": 4, "fuel": 2, "fuel_max": 5,
              "fuel_updated_at": "…", "fuel_unlimited_until": null }
}
```

- `results` has one entry per operation, in order. An entry may carry `granted` (operations.md).
- `state_version` is the version after the batch. It changes only if something changed.
- `state_stale` is true when `base_state_version` differed from the version before the batch. The
  operations were still validated against the server's state. The app then calls `GET /v1/state`.
- `wallet` is after the batch, with `fuel` recounted to the server's now.
- An empty `ops` list answers 200 with the current values.
- Sending the same batch again returns the same `results` and changes nothing.

### Errors (the whole request)

| HTTP | `code` | When |
| --- | --- | --- |
| 400 | `validation_error` | the body or an operation's envelope is malformed: `details.fields` names each problem by its dotted path (`{"ops.3.client_txn_id": ["…"]}`). Objects are closed: an unknown key is named too (`additionalProperties: false` in the OpenAPI), and so is an `op_type` outside `^[a-z][a-z0-9_]{0,39}$`. A body nested too deeply to parse is this error too |
| 400 | `batch_too_large` | more than 100 operations (`details.max`) |
| 401 / 403 | B02 codes | token missing, invalid, expired; account deleted |
| 413 | `payload_too_large` | a body over 256 KB (`details.limit_bytes` = 262144) |
| 415 | `unsupported_media_type` | not JSON |
| 429 | `rate_limited` | the limits above |
| 503 | `dependency_unavailable` | the database or cache is down; nothing was applied |

A rejection of one operation is **not** an error: the request answers 200. A rejected
`validation_error` operation names its field in the entry's `details.field` (such as `trip_id`,
`result.stars` or `display_name`), never the value.

## Versioning

These are `/v1` and additive from here: new optional fields, new operation types, new reasons. A
phone must treat an unknown `reason` as a generic rejection, and ignore unknown fields.

## Idempotency

`client_txn_id` plus `ProcessedOp` (constitution VI). The three endpoints are not credential
exchanges. `GET` requests change nothing except `last_active_at` and the session markers of
bootstrap (research R13), which are idempotent within a session.
