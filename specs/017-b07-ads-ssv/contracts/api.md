# API contract: B07

The committed `contracts/openapi.yaml` is regenerated from the code and must match this file. The
error envelope and codes are backend §6.2's; `signature_invalid` is new.

## `GET /v1/ads/ssv` — AdMob server-side verification callback

Called by Google, not the app. No token, no `X-Client-Version`/`X-Platform`, no version gate,
works in maintenance. Throttled per client address at `THROTTLE_SSV_RATE` (`600/min`).

**Query** (as AdMob sends it; order matters for the signature, `signature` and `key_id` last):

| Parameter | Use |
| --- | --- |
| `ad_network`, `ad_unit` | recorded |
| `custom_data` | URL-encoded compact JSON `{"placement":"morning_piggy","nonce":"<uuid>"}`, set by the app |
| `reward_amount`, `reward_item` | recorded, never used for the amount |
| `timestamp` | milliseconds since the epoch; older than 7 days → `expired` |
| `transaction_id` | the idempotency key |
| `user_id` | the player id, set by the app |
| `signature` | URL-safe base64 DER ECDSA (P-256, SHA-256) over the query string before `&signature=` |
| `key_id` | integer id of Google's verifier key |

### Answers

| Status | Body | When |
| --- | --- | --- |
| 200 | `{}` | any validly signed callback: granted, duplicate, or recorded as refused or unattributed |
| 403 | `{"error": {"code": "signature_invalid", …}}` | no signature or key id, a signature that doesn't verify, an unknown key after a refresh, or anything after `key_id` |
| 429 | `rate_limited` | the throttle |
| 503 | `dependency_unavailable` | Google's keys can't be fetched and the needed key isn't held; nothing recorded |

A 200 body never says what happened, so the endpoint can't be used to probe players.

## `GET /v1/ads/rewards/{nonce}` — the app asks for its reward

Player defaults: access token, the two headers, the per-player throttle, the version gate.

### 200, granted

```json
{
  "status": "granted",
  "jenehat": 30,
  "bonat": 2,
  "granted_at": "2026-11-03T07:14:22.120Z",
  "wallet": { "…": "B03's wallet answer, recounted to now" }
}
```

### 200, refused

```json
{ "status": "refused", "reason": "cap_reached" }
```

`reason` ∈ `cap_reached`, `not_server_placement`, `expired`. (`malformed` and
`duplicate_reference` rows hold no reference, so they are never found; `unattributed` rows belong to
no player.)

**404 `not_found`**: the reference isn't recorded yet, belongs to another player, is unattributed,
was never used, or isn't a UUID. The app keeps polling (1 s, 2 s, 4 s) and then shows
«هتوصلك المكافأة أول ما توصل».

The lookup never writes.

## `GET /v1/bootstrap` — new `ads` block (required)

```json
"ads": {
  "morning_piggy": {
    "available": true,
    "unseen": [
      { "nonce": "0192f…", "jenehat": 30, "bonat": 2, "granted_at": "2026-11-02T21:59:58.000Z" }
    ]
  }
}
```

- `available`: the player's `granted` piggy rewards on the current game day are fewer than
  `ads_morning_piggy_daily_cap`.
- `unseen`: at most 5 `granted` rewards with no `shown_at`, newest first; `[]` when none.

## `POST /v1/sync` — new operation `ad_reward_seen`

```json
{ "client_txn_id": "<uuidv7>", "op_type": "ad_reward_seen", "occurred_at": "…", "payload": { "nonce": "<uuid>" } }
```

Always `accepted` with `grants: []`. Marks the player's granted, unseen reward with that reference
as shown; any other reference changes nothing. Doesn't move `state_version`. A repeat returns the
stored result (`ProcessedOp`).

`ad_reward` with `ad_placement: "morning_piggy"` stays rejected `server_only`.

## Error code added to backend §6.2

| Code | HTTP | Meaning |
| --- | --- | --- |
| `signature_invalid` | 403 | A webhook's signature is missing or doesn't verify |
