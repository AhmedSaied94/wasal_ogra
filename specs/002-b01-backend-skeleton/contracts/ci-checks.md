# Contract: Backend CI/CD Checks

Spec FR-025 – FR-034, SC-003, SC-004. Versions come from research.md R2, R8 and R12: `astral-sh/setup-uv@v10.3.0` (no major tags exist), `actions/checkout@v7`, `docker/setup-buildx-action@v4`, `docker/build-push-action@v7`, `docker/login-action@v4`, and gitleaks `v8.30.1`. There are three
workflows: `backend.yml` (checks, image, staging deploy), `backend-release.yml` (production) and
`secrets.yml` (gitleaks).

## `backend.yml`

### Triggers

| Event | Runs |
| --- | --- |
| `pull_request` (any) | `changes` always. The backend jobs run only if the PR touches `backend/**`, `contracts/**` or `.github/workflows/backend*.yml`. |
| `push` to `master` | Same path rule, plus the image push and `deploy-staging` |
| `workflow_dispatch` | Everything (forced `backend=true`). Optional input `rehearse`: `none` (default), `migrate-fail` or `verify-fail`. A non-`none` value runs only `deploy-staging` (on `master`), which sends `sha-<commit> rehearse-<value>`. The commit is the newest one on `master` that has an image (operations.md, quickstart items 11–12). |

- There is no workflow-level `paths:` filter, the same rule as `mobile.yml`: a required check that
  never starts stays pending forever. `changes` computes the path rule with `git diff --name-only`
  against the merge base.
- `concurrency: backend-${{ github.ref }}` with `cancel-in-progress: ${{ github.event_name ==
  'pull_request' }}`. PR runs are superseded, but a `master` run is never cancelled mid-deploy.

### Jobs

| Job | Needs | Runner | Steps | Fails when |
| --- | --- | --- | --- | --- |
| `changes` | — | ubuntu-24.04 | checkout (`fetch-depth: 0`) → diff → output `backend` | never |
| `lint` | changes | ubuntu-24.04 | setup-uv → `uv sync --locked` → `ruff check` → `ruff format --check` | any lint or format issue, or a stale `uv.lock` |
| `types` | changes | ubuntu-24.04 | setup-uv → `uv sync --locked` → `mypy .` | any mypy error (`strict = true`, django-stubs plugin) |
| `test` | changes | ubuntu-24.04 | services `postgres:17.11-trixie`, `valkey/valkey:8.1.10-trixie` → install `postgresql-client-17` from the PGDG apt repository (the runner's own client is older than the server, and `pg_dump` refuses that) → setup-uv → `uv sync --locked` → `pytest --cov --cov-fail-under=80` | any failing test (unit, integration, settings guards, UUIDv7 system check, schemathesis contract suite, backup/drill/deploy-logic tests), or coverage < 80% |
| `contract` | changes | ubuntu-24.04 | setup-uv → `manage.py makemigrations --check --dry-run` → `manage.py spectacular --file /tmp/openapi.yaml --validate --fail-on-warn` → `diff -u contracts/openapi.yaml /tmp/openapi.yaml` | missing migration, schema warning, or a contract diff |
| `image` | changes | matrix: ubuntu-24.04 (amd64), ubuntu-24.04-arm (arm64) | buildx → build `backend/docker/Dockerfile` with `RELEASE=${{ github.sha }}` natively per arch → on `master` push by digest to GHCR → upload digest | build error |
| `image-manifest` | lint, types, test, contract, image, smoke | ubuntu-24.04 | `master` only, and only when every check passed: `docker buildx imagetools create -t ghcr.io/ahmedsaied94/wassal-backend:sha-<sha>` from both digests. The release workflow relies on that tag meaning "every check passed". | manifest error |
| `smoke` | changes | ubuntu-24.04 | build amd64 image locally → `docker compose -f compose.yml -f compose.dev.yml up -d --wait` → `curl /healthz`, `/readyz` → edge smoke (below) → `docker compose down -v` | any service unhealthy within 120 s, or any edge assertion failing |
| `backend` | all of the above | ubuntu-24.04 | `if: always()`. Fails if any needed job failed or was cancelled. Skipped counts as passing. | a needed job failed |
| `deploy-staging` | backend, image-manifest | ubuntu-24.04 | Runs on a `master` push whose `image-manifest` succeeded, or on a rehearsal dispatch. Environment `staging`, `concurrency: deploy-staging` (`cancel-in-progress: false`). Steps: install `wireguard-tools` → `wg-quick up` from `WG_CONFIG` (the staging host's tunnel) → `ssh deploy@10.67.0.1 staging sha-<sha>` (the staging host's WireGuard address), with the key and `known_hosts` from the environment secrets, `StrictHostKeyChecking=yes` and `ServerAliveInterval=30` → `wg-quick down` (`always()`) | the remote `deploy` exits non-zero (GitHub then emails the failure, FR-038) |

- Every job has `timeout-minutes: 15` (SC-003).
- `lint`, `types`, `test`, `contract`, `image` and `smoke` run in parallel.
- **The required status checks for branch protection are `backend` and `gitleaks`** (from
  `secrets.yml`), plus the mobile jobs. Without `gitleaks` as a required check, a committed secret
  would fail CI without blocking the merge (FR-027).

### Edge smoke assertions (inside `smoke`)

The real `edge/Caddyfile` (the one both hosts run) is started with `network_mode: host` and these
settings:

- `WASSAL_ENV=prod`, so the sites proxy to `127.0.0.1:8100` and `127.0.0.1:8101`, where the job's
  stack listens;
- `PUBLIC_BIND_IP=127.0.0.1`, `ADMIN_BIND_IP=127.0.0.2`;
- `PUBLIC_TLS=internal`;
- `API_HOST=api.127-0-0-1.sslip.io` and `ADMIN_HOST=admin.127-0-0-2.sslip.io`, pinned with
  `curl --resolve`.

| Assertion | Requirement |
| --- | --- |
| `https://api…/healthz` → 200 with `Strict-Transport-Security` (`max-age` ≥ 31536000, `includeSubDomains`), `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: strict-origin-when-cross-origin` | FR-019 |
| `http://api…/healthz` → 308 to https | FR-019 |
| A 600 KB `POST` to `https://api…/v1/` → 413 with the `payload_too_large` envelope | FR-020, contracts/api.md |
| `https://api…/admin/` → 404 envelope; `https://admin…/v1/` → 404 | FR-021 |
| On `127.0.0.1:443` with `Host: admin…`, the response has no `Content-Security-Policy` header and no admin content (Caddy answers an unknown hostname with an empty `200`, research R6). On `127.0.0.2:443`, the admin answers with the CSP header. | FR-021, FR-023 |
| `caddy validate` passes for `Caddyfile` with `WASSAL_ENV=prod` and with `WASSAL_ENV=staging`, and for `Caddyfile.dev`. With `WASSAL_ENV` empty, `Caddyfile` fails to validate, so an edge that doesn't know its environment never starts. | FR-001a |

## `backend-release.yml` (production)

| Step | Rule |
| --- | --- |
| Trigger | `push` of a tag matching `v[0-9]+.[0-9]+.[0-9]+` |
| Verify | `git merge-base --is-ancestor $SHA origin/master`, **and** `docker buildx imagetools inspect …:sha-$SHA` succeeds (the image exists only if that commit's `master` run passed every check, FR-030), **and** the commit's `gitleaks` check run (secrets.yml) concluded `success`. Otherwise fail without deploying. |
| Tag | `imagetools create -t …:<tag> …:sha-$SHA` |
| Deploy | environment `production` (deployment rule: `v*` tags only), `concurrency: deploy-prod` (`cancel-in-progress: false`) → WireGuard (the prod host's tunnel) → `ssh deploy@10.66.0.1 prod <tag>` (the prod host's WireGuard address) |

The `sha-<commit>` image of every commit production has run must stay in the registry while
backups taken by it are kept (56 days): the restore drill on the staging host pulls it by that tag
([operations.md](./operations.md#restore-drill-fr-040-fr-040a)). No registry cleanup may delete
it sooner.

## `secrets.yml`

| Event | Runs | Fails when |
| --- | --- | --- |
| `pull_request`, `push` to `master` | gitleaks (R12) on the working tree **and** on the commits in the push or PR range, with the default rules plus `.gitleaks.toml` (allow-listing the `change-me-` placeholders in `.env.example`) | any finding (FR-027) |

GitHub secret scanning with push protection is also switched on in the repository settings (R12), as
defence in depth. It isn't a CI job.

## Commands (identical locally; listed in `CLAUDE.md`, FR-044)

| Purpose | Command (in `backend/`) |
| --- | --- |
| Install deps | `uv sync` |
| Start the local stack | `docker compose -f docker/compose.yml -f docker/compose.dev.yml up -d --wait` |
| Stop it (keep data) / wipe it | `docker compose … down` / `docker compose … down -v` |
| Migrate | `uv run manage.py migrate` (the dev stack's `migrate` service also runs it on every `up`) |
| Lint and format check | `uv run ruff check . && uv run ruff format --check .` |
| Type check | `uv run mypy .` |
| Tests + coverage gate | `uv run pytest --cov --cov-fail-under=80` |
| Missing-migration check | `uv run manage.py makemigrations --check --dry-run` |
| Regenerate the API contract | `uv run manage.py spectacular --file ../contracts/openapi.yaml --validate --fail-on-warn` |
| Create a staff user / issue TOTP | `uv run manage.py create_staff <name>` / `uv run manage.py staff_totp <name>` |
| Deploy, roll back, restore | See `docs/runbooks/deploy-and-rollback.md` and `restore.md` |

## Checks implemented as tests (inside `pytest`)

| Check | Test | Requirement |
| --- | --- | --- |
| Project models use `UUIDv7Model` (system check `common.E001` reports none) | `apps/common/tests/test_checks.py` | FR-016 |
| Each settings module refuses missing, placeholder or debug configuration outside dev | `tests/test_settings_guards.py` | FR-003 |
| Every error path returns the envelope with the documented code | `apps/common/tests/test_errors.py` | FR-013 |
| Health and readiness, including a dead database and a dead cache, within 5 s | `apps/common/tests/test_health.py` | FR-010, FR-011 |
| Throttle shared across processes (two clients, one cache) → 429 envelope | `apps/common/tests/test_throttles.py` | FR-015 |
| Access log line shape and no IPs or headers | `apps/common/tests/test_logging.py` | FR-036 |
| Sentry `before_send` strips IP, headers, cookies, bodies | `apps/common/tests/test_sentry.py` | FR-024 |
| Admin requires OTP. Lockout after 5 failures per username or per address. | `apps/accounts/tests/test_admin_auth.py` | FR-022 |
| Backup metadata counts equal restored counts (same snapshot); daily and weekly go to their own buckets | `apps/common/tests/test_backups.py` | FR-039 |
| `b2_setup.py` creates locked buckets and refuses a key whose capabilities differ from the expected list | `tests/test_b2_setup.py` | FR-039a |
| Drill: fetch and check steps, all four checks, failure paths, invariant registry | `apps/common/tests/test_restore_drill.py` | FR-040 |
| `deploy` decision logic (validation, including an `--only` other than the host's `WASSAL_ENV`; lock, migrate-fail, verify-fail → restore) | `backend/docker/host/tests/test_deploy_script.py` | FR-001a, FR-031 – FR-033 |
| `provision.sh` host identity: the first run records `--env` and its `WG_ADDRESS` in `host.env`; a later, different `--env`, a malformed `host.env`, or an `edge.env` whose `ADMIN_BIND_IP` isn't `WG_ADDRESS` is refused before anything changes | `backend/docker/host/tests/test_provision_identity.py` | FR-001a |
| Firewall render: Oracle's rules kept, project rules before the final `REJECT`, `wg0` ranges from the host's own /24 (rendered with `--wg-address 10.66.0.1` and `10.67.0.1`) | `backend/docker/host/tests/test_firewall_template.py` | FR-023 |
| `wg-peer`: addresses from the role's range inside the host's /24, only the host's own deploy role accepted, configs with the host's own endpoint and address | `backend/docker/host/tests/test_wg_peer.py` | FR-023a |
| Edge upstream ports: the Caddyfile's `api-<env>` and `admin-<env>` snippets use the `API_PORT` and `ADMIN_PORT` of `docker/env/<env>.env`, for both environments | `backend/docker/host/tests/test_edge_ports.py` | FR-005 |
| Host monitor: each host checks its own hostnames' certificates (the admin's only for current validity) and its own environment's queues; backup storage on prod only; exit 2 without `WASSAL_ENV` | `backend/docker/host/tests/test_host_monitor.py` | FR-038 |
| `backup` refuses an environment other than the host's | `backend/docker/host/tests/test_backup_script.py` | FR-001a, FR-039 |
| `restore-drill` runs only on the staging host, fetches with staging's serving image, checks with `sha-<the backup's release>` and that release's postgres image, and leaves no container, volume, network or directory behind | `backend/docker/host/tests/test_restore_drill_script.py` | FR-040, FR-040a |
| Contract: every operation in the committed `openapi.yaml` | `tests/test_contract.py` (schemathesis) | FR-018, constitution XIII |
