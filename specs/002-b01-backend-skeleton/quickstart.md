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

## Production: first-time setup (operator)

Follow `docs/runbooks/provision-host.md`. Its outline:

1. Create the VM in the existing tenancy (home region `me-jeddah-1`):
   - Reserve a public IP first.
   - Create **one** `VM.Standard.A1.Flex` with 2 OCPU, 12 GB and a 100 GB boot volume, and nothing
     outside Always Free. Attach the reserved IP to its VNIC.
   - Open TCP 22, 80, 443 and UDP 51820 in the security list.
   - On "Out of host capacity", retry daily. Jeddah has one availability domain, so there is nothing
     to rotate.
   - Record the latency baseline from Egypt once the VM serves (research R1).
2. Run `sudo passwd ubuntu` and keep the password in your password manager. It is only for the serial
   console. Then test the serial console once from Cloud Shell (break-glass, research R13).
3. `scp -r backend/docker ubuntu@<ip>:wassal-docker` then `sudo ./wassal-docker/host/provision.sh --public-ip <ip>`. It installs Docker,
   WireGuard, the iptables rules (keeping Oracle's), sshd on `wg0` only, the `deploy` user, `/opt/wassal`, and the systemd units
   and timers.
4. Fill in `/etc/wassal/*.env` from [contracts/environment.md](./contracts/environment.md), then re-run
   `sudo ./wassal-docker/host/provision.sh`. It starts the edge once `edge.env` exists.
5. `sudo wg-peer add <your-device> operator`. Import the config and connect.
6. `sudo ./host/provision.sh --finalize` (SSH now listens on `10.66.0.1` only), then remove TCP 22
   from the security list.
7. Add the `deploy-staging` and `deploy-prod` peers and keys, and store them as GitHub Environment
   secrets.
8. Set up the outside services, following `docs/runbooks/monitoring-setup.md`:
   - **Backblaze B2** (research R9):
     - Turn on MFA (the terms require it).
     - Set USD 0 caps on storage and on Class A, B and C transactions, keep the alert emails on, and
       leave Event Notifications off.
     - Create an admin application key and keep it in your password manager. It never goes on the
       host.
     - Run `uv run tools/b2_setup.py` from `backend/` on your machine. It creates the daily and weekly
       buckets with Object Lock, governance retention and lifecycle rules, creates the backup and
       drill keys, checks their capabilities, and prints the lines for `prod-backup.env` and
       `prod-drill.env`.
     - Copy the endpoint from a bucket's Endpoint field, and note the account's region for backend
       §15.
   - **Healthchecks.io:** 5 checks.
   - **UptimeRobot:** 1 monitor. Save a dated copy of its terms.
   - **Sentry:** done on 2026-10-19: organization `saied-store-div` (US region), project
     `wassal-backend`. Put its DSN in `/etc/wassal/{staging,prod}.env`.
   - **GitHub:** repository push protection on.
9. Merge to `master`, which deploys staging. Tag `v0.1.0`, which deploys production.

Time the run from step 1 to a serving production. Together with the drill's restore duration, it
must fit the 4 h RTO (SC-009).

## Production validation scenarios (US3–US6)

| # | Do | Expect | Covers |
| --- | --- | --- | --- |
| 1 | From a phone on mobile data: `curl -sv https://api.<ip>.sslip.io/healthz`, 100 times | `200` every time, a valid Let's Encrypt chain, HSTS, each request < 1 s | US3-1, SC-002 |
| 2 | `curl -sI http://api.<ip>.sslip.io/healthz` | `308` to https | US3-2 |
| 3 | From outside: `nmap -Pn -p- <ip>` and `nmap -sU -p 51820 <ip>` | Only 80 and 443 open. 51820 `open\|filtered` (no answer). | US3-7, SC-011 |
| 4 | Off WireGuard: open `https://admin.10-66-0-1.sslip.io` | No connection | US3-7 |
| 5 | On WireGuard as staff: open the admin, sign in with the password only | The OTP form, no admin pages until a valid code | US3-6 |
| 6 | Enter a wrong password 5 times | The 6th attempt is refused for 15 min, even with the right password | FR-022 |
| 7 | `sudo wg-peer remove <staff-device>`, then retry from that device | No connection at once | US3-8 |
| 8 | `https://api…/admin/` and `https://admin…/v1/` | `404` both | US3-3 |
| 9 | `curl -s -X POST --data-binary @600k.bin https://api…/v1/` | `413` `payload_too_large` envelope | US3-4 |
| 10 | Merge a trivial change, then watch the `deploy-staging` job | `https://staging-api…/healthz` reports the new `release` within 15 min | US4-1, SC-004 |
| 11 | Run `backend.yml` by hand with `rehearse: migrate-fail`, while polling production's `/healthz` every second | The staging deploy fails at migrate, the previous release keeps serving, and the failure email arrives within 5 min. Production answers throughout. | US4-4, SC-005, US3-5 |
| 12 | The same with `rehearse: verify-fail` | The new release is started, fails verification, and the previous one is restored | US4-5 |
| 13 | Push tag `v0.1.1` on a `master` commit, and separately a tag on a branch commit | The first deploys production. The second fails at verify without deploying. | US4-2, US4-3 |
| 14 | Re-run the release workflow of the previous tag | Production serves it again within 10 min | FR-033, SC-006 |
| 15 | During 10–14, poll `/healthz` every second from outside | Gaps ≤ 30 s per deploy | SC-004 |
| 16 | `sudo docker exec wassal-prod-api-1 python manage.py sentry_test`, then `sudo docker exec wassal-prod-worker-1 python manage.py sentry_test --task` | Two Sentry issues tagged `environment=prod`, `release=<sha>`, with no IP, cookies or headers | US5-1, US5-2, SC-007 |
| 17 | `sudo docker stop wassal-prod-api-1` | Uptime alert email ≤ 10 min. Restore with `docker start`. | US5-3, SC-008 |
| 18 | `sudo docker stop wassal-prod-beat-1` | Healthchecks `heartbeat-prod` alert ≤ 20 min | US5-4, SC-008 |
| 19 | `sudo systemctl start wassal-backup@prod` | A new `prod/YYYY/MM/DD/prod-…{.dump,.json}` pair in the daily bucket, `/var/lib/wassal/prod/backup/last-backup.json` updated, and `backup-prod` green | US6-1 |
| 20 | With the host's backup key: `aws s3api list-object-versions --bucket <daily bucket> --endpoint-url …`, then `aws s3api delete-object --bucket <daily bucket> --key <key> --version-id <id> --endpoint-url …` (version id from the B2 console) | Both refused (`AccessDenied`). Then upload a small file under that same key with the backup key: it succeeds, and the drill key's `list-object-versions` still shows the original version. | US6-8, FR-039a |
| 21 | `sudo systemctl start wassal-restore-drill@prod` | One `pass` line in `drill-results.jsonl` with durations, and no `wassal-drill-*` container, volume or network, or `/var/lib/wassal/drill/`, left (`docker ps -a`, `docker volume ls`, `docker network ls`) | US6-3, SC-009 |
| 22 | `sudo reboot`, then poll `/healthz` | Serving again within 5 min, no manual step | SC-010 |
| 23 | `sudo docker volume ls`, `sudo docker network ls`, then `grep -H ENV_FILE /var/lib/wassal/{staging,prod}/deploy/*/env/*.env` | Separate `wassal-staging_*` and `wassal-prod_*` volumes and networks. Each environment's sizing file points at its own `/etc/wassal/<env>.env` and `<env>-db.env`. | US3-5 |
| 24 | About 17 days after the first backup: list the daily bucket with the drill key, then `uv run tools/b2_setup.py --daily-bucket <daily> --weekly-bucket <weekly> --check` on your machine | The first day's pair is gone, and the check passes | US6-1 |

## Monthly operating routine (operator)

These keep the free accounts and their guarantees alive (research R1, R9, R11):

- Check that the 1st-of-month drill line in `drill-results.jsonl` passed.
- Sign in to the OCI console. Oracle may suspend tenancies left idle for 30 days.
- Sign in to Healthchecks.io. It deletes accounts with no login for a year.
- In the B2 console, check that the caps are still USD 0 and that storage is well under 10 GB.
  Then run `uv run tools/b2_setup.py --daily-bucket <daily> --weekly-bucket <weekly> --check` if anything in the console changed.
- Check that no service shows a charge (SC-013).

Item 16 uses a management command, so no test endpoint is ever exposed. Items 11–12 use the deploy
script's rehearsal mode, which only the staging deploy key can request
([operations.md](./contracts/operations.md#deploy-interface-fr-030--fr-034)).
