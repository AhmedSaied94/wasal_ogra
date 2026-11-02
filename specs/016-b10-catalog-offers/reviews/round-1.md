# Implementation review: 016-b10-catalog-offers, round 1

- Date: 2026-11-02 · Reviewer: Claude Code, Opus 5.5 (layer reviewers on Sonnet 5.5; every finding re-checked on Opus)
- Branch: 016-b10-catalog-offers · Base: origin/master (merge base dce3f64) · Head: 5a225f9, plus 115 uncommitted files
- Change: 1 commit, 126 files, +8884 −409
- Verdict: **CHANGES REQUESTED** · CRITICAL 0 · HIGH 6

## Checks

CI's `changes` job sets `backend=true` for this change set, which triggers `lint`, `types`, `test`, `contract`, `content-kit`, `solver`, `image` and `smoke`.

| Check | Command (in `backend/`) | Result |
| --- | --- | --- |
| Lint | `uv run ruff check .` | exit 0, all checks passed |
| Format | `uv run ruff format --check .` | exit 0, 392 files already formatted |
| Types | `uv run mypy .` | exit 0, no issues in 391 files |
| Tests + coverage | `uv run pytest -n 4 --cov --cov-fail-under=80` | exit 0, 2217 passed, total coverage 95.47%; `liveops/services/*` and `liveops/permissions.py` at 100% |
| Missing migrations | `uv run manage.py makemigrations --check --dry-run` | exit 0, no changes detected |
| OpenAPI drift | `uv run manage.py spectacular --file <tmp> --validate --fail-on-warn && diff -u ../contracts/openapi.yaml <tmp>` | exit 0 / exit 0, no diff |
| Economy property test, 10,000 examples | `HYPOTHESIS_PROFILE=thorough uv run pytest apps/economy/tests/test_properties.py` | exit 0, 1 passed in 780 s |
| Bypass scan (skip/xfail, new `noqa`/`type: ignore`, coverage/ruff/mypy config) | `git diff` of added lines | none found except the existing admin/form generics and two `S105` false positives; no config change; `economy/tests/test_tunables_parity.py` is replaced by the stricter `liveops/tests/test_tunables_parity.py` |
| `content-kit`, `solver` jobs | — | NOT RUN: no file under `tools/`, `content/`, `fixtures/` or `packages/` changed |
| `image`, `smoke` jobs | — | NOT RUN: these need the CI image build (ARM64) and the edge stack |
| Quickstart §1–§5 by hand | — | NOT RUN: walked through the code instead (see Requirements) |

## Findings

### HIGH

#### R1-1: Offers can't be created in the admin, and a new store product can't be added
- Layer: spec / ui-admin · Source: US5, FR-025, FR-026, US5 AS4; contracts/admin.md "Store products and Offers: list and form"; T034, T048 · Location: `backend/apps/liveops/admin.py:471`, `backend/apps/liveops/admin.py:400` · CONFIRMED
- Problem:
  - `UUIDv7Model.id` has `default=uuid7` (`apps/common/models.py:11`), so a new, unsaved `Offer()` or `StoreProduct()` already has a `pk`.
  - `OfferForm.__init__` checks `if self.instance.pk:` and then reads `self.instance.product.product_id`. On the add page there is no product.
  - `StoreProductForm.__init__` checks `if self.instance.pk:` and disables `product_id` on the add page too.
  - No test opens either admin page.
- Failure scenario:
  - `GET /admin/liveops/offer/add/` raises `RelatedObjectDoesNotExist` and answers 500, so the admin has no way to create an offer. The security reviewer reproduced this with a probe test.
  - Adding `starter_pack` (B12) shows a disabled, empty `product_id` field. The POST returns "This field is required." and nothing is saved.
- Fix direction:
  - Test `self.instance._state.adding`, not `pk`.
  - Add admin-client tests that add and edit a product and an offer, including a refused unknown rule.

#### R1-2: An invalid BONAT amount in the product form returns 500 instead of the refusal
- Layer: ui-admin · Source: US3 AS4 ("a BONAT amount must be a positive integer"); FR-023 · Location: `backend/apps/liveops/admin.py:403-409`, `backend/apps/liveops/services/catalog.py:123-124` · CONFIRMED
- Problem: `StoreProductForm.clean()` passes `cleaned.get(field)` for every field to `catalog.check_product`, which runs `int(values["bonat"])`. When `bonat` failed its own field validation (for example −5 on a `PositiveIntegerField`, or text), Django still calls `clean()`. The value is then `None`, and `int(None)` raises `TypeError`.
- Failure scenario: the operator types −5 into a pack's BONAT field and saves. They get a 500 page, not the form error.
- Fix direction:
  - Skip `check_product` when any of its fields already has an error, or make `check_product` refuse `None` with a `ValueError`.
  - Add an admin test with a negative and a non-numeric amount.

#### R1-3: Admin writes that change the live gate are authorized by the wrong permission
- Layer: security / admin · Source: FR-010, FR-033, contracts/admin.md (separate view/change permissions, and `liveops.switch_maintenance` for maintenance); plan "Security & privacy" ("admin forms can't bypass validation"); T064 · Location: `backend/apps/liveops/admin.py:209,358-368` (reset action), `:275,296-302` (versions page), `:370-379` with `:70-100` (generic setting form) · CONFIRMED (probe tests)
- Problem:
  - `reset_to_default` has no `allowed_permissions`, so anyone who can see the changelist can run it.
  - `versions_view` checks only `has_view_permission`, then confirms a new `min_client_version_<platform>`.
  - `maintenance_enabled` and `maintenance_until` can be edited through the generic `LiveSetting` change form with only `change_livesetting`. That gets around the `switch_maintenance` check that the Maintenance page (`admin.py:320`) and the command both make.
- Failure scenarios (each reproduced by the security reviewer):
  - Staff with only `view_livesetting` POSTs `platform=android&minimum=1.5.0&confirm=1` to the versions page. Every Android app below 1.5.0 now gets 426.
  - The same user resets `maintenance_enabled` or a minimum version through the action.
  - Staff with `change_livesetting` but not `switch_maintenance` sets `maintenance_enabled` to on from its change page, and every player write answers 503.
  - Today only the `live_ops` group holds these permissions, and it holds all of them, so this becomes reachable as soon as anyone grants a subset (for example a view-only role).
- Fix direction:
  - Give the action `allowed_permissions=("change",)`.
  - Require `has_change_permission` on the versions page's confirming POST.
  - Make the two `maintenance_*` rows read-only in `LiveSettingAdmin` (no change permission on them) unless the user has `liveops.switch_maintenance`, so they are switched only through `maintenance.switch`.
  - Add tests with a view-only user and a change-only user.

#### R1-4: A sync batch reads the live settings more than once (FR-007)
- Layer: economy · Source: FR-007 (P1, US1), spec edge case "A setting changed in the middle of a sync batch", research R4, T015 · Location: `backend/apps/accounts/services/names.py:76`, `backend/apps/content/services/lookups.py:307` · CONFIRMED
- Problem:
  - `process_batch` takes one snapshot (`economy/services/sync.py:191`, `config = settings.current()`).
  - Inside the batch's locked transaction, two paths call `live.current()` again:
    - `validate_display_name`, reached from `ops/profile.py:57` (`settings_update` with a name);
    - `lookups.supported`, reached through `Batch.version_status` (`batch.py:219-221`) for any content version that is not the current one, which is the normal case for 45 days after each publish.
  - `EconomySettings` already carries `name_min_length`, `name_max_length` and `content_max_age_days`, but nothing reads them.
  - `test_a_batch_reads_one_snapshot` (`economy/tests/test_live_economy_settings.py:48-66`) only sends `trip_start` on the current pack. That returns before line 307, so the test can't see either read.
- Failure scenario:
  1. A batch starts on snapshot A.
  2. The process's 30 s snapshot ages out (or another thread's `on_commit` refresh lands) before a `settings_update` or an older-pack `trip_start`.
  3. That op is judged against snapshot B, while fuel and flags use A. The refresh also runs its query inside the `FOR UPDATE` transaction.
- Fix direction:
  - Pass the batch's `EconomySettings` values into `validate_display_name` and `lookups.supported` (keep a `live.current()` default for callers outside a batch).
  - Extend the test with a `settings_update` carrying a name and a `trip_start` on an older published pack, still asserting one read.

#### R1-5: A setting row marked `unused` is never revived, so a saved value silently reverts to its code default
- Layer: db / economy · Source: research R2, spec edge case "A deploy whose code adds a setting", FR-005 / FR-001 (a saved value applies), spec edge case "never falls back silently to code defaults while a different value is saved" · Location: `backend/apps/liveops/seed.py:97` · CONFIRMED
- Problem:
  - `LiveSetting.objects.filter(key__in=[spec.key for spec in missing]).update(unused=False)` only touches rows the hook has just created. Those rows are already `unused=False`.
  - A row that was marked `unused` and whose key is back in the registry keeps `unused=True`.
  - `_load_settings` (`settings.py:150`) and the admin queryset (`admin.py:212`) both skip `unused` rows.
- Failure scenario:
  1. A later release (for example B07) adds key `K`, and the operator tunes it.
  2. A rollback, which is a deploy of the older tag and runs `migrate` (`docs/runbooks/deploy-and-rollback.md`), marks `K` unused.
  3. Re-deploying B07 leaves the flag set.
  4. Every process now applies `K`'s code default with no warning, and the row has disappeared from the admin.
  - The same happens when a key is dropped and later re-added.
- Fix direction:
  - Clear `unused` on every row whose key is in the registry: `filter(key__in=list(registry.SPECS), unused=True).update(unused=False)`.
  - Add a test that marks a non-default row unused, runs the hook, and asserts that the flag is cleared and `live.current()` returns the saved value.

#### R1-6: T027 is ticked, but the wallet index isn't built concurrently
- Layer: db · Source: T027 ("`AddIndexConcurrently`, `atomic = False`"); backend/CLAUDE.md "Migrations are expand/contract, so the previous release keeps working during a deploy" · Location: `backend/apps/economy/migrations/0004_wallet_last_active_index.py:2,13` · CONFIRMED
- Problem: the operation is `migrations.AddIndex(...)`, which runs a plain `CREATE INDEX` with a SHARE lock on `economy_wallet`. Its docstring says "concurrent, so a live table isn't locked", and `atomic = False` does nothing without the concurrent operation.
- Failure scenario: on production's migrate, which runs while the previous release still serves, every sync, bootstrap and ledger write that updates a wallet waits for the whole index build. That wait grows with the player count.
- Fix direction: use `django.contrib.postgres.operations.AddIndexConcurrently` (keeping `atomic = False`), and check that `makemigrations --check` stays clean.

## Requirements

| Requirement | Built in | Proven by | Status |
| --- | --- | --- | --- |
| FR-001 settings for every key | `liveops/registry.py` | `test_registry`, `test_tunables_parity` | built |
| FR-002 env reads retired | `economy/services/settings.py`, `names.py`, `lookups.py`, `config/env.py` | `tests/test_env`, `test_live_economy_settings` | built |
| FR-003 deployment settings kept | `config/env.py` | `tests/test_env`, `tests/test_settings_guards` | built |
| FR-004 types, ranges, rules | `registry.py` | `test_registry` | built |
| FR-005 applies within 60 s | `liveops/settings.py` `Cache` | `test_snapshot`, `test_live_economy_settings` | built |
| FR-006 history | `settings_admin.py`, `models.py` | `test_changes` | built |
| FR-007 one snapshot per batch | `sync.py:191` | `test_a_batch_reads_one_snapshot` | **wrong (R1-4)** |
| FR-008 tunables parity in CI | `liveops/tests/test_tunables_parity.py` | itself | built |
| FR-009 drift check | `services/remote_config.py`, `tasks.py` | `test_remote_config` | built |
| FR-010 `live_ops` only | migrations 0003–0007, admin | `test_admin_settings` (settings and history only) | **partly (R1-3)** |
| FR-011 env import | `migrations/0002_seed.py` | `test_env_import` | built |
| FR-012 bootstrap client block | `bootstrap.py` | `test_version_gate` | built |
| FR-013 426 elsewhere, exemptions | `permissions.py`, `base.py` | `test_version_gate` | built |
| FR-014 version comparison | `permissions.py` | `test_version_gate` | built |
| FR-015/016 503 maintenance, `until` | `permissions.py` | `test_maintenance` | built |
| FR-017 reads and sign-in during maintenance | default permissions | `test_maintenance` | built |
| FR-018 switch recorded | `services/maintenance.py` | `test_maintenance` | built |
| FR-019/020/021 catalog, seed, no price | `models.py`, `0004_products` | `test_catalog`, `test_offers_api` | built |
| FR-022 `grants_for` | `services/catalog.py` | `test_catalog` | built |
| FR-023 catalog history | `catalog.save_product` | `test_catalog` (service) | built (admin path R1-1, R1-2) |
| FR-024 `GET /v1/offers` | `liveops/api/views.py` | `test_offers_api` | built |
| FR-025/026 offers and rules | `services/offers.py` | `test_offers_listing`, `test_offer_rules` | built in services; **can't be created in admin (R1-1)** |
| FR-027 hourly expiry | `offers.expire`, `tasks.py`, 0006 | `test_offers_listing`, `test_scheduled_jobs` | built |
| FR-028 no offer seeded | — | `test_offers_listing` | built |
| FR-029 ad caps live | registry | `test_live_economy_settings` | built |
| FR-030 contracts and docs | `contracts/openapi.yaml`, docs | `tests/test_contract`, OpenAPI drift check | built |
| FR-031 player version recorded | `bootstrap._record_client` | `test_versions` | built |
| FR-032 versions page | `services/versions.py`, admin | `test_versions` | built (permission R1-3) |
| FR-033 maintenance command | `management/commands/maintenance.py`, runbook | `test_maintenance_command` | built |
| FR-034 jobs skip in maintenance | `liveops/tasks.py` + four task modules | `test_scheduled_jobs` | built |
| SC-001 under 2 min on staging | — | owner, T068 | not checkable here |
| SC-002 … SC-007 | as above | as above | built (SC-007: the Offer change page shows no history, below HIGH) |
| US1 AS1–AS5 | — | `test_snapshot`, `test_admin_settings`, `test_changes`, `test_migrations` | built |
| US1 AS6 no permission | admin | `test_admin_settings` | partly (R1-3; products and offers pages untested) |
| US2 AS1–AS6 | — | `test_version_gate`, `test_versions` | built |
| US3 AS1–AS3 | — | `test_offers_api`, `test_catalog` | built |
| US3 AS4 edit grants | admin + service | service tests | **partly (R1-1, R1-2)** |
| US4 AS1–AS3, AS5 | — | `test_maintenance` | built; AS4 has no callbacks yet (B06/B07) |
| US5 AS1–AS3 | — | `test_offers_listing`, `test_offer_rules` | built |
| US5 AS4 unknown rule refused on save | `OfferForm.clean_rules` | validator only | **partly (R1-1)** |

## Task audit

Ticked 65, verified 57, not done 1, partly done 7. T066–T069 are owner tasks and are correctly unticked.

| Task | Mismatch |
| --- | --- |
| T015 | Its test can't see the two extra reads (R1-4) |
| T017 | 403 is tested only on the settings and history pages (R1-3) |
| T027 | **Not done as written:** `AddIndex`, not `AddIndexConcurrently` (R1-6) |
| T034 | The product add form can't be submitted, and invalid amounts give 500 (R1-1, R1-2) |
| T048 | The Offer add page answers 500 (R1-1) |
| T054 | The offers scenario is in `tools/sync_load.py`, but no p50/p95 is recorded (below HIGH) |
| T064 | The security review missed the admin permission gaps (R1-3) |
| T062, T063, T065 | No artifact; this round reran T062's gates (all pass) and T063's property test (see Checks) |

## Outside this change

Nothing in the change set is outside the feature. Changes to `specs/002`, `specs/004` and `specs/010` close the plans' Complexity Tracking entries and point the retired variables here, as the plan says.

Below the bar, so not findings and no tasks; listed for the implementer's judgement:
- `HistoryMixin` picks `product_id` (the foreign-key UUID) for an Offer, so the Offer change page always says "No change yet" (`admin.py:58`).
- A non-string `status` in a `chapter_reached` rule raises `TypeError` (`offers.py:110`).
- The maintenance page's "Pick on or off." error is followed by the success redirect (`admin.py:339-345`).
- `remote_config.run` retries three times without delay, so the task's `retry_backoff` never fires.
- `catalog.grants_for` reads the 30 s snapshot. B06 should read the row fresh inside its grant transaction.
- One query per row for `last_change` and `drift_display` in the settings changelist.

## Not reviewed

- The CI `image` and `smoke` jobs, and quickstart §3–§4 on the phone, were not run.
- SC-001 (staging timing) and the Remote Config call against the real API (owner action T066) were not checked.
- Docs (T055–T061) were checked for presence and the points the plan lists, not proofread.
