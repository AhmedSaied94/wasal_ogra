# Contract: Edge, Host and Operations

Spec FR-001a, FR-005 – FR-009, FR-019 – FR-023a, FR-030 – FR-043. This is the interface between the
repository and the two hosts. The scripts live in `backend/docker/host/` and are installed to
`/opt/wassal/` by `provision.sh`.

> **Changed 2026-10-19 (owner decision):** staging and production each run on their own VM. This
> replaces the first design, one VM running both environments behind one shared edge. Everything
> below describes the two-host design.

## Host layout

Each host serves exactly one environment (FR-001a), chosen once by `provision.sh --env`
([Host identity](#host-identity-fr-001a)). The IP addresses and hostnames are configuration
(FR-042a). They live in the host's env files, never in code.

| | prod host | staging host |
| --- | --- | --- |
| Shape | `VM.Standard.A1.Flex`, 1 OCPU / 6 GB, 100 GB boot volume | `VM.Standard.A1.Flex`, 1 OCPU / 6 GB, 47 GB boot volume |
| Reserved public IP | `193.122.74.125` | `141.147.129.92` |
| VCN private IP (`PUBLIC_BIND_IP`) | `10.0.0.28` (its own VCN) | `10.1.0.216` |
| WireGuard `wg0` (`WG_ADDRESS`) | `10.66.0.1/24` | `10.67.0.1/24` |
| API hostname | `api.193-122-74-125.sslip.io` | `staging-api.141-147-129-92.sslip.io` |
| Admin hostname | `admin.10-66-0-1.sslip.io` | `staging-admin.10-67-0-1.sslip.io` |
| Compose projects | `wassal-edge`, `wassal-prod` | `wassal-edge`, `wassal-staging` |
| App upstreams (API / admin) | `127.0.0.1:8100` / `127.0.0.1:8101` | `127.0.0.1:8200` / `127.0.0.1:8201` |
| Timers | `wassal-backup@prod.timer`, `wassal-host-monitor.timer` | `wassal-restore-drill@prod.timer` (drills production's backups), `wassal-host-monitor.timer` |
| Deploy access | WireGuard peer `deploy-prod`, `deploy --only prod` | WireGuard peer `deploy-staging`, `deploy --only staging` |

The files under `/etc/wassal/` on each host are listed in
[environment.md](./environment.md#host-and-edge-files).

On both hosts:

| Item | Value |
| --- | --- |
| OS | Ubuntu 24.04 LTS aarch64 (Oracle platform image), `unattended-upgrades` on for security updates |
| Interfaces | The public interface is the default route's (`enp0s6` on the staging VM; Oracle's docs say `ens3`). It carries the VCN private IP mapped to the reserved public IP. `provision.sh` takes its name from the default route, so either name works (R13). `wg0` = `<WG_ADDRESS>/24`, UDP 51820. |
| Docker | Engine + Compose v2 from Docker's apt repository. Data root on the boot volume (R1). Every container has `restart: unless-stopped` (FR-008). |
| Compose projects | `wassal-edge` (from `/opt/wassal/edge/`, updated by re-running `provision.sh`) and the host's own `wassal-<env>` (from the serving tag's `deploy/` copy). No host runs the other environment's project. |
| State | For the host's environment only: `/var/lib/wassal/<env>/release`, `release.previous`, `/var/lib/wassal/<env>/deploy/<tag>/` (the compose file and sizing env of each deployed tag; the two newest are kept). Both hosts: `/var/lib/wassal/host-monitor/`. Prod host only: `/var/lib/wassal/prod/backup/last-backup.json` (the backup container's own directory). Staging host only: `/var/lib/wassal/drill-results.jsonl`, and `/var/lib/wassal/drill/` while a drill runs. |
| Logs | Containers use the `json-file` driver with `max-size=10m`, `max-file=5` (FR-036). Caddy's access log is `/var/log/caddy/access.log` with `roll_size 50MiB` and `roll_keep_for 336h`, so client IPs are kept at most 14 days (backend §14.2). |

The hosts never talk to each other. Neither can reach the other's private network or loopback
services. Production data reaches the staging host only from B2, during a restore drill (FR-040a).

## Host identity (FR-001a)

`provision.sh` records the host's environment on its first run. Every host script reads it from
there.

- **First run:** `sudo ./provision.sh --env <staging|prod> --public-ip <reserved public IP>`. Both
  options are required while `/etc/wassal/host.env` doesn't exist. `--env` is checked before any
  other step changes the host.
- **`/etc/wassal/host.env`** (root, `0600`, nothing secret) is written by `provision.sh` only:

  | Variable | prod host | staging host |
  | --- | --- | --- |
  | `WASSAL_ENV` | `prod` | `staging` |
  | `WG_ADDRESS` | `10.66.0.1` | `10.67.0.1` |

  `WG_ADDRESS` follows from the environment. It is never given separately.
- **Later runs** read `host.env`. `--env` may be repeated with the same value. A different value is
  refused (exit 1) before anything changes: switching a host's environment means rebuilding it
  (FR-043). A `host.env` with an unknown `WASSAL_ENV`, or a `WG_ADDRESS` other than its
  environment's, is refused the same way.
- `--public-ip` on a later run rewrites `WG_ENDPOINT` in `wg-server.env`. If `wg0.conf` is missing
  (break-glass re-keying, or a moved-aside one-host config), the run generates a new key and needs
  `--public-ip` again.
- `provision.sh` never deletes data. If it finds something that doesn't belong on this host (the
  other environment's Compose project, `/var/lib/wassal/<other env>/` or env files, or the other
  host's backup or drill env file), it prints a warning naming each one. Removing them is a runbook
  step.

What follows from `host.env`:

| Item | Rule |
| --- | --- |
| `/etc/wireguard/wg0.conf` | `Address = <WG_ADDRESS>/24`, written on the first run |
| Firewall | The `wg0` rules use the host's own /24 ([Network exposure](#network-exposure-fr-023-sc-011)) |
| sshd (`--finalize`) | `ListenAddress <WG_ADDRESS>`. `--finalize` requires a recent handshake from an operator peer of this host, and checks that sshd then listens on `<WG_ADDRESS>:22` only. |
| sudoers | `deploy ALL=(root) NOPASSWD: /opt/wassal/bin/deploy --only <WASSAL_ENV>` |
| State directories | `/var/lib/wassal/<WASSAL_ENV>/` and `/var/lib/wassal/host-monitor/` |
| Timers | prod: `wassal-backup@prod.timer` and `wassal-host-monitor.timer`. staging: `wassal-restore-drill@prod.timer` and `wassal-host-monitor.timer`. The unit files are installed on both hosts, and any other `wassal-*` timer is disabled. |
| Edge | `WASSAL_ENV` picks the upstream ports, and `ADMIN_BIND_IP` must equal `WG_ADDRESS` ([Edge](#edge-caddy-network_mode-host)) |
| Host scripts | `deploy`, `backup`, `restore-drill`, `host-monitor` and `wg-peer` read `host.env` as data, never sourced, and refuse to act for the other environment (their sections below). A missing `host.env` is an error. |

## Network exposure (FR-023, SC-011)

Each host has its own firewall: Oracle's own iptables framework (`netfilter-persistent`).
`provision.sh` renders it from `host/iptables/rules.v4.tmpl`, keeping Oracle's `InstanceServices`
rules and inserting the rules below before the image's final `REJECT` (research R13). The security
list of each host's subnet mirrors that host's public rules. UFW is never used.

`<wg>` below is the host's WireGuard prefix, from `WG_ADDRESS`: `10.66.0` on prod, `10.67.0` on
staging. The template writes it as `@WG_NET@`, and `provision.sh` fills it in, as it fills
`@PUBLIC_IF@` from the default route. `--render-firewall` takes `--wg-address <address>` (default
`10.66.0.1`), so the tests can render both hosts.

| Interface | Allowed in | Notes |
| --- | --- | --- |
| Public (the default route's) | TCP 80, TCP 443 (Caddy, this host's public API site only), UDP 51820 (this host's WireGuard) | WireGuard never answers unauthenticated packets. TCP 22 is open only during first provisioning and closed by `provision.sh --finalize`. |
| `wg0` | from `<wg>.2–9` (operator): TCP 22, TCP 443 · from `<wg>.10–99` (staff): TCP 443 · from `<wg>.200–209` (deploy): TCP 22 | sshd listens on `<wg>.1:22` only, once finalized |
| `lo` | everything | App containers publish only on `127.0.0.1` |
| Docker | Only Caddy reaches the outside, and it uses the host network, so host input rules apply. No other container publishes on a non-loopback address. | — |

- The two /24s differ, so one device can hold both tunnels at once. Neither host routes to the
  other's network.
- HTTP/3 is off (`protocols h1 h2`), so UDP 443 stays closed.
- Every site binds an explicit address (Caddy warns against mixing bound and unbound sites on one
  port).
- `net.ipv4.ip_nonlocal_bind = 1` lets Caddy bind the host's `WG_ADDRESS` even if it starts before
  `wg0` is up at boot.
- Django also sets `DATA_UPLOAD_MAX_MEMORY_SIZE = 524288` as a backstop, enforced on the API by
  `BodySizeLimitMiddleware` with the same `413 payload_too_large`.

## Edge (Caddy, `network_mode: host`)

Each host runs its own edge, Compose project `wassal-edge` from `/opt/wassal/edge/`. It serves one
API site and one admin site, both for the host's own environment. Both hosts use the same
`Caddyfile`. The edge container's two `env_file`s make the difference: `/etc/wassal/host.env`, then
`/etc/wassal/edge.env`.

| Site | Bind | TLS | Behaviour |
| --- | --- | --- | --- |
| `{$API_HOST}` | `{$PUBLIC_BIND_IP}` | `tls {$PUBLIC_TLS}`: Let's Encrypt (HTTP-01/TLS-ALPN) with that account email, or `internal` in the CI smoke test | `request_body max_size 512KiB` (524,288 bytes; Caddy reads `512KB` as 512,000), plus `reverse_proxy { request_buffers 1MB }`. The body is read before proxying, so the limit fires even when the upstream never reads it. Never `unlimited` (Caddy bug #8206, R6). `handle_errors 413` → JSON `payload_too_large` envelope. Security headers (below). `reverse_proxy 127.0.0.1:<the environment's API port>` with `lb_try_duration 30s` and `lb_try_interval 250ms` (connection failures are retried for every method while the upstream restarts, SC-004). JSON access log. |
| `{$ADMIN_HOST}` | `{$ADMIN_BIND_IP}` (the host's `WG_ADDRESS`) | `tls internal`: this host's own local CA, so each host has its own root. Staff who use both admins install both roots (runbook `private-network.md`). | Same headers plus the admin CSP. `reverse_proxy 127.0.0.1:<the environment's admin port>`. |
| `http://…` (public bind) | `{$PUBLIC_BIND_IP}:80` | — | 308 redirect to HTTPS (Caddy's automatic HTTPS) |

**Upstream ports:** the edge proxies to its environment's fixed loopback ports, `API_PORT` and
`ADMIN_PORT` in the release's sizing file `docker/env/<env>.env`: prod `8100` / `8101`, staging
`8200` / `8201`.

- The Caddyfile defines one snippet per environment and role, before the sites: `api-prod`
  (`import api 8100`), `api-staging` (`import api 8200`), `admin-prod` (`import admin 8101`) and
  `admin-staging` (`import admin 8201`).
- The API site imports `api-{$WASSAL_ENV}`, and the admin site `admin-{$WASSAL_ENV}`.
- An empty or unknown `WASSAL_ENV` names no snippet, so the Caddyfile doesn't load and the edge
  doesn't start (Caddy 2.11.7 reports "File to import not found"). It never falls back to the other
  environment's ports.
- A test keeps the snippet ports equal to the sizing files' ports
  ([ci-checks.md](./ci-checks.md#checks-implemented-as-tests-inside-pytest)).

**Starting the edge:** `provision.sh` starts it only once `edge.env` exists. It first checks that
`edge.env`'s `ADMIN_BIND_IP` equals `host.env`'s `WG_ADDRESS`, and stops with an error otherwise:
with `ip_nonlocal_bind`, an admin site bound to the other host's address would start and never
answer.

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
- **Access logs:** JSON, `roll_size 50MiB`, `roll_keep_for 336h`. The API site writes
  `/var/log/caddy/access.log`, and the admin site `/var/log/caddy/admin-access.log`.

**Admin CSP:** `default-src 'self'; script-src 'self' 'sha256-QE3U2xYF7B4J2ro1/9oxiKhaWCGW39gB7ocQ/xlD0bE=';
style-src 'self' 'unsafe-inline'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'self';
form-action 'self'; object-src 'none'`.

- The hash is django-celery-beat's inline script on the periodic-task form. The T047 spike found it
  (R5).
- `apps/accounts/tests/test_admin_csp.py` keeps the hash list equal to the inline scripts the admin
  pages render.

## Deploy interface (FR-030 – FR-034)

CI reaches each host only as that host's WireGuard peer and SSH user `deploy`: peer `deploy-staging`
on the staging host (`deploy@10.67.0.1`), peer `deploy-prod` on the prod host (`deploy@10.66.0.1`).

- On each host, `~deploy/.ssh/authorized_keys` has one key:
  `restrict,command="sudo /opt/wassal/bin/deploy --only <env>"`, where `<env>` is the host's
  `WASSAL_ENV`. The key can do nothing but deploy that host's environment.
- The script runs as root through a sudoers rule that allows only that one invocation.
- `deploy` isn't in the `docker` group, so an `authorized_keys` line that loses its forced command
  gives an unprivileged shell, not root.

**`/opt/wassal/bin/deploy --only <env>`**, with the arguments in `SSH_ORIGINAL_COMMAND` as
`<env> <tag> [rehearse-migrate-fail|rehearse-verify-fail]`. A third token is accepted only with
`--only staging`. It replaces the migrate command with one that exits 1, or makes verification
expect a wrong release, so the real failure and restore paths run against real containers (US4-4,
US4-5, SC-005) without a broken image ever being built.

| Step | Rule | On failure |
| --- | --- | --- |
| 1. Validate | `--only` equals the host's `WASSAL_ENV` (`/etc/wassal/host.env`), so even the operator's `sudo` can't deploy the other environment here (FR-001a). `env` equals `--only`. `tag` matches `^sha-[0-9a-f]{40}$` (staging) or `^v[0-9]+\.[0-9]+\.[0-9]+$` (prod). The image repository is fixed in the script and never taken from input. | exit 2, nothing touched |
| 2. Lock | `flock -w 900 /run/lock/wassal-deploy-<env>.lock`. A second deploy waits (FR-032). | exit 3 on timeout |
| 3. Pull | `docker pull ghcr.io/ahmedsaied94/wassal-backend:<tag>`. Read `RELEASE` from the image. Copy the release's `/app/deploy/` (its `compose.yml`, the `env/<env>.env` sizing file and `postgres/initdb/`, which `compose.yml` mounts) to `/var/lib/wassal/<env>/deploy/<tag>/`, so the stack definition deploys and rolls back with the code. Every later `docker compose` call uses `-f …/<tag>/compose.yml --env-file …/<tag>/env/<env>.env`. Then check the rendered stack against the host's allowlist (below). | exit 4 |
| 4. Migrate | `RELEASE_TAG=<tag> docker compose -p wassal-<env> --profile ops run --rm migrate`. Runs `migrate --noinput`, then `check --deploy`. | exit 5. Services were never restarted, so the previous release keeps serving (US4-4). |
| 5. Restart | `RELEASE_TAG=<tag> docker compose -p wassal-<env> up -d --no-deps --wait --wait-timeout 180 api admin worker beat` | go to 7 |
| 6. Verify | Within 120 s, polling every 2 s: `GET 127.0.0.1:<api port>/readyz` = 200 and `/healthz` `.release` = `RELEASE`, and the same for the admin port. These direct calls carry no `X-Forwarded-For`, so the rate limit doesn't count them ([api.md](./api.md#conventions-on-the-api-hostname)). | go to 7 |
| 7. Restore | Re-run step 5 with `release.previous`, wait for it to be healthy, then exit 6 | exit 7 if even the restore fails (the operator is alerted by the CI failure **and**, for prod, by the uptime check) |
| 8. Record | Move `release` to `release.previous`, write the new tag, print a JSON summary | — |
| 9. Prune | Delete the `deploy/<tag>/` copies and local images of every tag except `release` and `release.previous`. Only the environment's own tag form is pruned (`sha-…` on staging, `v…` on prod). On the staging host, this also removes the image a restore drill pulled. | Logged, not fatal |

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
  - The backup script passes the same sizing file, so it sees the same path.
- The JSON summary goes to stdout; progress and compose output go to stderr.

- Re-running a deploy of the tag that is already serving only re-verifies.
- **Rollback** (FR-033) is a normal deploy of the previous tag, from CI (re-run the old tag's
  release workflow) or by the operator on the prod host, over the prod WireGuard network as
  `ubuntu@10.66.0.1` (`sudo env SSH_ORIGINAL_COMMAND='prod v1.2.2' /opt/wassal/bin/deploy --only prod`).
  Migrations are never reversed.

## Backup job (FR-039, FR-039a)

`wassal-backup@prod.timer` runs on the prod host only, at `OnCalendar=*-*-* 03:00:00 Africa/Cairo`
with `Persistent=true` (a missed run fires at the next boot). The service runs
`/opt/wassal/bin/backup prod`. The script refuses (exit 2) an environment other than the host's
`WASSAL_ENV`. It reads the serving tag from `/var/lib/wassal/prod/release`, takes the deploy lock
(so a release never switches under a running backup), and runs `docker compose -p wassal-prod` with
that tag's `deploy/` copy and `--profile ops run --rm --no-deps -T backup`. That calls
`python manage.py backup_db` in the serving release's image. The steps:

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

`wassal-restore-drill@prod.timer` runs on the **staging host**, at
`OnCalendar=*-*-01 05:00:00 Africa/Cairo` with `Persistent=true`. That is two hours after that
night's backup on the prod host, so the newest backup is that night's. The time is configurable
through a systemd drop-in. The instance name is the environment whose backups are drilled, not the
host's. The service runs `/opt/wassal/bin/restore-drill prod` with `/etc/wassal/prod-drill.env` as
its environment.

The script refuses (exit 2) unless `host.env` says `WASSAL_ENV=staging`. The drill never runs on the
prod host, so it never competes with production for CPU, memory or disk (FR-001a). The steps:

1. Check that free disk on the Docker volume is at least `DRILL_MIN_FREE_GB` (default 5). If not,
   ping `/fail` and stop.
2. **Fetch** (outside access, no database): run the staging host's serving image (the tag in
   `/var/lib/wassal/staging/release`, already on the host) on the default bridge network with
   `prod-drill.env` and a fresh host directory `/var/lib/wassal/drill/` mounted, and call
   `python manage.py restore_drill fetch /drill`.
   - It downloads the newest *complete* backup (one with metadata) to `/drill/backup.dump` and its
     metadata to `/drill/backup.json`, and checks the `sha256`.
   - This container holds the read-only drill key, plus the same throwaway values as step 5 (with an
     unreachable `DATABASE_URL`), because `config.settings.prod` won't start without them. It gets
     none of staging's or production's application secrets.
   - With no staging release yet, the drill pings `/fail` ("no staging release to fetch with").
3. **Check image:** read `release` from `/var/lib/wassal/drill/backup.json`, as data. It must match
   `^[0-9a-f]{40}$`.
   - The check image is `ghcr.io/ahmedsaied94/wassal-backend:sha-<release>`: the production release
     that took the backup, which was serving production then. `docker pull` it. It exists, because
     every production tag is added to an existing `sha-` image
     ([ci-checks.md](./ci-checks.md#backend-releaseyml-production)).
   - Copy its `/app/deploy/compose.yml` out with `docker create` and `docker cp`, as deploy does,
     and take the `postgres:<tag>` image it names: production's database image for that release.
   - A bad `release`, a failed pull or a compose file with no postgres image pings `/fail`.
   - Not staging's image: staging usually runs newer code, with migrations production hasn't
     applied, so the migrations check would fail on a sound backup. Not production's serving tag
     either: the staging host can't read the prod host.
4. Create an internal network `wassal-drill` (`--internal`: no outside route, not attached to the
   staging stack's networks) and a volume `wassal-drill-pgdata`. Start the `postgres:<tag>` from
   step 3, named `wassal-drill-db`, on it, with `--memory 1g`, a random password for this run, and
   the volume.
5. **Check** (database only, no outside access): run the check image on `wassal-drill` only, with
   `/var/lib/wassal/drill/` mounted read-only, `DATABASE_URL` pointing at `wassal-drill-db`, and
   throwaway values for every other setting that `config.settings.prod` requires:
   - `WASSAL_ENV=prod` and a random `SECRET_KEY` of 64 characters for this run;
   - `CACHE_URL=locmem://` and `CELERY_BROKER_URL=memory://` (the check uses neither);
   - `API_HOST=drill.invalid` and `ADMIN_HOST=drill.invalid`;
   - inert `SENTRY_DSN=https://drill@drill.invalid/1` and `HC_PING_HEARTBEAT_URL=https://drill.invalid/`.
     The `.invalid` domain never resolves, and the network has no outside route anyway.

   It gets no storage key and none of staging's or production's application secrets.
   `python manage.py restore_drill check /drill`:
   - runs `pg_restore --no-owner --no-privileges --exit-on-error` (the drill database has no `wassal`
     role to grant to);
   - checks **restore** (exit 0), **migrations** (every migration in the code's graph is applied,
     counting a squash as applied once everything it replaces is, and no applied migration is unknown
     to the code; `django_migrations` is read over the drill's own connection), **row counts** (each
     table equals the metadata, within `DRILL_ROWCOUNT_TOLERANCE`, with no missing or extra tables)
     and **invariants** (every registered check passes);
   - prints the result line (data-model "Restore drill result") with the durations, as the last
     stdout line that starts with `{"started_at":` (the app's JSON logs share stdout). Its `release`
     is the check image's, so it equals the backup's `release`. It exits 1 after printing when the
     outcome is `fail`, and non-zero with no line when it can't finish.
6. The host script appends that line to `/var/lib/wassal/drill-results.jsonl` on the staging host
   and pings `HC_PING_DRILL_URL` with it, or `/fail` with a short reason if any step failed or
   printed no result.
7. `trap EXIT` always runs `docker rm -f wassal-drill-db`, `docker volume rm wassal-drill-pgdata`,
   `docker network rm wassal-drill` and `rm -rf /var/lib/wassal/drill/`, and removes the run's
   temporary files, the copied compose file included. The pulled check image stays. It is a `sha-`
   tag, so the next staging deploy prunes it, unless it is staging's `release` or
   `release.previous`.

Two releases share one drill, so later releases keep two rules: `restore_drill fetch` accepts the
metadata `schema_version` of every backup still in retention (56 days), and the `/drill` layout
(`backup.dump`, `backup.json`) stays readable by an older release's `check`.

The container that restores the backup can reach neither the internet nor the staging stack's
database, cache or networks, and the container that downloads it never touches a database.
Production data is on the staging host only while the drill runs (`/var/lib/wassal/drill/`, the
`wassal-drill-pgdata` volume, `wassal-drill-db`). It never reaches the staging environment and never
leaves the host (FR-040a).

## Host monitor (FR-038)

Each host runs its own `wassal-host-monitor.timer`, every 5 min, with its own
`/etc/wassal/host-monitor.env` and its own Healthchecks.io check (`host-monitor-prod`,
`host-monitor-staging`). `/opt/wassal/bin/host-monitor` reads `WASSAL_ENV` from `host.env` and runs
that host's checks:

| Check | Runs on | Fails when |
| --- | --- | --- |
| Disk | both | `/` or the Docker data root ≥ `DISK_ALERT_PERCENT` (80) |
| Certificates | both | The certificate served for this host's `API_HOST` (from its `edge.env`) expires in < `CERT_ALERT_DAYS` (14), or the one served for its `ADMIN_HOST` has already expired, or either can't be read. Both are read with `openssl s_client` against the site's bind address (`PUBLIC_BIND_IP`, `ADMIN_BIND_IP`) with SNI. |
| Queue backlog | both | `LLEN` of any of the 4 queues of this host's environment (`wassal-<env>-valkey-1`, database 1) > `QUEUE_BACKLOG_THRESHOLD` (100) for ≥ `QUEUE_BACKLOG_MINUTES` (10), tracked in `/var/lib/wassal/host-monitor/backlog.json` |
| Backup storage | prod | The latest dump's `size_bytes` (from `/var/lib/wassal/prod/backup/last-backup.json`) × 22 (14 daily + 8 weekly kept) ≥ `BACKUP_STORAGE_ALERT_BYTES` (8 GB, 80% of B2's free 10 GB, research R9). No file yet (no backup so far) passes. |

- The admin certificate comes from the host's local CA (`tls internal`). Caddy issues it for 12
  hours and renews it itself (measured with Caddy 2.11.7), so a 14-day threshold would always fail.
  Its check only catches a broken renewal. FR-038's 14-day alert is for public certificates.
- All checks pass → ping `HC_PING_HOST_MONITOR_URL`, with the checks that ran in the body.
- Any check fails → ping `/fail` with the failing checks listed.
- A missing ping URL, or a missing or unknown `WASSAL_ENV`, exits 2 without a ping.
  Healthchecks.io then alerts after its grace period, as it does when the monitor itself stops.

## Heartbeat (FR-007)

The `heartbeat` periodic task (data migration, every 5 min, queue `default`) runs
`common.tasks.heartbeat`:

- `bind=True`, `autoretry_for=(requests.RequestException,)`, `retry_backoff=True`, `max_retries=3`;
- HTTP timeout 10 s.

It pings `HC_PING_HEARTBEAT_URL`, and does nothing if that is empty (dev).

## Private-network administration (FR-023a)

Each host runs its own WireGuard server, with its own key, `wg0.conf`, peer registry
`/etc/wassal/wg-peers.tsv` and `/etc/wassal/wg-server.env`. `wg-peer` on a host manages that host's
peers only, and reads `WG_ADDRESS` and `WASSAL_ENV` from `host.env`. A device that needs both
networks gets one peer, and one config, on each host.

| Command | Effect |
| --- | --- |
| `sudo wg-peer add <name> <role>` | The role is `operator`, `staff`, or this host's deploy role (`deploy-prod` on prod, `deploy-staging` on staging); the other deploy role is refused. Generates a key pair on the host, assigns the next address in the role's range inside this host's /24 (operator `<wg>.2–9`, staff `<wg>.10–99`, deploy `<wg>.200–209`), appends to `wg-peers.tsv`, applies with `wg set` and `wg-quick save`, and prints the client config once, with this host's `WG_ENDPOINT` and `AllowedIPs = <WG_ADDRESS>/32`. The private key is never stored on the host afterwards. |
| `sudo wg-peer remove <name>` | `wg set wg0 peer <pub> remove`, then saves and marks the row removed. Access ends at once (US3-8). |
| `sudo wg-peer list` | Name, role, address, latest handshake |

CI's peer on each host is named after its role: `deploy-staging` on staging, `deploy-prod` on prod.

**Break-glass** (spec edge case): each VM's OCI serial console connection (R1) reaches it without
the network. `docs/runbooks/break-glass.md` covers re-keying that host's `wg0` and reopening SSH
temporarily.
