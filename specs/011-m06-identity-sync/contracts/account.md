# Contract: The Account

The install id, the session, the first open, account changes, deletion and the link request.
Code in `lib/core/account/`. Research: R1, R2, R4–R8.

## Stores

```dart
abstract interface class InstallIdStore {
  /// The stored id, or a new one written to every store the platform has. Never null.
  Future<InstallId> readOrCreate();
}

abstract interface class SessionStore {
  Future<Session?> read();
  Future<void> write(Session session);   // one call: access and refresh together
  Future<void> clear();
}
```

| Implementation | Platform | Where |
| --- | --- | --- |
| `AndroidInstallIdStore` | Android | Block Store through `wassal/install_id` (`read`, `write`), then `wassal_install.xml` |
| `KeychainInstallIdStore` | iOS | `flutter_secure_storage`, key `wassal.install_id`, `first_unlock_this_device`, not synchronizable |
| `SecureSessionStore` | both | `flutter_secure_storage`, key `wassal.session` |
| `MemoryInstallIdStore`, `MemorySessionStore` | tests | memory |

### The `wassal/install_id` channel (`MainActivity.kt`)

| Method | Arguments | Answer |
| --- | --- | --- |
| `read` | — | the stored string, or `null` (no Play services, nothing stored, or an error) |
| `write` | `{id}` | `true` when Block Store accepted it; `false` otherwise. Cloud backup is requested only when `isEndToEndEncryptionAvailable()`. |

A failure of either method never fails the app. The preference file keeps the id.

`readOrCreate` order: Block Store → `wassal_install.xml` → a new `CryptoRNG` v4 id. Whatever it
returns is written to whichever store lacks it.

## `AccountService` (`lib/core/account/account_service.dart`)

```dart
abstract interface class AccountService {
  AccountStatus get status;                    // synchronous after startup
  Stream<AccountStatus> get statuses;
  Profile? get profile;

  /// The first open's work (R6): install id, account creation, a returning player's state.
  /// Runs once per install; later launches answer `notFirstOpen` at once.
  Future<FirstOpenOutcome> firstOpen();

  /// Boot calls it just before it leaves the Loading screen. Past it, firstOpen() leaves a
  /// returning player's state to the sync engine (R6).
  void handOver();

  /// Makes sure there is an active session, signing in with the install id when there is none.
  /// The sync and the bootstrap call it; screens don't.
  Future<bool> ensureSession();

  /// R8. Flushes pending operations (up to 15 s), then links.
  Future<LinkOutcome> link(String googleIdToken, {LinkResolve? resolve, String? existingPlayerId});
}
```

### Providers

| Provider | Value | Readers |
| --- | --- | --- |
| `accountServiceProvider` | `AccountService` | boot, sync, M14 |
| `accountStatusProvider` | `AccountStatus` stream | M14, B09's screens, the debug card |
| `profileProvider` | `Profile?` | M07, M08, M14 |
| `firstOpenOutcomeProvider` | `Future<FirstOpenOutcome>` | boot; M07 routes by it |
| `progressRestoredProvider` | `Stream<void>`: a returning player's state landed after the 3 s | M07 |

## The first open

```text
startup: database open ─▶ account row status = none?
   no  ─▶ notFirstOpen
   yes ─▶ clear wassal.session ─▶ install id ─▶ link down? ─▶ offline
                                            └─▶ POST /v1/auth/anonymous
                                                 created: true  ─▶ newPlayer
                                                 created: false ─▶ GET /v1/state ─▶ replaceFromServer ─▶ restored
                                                                   (only before handOver)
boot: waits for the outcome up to firstOpenWait (3 s) after startup completes; past it, timedOut.
      handOver() just before it navigates. A returning player found later goes to
      SyncEngine.requestRestore(): the next pass, off the trip route, takes the state, then
      progressRestoredProvider emits.
```

- **No state change during a trip** (FR-018, SC-010). `firstOpen()` calls `replaceFromServer`
  only before `handOver()`. A call already queued then still completes before any trip can start,
  since `trip_start` queues behind it on the economy's serial queue. Past `handOver()`, a
  `created: false` answer, or a state answer still in flight, isn't applied: `firstOpen()` calls
  `SyncEngine.requestRestore()`. On `StateTaken(firstOpen)`, the service sets `restored_at_ms` and
  emits `progressRestoredProvider`. The pending restore lives in memory. After a kill, the stale or
  ahead path still takes the state, without the signal.

- The boot step `account` completes when the wait ends, so the road bar reaches its end.
- `account.first_open_at_ms` is set when the work starts, and `account.restored_at_ms` when a
  returning player's state is taken.
- With no account at the end (offline, timed out, failed), `ensureSession` creates it at the next
  trigger. A failed creation (unreachable, or a `5xx`) closes the account gate and sets the sync's
  backoff: 2 s doubling to 5 min, ±20%. A `429` waits at least `retry_after_s` (FR-004).

## Account changes (R7)

| Event | Account | Economy | Sync |
| --- | --- | --- | --- |
| First token answer, no player yet | `active`, `player_id` = P | base player stays null until the first state or batch, then P | runs |
| Token answer for the same player | profile and providers updated | — | runs |
| Token answer for player Q ≠ P | `player_id` = Q, session stored | unchanged until the next pass | blocked until `adoptAccount` |
| Next pass after a change | — | `GET /v1/state` (Q) → `adoptAccount`: pending → `rejected(account_changed)`, base = Q's state, fold | runs |
| `403 account_deleted` | `deleted` | unchanged; play goes on | stopped, also on later launches |

## Link outcomes (R8)

| Answer | `LinkOutcome` | Afterwards |
| --- | --- | --- |
| `200 {player_id, providers}` | `Linked(providers)` | profile providers updated |
| `200 TokenPair` (after `switch_to_existing`) | `Linked(providers)` | session stored; account change to the existing player |
| `409 provider_in_use` | `Conflict(current, existing)` | M14 shows both; the retry passes `resolve` and `existing.playerId` |
| `409 provider_already_linked` | `ProviderAlreadyLinked` | — |
| `422 provider_token_invalid` | `GoogleTokenRefused(reason)` | never renews our session |
| unreachable | `LinkUnreachable` | — |
| anything else | `LinkFailed(code)` | the token rules apply to `401`s |

Every outcome carries `flushed`: whether the queue was empty before the link was sent.
