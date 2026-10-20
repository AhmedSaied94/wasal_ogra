# Monitoring setup

The operator is emailed when production is down, a heartbeat stops, a backup or the monthly drill
fails, either VM runs short of disk or stops reporting, a certificate nears expiry, a queue backs
up, or a deploy fails (FR-038). Every service here is free, and its terms allow commercial use
(research R11, checked 2026-10-18). Each one runs outside the VM it watches, except the host
monitors, which ping out.

Put every ping URL and DSN straight into its `/etc/wassal/*.env` file, on the VM the table names
(mode `0400`, provision-host.md step 4). They are secrets: anyone holding a ping URL can fake a
green check.

| File | VM | What this page puts in it |
| --- | --- | --- |
| `prod.env` | prod | `SENTRY_DSN`, and `heartbeat-prod`'s URL as `HC_PING_HEARTBEAT_URL` |
| `staging.env` | staging | `SENTRY_DSN`, and `heartbeat-staging`'s URL as `HC_PING_HEARTBEAT_URL` |
| `prod-backup.env` | prod | The B2 backup key lines, and `backup-prod`'s URL as `HC_PING_BACKUP_URL` |
| `prod-drill.env` | staging | The B2 drill key lines, and `restore-drill-prod`'s URL as `HC_PING_DRILL_URL` |
| `host-monitor.env` | each | That VM's own host-monitor URL as `HC_PING_HOST_MONITOR_URL`, and the thresholds |

No VM holds both B2 keys, and the B2 admin key is on neither.

## Healthchecks.io (dead-man's switches)

1. Create a **Hobbyist** account (no card). Use the email you want alerts on.
2. Set the project time zone to `Africa/Cairo`.
3. Create the seven checks:

| Check | Schedule | Grace | Ping URL goes into | Pinged by |
| --- | --- | --- | --- | --- |
| `heartbeat-prod` | period 5 min | 10 min | `HC_PING_HEARTBEAT_URL` in `/etc/wassal/prod.env`, prod VM | the `heartbeat` task, every 5 min, through beat, the broker and a worker (FR-006) |
| `heartbeat-staging` | period 5 min | 10 min | `HC_PING_HEARTBEAT_URL` in `/etc/wassal/staging.env`, staging VM | the same, on staging |
| `backup-prod` | period 1 day | 2 h | `HC_PING_BACKUP_URL` in `/etc/wassal/prod-backup.env`, prod VM | the nightly backup, 03:00 Cairo, or `/fail` with the reason |
| `backup-staging` | period 1 day | 2 h | `HC_PING_BACKUP_URL` in `/etc/wassal/staging-backup.env`, staging VM | staging's own nightly backup, 03:00 Cairo, or `/fail` (B04 research R8) |
| `restore-drill-prod` | period 30 days | 5 days | `HC_PING_DRILL_URL` in `/etc/wassal/prod-drill.env`, staging VM | the drill of production's backups, 05:00 Cairo on the 1st, or `/fail` |
| `host-monitor-prod` | period 5 min | 10 min | `HC_PING_HOST_MONITOR_URL` in `/etc/wassal/host-monitor.env`, prod VM | the prod VM's `wassal-host-monitor.timer`, or `/fail` listing the failing checks |
| `host-monitor-staging` | period 5 min | 10 min | `HC_PING_HOST_MONITOR_URL` in `/etc/wassal/host-monitor.env`, staging VM | the staging VM's `wassal-host-monitor.timer`, or `/fail` |

A host monitor's missed ping also covers a VM that Oracle stopped (break-glass.md "Instance
stopped by Oracle"). For the staging VM, it is the only alert for that.

Each VM's `/etc/wassal/host-monitor.env` holds its own ping URL and the thresholds. Each VM backs
up its own environment, so each checks its own backup storage. Each environment's buckets are in
a B2 account of their own (production's and staging's), each with its own free 10 GB, so both VMs
use the same 8 GB alert:

```text
HC_PING_HOST_MONITOR_URL=https://hc-ping.com/<uuid of host-monitor-prod or host-monitor-staging>
DISK_ALERT_PERCENT=80
CERT_ALERT_DAYS=14
QUEUE_BACKLOG_THRESHOLD=100
QUEUE_BACKLOG_MINUTES=10
BACKUP_STORAGE_ALERT_BYTES=8000000000
```

Each host monitor reads its environment from `/etc/wassal/host.env` and checks its own VM:

| Check | prod VM | staging VM |
| --- | --- | --- |
| Disk, `/` and the Docker data root | yes | yes, including the drill's space |
| Certificates: `API_HOST` at `PUBLIC_BIND_IP:443` has more than 14 days left, and `ADMIN_HOST` at `ADMIN_BIND_IP:443` hasn't expired | its own, from its `edge.env` | its own, from its `edge.env` |
| Queue backlog, in `wassal-<env>-valkey-1` | production's queues | staging's queues |
| Backup storage (latest dump × 22 under `BACKUP_STORAGE_ALERT_BYTES`) | production's backups | staging's own backups |
| Success ping body | `ok: disk, certificates, queues, backup storage` | the same |

- The admin certificate comes from the VM's own CA and lasts 12 hours, so it is only checked for
  having expired, which catches a broken renewal.
- If `edge.env` lacks any of `API_HOST`, `ADMIN_HOST`, `PUBLIC_BIND_IP` and `ADMIN_BIND_IP`, the
  certificate check fails (`certificates: … is missing from edge.env`).
- A failure pings `/fail` with one line per failing check, so the alert email says what broke.
- A missing ping URL, or a missing or broken `host.env`, exits 2 without a ping. Healthchecks.io
  then alerts after its grace period, as when the VM is down.

A host monitor stays skipped until its file exists. Once it exists, it fails until its VM's
environment is deployed, because it reads that environment's queues. So create the file on each VM
once its environment serves: the staging VM after the first merge, the prod VM after the first
tag.

Test it on that VM, then check the Healthchecks dashboard:

```bash
sudo systemctl start wassal-host-monitor.service && journalctl -u wassal-host-monitor -n 5
```

## UptimeRobot (production down)

1. Create a **Free** account.
2. Add an **HTTP(s)** monitor on `https://api.193-122-74-125.sslip.io/healthz`, with a 5-minute
   interval and an email alert. A down production sends that email within 10 minutes (SC-008).
   That is the only monitor: staging needs none, because `host-monitor-staging` notices a stopped
   staging VM.
3. **Save a dated copy of the terms.** The free plan allows commercial use only since 2026-05-26;
   before that it was non-commercial only. Save the terms page as PDF in your password manager or
   your documents, named with the date (R11). Check again if UptimeRobot announces a change.

Optional second opinion: a **Sentry uptime monitor** on the same URL (one is free). It opens an issue
only after 3 failures, so it can't replace UptimeRobot.

## Sentry (errors)

1. The organization is `saied-store-div` (<https://saied-store-div.sentry.io>), in the **US** data
   region. The region can't be changed later. The owner kept this existing organization on
   2026-10-19 instead of creating one in the EU region, as first planned: the server sends no
   personal data (step 5), so Sentry holds only scrubbed errors and traces.
2. Stay on the **Developer** plan: 1 user, 5k errors a month, with over-quota data dropped, never
   billed.
3. The Django project `wassal-backend` exists (created 2026-10-19). Copy its DSN from Project
   Settings → Client Keys (DSN) into `SENTRY_DSN` in `/etc/wassal/staging.env` on the staging VM
   and `/etc/wassal/prod.env` on the prod VM. Events carry `environment` (`staging` or `prod`) and
   `release` (the commit), so one project is enough. Leave `SENTRY_DSN` empty in `backend/.env`,
   so dev runs don't use the quota.
4. Leave the default alert, an email on every new issue.
5. The server already scrubs what it sends: no IP addresses, cookies, headers, request bodies or
   local variables (research R7). Don't turn on "send default PII" in any project setting. Sentry
   still derives a country from the address an event arrives from, which is the server's, never a
   player's. To drop that too, turn on **Prevent Storing of IP Addresses** under Project Settings →
   Security & Privacy.

Test it after the first production deploy, on the prod VM (quickstart scenario 16):

```bash
sudo docker exec wassal-prod-api-1 python manage.py sentry_test
sudo docker exec wassal-prod-worker-1 python manage.py sentry_test --task
```

Two issues appear, tagged `environment=prod` and with the release. Open one and check that it has
no IP address, cookies or headers.

## Backblaze B2 (backups)

The nightly backup, on the prod VM, stores production's dumps in B2. The monthly drill, on the
staging VM, reads them back (research R9). Since B04, the staging VM also backs up its own
database, where authors work, into its own pair of buckets with its own write-only key (B04
research R8), in a **second B2 account**, so each environment has its own free 10 GB. Do steps
1–7 once, in production's account, before the first production deploy (quickstart step 8), and
step 8 when B04 merges.

1. Create the account and **turn on MFA** first: the terms require it.
2. **Note the account's region**, shown at sign-up and in each bucket's Endpoint field
   (`s3.<region>.backblazeb2.com`). It can't be changed later. From B02 on, the backups hold player
   data, so record the region in research R9 "Data location", next to the Jeddah VMs, for the
   PDPL review (backend §15, §22.9).
3. Under **Caps & Alerts**, set a **USD 0** daily cap on storage and on Class A, B and C
   transactions (and on downloads, if offered), and keep the alert emails on. At a USD 0 cap, an
   upload past the free 10 GB fails, so the backup pings `/fail` instead of running up a bill.
4. Leave **Event Notifications** off. They are billed and can't be capped.
5. Create an **admin application key** with all capabilities, on all buckets. Keep it in your
   password manager only. It never goes on either VM, and only it can delete a backup before its
   lock ends.
6. On your machine, from `backend/`, run the setup with two bucket names of your choice (B2 names are
   global):

   ```bash
   uv run tools/b2_setup.py --daily-bucket wassal-prod-daily-<suffix> --weekly-bucket wassal-prod-weekly-<suffix>
   ```

   It asks for the admin key (not echoed) and then:
   - creates both buckets private, with Object Lock on and their lifecycle rules (hide after 14 or
     56 days, delete a day later);
   - sets governance default retention, 14 and 56 days;
   - creates the backup key (`writeFiles` only) and the drill key (`listBuckets`, `listFiles`,
     `readFiles`), both limited to the two buckets and `prod/`;
   - signs in with each new key, checks the rights B2 reports, and prints the lines for
     `/etc/wassal/prod-backup.env` and `/etc/wassal/prod-drill.env`.

   The application keys are shown **only once**:
   - Copy both blocks into your password manager.
   - Then create each file with mode `0400` (provision-host.md step 4): `prod-backup.env` on the
     prod VM, `prod-drill.env` on the staging VM.
   - Paste the `backup-prod` and `restore-drill-prod` ping URLs in place of the placeholders.

   The endpoint and region lines come from B2's answer, so they match the account.
7. On each VM, re-run `sudo ./wassal-docker/host/provision.sh` (or `sudo systemctl daemon-reload`).
   The backup and drill timers stay skipped until their env files exist.
8. **Staging's backups, in staging's own B2 account.** Repeat steps 1–5 in that account: MFA, its
   region (record it in research R9 "Data location" too), the USD 0 caps, Event Notifications
   off, and its own admin key, kept in your password manager only. Then run the setup with that
   account's admin key, `--env staging` and staging's bucket names (`wassal-staging-backup-daily`
   and `wassal-staging-backup-weekly`, with a suffix if B2 says a name is taken):

   ```bash
   uv run tools/b2_setup.py --env staging --daily-bucket wassal-staging-backup-daily --weekly-bucket wassal-staging-backup-weekly
   ```

   It does what step 6 does with the `staging/` prefix, but creates only the backup key,
   `wassal-staging-backup` (`writeFiles` only): staging's backups are never drilled, so there is no
   read key. It prints the lines for `/etc/wassal/staging-backup.env`:
   - Copy them into your password manager, then create the file on the staging VM with mode `0400`.
   - Paste the `backup-staging` ping URL in place of the placeholder.
   - Never reuse production's backup key or the drill key here.

   The `B2_S3_ENDPOINT` and `B2_REGION` lines come from staging's account, so they can differ from
   production's.

After the first production deploy, test both (quickstart scenarios 19 and 21). On the prod VM:

```bash
sudo systemctl start wassal-backup@prod && journalctl -u wassal-backup@prod -n 20
```

Then, once that backup has finished and staging has a release, on the staging VM:

```bash
sudo systemctl start wassal-restore-drill@prod && sudo tail -n 1 /var/lib/wassal/drill-results.jsonl
```

`backup-prod` and `restore-drill-prod` turn green. Once `staging-backup.env` exists, test staging's
own backup on the staging VM too:

```bash
sudo systemctl start wassal-backup@staging && journalctl -u wassal-backup@staging -n 20
```

`backup-staging` turns green, and a `staging/YYYY/MM/DD/…` pair is in the daily bucket.

`uv run tools/b2_setup.py [--env staging] --check` with the same bucket names verifies an
environment's buckets and keys at any time, without changing anything.

## GitHub (deploy failures)

Under GitHub → Settings → Notifications → Actions, turn on email for failed workflows. A failed
deploy job is then an email (deploy-and-rollback.md).

## Monthly routine

These keep the free accounts and their guarantees alive (research R1, R9, R11). Put a monthly
reminder in your calendar.

- Check that the 1st-of-month drill passed: `restore-drill-prod` is green, and the latest line of
  `/var/lib/wassal/drill-results.jsonl` **on the staging VM** says `pass` (restore.md, "Reading
  drill-results.jsonl").
- Sign in to the **OCI console**. Oracle may suspend tenancies left idle for 30 days. Check that
  both instances are running.
- Sign in to **Healthchecks.io**. It deletes accounts with no login for a year.
- In **each B2 account** (production's and staging's), check that the caps are still USD 0 and
  storage is well under 10 GB. If anything changed, run
  `uv run tools/b2_setup.py [--env staging] --daily-bucket <daily> --weekly-bucket <weekly> --check`
  for each environment.
- Check that no service shows a charge (SC-013).
