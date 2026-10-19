# Restore from a backup

Production is backed up every night at 03:00 Cairo time to two Backblaze B2 buckets. On the 1st of
each month at 05:00, a drill restores the newest backup on the host and checks it. This runbook covers
a real restore into production, the full rebuild on a new host, and reading the drill's results.

The recovery targets (backend §15, FR-041): at most **24 h of data lost** and **4 h to serve again**.
Background: research R9; contracts: `specs/002-b01-backend-skeleton/contracts/operations.md`
"Backup job" and "Restore drill".

## What a backup is

| Where | Key | What |
| --- | --- | --- |
| Daily bucket (kept 14 days) | `prod/YYYY/MM/DD/prod-YYYYMMDDTHHMMSSZ.dump` | `pg_dump` custom format |
| Daily bucket | `prod/YYYY/MM/DD/prod-YYYYMMDDTHHMMSSZ.json` | Its metadata. It is uploaded last, so a dump without it is incomplete. |
| Weekly bucket (kept 8 weeks) | The same pair | Taken on Sundays |

The metadata holds the dump's `sha256` and size, the release that took it, and the exact row count
of every table, all read in the dump's own snapshot.

B2 keeps every version of a key, and each version is locked for its bucket's retention. A
compromised host can upload a newer version under an existing name or hide a file, but it can't
delete or change a locked version. If the newest backup looks wrong, the original is still listed by
version (step 2).

## Before you start

Work on the host over WireGuard. Note the time: the clock for the 4 h target is running. Set these in
your shell first; every step below uses them:

```bash
TAG="$(cat /var/lib/wassal/prod/release)"
STACK="/var/lib/wassal/prod/deploy/$TAG"
IMAGE="ghcr.io/ahmedsaied94/wassal-backend:$TAG"
PG=wassal-prod-postgres-1
dc() { sudo RELEASE_TAG="$TAG" docker compose -p wassal-prod -f "$STACK/compose.yml" --env-file "$STACK/env/prod.env" "$@"; }
```

## Restore into production

### 1. Stop the app and the scheduled jobs

```bash
sudo systemctl stop wassal-backup@prod.timer wassal-restore-drill@prod.timer
dc stop api admin worker beat
```

PostgreSQL and Valkey keep running. The uptime alert fires, which is expected.

### 2. Download the backup

**The usual case, the newest complete backup.** The drill's own fetch downloads it and checks its
size and `sha256`:

```bash
sudo install -d -m 0700 -o 10001 -g 10001 /var/lib/wassal/restore
sudo docker run --rm --env-file /etc/wassal/prod.env --env-file /etc/wassal/prod-drill.env \
  -v /var/lib/wassal/restore:/drill "$IMAGE" python manage.py restore_drill fetch /drill
```

It prints `fetched prod/…dump` and leaves `backup.dump` and `backup.json` in
`/var/lib/wassal/restore/`. Go on to step 4.

**An older backup, or the newest one was hidden or replaced** (the fetch says `sha256 mismatch` or
`no complete backup`, or the drill failed the same way). List every version with the drill key:

```bash
sudo docker run --rm -i --env-file /etc/wassal/prod-drill.env "$IMAGE" python - <<'PY'
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
sudo docker run --rm -i --env-file /etc/wassal/prod-drill.env -v /var/lib/wassal/restore:/drill \
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
pick another one. A replaced backup means someone used the backup key, so treat the host as
compromised:

- Delete the backup key in the B2 console.
- Create a replacement with the same name, capabilities, buckets and prefix (research R9), using the
  native API's `b2_create_key` with the admin key.
- Confirm it with `uv run tools/b2_setup.py --daily-bucket <daily> --weekly-bucket <weekly> --check`.
- Rebuild the host ("Full rebuild" below).

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
- From outside, `https://<prod API host>/healthz` answers, and the uptime alert clears.

Then take a fresh backup of the restored data and turn the schedules back on:

```bash
sudo systemctl start wassal-backup@prod.service
sudo systemctl start wassal-backup@prod.timer wassal-restore-drill@prod.timer
```

Write down the total time. When you are sure the restore is good (give it a few days), remove what
it left:

```bash
sudo docker exec "$PG" psql -U postgres -c "DROP DATABASE wassal_before_<stamp>"
sudo docker exec "$PG" rm -f /tmp/restore.dump /tmp/restore.list
sudo rm -r /var/lib/wassal/restore
```

## Full rebuild on a new host (within 4 h)

Use this when the VM or its boot volume is gone. Each step names its runbook. Note the time of each,
to compare with the measured setup time (T054) and drill restore time (T085).

1. **Provision.** Follow provision-host.md steps 1–8 on a new VM:
   - Re-attach the reserved public IP, so the `sslip.io` hostnames stay the same.
   - Put back the env files from your password manager: `prod.env`, `prod-db.env`, `edge.env`,
     `host-monitor.env`, `prod-backup.env`, `prod-drill.env`, and staging's. New database
     passwords are fine, because the databases are new.
   - The new host has a new WireGuard key and a new SSH host key. Re-add your device and the
     `deploy-*` peers, then update the GitHub Environment secrets (`WG_CONFIG`, the host key)
     (provision-host.md step 8, deploy-and-rollback.md "Replacing a deploy key").
2. **Deploy the serving tag.** Re-run the release workflow of the tag that was serving
   (deploy-and-rollback.md, "Roll back"). This brings up PostgreSQL with an empty `wassal`
   database, migrated, and an empty production. It comes first because the database container and
   its init script are part of that release's stack.
3. **Restore.** Follow "Restore into production" above, steps 1–5. The `wassal` database you move
   aside in step 4 is the empty one.
4. **Check the rest.** The uptime monitor is green, `heartbeat-prod` and `host-monitor` ping again,
   and `sudo systemctl list-timers 'wassal-*'` shows the backup, drill and monitor timers.

The sum must stay within 4 h (SC-009). If it doesn't, write down which step was slow and why.

## Reading drill-results.jsonl

Each drill appends one JSON line to `/var/lib/wassal/drill-results.jsonl`, and sends the same line as
the `restore-drill-prod` ping body. To read the latest:

```bash
sudo tail -n 1 /var/lib/wassal/drill-results.jsonl | python3 -m json.tool
```

| Field | Meaning |
| --- | --- |
| `started_at`, `finished_at` | When the check ran (UTC) |
| `backup_key`, `backup_created_at` | Which backup was restored, and when it was taken |
| `release` | The serving release whose code ran the checks |
| `checks.restore` | `pg_restore` finished without an error |
| `checks.migrations` | The serving code has nothing left to apply, and knows every applied migration |
| `checks.row_counts` | Every table's count equals the metadata, with no table missing or extra |
| `checks.invariants` | Each registered data invariant, by name (none in B01) |
| `restore_duration_s`, `total_duration_s` | Seconds. The restore time counts toward the 4 h target. |
| `outcome`, `failure` | `pass`, or `fail` with a short reason |

When `outcome` is `fail`, `failure` says why:

| `failure` starts with | Meaning | Do |
| --- | --- | --- |
| `restore failed (exit …)` | `pg_restore` refused the dump | Run the drill again. If it repeats, read `journalctl -u wassal-restore-drill@prod`, and compare `postgres_version` in the metadata with the serving PostgreSQL. |
| `migrations: … pending` | The backup is older than the serving code's migrations. A deploy with a migration probably ran between the 03:00 backup and the 05:00 drill. | Take a backup, then run the drill again: `sudo systemctl start wassal-backup@prod wassal-restore-drill@prod` |
| `migrations: … unknown` | The backup has migrations the serving code doesn't: production was rolled back past a migration | Expected after such a rollback. It passes again once that release serves. |
| `row counts: …` | The restored data differs from what was counted in the same snapshot | Treat that backup as damaged. Take a new backup and run the drill again. If it repeats, investigate before you need a restore. |
| `invariants failed: …` | A data invariant fails in the backup, so it fails in production too | Investigate the data in production |
| `… raised …` | A check itself broke | Read the traceback with `journalctl -u wassal-restore-drill@prod` |

Some failures happen before a result exists. Then no line is added, and only the `/fail` ping body
gives the reason:

- `disk: …`: less than 5 GB is free on the Docker volume.
- `fetch failed`: the journal shows why, for example `sha256 mismatch` or `no complete backup`. See
  step 2 above.
- `the drill database never got ready`.
- `check printed no result`.

The drill leaves nothing behind either way: no `wassal-drill-*` container, volume or network, and no
`/var/lib/wassal/drill/`.
