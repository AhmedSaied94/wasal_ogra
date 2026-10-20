# Restore from a backup

Production is backed up every night at 03:00 Cairo time, on the prod VM, to two Backblaze B2
buckets. On the 1st of each month at 05:00, a drill **on the staging VM** restores production's
newest backup into a throwaway database and checks it. Since B04, staging, where authors work, is
backed up the same way into its own two buckets (B04 research R8). This runbook covers a real
restore into production, a restore of staging, the full rebuild of either VM, and reading the
drill's results.

The recovery targets (backend §15, FR-041): at most **24 h of data lost** and **4 h to serve again**.
Background: research R9; contracts: `specs/002-b01-backend-skeleton/contracts/operations.md`
"Backup job" and "Restore drill".

## What a backup is

| Where | Key | What |
| --- | --- | --- |
| Daily bucket (kept 14 days) | `prod/YYYY/MM/DD/prod-YYYYMMDDTHHMMSSZ.dump` (staging's: `staging/…/staging-….dump`) | `pg_dump` custom format |
| Daily bucket | `prod/YYYY/MM/DD/prod-YYYYMMDDTHHMMSSZ.json` | Its metadata. It is uploaded last, so a dump without it is incomplete. |
| Weekly bucket (kept 8 weeks) | The same pair | Taken on Sundays |

The metadata holds the dump's `sha256` and size, the release that took it, and the exact row count
of every table, all read in the dump's own snapshot.

B2 keeps every version of a key, and each version is locked for its bucket's retention. A
compromised prod VM can upload a newer version under an existing name or hide a file, but it can't
delete or change a locked version. If the newest backup looks wrong, the original is still listed by
version (step 2).

The keys are split between the VMs: the prod VM holds production's backup key, which can only
write, and the staging VM holds the drill key, which can only list and read production's backups.
The staging VM also holds staging's own backup key, which can only write under `staging/`. No key
can read staging's backups: a staging restore creates one that expires after a day ("Restore
staging" below).

## Before you start

Work on the prod VM over its WireGuard (`ssh ubuntu@10.66.0.1`). Note the time: the clock for the
4 h target is running.

The download needs the drill key, which lives on the staging VM only. Put a temporary copy on the
prod VM, in `/run`, so a reboot removes it if you forget. Paste the drill block (`B2_*`,
`BACKUP_PREFIX`) from your password manager:

```bash
sudo install -m 0400 -o root -g root /dev/null /run/wassal-prod-drill.env
sudoedit /run/wassal-prod-drill.env
```

Set these in your shell first; every step below uses them:

```bash
TAG="$(cat /var/lib/wassal/prod/release)"
STACK="/var/lib/wassal/prod/deploy/$TAG"
IMAGE="ghcr.io/ahmedsaied94/wassal-backend:$TAG"
PG=wassal-prod-postgres-1
DRILL_ENV=/run/wassal-prod-drill.env
dc() { sudo RELEASE_TAG="$TAG" docker compose -p wassal-prod -f "$STACK/compose.yml" --env-file "$STACK/env/prod.env" "$@"; }
```

## Restore into production

### 1. Stop the app and the backup

```bash
sudo systemctl stop wassal-backup@prod.timer
dc stop api admin worker beat
```

PostgreSQL and Valkey keep running. The uptime alert fires, which is expected. The drill runs on the
staging VM and never touches production, so leave it alone.

### 2. Download the backup

**The usual case, the newest complete backup.** The drill's own fetch downloads it and checks its
size and `sha256`:

```bash
sudo install -d -m 0700 -o 10001 -g 10001 /var/lib/wassal/restore
sudo docker run --rm --env-file /etc/wassal/prod.env --env-file "$DRILL_ENV" \
  -v /var/lib/wassal/restore:/drill "$IMAGE" python manage.py restore_drill fetch /drill
```

It prints `fetched prod/…dump` and leaves `backup.dump` and `backup.json` in
`/var/lib/wassal/restore/`. Go on to step 4.

**An older backup, or the newest one was hidden or replaced** (the fetch says `sha256 mismatch` or
`no complete backup`, or the drill failed the same way). List every version with the drill key:

```bash
sudo docker run --rm -i --env-file "$DRILL_ENV" "$IMAGE" python - <<'PY'
import os
from apps.common.services.backups import b2_client

s3 = b2_client(os.environ["B2_S3_ENDPOINT"], os.environ["B2_REGION"],
               os.environ["B2_DRILL_KEY_ID"], os.environ["B2_DRILL_APP_KEY"])
for bucket in (os.environ["B2_DAILY_BUCKET"], os.environ["B2_WEEKLY_BUCKET"]):
    for page in s3.get_paginator("list_object_versions").paginate(Bucket=bucket, Prefix="prod/"):
        for v in page.get("Versions", []):
            print(bucket, v["Key"], v["VersionId"], v["LastModified"].isoformat(), v["Size"],
                  "latest" if v["IsLatest"] else "older")
        for m in page.get("DeleteMarkers", []):
            print(bucket, m["Key"], m["VersionId"], m["LastModified"].isoformat(), "hidden")
PY
```

Pick the pair you want: a `.dump` and its `.json`, normally the **oldest** version of each name,
which is the one the backup job wrote. Download them by version:

```bash
sudo install -d -m 0700 -o 10001 -g 10001 /var/lib/wassal/restore
sudo docker run --rm -i --env-file "$DRILL_ENV" -v /var/lib/wassal/restore:/drill \
  "$IMAGE" python - <bucket> <key without .dump/.json> <dump version id> <json version id> <<'PY'
import os, sys
from apps.common.services.backups import b2_client

bucket, base, dump_version, meta_version = sys.argv[1:]
s3 = b2_client(os.environ["B2_S3_ENDPOINT"], os.environ["B2_REGION"],
               os.environ["B2_DRILL_KEY_ID"], os.environ["B2_DRILL_APP_KEY"])
s3.download_file(bucket, f"{base}.dump", "/drill/backup.dump", ExtraArgs={"VersionId": dump_version})
s3.download_file(bucket, f"{base}.json", "/drill/backup.json", ExtraArgs={"VersionId": meta_version})
print("downloaded", base)
PY
```

### 3. Check the sha256 (by-version downloads only)

```bash
sudo sha256sum /var/lib/wassal/restore/backup.dump
sudo grep -E '"(sha256|size_bytes|created_at|release)"' /var/lib/wassal/restore/backup.json
```

The two `sha256` values must match. If they don't, that version isn't the backup it claims to be:
pick another one. A replaced backup means someone used the backup key, so treat the prod VM as
compromised:

- Delete the backup key in the B2 console.
- Create a replacement with the same name, capabilities, buckets and prefix (research R9), using the
  native API's `b2_create_key` with the admin key.
- Confirm it with `uv run tools/b2_setup.py --daily-bucket <daily> --weekly-bucket <weekly> --check`.
- Rebuild the prod VM ("Full rebuild" below), with the new key in `prod-backup.env`.

### 4. Restore into a fresh database

Keep the damaged database aside under a dated name, create a fresh `wassal` owned by the app role,
and restore into it as that role:

```bash
STAMP="$(date -u +%Y%m%d%H%M)"
sudo docker exec "$PG" psql -U postgres -v ON_ERROR_STOP=1 -c "ALTER DATABASE wassal RENAME TO wassal_before_$STAMP"
sudo docker exec "$PG" psql -U postgres -v ON_ERROR_STOP=1 -c "CREATE DATABASE wassal OWNER wassal"
sudo docker exec "$PG" psql -U postgres -d wassal -v ON_ERROR_STOP=1 -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements"
sudo docker cp /var/lib/wassal/restore/backup.dump "$PG:/tmp/restore.dump"
sudo docker exec "$PG" pg_restore --list /tmp/restore.dump | grep -v " EXTENSION " | sudo tee /var/lib/wassal/restore/restore.list >/dev/null
sudo docker cp /var/lib/wassal/restore/restore.list "$PG:/tmp/restore.list"
sudo docker exec "$PG" pg_restore -U postgres --dbname=wassal --use-list=/tmp/restore.list \
  --clean --if-exists --no-owner --role=wassal --exit-on-error /tmp/restore.dump
```

- The rename fails while something is still connected. Check that step 1 stopped every app service,
  then run `SELECT pid, application_name FROM pg_stat_activity WHERE datname = 'wassal'` to see who.
- `pg_stat_statements` belongs to the superuser, so it is created first and left out of the app
  role's restore (the `grep -v " EXTENSION "`). Everything else is created by, and owned by, `wassal`.
- `pg_restore` exits 0 on success. With `--exit-on-error`, any error stops it. Read that error, fix
  the cause, then drop the new `wassal` and repeat this step from `CREATE DATABASE`.
- The old database still takes disk space. Check `df -h /` if the disk is close to full.

### 5. Migrate, restart and verify

```bash
dc --profile ops run --rm migrate
dc up -d --wait --wait-timeout 180 api admin worker beat
curl -fsS http://127.0.0.1:8100/readyz; echo
curl -fsS http://127.0.0.1:8100/healthz; echo
```

`migrate` applies whatever the serving code has that the backup doesn't. Then:

- Compare a few row counts with the metadata, for example
  `sudo docker exec "$PG" psql -U postgres -d wassal -tAc "SELECT count(*) FROM accounts_user"`
  against `"public.accounts_user"` in `backup.json`.
- Sign in to the admin.
- From outside, `https://api.193-122-74-125.sslip.io/healthz` answers, and the uptime alert clears.

Then remove the temporary drill key, take a fresh backup of the restored data, and turn the
schedule back on:

```bash
sudo rm "$DRILL_ENV"
sudo systemctl start wassal-backup@prod.service
sudo systemctl start wassal-backup@prod.timer
```

Then bring the pack files back in line with the restored records (B04). The worker writes any
pack or release file the database has and the disk lacks, never overwrites one, and raises
`core.floor.json` to the highest stored version:

```bash
sudo docker exec wassal-prod-worker-1 python manage.py content_files sync --verify
```

It ends with `files in sync`. Packs promoted after the backup keep their files, and the floor file
never goes down, so staging never reuses their numbers. Promote them again if they should serve
(content-publishing.md section 2).

To check that fresh backup at once, run the drill on the staging VM once the backup has finished:
`sudo systemctl start wassal-restore-drill@prod`.

Write down the total time. When you are sure the restore is good (give it a few days), remove what
it left on the prod VM:

```bash
sudo docker exec "$PG" psql -U postgres -c "DROP DATABASE wassal_before_<stamp>"
sudo docker exec "$PG" rm -f /tmp/restore.dump /tmp/restore.list
sudo rm -r /var/lib/wassal/restore
```

## Restore staging

Staging's database holds the authors' work: drafts, speech lines and their reviews, pack records
and the content audit log. Restore it when that work is lost or wrong. Production is never
touched.

1. **A read key.** On your machine, from `backend/`, with staging's bucket names:

   ```bash
   uv run tools/b2_setup.py --env staging --daily-bucket <daily> --weekly-bucket <weekly> --restore-key
   ```

   It asks for the admin key and prints a block for `/run/wassal-staging-restore.env`. The key
   can only list and read `staging/` in those two buckets, and B2 expires it after 24 h.
2. **On the staging VM** (`ssh ubuntu@10.67.0.1`), put the block in `/run`, so a reboot removes it:

   ```bash
   sudo install -m 0400 -o root -g root /dev/null /run/wassal-staging-restore.env
   sudoedit /run/wassal-staging-restore.env
   ```

3. **Set the shell variables** for staging:

   ```bash
   TAG="$(cat /var/lib/wassal/staging/release)"
   STACK="/var/lib/wassal/staging/deploy/$TAG"
   IMAGE="ghcr.io/ahmedsaied94/wassal-backend:$TAG"
   PG=wassal-staging-postgres-1
   DRILL_ENV=/run/wassal-staging-restore.env
   dc() { sudo RELEASE_TAG="$TAG" docker compose -p wassal-staging -f "$STACK/compose.yml" --env-file "$STACK/env/staging.env" "$@"; }
   ```

4. **Follow "Restore into production" steps 1–5** with these variables. Use staging's names
   wherever they say prod:
   - `wassal-backup@staging.timer` and `wassal-backup@staging.service`;
   - `--env-file /etc/wassal/staging.env` in the fetch;
   - `Prefix="staging/"` if you list versions by hand;
   - `https://staging-api.141-147-129-92.sslip.io/healthz` from outside.

   A replaced staging backup (step 3's `sha256` check fails) means someone used staging's backup
   key. Delete `wassal-staging-backup` in the B2 console, run the `--env staging` setup's key step
   again, and rebuild the staging VM.
5. **The pack files.** In the worker, write any pack or release file the restored records have and
   the disk lacks:

   ```bash
   sudo docker exec wassal-staging-worker-1 python manage.py content_files sync --verify
   ```

   It ends with `files in sync`. Files of packs published after the backup stay, and are never
   overwritten. The next build still gets a number above every one of them: staging numbers each
   build above production's floor file (content-publishing.md "A build fails with
   `version_floor_unavailable`").
6. **Clean up.** `sudo rm /run/wassal-staging-restore.env`, then delete `wassal-staging-restore` in
   the B2 console. Remove the moved-aside database and `/var/lib/wassal/restore` as in step 5's
   last block, once you are sure.

**If no staging backup is usable**, rebuild staging's content from the repository instead (B04
research R7, R8):

1. Import `content/source` in staging's admin (Content packs → "Import zip", from a zip of that
   folder), or with `content_import` in the admin container.
2. Speech-line reviews aren't in `content/source`: select every pool → "Mark reviewed" once
   you've checked them.
3. Build. The new pack is numbered above production's floor file, so above every pack production
   holds, gaps included.

## Full rebuild on a new host (within 4 h)

Use this when a VM or its boot volume is gone. Each VM is rebuilt on its own, and the other VM
keeps running and needs nothing. Each step names its runbook. Note the time of each, to compare
with that VM's measured setup time (T103 for staging, T104 for prod) and the drill's restore time
(T085).

Both cases change the VM's WireGuard key, SSH host key and admin CA root. So you always re-add
peers, replace that environment's deploy secrets, and install the new CA root on each device that
uses that admin (private-network.md).

### The prod VM

1. **Provision.** Follow provision-host.md steps 1–8 with the prod values, on a new VM:
   - Re-attach the reserved public IP `193.122.74.125`, so the `sslip.io` hostnames stay the same.
   - Put back the env files from your password manager: `prod.env`, `prod-db.env`, `edge.env`,
     `host-monitor.env` and `prod-backup.env`. New database passwords are fine, because the
     database is new. Check `PUBLIC_BIND_IP` in `edge.env`: the new VNIC's private IP may differ.
   - Re-add your device's prod tunnel, the staff peers and `deploy-prod`. Then replace the
     `production` Environment's secrets (provision-host.md step 8, deploy-and-rollback.md
     "Replacing a deploy key").
2. **Deploy the serving tag.** Re-run the release workflow of the tag that was serving
   (deploy-and-rollback.md, "Roll back"). This brings up PostgreSQL with an empty `wassal`
   database, migrated, and an empty production. It comes first because the database container and
   its init script are part of that release's stack.
3. **Restore.** Follow "Before you start" and "Restore into production" above, steps 1–5. The
   `wassal` database you move aside in step 4 is the empty one. Staff accounts come back with the
   data.
4. **Check the rest.** The uptime monitor is green, `heartbeat-prod` and `host-monitor-prod` ping
   again, `sudo systemctl list-timers 'wassal-*'` shows the backup and host monitor timers, and
   `content_files sync --verify` (end of step 5) wrote the pack files back.

The prod VM's time plus the restore must stay within 4 h (SC-009). If it doesn't, write down which
step was slow and why.

### The staging VM

Staging's database comes back from its own backups (since B04).

1. **Provision.** Follow provision-host.md steps 1–8 with the staging values, on a new VM:
   - Re-attach the reserved public IP `141.147.129.92`.
   - Put back the env files from your password manager: `staging.env`, `staging-db.env`,
     `edge.env`, `host-monitor.env`, `staging-backup.env` and `prod-drill.env`. Check
     `PUBLIC_BIND_IP` in `edge.env`.
   - Re-add your device's staging tunnel, the staff peers and `deploy-staging`. Then replace the
     `staging` Environment's secrets.
2. **Deploy.** In Actions → `backend`, open the newest `master` run and re-run its `deploy-staging`
   job.
3. **Restore.** Follow "Restore staging" above. The `wassal` database you move aside is the empty
   one. Staff accounts and authored content come back with the data; the pack files come back
   from step 5 there. If no backup is usable, use its last part, and create the staff accounts
   again, yours with `--superuser` (staff-accounts.md).
4. **Check the rest.** `heartbeat-staging`, `backup-staging` and `host-monitor-staging` ping again,
   `sudo systemctl list-timers 'wassal-*'` shows the backup, drill and host monitor timers, and an
   on-demand drill passes: `sudo systemctl start wassal-restore-drill@prod`.

The staging VM's time on its own must stay within 4 h (SC-009).

## Reading drill-results.jsonl

The drill runs on the staging VM. It fetches production's newest complete backup with the drill
key, using staging's serving image. Then it restores and checks it with the image of the
production release that took it: it pulls `sha-<release>` (the `release` in the backup's metadata)
from GHCR, and uses that release's PostgreSQL image. Staging's own image would be wrong: it usually
has migrations production hasn't applied yet. So the staging VM must be able to pull production's
`sha-` images: the package is public, and they stay at least 56 days (deploy-and-rollback.md
"Images in GHCR").

Each drill appends one JSON line to `/var/lib/wassal/drill-results.jsonl` on the staging VM, and
sends the same line as the `restore-drill-prod` ping body. To read the latest, on the staging VM:

```bash
sudo tail -n 1 /var/lib/wassal/drill-results.jsonl | python3 -m json.tool
```

The file isn't backed up, so a rebuilt staging VM starts a new one. Healthchecks.io's event log for
`restore-drill-prod` still shows the recent lines.

| Field | Meaning |
| --- | --- |
| `started_at`, `finished_at` | When the check ran (UTC) |
| `backup_key`, `backup_created_at` | Which backup was restored, and when it was taken |
| `release` | The production release that took the backup. Its image ran the checks. |
| `checks.restore` | `pg_restore` finished without an error |
| `checks.migrations` | That release's code has nothing left to apply, and knows every applied migration |
| `checks.row_counts` | Every table's count equals the metadata, with no table missing or extra |
| `checks.invariants` | Each registered data invariant, by name (none in B01) |
| `restore_duration_s`, `total_duration_s` | Seconds. The restore time counts toward the 4 h target. |
| `outcome`, `failure` | `pass`, or `fail` with a short reason |

To run the drill again, on the staging VM: `sudo systemctl start wassal-restore-drill@prod`. To
take a new backup first, run `sudo systemctl start wassal-backup@prod` on the prod VM, and start
the drill once it has finished.

When `outcome` is `fail`, `failure` says why:

| `failure` starts with | Meaning | Do |
| --- | --- | --- |
| `restore failed (exit …)` | `pg_restore` refused the dump | Run the drill again. If it repeats, read `journalctl -u wassal-restore-drill@prod` on the staging VM, and compare `postgres_version` in the metadata with the PostgreSQL image of that release (its `docker/compose.yml`). |
| `migrations: … pending` | The backup lacks migrations of the release that took it. That shouldn't happen: a release serves only after its migrations ran. | Treat that backup as suspect. Take a new backup and run the drill again. If it repeats, investigate before you need a restore. |
| `migrations: … unknown` | The backup has migrations the release that took it doesn't know. A production deploy migrated and then failed (exit 5 partway, 6 or 7), or production was rolled back past a migration. | Expected after such a deploy or rollback. It passes again once a release that knows them serves and takes the backup. |
| `row counts: …` | The restored data differs from what was counted in the same snapshot | Treat that backup as damaged. Take a new backup and run the drill again. If it repeats, investigate before you need a restore. |
| `invariants failed: …` | A data invariant fails in the backup, so it fails in production too | Investigate the data in production |
| `… raised …` | A check itself broke | Read the traceback with `journalctl -u wassal-restore-drill@prod` on the staging VM |

Some failures happen before a result exists, or make it unusable. Then no line is added, and only
the `/fail` ping body gives the reason. The journal has the details
(`journalctl -u wassal-restore-drill@prod` on the staging VM):

- `no staging release to fetch with`, or `the staging release file is invalid`: staging has never
  been deployed on this VM. The fetch runs in staging's serving image, so deploy staging first.
- `/etc/wassal/prod-drill.env is missing`: create it (monitoring-setup.md "Backblaze B2").
- `disk: …`: less than 5 GB is free on the staging VM's Docker volume.
- `fetch failed`: for example `sha256 mismatch` or `no complete backup`. See step 2 above.
- `the backup's metadata has no valid release`: treat that backup as damaged.
- `couldn't pull the backup's release sha-<release>`: the staging VM couldn't pull production's
  image from GHCR. It pulls without credentials, so the package must be public, and the image must
  still be there (deploy-and-rollback.md "Images in GHCR"). Check the VM's outbound network too.
- `couldn't read the compose.yml of sha-<release>`, or `… names no postgres image`: that release's
  stack can't give the drill its PostgreSQL image.
- `couldn't create the drill network` or `volume`, `couldn't start the drill database`, or
  `the drill database never got ready`: Docker on the staging VM. Read the journal, then run the
  drill again.
- `check printed no result (exit …)`: the check crashed before reporting.
- `check ran another release, not the backup's sha-<release>`: the check's result names a release
  other than the one that took the backup, so it doesn't count.

The drill runs only on the staging VM, and only for `prod`. Started anywhere else, it exits 2 at
once and pings nothing.

The drill leaves nothing behind either way: no `wassal-drill-*` container, volume or network, and no
`/var/lib/wassal/drill/`. Production data is on the staging VM only while the drill runs, and never
reaches the staging environment.
