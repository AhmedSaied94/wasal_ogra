# Data Model: Local Economy (M05)

Phase 1 of [plan.md](./plan.md). Two layers:

- **Domain values**, pure Dart in `lib/core/economy/domain/`: what the rules compute.
- **Tables** of the app database, `<app support>/db/wassal.sqlite`, schema version 1, in
  `lib/core/storage/`.

Every amount, count and time is an integer (constitution II, FR-008). Times are UTC milliseconds
since the epoch, in trusted time ([research R9](./research.md#r9-trusted-time)). Identifiers are
the glossary's (§3) and content_models' generated enums.

## Domain values

### `EconomyState`

Everything the operations produce. Immutable. `apply(state, op)` returns a new one.

| Field | Type | Rule |
| --- | --- | --- |
| `jenehat` | `int` | ≥ 0 |
| `bonat` | `int` | ≥ 0. Rises only through a base from the server (FR-011). |
| `fuel` | `FuelState` | below |
| `inventory` | `Map<BoosterId, int>` | the four in-trip boosters only; each count ≥ 0 |
| `ownership` | `Map<OwnedKey, Owned>` | `OwnedKey = (SkuKind kind, String skuId)`, kind ∈ {`item`, `vehicle`, `chapter`} |
| `progress` | `Map<String, TripProgress>` | by `trip_id`. Entries the active pack lacks are kept (FR-034). |
| `unfinished` | `UnfinishedTrip?` | at most one (FR-031) |
| `lastResult` | `LastResult?` | the latest recorded result, for ×2 |

**New player** (FR-010): `jenehat = 0`, `bonat = 0`, `fuel = FuelState(liters: fuel_max,
countedFrom: <first open>, unlimitedUntil: null)`, everything else empty or null.

### `FuelState`

| Field | Type | Rule |
| --- | --- | --- |
| `liters` | `int` | ≥ 0. May exceed the maximum only when the maximum was lowered (FR-024). |
| `countedFromMs` | `int` | below the maximum: when the countdown to the next liter started; at or above it: when the tank last became full (backend §7.5's `fuel_updated_at`) |
| `unlimitedUntilMs` | `int?` | end of the unlimited-fuel window; null when none was bought |

The view adds `max`, `nextLiterAtMs` and `fullAtMs`, computed at read time (research R8).

### `TripProgress`

| Field | Type | Rule |
| --- | --- | --- |
| `bestStars` | `int` | 0–3, never decreases |
| `bestTimeMs` | `int?` | shortest `duration_ms` among finished runs; null until one finishes; never increases |
| `plays` | `int` | +1 per recorded result, any outcome |
| `firstCompletedAtMs` | `int?` | set by the first finished result, then fixed |

### `Owned`

`variantId` (`String?`, required for items, null otherwise), `acquiredAtMs`, `acquiredBy` (the
operation's `TxnId`).

### `UnfinishedTrip`

`startTxn`, `tripId`, `contentVersion`, `maxEarningsJenehat` (from the definition at start),
`startedAtMs`, `revived` (`bool`), `trafficJamAds` (`int`, 0 or 1).

### `LastResult`

`startTxn`, `outcome` (`TripOutcome`), `earningsJenehat`, `doubled` (`bool`).

### `TxnId`

A UUIDv7 in canonical lowercase form (research R10). A value type that refuses anything else.

### `OpRequest` → `Op`

A request is what a caller asks for (contracts/economy-api.md). Validating it against the state,
the content source, the tunables and trusted now either refuses it with an `EconomyRefusal` or yields
an `Op`. That is what is stored and applied:

| Field | Type | Notes |
| --- | --- | --- |
| `txnId` | `TxnId` | unique |
| `type` | `OpType` | `trip_start`, `trip_result`, `ad_reward`, `spend_jenehat`, `spend_bonat`, `use_booster` |
| `payload` | `Map<String, Object>` | the wire payload (contracts/operations.md), integers and strings only |
| `jenehatDelta`, `bonatDelta`, `fuelDelta` | `int` | the effects |
| `reason` | `LedgerReason?` | backend §7.2, for a JENEHAT or BONAT effect |
| `ref` | `TxnId?` | the trip start it belongs to |
| `occurredAtMs` | `int` | trusted time |
| `contentVersion` | `int` | the active pack's |
| `fuelMax`, `fuelRegenMinutes` | `int` | the tunables applied |
| `maxEarningsJenehat` | `int?` | `trip_start` only; local, never sent |

### `SyncStatus`

`pending` → `accepted` | `rejected`. Set only by M06 (`markAccepted`, `markRejected`), and never
back to `pending`.

### `ClockAnchor`

`anchorMs`, `anchorElapsedMs`, `bootCount` (`int?`), `source` (`device` | `server`),
`latestTrustedMs` (research R9).

## Tables (schema version 1)

Every column is `INTEGER` or `TEXT`. A guard forbids `REAL` (FR-008). Single-row tables use
`id INTEGER PRIMARY KEY CHECK (id = 1)`.

### `ledger_ops`

| Column | Type | Constraint |
| --- | --- | --- |
| `seq` | INTEGER | PRIMARY KEY AUTOINCREMENT: the application order |
| `txn_id` | TEXT | NOT NULL UNIQUE |
| `op_type` | TEXT | NOT NULL, CHECK in the six types |
| `payload` | TEXT | NOT NULL: canonical JSON (keys sorted, no whitespace, integers only) |
| `jenehat_delta`, `bonat_delta`, `fuel_delta` | INTEGER | NOT NULL DEFAULT 0 |
| `reason` | TEXT | NULL |
| `ref` | TEXT | NULL |
| `occurred_at_ms` | INTEGER | NOT NULL |
| `content_version` | INTEGER | NOT NULL, ≥ 1 |
| `fuel_max`, `fuel_regen_minutes` | INTEGER | NOT NULL, ≥ 1 |
| `max_earnings_jenehat` | INTEGER | NULL, ≥ 0 |
| `sync_status` | TEXT | NOT NULL DEFAULT `pending`, CHECK in (`pending`, `accepted`, `rejected`) |
| `sync_reason` | TEXT | NULL |

Indexes: `txn_id` (unique), `(sync_status, seq)`, `ref`. Rows are never deleted or edited except
`sync_status` and `sync_reason` (FR-015). The `economy_writes_test` guard enforces this.

### `wallet` (one row)

| Column | Type | Constraint |
| --- | --- | --- |
| `id` | INTEGER | = 1 |
| `jenehat`, `bonat`, `fuel` | INTEGER | NOT NULL, CHECK ≥ 0 |
| `fuel_counted_from_ms` | INTEGER | NOT NULL |
| `fuel_unlimited_until_ms` | INTEGER | NULL |
| `last_seq` | INTEGER | NOT NULL: the last operation folded in |

### `inventory`

`booster_id` TEXT PRIMARY KEY (one of the four in-trip boosters), `count` INTEGER NOT NULL CHECK ≥ 0.

### `ownership`

`kind` TEXT CHECK in (`item`, `vehicle`, `chapter`), `sku_id` TEXT, `variant_id` TEXT NULL,
`acquired_at_ms` INTEGER, `acquired_by` TEXT (a `txn_id`). PRIMARY KEY (`kind`, `sku_id`).

### `trip_progress`

`trip_id` TEXT PRIMARY KEY, `best_stars` INTEGER CHECK 0–3, `best_time_ms` INTEGER NULL,
`plays` INTEGER CHECK ≥ 0, `first_completed_at_ms` INTEGER NULL.

### `trip_session` (one row)

The unfinished trip and the latest result:

- `unfinished_start`, `unfinished_trip_id`, `unfinished_content_version`,
  `unfinished_max_earnings`, `unfinished_started_at_ms`, `unfinished_revived` (0/1),
  `unfinished_traffic_jam_ads`, all NULL when no trip is unfinished;
- `last_result_start`, `last_result_outcome`, `last_result_earnings`, `last_result_doubled` (0/1),
  all NULL before the first result.

### `projection_base` (one row)

`state` TEXT (the base `EconomyState` as canonical JSON), `after_seq` INTEGER (the last operation
it already includes), `kind` TEXT CHECK in (`new_player`, `server_snapshot`), `state_version`
INTEGER NULL (the server's, from M06), `taken_at_ms` INTEGER.

### `clock_anchor` (one row)

`anchor_ms`, `anchor_elapsed_ms` INTEGER NOT NULL; `boot_count` INTEGER NULL; `source` TEXT CHECK
in (`device`, `server`); `latest_trusted_ms` INTEGER NOT NULL.

### First open

`onCreate` makes the tables and, in the same transaction, the first `projection_base`
(`new_player`, `after_seq = 0`), the `wallet`, `trip_session` and `clock_anchor` rows (the anchor
taken on the device clock now), and no other rows. `fuel_max` comes from the tunables read during
startup.

## Invariants

1. **Projection** (FR-018): `wallet`, `inventory`, `ownership`, `trip_progress` and `trip_session`
   equal `fold(projection_base.state, ops with seq > after_seq and sync_status ≠ rejected)`, with
   the dependent operations of research R6 left out.
2. **Balances** (FR-018, SC-001): `wallet.jenehat = base.jenehat + Σ jenehat_delta` over the
   folded operations, and the same for BONAT.
3. **Never negative** (FR-009): CHECK constraints on `wallet` and `inventory`, and the domain
   refuses first, so a CHECK failure is a bug.
4. **One unfinished trip** (FR-031): at most one, held in `trip_session`.
5. **One result per start** (FR-032): a `trip_result` whose `ref` already has a result is refused
   (`result_exists`), and the fold leaves out a second one.
6. **Trusted time never goes back** (FR-026): `latest_trusted_ms` never decreases, and every
   operation's `occurred_at_ms` is ≥ the previous one's.
7. **BONAT never rises on the device** (FR-011): no operation has `bonat_delta > 0`.

## Lifecycles

**Operation.** Requested → validated → refused (nothing stored) or stored and applied
(`pending`) → `accepted` or `rejected` (M06). A rejection triggers a rebuild, which may leave
later operations out of the projection without changing their rows (research R6).

**Trip.** No trip → `trip_start` (unfinished) → optional revive and booster uses → `trip_result`
(no unfinished trip; it becomes the latest result) → optional `result_double`.

**Fuel.** Full (`countedFrom` = when it filled) → spend → counting from that moment → one liter per
`regen` → full again. A refill or the window can apply at any point (research R8).

**Clock anchor.** First open (device) → same boot: counts with uptime → restart: re-anchored at
`max(device now, latest)` → (M06) anchored on server time.
