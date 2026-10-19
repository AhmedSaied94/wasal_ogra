# Quickstart: Backend Skeleton (B01)

How to set up, run and validate B01 end to end. Commands run from `backend/` unless noted. The full
command list is in [contracts/ci-checks.md](./contracts/ci-checks.md#commands-identical-locally-listed-in-claudemd-fr-044).
Host procedures are in `docs/runbooks/`, which is written in this feature.

## Prerequisites (developer machine)

| Tool | Version | Notes |
| --- | --- | --- |
| Docker Engine + Compose plugin | Engine ≥ 27, Compose ≥ 2.29 (the current plugin is v5.6) | `docker compose version` |
| uv | 0.13.1 (research R2) | `uv --version`. uv installs Python 3.13 itself from `.python-version`. Since uv 0.13 the default download is 3.15, so the pin matters. |
| git | any recent | — |
| PostgreSQL client tools | `pg_dump` and `pg_restore` ≥ 17 on `PATH` | The backup and drill tests call them against the dev database (PostgreSQL 17). Newer clients work with older servers, not the reverse. |
| Android emulator | optional | Only for US1-4 |

## Setup

```bash
cd backend
cp .env.example .env                     # dev values; every secret is a change-me placeholder
uv sync                                  # creates .venv from uv.lock
docker compose -f docker/compose.yml -f docker/compose.dev.yml up -d --wait   # runs migrations first
uv run manage.py create_staff ahmed --superuser && uv run manage.py staff_totp ahmed
```

- API: <http://localhost:8000/healthz>. Admin: <http://localhost:8001/admin/>, which needs a TOTP
  code from your authenticator app.
- With `--profile edge`, the dev Caddy also serves <https://localhost:8443> with `tls internal`.

## Automated validation (the same as CI)

```bash
uv run ruff check . && uv run ruff format --check .
uv run mypy .
uv run pytest --cov --cov-fail-under=80
uv run manage.py makemigrations --check --dry-run
uv run manage.py spectacular --file /tmp/openapi.yaml --validate --fail-on-warn \
  && diff -u ../contracts/openapi.yaml /tmp/openapi.yaml
```

Expected: every step exits 0. pytest includes:

- the settings guards, the UUIDv7 system check and the error-envelope tests;
- health with dead dependencies, throttling, logging and Sentry scrubbing;
- admin OTP and lockout;
- backup and drill services, the deploy-script logic;
- the schemathesis contract suite.

**Gates fail when they should** (try each on a scratch branch):

| Change | Expected failure |
| --- | --- |
| Add a model in `apps/common` without `UUIDv7Model` | `common.E001` in pytest |
| Add a field without a migration | `makemigrations --check` |
| Change a health response without regenerating | the contract diff |
| Delete a test to drop coverage below 80% | `--cov-fail-under` |
| Commit `AKIA…`-style or private-key text | `secrets.yml` (gitleaks) |

## Local validation scenarios (US1)

| # | Do | Expect |
| --- | --- | --- |
| 1 | `curl -s localhost:8000/readyz` | `200`, all three checks `pass` |
| 2 | `docker compose … stop postgres`, then `curl -s -w '%{http_code}' localhost:8000/readyz` and `/healthz` | readyz `503` `not_ready` with `database: fail` in < 5 s. healthz still `200`. |
| 3 | `docker compose … start postgres`, wait 5 s, `curl localhost:8000/readyz` | `200` again, with no restart of `api` (`docker compose ps` shows the same container age) |
| 4 | In the emulator's browser open `http://10.0.2.2:8000/healthz` | `{"status":"ok","release":"dev"}` |
| 5 | Remove `SECRET_KEY` from `.env` (or leave it empty), then `docker compose … up -d api && docker compose … logs api` | The container exits with `SECRET_KEY is required` and no value printed |
| 6 | `docker compose … run --rm -e DJANGO_SETTINGS_MODULE=config.settings.prod -e WASSAL_ENV=prod -e DJANGO_DEBUG=false api python manage.py check` with the dev `.env` | Refuses: `SECRET_KEY is a placeholder, which only dev accepts`. (Without `-e DJANGO_DEBUG=false` it refuses earlier, on `DJANGO_DEBUG`.) |
| 7 | `curl -s localhost:8000/nope`, `curl -s -X DELETE localhost:8000/healthz` | `404` `not_found` and `405` `method_not_allowed` envelopes |
| 8 | `for i in $(seq 130); do curl -s -o /dev/null -w '%{http_code}\n' localhost:8000/healthz; done \| sort \| uniq -c` | About 120 `200`s, then `429`s with `Retry-After` |

## Staging and production: first-time setup (operator)

Each environment has its own VM, and each VM serves only its own environment. Both VMs exist
(created 2026-10-19):

| | prod VM | staging VM |
| --- | --- | --- |
| Shape | `VM.Standard.A1.Flex`, 1 OCPU / 6 GB | `VM.Standard.A1.Flex`, 1 OCPU / 6 GB |
| Boot volume | 100 GB | 47 GB |
| Reserved public IP | `193.122.74.125` | `141.147.129.92` |
| VCN private IP | `10.0.0.28` | `10.1.0.216` (interface `enp0s6`) |
| WireGuard `wg0` | `10.66.0.1/24` | `10.67.0.1/24` |
| API hostname | `api.193-122-74-125.sslip.io` | `staging-api.141-147-129-92.sslip.io` |
| Admin hostname | `admin.10-66-0-1.sslip.io` | `staging-admin.10-67-0-1.sslip.io` |
| Timers | `wassal-backup@prod`, `wassal-host-monitor` | `wassal-restore-drill@prod` (drills prod's backups), `wassal-host-monitor` |

Together they use the whole Always Free A1 allowance (2 OCPU / 12 GB) and 147 GB of the 200 GB of
block storage, which leaves 53 GB for the 47 GB break-glass rescue boot volume.

Follow `docs/runbooks/provision-host.md`. Steps 2–7 run once on each VM. The outline:

1. Create the VMs in the existing tenancy (home region `me-jeddah-1`):
   - Reserve both public IPs first.
   - Create the two VMs above, each in its own VCN, and nothing outside Always Free. Attach each
     reserved IP to its own VM's VNIC.
   - Open TCP 22, 80, 443 and UDP 51820 in each VCN's security list.
   - On "Out of host capacity", retry daily. Jeddah has one availability domain, so there is nothing
     to rotate.
   - Record the latency baseline from Egypt once production serves (research R1).
2. Run `sudo passwd ubuntu` and keep the password in your password manager. It is only for the serial
   console. Then test the VM's serial console once from Cloud Shell (break-glass, research R13).
3. `scp -r backend/docker ubuntu@<ip>:wassal-docker`, then
   `sudo ./wassal-docker/host/provision.sh --env <env> --public-ip <ip>`:
   - prod: `--env prod --public-ip 193.122.74.125`;
   - staging: `--env staging --public-ip 141.147.129.92`.

   It records the environment in `/etc/wassal/host.env` (`WASSAL_ENV`, `WG_ADDRESS`) and refuses a
   different `--env` later. It installs Docker, WireGuard on the host's own address, the iptables
   rules (keeping Oracle's), sshd on `wg0` only, the `deploy` user, `/opt/wassal`, and the systemd
   units and timers for that host.
4. Fill in the host's `/etc/wassal/*.env` from
   [contracts/environment.md](./contracts/environment.md): its own environment's files, plus
   `prod-backup.env` on prod and `prod-drill.env` on staging. Then re-run
   `sudo ./wassal-docker/host/provision.sh`. It starts the edge once `edge.env` exists.
5. `sudo wg-peer add <your-device> operator` on that host. Import the config and connect. A laptop
   can keep both hosts' tunnels up at once; a phone runs one at a time.
6. `sudo ./wassal-docker/host/provision.sh --finalize` (SSH now listens on the host's WireGuard
   address only), then remove TCP 22 from that VM's security list.
7. Add the host's deploy peer and key: `deploy-prod` on prod, `deploy-staging` on staging, each
   limited to its own environment. Store them as the matching GitHub Environment's secrets. CI then
   deploys with `ssh deploy@10.67.0.1 staging <tag>` and `ssh deploy@10.66.0.1 prod <tag>`.
8. Set up the outside services, following `docs/runbooks/monitoring-setup.md`:
   - **Backblaze B2** (research R9):
     - Turn on MFA (the terms require it).
     - Set USD 0 caps on storage and on Class A, B and C transactions, keep the alert emails on, and
       leave Event Notifications off.
     - Create an admin application key and keep it in your password manager. It never goes on the
       host.
     - Run `uv run tools/b2_setup.py` from `backend/` on your machine. It creates the daily and weekly
       buckets with Object Lock, governance retention and lifecycle rules, creates the backup and
       drill keys, checks their capabilities, and prints the lines for `prod-backup.env` (prod
       host) and `prod-drill.env` (staging host).
     - Copy the endpoint from a bucket's Endpoint field, and note the account's region for backend
       §15.
   - **Healthchecks.io:** 6 checks, including one host monitor per host.
   - **UptimeRobot:** 1 monitor. Save a dated copy of its terms.
   - **Sentry:** done on 2026-10-19: organization `saied-store-div` (US region), project
     `wassal-backend`. Put its DSN in `/etc/wassal/staging.env` on staging and
     `/etc/wassal/prod.env` on prod.
   - **GitHub:** repository push protection on.
9. Merge to `master`, which deploys staging. Tag `v0.1.0`, which deploys production.

Time each host's run, from step 1 to serving its environment's `/healthz`. The 4 h RTO (SC-009)
applies per host: production's time plus the drill's restore duration must fit it, and so must
staging's time alone.

## Production validation scenarios (US3–US6)

Run each scenario on the host in the Host column. "each" means once on each host: those scenarios
check per-host configuration, while the others test code or scripts that are the same on both
hosts. `<ip>` is that host's reserved public IP (in hostnames, with dashes).

| # | Host | Do | Expect | Covers |
| --- | --- | --- | --- | --- |
| 1 | prod | From a phone on mobile data: `curl -sv https://api.<ip>.sslip.io/healthz`, 100 times | `200` every time, a valid Let's Encrypt chain, HSTS, each request < 1 s | US3-1, SC-002 |
| 2 | prod | `curl -sI http://api.<ip>.sslip.io/healthz` | `308` to https | US3-2 |
| 3 | each | From outside: `nmap -Pn -p- <ip>` and `nmap -sU -p 51820 <ip>` | Only 80 and 443 open. 51820 `open\|filtered` (no answer). | US3-7, SC-011 |
| 4 | each | Off WireGuard: open `https://admin.10-66-0-1.sslip.io` (prod) and `https://staging-admin.10-67-0-1.sslip.io` (staging) | No connection | US3-7 |
| 5 | prod | On WireGuard as staff: open the admin, sign in with the password only | The OTP form, no admin pages until a valid code | US3-6 |
| 6 | prod | Enter a wrong password 5 times | The 6th attempt is refused for 15 min, even with the right password | FR-022 |
| 7 | prod | `sudo wg-peer remove <staff-device>`, then retry from that device | No connection at once | US3-8 |
| 8 | prod | `https://api…/admin/` and `https://admin…/v1/` | `404` both | US3-3 |
| 9 | prod | `curl -s -X POST --data-binary @600k.bin https://api…/v1/` | `413` `payload_too_large` envelope | US3-4 |
| 10 | staging | Merge a trivial change, then watch the `deploy-staging` job | `https://staging-api…/healthz` reports the new `release` within 15 min | US4-1, SC-004 |
| 11 | staging | Run `backend.yml` by hand with `rehearse: migrate-fail`, while polling production's `/healthz` every second | The staging deploy fails at migrate, the previous release keeps serving, and the failure email arrives within 5 min. Production answers throughout. | US4-4, SC-005, US3-5 |
| 12 | staging | The same with `rehearse: verify-fail` | The new release is started, fails verification, and the previous one is restored | US4-5 |
| 13 | prod | Push tag `v0.1.1` on a `master` commit, and separately a tag on a branch commit | The first deploys production. The second fails at verify without deploying. | US4-2, US4-3 |
| 14 | prod | Re-run the release workflow of the previous tag | Production serves it again within 10 min | FR-033, SC-006 |
| 15 | staging (10–12), prod (13–14) | During 10–14, poll the deployed host's `/healthz` every second from outside | Gaps ≤ 30 s per deploy | SC-004 |
| 16 | prod | `sudo docker exec wassal-prod-api-1 python manage.py sentry_test`, then `sudo docker exec wassal-prod-worker-1 python manage.py sentry_test --task` | Two Sentry issues tagged `environment=prod`, `release=<sha>`, with no IP, cookies or headers | US5-1, US5-2, SC-007 |
| 17 | prod | `sudo docker stop wassal-prod-api-1` | Uptime alert email ≤ 10 min. Restore with `docker start`. | US5-3, SC-008 |
| 18 | prod | `sudo docker stop wassal-prod-beat-1` | Healthchecks `heartbeat-prod` alert ≤ 20 min | US5-4, SC-008 |
| 19 | prod | `sudo systemctl start wassal-backup@prod` | A new `prod/YYYY/MM/DD/prod-…{.dump,.json}` pair in the daily bucket, `/var/lib/wassal/prod/backup/last-backup.json` updated, and `backup-prod` green | US6-1 |
| 20 | prod, then staging | With the prod host's backup key: `aws s3api list-object-versions --bucket <daily bucket> --endpoint-url …`, then `aws s3api delete-object --bucket <daily bucket> --key <key> --version-id <id> --endpoint-url …` (version id from the B2 console) | Both refused (`AccessDenied`). Then upload a small file under that same key with the backup key: it succeeds, and the drill key's `list-object-versions` (on the staging host) still shows the original version. | US6-8, FR-039a |
| 21 | staging | `sudo systemctl start wassal-restore-drill@prod` | One `pass` line in `drill-results.jsonl` with durations, and no `wassal-drill-*` container, volume or network, or `/var/lib/wassal/drill/`, left (`docker ps -a`, `docker volume ls`, `docker network ls`), so no prod data stays on the staging host | US6-3, SC-009 |
| 22 | each | `sudo reboot`, then poll that host's `/healthz` | Serving again within 5 min, no manual step | SC-010 |
| 23 | each | `cat /etc/wassal/host.env`, `sudo docker volume ls`, `sudo docker network ls`, `grep -H ENV_FILE /var/lib/wassal/*/deploy/*/env/*.env`, then `sudo ./wassal-docker/host/provision.sh --env <the other environment>` | `host.env` names the host's own environment. Only that environment's `wassal-<env>_*` volumes and networks exist, besides the edge's, and its sizing files point at its own `/etc/wassal/<env>.env` and `<env>-db.env`. The `--env` change is refused. | US3-5 |
| 24 | staging, then your machine | About 17 days after the first backup: list the daily bucket with the drill key, then `uv run tools/b2_setup.py --daily-bucket <daily> --weekly-bucket <weekly> --check` on your machine | The first day's pair is gone, and the check passes | US6-1 |

## Monthly operating routine (operator)

These keep the free accounts and their guarantees alive (research R1, R9, R11):

- Check that the 1st-of-month drill line in the staging host's `drill-results.jsonl` passed.
- Sign in to the OCI console. Oracle may suspend tenancies left idle for 30 days.
- Sign in to Healthchecks.io. It deletes accounts with no login for a year.
- In the B2 console, check that the caps are still USD 0 and that storage is well under 10 GB.
  Then run `uv run tools/b2_setup.py --daily-bucket <daily> --weekly-bucket <weekly> --check` if anything in the console changed.
- Check that no service shows a charge (SC-013).

Item 16 uses a management command, so no test endpoint is ever exposed. Items 11–12 use the deploy
script's rehearsal mode, which only the staging deploy key can request
([operations.md](./contracts/operations.md#deploy-interface-fr-030--fr-034)).
