---

description: "Task list for B10 Live-ops Settings, Store Catalog and Offers"
---

# Tasks: Live-ops Settings, Store Catalog and Offers (B10)

**Input**: Design documents from `specs/016-b10-catalog-offers/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**:

- **Mandatory, and first.** Constitution XIII. Every phase writes its tests first, and they must fail
  before its implementation tasks start.
- **Real services.** PostgreSQL and Valkey from the dev stack, never mocks of the database. Time moves
  with `time-machine`. The Remote Config HTTP calls are the one thing replaced, by a fixture that swaps
  the module's fetch functions (the pattern of B02's `google_jwks` in
  `backend/apps/accounts/tests/conftest.py`).
- **Coverage.** At least 80% for the backend (CI gate), and 100% of lines in
  `backend/apps/liveops/services/` and `backend/apps/liveops/permissions.py`.

**Organization**:

- **Paths** are from the repository root. Run `uv` commands in `backend/`.
- **One PR.** Phases 3–7 follow the spec's user stories in priority order.
- **Owner tasks** need the owner's consoles or hosts. An agent can't do them alone.
- **Constraints are quoted** from `data-model.md` and the contracts. Do not loosen them.
- **Prices and names**: this feature has none of the pack's. The pack amounts are the spec's FR-020
  (60 / 300 + 30 / 800 + 120), not the `Shop` board's sample.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story the task belongs to (US1–US5 from spec.md)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: the app, the new environment variables and the two error codes (plan "Project
Structure", research R1, R15, contracts/environment.md).

- [X] T001 Create the app skeleton `backend/apps/liveops/` (`__init__.py`, `apps.py` with label
  `liveops`, empty `models.py`, `services/__init__.py`, `api/__init__.py`, `tests/__init__.py`,
  `migrations/__init__.py`, `management/commands/__init__.py`) and add `"apps.liveops"` to
  `INSTALLED_APPS` in `backend/config/settings/base.py` **before** `"apps.progress"`, with the comment
  "`economy`, `accounts` and `content` import `liveops`; `liveops` never imports `economy` (B10
  research R1)".
- [X] T002 [P] Add the three new variables to `backend/config/env.py` and `base.py`
  (contracts/environment.md "New"): `LIVEOPS_REFRESH_SECONDS` (default `30`, range 5–55),
  `FIREBASE_PROJECT_ID` (default empty) and `REMOTE_CONFIG_SERVICE_ACCOUNT` (`env.secret`, default
  empty, never required). Startup fails naming the variable when exactly one of the two Firebase
  variables is set. List all three in `backend/.env.example` and `backend/docker/env/{prod,staging}.env`
  (empty). Extend `backend/tests/test_env.py` with the range and the one-without-the-other refusal.
- [X] T003 [P] Add `docs/architecture-backend.md` §6.2 rows first (B01's rule): `426
  client_outdated` with `details.min_version`, `503 maintenance` with optional `details.until`
  (ISO-8601 UTC). Then add `CLIENT_OUTDATED = "client_outdated"` and `MAINTENANCE = "maintenance"`
  to `ErrorCode`, `MESSAGES` ("Client outdated", "Down for maintenance") and `STATUSES` (426, 503) in
  `backend/apps/common/errors.py`, with a test in `backend/apps/common/tests/test_errors.py` that each
  renders the envelope with its `details`. Add both to the error table in
  `specs/002-b01-backend-skeleton/contracts/api.md`.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the registry, the setting rows, the change history and the per-process snapshot. Every
story reads settings through these (research R2, R3, R14).

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Tests (write first, they must fail)

- [X] T004 [P] Write `backend/apps/liveops/tests/test_registry.py` (contracts/settings.md):
  - every key in `apps/mobile/assets/config/tunables.json` is in the registry with `applied_by`
    `phone` or `both`; exactly `fuel_max`, `fuel_max_subscriber`, `fuel_regen_minutes`,
    `ads_fuel_refill_daily_cap` are `both`;
  - the 12 server-only keys and the 6 version and maintenance keys of contracts/settings.md
    "Server-only" exist with their defaults;
  - each default passes its own kind and range; `trip_break_min_piasters` and
    `trip_tip_piasters_regular_customer` refuse a value that isn't a multiple of 50;
  - choices: `trip_hints_mode_<line_id>` ∈ `off`, `first_time`, `always`; `pre_trip_card_mode` ∈
    `always`, `new_only`; a version key accepts only `MAJOR.MINOR.PATCH`;
  - each cross-setting rule of contracts/settings.md "Rules" refuses with its exact text.
- [X] T005 [P] Write `backend/apps/liveops/tests/test_snapshot.py` (research R3): `current()` returns
  typed values; a saved change is seen after `LIVEOPS_REFRESH_SECONDS` (time-machine) and not before;
  a database error during refresh keeps the last snapshot and logs a warning; a key without a row
  falls back to its registry default; an unknown key raises `KeyError`; the request path makes zero
  queries when the snapshot is fresh (`django_assert_num_queries(0)`).
- [X] T006 [P] Write `backend/apps/liveops/tests/test_changes.py` (spec FR-006, research R14):
  `settings_admin.change(key, value, actor, note, source)` writes the row and one `LiveopsChange`
  (`target` `setting`, `old`, `new`, `actor`, `source`, `note`) in one transaction; a refused value
  writes neither; `reset` writes the default with `source` `reset`; saving an existing
  `LiveopsChange` raises; no group in the database has `change_liveopschange` or
  `delete_liveopschange`. Concurrency (spec edge case "Two operators save…"): two threads saving
  `fuel_max = 8` and `fuel_max_subscriber = 6` at once from defaults 5 and 7 (each valid alone) end
  with exactly one applied and the other refused with the rule's text, never both; two saves of the
  same key both appear in the history and the last one wins.
- [X] T007 [P] Write `backend/apps/liveops/tests/test_migrations.py` (spec edge cases, research R2,
  R5): after migrate every registry key has a row with its default; a registry key added later gets a
  row from the post-migrate hook; a row whose key the registry dropped is marked `unused` and never
  read.

### Implementation

- [X] T008 Write `backend/apps/liveops/registry.py`: a frozen `Spec(key, kind, default, minimum,
  maximum, choices, multiple_of, applied_by, meaning)` per setting, the full table of
  contracts/settings.md (the per-line keys generated from glossary §3.6's five `line_id`s),
  `validate(spec, raw) -> value`, and the cross-setting rules as functions checked against a
  candidate snapshot, each with the exact text of contracts/settings.md "Rules".
- [X] T009 Write the models in `backend/apps/liveops/models.py` (data-model.md): `LiveSetting`
  (`key` varchar(64) unique, `value` JSON, `unused` bool default false, `updated_by` FK
  `accounts.User` null, `updated_at`) and `LiveopsChange` (`target` ∈ `setting` | `product` |
  `offer`, `key` varchar(64), `old` JSON null, `new` JSON, `source` ∈ `admin` | `command` | `import`
  | `reset`, `actor` FK `accounts.User` null `on_delete=PROTECT`, `note` varchar(500) blank, `at`
  indexed with `(target, key)`), whose `save` refuses an existing pk. Migration
  `backend/apps/liveops/migrations/0001_initial.py`.
- [X] T010 Write `backend/apps/liveops/settings.py`: `Snapshot` (an immutable mapping),
  `current()` with the per-process age check against `settings.LIVEOPS_REFRESH_SECONDS`, one query
  for all non-`unused` rows, the keep-last-on-error rule, and `refresh()` for tests.
- [X] T011 Write `backend/apps/liveops/services/settings_admin.py`: `change`, `change_many` (one
  transaction, rules checked once), `reset`, each validating through the registry. Inside the
  transaction, lock with `select_for_update()` the rows of the changed keys **and** of every key that
  shares a rule with them (contracts/settings.md "Rules"; the registry lists each rule's keys), in key
  order to avoid deadlocks, then check the rules against the locked current values plus the new ones.
  Each also writes
  `LiveopsChange`, and calling `transaction.on_commit(settings.refresh)` so the saving process sees
  its own change at once.
- [X] T012 Write `backend/apps/liveops/migrations/0002_seed.py` (rows for every registry key with its
  default) and the post-migrate hook in `backend/apps/liveops/apps.py` (create missing keys, mark
  `unused`). The env import is US1's T020; leave a clearly named no-op function it fills.
- [X] T013 Add the `live_settings` fixture to `backend/conftest.py`: `live_settings(**values)` writes
  the rows through `settings_admin.change` with a test actor and refreshes the snapshot; it restores
  the defaults after the test.

**Checkpoint**: T004–T007 pass. Settings exist, are typed, and changes are recorded.

---

## Phase 3: User Story 1 - The operator retunes a number without a release (Priority: P1) 🎯 MVP

**Goal**: every balancing number the server applies is read from the live settings; the env
variables are retired; the admin edits them with history (spec US1, FR-001–FR-011).

**Independent Test**: change `fuel_overdraft_per_day` from 2 to 1 in the admin; within 60 s a batch's
second empty-tank start is `cap_reached`; saving `fuel_max_subscriber` 3 while `fuel_max` is 5 is
refused (quickstart §1).

### Tests for User Story 1 (write first, they must fail)

- [X] T014 [P] [US1] Write `backend/apps/liveops/tests/test_tunables_parity.py` (FR-008, research R9)
  and delete `backend/apps/economy/tests/test_tunables_parity.py`: every `tunables.json` key is in the
  registry with an equal default and a phone-facing `applied_by`, and every phone-facing registry key
  is in the file.
- [X] T015 [P] [US1] Write `backend/apps/economy/tests/test_live_economy_settings.py` (FR-002,
  FR-005, FR-007): with `live_settings(fuel_overdraft_per_day=1)` the second empty-tank start of a
  game day is `cap_reached`; with `comeback_away_days=5` a 5-day gap offers the comeback; a value
  changed by another process mid-batch is not seen by that batch (patch the snapshot between two
  operations and assert one snapshot is used); after the refresh window a new batch sees it.
- [X] T016 [P] [US1] Write `backend/apps/liveops/tests/test_env_import.py` (FR-011, research R5):
  with `ECONOMY_FUEL_OVERDRAFT_PER_DAY=3` and `CLIENT_MIN_VERSION=1.1.0` in the environment, the seed
  migration's import sets `fuel_overdraft_per_day` 3 and both platforms' minimum `1.1.0`, each with
  one `import` change (actor null, note "from env on migrate"); a default-equal or unparseable value
  imports nothing; the system check `liveops.W001` warns naming each retired variable still set.
- [X] T017 [P] [US1] Write `backend/apps/liveops/tests/test_admin_settings.py` (FR-004, FR-006,
  FR-010): a `live_ops` member edits a setting through the admin and the history row appears; an
  out-of-range value and a rule break show the error and keep the old value; "Reset to default"
  works; a `player_support` and a `content_author` member get 403 on every live-ops page; the
  changelist filters by `applied_by`, changed-from-default and drifted.

### Implementation for User Story 1

- [X] T018 [US1] Rewrite `backend/apps/economy/services/settings.py` as the adapter of research R4:
  `current()` builds `EconomySettings` from one `liveops.settings.current()` snapshot plus the env
  `SYNC_GAME_TIMEZONE` and `SYNC_OP_RETENTION_DAYS`; drop `client_min_version` and
  `client_latest_version` from the dataclass. Keep the signature for the six callers. In the same
  task, switch `backend/apps/economy/services/bootstrap.py`'s `client` block to
  `min_client_version_<platform>`/`latest_client_version_<platform>` from the snapshot for the
  request's platform (its only reader of the dropped fields), so B03's suite passes at the US1
  checkpoint.
- [X] T019 [US1] Retire the 18 variables of research R4 from `backend/config/env.py` (`economy()`),
  `backend/config/settings/base.py`, `backend/.env.example` and `backend/docker/env/*.env`; keep
  `SYNC_GAME_TIMEZONE` and `SYNC_OP_RETENTION_DAYS` (FR-003). Update `backend/tests/test_env.py`.
  Switch every test that overrode one of them with the `settings` fixture to `live_settings`
  (`grep -rn "ECONOMY_\|SYNC_\|CLIENT_" backend/apps/*/tests`).
- [X] T020 [US1] Fill the env import in `0002_seed.py` (research R5: read `os.environ` directly; the
  four fuel variables map to the `both` keys; `CLIENT_MIN_VERSION`/`CLIENT_LATEST_VERSION` to both
  platforms) and write `backend/apps/liveops/checks.py` with `liveops.W001`, registered in
  `apps.py`.
- [X] T021 [US1] Write the settings admin in `backend/apps/liveops/admin.py` and its templates
  (contracts/admin.md "Live settings", "Change history"): changelist columns, filters, change form with
  range or choices and note, the history inline (read-only), the reset action; every save through
  `settings_admin`. `LiveopsChange` registered read-only.
- [X] T022 [US1] Write `backend/apps/liveops/migrations/0003_group.py` (the pattern of
  `backend/apps/economy/migrations/0002_groups.py`): group `live_ops` with view and change on
  `LiveSetting`, view on `LiveopsChange`, and the custom `liveops.switch_maintenance` declared in
  `LiveSetting.Meta.permissions`. Later phases add their models' permissions to the same group in
  their own migrations (T031, T045, T050), so each migration only names tables that exist.

**Checkpoint**: US1's tests pass; B03's full suite passes on live settings
(`uv run pytest apps/economy apps/progress apps/accounts`).

---

## Phase 4: User Story 2 - An app too old to play safely is asked to update (Priority: P1)

**Goal**: the per-platform version gate and live client block, and the version counts before a new
minimum (spec US2, FR-012–FR-014, FR-031, FR-032).

**Independent Test**: Android minimum 1.3.0: bootstrap from 1.2.4 answers 200 with
`force_update: true`, sync answers 426; 1.3.0 and iOS 1.2.4 are unaffected (quickstart §2).

### Tests for User Story 2 (write first, they must fail)

- [X] T023 [P] [US2] Write `backend/apps/liveops/tests/test_version_gate.py` (contracts/api.md):
  below the platform's minimum, `POST /v1/sync` and `GET /v1/state` and `POST /v1/auth/link` answer
  `426 client_outdated` with `details.min_version` and apply nothing (no `ProcessedOp`); bootstrap
  answers 200 with the live `client` block and `force_update: true`; `auth/anonymous`,
  `auth/refresh`, the manifest and `/healthz` are unaffected; `1.3.0+57` counts as 1.3.0; the iOS
  minimum is independent of Android's; the order of checks (401 before 400 before 426 before 503)
  holds.
- [X] T024 [P] [US2] Write `backend/apps/liveops/tests/test_versions.py` (FR-031, FR-032, research
  R10): bootstrap writes `Player.platform` and `Player.client_version` when they differ and makes no
  write when equal; `versions.active_counts(platform)` groups players whose `Wallet.last_active_at`
  is within 7 days by `MAJOR.MINOR.PATCH`, folding `+BUILD`, with players without a recorded version
  as "unknown"; `versions.blocked(platform, minimum)` returns the count and share, "unknown" never
  counted as blocked; the admin page shows the preview and saves only after the confirm step.

### Implementation for User Story 2

- [X] T025 [US2] Write `CurrentClient` in `backend/apps/liveops/permissions.py` (research R6):
  compares `parse_client_version(X-Client-Version)` with `as_tuple(snapshot[f"min_client_version_{platform}"])`,
  raises `ApiError(ErrorCode.CLIENT_OUTDATED, details={"min_version": …})`, skips views with
  `allow_outdated_client = True` and methods the view doesn't serve (as `ClientHeaders` does). Add
  it to `DEFAULT_PERMISSION_CLASSES` in `backend/config/settings/base.py` after `ClientHeaders`.
- [X] T026 [US2] In `backend/apps/economy/api/views.py` set `allow_outdated_client = True` on
  `BootstrapView`; in `backend/apps/economy/services/bootstrap.py` (whose `client` block T018 already
  moved to live settings) write the player's platform and version when they differ (one conditional
  `UPDATE`).
- [X] T027 [US2] Add an index on `Wallet.last_active_at` in `backend/apps/economy/models.py` with an
  expand-only migration `backend/apps/economy/migrations/0004_wallet_last_active_index.py`
  (`AddIndexConcurrently`, `atomic = False`).
- [X] T028 [US2] Write `backend/apps/liveops/services/versions.py` and the "App versions" admin page
  (contracts/admin.md), linked from the four version settings; the confirm step saves through
  `settings_admin.change_many` so the minimum ≤ latest rule is checked.

**Checkpoint**: US2's tests pass; M06's forced-update path can be exercised against the dev stack.

---

## Phase 5: User Story 3 - The shop shows what each store product gives (Priority: P2)

**Goal**: the store catalog with typed grants, `grants_for` for B06, and `GET /v1/offers` listing
products (spec US3, FR-019–FR-024).

**Independent Test**: `GET /v1/offers` as an Android player lists the four products with 60,
300 + 30, 800 + 120 (best value) and `remove_ads`, and no price; deactivating `bonat_pack_s` removes it
(quickstart §3).

### Tests for User Story 3 (write first, they must fail)

- [X] T029 [P] [US3] Write `backend/apps/liveops/tests/test_catalog.py` (data-model.md
  "StoreProduct"): the seed has exactly the four rows of data-model.md's seed table on both
  platforms; the constraints refuse "`consumable` ⇒ `bonat > 0` and `entitlement = ''`" and
  "`non_consumable` ⇒ `entitlement <> ''` and `bonat = 0` and `bonus_bonat = 0`" violations; a second
  active `best_value` is refused; an unknown `product_id` is refused by the form; `grants_for` returns
  `ProductGrants(bonat_total=bonat + bonus_bonat, entitlement)` and raises `ProductUnavailable` for an
  unknown, inactive or other-platform product; every save writes a `product` change.
- [X] T030 [P] [US3] Write `backend/apps/liveops/tests/test_offers_api.py` (contracts/api.md
  "`GET /v1/offers`"): the response shape, products ordered by `display_order`, only the request
  platform's active products, `offers: []` with no offer rows, no key named `price` or `currency`
  anywhere in the body, `Cache-Control: private, no-store`, 401 without a token, 426 below the
  minimum, 200 during maintenance; a fixed query count with 0 and with 20 offers.

### Implementation for User Story 3

- [X] T031 [US3] Add `StoreProduct` to `backend/apps/liveops/models.py` (data-model.md: `product_id`
  varchar(48) unique; `kind` ∈ `consumable` | `non_consumable` | `subscription`; `platforms` array of
  `android` | `ios`, non-empty; `bonat`, `bonus_bonat` positive integers default 0; `entitlement`
  varchar(32) blank; `best_value`; `display_order` small integer; `active`; `updated_at`), the two
  check constraints and the partial unique index "at most one row with `active AND best_value`". No
  price column. Migration `0004_products.py` creates the table, seeds the four products of FR-020,
  and gives `live_ops` view, add and change on `StoreProduct`.
- [X] T032 [US3] Write `backend/apps/liveops/services/catalog.py`: `ProductGrants`,
  `ProductUnavailable`, `grants_for(product_id, platform)`, `save_product(...)` writing a `product`
  change, and `active_products(platform)` read from the per-process snapshot (the same 30 s refresh,
  research R12).
- [X] T033 [US3] Write `backend/apps/liveops/api/views.py`, `serializers.py` and the URL in
  `backend/config/urls.py` for `GET /v1/offers` (default authentication, permissions and throttle),
  returning `{server_time, products, offers}` with `offers` from US5's service (an empty list until
  Phase 7). drf-spectacular schema with the 401, 426 and 429 answers.
- [X] T034 [US3] Add the Store products admin (contracts/admin.md), saving through
  `catalog.save_product`; history inline.

**Checkpoint**: US3's tests pass; M12 can read the catalog from the dev stack.

---

## Phase 6: User Story 4 - Maintenance pauses the server's writes, not the game (Priority: P2)

**Goal**: the maintenance switch in the admin and the command, the 503 on writes, and the skipped
scheduled jobs (spec US4, FR-015–FR-018, FR-033, FR-034).

**Independent Test**: maintenance on with an end time: sync answers 503 `maintenance` with
`details.until`, bootstrap and offers answer 200, `economy.tasks.prune` logs a skip; off: the same
sync applies (quickstart §4).

### Tests for User Story 4 (write first, they must fail)

- [X] T035 [P] [US4] Write `backend/apps/liveops/tests/test_maintenance.py` (contracts/api.md, FR-015–
  FR-018): while on, `POST /v1/sync` and `POST /v1/auth/link` answer 503 `maintenance` and apply
  nothing; `details.until` is present only when the end is set and in the future (time-machine past
  the end: maintenance still on, `until` absent); bootstrap, state, offers, the manifest,
  `auth/anonymous` and `auth/refresh` answer normally; a request already inside the view when the
  switch flips completes; turning it on and off writes `LiveopsChange` rows; setting an end without
  enabling, or one in the past, is refused with the rule's text. After maintenance (spec SC-004): a
  batch refused with 503 is sent again after `off` and every operation is applied once; sending the
  same batch a third time returns the stored results and changes no balance (no duplicates).
- [X] T036 [P] [US4] Write `backend/apps/liveops/tests/test_maintenance_command.py` (FR-033,
  contracts/admin.md "Command"): `status`, `on --until … --note …`, `off`; an actor without
  `switch_maintenance`, an unknown actor and an `--until` in the past or without a zone exit 2 and
  change nothing; the change's `source` is `command`.
- [X] T037 [P] [US4] Write `backend/apps/liveops/tests/test_scheduled_jobs.py` (FR-034, research R7):
  every `PeriodicTask` the migrations create is either wrapped by `skip_in_maintenance` or in the
  explicit monitoring list (jobs that write only their own check rows: `common.tasks.heartbeat`, `liveops.tasks.check_remote_config`); each
  wrapped task returns `{"skipped": "maintenance"}` and logs `task_skipped_maintenance` while on, and
  runs normally when off.

### Implementation for User Story 4

- [X] T038 [US4] Write `NotInMaintenance` in `backend/apps/liveops/permissions.py` (unsafe methods
  only; `ApiError(ErrorCode.MAINTENANCE, details={"until": …})` or `{}`) and add it to
  `DEFAULT_PERMISSION_CLASSES` after `CurrentClient`.
- [X] T039 [US4] Write `backend/apps/liveops/services/maintenance.py` (`state()`, `switch(enabled,
  until, actor, note, source)` through `settings_admin.change_many`) and the maintenance admin page
  guarded by `liveops.switch_maintenance` (contracts/admin.md "Maintenance").
- [X] T040 [US4] Write `backend/apps/liveops/management/commands/maintenance.py` (contracts/admin.md
  "Command"), checking the actor's permission as the content commands do
  (`backend/apps/content/management/commands/content_build.py`).
- [X] T041 [US4] Write `skip_in_maintenance` in `backend/apps/liveops/tasks.py` and apply it to
  `accounts.tasks.prune_sessions` (`backend/apps/accounts/tasks.py`), `economy.tasks.prune`
  (`backend/apps/economy/tasks.py`), `content.tasks.sweep_stuck_builds` and `content.tasks.sync_files`
  (`backend/apps/content/tasks.py`), keeping each task's `bind=True` and retry options.
- [X] T042 [US4] Add the "Maintenance window" section to `docs/runbooks/deploy-and-rollback.md`
  (research R7): when to use it (a migration that rewrites or locks a large table), the command in
  the host's `api` container, wait 60 s, deploy, check, off.

**Checkpoint**: US4's tests pass; M06's maintenance card shows the end time against the dev stack.

---

## Phase 7: User Story 5 - Offers appear only to the players they are meant for (Priority: P3)

**Goal**: `Offer` with validated rules, eligibility in `GET /v1/offers`, and the hourly expiry (spec
US5, FR-025–FR-028).

**Independent Test**: an offer for `remove_ads` with `country_in ["EG"]` and `days_since_install`
0–6 shows to an Egyptian player on day 2, not on day 8, not to a Saudi player; past its end it
disappears and the job marks it `expired` (quickstart §5).

### Tests for User Story 5 (write first, they must fail)

- [X] T043 [P] [US5] Write `backend/apps/liveops/tests/test_offer_rules.py` (contracts/offers.md):
  for each of `country_in`, `days_since_install`, `payer`, `owns_product`, `lacks_product`,
  `chapter_reached`, one player who meets it and one who doesn't (`payer` and the two product rules
  with a stubbed `PlayerFacts`, and once with the shipped "no purchases" facts); a blank country never
  matches; day 0 is the Cairo install day; validation refuses an unknown `rule`, a missing or extra
  field and a wrong type, naming the position and the rule.
- [X] T044 [P] [US5] Write `backend/apps/liveops/tests/test_offers_listing.py` (FR-025–FR-027): an
  offer is listed only for `starts_at ≤ now < ends_at` (null end = open), only when its product is
  active on the platform, never to the owner of its non-consumable product; order by `priority`
  descending then `starts_at`; past `ends_at` it is gone before the job runs; `expire_offers` sets
  `scheduled` → `active` and → `expired`; the check constraint "`ends_at IS NULL OR ends_at >
  starts_at`" holds; no offer is seeded.

### Implementation for User Story 5

- [X] T045 [US5] Add `Offer` to `backend/apps/liveops/models.py` (data-model.md: `offer_id` slug
  unique; `kind` ∈ `starter` | `sale` | `season_pass` | `other`; `product` FK `StoreProduct`
  `PROTECT`; `starts_at`; `ends_at` null; `priority` small integer; `rules` JSON list; `status` ∈
  `scheduled` | `active` | `expired`; `created_at`, `updated_at`; index `(status, starts_at)`; the
  check constraint) with migration `0005_offers.py`, which gives `live_ops` view, add and change on
  `Offer`.
- [X] T046 [US5] Write `backend/apps/liveops/services/facts.py` (`PlayerFacts` from one player query
  and one `progress.StoryState` query; `has_purchase` false and `entitlements` empty until B06, in one
  function B06 replaces) and `backend/apps/liveops/services/offers.py` (one validator and one
  evaluator per rule, `save_offer` writing an `offer` change, `eligible_offers(player, platform)` over
  the per-process snapshot). Wire it into the `GET /v1/offers` view of T033.
- [X] T047 [US5] Write `liveops.tasks.expire_offers` (`bind=True`, retries on `OperationalError`,
  wrapped by `skip_in_maintenance`) and its hourly schedule in
  `backend/apps/liveops/migrations/0006_offer_schedule.py` (the pattern of
  `backend/apps/economy/migrations/0003_prune_schedule.py`).
- [X] T048 [US5] Add the Offers admin (contracts/admin.md), saving through `offers.save_offer`, with
  the rules field validated and its errors shown per rule; history inline.

**Checkpoint**: all five stories pass their tests.

---

## Phase 8: The Remote Config drift check (spec FR-009)

**Purpose**: the daily comparison with Remote Config's defaults, the admin's drift mark and the
Sentry warning (research R8). It serves US1's operator but needs nothing from the other stories.

### Tests for the drift check (write first, they must fail)

- [X] T049 [P] Write `backend/apps/liveops/tests/test_remote_config.py` with a fixture replacing
  `remote_config.fetch_token` and `remote_config.fetch_template`:
  - the signed JWT (a test RSA key) has the service account's `client_email` as `iss`, the scope
    `https://www.googleapis.com/auth/firebase.remoteconfig`, audience
    `https://oauth2.googleapis.com/token`, and a lifetime ≤ 1 hour;
  - equal defaults → an `ok` row; a template `fuel_max` of 6 against 5 → a `drift` row naming it and
    one Sentry `capture_message` at `warning` with fingerprint `["liveops", "remote-config-drift"]`;
    a phone-only drift (`trip_hop_ms_line_hay`) → `drift` row, a log warning, no Sentry event;
  - an absent parameter or `useInAppDefault` compares the bundled default; conditional values are
    ignored;
  - a network error retries, then records `unreachable`, and the admin keeps the previous drift marks;
  - both variables empty → `not_configured` and no network call;
  - rows older than 90 days are deleted by the run;
  - no log line or Sentry event contains the key's `private_key_id`, its `private_key` or the access
    token (contracts/environment.md).

### Implementation for the drift check

- [X] T050 Add `RemoteConfigCheck` to `backend/apps/liveops/models.py` (data-model.md: `ran_at`
  indexed; `status` ∈ `ok` | `drift` | `unreachable` | `not_configured`; `template_version`
  varchar(32) blank; `drift` JSON list of `{"key", "server", "remote_config", "applied_by"}`) in
  migration `0007_remote_config_check.py`, which gives `live_ops` view on `RemoteConfigCheck`.
- [X] T051 Write `backend/apps/liveops/services/remote_config.py` (research R8: the JWT with PyJWT,
  the token exchange and the template GET with `requests`, 10 s timeouts, errors that name only the
  step and the HTTP status; the comparison) and `liveops.tasks.check_remote_config` (`bind=True`,
  `autoretry_for=(requests.RequestException,)`, `retry_backoff=True`, `max_retries=3`, **not**
  wrapped by `skip_in_maintenance`) with its daily 05:15 Cairo schedule in
  `0008_remote_config_schedule.py`.
- [X] T052 Show the drift in the settings changelist (T021) from the latest `ok` or `drift` row, and
  register `RemoteConfigCheck` read-only in the admin.

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: the contract, performance, the docs, the review and the live checks.

- [X] T053 [P] Regenerate `contracts/openapi.yaml`
  (`uv run manage.py spectacular --file ../contracts/openapi.yaml --validate --fail-on-warn`) and
  extend `backend/tests/test_contract.py`: `GET /v1/offers` conforms, and the 426 and 503 answers are
  documented on every default endpoint.
- [X] T054 [P] Extend `backend/tools/sync_load.py` with an offers scenario and record p50/p95 for
  `GET /v1/offers`, bootstrap and a 100-op batch (research R16; never in CI).
- [X] T055 [P] Update `docs/architecture-backend.md` (plan "Post-design re-check"): §6.4 bootstrap's
  `client` source; §6.5 426 live and who is exempt; §8.1 the pack amounts and grants as typed
  columns; §11.2 `check_remote_config` and `expire_offers` (and the job skip); §11.4 the five rules;
  §12 the `liveops` models as built; §15 the maintenance row (admin and command, writes only, jobs
  skip); §22.10 resolved (60 / 300 + 30 / 800 + 120). Mirror the §6 changes in
  `specs/002-b01-backend-skeleton/contracts/api.md` where it lists codes.
- [X] T056 [P] Update `docs/architecture-mobile.md` §14.3: the server-only numbers are live settings
  (their new lowercase keys), the phone keys' server copies and the daily drift check; §15.2: the shop
  reads amounts from `GET /v1/offers`.
- [X] T057 [P] Update `specs/010-b03-ledger-sync/contracts/environment.md` (the retired variables
  point to `specs/016-b10-catalog-offers/contracts/environment.md`) and mark the Complexity Tracking
  entries of `specs/004-m01-trip-engine/plan.md` and `specs/010-b03-ledger-sync/plan.md` "closed by
  B10 (016)".
- [X] T058 [P] Write `docs/runbooks/live-ops.md` (new) and link it from `docs/runbooks/README.md`:
  changing a setting and reading its history; which settings need the same change in Remote Config
  (`applied_by: both`) and in what order (server first when raising a cap, phone first when lowering
  it); the drift check and its Sentry alert; raising a minimum version with the preview; products and
  offers; maintenance. Add the Firebase secret to `docs/runbooks/monitoring-setup.md`.
- [X] T059 [P] Update `backend/CLAUDE.md`: B10 in "What's built"; the `maintenance` command in the
  commands table; the environment line (three new variables, the retired ones); the rules "every
  balancing number is a live setting in `apps/liveops/registry.py`" and "a scheduled job that writes
  uses `skip_in_maintenance`". In the root `CLAUDE.md`, add 016 B10 to the features list.
- [X] T060 [P] Update `docs/delivery-plan.md`: record under B10 that backend §22.10 and HANDOFF §9.3
  #8 (`details.until`) are resolved, add research's "Handed to later features" to the B06, B07, B08,
  B11, B12, B14, M11 and M12 entries, and tick `016-b10-catalog-offers` in Progress after merge.
- [X] T061 Add B10's section to `docs/owner-actions.md` and keep "Open now" current (T066–T069).
- [X] T062 Run the full gates in `backend/`: `uv run ruff check . && uv run ruff format --check .`,
  `uv run mypy .`, `uv run manage.py makemigrations --check --dry-run`,
  `uv run pytest -n 4 --cov --cov-fail-under=80`, the OpenAPI drift check, and confirm 100% line
  coverage of `apps/liveops/services/` and `apps/liveops/permissions.py`. Fix what fails.
- [X] T063 Run the thorough economy property pass once (the economy's settings changed):
  `HYPOTHESIS_PROFILE=thorough uv run pytest apps/economy/tests/test_properties.py`; record the result
  in the PR.
- [X] T064 Security review: run the **security-reviewer** agent over `apps/liveops`, the permission
  changes in `config/settings/base.py`, and the `economy`, `accounts` and `content` edits. Fix every
  CRITICAL and HIGH finding. Cover at least: the permission order and exemptions, that admin forms
  can't bypass the services, the command's actor check, the service account key's handling, and that
  `GET /v1/offers` leaks nothing about other players.
- [X] T065 Walk quickstart §1–§5 and §7 end to end on a clean dev stack and fix any step that doesn't
  match, in the document or the code.
- [X] T066 **Owner, before merge.** In Google Cloud project `wassal-ogra`, create a service account
  with only the "Firebase Remote Config Viewer" role, one key per host; store each as
  `REMOTE_CONFIG_SERVICE_ACCOUNT` with `FIREBASE_PROJECT_ID=wassal-ogra` in the staging and
  production env files (`docs/runbooks/monitoring-setup.md`). Without it the check reports
  `not_configured` and nothing fails, so this can also follow the merge.
- [X] T067 **Owner, after merge.** In Sentry, add an alert rule that emails on the fingerprint
  `liveops` / `remote-config-drift` for both environments.
- [ ] T068 **Owner, after merge.** Create the `live_ops` members on both hosts
  (`create_staff <name> --group live_ops`), then run quickstart §1–§4 and §6 on staging; on
  production check that every setting shows its default (or the imported value) and that the deploy
  log has no `liveops.W001` (or remove the named lines from the env file).
- [ ] T069 **Owner, before M12.** In Play Console, create the in-app products `bonat_pack_s`,
  `bonat_pack_m`, `bonat_pack_l` (consumable) and `remove_ads` (non-consumable) with their price
  tiers; the smallest pack priced for mobile-balance payment (product spec «المشتريات»).

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (Phase 1)** → **Foundational (Phase 2)** → the stories.
- **US1 (Phase 3)** needs Phase 2. It is the MVP: the constitution VIII exceptions close here.
- **US2 (Phase 4)** needs Phase 2 and T018–T019 of US1 (the client block moved off env).
- **US3 (Phase 5)** needs Phase 2 only.
- **US4 (Phase 6)** needs Phase 2; T038 needs T025's position in the permission list.
- **US5 (Phase 7)** needs US3 (products and the offers view).
- **Drift check (Phase 8)** needs Phase 2 and T021 (the changelist).
- **Polish (Phase 9)** needs everything it documents.

### Within phases

- Tests first, failing, then models, services, views and admin.
- Every migration in `apps/liveops/migrations/` is numbered in the order written above; renumber if
  phases are done in another order, before the PR.

### Parallel opportunities

- T002 and T003 in Setup.
- T004–T007 (foundational tests) together.
- Each story's test tasks together; US3 and US4 can be built in parallel after US1, by different
  people, since they touch different files (US4's T041 touches other apps' `tasks.py` only).
- T053–T060 in Polish.

---

## Parallel Example: Foundational tests

```text
Task: "T004 test_registry.py"
Task: "T005 test_snapshot.py"
Task: "T006 test_changes.py"
Task: "T007 test_migrations.py"
```

## Parallel Example: User Story 4 tests

```text
Task: "T035 test_maintenance.py"
Task: "T036 test_maintenance_command.py"
Task: "T037 test_scheduled_jobs.py"
```

---

## Implementation Strategy

### MVP first (User Story 1)

1. Phases 1–2, then US1.
2. Stop and check: B03's whole suite passes on live settings, and quickstart §1 works.

### Incremental delivery (still one PR)

1. US2 (the gate, which M06 already waits for).
2. US3 and US4 (the catalog for B06/M12; maintenance).
3. US5, then the drift check.
4. Polish, the review, then the owner tasks.

## Notes

- [P] tasks touch different files and depend on nothing incomplete.
- Commit after each task or logical group.
- Never write a balance here: B10 defines grants, B06 applies them through `apps.economy.services.ledger`.

## Phase 10: Review fixes (round 1)

Tasks from `reviews/round-1.md`. Each finding's failure scenario and evidence is there.

- [x] T070 [R1-1] Fix the add forms in `backend/apps/liveops/admin.py` (`StoreProductForm.__init__`, `OfferForm.__init__`): both test `self.instance.pk`, which a new `UUIDv7Model` already has, so `GET /admin/liveops/offer/add/` answers 500 (`RelatedObjectDoesNotExist`) and a new product's `product_id` is disabled and can't be submitted. Use `self.instance._state.adding`. Add admin-client tests in `backend/apps/liveops/tests/` that add and edit a product and an offer as a `live_ops` member, and that an offer with `{"rule": "vip"}` is refused naming `vip`; they fail before the fix. (HIGH, per US5 AS4, FR-025, T034, T048)
- [x] T071 [R1-2] Stop the product form crashing on an invalid amount in `backend/apps/liveops/admin.py` (`StoreProductForm.clean`) and `backend/apps/liveops/services/catalog.py` (`check_product`): when `bonat` or `bonus_bonat` failed field validation, `clean()` passes `None` and `int(None)` raises `TypeError` (500). Skip `check_product` when its fields already have errors, or refuse `None` with a `ValueError`, so the operator sees a form error. Add admin-client tests saving −5 and `abc` as BONAT that expect a 200 with the error and no change. (HIGH, per US3 AS4)
- [x] T072 [R1-3] Authorize live-ops admin writes by the right permission in `backend/apps/liveops/admin.py`. Today `reset_to_default` has no `allowed_permissions`, `versions_view` saves a new minimum under `has_view_permission`, and the generic `LiveSetting` change form edits `maintenance_enabled`/`maintenance_until` without `liveops.switch_maintenance`. After the fix: the action needs `change`; the versions page's confirming POST needs `has_change_permission`; the two `maintenance_*` rows can't be changed from the generic form or the action unless the user has `liveops.switch_maintenance` (point them to the Maintenance page). Add tests with a staff user holding only `view_livesetting` and one holding `change_livesetting` without `switch_maintenance`: each attempt is refused (403 or no change). Also extend the 403 test so a `player_support` and a `content_author` member are refused on the products, offers, maintenance and versions pages. (HIGH, per FR-010, FR-033, contracts/admin.md)
- [x] T073 [R1-4] Make a sync batch read the live settings once in `backend/apps/accounts/services/names.py` (`validate_display_name`), `backend/apps/content/services/lookups.py` (`supported`), and their callers `backend/apps/economy/services/ops/profile.py` and `backend/apps/economy/services/batch.py` (`version_status`). Today both call `live.current()` inside the batch, while `EconomySettings` already carries `name_min_length`, `name_max_length` and `content_max_age_days`. Pass the batch's values in, keeping a `live.current()` default for callers outside a batch. Extend `test_a_batch_reads_one_snapshot` in `backend/apps/economy/tests/test_live_economy_settings.py` with a `settings_update` carrying a display name and a `trip_start` on an older, still-supported published pack, asserting one snapshot read; it fails before the fix. (HIGH, per FR-007)
- [x] T074 [R1-5] Revive `unused` rows whose key is back in the registry in `backend/apps/liveops/seed.py` (`sync_registry_rows`): today the `update(unused=False)` only touches rows it just created, so after a rollback and redeploy (or a key dropped and re-added) the saved value is silently ignored for the code default and the row is hidden in the admin. After the fix every registry key's row has `unused=False`, its value is kept, and only keys missing from the registry are marked `unused`. Add a test in `backend/apps/liveops/tests/test_migrations.py` that marks a non-default row `unused`, runs the hook, and asserts the flag is cleared and `live.current()` returns the saved value. (HIGH, per research R2, FR-005)
- [x] T075 [R1-6] Build the wallet index concurrently in `backend/apps/economy/migrations/0004_wallet_last_active_index.py`: it uses `migrations.AddIndex` (a plain `CREATE INDEX` that locks `economy_wallet` while the previous release serves) although T027 and its docstring say concurrent. Use `django.contrib.postgres.operations.AddIndexConcurrently` with `atomic = False`, and confirm `uv run manage.py makemigrations --check --dry-run` stays clean and `test_migrations` passes. (HIGH, per T027, backend/CLAUDE.md expand/contract)

## Phase 11: Review fixes (round 2)

Tasks from `reviews/round-2.md`. Each finding's failure scenario and evidence is there.

- [x] T076 [R2-1] Cover `_amount`'s non-numeric branch in `backend/apps/liveops/tests/test_catalog.py`. `backend/apps/liveops/services/catalog.py:138-139` (the `except (TypeError, ValueError)` that T071 added) never runs, so `liveops/services/` sits at 97% against T062's 100% bar. Add a non-numeric amount case (for example `{"bonat": "abc"}`) to `test_the_save_validates_the_platforms_and_the_amounts`, expecting "whole number". Then confirm with `uv run pytest -n 4 --cov --cov-fail-under=80` that every file under `apps/liveops/services/` and `apps/liveops/permissions.py` is at 100%. (HIGH, per T062)
