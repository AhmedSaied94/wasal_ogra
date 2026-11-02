# Research: Live-ops Settings, Store Catalog and Offers (B10)

Each decision says what was chosen, why, and what was rejected. The spec's clarifications (session
2026-11-01) are fixed inputs, so they are not reopened here.

## R1. A new `liveops` app

- **Decision:** a new Django app, `apps/liveops`, in backend §5's layout (`models`, `services/`,
  `api/`, `tasks`, `admin`). It holds the settings registry and its rows, the change history, the
  store products, the offers and the Remote Config check. `economy` imports `liveops`, never the
  reverse, like `economy` → `progress` (B03 R1). `INSTALLED_APPS` lists it before `progress`.
- **Why:** backend §12 already names `liveops` and its models, and the constitution names
  `liveops.LiveSetting`. Settings read by `accounts`, `economy` and later apps can't live in any one
  of them.
- **Rejected:** settings in `common` (it is infrastructure, with no models of game data); a
  third-party settings package such as django-constance (no typed cross-setting rules, no
  who-applies-it flag, a history we'd have to add anyway, and one more dependency for ~40 lines).

## R2. The registry is code, the values are rows

- **Decision:** `apps/liveops/registry.py` declares every setting as a frozen `Spec`: key, kind
  (`int`, `choice`, `version`, `bool`, `datetime`), default, bounds or choices, `applied_by`
  (`phone`, `server`, `both`), and a one-line meaning. `LiveSetting` rows hold only the key, the
  current value (JSON) and who and when. Cross-setting rules are functions in the same file
  (contracts/settings.md "Rules"). A migration creates every row with its default; a post-migrate
  hook creates rows for keys a later deploy adds (spec edge case), and marks rows whose key the
  registry no longer has as `unused`.
- **Why:** types, ranges and rules are code review material and must be tested; only the value is
  live-ops data. It also lets the parity test (R9) read the defaults without a database.
- **Rejected:** type and range columns on the row (an operator could widen a range in the admin);
  one JSON document holding all values (no per-key history, every save races every other).

## R3. Every process re-reads the table, no cache

- **Decision:** `liveops.settings.current()` returns an immutable `Snapshot` (a mapping of key to
  typed value). Each process keeps its last snapshot and the time it loaded it, and re-reads the
  table when the snapshot is older than `LIVEOPS_REFRESH_SECONDS` (30, env). The read is one query
  of about 70 small rows. If the database read fails, the process keeps its last snapshot and logs
  a warning; a process that has never loaded raises, as any database outage does today. Code
  defaults are used only for a key that has no row yet (the window between deploy and migrate).
- **Why:** with 1 OCPU per host there are a handful of gunicorn and Celery processes, so the cost
  is a few queries a minute. 30 s refresh plus a request already running stays inside FR-005's 60 s.
  It has no dependency on Valkey, so the spec's "cache down" edge case needs no code: Valkey isn't
  involved.
- **Rejected:** a generation counter in Valkey, as the manifest does (more moving parts for no
  gain at this size, and a Valkey outage would then need its own fallback); reading the table on
  every request (a query per request on the hottest path); `django.conf.settings` with a restart
  (FR-005 forbids it).

## R4. B03's settings reader becomes an adapter

- **Decision:** `economy.services.settings.current()` keeps its signature and its frozen
  `EconomySettings`, built from one liveops snapshot plus the env-only `SYNC_GAME_TIMEZONE` and
  `SYNC_OP_RETENTION_DAYS`. The batch already calls it once (FR-007 holds as is). The
  `client_min_version` and `client_latest_version` fields are dropped: the client block reads
  liveops directly per platform (R6). Tests that override a value today with the `settings`
  fixture use a new `live_settings` fixture instead (`conftest.py`), which writes the row and
  refreshes the process snapshot.
- **Why:** the six callers and B03's tests don't change; only where the numbers come from does.
- **Retired env variables** (removed from `config/env.py`, `.env.example`, the docker env files
  and B03's environment contract): `ECONOMY_FUEL_MAX`, `ECONOMY_FUEL_MAX_SUBSCRIBER`,
  `ECONOMY_FUEL_REGEN_MINUTES`, `ECONOMY_FUEL_REFILL_DAILY_CAP`, `ECONOMY_FUEL_OVERDRAFT_PER_DAY`,
  `ECONOMY_TRAFFIC_JAM_ADS_PER_TRIP`, `ECONOMY_NAME_MIN_LENGTH`, `ECONOMY_NAME_MAX_LENGTH`,
  `SYNC_CONTENT_MAX_AGE_DAYS`, `SYNC_MIN_DURATION_PERCENT`, `SYNC_FAST_RUN_PERCENT`,
  `SYNC_TRIPS_PER_DAY_FLAG`, `SYNC_CLOCK_CLAMP_FLAG_MINUTES`, `SYNC_SESSION_GAP_MINUTES`,
  `SYNC_COMEBACK_AWAY_DAYS`, `SYNC_COMEBACK_COOLDOWN_DAYS`, `CLIENT_MIN_VERSION`,
  `CLIENT_LATEST_VERSION`.
- **Kept as env** (FR-003): `SYNC_GAME_TIMEZONE`, `SYNC_OP_RETENTION_DAYS`, `THROTTLE_*`,
  `CONTENT_INDEX_KEEP`, secrets and URLs. The retention is kept because it sizes the database and
  defines `op_expired`, a contract with the phone, not a balance.

## R5. Importing host overrides once

- **Decision:** the seeding migration (`liveops/0002_seed`) reads each retired variable straight
  from `os.environ`. A value that parses, is in range and differs from the default becomes the
  live value, with an `import` change record (actor empty, note "from env on migrate"). A value
  that doesn't parse is ignored with a migration warning, since the running release already
  refused it at startup. After that the variables are never read. A Django system check,
  `liveops.W001`, warns at every start while any retired variable is still set, naming it, so the
  deploy log says what to delete from the host's env file.
- **Why:** FR-011: the deploy must not change behaviour. Today all hosts run the defaults, so in
  practice nothing is imported, but the rule costs one function.
- **Rejected:** an error at startup when a retired variable is set (a forgotten line would stop a
  deploy for nothing).

## R6. The version gate is a default permission

- **Decision:** two permission classes are added to `REST_FRAMEWORK["DEFAULT_PERMISSION_CLASSES"]`
  after `ClientHeaders`:
  - `CurrentClient` answers `426 client_outdated` with `details.min_version` when the parsed
    `X-Client-Version` is below the live `min_client_version_<platform>`. A view sets
    `allow_outdated_client = True` to opt out; only `BootstrapView` does.
  - `NotInMaintenance` (R7).
  Views that already replace the defaults (`AnonymousView` and `RefreshView` with
  `(ClientHeaders,)`, the manifest and health with `AllowAny`) are exempt without a change, which is
  exactly FR-013's list. B06's and B07's store and ad callbacks will set their own permissions too.
- Bootstrap's `client` block reads `min_client_version_<platform>` and
  `latest_client_version_<platform>` for the request's `X-Platform`.
- **Why:** B02's comment in `base.py` makes the defaults the place for "every player endpoint";
  a permission runs before the view body, so nothing is applied. It reuses `parse_client_version`
  and `as_tuple` (FR-014).
- **Rejected:** a middleware (it would run before authentication and parse headers twice, and the
  admin hostname would need excluding); a decorator on each view (a new endpoint would forget it).

## R7. Maintenance

- **Decision:** two settings, `maintenance_enabled` (bool) and `maintenance_until` (optional UTC
  datetime). `NotInMaintenance` answers `503 maintenance` for every unsafe method (`POST`, `PUT`,
  `PATCH`, `DELETE`) on views using the defaults, with `details.until` only when the end is set and
  in the future (FR-016). Safe methods pass. The admin isn't on DRF, so it is unaffected.
  - **The command** `uv run manage.py maintenance on [--until 2026-11-03T15:30Z] --actor <staff>
    [--note …]`, `off --actor <staff>`, `status`. It checks the `live_ops` group's permission like
    the content commands (B04), and writes through the same service as the admin, so it is in the
    same history (FR-033).
  - **The runbook** `docs/runbooks/deploy-and-rollback.md` gets a "Maintenance window" section: run
    the command in the host's `api` container before a deploy whose migration rewrites or locks a
    large table (any non-expand migration, or one marked `# maintenance` in review), wait 60 s, deploy,
    check, turn it off.
- **Scheduled jobs** (FR-034): a decorator, `liveops.tasks.skip_in_maintenance`, wraps the task
  body: when the snapshot says maintenance is on, it logs `task_skipped_maintenance` with the task
  name and returns `{"skipped": "maintenance"}`. It is applied to every scheduled job that writes:
  `accounts.tasks.prune_sessions`, `economy.tasks.prune`, `content.tasks.sweep_stuck_builds`,
  `content.tasks.sync_files` and the new `liveops.tasks.expire_offers`. `common.tasks.heartbeat`
  and `liveops.tasks.check_remote_config` aren't wrapped. A test lists every `PeriodicTask` the
  migrations create and fails if one is neither wrapped nor in an explicit monitoring list, so later
  features can't forget.
- **Why:** a permission is the same mechanism as R6; reads go on so bootstrap and state work (M06
  R19 expects that). The 30 s snapshot means a switch applies within FR-005's window on every
  process, Celery included.
- **Rejected:** a Caddy-level maintenance page (reads would stop too, and the phone would get HTML).

## R8. The Remote Config drift check

- **Decision:** a daily Celery task `liveops.tasks.check_remote_config` (bind=True,
  `autoretry_for=(requests.RequestException,)`, backoff, 3 retries, 10 s timeout per call) at 05:15
  Cairo.
  - **Auth without a new package:** the service account's JSON key (`REMOTE_CONFIG_SERVICE_ACCOUNT`,
    a secret, optional) signs a JWT with PyJWT[crypto] (already a dependency), exchanged at
    `https://oauth2.googleapis.com/token` for an access token with the scope
    `https://www.googleapis.com/auth/firebase.remoteconfig`, then
    `GET https://firebaseremoteconfig.googleapis.com/v1/projects/{FIREBASE_PROJECT_ID}/remoteConfig`
    with `requests` (already a dependency). The account has only the "Firebase Remote Config Viewer"
    role.
  - **What is compared:** for each setting with `applied_by` `phone` or `both`, the template's
    `parameters.<key>.defaultValue.value`, parsed with the setting's kind. A parameter that is
    absent, or whose default is `useInAppDefault`, means the phone uses its bundled default, so the
    compared value is `tunables.json`'s (the same as the registry default, R9). Conditional values
    are ignored (FR-009).
  - **What is recorded:** one `RemoteConfigCheck` row per run: when, status (`ok`, `drift`,
    `unreachable`, `not_configured`), the template's version number, and the drifted keys with both
    values. `unreachable` after the retries leaves the last drift marks as they were, since the admin
    shows the latest row that has a comparison. The admin's settings list shows a "drift" column
    from that row.
  - **Sentry:** when any drifted key is `applied_by: both`, one `capture_message` at `warning`, with
    a fixed fingerprint `["liveops", "remote-config-drift"]` and the keys and both values as extra
    data (no player data). Sentry's alert rule emails the operator (owner action). Phone-only drift
    is logged, not sent.
  - **Not configured:** with no key or no project id, the task records `not_configured` and returns.
    Nothing else depends on it.
- **Why:** Remote Config's template API is the only read of the defaults; the clarification fixed
  the direction. The B02 Google sign-in check already uses PyJWT, so the signing code style exists.
- **Rejected:** `firebase-admin` (a large dependency for one GET; its Python Remote Config module
  targets server templates, not the client template); `google-auth` (another dependency for what
  is 20 lines with PyJWT).

## R9. One parity test for every phone key

- **Decision:** `apps/liveops/tests/test_tunables_parity.py` replaces B03's four-key test: every key
  in `apps/mobile/assets/config/tunables.json` must be in the registry with `applied_by` `phone` or
  `both` and an equal default, and every registry key that the phone applies must be in the file.
  B03's `test_tunables_parity.py` is deleted.
- **`applied_by: both`** today: `fuel_max`, `fuel_max_subscriber`, `fuel_regen_minutes`,
  `ads_fuel_refill_daily_cap`. B07 adds its caps the same way.
- **Server-only keys** get lowercase names in the registry (`fuel_overdraft_per_day`,
  `comeback_away_days`, …) and no Remote Config key (Complexity Tracking).

## R10. App versions in use (FR-031, FR-032)

- **Decision:** reuse B02's `Player.platform` and `Player.client_version`, which token issue and
  renewal already set. Bootstrap also updates them when they differ from the request (one
  conditional `UPDATE`, so an app updated mid-session counts at once). "Active" is
  `Wallet.last_active_at` within 7 days (B03 sets it on every bootstrap, state and sync); an index
  on `Wallet.last_active_at` is added. The admin's version page groups `(platform, client_version)`
  counts with one aggregate query and folds the `+BUILD` suffix in Python (distinct versions are
  few). Players without a wallet (never bootstrapped) aren't counted. The page shows, for a minimum
  typed in its form, the blocked count and share before the confirm step.
- **Why:** the data already exists. Storing the raw header (with the build) is B02's contract, and
  folding at read time keeps B02's columns unchanged.
- **Spec note:** FR-031 says "record the version without the build suffix"; it is recorded as B02
  does and folded when counted, which meets the same need. FR-031 is updated to say so.
- **Rejected:** a separate version table (duplicates B02's columns); Firebase Analytics (not on the
  server, and can't preview a minimum).

## R11. Store products

- **Decision:** `StoreProduct(product_id, kind, platforms, bonat, bonus_bonat, entitlement,
  best_value, display_order, active)`, `product_id` unique and limited to glossary §3.5's list. A
  check constraint keeps grants coherent with the kind: a consumable has `bonat > 0` and no
  entitlement; a non-consumable has an entitlement and `bonat = bonus_bonat = 0` (until phase 2's
  `starter_pack`, which a later feature allows by widening the constraint). A partial unique index
  allows at most one active `best_value`. The seed migration creates the four products of FR-020,
  on both platforms.
- **`catalog.grants_for(product_id, platform)`** returns a frozen `ProductGrants(bonat_total,
  entitlement)`, or raises `ProductUnavailable`. B06 calls it inside its grant transaction and
  stores the result on `Purchase` (FR-022).
- The grants are not separate JSON (backend §12's `grants (JSON)`): typed columns are checkable,
  and the shape is known for every MVP product. Backend §12 is updated.
- **Rejected:** grants as JSON (no constraint can check it, and a typo grants nothing or too much).

## R12. Offers and their rules

- **Decision:** `Offer(offer_id, kind, product, starts_at, ends_at, priority, rules, status)`.
  `rules` is a JSON list of objects, each with a `rule` name from a closed set, validated on save by
  one function per rule:
  - `country_in` `{"countries": ["EG"]}` (ISO 3166 alpha-2, from `Player.country`);
  - `days_since_install` `{"min": 0, "max": 6}` (Cairo calendar days since `Player.created_at`,
    inclusive);
  - `payer` `{"is": false}` (has a granted purchase; always false until B06 adds purchases, through
    one function B06 replaces);
  - `owns_product` / `lacks_product` `{"product_id": "remove_ads"}` (entitlements, neutral until
    B06, same hook);
  - `chapter_reached` `{"chapter_id": "ch1_first_job", "status": "completed"}` (from
    `progress.StoryState`).
  An offer for a non-consumable is never listed to its owner, whatever its rules (FR-026).
- **Evaluation:** `GET /v1/offers` loads the active offers from a per-process snapshot (the same
  30 s refresh as settings, R3), loads the player's facts once (one query for the player, one for
  story state, the B06 hooks), and filters in Python. The query count is fixed whatever the number
  of offers (SC-006).
- **Expiry:** `liveops.tasks.expire_offers`, hourly, sets `status = expired` on offers past
  `ends_at`; listing filters on `starts_at ≤ now < ends_at` itself, so it never depends on the job
  (FR-027).
- **Rejected:** a rules engine or expression language (CEL, JSON Logic: more than five fixed rules
  need, and untestable as data); rules as model fields (every new rule a migration).

## R13. The response of `GET /v1/offers`

- **Decision:** `{"server_time", "products": [...], "offers": [...]}`. Products ordered by
  `display_order`, each `{product_id, kind, bonat, bonus_bonat, entitlement, best_value}`. Offers
  ordered by `priority` descending, each `{offer_id, kind, product_id, ends_at}`. No price, ever.
  Full shape in contracts/api.md. It follows the defaults (token, headers, player throttle, 426,
  and it is a read, so maintenance passes).
- **Why:** M12 needs amounts, bonus and the ribbon; HANDOFF's `Shop` reads them "from the catalog".

## R14. History and permissions

- **Decision:** one append-only `LiveopsChange` table for settings, products and offers:
  `target` (`setting`, `product`, `offer`), `key`, `old`, `new` (JSON), `actor` (nullable for the
  migration import), `source` (`admin`, `command`, `import`, `reset`), `note`, `at`. The service
  layer writes it in the same transaction as the change; the admin shows it read-only per object;
  no edit or delete permission exists for it (a test checks), like B03's `WalletAdjustment`.
- **Group** `live_ops` (migration, the pattern of `economy/0002_groups`) with view and change on
  `LiveSetting`, add/change/view on `StoreProduct` and `Offer`, view on `LiveopsChange` and
  `RemoteConfigCheck`, and a custom `liveops.switch_maintenance`. No other group gets them.
  `create_staff --group live_ops` works without a change.
- **Admin forms** call the services, never `save()` directly, so validation and history can't be
  skipped (a test saves through the admin and checks the history row).

## R15. Error codes

- **Decision:** `client_outdated` (426, `details.min_version`) and `maintenance` (503,
  `details.until` optional) are added to `ErrorCode`, `MESSAGES` and `STATUSES` in
  `apps/common/errors.py`, after they are in backend §6.2 (B01's rule).

## R16. Performance

- **Decision:** targets on staging: `GET /v1/offers` p95 ≤ 150 ms; bootstrap and sync keep B03's
  targets (no added query on the request path: the two permissions read the in-process snapshot).
  Checked with B03's `tools/sync_load.py` pattern, extended with an offers scenario.

## Handed to later features

- **B06:** call `catalog.grants_for` inside the grant and store its result on `Purchase`; replace
  the `payer` and entitlement hooks of R12; the iOS products list in `platforms` once iOS sells.
- **B07:** add its caps to the registry as `applied_by: both`, and read them from the snapshot.
- **B08, B11:** their tunables (daily challenge retry cost, `notif_daily_max` is already a phone key)
  go in the registry; their scheduled jobs that write use `skip_in_maintenance` and catch up on their
  next run (FR-034).
- **B12, B14:** the `starter_pack` and season-pass offers are data; `starter_pack` widens R11's
  constraint.
- **M11, M12:** the app reads `GET /v1/offers` for the shop (M12), and bundles nothing about pack
  amounts.
