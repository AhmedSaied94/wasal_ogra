# Contract: Tokens, Sessions and the Client's Part (FR-009–FR-018)

The rules both sides follow. The server's half is built in B02. The client's half
("Client obligations") is M06's (spec 011), and M14's for linking. Research: R2, R3, R13.

## Tokens

| | Access | Refresh |
| --- | --- | --- |
| Lifetime | 15 min | 30 days from issue, renewed by each rotation |
| Sent as | `Authorization: Bearer <access>` | the `refresh` field of `POST /v1/auth/refresh` |
| Algorithm | HS256 | HS256 |
| Header | `{"alg": "HS256", "kid": "<key id>", "typ": "JWT"}` | same |
| Claims | `token_type: "access"`, `sub` (player id), `sid` (session id), `jti`, `iat`, `exp` | `token_type: "refresh"`, `sub`, `sid`, `jti`, `iat`, `exp` |
| Personal data | none (FR-015) | none |

- Tokens are opaque to the app. It must not depend on their claims. It reads
  `access_expires_in` from the answer instead.
- **Verification on the server:**
  - the signature, with the key that `kid` names in the ring;
  - `exp`, with no leeway;
  - `token_type`.

  Then, for an access token, the player's status (FR-014), and for a refresh token, the session
  (below).

## Sessions

A session is the chain of refresh tokens from one sign-in on one device. A sign-in is
`POST /v1/auth/anonymous`, or `switch_to_existing`.

- **Independent.** A new sign-in doesn't end the device's or the player's other sessions
  (Clarifications 2026-10-24).
- **Lapse.** A session lapses when its current refresh token expires, 30 days after the last
  renewal.
- **Cap.** At most `AUTH_MAX_SESSIONS_PER_PLAYER` (10) live sessions per player. A sign-in beyond it
  ends the least recently renewed one (`limit`).
- **It ends on:**
  - **reuse:** a spent refresh token outside the retry window;
  - **switch:** `switch_to_existing` on this session;
  - **limit:** the cap.

  Its access tokens may live out their 15 minutes after it ends. Deletion is checked per request
  instead (FR-014).

### Rotation

| Presented refresh token | Answer | Session afterwards |
| --- | --- | --- |
| The current one | New access, **new** refresh | The new refresh is current, and the presented one is previous (spent now) |
| The previous one, spent ≤ `AUTH_REFRESH_RETRY_SECONDS` (60) ago | New access, the **same** refresh as the first answer, byte for byte | Unchanged |
| The previous one after the window, or any older one | `401 token_invalid` | **Ended** (`reuse`). A `refresh_reuse` security event names the player and the session. |
| Any token of an ended session | `401 token_invalid` | Unchanged |
| A well-signed token past its `exp` | `401 token_expired` | Unchanged (lapsed) |

Two renewals that race with the same token both get the same successor.

### Signing keys

- `AUTH_SIGNING_KEYS` is a ring of `kid:key` entries. The first signs, and all of them verify.
- Rotating puts a new entry first. The old entry is removed 30 days and 15 minutes later
  (`docs/runbooks/auth-keys.md`).
- A token whose `kid` has been retired is `token_invalid`. The phone gets back in through its
  install id, so a retirement never locks anyone out.

## Client obligations (M06, M14)

| Situation | What the app does |
| --- | --- |
| First open | Generate a v4 install id once, and keep it where a re-install on the same phone doesn't wipe it (research R5). Never send it anywhere but `POST /v1/auth/anonymous`. |
| First online launch, or no tokens held | `POST /v1/auth/anonymous` in the background. Play never waits for it (constitution V). |
| `429` on account creation | Retry after `retry_after_s`. Keep playing offline. |
| Before a call, `access` within about 60 s of expiry | Renew first |
| A renewal times out or its answer is lost | Retry with the same refresh token within 60 s. The same successor comes back. |
| `200` from a renewal | Store `access` and `refresh` together, in secure storage, before any other call uses them |
| `401 token_expired` on a call | Renew. If renewal answers `token_expired` or `token_invalid`, sign in again with the install id. |
| `401 token_invalid` | Renew once. If that fails too, sign in again with the install id. |
| `403 account_deleted` | Stop calling player endpoints. B09 and M14 define what the screen shows. |
| `player_id` in an answer differs from the stored one (after a switch, or a new player for a deleted one) | Treat it as a different account. Local state follows M06's rules for a new player (spec 011). |
| Before `POST /v1/auth/link` | Send pending sync operations first, so the summaries compare real numbers (spec Edge Cases) |
| `409 provider_in_use` | Show both summaries (M14). Retry with the chosen `resolve` and `details.existing.player_id`. A new 409 means the situation changed: show it again. |
| `200` with a `TokenPair` from `switch_to_existing` | Replace the stored tokens and `player_id`. Don't send the old player's pending operations with the new tokens: they belong to the old player, whose session has ended, and they can't be renewed once its access token expires. |
| `422 provider_token_invalid` | Ask Google for a fresh token once. Otherwise show a neutral failure. Never renew our tokens because of it. |
| Never | Put tokens in logs, analytics or SharedPreferences (constitution) |
