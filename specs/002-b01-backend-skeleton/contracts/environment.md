# Contract: Configuration and Secrets

Spec FR-001 – FR-004, FR-024, FR-042a. All configuration comes from the environment (FR-002).

- In `dev`, it comes from `backend/.env`, copied from the committed `backend/.env.example`.
- In `staging` and `prod`, it comes from root-owned files under `/etc/wassal/` (mode `0400`), which
  Compose reads as `env_file`. They are never committed, and `.gitignore` already blocks `.env*`
  except `.env.example`.

## Startup rules (FR-003)

`config/env.py` loads every setting through one typed reader before Django finishes loading the
settings module.

1. **Missing or invalid required variable**: raise `ImproperlyConfigured("<NAME> is required"…)`
   naming the variable, never its value. The process exits non-zero, and the container is restarted
   with backoff.
2. **Outside `dev`**, startup also fails when:
   - any secret's value contains `change-me` (every placeholder in `.env.example` does);
   - `SECRET_KEY` is shorter than 50 characters;
   - `DJANGO_DEBUG` is true;
   - `WASSAL_ENV` doesn't match the settings module.
3. Validation runs in every role (`api`, `admin`, `worker`, `beat`, `ops`), so a misconfigured worker
   can't run silently either.

Tests (`tests/test_settings_guards.py`) load each settings module in a subprocess with a crafted
environment and assert the exit code and the message.

## Application variables

| Variable | Required in | Secret | Example or default | Rule |
| --- | --- | --- | --- | --- |
| `DJANGO_SETTINGS_MODULE` | all | no | `config.settings.prod` | One of `dev`, `test`, `staging`, `prod` |
| `WASSAL_ENV` | all | no | `prod` | `dev` \| `staging` \| `prod` (`test` under pytest) |
| `ADMIN_ONLY` | admin role | no | `1` | `1` → `ROOT_URLCONF = config.urls_admin` (backend §4) |
| `SECRET_KEY` | all | **yes** | `change-me-…` in dev | ≥ 50 characters outside dev |
| `DATABASE_URL` | all | **yes** | `postgres://wassal:…@postgres:5432/wassal` | `connect_timeout=3` is appended if absent |
| `CACHE_URL` | all | **yes** | `redis://valkey:6379/0` | Django cache, used for throttles and readiness. `redis://`, or `locmem://` (the restore drill's check step only). |
| `CELERY_BROKER_URL` | all | **yes** | `redis://valkey:6379/1` | — |
| `API_HOST` | all | no | `api.140-238-1-2.sslip.io` | FR-042a. Goes into `ALLOWED_HOSTS` for the API role. |
| `ADMIN_HOST` | all | no | `admin.10-66-0-1.sslip.io` | `ALLOWED_HOSTS` and `CSRF_TRUSTED_ORIGINS` for the admin role |
| `NUM_PROXIES` | all | no | `1` (`0` in dev) | Proxies in front of Django, for the client address |
| `RELEASE` | all | no | baked into the image | 40-hex commit. `dev` uses `dev`. |
| `SENTRY_DSN` | staging, prod | **yes** | empty in dev | Empty disables Sentry |
| `SENTRY_TRACES_SAMPLE_RATE` | — | no | `0.05` | `0.0`–`0.1` allowed (FR-035) |
| `THROTTLE_ADDRESS_RATE` | — | no | `120/min` | DRF rate string (FR-015) |
| `HC_PING_HEARTBEAT_URL` | staging, prod | **yes** | empty in dev | Healthchecks.io ping URL. Empty skips the ping. |
| `LOG_LEVEL` | — | no | `INFO` | — |
| `WASSAL_READ_DOTENV` | — | no | `1` | `dev` only: `0` stops `config/env.py` from reading `backend/.env` (the settings-guard tests and the image build set it) |
| `GUNICORN_WORKERS`, `GUNICORN_THREADS` | — | no | `2`, `4` | Set per role and environment by `compose.yml` from the sizing files in `backend/docker/env/` |
| `TEST_DATABASE_URL`, `TEST_CACHE_URL`, `TEST_BROKER_URL` | test | **yes** (placeholder in dev) | `postgres://postgres:change-me-postgres@127.0.0.1:5432/postgres`, `redis://127.0.0.1:6379/2`, `redis://127.0.0.1:6379/3` | pytest only, against the real PostgreSQL and Valkey (constitution XIII). The superuser URL lets pytest-django create its test database. |

In `dev`, `backend/.env` points `DATABASE_URL`, `CACHE_URL` and `CELERY_BROKER_URL` at `127.0.0.1` for
commands run on the host. `compose.dev.yml` overrides them with the service names inside the
containers.

## Backup and drill variables (production ops role only)

These live in separate files, so the API and worker containers never hold storage credentials.

| File | Variable | Secret | Rule |
| --- | --- | --- | --- |
| `/etc/wassal/prod-backup.env` | `B2_S3_ENDPOINT`, `B2_REGION` | no | `https://s3.<region>.backblazeb2.com` and its `<region>`, from the bucket's Endpoint field (research R9) |
| | `B2_DAILY_BUCKET`, `B2_WEEKLY_BUCKET` | no | The two Object Lock buckets (14 and 56 days) |
| | `B2_BACKUP_KEY_ID`, `B2_BACKUP_APP_KEY` | **yes** | The backup key: `writeFiles` only (FR-039a) |
| | `BACKUP_PREFIX` | no | `prod` (the keys are restricted to `prod/`) |
| | `BACKUP_WEEKLY_WEEKDAY` | no | `6` (Sunday, Python `weekday()`) |
| | `HC_PING_BACKUP_URL` | **yes** | — |
| | `BACKUP_STATE_FILE` | no | Optional. Default `/var/lib/wassal/backup/last-backup.json`, inside the container (the compose `backup` service mounts `/var/lib/wassal/prod/backup/` there) |
| `/etc/wassal/prod-drill.env` | `B2_S3_ENDPOINT`, `B2_REGION`, `B2_DAILY_BUCKET`, `B2_WEEKLY_BUCKET`, `BACKUP_PREFIX` | no | — |
| | `B2_DRILL_KEY_ID`, `B2_DRILL_APP_KEY` | **yes** | The drill key: `listBuckets`, `listFiles`, `readFiles` |
| | `DRILL_ROWCOUNT_TOLERANCE` | no | `0` (counts are snapshot-exact, research R9) |
| | `HC_PING_DRILL_URL` | **yes** | — |

- The backup job's container gets all of `prod-backup.env`.
- In the drill, only the fetch container gets `prod-drill.env`. The check container gets
  `DRILL_ROWCOUNT_TOLERANCE` alone, plus throwaway values for what `config.settings.prod` requires
  (the fetch container gets those too). `HC_PING_DRILL_URL` is read by the host script
  ([operations.md](./operations.md#restore-drill-fr-040-fr-040a)).
- The B2 admin key is never on the host. It stays in the operator's password manager and is typed
  into `backend/tools/b2_setup.py` when needed (research R9).

## Host and edge files

| File | Holds | Read by |
| --- | --- | --- |
| `/etc/wassal/<env>.env` | The application variables above | Compose `env_file` for `api`, `admin`, `worker`, `beat`, `migrate` |
| `/etc/wassal/<env>-db.env` | `POSTGRES_PASSWORD` (superuser), `WASSAL_DB_PASSWORD` (app role) | The `postgres` container and its init script |
| `/etc/wassal/edge.env` | `PUBLIC_BIND_IP` (the VNIC's private IP), `ADMIN_BIND_IP=10.66.0.1`, `PUBLIC_TLS` (the Let's Encrypt account email; `internal` in the CI smoke test), `PROD_API_HOST`, `PROD_ADMIN_HOST`, `STAGING_API_HOST`, `STAGING_ADMIN_HOST` | The edge Caddy container |
| `/etc/wassal/host-monitor.env` | `HC_PING_HOST_MONITOR_URL` (secret), `DISK_ALERT_PERCENT=80`, `CERT_ALERT_DAYS=14`, `QUEUE_BACKLOG_THRESHOLD=100`, `QUEUE_BACKLOG_MINUTES=10`, `BACKUP_STORAGE_ALERT_BYTES=8000000000` | `wassal-host-monitor.service` |
| `/etc/wireguard/wg0.conf` | Server private key and peers | `wg-quick@wg0` |
| `/etc/wassal/wg-peers.tsv` | Peer registry ([data-model.md](../data-model.md#private-network-peer)) | `wg-peer` |
| `/etc/wassal/wg-server.env` | `WG_SERVER_PUBLIC_KEY`, `WG_ENDPOINT` (`<reserved public IP>:51820`), written by `provision.sh --public-ip` | `wg-peer` |
| `~deploy/.ssh/authorized_keys` | Two keys, each `restrict,command="sudo /opt/wassal/bin/deploy --only <env>"` | sshd (listening on `10.66.0.1` only) |
| `/etc/sudoers.d/wassal-deploy` | `deploy ALL=(root) NOPASSWD: /opt/wassal/bin/deploy --only staging, /opt/wassal/bin/deploy --only prod`, plus `env_keep` for `SSH_ORIGINAL_COMMAND`. `deploy` isn't in the `docker` group. | sudo |

## CI secrets (GitHub Environments)

| Environment | Secret | Purpose |
| --- | --- | --- |
| `staging` | `WG_CONFIG` | A complete `wg-quick` client config for peer `deploy-staging` |
| | `DEPLOY_SSH_KEY`, `DEPLOY_KNOWN_HOSTS` | The `deploy` key limited to `--only staging`, and the host key pin |
| `production` | the same three for `deploy-prod` | Deployment rule: tags matching `v*` only |

No other credentials exist in CI. GHCR pushes use the workflow's own `GITHUB_TOKEN` with
`packages: write`.
