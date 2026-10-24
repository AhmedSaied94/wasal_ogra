# Implementation Plan: Accounts and Auth (B02)

**Branch**: `009-b02-accounts-auth` | **Date**: 2026-10-24 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/009-b02-accounts-auth/spec.md`

## Summary

B02 gives every phone a server account without a screen, keeps its session alive, and lets the
player link Google without ever merging or losing progress silently.

- **Accounts.** `POST /v1/auth/anonymous` turns a v4 install id into a `Player` and a `Device`.
  - The device record is the anonymous identity, and the install id always leads to its device's
    player, linked or not (Clarifications).
  - Backend §22.6 is resolved: the app keeps the install id across a re-install (M06), so the same
    phone gets its player back.
  - A race of requests with one id still gives one player.
- **Sessions.** simplejwt tokens (HS256, a `kid` key ring for rotation): access 15 min, refresh
  30 days.
  - Our own `PlayerSession` table, not simplejwt's blacklist app, rotates and blacklists on use.
  - A lost answer retried within 60 s gets the same successor, byte for byte.
  - Any older token ends its session as reuse.
  - At most 10 live sessions per player.
- **Linking.** `POST /v1/auth/link` verifies Google ID tokens with PyJWT against Google's cached
  keys, and keeps only the subject.
  - A Google account held by another active player gives `409 provider_in_use` with two
    summaries.
  - `switch_to_existing` moves the device. `keep_current` moves the identity. A retry names the
    player it answers, so it can't act on a changed conflict.
- **Around it:**
  - per-player limits for all authenticated traffic, and creation at 60/hour per address,
    because of carrier-grade NAT;
  - the two client headers required on player endpoints;
  - a status check on every request, so deletion bites at once;
  - a read-only player admin with a tester flag;
  - the manifest stays public.

Decisions and alternatives: [research.md](./research.md).

## Technical Context

**Language/Version**: Python 3.13 with uv (backend). No mobile code in this feature.

**Primary Dependencies**:

- New: `djangorestframework-simplejwt==5.5.1` (locked by the constitution) and `PyJWT[crypto]==2.15.1`
  (simplejwt's JWT layer, and the Google check; `cryptography` is already locked).
- New for development: `time-machine==3.5.1`.
- Everything else is B01's stack: Django 5.2, DRF, drf-spectacular, Celery and beat, hypothesis
  and schemathesis (R16).

**Storage**:

- PostgreSQL 17: `Player`, `Device`, `Identity`, `PlayerSession` (data-model.md). Sessions and the
  retry window are in the database, never the cache (R3).
- Valkey: throttle counters only.

**Testing**:

- pytest-django on real PostgreSQL and Valkey.
- hypothesis stateful tests, with a 300-example CI profile and a 10,000-example `thorough` one.
- time-machine for lifetimes and the 30-day simulation.
- A local JWKS server and a test RSA key for Google tokens.
- schemathesis with an auth hook.
- Coverage at least 80% (R15).

**Target Platform**: The API role on B01's two ARM64 Always Free VMs. The admin role serves the
player view.

**Project Type**: A backend feature: a Django app's models, services, API and admin, plus settings,
throttles and the error mapping in `apps/common`.

**Performance Goals**:

- `anonymous` and `refresh` at p95 ≤ 150 ms, and `link` at p95 ≤ 1 s with the keys cached
  (SC-009).
- 1,000 renewals from one address in one minute without a refusal (SC-008).

**Constraints**:

- Constitution: access 15 min, refresh 30 days, rotated and blacklisted on use.
- No personal data beyond the Google subject.
- No email, name or picture is stored or logged.
- No new paid service: Google sign-in is free.
- Expand-only migrations.

**Scale/Scope**:

- About 30k monthly players at 10k DAU; the design point is 100k DAU.
- About 4 renewals per active player-hour.
- Up to 10 live sessions per player, and sessions pruned 30 days after they end or lapse.

## Constitution Check

*GATE: passed before Phase 0, and re-checked after Phase 1 below.*

| # | Principle | Applies | How B02 satisfies it |
| --- | --- | --- | --- |
| I | Engine purity | No | No trip rule is touched. |
| II | Integer money | Lightly | The conflict summary's `bonat` and `driver_level` are integers. No money is computed. |
| III | Parity | No | No engine change, no fixtures. |
| IV | Server authority | Yes | Linking and resolving never move currency, purchases or progress between players (FR-028), and accounts are never merged. B02 grants no currency (FR-006). Identity is decided on the server. |
| V | Offline-first | Yes | The account is created in the background, and a refused or failed creation never blocks play (FR-033). The manifest stays public, so content updates don't wait for an account (FR-035). Losing a session never needs the player: the install id brings it back (FR-005). |
| VI | Idempotency | Yes | The three auth endpoints are credential exchanges, which constitution 1.5.0 makes idempotent on their own credential, never stored in `ProcessedOp` (their results hold tokens). Creation is idempotent on the install id, also under races (R4). Renewal is idempotent on the session and `jti`: the same successor comes back within the retry window (R3). Linking is idempotent on the provider subject, so a repeat changes nothing (FR-024). The property tests prove that repeating a request gives the same outcome. Server time is the only clock for lifetimes. |
| VII | Content, not code | Lightly | No player-visible text: error messages are fixed English strings for developers (B01). `ch1_first_job` in the stand-in summary is a glossary identifier, which B03 replaces with the player's real chapter. |
| VIII | Tunable numbers | No | The session cap, retry window and rate limits are server protections, set as environment settings, like B04's thresholds. None is a balancing number. |
| IX | No ads in a trip | No | — |
| X | RTL and Arabic first | No | No screens. The admin view is staff-only. |
| XI | Accessible minimums | No | No screens. |
| XII | No runtime LLM | No | — |
| XIII | Small, testable features | Yes | Tests come first for issuing, renewal, reuse, the cap, Google verification and link resolution. Backend tests run on real PostgreSQL and Valkey. The hypothesis state machine covers the invariants. schemathesis covers the endpoints. One feature, one folder, one PR. |

**Locked stack.** simplejwt is used as the constitution names it (R1): its tokens, its backend and
its authentication flow. Its optional `token_blacklist` app is replaced by our session table. That
is a design choice inside the locked library, not a stack change. Backend §12's sentence naming
the blacklist tables is updated (FR-041). `PyJWT` is simplejwt's own dependency, pinned directly
because B02 also calls it.

**Architecture boundaries.**

- **Business logic** is in `apps/accounts/services/` (`players`, `sessions`, `tokens`,
  `google`, `linking`, `summary`). Views and serializers only validate and call services.
- **Errors** use B01's envelope. Two codes are added to backend §6.2 and B01's `contracts/api.md`
  first (R8).
- **Keys and migrations:** UUIDv7 keys, checked by `common.E001`. Expand-only migrations
  (data-model.md).
- **Stateless:** no per-process state except Google's cached public keys, which any process can
  fetch again.
- **Outbound call:** fetching Google's keys happens in the request with a 5 s timeout, because
  linking can't wait for a queue. It is the same kind of exception the constitution makes for
  purchase verification. It reads public keys and changes nothing remote, so no retry path is
  needed: a failure answers 503, and the app retries.

**Security & privacy.**

- **Tokens:** access 15 min and refresh 30 days, rotated and blacklisted on use.
  - A renewal repeated within the 60 s retry window gets the same successor. Any other reuse of a
    spent token is refused and ends the chain (constitution 1.5.0, "Security & privacy").
  - Signing keys come from host secrets with `kid` rotation, refused at startup when missing or
    placeholders (R13).
- **Google tokens:** checked for signature, `iss`, `aud`, `exp` and `iat` (R6).
- **Minimal data:** no email, phone or name stored. Install ids are hashed. Nothing sensitive is
  logged (R14).
- **Every endpoint is rate-limited:** per player when authenticated, per session for renewals, per
  address otherwise (R9).
- **Strict input:** serializers check v4 UUIDs, enums and length caps. There is no raw SQL.
- **The player admin** is staff-only, on the 2FA admin over WireGuard, and read-only apart from
  the tester flag (R12).
- **A security review** is required before merge (FR-043): this changes auth and personal data.

**Post-design re-check (after Phase 1).** It still passes, with no Complexity Tracking entry. The
design changes four documented details, each recorded and updated in the same PR (R17):

- **The anonymous identity is the `Device` row**, not an `Identity` row (backend §12). It follows
  from the owner's FR-005 answer.
- **Sessions replace simplejwt's blacklist tables** (backend §12). This is still simplejwt.
- **Account creation is limited at 60/hour per address**, not §6.5's 10 (R9). The B01 hand-over
  on carrier-grade NAT asked for this.
- **The `link` retry carries `existing_player_id`**, and the token answer gains
  `access_expires_in` and `providers` (backend §6.4). These are additions, and no client exists
  yet.

## Project Structure

### Documentation (this feature)

```text
specs/009-b02-accounts-auth/
├── plan.md              # This file
├── research.md          # R1–R17 and the hand-over list
├── data-model.md        # Player, Device, Identity, PlayerSession; transitions; migrations
├── quickstart.md        # Local checks and the owner's live checks on staging
├── contracts/
│   ├── api.md           # the three endpoints, answers, errors (shared with M06, M14)
│   ├── tokens.md        # tokens, sessions, rotation, keys, client obligations
│   ├── environment.md   # new settings and where they go
│   └── admin.md         # the player admin and the player_support group
├── checklists/requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
backend/
├── pyproject.toml, uv.lock             # + simplejwt, PyJWT[crypto]; dev + time-machine
├── .env.example                        # + AUTH_*, GOOGLE_*, THROTTLE_* (contracts/environment.md)
├── config/
│   ├── env.py                          # + signing_keys(), auth() readers and their checks
│   └── settings/base.py, test.py       # + auth settings, DEFAULT_AUTHENTICATION/PERMISSION/THROTTLE classes
│   └── urls.py                         # + /v1/auth/anonymous, /refresh, /link
├── apps/common/
│   ├── client.py                       # new: X-Client-Version / X-Platform parsing (moved from content)
│   ├── permissions.py                  # new: ClientHeaders
│   ├── throttles.py                    # + PlayerRateThrottle, RefreshThrottle, AnonymousThrottle, LinkThrottle; address skips players
│   └── errors.py                       # + the four auth codes, provider_*; NotAuthenticated/AuthenticationFailed mapping
├── apps/content/services/manifest.py   # imports the version parser from common.client
├── apps/accounts/
│   ├── models.py                       # + Player, Device, Identity, PlayerSession (User unchanged)
│   ├── authentication.py               # PlayerAuthentication
│   ├── tokens.py                       # KeyRingBackend, PlayerAccessToken, PlayerRefreshToken
│   ├── services/
│   │   ├── players.py                  # create-or-return by install id (R4)
│   │   ├── sessions.py                 # open, rotate, replay, reuse, cap, prune (R3)
│   │   ├── google.py                   # GoogleKeys + verify_id_token (R6)
│   │   ├── linking.py                  # link, conflict, switch, keep_current (R7)
│   │   └── summary.py                  # summarize(player); B03 fills it
│   ├── api/{serializers.py,views.py,messages.py}   # the three endpoints, thin; fixed error messages
│   ├── admin.py                        # + PlayerAdmin with inlines (contracts/admin.md)
│   ├── tasks.py                        # prune_sessions (bind=True, retries)
│   ├── management/commands/auth_signing_key.py
│   ├── migrations/0002_players.py, 0003_player_support_group.py, 0004_prune_sessions_schedule.py
│   └── tests/                          # test_anonymous, test_sessions, test_tokens, test_google,
│                                       # test_linking, test_throttles, test_headers, test_admin_players,
│                                       # test_properties (hypothesis), test_privacy_scan, conftest (keys, JWKS server)
└── tests/
    ├── test_contract.py                # + auth hook for player endpoints
    └── test_settings_guards.py         # + AUTH_SIGNING_KEYS refusals
contracts/openapi.yaml                  # + the three paths, bearerAuth, the new schemas
apps/mobile/lib/core/network/http_client.dart   # comment only: the manifest stays public (FR-035)
docs/                                   # backend §6.2–6.5, §12, §13, §14.2, §22.6; mobile §16;
                                        # runbooks/auth-keys.md (new), runbooks/README.md;
                                        # owner-actions.md (B02), delivery-plan.md (progress)
CLAUDE.md                               # B02 overview line; auth_signing_key and the thorough property run
```

**Structure decision.** Everything lives in the existing `apps/accounts` (backend §5 names it for
"players, identities, devices, JWT, linking"), next to B01's staff `User`. The cross-cutting
pieces that every later endpoint inherits go in `apps/common`, where B01 put the address throttle
and the envelope: the throttles, the header permission and the error mapping.

## Delivery

One PR. It merges when:

- CI is green, including the 80% coverage gate and the OpenAPI drift check;
- the thorough property run has passed once (quickstart A1);
- the security review is done;
- the owner's "Before merge" items are done: the Google Cloud project and clients, and the
  staging and prod signing keys and client ids in the host env files. Without them the deploy
  stops at startup by design.

Quickstart Part B runs on staging after the merge deploys it. It unblocks B03 (spec 010), then M06.

## Owner actions (added to `docs/owner-actions.md` by `/speckit-implement`)

**Before merge:**

- **Google Cloud project** (free), "Google Auth Platform":
  - **Branding:** app name and support email. Leave the app in **Testing**, with the owner's
    accounts as test users, until the real domain exists. Moving it to **In production** needs a
    privacy-policy URL on that domain, and is a before-closed-test item.
  - **The server (web) client:** its id goes into `GOOGLE_OAUTH_CLIENT_IDS`. Add the OAuth
    Playground's redirect URI for the live check. Keep its secret off the hosts: the server never
    needs it.
  - **Three Android clients:**
    - `com.wassalogra.app.dev`, with the debug keystore's SHA-1;
    - `com.wassalogra.app.staging`, with its signing SHA-1;
    - `com.wassalogra.app`, with Play App Signing's SHA-1 once Play Console has it, plus the upload
      key's.

    M06 needs these. B02 needs only the server client.
- **Each host:** add `AUTH_SIGNING_KEYS` (from `manage.py auth_signing_key`, a different key per
  environment) and `GOOGLE_OAUTH_CLIENT_IDS` to `/etc/wassal/staging.env` and
  `/etc/wassal/prod.env`.

**After merge:**

- Run quickstart Part B on staging and record it in the PR.
- Add calendar reminders for key rotation (yearly, or at once if a key may have leaked:
  `docs/runbooks/auth-keys.md`).
- Before the closed test: publish the Google Auth Platform app to "In production" once the domain
  and privacy policy exist.

## Complexity Tracking

No constitution violations. Nothing to justify.
