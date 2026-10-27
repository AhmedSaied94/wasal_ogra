# Contract: The Sync

How pending operations reach the server and how its answers change the phone. Code in
`lib/core/sync/` and `lib/core/economy/economy_sync.dart`. Research: R9–R16, R20.

## `EconomySync` (`lib/core/economy/economy_sync.dart`)

The economy's sync-only interface. `EconomyService` implements it beside `Economy`, and every
call runs on the service's serial queue, so it never interleaves with a player's request. Only
`lib/core/sync/` and `lib/core/account/` may read `economySyncProvider` (contracts/ci-checks.md).

```dart
abstract interface class EconomySync {
  /// The base: its server state version (null before any), and its player (null before any).
  ({int? stateVersion, String? playerId}) get baseInfo;

  int get pendingCount;
  Stream<int> get pendingCounts;                 // a value after every change

  /// The oldest pending operations, in `seq` order.
  Future<List<LedgerOp>> pendingOps({int limit = 100});

  /// The highest `seq` with an answer (accepted or rejected); 0 when none.
  Future<int> highestAnsweredSeq();

  /// One answer, in one transaction (R11): marks the results, rebases on the answer's wallet
  /// unless [answer.stateStale], folds what is still pending. Returns what the fold left out
  /// among the accepted operations (the divergence check) and the view before and after.
  Future<AnswerApplied> applyAnswer(SyncAnswer answer, {required List<LedgerOp> batch, required String playerId});

  /// The full state, for the same player or for operations recorded before any account (R12).
  Future<void> replaceFromServer(EconomyState snapshot, {required String playerId, required int stateVersion});

  /// Another player's state (R7): pending operations become rejected(account_changed).
  Future<int> adoptAccount(EconomyState snapshot, {required String playerId, required int stateVersion});

  /// A local rejection (R13): `validation_error`, `payload_too_large`.
  Future<void> setAside(Map<TxnId, String> reasons);

  /// The comeback gift (R16). Fuel to the maximum and one change_bag. Guarded by ComebackGift.
  Future<OpOutcome> grantComebackGift(TxnId id);
}
```

`markAccepted`, `markRejected` and `replaceBase` leave the `Economy` interface. Their store methods
stay, and `applyAnswer` composes them in one transaction.

## The rebase (R11)

```text
answer A for batch B (operations in seq order, max seq S), not stale:
  1. mark A.results (accepted / rejected(reason))
  2. base' = fold(base, ops with seq ≤ S that aren't rejected)
            with jenehat, bonat ← A.wallet; fuel ← FuelState(A.wallet.fuel, A.wallet.fuel_updated_at,
            A.wallet.fuel_unlimited_until)
     base'.after_seq = S, .state_version = A.state_version, .player_id = playerId
  3. tables = fold(base', pending ops after S)
answer A with state_stale: step 1 only; the engine fetches the full state next.
```

If step 2's fold leaves out an operation the answer accepted, the engine fetches the full state
after this batch.

## `SyncEngine` (`lib/core/sync/sync_engine.dart`)

```dart
abstract interface class SyncEngine {
  /// Asks for a pass. Joins the running one (which then runs once more), or starts one if no
  /// gate is closed.
  void request(SyncTrigger trigger);

  /// Internal builds' «sync now»: a forced bootstrap, then a pass.
  Future<PassOutcome> syncNow();

  /// Sends until nothing is pending or [timeout] passes; for the link (R8).
  Future<bool> flush({Duration timeout = const Duration(seconds: 15)});

  /// A returning player was found after the first open's hand-over (R6). The next pass takes the
  /// full state first (step 2b) and emits StateTaken(firstOpen). Held in memory.
  void requestRestore();

  Stream<SyncEvent> get events;   // pass started/ended, batch answered, set aside, rejected, dropped
  SyncSnapshot get snapshot;      // for the debug card: last pass, outcome, last error, counts
}

enum SyncTrigger { startup, accountActive, resume, online, opsRecorded, leftTrip, manual }
```

### Gates

A pass doesn't start, and a running pass stops before its next request, when any is closed.

| Gate | Closed while |
| --- | --- |
| account | `AccountStatus` isn't `active`, after `ensureSession` failed |
| deleted | `AccountStatus.deleted` |
| trip route | `/trip/:tripId` is the visible route (pause and fail included; the result route isn't) |
| maintenance | a `503 maintenance` since the last resume |
| background | the app isn't in the foreground |
| backoff | the backoff's next time hasn't come, unless the trigger is `online` or `manual` |

### A pass

```text
1. ensureSession
2. if account.player_id ≠ base.player_id (both set): GET /v1/state → adoptAccount
2b. if a first-open restore is pending: GET /v1/state → replaceFromServer (StateTaken firstOpen)
3. loop:
     batch = pendingOps(100), trimmed to ≤ 200 KiB encoded
     if empty: break
     POST /v1/sync {base_state_version: base.state_version ?? 0, ops: batch}
     ApiOk:   applyAnswer; if stale or diverged: GET /v1/state → replaceFromServer
     refused: research R13's table
     wait ≥ 1 s before the next batch
4. if nothing pending and serverInfo.state_version > base.state_version: GET /v1/state → replaceFromServer
5. if the pass rejected an operation with a visible effect: the toast (R14), once
```

- **Backoff** after an unreachable server, a `5xx`, a malformed answer or a `429`, from a batch or
  from step 1's account creation: 2 s, 4 s, 8 s and so on, up to 5 min, with ±20% jitter, and
  never less than `Retry-After` (or creation's `retry_after_s`). A success resets it.
- **Debounce:** `opsRecorded` waits 2 s, so a trip's start and result often travel together.

## The wire (R10)

```json
{
  "base_state_version": 41,
  "ops": [
    { "client_txn_id": "<row txn_id>", "op_type": "<row op_type>",
      "occurred_at": "2026-10-27T09:12:03.120Z", "payload": { "…row payload…": 0, "content_version": 7 } }
  ]
}
```

| `op_type` | Payload sent |
| --- | --- |
| `trip_start` | the row's payload + `content_version` |
| `trip_result` | the row's payload |
| `ad_reward` | the row's payload |
| `spend_jenehat` | the row's payload + `content_version` |
| `spend_bonat` | the row's payload + `content_version` |
| `use_booster` | the row's payload |
| `comeback_gift` | `{}` |

Later features add theirs (`tutorial_gift` and `settings_update` from M07; `story_progress` and
`claim_request`, with `content_version`, from M10).

## Taking the full state (R12)

| State field | Becomes |
| --- | --- |
| `wallet` | JENEHAT, BONAT and `FuelState` as in the rebase |
| `inventory` | the four boosters' counts |
| `ownership[]` | `Owned(kind, variantId: variant == "" ? null : variant, acquiredAtMs: server_time, acquiredBy: null)` |
| `trips[]` | `TripProgress(bestStars, bestTimeMs, plays, firstCompletedAtMs: null)` |
| `open_trip` | `UnfinishedTrip` only if this phone has its trip record; `maxEarningsJenehat` from the active pack; else left out |
| `last_result` | `LastResult` |
| `player.display_name`, `driver_level` | `account` |
| `server_time` | the trusted-time anchor |
| `story`, `grants`, `stats` | not mapped yet (M07, M10, M13) |

`after_seq` is `highestAnsweredSeq()`, and the pending operations are folded on top.

## The comeback gift (R16)

```dart
abstract interface class ComebackGift {
  bool get claimable;            // cached flag, no pending claim, flag newer than the last answer
  Stream<bool> get claimables;
  Future<OpOutcome> claim(TxnId id);   // OpRefused(notEligible) when not claimable
}
```

- **Local operation `comeback_gift`.** Payload `{}`.
  - Effects: `fuel_delta = max − liters` (0 on a full tank, which is still applied) and inventory
    `change_bag` + 1.
  - No reason, no ref.
  - In the fold: always applies.
  - Never adds BONAT: the direction test lists it.
- **The claim:**
  - Claiming sets `server_info.comeback_claimed_at_ms`.
  - Answering the claim's operation sets `comeback_answered_at_ms`.
  - A bootstrap's `claimable` counts only if it arrived after `comeback_answered_at_ms`, and after
    `comeback_claimed_at_ms` when that is later.

## Events (for M15 and the debug card)

| Event | Fields |
| --- | --- |
| `PassEnded` | outcome, batches, accepted, rejected, set aside, duration |
| `OpRejected` | txn id, op type, reason |
| `OpSetAside` | txn id, op type, local reason |
| `OpsDropped` | count, reason `account_changed` |
| `RenewalFailed` | code |
| `StateTaken` | state version, why (`stale`, `ahead`, `diverged`, `account`, `firstOpen`) |
