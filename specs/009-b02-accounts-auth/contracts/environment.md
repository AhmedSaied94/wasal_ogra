# Contract: Configuration Added by B02

This extends B01's `contracts/environment.md` and B04's. The same startup rules apply: values are
checked when they are read, and a bad value stops the process, naming the variable but never the
value. They are read in every role, so a misconfigured worker fails too.

## Application variables

| Variable | dev | test | staging | prod | Secret | Rule |
| --- | --- | --- | --- | --- | --- | --- |
| `AUTH_SIGNING_KEYS` | `dev1:change-me-…` (in `.env.example`) | a fixed test key (test settings) | from `manage.py auth_signing_key` | from `manage.py auth_signing_key` | **yes** | Required everywhere. Comma-separated `kid:key`, first signs. `kid` matches `^[a-z0-9-]{1,32}$`, unique. Each key is base64url and decodes to ≥ 32 bytes. 1–4 entries. Outside dev and test: no `change-me`, and no key equal to `SECRET_KEY` (research R13). |
| `AUTH_REFRESH_RETRY_SECONDS` | `60` | `60` | `60` | `60` | no | 0–300 (research R3) |
| `AUTH_MAX_SESSIONS_PER_PLAYER` | `10` | `10` | `10` | `10` | no | 1–50 |
| `AUTH_HTTP_TIMEOUT_SECONDS` | `5` | `2` | `5` | `5` | no | 1–15. Fetching Google's keys. |
| `GOOGLE_OAUTH_CLIENT_IDS` | empty, or the dev web client id | `test-client.apps.googleusercontent.com` | the server (web) client id | the server (web) client id | no | Comma-separated. Required on staging and prod. Empty turns `provider: google` into `validation_error` (dev and test only). |
| `GOOGLE_JWKS_URL` | `https://www.googleapis.com/oauth2/v3/certs` | the local test server | default | default | no | Absolute URL, `https://` outside dev and test (B01's `url` reader). Set only by tests. |
| `GOOGLE_KEYS_CACHE_SECONDS` | `3600` | `0` | `3600` | `3600` | no | 60–21600; 0 (no cache) only in dev and test, where made-up `kid`s can't make every request fetch. |
| `THROTTLE_PLAYER_RATE` | `120/min` | as dev | as dev | as dev | no | DRF rate string (research R9). The `no_throttle` fixture turns every limit off. |
| `THROTTLE_ANONYMOUS_RATE` | `60/hour` | | | | no | — |
| `THROTTLE_REFRESH_RATE` | `30/min` | | | | no | — |
| `THROTTLE_LINK_RATE` | `10/min` | | | | no | — |

- The access (15 min) and refresh (30 days) lifetimes are constants, set by the constitution. They
  are not variables.
- `THROTTLE_ADDRESS_RATE` (B01) still limits unauthenticated requests, but no longer requests
  authenticated as a player.

## Where the values go

| Host file | Adds |
| --- | --- |
| `/etc/wassal/staging.env` (staging host), `/etc/wassal/prod.env` (prod host) | `AUTH_SIGNING_KEYS` (each environment's own, never shared) and `GOOGLE_OAUTH_CLIENT_IDS` |
| `backend/.env.example` | Every variable above, with the dev values and a `change-me` key |
| `backend/docker/env/*.env` | Nothing: these are sizing files, not settings |

- Only the `api` role verifies tokens. The others read the variables because every role validates
  every setting (B01 rule 3).
- After a key change, the runbook recreates `api`.

## Outbound network

| From | To | Why | Timeout |
| --- | --- | --- | --- |
| `api` | `https://www.googleapis.com/oauth2/v3/certs` | Google's signing keys (research R6), at most once an hour per process, plus once for an unknown `kid` | `AUTH_HTTP_TIMEOUT_SECONDS` |

The hosts already allow outbound HTTPS (B01). Nothing new opens inbound.
