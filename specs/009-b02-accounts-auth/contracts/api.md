# Contract: The Auth Endpoints (FR-001, FR-009, FR-020)

Three endpoints on the API role. They extend B01's `contracts/api.md`: the error envelope, request
ids, `Cache-Control: no-store`, JSON only, and the 512 KB body limit all apply. This is the shared
contract with M06 (spec 011) and M14. Tokens and sessions: [tokens.md](./tokens.md).

## Common rules

| Rule | Value |
| --- | --- |
| Base path | `/v1/auth/` |
| Required headers | `X-Client-Version`: `MAJOR.MINOR.PATCH` with optional `+BUILD` (`1.4.0+57`). `X-Platform`: `android` \| `ios`. A missing or malformed value gives `400 validation_error` with `details.fields["X-Client-Version"]` or `["X-Platform"]` (FR-034). |
| Body | `application/json`. Unknown fields are ignored. |
| Ids | `player_id` is a UUIDv7 string |
| Player endpoints after B02 | Every endpoint not listed as public needs `Authorization: Bearer <access>` and the two headers above, and is limited per player (FR-019, FR-032) |
| Public endpoints | `/healthz`, `/readyz`, `GET /v1/content/manifest` (FR-035; B04's contract is unchanged), `POST /v1/auth/anonymous`, `POST /v1/auth/refresh`. Store and ad callbacks (B06, B07) will be public too. |

### The token answer (`TokenPair`)

Shared by all three endpoints whenever they issue tokens.

```json
{
  "player_id": "0192f1c3-7d1e-7a4b-9c11-5e2f8a9b0c3d",
  "access": "<jwt>",
  "refresh": "<jwt>",
  "access_expires_in": 900,
  "providers": ["google"]
}
```

| Field | Meaning |
| --- | --- |
| `access` | Access token, 15 min (tokens.md) |
| `refresh` | Refresh token, 30 days from now |
| `access_expires_in` | Seconds until `access` expires: 900, since every answer, a replay included, carries a fresh access token |
| `providers` | Linked providers, in a fixed order: `[]` or `["google"]` (`"apple"` in phase 3) |

## `POST /v1/auth/anonymous`: create or return the device's player (FR-001–FR-008)

Auth: none. Limit: 60/hour per client address (research R9).

```json
// request
{ "install_id": "3b0b9d3e-6f1a-4c8e-9f7a-2d5c1e8b4a90", "platform": "android", "locale": "ar-EG" }
```

| Field | Rule |
| --- | --- |
| `install_id` | A version-4 UUID (any letter case, read as lowercase). Anything else, a v7 included, is `validation_error`. |
| `platform` | `android` \| `ios`, equal to `X-Platform` |
| `locale` | `^[a-z]{2,3}(-[A-Z]{2})?$`, at most 16 characters |

| Outcome | Status | Body |
| --- | --- | --- |
| No device has this install id: a player and a device are created | `201` | `TokenPair` + `"created": true` |
| The device's player is active (linked or not, FR-005) | `200` | `TokenPair` + `"created": false`. A new session opens, and older ones stay (FR-010). |
| The device's player is pending deletion or deleted | `201` | A new player; the device moves to it (FR-004) |

| Error | When |
| --- | --- |
| `400 validation_error` | A field or header rule above |
| `406 not_acceptable`, `415 unsupported_media_type`, `413 payload_too_large` | B01 |
| `429 rate_limited` | The address limit. `details.retry_after_s` and `Retry-After`. The app keeps playing offline and retries. |
| `503 dependency_unavailable` | The database is down |

## `POST /v1/auth/refresh`: renew a session (FR-009–FR-013)

Auth: none (the refresh token is the credential). Limit: 30/min per session; requests whose token
doesn't verify are limited per address (research R9).

```json
// request
{ "refresh": "<jwt>" }
```

| Outcome | Status | Body |
| --- | --- | --- |
| The session's current refresh token | `200` | `TokenPair` with a new `refresh` (tokens.md "Rotation") |
| The session's previous token, spent ≤ 60 s ago (the retry window) | `200` | `TokenPair` with the **same** `refresh` as the first answer, and a new `access` |

| Error | When |
| --- | --- |
| `400 validation_error` | No `refresh` field, an empty one or one over 4096 characters, or a header rule. Any other string is judged by its signature. |
| `401 token_expired` | A well-signed refresh token past its 30 days |
| `401 token_invalid` | Bad signature, unknown `kid`, wrong `token_type`, an ended session, or a spent token outside the retry window, which also **ends the session** (FR-012) |
| `403 account_deleted` | The player is pending deletion or deleted |
| `429 rate_limited` | — |
| `503 dependency_unavailable` | The database is down |

`401` answers carry `WWW-Authenticate: Bearer`.

## `POST /v1/auth/link`: link Google, or resolve a conflict (FR-020–FR-031)

Auth: `Bearer <access>`. Limits: 10/min per player, plus the 120/min per-player default.

```json
// first request
{ "provider": "google", "id_token": "<google id token>" }
// retry after a 409 provider_in_use
{ "provider": "google", "id_token": "<google id token>", "resolve": "switch_to_existing",
  "existing_player_id": "0192e0aa-…" }
```

| Field | Rule |
| --- | --- |
| `provider` | `google`. `apple` (or any other value) is `validation_error` in the MVP (FR-021). `google` is also `validation_error` in an environment with no Google client id configured (dev and test only; research R6). |
| `id_token` | 1 to 4096 characters. Verified as in research R6: any such string that isn't a valid Google token is `422`, never `400`. |
| `resolve` | Optional: `switch_to_existing` \| `keep_current`. Ignored when there is no conflict. |
| `existing_player_id` | Required with `resolve`, forbidden without it. The `details.existing.player_id` of the 409 the player answered. |

| Outcome | Status | Body |
| --- | --- | --- |
| G linked to the current player (new link, already linked, or freed from a non-active holder) | `200` | `{ "player_id": "<current>", "providers": ["google"] }` |
| `keep_current`, and the conflict is still the one shown | `200` | Same as above. G no longer belongs to the existing player. |
| `switch_to_existing`, and the conflict is still the one shown | `200` | `TokenPair` for the **existing** player. The current player's sessions on this device have ended, and the device now belongs to that player. A repeat answers the same way. If the device already went to a third player, `401 token_invalid`. |

| Error | When | `details` |
| --- | --- | --- |
| `400 validation_error` | A field or header rule | `fields` |
| `401 token_expired`, `401 token_invalid` | The access token (tokens.md) | — |
| `403 account_deleted` | The current player is pending deletion or deleted | — |
| `409 provider_in_use` | G belongs to another active player and there is no `resolve`. Or there was a `resolve`, but the conflict has changed (FR-029). | below |
| `409 provider_already_linked` | The current player already has a different Google account (FR-024) | `{ "provider": "google" }` |
| `422 provider_token_invalid` | The Google token fails a check | `{ "provider": "google", "reason": "expired" \| "audience" \| "issuer" \| "signature" \| "malformed" }` |
| `429 rate_limited` | — | `retry_after_s` |
| `503 dependency_unavailable` | Google's keys can't be fetched and none are cached, or the database is down | — |

```json
// 409 provider_in_use
{ "error": { "code": "provider_in_use", "message": "Provider linked to another player", "details": {
  "current":  { "driver_level": 3,  "chapter_id": "ch1_first_job", "bonat": 40 },
  "existing": { "player_id": "0192e0aa-…", "driver_level": 11, "chapter_id": "ch3_shabka", "bonat": 220 } } } }
```

- The summaries show what the server holds now (FR-025). Until B03 fills them, `chapter_id` is
  `ch1_first_job` and `bonat` 0.
- Nothing in the summaries is personal. `existing.player_id` lets the retry name the conflict it
  answers (research R7).

## Error codes added to backend §6.2 (FR-040)

| HTTP | `code` | Message (fixed string) |
| --- | --- | --- |
| 409 | `provider_already_linked` | `Another account of this provider is already linked` |
| 422 | `provider_token_invalid` | `Provider token could not be verified` |

These codes are reused, with messages fixed in `apps.common.errors`:

| HTTP | `code` | Message |
| --- | --- | --- |
| 401 | `token_expired` | `Token expired` |
| 401 | `token_invalid` | `Token invalid` |
| 403 | `account_deleted` | `Account deleted` |
| 409 | `provider_in_use` | `Provider linked to another player` |

DRF's `NotAuthenticated` and `AuthenticationFailed` map to these codes, never to DRF's own
`not_authenticated` and `authentication_failed` (research R8).

## OpenAPI

- **Serializers:** `AnonymousRequest`, `RefreshRequest`, `LinkRequest`, `TokenPair`,
  `AnonymousTokenPair` (with `created`), `LinkResult`, `ConflictSummary` and `ConflictDetails`.
  Each error response points at B01's `ErrorEnvelope`.
- **Headers:** the two required headers are declared as header parameters on each operation.
- **Security:** a `bearerAuth` scheme on `/v1/auth/link`, and on every later player endpoint by
  default.
- **Drift and contract checks:** the committed `contracts/openapi.yaml` gains the three paths.
  B01's drift check and schemathesis cover them (FR-039), with an auth hook that creates a player
  through `/v1/auth/anonymous` on the live server (research R15).

## Performance (SC-009)

- `anonymous` and `refresh`: p95 < 150 ms on staging. Each does a few indexed reads and writes in
  one transaction, plus an HMAC.
- `link`: p95 < 1 s once Google's keys are cached. The verification is local after the first
  fetch per process per hour.
