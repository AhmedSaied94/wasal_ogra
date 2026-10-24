# Quickstart: Validating Accounts and Auth (B02)

How to check that B02 works. Part A runs locally with the dev stack. Part B is the owner's live
check on staging, after the Google Cloud setup in `docs/owner-actions.md` (B02 section). Contracts:
[api.md](./contracts/api.md), [tokens.md](./contracts/tokens.md).

## A. Locally

### Setup

From `backend/`:

```bash
cp -n .env.example .env          # adds AUTH_SIGNING_KEYS and the other B02 values
uv sync
docker compose -f docker/compose.yml -f docker/compose.dev.yml up -d --wait
uv run manage.py migrate
```

### A1. The automated suite

| Command (in `backend/`) | Expect |
| --- | --- |
| `uv run pytest -n 4 --cov --cov-fail-under=80` | Green. It includes the auth tests, the 300-example property run, the CGNAT test (SC-008) and the 30-day simulation (SC-002). |
| `HYPOTHESIS_PROFILE=thorough uv run pytest apps/accounts/tests/test_properties.py` | Green after 10,000 sequences (SC-006). Run once before merge; it takes several minutes. |
| `uv run manage.py spectacular --file ../contracts/openapi.yaml --validate --fail-on-warn && git diff --exit-code ../contracts/openapi.yaml` | No diff: the committed contract has the three endpoints (SC-010) |
| `uv run manage.py makemigrations --check --dry-run` | No changes |
| `uv run ruff check . && uv run ruff format --check . && uv run mypy .` | Clean |

### A2. The flows by hand

The headers every call needs:

```bash
H=(-H 'Content-Type: application/json' -H 'X-Client-Version: 1.0.0+2' -H 'X-Platform: android')
ID=$(python3 -c 'import uuid; print(uuid.uuid4())')
```

| # | Do | Expect |
| --- | --- | --- |
| 1 | `curl -s "${H[@]}" -d "{\"install_id\":\"$ID\",\"platform\":\"android\",\"locale\":\"ar-EG\"}" localhost:8000/v1/auth/anonymous` | `201`, `created: true`, a `player_id`, two tokens, `access_expires_in: 900`, `providers: []` |
| 2 | Repeat 1 | `200`, `created: false`, the same `player_id`, new tokens |
| 3 | Repeat 1 without `-H 'X-Platform: android'` | `400 validation_error`, `details.fields["X-Platform"]` |
| 4 | Repeat 1 with a v7 id (`python3 -c 'import uuid_utils; print(uuid_utils.uuid7())'` in `uv run`) | `400 validation_error` on `install_id` |
| 5 | `curl -s "${H[@]}" -d '{"refresh":"<R1 from 1>"}' localhost:8000/v1/auth/refresh` | `200` with a new refresh R2 |
| 6 | Repeat 5 within a minute | `200` with exactly R2 again (the retry window) |
| 7 | Wait more than 60 s, repeat 5 | `401 token_invalid`. Then 5 with R2 is `401 token_invalid` too: the session ended. The api log has a `refresh_reuse` warning naming the player and session, with no token in it. |
| 8 | 1 again | `200`, the same `player_id`: the phone gets back in with its install id |
| 9 | `curl -s "${H[@]}" -H "Authorization: Bearer <access>" -d '{"provider":"apple","id_token":"x"}' localhost:8000/v1/auth/link` | `400 validation_error` on `provider` (Apple is phase 3) |
| 10 | 9 with `"provider":"google"` and `"id_token":"x"` (with `GOOGLE_OAUTH_CLIENT_IDS` set in `.env`) | `422 provider_token_invalid`, `reason: malformed` |
| 11 | `curl -s "${H[@]}" -d '{}' localhost:8000/v1/auth/link` | `401 token_invalid`, with `WWW-Authenticate: Bearer` |
| 12 | `curl -s localhost:8000/v1/content/manifest` | `200` with no token, as before (FR-035) |

### A3. The admin

1. Create a staff user in the group: `uv run manage.py create_staff support1 --group player_support`,
   then `uv run manage.py staff_totp support1`.
2. Sign in at <http://localhost:8001/admin/>, open Players, and search for the `player_id` from A2.
   - **You see:** its status, platform, client version, created and last seen, the device, and
     "Live sessions: 2" or so.
   - **You don't see:** any token, install id, hash or subject.
3. Tick "Tester" and save. The history shows the change, and no other field is editable.
4. A `content_author` staff user has no Players entry.

## B. Live on staging (owner)

Prerequisites, from the B02 owner actions:

- the Google Cloud project, with the server (web) client and the three Android clients;
- `GOOGLE_OAUTH_CLIENT_IDS` and `AUTH_SIGNING_KEYS` in `/etc/wassal/staging.env`;
- B02 deployed to staging.

Use `API=https://staging-api.141-147-129-92.sslip.io` and the headers from A2.

| # | Do | Expect |
| --- | --- | --- |
| B1 | Steps A2-1 to A2-8 against `$API` | The same results, over HTTPS |
| B2 | Get a real Google ID token for the server client from the [OAuth 2.0 Playground](https://developers.google.com/oauthplayground): ⚙ → "Use your own OAuth credentials" with the web client's id and secret (its redirect URIs list the Playground). Scopes: `openid email profile`. Exchange the code and copy `id_token`. | An `id_token` whose `aud` is the server client id |
| B3 | Link it from player P1 (A2-9 with `google` and that token) | `200`, `providers: ["google"]`. In the staging admin, P1 shows "google". The database holds only the subject: `docker compose exec postgres psql … -c "select provider, length(subject) from accounts_identity"`, with no email anywhere. |
| B4 | Create P2 with a new install id, and link the same token from P2 | `409 provider_in_use`, with `current` (P2) and `existing` (P1, with its `player_id`) |
| B5 | Retry from P2 with `"resolve":"switch_to_existing"` and `existing_player_id` = P1 | `200` with tokens for P1. P2's old access token can't renew. The P2 install id now returns P1 (A2-1). |
| B6 | Repeat B4 to B5 with `keep_current` on a fresh P3 | `200`, P3 has google, and P1 no longer does |
| B7 | **Latency (SC-009):** run 300 account creations and 300 renewals in a loop from your machine, then read the server-side durations from the access log: the full commands are in `docs/runbooks/auth-keys.md` "Measuring latency" | p95 ≤ 150 ms for both. Link p95 ≤ 1 s over 30 links with B2's token. |
| B8 | **Key rotation (SC-004):** follow `docs/runbooks/auth-keys.md` to add a new key first. Then renew a session opened before the rotation. | `200`. Its new tokens carry the new `kid`. Nobody is signed out. |

Record B1–B8 in the PR, and tick the owner actions.
