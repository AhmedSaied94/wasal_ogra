# Data Model: Identity, Bootstrap and Sync (M06)

What this feature keeps, where, and how it changes. The decisions are in
[research.md](./research.md). The economy's own tables are M05's
(`specs/007-m05-local-economy/data-model.md`); this file lists only what M06 adds or changes.

## Where each value lives

| Value | Store | Survives a re-install | Written by |
| --- | --- | --- | --- |
| Install id | Android: Block Store + `wassal_install.xml` (backed up); iOS: keychain (this device) | yes, where the platform allows (R1) | `InstallIdStore` |
| Session (`player_id`, `access`, `refresh`, `access_expires_at_ms`) | `flutter_secure_storage`, key `wassal.session` | no on Android; may on iOS, and a fresh database deletes it (R2) | `SessionStore` |
| Account record, profile | app database, `account` | no (database out of backup) | `DriftAccountStore` |
| Last bootstrap, comeback lock | app database, `server_info` | no | `DriftAccountStore` |
| Whose state the economy holds, and its version | app database, `projection_base.player_id`, `.state_version` | no | `DriftEconomyStore` |
| Dismissed optional-update version | preference store (`SettingsStore`), key `update.dismissedVersion` | yes (backed up; harmless) | `UpdateState` |
| Update state, maintenance, reach, last pass, backoff, a pending first-open restore (R6) | memory | no | `ServerStatus`, `SyncEngine` |

## Domain values (`lib/core/account/domain/`, `lib/core/sync/domain/`)

Pure Dart. They import nothing but `dart:core`, `content_models` and the economy and content
domains (the domain-imports guard).

- **`InstallId`**: a lowercase version-4 UUID string. `InstallId.parse` refuses anything else.
- **`Session`**: `playerId` (UUIDv7 string), `access`, `refresh`, `accessExpiresAtMs`. Its
  `toString()` prints only the player id.
- **`AccountStatus`**: `none`, `active`, `deleted`.
- **`Profile`**: `playerId`, `providers` (a set of `google`; `apple` later), `displayName?`,
  `driverLevel?`.
- **`FirstOpenOutcome`**: `newPlayer`, `restored`, `offline`, `timedOut`, `notFirstOpen`.
- **`TokenPair`** (wire): `playerId`, `access`, `refresh`, `accessExpiresIn` (seconds), `providers`,
  and `created` for account creation.
- **`ServerWallet`** (wire): `jenehat`, `bonat`, `fuel`, `fuelMax`, `fuelUpdatedAtMs`,
  `fuelUnlimitedUntilMs?`. It becomes the economy's `FuelState(liters: fuel, countedFromMs:
  fuelUpdatedAtMs, unlimitedUntilMs: fuelUnlimitedUntilMs)`.
- **`BootstrapSnapshot`** (wire): `serverTimeMs`, `profile`, `wallet`, `entitlements`,
  `stateVersion`, `contentVersion`, `client`, `daily`, `comebackClaimable`.
  - `ClientBlock` holds `minVersion`, `latestVersion` and `forceUpdate`.
  - `Entitlements` holds `removeAds`, `subscriptionUntilMs?`, `seasonPasses` and the flags
    `noInterstitials` and `fuelMaxBonus`.
  - `DailyBlock` holds `gameDate`, `challengeAvailable` and `rewardClaimable`.
- **`StateSnapshot`** (wire): `stateVersion`, `serverTimeMs`, `profile` (name, level), `wallet`,
  `inventory`, `ownership`, `trips`, `openTrip?` and `lastResult?`. `story`, `grants` and `stats`
  are parsed and kept raw for later features (R12).
- **`SyncBatch`**: the operations (`LedgerOp`s), `baseStateVersion` and its encoded size.
- **`SyncAnswer`** (wire): `stateVersion`, `stateStale`, `results` (`OpResult(txnId, accepted |
  rejected(reason), granted?)`) and `wallet`.
- **`PassOutcome`**: `idle`, `done(batches, accepted, rejected, setAside)`,
  `held(reason: trip | maintenance | account | deleted | background)`,
  `failed(code, retryAtMs)`.
- **`LinkOutcome`**: `Linked(providers)`, `Conflict(current, existing)`, `ProviderAlreadyLinked`,
  `GoogleTokenRefused(reason)`, `LinkUnreachable`, `LinkFailed(code)`. Each is reported with
  `flushed: bool`.
  - `ConflictSummary` holds `driverLevel`, `chapterId`, `bonat` and, for `existing`, its
    `playerId`.

## Tables (schema v3)

Every column is INTEGER or TEXT (constitution II, the no-REAL guard). v3's step goes in
`AppDatabase.upgradeSteps`; `make-migrations` writes `drift_schemas/app/drift_schema_v3.json` and
its tests.

### `account` (new, one row)

| Column | Type | Rule |
| --- | --- | --- |
| `id` | INTEGER PK | always 1 |
| `status` | TEXT | `none` \| `active` \| `deleted`; the upgrade and a new database insert `none` |
| `player_id` | TEXT NULL | the session's player; a UUIDv7 |
| `providers` | TEXT | a JSON array, `[]` until a token answer says otherwise |
| `display_name` | TEXT NULL | as the server last gave it |
| `driver_level` | INTEGER NULL | as the server last gave it |
| `first_open_at_ms` | INTEGER NULL | trusted time of the first open with M06; set once |
| `restored_at_ms` | INTEGER NULL | trusted time a returning player's state was first taken (R6) |
| `updated_at_ms` | INTEGER | trusted time of the last write |

### `server_info` (new, one row)

| Column | Type | Rule |
| --- | --- | --- |
| `id` | INTEGER PK | always 1 |
| `received_at_ms` | INTEGER NULL | trusted time the last bootstrap arrived; null before the first |
| `server_time_ms` | INTEGER NULL | its `server_time` |
| `state_version` | INTEGER NULL | its `state_version` |
| `content_version` | INTEGER NULL | its `content.version` |
| `client` | TEXT NULL | canonical JSON of the `client` block |
| `entitlements` | TEXT NULL | canonical JSON of `entitlements` |
| `daily` | TEXT NULL | canonical JSON of `daily` |
| `comeback_claimable` | INTEGER | 0 or 1; 0 before the first bootstrap |
| `comeback_claimed_at_ms` | INTEGER NULL | trusted time of the last claim (R16) |
| `comeback_answered_at_ms` | INTEGER NULL | trusted time the last claim's operation was answered |

### `projection_base` (changed)

| Column | Change |
| --- | --- |
| `player_id` | **new**, TEXT NULL: the player whose server state the base is. Null for a new player's base until the first state or the first accepted batch. |

### `ownership` (changed)

| Column | Change |
| --- | --- |
| `acquired_by` | **now nullable**: null for a row taken from the server's state (R12). A table rebuild in the v3 step. |

### `ledger_ops` (unchanged columns, new values)

`sync_reason` may now hold the local reasons `validation_error`, `payload_too_large` and
`account_changed`, besides the server's reasons (R13, R7). `op_type` may now be `comeback_gift`
(R16). Rows still change only in `sync_status` and `sync_reason` (the M05 guard).

## Secure storage and backup

- `wassal.session`, one JSON value, written in one call (R2).
- iOS: `KeychainAccessibility.first_unlock_this_device`, `synchronizable: false`, for the session
  and for the install id (`wassal.install_id`).
- Android backup rules (`data_extraction_rules.xml`, `backup_rules.xml`):
  - **excluded** from cloud backup and device transfer: `db/` (M05), and the secure storage
    plugin's four preference files (`FlutterSecureStorage.xml`, `FlutterSecureKeyStorage.xml`,
    `FlutterSecureStorageConfiguration.xml`, `FlutterSecureStorageConfiguration:FlutterSecureStorage.xml`;
    R2);
  - **no `<include>`**: one would limit the backup to the listed files. `wassal_install.xml` and
    everything else keep the platform's default backup.

## State transitions

### The account

```text
none ──(token answer)──▶ active ──(403 account_deleted)──▶ deleted
              active ──(token answer for another player)──▶ active (player changed; R7)
```

`deleted` is final for this feature. B09 and M14 decide what follows it.

### Whose state the economy holds

```text
base.player_id = null ──(first state, or first accepted batch)──▶ P
base.player_id = P, account.player_id = Q ≠ P ──(adoptAccount, R7)──▶ Q
```

While `account.player_id ≠ base.player_id` (with neither null), no batch is sent.

### An operation's sync status (M05's, with the new reasons)

```text
pending ──(accepted answer)──────────────────────────▶ accepted
pending ──(rejected answer, or set aside, or account_changed)──▶ rejected(reason)
```

A status never goes back.

### The update state (memory)

```text
none ──(live bootstrap: latest > app, not forced)──▶ optional(v) ──(closed)──▶ none (v remembered)
none | optional ──(live bootstrap force_update, or 426)──▶ forced   (until the process ends)
```

### Reach (memory)

```text
online ──(link down, or a request unreachable)──▶ offline
offline ──(bootstrap OK, then a pass with no network failure)──▶ online
```

### Maintenance (memory)

```text
clear ──(503 maintenance)──▶ on(until?) ──(next successful pass)──▶ clear
```

## Invariants

1. The materialized economy equals the fold of `projection_base` and the non-rejected operations
   after it (M05 invariant 1). `applyAnswer`, `replaceFromServer` and `adoptAccount` each keep it
   in one transaction.
2. After an answer without `state_stale`, the base's JENEHAT, BONAT and fuel equal the answer's
   wallet, and its `state_version` equals the answer's.
3. No operation is ever sent while `account.status ≠ active`, or while the base's player differs
   from the account's.
4. Every operation with `seq` ≤ `projection_base.after_seq` has been answered (`accepted` or
   `rejected`).
5. At most one `comeback_gift` operation is pending.
6. The install id, the access token and the refresh token appear in no log, crash report, analytics
   event, preference key or database column.
