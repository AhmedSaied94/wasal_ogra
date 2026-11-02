# Contract: Environment

## New

| Variable | Default | Range / rule | Meaning |
| --- | --- | --- | --- |
| `LIVEOPS_REFRESH_SECONDS` | `30` | 5–55 | how old a process's settings and offers snapshot may get (research R3); with a request's run time it stays under FR-005's 60 s |
| `FIREBASE_PROJECT_ID` | empty | a Firebase project id, or empty | the Remote Config project (`wassal-ogra`) |
| `REMOTE_CONFIG_SERVICE_ACCOUNT` | empty | a **secret**: the service account's JSON key, or empty | read-only Remote Config access (research R8) |

- Both Firebase variables empty means the drift check reports `not_configured`; neither is required
  in any environment, so a missing value never stops a deploy. One set without the other stops the
  process at startup with the variable's name.
- The key is never logged or put in an exception message. Sentry already sends no local variables
  and cuts outgoing URLs to their origin (`apps/common/sentry.py`), so the token exchange's request
  never reaches it; the check's own errors name the step (`token`, `template`) and the HTTP status
  only. A test makes the token call fail and asserts that neither the key's `private_key_id` nor
  the access token appears in the captured log lines or Sentry event.
- Listed in `backend/.env.example` and the docker env files (empty), and in
  `docs/runbooks/monitoring-setup.md` for where the secret is stored.

## Retired

The variables in research R4's list are removed from `config/env.py`, `.env.example`,
`docker/env/*.env` and B03's `contracts/environment.md` (with a line pointing here). A host that
still sets one gets the system check warning `liveops.W001` at every start (R5).

## Kept

`SYNC_GAME_TIMEZONE`, `SYNC_OP_RETENTION_DAYS`, every `THROTTLE_*`, `CONTENT_INDEX_KEEP`, and every
secret and URL (FR-003).
