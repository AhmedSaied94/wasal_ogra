# Contract: Edge, Host and Operations

Spec FR-005 – FR-009, FR-019 – FR-023a, FR-030 – FR-043. This is the interface between the repository
and the production host. The scripts live in `backend/docker/host/` and are installed to
`/opt/wassal/` by `provision.sh`.

## Host layout

| Item | Value |
| --- | --- |
| OS | Ubuntu 24.04 LTS aarch64 (Oracle platform image), `unattended-upgrades` on for security updates |
| Interfaces | `ens3` (VCN, private IP mapped to the reserved public IP; A1 images may name it `enp0s6`, and `provision.sh` takes it from the default route, R13); `wg0` = `10.66.0.1/24`, UDP 51820 |
| Docker | Engine + Compose v2 from Docker's apt repository. Data root on the boot volume (R1). Every container has `restart: unless-stopped` (FR-008). |
| Compose projects | `wassal-edge` (from `/opt/wassal/edge/`, updated by re-running `provision.sh`), `wassal-staging`, `wassal-prod` (from the serving tag's `deploy/` copy) |
| State | `/var/lib/wassal/<env>/release`, `release.previous`, `/var/lib/wassal/<env>/deploy/<tag>/` (the compose file and sizing env of each deployed tag; the two newest are kept), `/var/lib/wassal/prod/backup/last-backup.json` (the backup container's own directory), `/var/lib/wassal/drill-results.jsonl`, `/var/lib/wassal/host-monitor/` |
| Logs | Containers use the `json-file` driver with `max-size=10m`, `max-file=5` (FR-036). Caddy's access log is `/var/log/caddy/access.log` with `roll_size 50MiB` and `roll_keep_for 336h`, so client IPs are kept at most 14 days (backend §14.2). |

## Network exposure (FR-023, SC-011)

The host firewall is Oracle's own iptables framework (`netfilter-persistent`). `provision.sh`
renders it from `host/iptables/rules.v4.tmpl`, keeping Oracle's `InstanceServices` rules and
inserting the rules below before the image's final `REJECT` (research R13). The VCN security list
mirrors the public rules. UFW is never used.

| Interface | Allowed in | Notes |
| --- | --- | --- |
| `ens3` | TCP 80, TCP 443 (Caddy, public sites only), UDP 51820 (WireGuard) | WireGuard never answers unauthenticated packets. TCP 22 is open only during first provisioning and closed by `provision.sh --finalize`. |
| `wg0` | from `10.66.0.2–9` (operator): TCP 22, TCP 443 · from `10.66.0.10–99` (staff): TCP 443 · from `10.66.0.200–209` (deploy): TCP 22 | sshd listens on `10.66.0.1:22` only |
| `lo` | everything | App containers publish only on `127.0.0.1` |
| Docker | Only Caddy reaches the outside, and it uses the host network, so host input rules apply. No other container publishes on a non-loopback address. | — |

- HTTP/3 is off (`protocols h1 h2`), so UDP 443 stays closed.
- Every site binds an explicit address (Caddy warns against mixing bound and unbound sites on one
  port).
- `net.ipv4.ip_nonlocal_bind = 1` lets Caddy bind `10.66.0.1` even if it starts before `wg0` is up
  at boot.
- Django also sets `DATA_UPLOAD_MAX_MEMORY_SIZE = 524288` as a backstop, enforced on the API by
  `BodySizeLimitMiddleware` with the same `413 payload_too_large`.

## Edge (Caddy, `network_mode: host`)

| Site | Bind | TLS | Behaviour |
| --- | --- | --- | --- |
| `{$PROD_API_HOST}`, `{$STAGING_API_HOST}` | `{$PUBLIC_BIND_IP}` | `tls {$PUBLIC_TLS}`: Let's Encrypt (HTTP-01/TLS-ALPN) with that account email, or `internal` in the CI smoke test | `request_body max_size 512KiB` (524,288 bytes; Caddy reads `512KB` as 512,000), plus `reverse_proxy { request_buffers 1MB }`. The body is read before proxying, so the limit fires even when the upstream never reads it. Never `unlimited` (Caddy bug #8206, R6). `handle_errors 413` → JSON `payload_too_large` envelope. Security headers (below). `reverse_proxy 127.0.0.1:<port>` with `lb_try_duration 30s` and `lb_try_interval 250ms` (connection failures are retried for every method while the upstream restarts, SC-004). JSON access log. |
| `{$PROD_ADMIN_HOST}`, `{$STAGING_ADMIN_HOST}` | `{$ADMIN_BIND_IP}` (`10.66.0.1`) | `tls internal` (Caddy's local CA. Staff install its root, runbook `private-network.md`.) | Same headers plus the admin CSP. `reverse_proxy 127.0.0.1:<admin port>`. |
| `http://…` (public binds) | `{$PUBLIC_BIND_IP}:80` | — | 308 redirect to HTTPS (Caddy's automatic HTTPS) |

**Headers on every site:**

- `Strict-Transport-Security: max-age=31536000; includeSubDomains`
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`
- `Referrer-Policy: strict-origin-when-cross-origin`
- `-Server` and `-Via`: the edge doesn't name itself (`reverse_proxy` adds `Via: 1.1 Caddy`).

Error routes (`handle_errors`) set the same headers again, because Caddy drops them before running
one (R5).

**Edge process:**

- **Admin API:** a Unix socket at `/run/caddy/admin.sock`, on a tmpfs inside the container
  (`admin unix//…`). It is not on `127.0.0.1:2019`: with host networking, every local process could
  reach that and rewrite the edge, an unprivileged shell from a deploy key that lost its forced
  command included. `caddy reload` inside the container finds the socket from the Caddyfile.
- **Health check:** a site on `http://127.0.0.1:2020` that answers `ok`.
- **Timeouts:** `read_header 10s`, `read_body 30s` and `idle 2m`. Slow clients can't hold
  connections, or the 1MB request buffers, open.
- **Access logs:** JSON, `roll_size 50MiB`, `roll_keep_for 336h`. The API sites write
  `/var/log/caddy/access.log`, and the admin sites `/var/log/caddy/admin-access.log`.

**Admin CSP:** `default-src 'self'; script-src 'self' 'sha256-QE3U2xYF7B4J2ro1/9oxiKhaWCGW39gB7ocQ/xlD0bE=';
style-src 'self' 'unsafe-inline'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'self';
form-action 'self'; object-src 'none'`.

- The hash is django-celery-beat's inline script on the periodic-task form. The T047 spike found it
  (R5).
- `apps/accounts/tests/test_admin_csp.py` keeps the hash list equal to the inline scripts the admin
  pages render.

## Deploy interface (FR-030 – FR-034)

CI reaches the host only as WireGuard peer `deploy-<env>` and SSH user `deploy`. Each key's
`authorized_keys` line is `restrict,command="sudo /opt/wassal/bin/deploy --only <env>"`, so the key can
do nothing but run the deploy script for its own environment. The script runs as root through a
sudoers rule that allows only those two invocations. `deploy` isn't in the `docker` group, so an
`authorized_keys` line that loses its forced command gives an unprivileged shell, not root.

**`/opt/wassal/bin/deploy --only <env>`**, with the arguments in `SSH_ORIGINAL_COMMAND` as
`<env> <tag> [rehearse-migrate-fail|rehearse-verify-fail]`. A third token is accepted only with
`--only staging`. It replaces the migrate command with one that exits 1, or makes verification
expect a wrong release, so the real failure and restore paths run against real containers (US4-4,
US4-5, SC-005) without a broken image ever being built.

| Step | Rule | On failure |
| --- | --- | --- |
| 1. Validate | `env` equals `--only`. `tag` matches `^sha-[0-9a-f]{40}$` (staging) or `^v[0-9]+\.[0-9]+\.[0-9]+$` (prod). The image repository is fixed in the script and never taken from input. | exit 2, nothing touched |
| 2. Lock | `flock -w 900 /run/lock/wassal-deploy-<env>.lock`. A second deploy waits (FR-032). | exit 3 on timeout |
| 3. Pull | `docker pull ghcr.io/ahmedsaied94/wassal-backend:<tag>`. Read `RELEASE` from the image. Copy the release's `/app/deploy/` (its `compose.yml`, the `env/<env>.env` sizing file and `postgres/initdb/`, which `compose.yml` mounts) to `/var/lib/wassal/<env>/deploy/<tag>/`, so the stack definition deploys and rolls back with the code. Every later `docker compose` call uses `-f …/<tag>/compose.yml --env-file …/<tag>/env/<env>.env`. Then check the rendered stack against the host's allowlist (below). | exit 4 |
| 4. Migrate | `RELEASE_TAG=<tag> docker compose -p wassal-<env> --profile ops run --rm migrate`. Runs `migrate --noinput`, then `check --deploy`. | exit 5. Services were never restarted, so the previous release keeps serving (US4-4). |
| 5. Restart | `RELEASE_TAG=<tag> docker compose -p wassal-<env> up -d --no-deps --wait --wait-timeout 180 api admin worker beat` | go to 7 |
| 6. Verify | Within 120 s, polling every 2 s: `GET 127.0.0.1:<api port>/readyz` = 200 and `/healthz` `.release` = `RELEASE`, and the same for the admin port. These direct calls carry no `X-Forwarded-For`, so the rate limit doesn't count them ([api.md](./api.md#conventions-on-the-api-hostname)). | go to 7 |
| 7. Restore | Re-run step 5 with `release.previous`, wait for it to be healthy, then exit 6 | exit 7 if even the restore fails (the operator is alerted by the CI failure **and** by the uptime check) |
| 8. Record | Move `release` to `release.previous`, write the new tag, print a JSON summary | — |
| 9. Prune | Delete the `deploy/<tag>/` copies and local images of every tag except `release` and `release.previous`. Each environment prunes only its own tag form (`sha-…` or `v…`), so staging never removes a production image. | Logged, not fatal |

- The stack copy in step 3 is made with `docker create` and `docker cp` into `<tag>.new/`, then
  renamed, so a half-done copy is never used.
- The stack definition comes out of the image, and root runs it. So step 3 renders it
  (`docker compose --profile ops config --format json`) and checks it with the host's `python3`
  before anything starts. A commit on master or a write to the registry must not be able to give a
  container the host. The check allows only:
  - the services `api`, `admin`, `worker`, `beat`, `migrate` and `backup` on the release's own
    image, `postgres` on a `postgres:<version>` image and `valkey` on a `valkey/valkey:<version>` one;
  - the service keys the stack uses (image, command, entrypoint, environment, healthcheck, ports,
    volumes, networks, depends_on, profiles, restart, logging, mem_limit, stop_grace_period,
    working_dir). Anything else, such as `privileged`, `network_mode`, `cap_add` or `devices`, is refused;
  - ports bound to `127.0.0.1`, and the default network only;
  - plain named volumes, tmpfs, and exactly two binds: `/var/lib/wassal/<env>/initdb` read-only
    for postgres and `/var/lib/wassal/<env>/backup` for backup.

  A refused stack exits 4 with one `stack: …` line per problem, before the init scripts are synced
  or anything runs. The rendered config holds the environment's secrets, so it only goes to the
  checker's stdin, and the checker prints only the problems.
- Step 3 also copies the release's `postgres/initdb/` to `/var/lib/wassal/<env>/initdb/`. The sizing
  file names that path as `POSTGRES_INITDB_DIR`, and postgres mounts it from there.
  - With the release's own copy, the mount path changes with every tag. Compose then sees a changed
    postgres service and restarts the database on every deploy, a failed migration included. This
    was measured with real containers.
  - The script refuses (exit 4) a sizing file that names any other path.
  - The backup and drill scripts pass the same sizing file, so they see the same path.
- The JSON summary goes to stdout; progress and compose output go to stderr.

- Re-running a deploy of the tag that is already serving only re-verifies.
- **Rollback** (FR-033) is a normal deploy of the previous tag, from CI (re-run the old tag's release
  workflow) or by the operator over WireGuard as `ubuntu`
  (`sudo env SSH_ORIGINAL_COMMAND='prod v1.2.2' /opt/wassal/bin/deploy --only prod`). Migrations are
  never reversed.

## Backup job (FR-039, FR-039a)

`wassal-backup@prod.timer` runs at `OnCalendar=*-*-* 03:00:00 Africa/Cairo` with `Persistent=true`
(a missed run fires at the next boot). The service runs `/opt/wassal/bin/backup prod`, which reads the
serving tag from `/var/lib/wassal/prod/release`, takes the deploy lock (so a release never switches
under a running backup), and runs `docker compose -p wassal-prod` with that tag's `deploy/` copy and
`--profile ops run --rm --no-deps -T backup`. That calls `python manage.py backup_db` in the serving
release's image. The steps:

1. Open a `REPEATABLE READ, READ ONLY` transaction and `SELECT pg_export_snapshot()`.
2. Count every table of the app schemas in that snapshot. The counts use `psycopg.sql.Identifier`,
   never string formatting.
3. Run `pg_dump --format=custom --snapshot=<id>` to a temp file, with the password from the
   environment, never in argv. Close the transaction.
4. Check the file with `pg_restore --list`, then compute its `sha256`.
5. Upload the dump, then the metadata JSON (the completion marker), to `prod/YYYY/MM/DD/…` in
   `B2_DAILY_BUCKET`. On the weekly day, upload the same pair to `B2_WEEKLY_BUCKET` as well. Each new
   version inherits its bucket's governance lock (14 or 56 days). The backup key has `writeFiles`
   only, so it can't delete a version, shorten a lock, or read or list anything (R9).
6. Write the metadata to `/var/lib/wassal/prod/backup/last-backup.json` for the host monitor's
   storage check. That directory, owned by the image's `app` user (uid 10001), is the container's
   only host mount, at `/var/lib/wassal/backup`. The rest of `/var/lib/wassal/prod` holds the stack
   definitions that root runs, so the container never gets write access to it.
7. Ping `HC_PING_BACKUP_URL` on success (body: size, duration), or `/fail` with a short reason.

The service has `MemoryMax=1G`. A failure in any step pings `/fail` and exits non-zero.

## Restore drill (FR-040, FR-040a)

`wassal-restore-drill@prod.timer` runs at `OnCalendar=*-*-01 05:00:00 Africa/Cairo` with
`Persistent=true`. That is the quiet hour, two hours after that night's backup. The time is
configurable through a systemd drop-in. It runs `/opt/wassal/bin/restore-drill prod`:

1. Check that free disk on the Docker volume is at least `DRILL_MIN_FREE_GB` (default 5). If not,
   ping `/fail` and stop.
2. **Fetch** (outside access, no database): run the serving release's image on the default bridge
   network with `prod-drill.env` and a fresh host directory `/var/lib/wassal/drill/` mounted, and call
   `python manage.py restore_drill fetch /drill`. It downloads the newest *complete* backup (one with
   metadata) and its metadata, and checks the `sha256`. This container holds the read-only storage
   key, plus the same throwaway values as step 4 (with an unreachable `DATABASE_URL`), because
   `config.settings.prod` won't start without them. It gets none of production's application
   secrets.
3. Create an internal network `wassal-drill` (`--internal`: no outside route, not attached to
   production's networks) and a volume `wassal-drill-pgdata`. Start `postgres:<same tag as prod>`
   named `wassal-drill-db` on it, with `--memory 1g`, a random password for this run, and the volume.
4. **Check** (database only, no outside access): run the same image on `wassal-drill` only, with
   `/var/lib/wassal/drill/` mounted read-only, `DATABASE_URL` pointing at `wassal-drill-db`, and
   throwaway values for every other setting that `config.settings.prod` requires:
   - `WASSAL_ENV=prod` and a random `SECRET_KEY` of 64 characters for this run;
   - `CACHE_URL=locmem://` and `CELERY_BROKER_URL=memory://` (the check uses neither);
   - `API_HOST=drill.invalid` and `ADMIN_HOST=drill.invalid`;
   - inert `SENTRY_DSN=https://drill@drill.invalid/1` and `HC_PING_HEARTBEAT_URL=https://drill.invalid/`.
     The `.invalid` domain never resolves, and the network has no outside route anyway.

   It gets no storage key and none of production's application secrets. `python manage.py restore_drill check /drill`:
   - runs `pg_restore --no-owner --no-privileges --exit-on-error` (the drill database has no `wassal`
     role to grant to);
   - checks **restore** (exit 0), **migrations** (every migration in the code's graph is applied,
     counting a squash as applied once everything it replaces is, and no applied migration is unknown
     to the code; `django_migrations` is read over the drill's own connection), **row counts** (each table equals the metadata, within
     `DRILL_ROWCOUNT_TOLERANCE`, with no missing or extra tables) and **invariants** (every registered
     check passes);
   - prints the result line (data-model "Restore drill result") with the durations, as the last
     stdout line that starts with `{"started_at":` (the app's JSON logs share stdout). It exits 1
     after printing when the outcome is `fail`, and non-zero with no line when it can't finish.
5. The host script appends that line to `drill-results.jsonl` and pings `HC_PING_DRILL_URL` with it,
   or `/fail` with a short reason if any step failed or printed no result.
6. `trap EXIT` always runs `docker rm -f wassal-drill-db`, `docker volume rm wassal-drill-pgdata`,
   `docker network rm wassal-drill` and `rm -rf /var/lib/wassal/drill/`.

The container that restores the backup can reach neither the internet nor production's database,
cache or networks, and the container that downloads it never touches a database. The restored data
never leaves the host (FR-040a).

## Host monitor (FR-038)

`wassal-host-monitor.timer` runs every 5 min. `/opt/wassal/bin/host-monitor` checks:

| Check | Fails when |
| --- | --- |
| Disk | `/` or the Docker data root ≥ `DISK_ALERT_PERCENT` (80) |
| Certificates | Any public or admin hostname's served certificate expires in < `CERT_ALERT_DAYS` (14), checked with `openssl s_client` against the bind address with SNI |
| Queue backlog | `LLEN` of any of the 4 prod queues > `QUEUE_BACKLOG_THRESHOLD` (100) for ≥ `QUEUE_BACKLOG_MINUTES` (10), tracked in `/var/lib/wassal/host-monitor/backlog.json` |
| Backup storage | The latest dump's `size_bytes` × 22 (14 daily + 8 weekly kept) ≥ `BACKUP_STORAGE_ALERT_BYTES` (8 GB, 80% of B2's free 10 GB, research R9) |

- All checks pass → ping `HC_PING_HOST_MONITOR_URL`.
- Any check fails → ping `/fail` with the failing checks listed.
- If the monitor itself stops, Healthchecks.io alerts after its grace period.

## Heartbeat (FR-007)

The `heartbeat` periodic task (data migration, every 5 min, queue `default`) runs
`common.tasks.heartbeat`:

- `bind=True`, `autoretry_for=(requests.RequestException,)`, `retry_backoff=True`, `max_retries=3`;
- HTTP timeout 10 s.

It pings `HC_PING_HEARTBEAT_URL`, and does nothing if that is empty (dev).

## Private-network administration (FR-023a)

| Command | Effect |
| --- | --- |
| `sudo wg-peer add <name> <role>` | Generates a key pair on the host, assigns the next address in the role's range, appends to `wg-peers.tsv`, applies with `wg set` and `wg-quick save`, and prints the client config once. The private key is never stored on the host afterwards. |
| `sudo wg-peer remove <name>` | `wg set wg0 peer <pub> remove`, then saves and marks the row removed. Access ends at once (US3-8). |
| `sudo wg-peer list` | Name, role, address, latest handshake |

**Break-glass** (spec edge case): the OCI serial console connection (R1) reaches the VM without the
network. `docs/runbooks/break-glass.md` covers re-keying `wg0` and reopening SSH temporarily.
