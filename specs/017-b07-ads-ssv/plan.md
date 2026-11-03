# Implementation Plan: Ads — AdMob SSV Callback, Reward Polling and Caps (B07)

**Branch**: `017-b07-ads-ssv` | **Date**: 2026-11-03 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/017-b07-ads-ssv/spec.md`

## Summary

B07 lets the server, and only the server, grant the morning piggy's JENEHAT and BONAT once Google
confirms the ad was watched. The app can ask whether the reward has arrived, a late reward is
announced on the next session, and every ad placement's cap is proven on the server.

- **The callback.** A new `ads` app with `GET /v1/ads/ssv`. It opts out of the player defaults
  (token, headers, version gate) and is throttled per address at 600/min. It verifies the ECDSA
  signature on the raw query string against Google's AdMob verifier keys. Those keys are held per
  process for 24 h, refetched for an unknown key id at most once a minute, and served fast-fail
  during an outage; this is B02's Google-keys pattern with `cryptography`, so no new package (R1–R3).
- **The grant.** One transaction per callback, idempotent on `transaction_id`. The cheap refusals
  come first. Then it takes the player's wallet lock (the one sync takes), checks the reference
  and the daily cap, and writes `ssv_grant` ledger entries through `ledger.apply_now`, which moves
  `state_version`. Every validly signed callback answers 200 and is recorded with its outcome (R4–R6).
- **Asking and showing.** `GET /v1/ads/rewards/{nonce}` answers granted (amounts and wallet),
  refused (reason) or 404. Bootstrap gains `ads.morning_piggy` with `available` and the `unseen`
  rewards. A new sync operation `ad_reward_seen` marks a reward shown, through `ProcessedOp` like
  every write (R7–R9).
- **Live settings.** `ads_morning_piggy_daily_cap` is applied on both sides (1, also added to
  `tunables.json`), and `ads_morning_piggy_jenehat` (30) and `ads_morning_piggy_bonat` (2) are
  server-only, with a rule that they can't both be 0 (R10).
- **Operations.** A Sentry alert when refused signatures pass 20 in an hour or the keys can't be
  fetched. A read-only admin list. A daily cleanup of non-granting records older than 90 days that
  skips during maintenance. Logs never carry the player id or reference (R11–R14).
- **Caps.** One test per placement in glossary §3.4 drives it one past its cap (R15).

Decisions and alternatives: [research.md](./research.md).

## Technical Context

**Language/Version**: Python 3.13 with uv (backend). No mobile code; one shared file edited
(`apps/mobile/assets/config/tunables.json`, one key) and mobile §14.3 and §15.1 in the docs.

**Primary Dependencies**: no new package. Django 5.2, DRF, drf-spectacular, Celery and beat,
`cryptography` (via `PyJWT[crypto]`) for ECDSA, `requests` for the key list, sentry-sdk,
hypothesis, schemathesis, time-machine.

**Storage**: PostgreSQL 17: new table `ads_adreward` with three partial indexes (data-model.md).
Three `liveops_livesetting` rows from B10's `sync_registry_rows`. Valkey: the alert counters (5-minute
buckets) and the once-an-hour alert guards, through Django's cache; the throttle as today.

**Testing**:

- pytest-django on real PostgreSQL and Valkey. Tests come first for signature verification, the
  outcome order, idempotency, the cap, the lookup's answers, `ad_reward_seen` and the cleanup's
  guard (constitution XIII: webhook verification and ledger writers are test-first).
- An `admob_keys` fixture serves a session-generated P-256 public key in AdMob's key-list shape
  from a local HTTP server (as B02's `google_jwks`), and a signing helper builds real signed
  queries. Tampered, unsigned, unknown-key and trailing-parameter cases are recorded as fixtures.
  After the staging deploy, one real Google-signed callback is added with that day's key list
  (quickstart step 6).
- A property test (`apps/ads/tests/test_properties.py`) over random callback sequences (duplicates,
  new transaction ids, game-day boundaries via time-machine): `wallet == sum(ledger)` and at most
  the cap of grants per player per game day (SC-002). Concurrency: two threads deliver one
  transaction id, and two transaction ids for one player; exactly one grant each time.
- B03's ledger-writer AST scan and its ORM-in-handlers check cover the new code unchanged; the
  privacy scan is extended to `apps/ads`. B10's parity test covers the new both-sides key; its
  scheduled-jobs test covers the cleanup.
- `test_placement_caps.py` covers every placement (R15). schemathesis runs over the regenerated
  contract, including the two endpoints, the bootstrap block and `ad_reward_seen`.
- Coverage at least 80% overall; `apps/ads/services` at 100% of lines. B03's economy property test
  runs at 10,000 examples once (the economy is touched).

**Target Platform**: B01's API and worker roles on the two ARM64 Always Free VMs; the callback is
reached through Caddy like every `/v1` path.

**Project Type**: A backend feature: one new Django app (`ads`), small edits in `economy` (bootstrap,
the batch state, one operation), `liveops` (three keys, one rule), `common` (one error code) and the
committed OpenAPI contract.

**Performance Goals**: the callback answers in under 1 s at p95 with the keys held (SC-005), and
typically under 50 ms (one signature check, one transaction). Bootstrap adds two indexed queries
and keeps B03's 200 ms target. The lookup p95 is ≤ 100 ms. Measured by a timing test on the dev
stack (`apps/ads/tests/test_timing.py`, tag `timing`: 100 signed callbacks and 100 lookups with
the keys held, p95 asserted) and once on staging after the deploy.

**Constraints**:

- Constitution IV: BONAT only through this callback; amounts from live settings, never from the
  callback. VI: idempotent on `transaction_id`; the seen mark goes through sync's `ProcessedOp`.
- Expand-only migrations: a new table and data migrations (group permissions, the beat schedule).
- No player id, reference or raw query in logs or Sentry (R13).
- The callback is never gated by the app version or maintenance (R3).

**Scale/Scope**: at most one granted callback per player per day; 10k DAU at launch (about 10k
rows a day, which stay), 100k DAU as the design point. Refused rows are bounded by the 90-day
cleanup.

## Constitution Check

*GATE: passed before Phase 0, and re-checked after Phase 1 below.*

| # | Principle | Applies | How B07 satisfies it |
| --- | --- | --- | --- |
| I | Engine purity | No | No trip rule or engine change. |
| II | Integer money | Yes | Amounts are positive integer columns and int settings; BONAT and JENEHAT are separate entries, never converted (FR-013). No piasters involved. |
| III | Parity | No | No engine or fixture change. |
| IV | Server authority | Yes | `morning_piggy` grants only through the verified callback ("Ad rewards that grant BONAT MUST be verified on the server through AdMob SSV"); the sync path keeps refusing it `server_only`. Every change goes through `ledger.apply_now` with the wallet updated in the same transaction; the AST scan covers the new app. |
| V | Offline-first | Yes | Nothing offline depends on it. The piggy is a network feature (the app shows «محتاج نت», M11). The seen mark is a queued sync op. A key outage answers 503 to AdMob, never to the player. |
| VI | Idempotent everything | Yes | The webhook is idempotent on `transaction_id` (unique, with the race handled). The one new player write (`ad_reward_seen`) carries a `client_txn_id` through sync and `ProcessedOp`. Server time decides the game day and the cap. A property test covers repeats. |
| VII | Content, not code | Yes | No player text in code; the late-reward card's copy is the app's ARB (M11). Admin text is English. |
| VIII | Tunable numbers | Yes, with one entry | The cap is a both-sides live setting with a Remote Config key and a bundled default (parity test). The two amounts are server-only live settings with no Remote Config key: the same deviation B10's Complexity Tracking entry covers. See below. |
| IX | No ads in a trip | No | The server makes no ad calls. `morning_piggy` is shown on Home only (M11). |
| X | RTL and Arabic first | No | No screens. |
| XI | Accessible minimums | No | No screens. |
| XII | No runtime LLM | No | — |
| XIII | Small, testable features | Yes | Test-first for the webhook and the ledger writer; recorded valid and tampered payloads; real PostgreSQL and Valkey; one folder, one PR. |

**Architecture boundaries.**

- **Business logic** in `apps/ads/services/` (`keys.py`, `ssv.py`, `rewards.py`, `status.py`,
  `alerts.py`). Views stay thin; the sync handler is in `economy/services/ops/ads.py` and touches
  only `BatchState`.
- **Dependencies between apps:** `ads` imports `accounts`, `economy` (ledger, gameday, wallets) and
  `liveops` (settings, the task wrapper). `economy` imports two `ads` modules only: `ads.models` in
  `batch.py` (load and flush the unseen set), and `ads.services.status` in `bootstrap.py` (the
  `ads` block). Neither imports anything from `economy`: `ads.models` imports only
  `accounts.models` and `common.models`, and `status.piggy_block(player, game_date, cap)` imports
  only `ads.models`, because the caller passes the game day and the cap. So there is no import
  cycle, and a test (`apps/ads/tests/test_boundaries.py`) checks with an AST scan that those two
  modules never import `apps.economy`.
- **External calls:** one, the key list, synchronous on the request path because the callback must
  answer with a verdict, with a 5 s timeout and the fast-fail window. It runs rarely (once a day
  per process, or on a rotated key). This is like B02's Google keys.
- **Stateless:** the key set and the alert counters are caches; losing them costs one refetch or
  an undercount, never a wrong grant.

**Security & privacy.**

- **Public endpoint:** it accepts nothing it can't verify; a 200 reveals no outcome, and it is
  throttled. Signature checks run before any database access.
- **Replay:** blocked by the unique `transaction_id` and the 7-day expiry, which survives the
  90-day cleanup (FR-006a).
- **Lookup:** scoped to the caller; every not-yours case is the same 404.
- **Logs:** a hashed transaction id only; the privacy scan test covers `apps/ads`.
- **A security review** is required before merge, because this endpoint mints premium currency.

**Post-design re-check (after Phase 1).** It passes, provided the owner approves the one Complexity
Tracking entry below. The design changes these documented details, each updated in the same PR:

- backend §6.2 (`signature_invalid`), §6.3 (unchanged paths, auth column "ECDSA signature" kept),
  §6.4 (the bootstrap `ads` block, the lookup's answers), §7.4 (`ad_reward_seen`), §8.4 (the
  outcome order, 403/503 answers, expiry, alerts, what is recorded), §11.2 (the cleanup job), §12
  (`AdReward` fields: the reward's link to the ledger is `ref_type`/`ref_id`, not a
  `ledger_entry` FK, because a grant makes two entries), §14.2 (the data inventory row);
- mobile §14.3 (the new key; also correct its stale sentence that the backend keeps env settings),
  §15.1 (the lookup's 404, the bootstrap block, `ad_reward_seen`);
- `backend/CLAUDE.md` (what's built, the environment rows, the `admob_keys` fixture),
  `docs/runbooks/` (monitoring: the Sentry alert rule; a short "missing piggy reward" support
  entry), `docs/owner-actions.md` (the Remote Config key, the AdMob callback URL on the piggy's ad
  unit for staging and production, the recorded real callback), `docs/delivery-plan.md` (B07's
  hand-overs);
- B10's Complexity Tracking entry gets a line saying B07 adds two keys under it.

## Project Structure

### Documentation (this feature)

```text
specs/017-b07-ads-ssv/
├── spec.md
├── plan.md              # this file
├── research.md          # R1–R15
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── api.md           # the callback, the lookup, bootstrap's ads block, ad_reward_seen
│   ├── admin.md         # the ad rewards list, permissions
│   └── environment.md   # four new variables
├── checklists/requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
backend/
├── apps/ads/                              # new
│   ├── models.py                          # AdReward + guarded queryset
│   ├── services/
│   │   ├── keys.py                        # Google's verifier keys: cache, refresh, fast-fail
│   │   ├── ssv.py                         # verify, parse, decide, grant (one transaction)
│   │   ├── rewards.py                     # the lookup answer (uses economy's wallet answer)
│   │   ├── status.py                      # bootstrap's ads block (imports only ads.models)
│   │   └── alerts.py                      # 5-minute buckets, Sentry guards
│   ├── api/{views,serializers}.py         # GET /v1/ads/ssv, GET /v1/ads/rewards/{nonce}
│   ├── throttles.py                       # SsvThrottle (per address)
│   ├── tasks.py                           # prune_ad_rewards (skip_in_maintenance)
│   ├── admin.py                           # read-only AdRewardAdmin
│   ├── migrations/                        # 0001 table, 0002 view permissions, 0003 beat schedule
│   ├── management/commands/ads_dev_callback.py  # dev and test only: sign and send a callback (quickstart)
│   └── tests/                             # conftest (admob_keys), signing helper, fixtures/
├── apps/economy/services/ops/ads.py       # + ad_reward_seen
├── apps/economy/services/batch.py         # + unseen set, mark_reward_seen, _flush_seen
├── apps/economy/services/bootstrap.py     # + ads block
├── apps/economy/player_page.py            # + link to the player's ad rewards
├── apps/liveops/registry.py               # + three keys, one rule
├── apps/common/errors.py                  # + signature_invalid
├── config/env.py, config/settings/base.py # + four variables, the app, the throttle rate
├── .env.example, docker/env/*.env
apps/mobile/assets/config/tunables.json    # + ads_morning_piggy_daily_cap: 1
contracts/openapi.yaml                     # regenerated
docs/architecture-backend.md, docs/architecture-mobile.md, docs/runbooks/, docs/owner-actions.md
```

**Structure Decision**: one new app in backend §5's layout (`ads/` is already listed there), with
small, named edits where sync and bootstrap must know about rewards. The dev-only command
`ads_dev_callback` makes the quickstart runnable by hand: it refuses to run unless the environment
is `dev` or `test`. On first use it creates a P-256 dev key in the gitignored `backend/.dev/` and
writes its public half there as an AdMob-shaped key list, `admob_verifier_keys.json`. It then
signs a callback with the dev key and sends it to the running API. The dev stack mounts `backend/` at
`/app`, so the dev `.env` sets `ADS_VERIFIER_KEYS_URL=file:///app/.dev/admob_verifier_keys.json`.
`keys.py` accepts a `file://` URL only when the environment is `dev` or `test`, and the settings
check refuses it anywhere else. Production and staging never see the dev key. No mobile code: M11 consumes
these contracts.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
| --- | --- | --- |
| Constitution VIII asks every balancing number to have a Firebase Remote Config key. `ads_morning_piggy_jenehat` and `ads_morning_piggy_bonat` get a live setting and no Remote Config key. | The phone never applies them. It learns the amounts from the lookup and bootstrap, and the server alone grants BONAT (IV). This is the same case as B10's server-only numbers, whose entry the owner approved on 2026-11-01; VIII has not been amended since. | Adding unused Remote Config keys: dead config that invites someone to "tune" the piggy in the console with no effect. The follow-up is still B10's: amend VIII with `/speckit-constitution` so server-only numbers live only in `liveops.LiveSetting`. **Approved by the owner on 2026-11-03** (analysis finding D1). |
