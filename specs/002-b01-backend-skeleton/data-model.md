# Data Model: Backend Skeleton (B01)

B01 creates one project table, `accounts.User` for staff, and relies on framework tables for 2FA,
sign-in lockout, sessions and schedules. Everything else in this feature is configuration, files and
JSON documents: environments, releases, backups, drill results, monitoring checks and private-network
peers. Each entity below maps to requirements in [spec.md](./spec.md).

## Database (PostgreSQL 17, one database per environment)

### `accounts.User` — staff account (FR-017, FR-022)

The project's own `AUTH_USER_MODEL` from migration `accounts.0001`. It is staff-only. Players are a
separate `Player` model in B02 (backend §12), and B02 decides how its tokens authenticate. Because
the model is project-owned from the first migration, B02 can also extend it without rewriting a table.

| Field | Type | Rules |
| --- | --- | --- |
| `id` | UUID, primary key | UUIDv7 from `common.ids.uuid7()`, not editable (FR-016) |
| `username` | varchar(150), unique | `^[a-z0-9._-]{3,150}$`, lowercased on save |
| `password` | varchar(128) | Django hash. Validators: minimum length 12, common-password, numeric-only, similarity |
| `is_staff` | bool | Must be true to enter the admin. `create_staff` sets it. |
| `is_superuser` | bool | Only for the operator's own account |
| `is_active` | bool | Deactivating blocks sign-in immediately |
| `date_joined` | timestamptz | Set on create |
| `last_login` | timestamptz, null | From `AbstractBaseUser` |

- Built on `AbstractBaseUser` + `PermissionsMixin`, not `AbstractUser`, so there are no email, first
  name or last name columns (constitution: minimal personal data).
- Relationships: `PermissionsMixin` groups and permissions, `django_otp` devices,
  `django_admin_log.user`.
- **Lifecycle:**
  1. `create_staff <username>` → active, no device, can't sign in.
  2. `staff_totp <username>` → one confirmed TOTP device, can sign in.
  3. `staff_totp <username> --reset` → old device deleted, new one issued.
  4. Deactivated (`is_active = false`, through the admin or `create_staff --deactivate`).

  There is no public sign-up and no self-service reset (spec edge case).

### Framework tables (keep their own key types; outside the UUIDv7 check, spec edge case)

| Table (app) | Purpose | Notes |
| --- | --- | --- |
| `otp_totp_totpdevice` (django-otp) | One TOTP device per staff member | `key` is a secret held only in the database. Throttling fields enforce django-otp's backoff after wrong codes. |
| `axes_accessattempt`, `axes_accessfailurelog` (django-axes) | Failed admin sign-ins | 5 failures per username **or** per client address within 15 min → 15 min lockout (FR-022). The client addresses are private-network addresses from the host's own WireGuard range (10.66.0.x on prod, 10.67.0.x on staging), not player data. |
| `django_celery_beat_*` | Schedules as data (FR-006) | A data migration creates the `heartbeat` `PeriodicTask`: task `common.tasks.heartbeat`, every 5 min, queue `default` (FR-007). |
| `django_session` | Admin sessions | Secure, HTTP-only cookies on the admin hostname only |
| `django_admin_log`, `auth_group`, `auth_permission`, `django_content_type`, `django_migrations` | Django contrib | — |
| `pg_stat_statements` (extension view) | Per-query statistics (FR-037) | Created by the database init script as superuser. The app role only reads it. |

### Database roles

| Role | Rights | Used by |
| --- | --- | --- |
| `postgres` (superuser) | Everything | The init script and break-glass only. Password only in the host's `<env>-db.env`. |
| `wassal` (owner of database `wassal`) | DDL and DML on its own database. No superuser, no `CREATEROLE`. | API, admin, worker, beat, migrations, backups |

## Configuration entities

### Environment (FR-001, FR-042a)

| Field | `dev` | `staging` | `prod` |
| --- | --- | --- | --- |
| Host | The developer's machine | The staging VM: 1 OCPU / 6 GB, 47 GB boot volume | The prod VM: 1 OCPU / 6 GB, 100 GB boot volume |
| Host identity (`/etc/wassal/host.env`) | none | `WASSAL_ENV=staging`, `WG_ADDRESS=10.67.0.1` | `WASSAL_ENV=prod`, `WG_ADDRESS=10.66.0.1` |
| Settings module | `config.settings.dev` | `config.settings.staging` | `config.settings.prod` |
| Compose project | `wassal-dev` | `wassal-staging` | `wassal-prod` |
| API hostname | `localhost` | `staging-api.<public-ip>.sslip.io` | `api.<public-ip>.sslip.io` |
| Admin hostname | `localhost` | `staging-admin.10-67-0-1.sslip.io` | `admin.10-66-0-1.sslip.io` |
| API / admin upstream | `127.0.0.1:8000` / `127.0.0.1:8001` (the emulator reaches them as `10.0.2.2`) | `127.0.0.1:8200` / `127.0.0.1:8201` | `127.0.0.1:8100` / `127.0.0.1:8101` |
| App env file | `backend/.env` (copied from `.env.example`) | `/etc/wassal/staging.env` | `/etc/wassal/prod.env` |
| Backups | none | none | nightly to B2 `prod/` |
| Restore drill | none | monthly, of prod's backups (`wassal-restore-drill@prod`) | none |
| Heartbeat check | none | `heartbeat-staging` | `heartbeat-prod` |
| Host monitor check | none | `host-monitor-staging` | `host-monitor-prod` |

- `staging` and `prod` each have their own VM, and each VM serves only its own environment. The one
  crossover is the restore drill: it restores prod's newest backup on the staging host and leaves
  nothing behind (research R9).
- `provision.sh --env <env>` writes the host identity on its first run and refuses a different
  `--env` later.
- `<public-ip>` is the reserved public IP of the environment's own host, with dots replaced by
  dashes (FR-042a): `141-147-129-92` for staging, `193-122-74-125` for prod.
- Each admin hostname names its host's WireGuard address. Each host's edge has its own local CA, so
  a device that uses both admins trusts two CA roots.
- Every value is configuration. The variables are listed in
  [contracts/environment.md](./contracts/environment.md).

### Release (FR-029 – FR-033)

| Field | Rule |
| --- | --- |
| Image | `ghcr.io/ahmedsaied94/wassal-backend:sha-<40-hex>`, multi-arch (arm64 + amd64), pushed only by a green `master` run |
| Production tag | `:vMAJOR.MINOR.PATCH`, added to an existing `sha-` image by the release workflow |
| `RELEASE` | The 40-hex commit, baked into the image and reported by `/healthz` |
| Serving release | `/var/lib/wassal/<env>/release` on the environment's host, holding the image tag. `release.previous` holds the one before. |

**Deploy state transitions** (one deploy at a time per environment, FR-032):

```text
requested → pulling → migrating ──fail──→ failed (previous keeps serving, never restarted)
                          │
                          ok
                          ▼
                     restarting → verifying ──fail──→ restoring → failed (previous serving again)
                                      │
                                      ok
                                      ▼
                                   serving (release file updated)
```

### Health result (FR-010 – FR-012)

Response shapes are in [contracts/api.md](./contracts/api.md#health-endpoints). The readiness checks
are `database`, `cache` and `migrations`, each `pass` or `fail`.

### Backup (FR-039, FR-039a)

Objects in two Backblaze B2 buckets, written only by the production host's backup job (research R9):

```text
B2_DAILY_BUCKET   prod/YYYY/MM/DD/prod-YYYYMMDDTHHMMSSZ.dump   # pg_dump custom format
B2_DAILY_BUCKET   prod/YYYY/MM/DD/prod-YYYYMMDDTHHMMSSZ.json   # metadata, uploaded last = completion marker
B2_WEEKLY_BUCKET  prod/YYYY/MM/DD/…                            # same pair, on the weekly day (default Sunday)
```

**Metadata document** (`schema_version: 1`):

| Field | Type | Rule |
| --- | --- | --- |
| `environment` | string | `prod` |
| `created_at` | ISO-8601 UTC | Snapshot time |
| `release` | 40-hex | The release that took the backup |
| `postgres_version` | string | Server version, for example `17.6` |
| `retention_class` | `daily` \| `weekly` | Matches the bucket |
| `dump` | `{key, size_bytes, sha256, format: "custom"}` | `sha256` is checked on every download |
| `tables` | `{"<schema>.<table>": int}` | Exact row counts read in the **same snapshot** as the dump (exported snapshot, research R9) |
| `duration_s` | number | Dump plus upload |

- **Retention:** daily objects are kept 14 days and weekly objects 8 weeks. Each bucket's default
  governance lock keeps every version for that time: the backup key can't delete it or shorten the
  lock. Lifecycle rules then hide and delete the objects (values in research R9).
- **Versions:** B2 keeps every version. A second upload to an existing key adds a newer version and
  leaves the locked original in place, so a real restore may need to list versions (`restore.md`).
- **Validation:** a backup without its metadata object is incomplete, and the drill never uses it.
- **Local copy of the metadata:** the latest metadata is also written to
  `/var/lib/wassal/prod/backup/last-backup.json` on the prod host, for its host monitor's storage
  check. It holds no data.

### Restore drill result (FR-040, SC-009)

One JSON line per run, appended to `/var/lib/wassal/drill-results.jsonl` on the staging host, where
the drill runs, and sent as the Healthchecks.io ping body:

| Field | Type |
| --- | --- |
| `started_at`, `finished_at` | ISO-8601 UTC |
| `backup_key`, `backup_created_at` | string, ISO-8601 UTC |
| `release` | 40-hex (the release whose code ran the checks) |
| `checks` | `{restore, migrations, row_counts}`: `pass` \| `fail`, plus `invariants`: `{<name>: pass \| fail}` |
| `restore_duration_s`, `total_duration_s` | number |
| `outcome` | `pass` \| `fail` |
| `failure` | string or null. A short reason with no secrets or connection strings. |

### Invariant check (FR-040)

A registry in `apps/common/services/invariants.py`, holding a name and a callable that takes a
database connection and returns `passed` and `detail`.

- B01 registers none. The drill reports `invariants: {}`, which passes.
- B03 MUST register `economy.wallet_equals_ledger` when the ledger lands. It is the
  `wallet == sum(ledger)` invariant from backend §7.2.

### Monitoring check (FR-038)

| Check | Where | Period / grace | Alerts when |
| --- | --- | --- | --- |
| `uptime-prod` | UptimeRobot Free (research R11), plus an optional Sentry uptime monitor | 5 min | `GET https://<prod API host>/healthz` fails |
| `heartbeat-prod`, `heartbeat-staging` | Healthchecks.io | 5 min / 10 min | No ping for 15 min (FR-007) |
| `backup-prod` | Healthchecks.io | 1 day / 2 h | `/fail` ping, or no success in 26 h |
| `restore-drill-prod` | Healthchecks.io, pinged from the staging host | 30 days / 5 days | `/fail` ping, or no run in 35 days |
| `host-monitor-prod`, `host-monitor-staging` | Healthchecks.io, one per host | 5 min / 10 min | `/fail` (disk ≥ 80%, API certificate < 14 days or admin certificate invalid, queue backlog, and on prod projected backup storage ≥ 8 GB), or that host's monitor itself stops |
| Error tracking | Sentry | — | New issue in any environment |
| Deploy failure | GitHub Actions notification email | — | A deploy job fails |

### Private-network peer (FR-023a)

Each host runs its own WireGuard server with its own registry file, `/etc/wassal/wg-peers.tsv`,
managed only by that host's `wg-peer add|remove`, which also rewrites `/etc/wireguard/wg0.conf` and
applies it live. A device that needs both hosts is added on each, and each host gives it its own key
pair and address.

| Field | Rule |
| --- | --- |
| `name` | Unique on its host, `^[a-z0-9-]{2,32}$` (for example `ahmed-laptop`) |
| `role` | `operator` \| `staff` \| the host's own deploy role: `deploy-prod` on the prod host, `deploy-staging` on the staging host |
| `address` | `/32` from the role's range in the host's `/24` (prod `10.66.0.0/24`, staging `10.67.0.0/24`): operator `.2–.9`, staff `.10–.99`, deploy `.200–.209` |
| `public_key` | WireGuard public key. One per device and host, never reused. |
| `added_at` | ISO-8601 UTC |

The two hosts use different subnets so an operator laptop can run both tunnels at once. A phone runs
one tunnel at a time.

**What each role may reach on a host's `wg0`** (enforced by that host's iptables rules by source
range, FR-023). `<wg>` is the host's WireGuard address: `10.66.0.1` on prod, `10.67.0.1` on staging.

| Role | `<wg>:22` (SSH) | `<wg>:443` (that host's admin) |
| --- | --- | --- |
| operator | yes | yes |
| staff | no | yes |
| `deploy-prod` / `deploy-staging` | yes, as user `deploy` with a forced command limited to the host's own environment | no |

Removing a peer deletes it from that host's live interface at once (`wg set wg0 peer <key> remove`),
so its access to that host ends immediately. A device on both hosts is removed from each.
