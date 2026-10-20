# Contract: Configuration and Secrets

Spec FR-001 – FR-004, FR-001a, FR-024, FR-042a. All configuration comes from the environment
(FR-002).

- In `dev`, it comes from `backend/.env`, copied from the committed `backend/.env.example`.
- In `staging` and `prod`, it comes from root-owned files under `/etc/wassal/` (mode `0400`) on
  that environment's own host, which Compose reads as `env_file`. They are never committed, and
  `.gitignore` already blocks `.env*` except `.env.example`. Each host holds only its own files
  ([Host and edge files](#host-and-edge-files)).

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
| `API_HOST` | all | no | `api.193-122-74-125.sslip.io` (prod), `staging-api.141-147-129-92.sslip.io` (staging) | FR-042a. Goes into `ALLOWED_HOSTS` for the API role. The edge's `edge.env` holds the same value. |
| `ADMIN_HOST` | all | no | `admin.10-66-0-1.sslip.io` (prod), `staging-admin.10-67-0-1.sslip.io` (staging) | `ALLOWED_HOSTS` and `CSRF_TRUSTED_ORIGINS` for the admin role. The edge's `edge.env` holds the same value. |
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

These live in separate files, so the API and worker containers never hold storage credentials. The
backup file is on the prod host only, and the drill file on the staging host only, where the
restore drill runs ([operations.md](./operations.md#restore-drill-fr-040-fr-040a)). No host keeps
both keys. The one exception is a real restore into production: the operator puts a temporary copy
of the read key at `/run/wassal-prod-drill.env` on the prod host (cleared by a reboot) and deletes it
when the restore ends (`docs/runbooks/restore.md`).

| File | Variable | Secret | Rule |
| --- | --- | --- | --- |
| `/etc/wassal/prod-backup.env` (prod host) | `B2_S3_ENDPOINT`, `B2_REGION` | no | `https://s3.<region>.backblazeb2.com` and its `<region>`, from the bucket's Endpoint field (research R9) |
| | `B2_DAILY_BUCKET`, `B2_WEEKLY_BUCKET` | no | The two Object Lock buckets (14 and 56 days) |
| | `B2_BACKUP_KEY_ID`, `B2_BACKUP_APP_KEY` | **yes** | The backup key: `writeFiles` only (FR-039a) |
| | `BACKUP_PREFIX` | no | `prod` (the keys are restricted to `prod/`) |
| | `BACKUP_WEEKLY_WEEKDAY` | no | `6` (Sunday, Python `weekday()`) |
| | `HC_PING_BACKUP_URL` | **yes** | — |
| | `BACKUP_STATE_FILE` | no | Optional. Default `/var/lib/wassal/backup/last-backup.json`, inside the container (the compose `backup` service mounts `/var/lib/wassal/prod/backup/` there) |
| `/etc/wassal/prod-drill.env` (staging host) | `B2_S3_ENDPOINT`, `B2_REGION`, `B2_DAILY_BUCKET`, `B2_WEEKLY_BUCKET`, `BACKUP_PREFIX` | no | The same values as in `prod-backup.env`: the drill reads production's backups |
| | `B2_DRILL_KEY_ID`, `B2_DRILL_APP_KEY` | **yes** | The drill key: `listBuckets`, `listFiles`, `readFiles` |
| | `DRILL_ROWCOUNT_TOLERANCE` | no | `0` (counts are snapshot-exact, research R9) |
| | `HC_PING_DRILL_URL` | **yes** | — |

- The backup job's container, on the prod host, gets all of `prod-backup.env`.
- In the drill, on the staging host, only the fetch container gets `prod-drill.env`. The check
  container gets `DRILL_ROWCOUNT_TOLERANCE` alone, plus throwaway values for what
  `config.settings.prod` requires (the fetch container gets those too). `HC_PING_DRILL_URL` is read
  by the host script ([operations.md](./operations.md#restore-drill-fr-040-fr-040a)).
- The B2 admin key is never on either host. It stays in the operator's password manager and is
  typed into `backend/tools/b2_setup.py` when needed (research R9).

## Host and edge files

Each host holds only its own environment's files:

- **prod host:** `host.env`, `edge.env`, `prod.env`, `prod-db.env`, `prod-backup.env`,
  `host-monitor.env`, `wg-server.env` and `wg-peers.tsv` in `/etc/wassal/`, plus `wg0.conf`.
- **staging host:** `host.env`, `edge.env`, `staging.env`, `staging-db.env`, `staging-backup.env`
  (since B04: staging's own write-only key, B04 contracts/environment.md), `prod-drill.env`,
  `host-monitor.env`, `wg-server.env` and `wg-peers.tsv` in `/etc/wassal/`, plus `wg0.conf`.

| File | Host | Holds | Read by |
| --- | --- | --- | --- |
| `/etc/wassal/host.env` | both | `WASSAL_ENV` (`prod` or `staging`) and `WG_ADDRESS` (`10.66.0.1` on prod, `10.67.0.1` on staging). Written by `provision.sh --env` on the first run (root, `0600`), never by hand ([operations.md](./operations.md#host-identity-fr-001a)). | `provision.sh`; the edge container (`WASSAL_ENV` picks the upstream ports); `deploy`, `backup`, `restore-drill`, `host-monitor` and `wg-peer`, which read it as data |
| `/etc/wassal/<env>.env` | that environment's: `prod.env` on prod, `staging.env` on staging | The application variables above | Compose `env_file` for `api`, `admin`, `worker`, `beat`, `migrate` |
| `/etc/wassal/<env>-db.env` | that environment's | `POSTGRES_PASSWORD` (superuser), `WASSAL_DB_PASSWORD` (app role) | The `postgres` container and its init script |
| `/etc/wassal/edge.env` | both | `PUBLIC_BIND_IP` (the VNIC's private IP: `10.0.0.28` on prod, `10.1.0.216` on staging), `ADMIN_BIND_IP` (the host's `WG_ADDRESS`; `provision.sh` refuses any other value), `PUBLIC_TLS` (the Let's Encrypt account email; `internal` in the CI smoke test), `API_HOST` and `ADMIN_HOST` (this host's environment's hostnames, as in `<env>.env`) | The edge Caddy container, after `host.env` |
| `/etc/wassal/host-monitor.env` | both | `HC_PING_HOST_MONITOR_URL` (secret; this host's own check, `host-monitor-prod` or `host-monitor-staging`), `DISK_ALERT_PERCENT=80`, `CERT_ALERT_DAYS=14`, `QUEUE_BACKLOG_THRESHOLD=100`, `QUEUE_BACKLOG_MINUTES=10`. `BACKUP_STORAGE_ALERT_BYTES=8000000000` (since B04 both hosts check their own backups, each in its own B2 account with its own free 10 GB). | `wassal-host-monitor.service` |
| `/etc/wireguard/wg0.conf` | both | This host's server private key, `Address = <WG_ADDRESS>/24` and its peers | `wg-quick@wg0` |
| `/etc/wassal/wg-peers.tsv` | both | This host's peer registry ([data-model.md](../data-model.md#private-network-peer-fr-023a)) | `wg-peer` |
| `/etc/wassal/wg-server.env` | both | `WG_SERVER_PUBLIC_KEY`, `WG_ENDPOINT` (`<this host's reserved public IP>:51820`: `193.122.74.125:51820` on prod, `141.147.129.92:51820` on staging), written by `provision.sh --public-ip` | `wg-peer` |
| `~deploy/.ssh/authorized_keys` | both | One key: `restrict,command="sudo /opt/wassal/bin/deploy --only <env>"`, where `<env>` is the host's `WASSAL_ENV` | sshd (listening on the host's `WG_ADDRESS` only) |
| `/etc/sudoers.d/wassal-deploy` | both | `deploy ALL=(root) NOPASSWD: /opt/wassal/bin/deploy --only <env>` for the host's `WASSAL_ENV` only, plus `env_keep` for `SSH_ORIGINAL_COMMAND`. Written by `provision.sh`. `deploy` isn't in the `docker` group. | sudo |

## CI secrets (GitHub Environments)

Each GitHub Environment's secrets reach one host only.

| Environment | Secret | Purpose |
| --- | --- | --- |
| `staging` | `WG_CONFIG` | A complete `wg-quick` client config for peer `deploy-staging` on the staging host (`Endpoint = 141.147.129.92:51820`, `AllowedIPs = 10.67.0.1/32`) |
| | `DEPLOY_SSH_KEY`, `DEPLOY_KNOWN_HOSTS` | The staging host's `deploy` key (limited to `--only staging`), and that host's SSH host key pinned for `10.67.0.1` |
| `production` | the same three for the prod host: peer `deploy-prod` (`193.122.74.125:51820`, `AllowedIPs = 10.66.0.1/32`), its `deploy` key (`--only prod`) and its host key pinned for `10.66.0.1` | Deployment rule: tags matching `v*` only |

No other credentials exist in CI. GHCR pushes use the workflow's own `GITHUB_TOKEN` with
`packages: write`.
