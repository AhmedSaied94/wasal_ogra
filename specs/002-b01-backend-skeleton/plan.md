# Implementation Plan: Backend Skeleton (B01)

**Branch**: `002-b01-backend-skeleton` | **Date**: 2026-10-18 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/002-b01-backend-skeleton/spec.md`

## Summary

B01 creates the Django backend in `backend/` that every later backend feature builds on, and puts it
live at USD 0 on one Oracle Cloud Always Free ARM VM (2 OCPU, 12 GB, the whole allowance since 2026).
It ships no game endpoints, only:

- **App skeleton:**
  - Django 5.2 LTS + DRF settings per environment, with fail-fast validation of every setting.
  - A project-owned staff `User` model with UUIDv7 keys and a check that enforces them.
  - The error envelope with its codes, a per-address rate limit, request ids with JSON access logs,
    and `/healthz` and `/readyz`.
  - The committed `contracts/openapi.yaml`.
- **Background:** Celery worker (four queues) and beat with schedules in the database, plus a
  heartbeat job that proves the path end to end.
- **Admin:** a separate hostname reachable only over a WireGuard network, staff-only, TOTP 2FA and a
  5-failure / 15-minute lockout.
- **Stack:** one Docker Compose file for `dev`, `staging` and `prod`. A single edge Caddy on the
  host network serves the public API hostnames with Let's Encrypt and binds the admin hostnames to
  the WireGuard address only, with a private CA. Hostnames come from sslip.io until a real domain
  exists.
- **CI/CD (GitHub Actions):** lint, types, tests against real PostgreSQL and Valkey, ≥ 80% coverage,
  migration and OpenAPI drift checks, schemathesis, gitleaks, native arm64 + amd64 image builds,
  and a compose and edge smoke test.
  - Merges deploy to staging, and `v*` tags deploy to production.
  - Deploys go over WireGuard to a forced-command `deploy` script that migrates first, restarts,
    verifies and rolls back by itself.
- **Operations:**
  - Nightly snapshot-consistent `pg_dump` to Backblaze B2, kept safe from the host by Object Lock
    (governance mode) and a key that can only write.
  - A monthly automated restore drill in a throwaway container.
  - Healthchecks.io dead-man's switches, an external uptime check, Sentry, and a host monitor for
    disk, certificates and queue backlog.
  - Written runbooks for provisioning, deploy and rollback, restore, peers, break-glass and staff
    accounts.

Technical approach and versions: [research.md](./research.md).

## Technical Context

**Language/Version**: Python 3.13.16, managed with `uv` 0.13.1, pinned in `backend/.python-version`
and `pyproject.toml` (`requires-python = "==3.13.*"`) with a committed `uv.lock`. uv 0.13 defaults to
Python 3.15 downloads, so the pin is load-bearing.

**Primary Dependencies** (research R2 has the full pin list):

- Django 5.2.18 (LTS), djangorestframework 3.18.3, drf-spectacular 0.30.0.
- celery 5.6.3 + django-celery-beat 2.9.0. The `redis` client is 6.4.0, because kombu requires
  `< 6.5`.
- psycopg 3.3.6 (binary wheels), django-environ 0.14.0, uuid-utils 1.0.0 (`compat.uuid7`).
- django-otp 1.7.5 (TOTP admin) and django-axes 8.3.1 (lockout).
- sentry-sdk 2.72.0, python-json-logger 4.2.0, gunicorn 26.2.0, whitenoise 6.12.0 (admin static
  files), boto3 1.43.x (Backblaze B2's S3-compatible API, ops role only).
- Dev: ruff 0.17.1, mypy 1.19.1 + django-stubs 5.2.9 + djangorestframework-stubs 3.16.9 +
  celery-types 0.26.0, pytest 9.1.1 + pytest-django 4.14.0 + pytest-cov 7.1.0, factory-boy 3.3.3,
  hypothesis 6.170.x, schemathesis 4.31.x.

**Storage**: PostgreSQL 17 (`postgres:17.11-trixie`), one database per environment. Valkey
(`valkey/valkey:8.1.10-trixie`) for the cache, throttles and the Celery broker, with AOF on so queued
tasks survive restarts. Backblaze B2 for production backups only (R9).

**Testing**:

- pytest + pytest-django against real PostgreSQL and Valkey (constitution XIII): CI service
  containers, locally the dev compose services. Valkey is also the Celery broker in tests, and one
  test sends the heartbeat through it to an in-process worker.
- schemathesis against the committed `contracts/openapi.yaml` through `live_server`.
- Settings-guard tests in subprocesses, the UUIDv7 system check, backup and drill service tests
  against a real database (B2 replaced by a local S3-compatible fake only at the network boundary,
  R9), and the deploy script's decision logic tested with a stubbed `docker`.
- Edge behaviour is checked by a CI smoke job with real Caddy.
- Coverage ≥ 80% lines via pytest-cov, gated in CI.

**Target Platform**: Linux containers on one Oracle Cloud Always Free `VM.Standard.A1.Flex` VM with
**2 OCPU and 12 GB** (ARM64). That is the whole Always Free A1 allowance since Oracle halved it in
2026 (R1). Ubuntu 24.04 LTS aarch64, a 100 GB boot volume, and Docker Engine + the Compose plugin.
The region is `me-jeddah-1`, the home region of the owner's existing tenancy, with a reserved public
IP (R1). Images are also built for amd64 (developer machines and CI).

**Project Type**: web service (REST API + Django admin + Celery workers) in the `wassal` monorepo,
plus host operations scripts

**Performance Goals**:

- `/healthz` answers within 1 s from outside (SC-002). `/readyz` stays within 5 s even when every
  dependency hangs.
- API downtime ≤ 30 s per deploy (the edge holds requests while the upstream restarts, R6).
- A tag is serving within 15 min.
- The endpoint latency budgets in backend §2 belong to later features. B01 provides the Sentry
  traces that measure them.

**Constraints**:

- USD 0: Always Free only, never upgraded, and every other service on a free plan (FR-042b). B2
  stays inside its free 10 GB, with USD 0 caps set and Event Notifications (the one uncappable
  charge) left off (R9).
- Memory: staging and production together fit the 12 GB with the per-service limits in R1, which
  sum to about 64% of the host.
- Only 80/tcp, 443/tcp and 51820/udp are reachable from the internet, and WireGuard is silent to
  unknown peers (FR-023).
- Secrets only in `/etc/wassal/*.env` (FR-002).
- No IPs in application logs, and edge logs are kept 14 days.
- Staging and production on one VM, never sharing a database, cache, files or secrets.

**Scale/Scope**:

- 3 environments, 7 services each (the edge is shared), 4 worker queues.
- 1 project model, 2 health endpoints, 10 error codes (7 new).
- 5 Healthchecks.io checks, 1 uptime check.
- 3 CI workflows, 4 host timers or services, 7 runbooks.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| # | Principle | Applies | How B01 satisfies it |
| --- | --- | --- | --- |
| I | Engine purity | No | No trip rules or engine code |
| II | Integer money | No | No money. The drill's future `wallet == sum(ledger)` invariant compares integers, and B03 provides it. |
| III | Parity | No | No engine rules or fixtures |
| IV | Server authority | Indirectly | No value-bearing endpoints yet. B01 builds the authority's foundations: the private admin, the ledger-invariant hook in the drill, and backups that can't be deleted by a compromised host (FR-039a). |
| V | Offline-first | Indirectly | Nothing in the app depends on B01 at runtime. Outages and deploys affect only online features, and deploy downtime ≤ 30 s. |
| VI | Idempotency | No | No state-changing API endpoints. Deploys are idempotent per tag: re-running a deploy of the serving tag is a no-op apart from verify. |
| VII | Content, not code | Yes | No player-visible text. Error `message`s are generic developer English, and clients localize by `code`. Hostnames and thresholds are configuration (FR-042a). |
| VIII | Tunable numbers | No | No balancing numbers. Operational thresholds are environment settings, not game tunables. |
| IX | No ads in a trip | No | — |
| X | RTL and Arabic first | No | No player screens. The admin is a staff tool, and B04 handles Arabic content in it. |
| XI | Accessible minimums | No | No player screens |
| XII | No runtime LLM | Yes | None |
| XIII | Small, testable features | Yes | Tests first for the settings guards, the error envelope and its handlers, throttling, health services, the UUIDv7 check, backup metadata and snapshot counts, drill checks and the deploy decision logic. Integration tests run on real PostgreSQL and Valkey, schemathesis on the committed contract, and coverage ≥ 80% is gated. |

**Locked stack.** B01 uses it exactly:

- Python 3.13 with `uv`.
- Django 5.2 LTS + DRF, Django admin as the staff tool.
- PostgreSQL 17, Valkey, Celery 5 + `django-celery-beat`, `drf-spectacular`.
- One ARM64 Oracle VM running Docker Compose behind Caddy.

`simplejwt` arrives with B02, which first needs it. Additions that the stack doesn't list:

- `django-otp` and `sentry-sdk` are already named in backend §2.
- `django-axes` is new (R5).
- `uuid-utils` is in §2.
- `python-json-logger` is new (R7).
- `whitenoise` is new (R3).

**Architecture boundaries.**

- Logic lives in `apps/common/services/` (health, backups, drill, invariants, monitoring pings), and
  the API views are thin.
- The error envelope uses §6.2 codes, with the new ones added to §6.2 in this PR.
- UUIDv7 keys are enforced by a system check.
- Migrations follow expand/contract, which the deploy order relies on: migrate first, restart second.
- Services are stateless.
- The heartbeat's outbound call runs in Celery with a timeout and retries.

**Security & privacy.**

- HTTPS everywhere (with a private CA for the admin), HSTS.
- Secrets only in host env files, never in images or logs, and scrubbed from Sentry.
- Rate limiting on every endpoint.
- The admin is on its own host, staff-only, 2FA, behind WireGuard.
- Count queries compose identifiers with `psycopg.sql.Identifier`. There is no string-formatted SQL.
- No player data in B01. Client IPs only in edge logs, kept 14 days (backend §14.2).
- Gitleaks and GitHub push protection on the repository.
- The CI deploy credential can only deploy one environment.

**CI gates (constitution).**

- Backend: `ruff`, `mypy` (django-stubs), and `pytest` on real PostgreSQL and Valkey, including the
  schemathesis suite. The hypothesis suites start with B03's ledger.
- The OpenAPI diff.
- Parity, content and the direct-`Wallet`-write scan are not applicable until B05, B04 and B03 create
  what they check.

**Gate result (pre-research): PASS.** No violations. Two owner-approved departures from the
*architecture docs* (not the constitution) are recorded in Complexity Tracking for visibility.

**Gate result (post-design): PASS.** The re-check after Phase 1 found:

- the contracts keep every secret in host env files;
- the only public listeners are the edge and WireGuard;
- the deploy migrates before restarting, which needs expand/contract, as the constitution already
  requires;
- the design adds no endpoint that changes state.

No new violations.

## Project Structure

### Documentation (this feature)

```text
specs/002-b01-backend-skeleton/
├── plan.md              # This file
├── research.md          # Phase 0: decisions, versions, resolved open question backend §22.1
├── data-model.md        # Phase 1: staff user, framework tables, environments, releases, backups,
│                        #   drill results, monitoring checks, private-network peers
├── quickstart.md        # Phase 1: how to run, test, provision, deploy and verify
├── contracts/
│   ├── api.md           # conventions, error envelope + codes, health endpoints, access log
│   ├── environment.md   # every variable and file, startup rules, CI secrets
│   ├── ci-checks.md     # workflows, jobs, commands, pass criteria
│   └── operations.md    # edge, firewall, deploy interface, backup, drill, host monitor, timers
├── checklists/requirements.md
└── tasks.md             # Phase 2 (/speckit-tasks), not created here
```

### Source Code (repository root)

```text
contracts/openapi.yaml                    # generated by drf-spectacular, committed (FR-018)
.github/workflows/
├── backend.yml                           # changes · lint · types · test · contract · image (arm64+amd64)
│                                         #   · smoke · backend (aggregate) · deploy-staging
├── backend-release.yml                   # on v* tag: verify on master + image exists → tag → deploy-prod
└── secrets.yml                           # gitleaks on every PR and push (whole repository)
backend/
├── pyproject.toml  uv.lock  .python-version  manage.py  .env.example  .dockerignore
├── config/
│   ├── env.py                            # typed env reader + startup guards (FR-003)
│   ├── settings/{base,dev,test,staging,prod}.py
│   ├── urls.py                           # API role: /healthz, /readyz, /v1/ (router), handler404/500
│   ├── urls_admin.py                     # admin role: OTPAdminSite, /healthz, /readyz
│   ├── celery.py  wsgi.py  gunicorn.conf.py
├── apps/
│   ├── common/
│   │   ├── ids.py                        # uuid7()
│   │   ├── models.py                     # UUIDv7Model (abstract)
│   │   ├── checks.py                     # system check common.E001: project models must use UUIDv7Model
│   │   ├── errors.py                     # ErrorCode, envelope(), DRF exception handler, handler404/500
│   │   ├── throttles.py                  # AddressRateThrottle
│   │   ├── middleware.py                 # RequestId, AccessLog, DependencyUnavailable
│   │   ├── logging.py  sentry.py         # JSON log config; Sentry init + scrubber (FR-024)
│   │   ├── services/{health,monitoring,backups,restore_drill,invariants}.py
│   │   ├── api/views.py                  # HealthzView, ReadyzView (thin)
│   │   ├── tasks.py                      # heartbeat (bind=True, timeout, retries)
│   │   ├── migrations/0001_heartbeat_schedule.py
│   │   ├── management/commands/{backup_db,restore_drill,sentry_test}.py
│   │   └── tests/
│   └── accounts/
│       ├── models.py                     # User (staff, AUTH_USER_MODEL)
│       ├── admin.py
│       ├── management/commands/{create_staff,staff_totp}.py
│       ├── migrations/0001_initial.py
│       └── tests/
├── tests/                                # cross-cutting: settings guards, contract (schemathesis),
│                                         #   openapi drift helper, repo guards, b2_setup
├── tools/b2_setup.py                     # operator machine only: B2 buckets, locks, lifecycle, keys (R9)
└── docker/
    ├── Dockerfile                        # uv multi-stage; runtime python:3.13-slim-trixie + postgresql-client-17
    ├── compose.yml                       # per-environment app stack (+ ops profile: migrate, backup)
    ├── env/{staging,prod}.env            # non-secret sizing: ports, memory limits, workers (shipped in the image)
    ├── compose.dev.yml                   # dev overrides: build, ports, bind mount, optional edge profile
    ├── postgres/initdb/01-app-role.sh    # app role + pg_stat_statements
    ├── edge/{compose.yml,Caddyfile,Caddyfile.dev}
    └── host/
        ├── provision.sh                  # idempotent Ubuntu 24.04 aarch64 setup (R13)
        ├── iptables/rules.v{4,6}.tmpl    # Oracle's InstanceServices kept + project INPUT rules
        ├── sshd_config.d/wassal.conf  sysctl.d/90-wassal.conf  wireguard/wg0.conf.example
        ├── bin/{deploy,backup,restore-drill,host-monitor,wg-peer}
        ├── systemd/docker.service.d/after-wg.conf
        ├── systemd/{wassal-backup@,wassal-restore-drill@,wassal-host-monitor}.{service,timer}
        └── tests/                        # pytest drives the bash scripts with stub docker/curl on PATH
                                          #   (fixtures/oracle-rules.v4 for the firewall renderer)
docs/runbooks/
├── provision-host.md  deploy-and-rollback.md  restore.md  private-network.md
├── break-glass.md  staff-accounts.md  monitoring-setup.md
```

**Generated and local files**: `contracts/openapi.yaml` is generated and *committed*. `backend/.env`,
`.venv/` and caches are gitignored (already covered by the root `.gitignore`).

**Spikes come first.** They check every **[verify in spike]** item before the parts that depend on it
are built (tasks T004, T005 and T047). The app skeleton, US1 and US2 don't wait for them. If any check
fails, record the workaround in research.md before continuing.

1. On a GitHub-hosted `ubuntu-24.04` runner:
   - one host-network Caddy with a public site bound to `127.0.0.1` and an admin site bound to
     `127.0.0.2`, with `tls internal` (R6);
   - the 600 KB-body → 413 check against an upstream that never reads the body (R6);
   - `wg-quick up` with a config that has no `DNS=` line (R8).
2. Against a scratch B2 bucket made with the native API by a throwaway script, whose recorded call
   sequence then drives `b2_setup.py`: one boto3 upload and download under the USD 0
   caps, the backup key refused a version delete, a lock change and a listing, a second upload to the
   same name keeping the first version, and whether `listAllBucketNames` is needed (R9).
3. Locally, once the OTP admin exists: the Django 5.2 admin login, OTP and change pages under the admin CSP with no console
   violations (R5).

**Structure decision.** This is the `backend/` layout from backend §5, with two extensions. They are
recorded in Complexity Tracking.

- `backend/docker/` gains `edge/` and `host/`. There is one `compose.yml` plus env files instead of a
  separate `compose.staging.yml`.
- Runbooks go in `docs/runbooks/`.

Only `apps/common` and `apps/accounts` are created. The other apps in §5 arrive with their features.

## Complexity Tracking

> Fill ONLY if Constitution Check has violations that must be justified

No constitution violations. These departures from the architecture docs are recorded for visibility.
The docs are updated in this PR.

| Item | Why | Simpler alternative rejected because |
| --- | --- | --- |
| Backups in Backblaze B2, not OCI Object Storage (owner, 2026-10-18) | An Oracle account problem must not take the backups with it | Same-account storage breaks the RPO/RTO the moment the account is suspended or closed |
| Admin and SSH only over WireGuard (owner, 2026-10-18), stricter than §13 | Removes the two most powerful entry points from the internet | Public admin with 2FA only leaves a credential-stuffing and 0-day surface for no benefit |
| Ops jobs (backup, drill, host monitor) as host systemd timers, not Celery beat | They must run when the app is broken, and the drill needs Docker, which the worker must never get | Beat-driven backups stop exactly when the app is unhealthy, and Docker-socket access from the worker is a host takeover path |
| One edge Caddy with `network_mode: host` | Per-site `bind` to the WireGuard address is only reliable when Caddy sees host interfaces. The host firewall then filters it like any process. | Bridge networking hides which host interface a connection came in on, and published Docker ports bypass the host INPUT chain |
| `django-axes`, `python-json-logger` and `whitenoise` added to the dependency list | FR-022's lockout, FR-036's JSON lines, and the admin's static files with `DEBUG` off | A hand-written lockout or formatter is more code to secure and test than small, maintained libraries. Serving static files from the edge would need a per-environment volume shared across Compose projects and refreshed on every deploy. |
| `backend/docker/{edge,host}/` and `docs/runbooks/` | The shared edge and the host scripts are new kinds of files that §5 didn't foresee | Spreading them across `backend/` root or the compose files would mix host provisioning with app packaging |
