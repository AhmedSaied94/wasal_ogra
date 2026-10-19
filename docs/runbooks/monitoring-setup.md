# Monitoring setup

The operator is emailed when production is down, the heartbeat stops, a backup or the monthly drill
fails, the host runs short of disk, a certificate nears expiry, a queue backs up, or a deploy fails
(FR-038). Every service here is free, and its terms allow commercial use (research R11, checked
2026-10-18). Each one runs outside the VM it watches, except the host monitor, which pings out.

Put every ping URL and DSN straight into its `/etc/wassal/*.env` file (mode `0400`, provision-host.md
step 4). They are secrets: anyone holding a ping URL can fake a green check.

## Healthchecks.io (dead-man's switches)

1. Create a **Hobbyist** account (no card). Use the email you want alerts on.
2. Set the project time zone to `Africa/Cairo`.
3. Create the five checks:

| Check | Schedule | Grace | Ping URL goes into | Pinged by |
| --- | --- | --- | --- | --- |
| `heartbeat-prod` | period 5 min | 10 min | `HC_PING_HEARTBEAT_URL` in `/etc/wassal/prod.env` | the `heartbeat` task, every 5 min, through beat, the broker and a worker (FR-006) |
| `heartbeat-staging` | period 5 min | 10 min | `HC_PING_HEARTBEAT_URL` in `/etc/wassal/staging.env` | the same, on staging |
| `backup-prod` | period 1 day | 2 h | `HC_PING_BACKUP_URL` in `/etc/wassal/prod-backup.env` | the nightly backup, 03:00 Cairo, or `/fail` with the reason |
| `restore-drill-prod` | period 30 days | 5 days | `HC_PING_DRILL_URL` in `/etc/wassal/prod-drill.env` | the drill, 05:00 Cairo on the 1st, or `/fail` |
| `host-monitor` | period 5 min | 10 min | `HC_PING_HOST_MONITOR_URL` in `/etc/wassal/host-monitor.env` | `wassal-host-monitor.timer`, or `/fail` listing the failing checks |

`/etc/wassal/host-monitor.env` also holds the thresholds:

```text
HC_PING_HOST_MONITOR_URL=https://hc-ping.com/<uuid>
DISK_ALERT_PERCENT=80
CERT_ALERT_DAYS=14
QUEUE_BACKLOG_THRESHOLD=100
QUEUE_BACKLOG_MINUTES=10
BACKUP_STORAGE_ALERT_BYTES=8000000000
```

The host monitor stays skipped until that file exists. Once it exists, the monitor fails until
production is deployed, because it reads production's queues. That's expected during setup.

Test it on the host, then check the Healthchecks dashboard:

```bash
sudo systemctl start wassal-host-monitor.service && journalctl -u wassal-host-monitor -n 5
```

## UptimeRobot (production down)

1. Create a **Free** account.
2. Add an **HTTP(s)** monitor on `https://<prod API host>/healthz`, with a 5-minute interval and an
   email alert. A down production sends that email within 10 minutes (SC-008).
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
   Settings → Client Keys (DSN) into `SENTRY_DSN` in both `/etc/wassal/staging.env` and
   `/etc/wassal/prod.env`. Events carry `environment` (`staging` or `prod`) and `release` (the
   commit), so one project is enough. Leave `SENTRY_DSN` empty in `backend/.env`, so dev runs don't
   use the quota.
4. Leave the default alert, an email on every new issue.
5. The server already scrubs what it sends: no IP addresses, cookies, headers, request bodies or
   local variables (research R7). Don't turn on "send default PII" in any project setting. Sentry
   still derives a country from the address an event arrives from, which is the server's, never a
   player's. To drop that too, turn on **Prevent Storing of IP Addresses** under Project Settings →
   Security & Privacy.

Test it after the first deploy (quickstart scenario 16):

```bash
sudo docker exec wassal-prod-api-1 python manage.py sentry_test
sudo docker exec wassal-prod-worker-1 python manage.py sentry_test --task
```

Two issues appear, tagged `environment=prod` and with the release. Open one and check that it has
no IP address, cookies or headers.

## Backblaze B2 (backups)

The nightly backup and the monthly drill store and read production's dumps in B2 (research R9). Do
this once, before the first production deploy (quickstart step 8).

1. Create the account and **turn on MFA** first: the terms require it.
2. **Note the account's region**, shown at sign-up and in each bucket's Endpoint field
   (`s3.<region>.backblazeb2.com`). It can't be changed later. From B02 on, the backups hold player
   data, so record the region in research R9 "Data location", next to the Jeddah host, for the
   PDPL review (backend §15, §22.9).
3. Under **Caps & Alerts**, set a **USD 0** daily cap on storage and on Class A, B and C
   transactions (and on downloads, if offered), and keep the alert emails on. At a USD 0 cap, an
   upload past the free 10 GB fails, so the backup pings `/fail` instead of running up a bill.
4. Leave **Event Notifications** off. They are billed and can't be capped.
5. Create an **admin application key** with all capabilities, on all buckets. Keep it in your
   password manager only. It never goes on the host, and only it can delete a backup before its lock
   ends.
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
   - Then put them on the host with mode `0400` (provision-host.md step 4).
   - Paste the `backup-prod` and `restore-drill-prod` ping URLs in place of the placeholders.

   The endpoint and region lines come from B2's answer, so they match the account.
7. Re-run `sudo ./wassal-docker/host/provision.sh` (or `sudo systemctl daemon-reload`). The backup
   and drill timers stay skipped until their env files exist.

After the first production deploy, test both (quickstart scenarios 19 and 21):

```bash
sudo systemctl start wassal-backup@prod && journalctl -u wassal-backup@prod -n 20
sudo systemctl start wassal-restore-drill@prod && sudo tail -n 1 /var/lib/wassal/drill-results.jsonl
```

`backup-prod` and `restore-drill-prod` turn green. `uv run tools/b2_setup.py --check` with the same
bucket names verifies the buckets and keys at any time, without changing anything.

## GitHub (deploy failures)

Under GitHub → Settings → Notifications → Actions, turn on email for failed workflows. A failed
deploy job is then an email (deploy-and-rollback.md).

## Monthly routine

These keep the free accounts and their guarantees alive (research R1, R9, R11). Put a monthly
reminder in your calendar.

- Check that the 1st-of-month drill passed: `restore-drill-prod` is green, and the latest line of
  `/var/lib/wassal/drill-results.jsonl` says `pass` (restore.md, "Reading drill-results.jsonl").
- Sign in to the **OCI console**. Oracle may suspend tenancies left idle for 30 days.
- Sign in to **Healthchecks.io**. It deletes accounts with no login for a year.
- In the **B2** console, check that the caps are still USD 0 and storage is well under 10 GB. If
  anything changed, run `uv run tools/b2_setup.py --daily-bucket <daily> --weekly-bucket <weekly> --check`.
- Check that no service shows a charge (SC-013).
