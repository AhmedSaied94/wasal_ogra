# Data Model: Economy Ledger, Bootstrap and Sync (B03)

All primary keys are UUIDv7 (`UUIDv7Model`, checked by `common.E001`) unless a table's key is its
player. All amounts are integers: currencies and counts are `PositiveBigIntegerField` or
`BigIntegerField` for signed deltas, times are `DateTimeField` (UTC), and the fuel timeline is in
the same fields (milliseconds are computed, never stored as floats). Every table has `created_at`;
mutable ones have `updated_at`. Migrations only add tables and columns (expand-only).

## economy

### `Wallet`

One row per player. It is the row every batch locks.

| Field | Type | Notes |
| --- | --- | --- |
| `player` | OneToOne `accounts.Player`, primary key, `PROTECT` | |
| `jenehat` | `PositiveBigInteger`, default 0 | written only by `ledger.apply_entry` |
| `bonat` | `PositiveBigInteger`, default 0 | written only by `ledger.apply_entry` |
| `fuel` | `PositiveSmallInteger` | liters; starts at `fuel_max` |
| `fuel_updated_at` | datetime | M05's `countedFrom`: when the current countdown started, or when the tank last became full |
| `fuel_unlimited_until` | datetime, null | end of the unlimited window |
| `timeline_at` | datetime | the effective time of the last operation applied (research R7) |
| `state_version` | `PositiveInteger`, default 0 | +1 per batch that changed anything |
| `last_active_at` | datetime | last bootstrap, state or sync request (R13) |
| `session_started_at` | datetime | the current session's start |
| `comeback_return_at` | datetime, null | a return the player may claim a gift for (R13) |
| `created_at`, `updated_at` | | |

Constraints: `CHECK (jenehat >= 0)`, `CHECK (bonat >= 0)`, `CHECK (fuel >= 0)`. Created on first use
(bootstrap, state or sync) with `fuel` from `fuel_max`, both times and `timeline_at` at now, and
`state_version` 0 (spec FR-011).

### `LedgerEntry`

Append-only. `save()` refuses an update, and the manager refuses `update()` and `delete()`.

| Field | Type | Notes |
| --- | --- | --- |
| `player` | FK `Player`, `PROTECT` | |
| `currency` | `JENEHAT` \| `BONAT` | |
| `delta` | `BigInteger`, not 0 | signed |
| `balance_after` | `PositiveBigInteger` | the wallet's balance after this entry |
| `reason` | enum | backend §7.2 plus `request_reward`, `story_reward` |
| `ref_type` | varchar(16), blank | `trip`, `sku`, `request`, `room`, `chapter`, `adjustment`, … |
| `ref_id` | varchar(80), blank | an id or `client_txn_id`, as text |
| `op_id` | UUID, null | the `client_txn_id` of the operation. **Not a foreign key** (plan, post-design re-check): the processed-operation row is pruned, the ledger is not |
| `source` | `client_op` \| `purchase` \| `ssv` \| `system` \| `admin` | |
| `created_at` | datetime | |

Indexes: `(player, created_at)`, `(player, currency)`. Constraint: `CHECK (delta <> 0)`.

### `ProcessedOp`

| Field | Type | Notes |
| --- | --- | --- |
| `player` | FK `Player`, `PROTECT` | |
| `client_txn_id` | UUID | |
| `op_type` | varchar(40) | as sent, even if unknown |
| `payload_hash` | char(64) | sha256 of the canonical payload, to spot a changed repeat |
| `status` | `accepted` \| `rejected` | |
| `reason` | varchar(40), blank | the rejection reason |
| `result` | JSON | small: grants made (`{"jenehat": 46, "bonat": 0, "fuel": -1, "rooms": [...]}`), never the wallet |
| `processed_at` | datetime | |

Constraint: unique `(player, client_txn_id)`. Index: `processed_at` (the prune). Rows are pruned
after `SYNC_OP_RETENTION_DAYS` (R11).

### `Inventory`

`player` FK, `booster_id` (`change_bag`, `wake_all`, `ledger_peek`, `traffic_jam`), `count`
`PositiveInteger`. Unique `(player, booster_id)`.

### `PlayerFlag`

| Field | Type | Notes |
| --- | --- | --- |
| `player` | FK `Player`, `PROTECT` | |
| `kind` | enum | `fuel_overdraft`, `fast_three_star`, `trip_rate`, `txn_payload_mismatch`, `clock_clamped` |
| `game_date` | date | |
| `details` | JSON | ids and numbers only, with `count` (R8) |
| `reviewed_by` | FK `accounts.User`, null, `PROTECT` | |
| `reviewed_at` | datetime, null | |
| `resolution` | varchar(200), blank | |

Unique `(player, kind, game_date)`. Index: `(reviewed_at)` partial where null, for the open queue.

### `DayCounter`

`player`, `game_date`, `kind` (`overdraft`, `fuel_refill_ad`, `trips_started`), `count`
`PositiveInteger`. Unique `(player, game_date, kind)`. Pruned after 40 days.

### `GrantRecord`

Which one-time grants a player has had.

| Field | Type | Notes |
| --- | --- | --- |
| `player` | FK `Player`, `PROTECT` | |
| `kind` | `tutorial` \| `comeback` \| `request` \| `room` \| `chapter` | |
| `key` | varchar(80) | `""` for the tutorial; the return time (ISO, UTC) for a comeback; the request, room or chapter id |
| `op_id` | UUID, null | |
| `granted_at` | datetime | |

Unique `(player, kind, key)`. Index: `(player, kind, granted_at)` for the comeback cooldown.

### `WalletAdjustment`

Append-only record of a staff adjustment (R19): `actor` FK `accounts.User` (`PROTECT`), `player`,
`currency`, `delta`, `reason` (required, up to 200 characters), `ledger_entry` FK `LedgerEntry`
(`PROTECT`), `at`.

## progress

### `TripProgress`

`player`, `trip_id`, `best_stars` (0–3), `best_time_ms` (null), `plays`, `first_completed_at` (null).
Unique `(player, trip_id)`; `CHECK (best_stars BETWEEN 0 AND 3)`. `best_stars` and `best_time_ms`
are bests of *finished* results; `plays` counts every accepted result.

### `TripRun`

One played trip, kept 90 days (R12).

`player`, `trip_id`, `rev`, `start_op` (UUID of the start), `outcome` (`finished`, `failed`,
`abandoned`), `stars`, `fights`, `mistakes_count`, `earnings_jenehat`, `duration_ms`, `revived`,
`boosters_used` (JSON list), `command_log_hash` (char 64), `content_version`, `client_version`,
`created_at`. Indexes: `(created_at)`, `(player, created_at)`. Unique `(player, start_op)` (one
result per start).

### `TripSession`

One row per player: the open trip and the last result (mirrors M05's `trip_session`).

| Field | Type | Notes |
| --- | --- | --- |
| `player` | OneToOne, primary key | |
| `open_start` | UUID, null | the `client_txn_id` of the accepted start with no result |
| `open_trip_id`, `open_content_version`, `open_max_earnings`, `open_last_station_ms` | | copied from the pack at the start, so the result is checked against what the phone was shown |
| `open_started_at` | datetime, null | the effective time |
| `open_revived` | bool | |
| `open_traffic_jam_ads` | small int | |
| `last_start` | UUID, null | the start whose result came last |
| `last_outcome`, `last_earnings` | | for `result_double` |
| `last_doubled` | bool | |

### `Ownership`

`player`, `kind` (`vehicle`, `upgrade`, `cosmetic`, `item`, `chapter`), `sku_id`, `variant` (blank),
`acquired_at`, `acquired_by` (UUID). Unique `(player, kind, sku_id)`.

### `StoryState`

`player`, `chapter_id`, `status` (`open`, `completed`), `scenes_seen` (array of scene ids),
`completed_at` (null). Unique `(player, chapter_id)`. A row is created when a scene is recorded or a
chapter completes. Family requests claimed are `GrantRecord`s, not columns.

### `DailyState`

One row per player, created with the first bootstrap: `streak` 0, `longest_streak` 0,
`last_claim_game_date` (null), `task_counters` JSON `{}`, `tasks_game_date` (null). B03 reads it for
the stats; B08 and M13 write it.

## accounts (additions)

### `Player.settings`

A `JSONField(default=dict)` column on `Player` (expand-only). Written only by `settings_update`.

### `NameFilterEntry`

`term` (varchar 40), `normalized` (varchar 40, unique), `added_by` FK `accounts.User` (null for the
seed), `created_at`. `normalized` is computed on save by the shared normalizer (R10). The seed list
is inserted by a data migration.

## content (additions)

### `PackRulesIndex`

`pack` FK `ContentPack` (`CASCADE`), `version` (unique), `rules` JSON. Written by `index_pack`,
deleted with the other index rows when a version retires. `rules` shape (closed, written and read
by `lookups.py`):

```json
{
  "lines":    { "<line_id>": { "order": 1, "unlock": {"kind": "start"},
                               "trips": ["line_hay.01", "line_hay.02", "…"] } },
  "trips":    { "<trip_id>": { "line_id": "line_hay", "kind": "regular", "vehicle_id": "tuktuk" } },
  "vehicles": { "<vehicle_id>": { "starter": true } },
  "chapters": { "<chapter_id>": { "order": 1, "goal": {"kind": "complete_line", "line_id": "…"},
                                  "completion_bonat": 5, "story_trip_id": "",
                                  "scenes": ["the_stand", "…"] } },
  "rooms":    { "<room_id>": { "order": 1, "chapter_id": "…", "completion_bonat": 20,
                               "items": ["salon.nish", "…"] } },
  "items":    { "<item_id>": { "room_id": "…", "variants": ["classic", "…"] } },
  "requests": { "<request_id>": { "item_id": "…", "variant_id": "", "reward_bonat": 5 } }
}
```

A line's `trips` are in trip-number order (`line_hay.02` before `line_hay.10`), a room's `items` in
the items' `order`. `story_trip_id` and a request's `variant_id` are `""` when the content has none
(the rules document has no `null`). Written by `lookups.rules_document`.

`lookups.rules(version)` returns it or `None`; `lookups.supported(version)` implements the window
(R2). `CONTENT_INDEX_KEEP` (default 10) replaces B04's constant.

## The batch's in-memory state (not stored)

`BatchState` (`economy/services/batch.py`) is what handlers read and mutate during a batch. It
holds the locked `Wallet` (as plain values), dictionaries for the inventory, ownership, trip
progress, day counters, grants and story rows, the `TripSession`, the cached pack lookups per
version, and the lists of rows to write: ledger entries, processed operations, trip runs and flags.
`flush()` writes them (R5). It exists for one batch and holds no ORM objects after loading.

## State transitions

**Wallet currencies.** `balance' = balance + delta` through `apply_entry` only, never below 0.

**Fuel.** `regenerate`, `spend_one`, `fill_to_max`, `extend_unlimited` of contracts/fuel.md, applied
at the operation's effective time.

**Trip.**

```text
no open start ──trip_start (accepted)──▶ open start ──trip_result (accepted)──▶ no open start
                                            │  ▲                                  │
                  revive / in-trip ad / booster use (record on the open start)     └─ result_double (once)
                                            │
        a later trip_start closes it as abandoned (a TripRun with outcome abandoned, 0 stars, 0 earnings)
```

**Grants.** Each `GrantRecord` row is inserted once; the unique key makes a second insert a
rejection (`already_granted`).

**Comeback.** `comeback_return_at` is null → set at a bootstrap after a ≥ 7-day gap (and past the
cooldown) → kept after a claim, whose `GrantRecord(comeback, <return_at>)` marks it claimed → replaced
by a later return (research R9, R13).

## Migrations

- `economy/0001_economy`, `progress/0001_progress`: all the tables above.
- `accounts/00NN_player_settings_namefilter`: `Player.settings`, `NameFilterEntry`, the seed rows.
- `content/00NN_pack_rules_index`: `PackRulesIndex`. Existing published packs have no row until
  `content_index --rebuild` runs (a deploy step).
- `economy/0002_groups`: the `economy_ops` group and the added permissions of `player_support`
  (the pattern of B02's `0003_player_support_group`), and the custom permission
  `economy.adjust_wallet`.
- `economy/0003_prune_schedule`: the daily beat entry for `economy.tasks.prune`.

No migration touches an existing column's type or removes anything, so the previous release keeps
working during a deploy: it ignores the new tables, and the three endpoints don't exist in it.

## Volume

| Table | Rows per player-day | Retention | At 10k DAU |
| --- | --- | --- | --- |
| `ProcessedOp` | ~20 | 180 days | ~36M |
| `LedgerEntry` | ~6 | kept | ~60k a day |
| `TripRun` | ~15 | 90 days | ~13M |
| `PlayerFlag`, `DayCounter` | ≤ 3 | kept / 40 days | small |
| `TripProgress`, `Ownership`, `Inventory` | grows with progress, then flat | kept | ~100 per player at most |
