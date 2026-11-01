# Data Model: Live-ops Settings, Store Catalog and Offers (B10)

New app `apps/liveops`. UUIDv7 primary keys (`common.E001`), expand-only migrations. Every write
goes through `apps/liveops/services/`, which writes the `LiveopsChange` row in the same
transaction (research R14).

## LiveSetting

One row per registry key (research R2). Type, range and meaning live in the registry, not here.

| Field | Type | Notes |
| --- | --- | --- |
| `id` | UUIDv7 | |
| `key` | varchar(64), unique | a registry key (contracts/settings.md) |
| `value` | JSON | typed by the registry; validated before save |
| `unused` | bool, default false | set by the post-migrate hook when the registry no longer has the key |
| `updated_by` | FK `accounts.User`, null | null for the seed and the env import |
| `updated_at` | datetime | |

- Created by `0002_seed` with each default (or the imported env value, R5); keys added later are
  created by the post-migrate hook.
- Never deleted. `unused` rows are hidden from the admin's default list and never read.

## LiveopsChange (append-only)

| Field | Type | Notes |
| --- | --- | --- |
| `id` | UUIDv7 | |
| `target` | `setting` \| `product` \| `offer` | |
| `key` | varchar(64) | the setting key, `product_id` or `offer_id` |
| `old` | JSON, null | null on create |
| `new` | JSON | the whole new value or row (products and offers: their fields) |
| `source` | `admin` \| `command` \| `import` \| `reset` | |
| `actor` | FK `accounts.User`, null, `on_delete=PROTECT` | null only for `import` |
| `note` | varchar(500), blank | |
| `at` | datetime, indexed with `(target, key)` | |

- No update or delete path: the admin registers it read-only, the model's `save` refuses an existing
  pk, and no group has `change_` or `delete_` on it (a test checks, as B03's `WalletAdjustment`).

## StoreProduct

| Field | Type | Notes |
| --- | --- | --- |
| `id` | UUIDv7 | |
| `product_id` | varchar(48), unique | glossary §3.5; the form allows only the known ids |
| `kind` | `consumable` \| `non_consumable` \| `subscription` | `subscription` unused in the MVP |
| `platforms` | array of `android` \| `ios`, non-empty | |
| `bonat` | positive integer, default 0 | |
| `bonus_bonat` | positive integer, default 0 | shown as «+N هدية» |
| `entitlement` | varchar(32), blank | `remove_ads` in the MVP |
| `best_value` | bool | «أوفر كيس» |
| `display_order` | small integer | |
| `active` | bool | |
| `updated_at` | datetime | |

Constraints:

- `consumable` ⇒ `bonat > 0` and `entitlement = ''`.
- `non_consumable` ⇒ `entitlement <> ''` and `bonat = 0` and `bonus_bonat = 0` (widened by B12 for
  `starter_pack`).
- Partial unique index: at most one row with `active AND best_value`.
- No price column, ever (FR-021).

Seed (`0004_products`, both platforms, active):

| `product_id` | kind | `bonat` | `bonus_bonat` | `entitlement` | `best_value` | order |
| --- | --- | --- | --- | --- | --- | --- |
| `bonat_pack_s` | consumable | 60 | 0 | | no | 1 |
| `bonat_pack_m` | consumable | 300 | 30 | | no | 2 |
| `bonat_pack_l` | consumable | 800 | 120 | | yes | 3 |
| `remove_ads` | non_consumable | 0 | 0 | `remove_ads` | no | 4 |

## Offer

| Field | Type | Notes |
| --- | --- | --- |
| `id` | UUIDv7 | |
| `offer_id` | slug, unique | |
| `kind` | `starter` \| `sale` \| `season_pass` \| `other` | |
| `product` | FK `StoreProduct`, `PROTECT` | |
| `starts_at` | datetime | |
| `ends_at` | datetime, null | null = open-ended |
| `priority` | small integer | higher first |
| `rules` | JSON list | contracts/offers.md; validated on save |
| `status` | `scheduled` \| `active` \| `expired` | informational; listing uses the times |
| `created_at`, `updated_at` | datetime | |

- Check constraint: `ends_at IS NULL OR ends_at > starts_at`.
- Index on `(status, starts_at)`.
- State: `scheduled` → `active` when `starts_at` passes (set by the hourly job), → `expired` when
  `ends_at` passes. An operator may end an offer early by setting `ends_at` to now.
- No offer is seeded (FR-028).

## RemoteConfigCheck

One row per run of the daily check (research R8).

| Field | Type | Notes |
| --- | --- | --- |
| `id` | UUIDv7 | |
| `ran_at` | datetime, indexed | |
| `status` | `ok` \| `drift` \| `unreachable` \| `not_configured` | |
| `template_version` | varchar(32), blank | Remote Config's version number |
| `drift` | JSON list | `[{"key", "server", "remote_config", "applied_by"}]` |

- The admin's drift column reads the latest row whose status is `ok` or `drift`.
- Rows older than 90 days are deleted by the same task.

## Changes to existing tables

| Table | Change |
| --- | --- |
| `economy.Wallet` | index on `last_active_at` (the 7-day version counts, R10) |
| `accounts.Player` | none; bootstrap now also writes `platform` and `client_version` when they differ (R10) |
| `django_celery_beat` | `liveops.check_remote_config` (daily 05:15 Cairo), `liveops.expire_offers` (hourly) |
| `auth.Group` | `live_ops` with the permissions of research R14 |
