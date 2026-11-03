# Implementation Plan: Live-ops Settings, Store Catalog and Offers (B10)

**Branch**: `016-b10-catalog-offers` | **Date**: 2026-11-01 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/016-b10-catalog-offers/spec.md`

## Summary

B10 gives the server one live place for every balancing number, a gate for apps too old to play,
a maintenance switch that pauses writes and not the game, and the store catalog and offers the shop
and B06 read.

- **Live settings.** A new `liveops` app. The registry in code declares each setting's type, range,
  default and who applies it (phone, server or both); `LiveSetting` rows hold the values. Every
  process re-reads the table every 30 s, so a change applies within a minute without a restart
  (R3). B03's settings reader keeps its shape and reads from here (R4). Eighteen env variables
  are retired, and a host's overrides are imported once on migrate (R5). This ends M01's and B03's
  exceptions to constitution VIII.
- **The version gate.** Two default DRF permissions: `CurrentClient` answers `426 client_outdated`,
  `NotInMaintenance` answers `503 maintenance` on writes (R6, R7). Bootstrap's `client` block is
  live per platform, and the admin shows active players per version before a new minimum is saved
  (R10).
- **Maintenance.** A setting pair (on, optional end), switched in the admin or with a
  `maintenance` command, both in the history. Writing scheduled jobs skip their run (R7).
- **The catalog.** `StoreProduct` with typed grants (seeded 60, 300 + 30, 800 + 120, `remove_ads`)
  and `catalog.grants_for` for B06 (R11). `GET /v1/offers` lists products and eligible offers, never
  a price (R13).
- **Offers.** `Offer` with five validated rule kinds evaluated in Python with a fixed query count,
  and an hourly expiry job (R12). None ships at launch.
- **The drift check.** A daily task reads Remote Config's defaults with a read-only service account
  (PyJWT + requests, no new package), marks drift in the admin, and sends Sentry one warning when a
  setting both sides apply differs (R8).
- **History.** One append-only `LiveopsChange` table for settings, products and offers; a new
  `live_ops` group (R14).

Decisions and alternatives: [research.md](./research.md).

## Technical Context

**Language/Version**: Python 3.13 with uv (backend). No mobile code; one shared file read
(`apps/mobile/assets/config/tunables.json`, by the parity test).

**Primary Dependencies**: no new package. Django 5.2, DRF, drf-spectacular, Celery and beat,
PyJWT[crypto] and requests (the Remote Config call, R8), sentry-sdk, hypothesis, schemathesis,
time-machine.

**Storage**: PostgreSQL 17: new tables `liveops_livesetting`, `liveops_liveopschange`,
`liveops_storeproduct`, `liveops_offer`, `liveops_remoteconfigcheck`; an index on
`economy_wallet.last_active_at` (data-model.md). Valkey: not used by this feature.

**Testing**:

- pytest-django on real PostgreSQL and Valkey; tests first for the rules and range checks, the
  version gate, maintenance, `grants_for`, the offer rules and the env import (constitution XIII).
- The parity test against `tunables.json` (R9), the scheduled-jobs test (every `PeriodicTask` is
  wrapped or listed read-only, R7), the history-is-append-only test, the privacy test of the drift
  check's errors.
- Remote Config calls are tested with a fixture that replaces the module's fetch functions, as B02's
  `google_jwks` fixture does for Google's keys (no new test package), and a real RSA key generated in
  the test to check the signed token; never the real API in CI.
- B03's suites run unchanged except for the `settings` → `live_settings` fixture switch, and B03's
  property test at 10,000 examples once (the economy is touched).
- schemathesis over the regenerated `contracts/openapi.yaml`, with `GET /v1/offers` and the two new
  codes.
- Coverage at least 80%; `liveops/services` and `liveops/permissions.py` at 100% of lines.

**Target Platform**: B01's API and admin roles on the two ARM64 Always Free VMs.

**Project Type**: A backend feature: one new Django app, changes in `common`, `accounts`, `economy`,
`content` (task wrappers) and the committed OpenAPI contract.

**Performance Goals**: `GET /v1/offers` p95 ≤ 150 ms on staging; bootstrap and sync keep B03's
targets (200 ms, 1 s) with zero added queries on the request path (R3, R16). The version page's
aggregate runs under 2 s at 100k active players.

**Constraints**:

- Constitution IV: the catalog defines grants, B06 applies them through the ledger; no price is
  stored. VI: settings change outside batches, and a batch reads one snapshot.
- Expand-only migrations; the retired env variables stop being read in the same release that seeds
  their rows, so no release reads both.
- No secret in logs or Sentry (contracts/environment.md).
- The phone never gets 426 on sign-in, refresh or the manifest, so it can always reach bootstrap.

**Scale/Scope**: about 75 settings, 4 products, a handful of offers; 10k DAU at launch, 100k as the
design point.

## Constitution Check

*GATE: passed before Phase 0, and re-checked after Phase 1 below.*

| # | Principle | Applies | How B10 satisfies it |
| --- | --- | --- | --- |
| I | Engine purity | No | No trip rule changes. The trip tunables are copies; the engine still gets them as `params` from the phone. |
| II | Integer money | Yes | `bonat`, `bonus_bonat` and every setting amount are integers (positive integer columns, `int` kind); piaster settings must be multiples of 50. No real-money amount exists on the server. |
| III | Parity | No | No engine or fixture change. |
| IV | Server authority | Yes | The server alone decides grants (`grants_for`), offers' eligibility and the server-only numbers. The phone is never told a server-only number. |
| V | Offline-first | Yes | Maintenance blocks writes only; reads and offline play go on, and the queue is applied after (US4). Sign-in and refresh are never gated, so a phone can always learn why it is refused. |
| VI | Idempotent everything | Yes | No new operation type. Settings are read once per batch (FR-007). B06 grants idempotently from `grants_for`. |
| VII | Content, not code | Yes | Pack amounts, offers and their rules are data edited in the admin. The only text added is admin-side English (rule texts); no player text. |
| VIII | Tunable numbers | Yes, with one entry | Every key in `tunables.json` gets its server copy, checked by CI (R9), and the B03 server-only numbers leave env settings. The server-only numbers have **no Remote Config key**, because the phone never applies them (IV); VIII's first sentence asks for one. This is the one entry in Complexity Tracking. |
| IX | No ads in a trip | No | No ad calls. |
| X | RTL and Arabic first | No | No screens. |
| XI | Accessible minimums | No | No screens. |
| XII | No runtime LLM | No | — |
| XIII | Small, testable features | Yes | Tests first for the rules, the gate, maintenance and grants; real services; one feature, one folder, one PR. |

**Architecture boundaries.**

- **Business logic** in `apps/liveops/services/`; admin forms and the command call services. Views
  stay thin.
- **Errors** use B01's envelope; `client_outdated` and `maintenance` are added to backend §6.2 first.
- **Dependencies between apps:** `economy`, `accounts` and `content` import `liveops` (settings,
  the task wrapper); `liveops` imports `accounts` (users, players) and `progress` (story state for one
  rule), never `economy`.
- **External calls:** one, the daily Remote Config read in Celery, with timeouts and retries (backend
  §17.1). Nothing on the request path calls out.
- **Stateless:** the per-process snapshot is a cache of the database with a 30 s age limit, rebuilt
  on demand; no state is lost when a process dies.

**Security & privacy.**

- **Admin:** a new `live_ops` group, TOTP and WireGuard (B01). Every change is attributed and
  append-only. Admin forms can't bypass validation (they call services).
- **The command:** `--actor` must hold `switch_maintenance`; it runs only inside a host's
  container, reached over WireGuard.
- **Secret:** the Remote Config key is optional, read-only scoped, never logged (test).
- **API:** `GET /v1/offers` returns only catalog data and the caller's own eligible offers; no
  endpoint takes a player id.
- **A security review** is required before merge (this gates every player write).

**Post-design re-check (after Phase 1).** Passes, with the one Complexity Tracking entry below
approved by the owner on 2026-11-01. The design changes these documented details, each updated in the same
PR:

- backend §6.2 (two codes), §6.4 (bootstrap's `client` source), §6.5 (426 is live; who is exempt),
  §8.1 (the pack amounts; grants as typed columns), §11.2 (two jobs), §12 (`liveops` models),
  §15 (maintenance: the command and the job skip), §22.10 resolved;
- mobile §14.3 (the server-only numbers are live settings; the drift check);
- B03's `contracts/environment.md` (retired variables point to this feature);
- `backend/CLAUDE.md` (what's built, the command, the environment), `docs/runbooks/` (a live-ops
  runbook; the maintenance window in deploy-and-rollback; the secret in monitoring-setup),
  `docs/owner-actions.md` (the service account, the Sentry alert rule, the Play Console product ids);
- the Complexity Tracking entries of `specs/004-m01-trip-engine/plan.md` and
  `specs/010-b03-ledger-sync/plan.md` are marked closed by B10.

## Project Structure

### Documentation (this feature)

```text
specs/016-b10-catalog-offers/
├── spec.md
├── plan.md              # this file
├── research.md          # R1–R16
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── api.md           # 426, 503 maintenance, bootstrap, GET /v1/offers, grants_for
│   ├── settings.md      # the registry, the rules
│   ├── offers.md        # the offer rules
│   ├── admin.md         # group, pages, the maintenance command
│   └── environment.md   # new, retired and kept variables
├── checklists/requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
backend/
├── apps/liveops/                       # new
│   ├── models.py                       # LiveSetting, LiveopsChange, StoreProduct, Offer, RemoteConfigCheck
│   ├── registry.py                     # every setting's Spec and the cross-setting rules
│   ├── settings.py                     # current() → Snapshot, the 30 s refresh
│   ├── permissions.py                  # CurrentClient (426), NotInMaintenance (503)
│   ├── services/
│   │   ├── settings_admin.py           # change, reset, import
│   │   ├── maintenance.py              # switch, state
│   │   ├── catalog.py                  # grants_for, product saves
│   │   ├── offers.py                   # rule validation and evaluation, listing
│   │   ├── facts.py                    # PlayerFacts (B06 fills the purchase fields)
│   │   ├── versions.py                 # active players per version, blocked share
│   │   └── remote_config.py            # token, template read, comparison
│   ├── api/{views,serializers}.py      # GET /v1/offers
│   ├── tasks.py                        # check_remote_config, expire_offers, skip_in_maintenance
│   ├── admin.py, templates/            # pages of contracts/admin.md
│   ├── checks.py                       # liveops.W001 (retired env variables still set)
│   ├── management/commands/maintenance.py
│   ├── migrations/                     # 0001 settings + history, 0002 seed + env import, 0003 group, then products, offers, the check and their schedules (tasks.md)
│   └── tests/
├── apps/common/errors.py               # client_outdated, maintenance
├── apps/economy/services/settings.py   # adapter over liveops (R4)
├── apps/economy/services/bootstrap.py  # live client block, writes the player's version
├── apps/economy/models.py              # index on Wallet.last_active_at (+ migration)
├── apps/economy/tests/test_tunables_parity.py   # removed (replaced in liveops)
├── apps/{accounts,economy,content}/tasks.py     # skip_in_maintenance on the scheduled writers
├── config/env.py, config/settings/base.py       # retired variables out, three new in, the two permissions, the app
├── conftest.py                         # live_settings fixture
├── .env.example, docker/env/*.env
contracts/openapi.yaml                  # regenerated
docs/architecture-backend.md, docs/architecture-mobile.md, docs/runbooks/, docs/owner-actions.md
```

**Structure Decision**: one new app in backend §5's layout, plus small edits to the apps whose
settings and jobs it takes over. No mobile change: M06 already reads the 426, the maintenance
answer and `details.until`; M12 will read `GET /v1/offers`.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
| --- | --- | --- |
| Constitution VIII asks every balancing number to have a Firebase Remote Config key. The 12 server-only numbers (contracts/settings.md "Server-only": overdraft, traffic-jam ads, name lengths, the sync thresholds, the comeback gaps) get a live setting and no Remote Config key. | The phone never applies them (constitution IV: the server alone decides), so a Remote Config key would be a value nothing reads, and the drift check would compare it to nothing. The constitution's rationale (retune without a release, record what ran) is met by the live setting alone. | Adding unused Remote Config keys: dead config that invites someone to "tune" a number in the console that has no effect. Recommended follow-up: amend VIII through `/speckit-constitution` (a PATCH clarification: "numbers the phone applies have a Remote Config key; server-only numbers live only in `liveops.LiveSetting`"), after which this entry closes. **Approved by the owner on 2026-11-01** (analysis finding C1). |

B07 adds `ads_morning_piggy_jenehat` and `ads_morning_piggy_bonat` under this entry
(specs/017-b07-ads-ssv/plan.md).
