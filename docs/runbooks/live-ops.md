# Live ops: settings, versions, products, offers, maintenance

Everything an operator retunes without a release lives in the admin's **Live ops** pages
(`Live settings`, `App versions`, `Maintenance`, `Store products`, `Offers`, `Remote Config
checks`, `Change history`) or on the `maintenance` command. Every save is attributed and
append-only. Contract: `specs/016-b10-catalog-offers/contracts/`; the registry of every setting is
`apps/liveops/registry.py`.

Members of the `live_ops` group edit settings and the switch; `player_support` and
`content_author` see none of these pages. `create_staff <name> --group live_ops` adds a member, with
the usual TOTP and WireGuard.

## Changing a setting, and reading its history

1. **Live settings** (`/admin/liveops/livesetting/`): every registry key with its value, its
   default, who applies it (`phone`, `server`, `both`), its meaning and the last change. Filter by
   `applied by`, `changed from default` or `drifted`.
2. Open the key, type the value and a note, save. The form refuses a value outside the range or a
   rule the other settings break, and keeps the old value. The history below the form shows every
   change with its old and new value, who and why.
3. **JSON is never edited by hand**: the form is typed by the registry (integer with its bounds,
   choice, `MAJOR.MINOR.PATCH`, true/false, ISO-8601 UTC).
4. **Reset to default** (an action on the list) writes a `reset` change.

A change applies within 60 s on every process without a restart: each process re-reads the table
at most every `LIVEOPS_REFRESH_SECONDS` (30). A batch already running keeps the snapshot it read.

The rules that can refuse a save: the subscriber tank at or above the normal one, the fast-run flag
at or above the minimum duration, the longest name at or above the shortest, the minimum version at
or below the latest, and a maintenance end only while on and in the future.

## Settings that live in two places (`applied_by: both`)

Eight keys are applied by the phone and the server: `fuel_max`, `fuel_max_subscriber`,
`fuel_regen_minutes`, `ads_fuel_refill_daily_cap` (and B07's caps later). Remote Config edits the
phone's bundled copy; the server keeps its own. Change both, and in this order:

- **Raising a cap** (a bigger tank): **server first**, then Remote Config. A phone that already
  allows more than the server accepts gets no benefit and no error; the reverse would refuse fuel
  the phone granted itself.
- **Lowering a cap**: **Remote Config first**, then the server. A phone that still allows the old
  amount never sends more than the server accepts; the reverse would refuse a start the phone
  already played.

The daily drift check (`liveops.tasks.check_remote_config`, 05:15 Cairo) compares Remote Config's
defaults with the live settings. A difference on a `both` key is a `drift` row in the admin, a log
warning, and **one Sentry warning** with the fingerprint `liveops` / `remote-config-drift`; a
phone-only difference is logged only. Sentry's alert rule emails you for both environments (owner
action). Fix the side that is wrong, then wait for the next run; `celery call
liveops.tasks.check_remote_config` runs it now.

The Firebase service account is a read-only secret: `FIREBASE_PROJECT_ID=wassal-ogra` and
`REMOTE_CONFIG_SERVICE_ACCOUNT` (the JSON key) in each host's `/etc/wassal/<env>.env`. With both
empty the check records `not_configured` and nothing else happens.

## Raising a minimum app version

**App versions** (`/admin/liveops/livesetting/versions/`, also linked from the four version
settings) shows the players active in the last 7 days per `MAJOR.MINOR.PATCH` per platform (the
build suffix is folded). Type a proposed minimum, **Preview**: it shows how many players and what
share it would block. **Save the minimum** is the confirm step; it writes through the same service,
so the minimum can't pass the latest version. It applies within 60 s: older apps get
`426 client_outdated` on every player endpoint except bootstrap, which answers
`force_update: true`.

## Products and offers

- **Store products** (`/admin/liveops/storeproduct/`): the four seeded products with their typed
  grants. A consumable needs BONAT and no entitlement; a non-consumable needs an entitlement and no
  BONAT; only one active product may be the best value. **There is no price column** and none may
  be added: prices are configured in Play Console / App Store Connect.
- **Offers** (`/admin/liveops/offer/`): rules are a JSON list validated on save
  (`country_in`, `days_since_install`, `payer`, `owns_product`, `lacks_product`,
  `chapter_reached`). Listing filters on the times itself, so an offer disappears at its end even
  before the hourly `liveops.tasks.expire_offers` marks it `expired`. Ending an offer early is
  setting `ends_at` to now.
- No offer ships at launch.

`GET /v1/offers` returns the catalog and the caller's eligible offers and never a price. B06 calls
`apps.liveops.services.catalog.grants_for` inside its grant transaction.

## Maintenance

Use it for a deploy whose migration rewrites or locks a large table (any non-expand migration, or
one marked `# maintenance` in review). Reads and offline play continue; writes answer
`503 maintenance` (`details.until` when set and in the future), and every scheduled job that writes
skips its run and catches up next time.

1. **Admin:** **Maintenance** (from any live-setting page, or
   `/admin/liveops/livesetting/maintenance/`), enter an optional end time and a note, **Turn on**.
   **Command** on a host:

   ```bash
   sudo docker compose -p wassal-<env> exec api python manage.py maintenance on \
       --actor <staff> --until 2026-11-03T15:30Z --note "deploy"
   sudo docker compose -p wassal-<env> exec api python manage.py maintenance status
   sudo docker compose -p wassal-<env> exec api python manage.py maintenance off --actor <staff>
   ```

   `--actor` must be an active staff user with `liveops.switch_maintenance`, and `--until` must be
   ISO-8601 with a zone and in the future; otherwise the command exits 2 and changes nothing.
2. Wait 60 s for every process to see it, then deploy (`deploy-and-rollback.md`, "Maintenance
   window").
3. Turn it off. The phone sends its queued batch again and every operation applies once: a replay
   returns the stored results.

Both switches are in **Change history** with source `command` or `admin`.
