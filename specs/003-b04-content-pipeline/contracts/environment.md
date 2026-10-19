# Contract: Configuration Added by B04

This extends B01's `contracts/environment.md`. The same startup rules apply: a value is checked
when it is read, and a bad one stops the process, naming the variable but never the value. Nothing
here is a secret.

## Application variables

| Variable | dev | test | staging | prod | Rule |
| --- | --- | --- | --- | --- | --- |
| `CONTENT_ROLE` | `source` | `source` | `source` | `target` | Required. `target` only with `WASSAL_ENV=prod`, and `source` everywhere else (research R9). |
| `CONTENT_PACKS_DIR` | `/app/var/packs` | a temporary directory | `/var/lib/wassal/packs` | `/var/lib/wassal/packs` | The path inside the worker (and inside the dev API). It must exist and be writable by the worker, which checks at startup. The API role doesn't need it. |
| `CONTENT_PACKS_PUBLIC_URL` | `http://localhost:8000/packs/` | `https://packs.test.invalid/packs/` | `https://<staging API_HOST>/packs/` | `https://<API_HOST>/packs/` | Required. An absolute URL ending in `/`, and `https://` outside dev and test. Manifest URLs are built from it (research R5). |
| `CONTENT_VERSION_FLOOR_URL` | empty | empty, or a local test server | production's `CONTENT_PACKS_PUBLIC_URL` | must be empty | `https://` when set. Staging's builds read production's `core.floor.json` here (research R7). |
| `CONTENT_PROMOTION_SOURCE_URL` | must be empty | a local test server | must be empty | staging's `CONTENT_PACKS_PUBLIC_URL` | Required on `target`. `https://`. Where promotions fetch from (research R6). |
| `CONTENT_SOLVER_STAGE` | `stand_in` | `stand_in` | `none` | `none` | `none` (reports `not_available`), `stand_in` (passes every trip: dev and test only), or a dotted path that B05 sets. The settings check refuses `stand_in` on staging and prod (FR-022). |
| `CONTENT_MANIFEST_CACHE_SECONDS` | `30` | `0` | `30` | `30` | 0–60 (FR-031) |
| `CONTENT_HTTP_TIMEOUT_SECONDS` | `10` | `2` | `10` | `10` | 1–30, for reading the floor file and for promotion fetches |

`dev`'s `CONTENT_PACKS_DIR` is `backend/var/packs/` mounted at `/app/var/packs`. It is gitignored,
and the API serves it under `DEBUG` only.

## Host paths and mounts

| Host | Path | Mounted into | Mode |
| --- | --- | --- | --- |
| staging, prod | `/var/lib/wassal/packs/` (owner uid 10001, `0755`) | the `worker` at `/var/lib/wassal/packs` (rw), and the edge Caddy at `/srv/packs` (ro) | — |
| staging, prod | — | not the `api`, `admin` or `beat` containers | — |

`provision.sh` creates the directory on both hosts. The edge's `compose.yml` adds the read-only
mount. The edge `Caddyfile`'s `(api)` snippet gains the `/packs/` route (contracts/pack-delivery.md)
before its `reverse_proxy`, and its `(admin)` snippet gains `request_body { max_size 8MiB }`
(research R9).

## Staging backups (research R8)

These reuse B01's backup variables in staging's own files. `docker/env/staging.env` already names
`BACKUP_ENV_FILE=/etc/wassal/staging-backup.env` and
`BACKUP_STATE_DIR=/var/lib/wassal/staging/backup`.

| Variable | In | Value |
| --- | --- | --- |
| `B2_DAILY_BUCKET`, `B2_WEEKLY_BUCKET` | `/etc/wassal/staging-backup.env` | `wassal-staging-backup-daily`, `wassal-staging-backup-weekly` |
| `B2_BACKUP_KEY_ID`, `B2_BACKUP_APP_KEY` | the same file (secret, `0400`) | A **write-only** key for those two buckets only, never production's key or the drill key |
| `HC_PING_BACKUP_URL` | the same file (secret) | A separate Healthchecks.io check for staging's backup |
| `BACKUP_PREFIX` | the same file | `staging` (B01's default is `prod`) |
| `B2_S3_ENDPOINT`, `B2_REGION`, `BACKUP_WEEKLY_WEEKDAY` | the same file | As in production |

The timer is `wassal-backup@staging.timer`, at the same 03:00 Cairo time. The staging host monitor
also checks the backup age, as production's does (B01 FR-038).

## Repository files read at runtime

| Path in the image | From | Use |
| --- | --- | --- |
| `wassal_content/schemas/*.json` (package data) | `content/schemas/`, copied by codegen (research R13) | Validation, `schema-set.json` floors |
