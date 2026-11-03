# Data Model: Ads — AdMob SSV Callback, Reward Polling and Caps (B07)

One new table in a new app, three live-setting rows, one sync operation. No change to existing
tables. Migrations are expand-only.

## `ads.AdReward` (table `ads_adreward`)

One validly signed AdMob callback (spec "Key Entities"; research R4, R5, R12). Rows are written
once; only `shown_at` is ever set afterwards, and only rows that granted nothing are ever deleted.

| Field | Type | Rules |
| --- | --- | --- |
| `id` | UUIDv7 PK | `UUIDv7Model`; the ledger entries' `ref_id` |
| `transaction_id` | `CharField(128)` | **unique**; AdMob's id, the idempotency key (constitution VI) |
| `player` | FK `accounts.Player`, null, `PROTECT` | null when unattributed |
| `placement` | `CharField(32)`, blank | from `custom_data`; blank when malformed |
| `nonce` | `UUIDField`, null | the app's reference; **unique where not null**; null for `duplicate_reference` and `malformed` |
| `custom_data` | `CharField(512)`, blank | the raw value, kept for staff (holds no personal data: placement and reference) |
| `ad_network` | `CharField(32)`, blank | as sent |
| `ad_unit` | `CharField(64)`, blank | as sent |
| `reward_amount` | `IntegerField` | as sent; recorded, never used for the amount (FR-011) |
| `reward_item` | `CharField(64)`, blank | as sent |
| `key_id` | `BigIntegerField` | the verifier key that signed it |
| `callback_at` | `DateTimeField`, null | AdMob's `timestamp` (ms → UTC); used only for `expired` |
| `outcome` | `CharField(24)`, choices | `granted`, `duplicate_reference`, `cap_reached`, `not_server_placement`, `malformed`, `expired`, `unattributed` |
| `jenehat` | `PositiveIntegerField`, default 0 | granted amount; 0 unless `granted` |
| `bonat` | `PositiveIntegerField`, default 0 | granted amount; 0 unless `granted` |
| `game_date` | `DateField` | `gameday.game_date(processed time)` (FR-012) |
| `created_at` | `DateTimeField` | processing time |
| `shown_at` | `DateTimeField`, null | set once by `ad_reward_seen`; only for `granted` |

### Constraints

- `ad_reward_transaction_once`: unique(`transaction_id`).
- `ad_reward_nonce_once`: unique(`nonce`) where `nonce IS NOT NULL`.
- `ad_reward_amounts_only_when_granted`: check `outcome = 'granted' OR (jenehat = 0 AND bonat = 0)`.
- `ad_reward_granted_has_player`: check `outcome <> 'granted' OR player_id IS NOT NULL`.
- `ad_reward_shown_only_when_granted`: check `shown_at IS NULL OR outcome = 'granted'`.

### Indexes

- `ad_reward_daily_cap`: (`player`, `placement`, `game_date`) where `outcome = 'granted'` — the cap
  count and bootstrap's `available`.
- `ad_reward_unseen`: (`player`, `created_at`) where `outcome = 'granted' AND shown_at IS NULL` —
  bootstrap's `unseen` and the seen op's load.
- `ad_reward_prune`: (`created_at`) where `outcome <> 'granted'` — the daily cleanup.

**Queryset guard** (`AdRewardQuerySet`): `update()` accepts only `shown_at`; `delete()` refuses
when any selected row is `granted`. `save()` on an existing row refuses changes to any field but
`shown_at`.

**Outcome decision order** (research R4): no usable `transaction_id` (missing or over 128
characters: 200, logged `malformed`, **no row**) → duplicate `transaction_id` (no new row) →
`malformed` (missing, unparseable or over-long field) → `expired` (a parsed `timestamp` more than
7 days old) → `unattributed` → `not_server_placement` → (wallet lock) → `duplicate_reference` →
`cap_reached` → `granted`.

**Malformed input is stored, never rejected by the database:** text values are cut to their column
length (`custom_data` 512, `ad_unit` 64, `reward_item` 64, `ad_network` 32), an unparseable
`reward_amount` is stored as 0 and an unparseable `timestamp` as `callback_at = NULL`, so a signed
callback can never answer 500.

**Relationships**: Player 1 — 0..n AdReward. A `granted` row has one or two `LedgerEntry` rows with
`reason = ssv_grant`, `source = ssv`, `ref_type = "ad_reward"`, `ref_id = AdReward.id` (one per
non-zero amount). No FK from the reward to the ledger: two currencies make two entries, and the
ledger is the record of value.

### Lifecycle

```text
validly signed callback ──► row written with its outcome
granted ──► (ad_reward_seen) shown_at set ──► kept with the ledger
any other outcome ──► deleted 90 days after created_at (daily job, skipped in maintenance)
```

## Live settings (`apps/liveops/registry.py`)

| Key | Kind | Default | Range | Applied by | Notes |
| --- | --- | --- | --- | --- | --- |
| `ads_morning_piggy_daily_cap` | int | 1 | 0–10 | both | in `tunables.json` and mobile §14.3; needs a Remote Config key |
| `ads_morning_piggy_jenehat` | int | 30 | 0–10 000 | server | |
| `ads_morning_piggy_bonat` | int | 2 | 0–100 | server | |

Rule `morning_piggy_gives_something` over the two amounts: not both 0 (FR-013). Rows are created by
B10's `sync_registry_rows` after migrate.

## `BatchState` additions (`apps/economy/services/batch.py`)

| Member | Purpose |
| --- | --- |
| `_unseen_rewards: set[UUID] \| None` | lazily loaded: the player's `granted` references with `shown_at IS NULL` |
| `_seen_new: set[UUID]` | references marked in this batch |
| `mark_reward_seen(nonce) -> bool` | True when the reference was the player's and unseen; never a mutation |
| `_flush_seen()` | one `AdReward.objects.filter(player=…, nonce__in=…, shown_at__isnull=True).update(shown_at=now)` |

## Sync operation `ad_reward_seen`

| Field | Rule |
| --- | --- |
| `nonce` | UUID, required |

Always accepted, result `[]`; marks at most one row; doesn't move `state_version`. Payload hash and
`ProcessedOp` as for every operation.

## Ledger

No schema change. Uses the existing reason `ssv_grant` and source `ssv`; `ref_type` value
`ad_reward` is new (16 characters allowed).
