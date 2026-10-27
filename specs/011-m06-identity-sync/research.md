# Research: Identity, Bootstrap and Sync (M06)

Decisions for [spec.md](./spec.md). Each has the decision, the reason, and what was rejected. The
server side is B02's and B03's merged contracts (`specs/009-b02-accounts-auth/contracts/`,
`specs/010-b03-ledger-sync/contracts/`). The client side builds on M05's economy
(`specs/007-m05-local-economy/contracts/`) and M04's content updater.

## R1. Where the install id lives (resolves the device side of backend §22.6)

- **Decision:** one version-4 id per install, generated with `uuid`'s `CryptoRNG` (passed
  explicitly, not left to the package default), canonical lowercase. It sits behind
  `InstallIdStore` (`lib/core/account/install_id_store.dart`), with one implementation per
  platform:
  - **Android: Block Store first, a backed-up preference file second.**
    - Block Store (`com.google.android.gms:play-services-auth-blockstore:16.4.0`) keeps up to 16
      entries of 4 KB. With the user's Google backup on, it keeps them across an uninstall and a
      re-install on the same phone, and carries them to a new phone in the restore flow (Android
      docs, "Block Store"). The value is stored with `setShouldBackupToCloud(true)` when
      `isEndToEndEncryptionAvailable()` is true; otherwise it stays on the device.
    - The fallback is a dedicated SharedPreferences file, `wassal_install.xml`, which Android's own
      backup carries. It covers a phone where Block Store fails, but Play services and backup are
      on. Dart writes it through `SharedPreferencesAsync` on the `SharedPreferences` backend, with
      `AndroidSharedPreferencesStoreOptions(fileName: 'wassal_install')`. Those options come from
      `shared_preferences_android` 2.5.1, which becomes a direct dependency (R24). The backup rules
      stay exclude-only (R2), so the default backup carries the file.
    - A small method channel, `wassal/install_id` in `MainActivity.kt`, next to M05's
      `wassal/clock`: `read()` returns Block Store's value or null, and `write(id)` stores it. The
      Dart side reads Block Store, then the preference file, and writes the id to both whenever one
      lacks it.
  - **iOS: the keychain**, through `flutter_secure_storage` with
    `KeychainAccessibility.first_unlock_this_device` and `synchronizable: false`. Keychain items
    outlive the app's deletion, and "this device" keeps them out of iCloud. The keychain's survival
    of a deletion is long-standing iOS behaviour, not a documented promise; if Apple changes it,
    linking Google is the way back (spec Edge Cases).
  - **Tests and Linux:** an in-memory store.
- **The id is never sent anywhere but `POST /v1/auth/anonymous`, and never logged** (FR-002). A
  guard checks it (contracts/ci-checks.md).
- **Why not `flutter_secure_storage` on Android:** its data goes with the app on uninstall, and a
  backup restored to another phone can't unwrap its keys (`InvalidKeyException`, the plugin's own
  warning).
- **Rejected:**
  - Android ID: an identifier the Data safety form has to declare, and a factory reset changes it
    (B02 R5).
  - An Android backup agent written by hand: the preference file with the platform's own backup
    does the same with no code.
  - Credential Manager or passkeys: they need a user's account and a prompt, and this id must work
    silently on the first open.

## R2. The session tokens

- **Decision:** `SessionStore` (`lib/core/account/session_store.dart`) over `flutter_secure_storage`
  11.2.0, under one key, `wassal.session`. Its value is one JSON object:
  `{player_id, access, refresh, access_expires_at_ms}`. One write stores the access and refresh
  tokens together, before anything uses them (B02 "Client obligations").
  - `access_expires_at_ms` is trusted time (M05's clock) at the answer, plus `access_expires_in`
    seconds. The tokens' contents are never read.
  - iOS uses the same keychain options as R1.
  - Android: `storageNamespace` stays unset, so 11.2.0 writes four `sharedpref` files:
    `FlutterSecureStorage.xml` (the data), `FlutterSecureKeyStorage.xml` (the wrapped key), and
    `FlutterSecureStorageConfiguration.xml` and `FlutterSecureStorageConfiguration:FlutterSecureStorage.xml`
    (its settings).
    - All four are excluded from cloud backup and device transfer (`data_extraction_rules.xml`,
      `backup_rules.xml`, contracts/ci-checks.md). A plugin upgrade must re-check the names.
    - The rules stay exclude-only: an `<include>` would limit the backup to the listed files and
      drop the settings file.
    - `resetOnError` stays on. A store that can't be read is wiped, and the app signs in again
      with its install id, which lives elsewhere (R1).
- **A fresh database clears the session.** When the database has no account yet (R5), the app
  deletes `wassal.session` before anything else. A previous install's tokens can survive in the
  iOS keychain, and they would belong to a state this database never took.
- **Never in logs.** No HTTP logging interceptor is added in any flavor, and tokens never appear in
  `toString()`s or error reports (contracts/ci-checks.md).
- **Rejected:**
  - Two keys, one per token: a kill between the two writes would pair a new access token with a
    spent refresh token.
  - Decoding the JWT's `exp`: B02 forbids depending on the claims.

## R3. The API client

- **Decision:** an `ApiClient` interface (constitution, Architecture boundaries), with one Dio
  implementation, in `lib/core/network/api_client.dart`. It answers with a sealed `ApiResult`:
  - `ApiOk(status, json, receivedAtElapsedMs)`;
  - `ApiFailure(status, code, details)`, from B01's error envelope. A body that isn't the envelope
    is `server_error`;
  - `ApiUnreachable(kind)`: no connection, a timeout, or DNS.
- It never throws for an answer.
- **One Dio** from M04's `createHttpClient` (base URL, the URL check, no redirects, the two headers).
  The player token is added per request by `AuthorizedApi` (R4), not by the factory. The manifest and
  pack downloads keep using the factory without a token (FR-008). The factory's comment changes to
  say so.
- **Timeouts:** connect 10 s; receive 15 s for bootstrap, state and the auth calls, and 30 s for
  sync.
- **Parsing:** hand-written, strict readers in `lib/core/sync/domain/wire/`. Integers must be
  integers, and an unknown field is ignored (B03 "Versioning"). They follow M04's manifest reader.
  A malformed `200` answer counts as `server_error`, and the batch is retried later.
- **Rejected:**
  - Retrofit, or a client generated from `contracts/openapi.yaml`: six endpoints, and a generator
    adds a build step and a dependency outside the locked stack.
  - Dio interceptors for renewal: they hide the single flight and the retry window in callbacks
    that are hard to test.

## R4. Renewal, signing in again and the token rules

- **Decision:** `AuthorizedApi` wraps `ApiClient` for every player endpoint. It follows B02's
  table (contracts/tokens.md "Client obligations"):
  - **Before a call:** if the access token has less than 60 s left (trusted time), renew first.
  - **One renewal at a time.** Concurrent callers await the same renewal.
  - **A lost renewal answer** (unreachable or a timeout) is retried with the same refresh token, at
    most twice, as long as the first attempt was under 60 s ago (measured on the uptime
    stopwatch). B02's window then returns the same successor. Past 60 s, the app signs in again
    instead.
  - **`401 token_expired` on a call:** renew, then repeat the call once.
  - **`401 token_invalid` on a call:** renew once, then repeat once. If the repeat is
    `token_invalid` again, sign in again.
  - **The renewal itself answers `token_expired` or `token_invalid`:** sign in again with the
    install id.
  - **`403 account_deleted`** anywhere: R7.
- **Signing in again** is `POST /v1/auth/anonymous` with the install id, `platform` and
  `locale: ar-EG`. A `429` waits `details.retry_after_s`.
- **Every token answer is written to `SessionStore` before it is used.** It is then compared with
  the stored player (R7).
- **Rejected:** renewing on a timer. The app has no background work, and a renewal is only needed
  before a call.

## R5. The account record and the first open

- **Decision:** a new one-row table, `account` (data-model.md), written only by
  `DriftAccountStore`. It holds:
  - `status`: `none`, then `active`, or `deleted`;
  - `player_id`;
  - the profile: providers, display name and driver level;
  - `first_open_at_ms`, set at the first open and never changed.
- **"The first open of an install"** (FR-027) means the row has `status = none` when startup
  reaches the account step. Schema v3's upgrade inserts the row as `none`, so a phone upgraded from
  a pre-M06 build counts as a first open too. That only happens on internal builds, and its wait is
  harmless: the account is new.
- The install id and the session live outside the database (R1, R2). Startup reads the row after
  the database step, and never waits for the network on a later launch.
- **Rejected:** a preference flag for "first open". A restored preference file would say "not
  first" on a fresh database.

## R6. The first open's 3-second wait (Clarifications Q1)

- **Decision:** `AccountService.firstOpen()` runs as soon as the database is open, in parallel with
  the rest of startup:
  1. Read or create the install id.
  2. If the phone reports no connection, end at once (`offline`).
  3. Call `POST /v1/auth/anonymous`.
     - `created: true` means a new player: end (`newPlayer`).
     - `created: false` means a returning player: fetch `GET /v1/state` and take it (R12), then end
       (`restored`).
  - **The boot screen waits for it, up to 3 s from the moment startup completes**, through a new
    boot step, `account`, which completes at once on later launches. The 3 s cap is a named
    constant (`firstOpenWait`), not a tunable: it is a UX bound, not a balancing number
    (constitution VIII).
  - **On time:** the outcome is in `firstOpenOutcomeProvider`. Boot goes to Home in every case
    today, since onboarding doesn't exist yet. M07 routes `newPlayer`, `offline` and `timedOut` to
    the intro, and `restored` to Home.
  - **Late:** the work goes on in the background, but the state is never taken while a trip may
    be on screen (FR-018, SC-010).
    - `firstOpen()` calls `replaceFromServer` only before the boot screen hands over
      (`AccountService.handOver()`, which boot calls just before it navigates). A call already
      queued then still completes before any trip can start, since `trip_start` queues behind it
      on the economy's serial queue.
    - Past the hand-over, a `created: false` answer, or a state answer still in flight, isn't
      applied: `firstOpen()` calls `SyncEngine.requestRestore()`. The engine's next pass, gated
      like every pass, takes the state first (contracts/sync.md step 2b) and emits
      `StateTaken(firstOpen)`.
    - On that event, the service sets `restored_at_ms` and announces the restore on
      `progressRestoredProvider` (a stream), for M07.
    - The pending restore is held in memory. After a kill, the next launch's stale or ahead path
      still takes the state, without the signal.
  - A connection that fails outright ends the wait at once, since the request answers
    `ApiUnreachable` immediately.
- **Rejected:**
  - A wait on every launch: the cold start budget (< 3 s to Home).
  - Waiting for the bootstrap as well: the state already holds what Home needs, and the bootstrap
    follows in the background.

## R7. Account changes and deletion

- **Decision:**
  - **Whose state the economy holds.** `projection_base` gains `player_id`: the player whose server
    state the base is. It is `null` until the first state, or the first accepted batch, for a new
    player.
  - **Operations recorded with no account** belong to the first player the phone signs into
    (FR-010). The first batch sends them, and the base takes that player's id.
  - **A different player.** When a token answer names a player other than `account.player_id`
    (after `switch_to_existing`, or a new player for a deleted one):
    1. Store the session and set `account.player_id` to the new player.
    2. From then on, `account.player_id ≠ projection_base.player_id`, which blocks the sync.
    3. The sync's next run fetches `GET /v1/state` with the new tokens.
    4. It then calls `EconomySync.adoptAccount(snapshot, playerId)` (contracts/sync.md), in one
       transaction:
       - mark every pending operation `rejected` with the local reason `account_changed`, keeping
         their count for M15;
       - replace the base with the snapshot, for the new player;
       - fold.

    A kill between steps 1 and 4 leaves the mismatch, so the next launch finishes the change. The
    old player's operations are never sent with the new tokens.
  - **`403 account_deleted`.** Set `account.status = deleted`, and stop every player call, now and
    on later launches. The bootstrap, the sync and renewal all check the status first. Play goes on
    with the local state. `accountStatusProvider` exposes it for M14 and B09, which decide what the
    screen shows and when to start fresh.
- **Rejected:** wiping the local database on a change. It would also lose the old player's
  unsynced operations on a mistaken answer, and dropping them as rejected keeps the log
  append-only (constitution IV).

## R8. The link request (Clarifications Q3)

- **Decision:** `AccountService.link(idToken, {resolve, existingPlayerId})`.
  1. If any operation is pending, run the sync to empty, for up to 15 s. The result reports
     `flushed: bool`, so M14 can warn when the summaries may be behind.
  2. Then `POST /v1/auth/link`. Its outcomes are a sealed `LinkOutcome`:
     - `Linked(providers)`;
     - `Conflict(current, existing)`, with both summaries and `existing.playerId`;
     - `ProviderAlreadyLinked`;
     - `GoogleTokenRefused(reason)`;
     - `LinkUnreachable`;
     - `LinkFailed(code)`.
  3. The retry passes `resolve` (`keep_current` or `switch_to_existing`) and `existingPlayerId`.
  - A `TokenPair` answer (`switch_to_existing`) goes through R7.
  - `422 provider_token_invalid` never triggers a renewal. Only the access token's own `401`s do.
  - M14 owns `google_sign_in`, which produces `idToken`, and every screen.
- **Rejected:** the link in M14 alone. The switch rewrites the tokens and the economy's base, which
  are this feature's.

## R9. The sync runner, its triggers and its gates

- **Decision:** one `SyncEngine` (`lib/core/sync/sync_engine.dart`), which runs at most one pass
  at a time. A trigger during a pass marks it dirty, so one more pass follows.
- **Triggers** (FR-018):
  - startup completed;
  - an account became active;
  - the app returned to the foreground;
  - the connection came back;
  - a new pending operation, debounced 2 s, from the economy's view stream (`pendingCount`
    changes);
  - the player left the trip route;
  - "sync now" on internal builds.
- **Gates.** A pass doesn't start, and a running pass stops before its next batch, when:
  - the account isn't `active`, or its player differs from the base's (R7, which the pass fixes
    first);
  - **the trip route is shown** (`/trip/:tripId`, which includes pause and fail; Clarifications
    Q4). A route listener, like M04's `HomeArrival`, gives `onTripScreen`. The result screen is
    another route, so the sync runs there;
  - maintenance is on hold until the next resume (R19);
  - the app is in the background. No background work (constitution, performance budgets): a pass
    in flight finishes its current request, and nothing new starts.
  - The bootstrap and account creation aren't gated by the trip route: they read, and don't change
    the economy (Clarifications Q4).
- **A pass:**
  1. Fix an account change (R7).
  2. Send batches until nothing is pending (R10, R11).
  3. Fetch the full state if the server is ahead (R12).
- **Spacing and backoff:**
  - At least 1 s between an answer and the next batch, which stays under the 60 per minute sync
    limit (SC-005):
    - A 5,000-operation backlog of real play takes about a minute. Trip results are about 0.6 KB
      (the parity fixtures' are 0.5–0.8 KB), so a batch holds 100 operations and the backlog is
      50 batches.
    - With every result at B03's 8 KB maximum, a batch holds about 46. The backlog then takes 2 to
      3 minutes, and is still never refused.
  - After an `ApiUnreachable`, a `5xx`, a malformed answer or a `429`, from a batch or from account
    creation in `ensureSession` (FR-004): wait 2 s, then 4 s, 8 s and
    so on, up to 5 min, with ±20% jitter. A `429` waits at least its `Retry-After`. A success
    resets the backoff, and so does any trigger after the connection comes back.
- **Rejected:** WorkManager or background fetch, which the constitution forbids; a periodic timer
  in the foreground, since the triggers cover every moment a sync can matter.

## R10. Batches and the wire mapping

- **Decision:**
  - **Batches.** Take up to 100 pending operations in `seq` order. Add them while the encoded body
    stays at or under 200 KiB, which leaves a margin under the server's 256 KB limit
    (contracts/api.md). Each batch carries `base_state_version` = `projection_base.state_version`
    (0 when there is none).
  - **Mapping** (`lib/core/sync/domain/op_wire.dart`, pure):
    - `client_txn_id`: the row's id.
    - `op_type`: the row's type.
    - `occurred_at`: ISO-8601 UTC with milliseconds and `Z`, from `occurred_at_ms`.
    - `payload`: the stored wire payload. For `trip_start`, `spend_jenehat` and `spend_bonat`
      (and, later, M10's `story_progress` and `claim_request`), `content_version` is added from the
      row's column (B03 operations.md).
    - Local columns aren't sent.
  - **Unknown answers.** A `reason` the app doesn't know is a plain rejection. A `granted` entry is
    read only for the debug card: the wallet in the answer already counts it (R11).
- **Rejected:** storing `content_version` in the payload at write time. M05's rows are append-only
  and already recorded without it, and the column is the source either way.

## R11. Applying an answer in one step: the rebase rule

- **Decision:** `EconomySync.applyAnswer(answer)` runs through the service's serial queue, so it
  never interleaves with a player's request (FR-022). It is one store transaction:
  1. Mark each result `accepted`, or `rejected` with its reason.
  2. **Rebase.** The new base is the old base folded with every operation up to the batch's
     highest `seq` that isn't rejected, with the wallet's JENEHAT, BONAT and fuel replaced by the
     answer's:
     - `fuel` becomes `liters`;
     - `fuel_updated_at` becomes `countedFromMs`;
     - `fuel_unlimited_until` becomes `unlimitedUntilMs`.

     Its `after_seq` is that highest `seq`, its `state_version` the answer's, and its `player_id`
     the account's player.
  3. Fold the remaining operations, the ones still pending after that `seq`, on top, and write the
     tables.
  - Every operation up to that `seq` has an answer, because batches go in order. The answer's
    `fuel` is recounted to the server's now, and its `fuel_updated_at` is the countdown start of
    that recount (`apps/economy/services/wallets.py`), so the device's own regeneration continues
    from it without counting twice.
  - The answer's `fuel_max` isn't used: the tank's size stays the tunables' until M17 brings the
    subscriber's tank.
  - **Divergence check.** If the fold in step 2 leaves out an operation the server accepted
    (M05's fold re-validates), the base can't match the server. The engine then fetches the full
    state (R12).
  - **State stale.** If the answer says `state_stale`, the rebase is skipped (the wallet includes
    another phone's changes). The results are still marked, and the full state follows at once
    (R12).
- **Measured** (T091, `test/core/economy/perf/apply_answer_budget_test.dart`, which CI runs with
  the same budget): a 100-operation answer on a 50,000-row log, the rest already answered, takes
  a median of 11 ms (runs of 9 to 21 ms) on the Linux dev machine on 2026-10-27. The budget is
  100 ms.
- **Rejected:**
  - `markAccepted`, `markRejected` and `replaceBase` as three calls: a kill between them would leave
    accepted operations folded on top of a wallet that already counts them.
  - Replacing only the wallet row: the projection is a fold (M05 R5), so the base must carry it.

## R12. Fetching and taking the full state

- **When:** after a `state_stale` answer; when nothing is pending and the bootstrap's
  `state_version` is above the base's; when the base's player differs from the account's (R7);
  after a divergence (R11); and on the first open of a returning player (R6).
- **Mapping** (`lib/core/sync/domain/state_snapshot.dart`, pure). The answer becomes an M05
  `EconomyState`:
  - **Wallet:** as in R11.
  - **`inventory`:** the four boosters.
  - **`trips`:** become `TripProgress`. `first_completed_at_ms` isn't in the answer, so it is null
    and screens don't rely on it.
  - **`ownership`:** becomes `Owned`. `variant` `""` becomes null, and items keep theirs.
    `acquiredAtMs` is the snapshot's `server_time`. **`acquiredBy` becomes nullable** (`null` means
    "from the server's state"): nothing reads it to decide anything, and B03 doesn't send it. That
    needs schema v3's table change (R21).
  - **`open_trip`:** becomes `UnfinishedTrip` only when this phone has M02's trip record for that
    start (`TripRecords.has(startTxn)`), with `maxEarningsJenehat` read from the active pack's trip
    and `startedAtMs` set to `server_time`.
    - A start the phone has no record of (played on another phone) is left out of the phone's
      state, so it is never offered for resuming.
    - The next `trip_start` this phone sends closes it on the server as abandoned (B03's rule), so
      the two agree again (FR-026).
    - This needs no change to M05's rules and no new column.
  - **`last_result`:** becomes `LastResult`.
  - **Not mapped yet:** `story`, `grants` and `stats`. The features that add their tables (M07,
    M10, M13) extend the mapping.
  - Ids the pack lacks are kept (FR-026).
- **Taking it:**
  - `EconomySync.replaceFromServer(snapshot, playerId, stateVersion)` sets
    `after_seq` = the highest `seq` already answered (every pending row sits after it), then folds
    the pending operations on top.
  - When the base's player is `null` (operations recorded before any account), they are adopted.
  - When it is another player, `adoptAccount` drops them instead (R7).
  - The profile (`player.display_name`, `driver_level`) goes to `account`.
  - `server_time` re-anchors trusted time (R15).
- **Rejected:** a backend change to send `acquired_at` and `acquired_by` with each ownership row. It
  is additive and possible later, but nothing on the phone needs the values.

## R13. When the whole request is refused

| Answer | What the engine does |
| --- | --- |
| `400 batch_too_large`, `413 payload_too_large` | Halve the batch's operation count and resend. A single operation refused for size is set aside as rejected `payload_too_large`. |
| `400 validation_error` with `details.fields` naming `ops.N.…` | Set operation N aside as rejected `validation_error`, and resend the rest. M15 reports it. |
| `400 validation_error` naming no operation, or naming the body | Hold the queue until the next launch, and record it for the debug card and M15. |
| `401` | R4. |
| `403 account_deleted` | R7. |
| `415`, `406` | App bug: like the `validation_error` with no operation. |
| `426 client_outdated` | The forced update state (R18), and hold. |
| `429 rate_limited` | Wait at least `Retry-After`, then back off (R9). |
| `503 maintenance` | The maintenance state, and hold until the next resume (R19). |
| `503 dependency_unavailable`, other `5xx`, unreachable, malformed `200` | Back off (R9). The queue is unchanged. |

Set-aside operations are rejections like any other: they roll back through the fold, and their
row keeps a local reason. The local reasons are `validation_error`, `payload_too_large` and
`account_changed`.

## R14. The rollback toast (Clarifications Q5)

- **Decision:**
  - **When.** After a pass, if any rejection in it (server or set-aside, but not `account_changed`)
    belonged to an operation with a visible effect, show the toast once. A visible effect is a
    non-zero JENEHAT, BONAT or fuel delta, or an ownership or inventory change: every operation
    type except `ad_reward` for `trip_revive` and `traffic_jam`, whose effects are counters.
  - **How.** `showAppToast` with the design's dark toast (`AppToast`, 008.5), no icon or button,
    for its default duration. It isn't shown on the trip route; it waits for the next screen.
  - **Proposed line** (for the owner's approval, owner-actions.md): «رصيدك اتظبط على آخر حساب»
    ("your balance was set to the latest count"). It names no item and doesn't apologize.
    String key `sync.balanceCorrected`.
- **Rejected:** a toast per rejection, and naming the item (Clarifications Q5).

## R15. The bootstrap, trusted time and the cached blocks

- **When.** After startup, on return to the foreground, and when the connection comes back, if the
  account is active and the last successful bootstrap was at least 60 s ago. A forced one ignores
  the spacing: after an account change, and from "sync now".
- **Time.** `anchorOnServer(server_time + rtt / 2, elapsedAtResponseMs: …)`. The midpoint corrects
  most of the request's delay, and M05's anchor never moves trusted time back anyway. The full state
  anchors the same way.
- **Cache.** One row, `server_info` (data-model.md), written by `DriftAccountStore`:
  - the last bootstrap's `state_version`, `content.version`, the `client` block, `entitlements`,
    `daily`, `comeback.claimable`, `server_time` and when it arrived;
  - the comeback lock (R16).

  The providers read it synchronously after startup, and offline (FR-015).
- **What follows the answer:**
  - the profile and providers go to `account`;
  - a `content.version` above the active pack's calls `ContentUpdater.check(force: true)`;
  - the `client` block goes to the update state (R18);
  - a `state_version` above the base's, with nothing pending, marks the state for fetching (R12);
  - and then a sync pass runs.
- **The wallet in the bootstrap isn't applied.** It changes nothing the state fetch or the next
  batch doesn't, and taking it without its operations' log would break the fold.

## R16. The comeback gift

- **Decision:**
  - **A seventh local operation, `comeback_gift`.**
    - Payload `{}`.
    - Effects: fuel to the maximum (a full tank is unchanged and still accepted), and
      `change_bag` + 1.
    - No reason and no ref.
    - The direction test lists it.
    - It sits on `EconomySync` (`grantComebackGift(id)`), not on `Economy`, so a screen can't skip
      the guard.
  - **The guard** (`ComebackGift.claim()` in `lib/core/sync/comeback_gift.dart`). A claim is
    allowed when:
    - the cached `comeback.claimable` is true;
    - no `comeback_gift` operation is pending;
    - and the cached flag arrived after the last claim's answer.

    Claiming sets `server_info.comeback_claimed_at_ms`. A bootstrap counts toward claimability only
    if it arrived after the claim's operation was answered. So a stale "claimable" from before the
    claim, or one received while the claim waits in the outbox, never allows a second claim (B03
    hand-over).
  - It works offline, from the cached flag (`Returning`'s "Offline: grant locally").
  - M13's `Returning` dialog calls `claim()` with one request id per tap.
- **Rejected:** claiming automatically on bootstrap. The design's «خدها» makes it the player's
  action.

## R17. The connection state and the offline banner

- **Decision:** `ServerReach` (`lib/core/sync/server_status.dart`) combines two signals:
  - the link, from M04's `ConnectivitySource`;
  - the last request outcome, from `ApiClient`.

  It is `offline` while the link is down, or since a request ended `ApiUnreachable` with no success
  after it. It turns `online` after a successful bootstrap followed by a pass with no network
  failure (`States` 1: "hides when the network is back and bootstrap + sync succeed"). A bootstrap
  earlier in the session counts: R15 spaces bootstraps, so after a short drop the next one may be
  minutes away, and waiting for it would keep the banner up while the sync works.
- `isOnlineProvider` gives later features their «محتاج نت» signal (FR-032).
- **Placement:** `HomeStatusArea` (`lib/features/home/home_status_area.dart`), at the top of the Home
  placeholder in every flavor. It holds `OfflineBanner` with `home.offline` from the string file.
  M08 places the same widget on its Home.
- **Rejected:** pinging `/healthz`. Real requests already tell the state, and a ping is network use
  with no purpose.

## R18. The update states (Clarifications Q2)

- **Decision:** an `UpdateState` notifier: `none`, `optional(latestVersion)` or `forced`.
  - **`forced`:** from a live bootstrap with `client.force_update: true`, or from any `426`. It is
    kept in memory only, so a launch with no network plays on (Q2).
  - **`optional`:** when `client.latest_version` is above the app's version (`ClientVersion`
    comparison, M04) and the update isn't forced. It is shown once per latest version: the dismissed
    version goes to the preference store (`SettingsStore`), which isn't a secret.
- **Shown by `StatusOverlayHost`,** in `WassalApp.builder` above the router. It is never shown
  while the trip route is visible (FR-033): it shows when the route changes.
  - **`forced`:** the design's `StatusCard.update` inside an `AppDialog` over a `Scrim`. There is no
    close button, a `PopScope(canPop: false)`, and taps outside are ignored.
  - **`optional`:** the same card with a tertiary «بعدين» button. It closes with back too.
  - The strings are `update.title`, `update.message`, `update.cta` and `update.later`.
- **The store link:** `StoreLauncher`, an interface over `url_launcher` 6.3.3 in
  `LaunchMode.externalApplication`.
  - Android opens `https://play.google.com/store/apps/details?id=<applicationId>`, with the
    flavor's id, so it opens the Play app.
  - iOS has no App Store listing yet (no paid Apple account), so `iosAppStoreId` is empty and the
    button isn't drawn. The card still blocks. The owner fills the id when the listing exists
    (owner-actions.md). Until B10, nothing makes iOS (or Android) forced anyway.
- **Rejected:** Play's in-app updates API: another plugin, Android only, and it can't express "the
  server says forced".

## R19. Maintenance

- **Decision:** a `503` whose code is `maintenance`, from any player endpoint, sets
  `maintenance(untilMs?)`:
  - The sync holds until the next resume (R9).
  - The bootstrap still runs, since B10 blocks only writes.
  - The state clears on the next successful sync pass.
  - `HomeStatusArea` shows `StatusCard.maintenance` in the banner's place:
    - with `details.until` (ISO-8601 UTC), the line is `maintenance.messageAt` with the device's
      local time, formatted as hours and minutes in the player's digit style;
    - without it, the line is `maintenance.message` («المشاوير شغالة أوفلاين.»).
  - Precedence: the offline banner wins over the card (FR-033).
- **Hand-over to B10:** the field `details.until` is proposed here. B10 decides its name and records
  it in backend §6.2 and its contracts. The app ignores an absent or malformed value.
- `503 dependency_unavailable` is not maintenance: it is a server error, with backoff.

## R20. Two interfaces for the economy

- **Decision:** M05's review asked for the sync's calls to be out of the screens' reach.
  - **`Economy`** (screens) keeps the views, the request ids and the player's requests.
  - **`EconomySync`** (`lib/core/economy/economy_sync.dart`) holds:
    - `pendingOps`, `pendingCount` and `highestAnsweredSeq`;
    - `applyAnswer`, `replaceFromServer`, `adoptAccount` and `setAside`;
    - `grantComebackGift`;
    - `baseInfo` (state version and player).

    `EconomyService` implements both. `economySyncProvider` is read only under `lib/core/sync/`
    and `lib/core/account/`, which a guard checks. M05's `markAccepted`, `markRejected` and
    `replaceBase` leave the public interface. Their store methods stay, and `applyAnswer` uses them
    inside one transaction.
- **Lifecycle work runs behind requests** (M05's review). `handleLifecycle`'s clock resync and
  `anchorOnServer` now go through the service's serial queue, so a resync never lands between a
  request's validation and its commit.
- **Rejected:** a second service writing the economy's tables. The store stays the only writer
  (constitution IV, client side).

## R21. Database v3

- **Decision:** `schemaVersion` 3, with its step in `AppDatabase.upgradeSteps`, generated by
  `drift_dev make-migrations` along with its schema JSON and tests.
  - **New `account`:** one row, inserted by the upgrade and at creation, with `status = none`.
  - **New `server_info`:** one row, empty until the first bootstrap.
  - **`projection_base` gains `player_id`** (TEXT, nullable).
  - **`ownership.acquired_by` becomes nullable.** This is a table rebuild through drift's
    `TableMigration`.
  - Every column stays INTEGER or TEXT.
  - Only `DriftAccountStore` writes `account` and `server_info`, and only the economy store writes
    the rest. The repo guards extend to both.
- **Rejected:** keeping the profile and cache in the preference store. Auto Backup restores it to a
  fresh database (R5), and the providers read it synchronously after startup either way.

## R22. Status on internal builds

- **Decision:** `SyncStatusCard` (`lib/features/dev/sync_status_card.dart`) on the playtest Home,
  beside `TripList` and `GalleryEntry` (router, dev and staging only). It shows:
  - the player id's first 8 characters and the providers;
  - the pending count and the base's state version;
  - the last pass's start, end and outcome, the last error code, and the set-aside count;
  - and a «sync now» button, which forces a bootstrap and a pass.

  No token or install id is shown. Its strings are English identifiers, as the trip's debug panel's
  are. Production builds don't route to it.
- **Rejected:** adding it to the trip's debug panel. Sync is gated off on the trip route.

## R23. Testing

- **Fakes:**
  - `FakeApi`, a scriptable `ApiClient` with answers per call, delays, drops and failures;
  - in-memory `InstallIdStore` and `SessionStore`;
  - M05's in-memory economy helpers;
  - a fake route signal.
- **Unit and service tests** for every row of R4, R7, R13, R16, R18 and R19, the first-open wait
  (R6), the rebase (R11) and the state mapping (R12).
- **The property test** (`test/core/sync/sync_property_test.dart`). A seeded property test runs
  1,000 sequences (SC-003) against `ModelServer`, a Dart model of B03's batch semantics:
  - idempotency by id;
  - in-order processing;
  - rejections drawn by the seed, with dependents rejected too;
  - the wallet from M05's own rules;
  - `state_stale` when a second client writes.

  Each sequence mixes recorded operations, lost answers, retries, kills before an answer is
  applied, and stale answers. After the queue drains, it checks that the device's view equals the
  model's state and that the model applied no operation twice.
- **Against the real stack** (`test/backend/`, tag `backend`, FR-042). The tests run on the host
  against the dev compose stack (`WASSAL_E2E_API`, default `http://localhost:8000`), with no Flutter
  test binding, so `dart:io` HTTP is real. The stack is seeded with the sample pack as version 1,
  the version dev builds bundle, by `test/backend/seed_backend.py` through `manage.py shell`
  (publishing has no command of its own). The scenarios:
  1. offline play then sync, with the connection cut at random points (SC-004);
  2. a second session on the same player makes the first stale;
  3. an ended session recovers through the install id.

  Staff adjustments and room rewards reaching the phone are covered against `FakeApi`.

  A new CI job, `sync-e2e` in `mobile.yml`, starts the stack and runs them when files under
  `lib/core/{account,sync,network,economy}/`, `test/backend/`, `backend/apps/{accounts,economy,progress}/`
  or `contracts/openapi.yaml` change.
- **Goldens:**
  - Home's placeholder with the offline banner, and with the maintenance card (with and without the
    time);
  - the forced and optional update cards over Home;
  - the toast.

  All in RTL with both digit styles. The `States` board's own golden and layout test are 008.5's
  and stay. The new screens reuse its components unchanged.
- **Coverage** stays at 80% or more.

## R24. Dependencies

| Package | Version | Why | Notes |
| --- | --- | --- | --- |
| `flutter_secure_storage` | ^11.2.0 | tokens; the install id on iOS | locked stack; Swift Package on iOS (`flutter_secure_storage_darwin`), so no Podfile; minSdk 24 |
| `url_launcher` | ^6.3.3 | the store listing | Flutter team; Swift Package on iOS |
| `play-services-auth-blockstore` | 16.4.0 | the install id on Android | Gradle, in `android/app/build.gradle.kts` |
| `shared_preferences_android` | ^2.5.1 | the install id's file on Android (R1) | in the lock already as a transitive dependency; direct now, because `AndroidInstallIdStore` imports its Android options |

Already present: `dio`, `uuid`, `connectivity_plus`, `drift`, `shared_preferences`. Each version
is more than two weeks old (11.2.0: 2026-09-16; 6.3.3: 2026-10-02).

## R25. Documents updated in this PR

- `docs/architecture-mobile.md`:
  - §11 (the `account` and `server_info` tables, the backup rules for the secure store);
  - §12 (the rebase, the trip-route gate, the toast, the set-aside reasons);
  - §16 (the install id per platform, the session key, the first-open wait).
- `docs/architecture-backend.md`: §22.6's note that the device side is resolved here (R1).
- `docs/delivery-plan.md`: step 6's "Resolved in M06" line, and the Progress list (009 and 010
  merged in #15 and #16; 011 when it merges).
- `CLAUDE.md`: the `sync-e2e` command, and the account and sync stores in the writers rule.
- `docs/owner-actions.md` (at `/speckit-implement`):
  - approve the toast's line;
  - fill `iosAppStoreId` once the App Store listing exists;
  - check a re-install on the Redmi Note 7 with Google backup on;
  - run the `sync-e2e` scenarios against staging once.

## Handed to later features

- **M07:**
  - route `firstOpenOutcomeProvider` (`newPlayer`, `offline` and `timedOut` to the intro,
    `restored` to Home);
  - react to `progressRestoredProvider`;
  - add `tutorial_gift` and `settings_update` as local operations;
  - map `grants.tutorial` and the profile's name in R12's mapping.
- **M08:** put `HomeStatusArea` on the real Home (`HomeStates`).
- **M10:** add `story_progress` and `claim_request`, with their `content_version` (R10), and map
  `story` (R12).
- **M11:** `ad_reward` already syncs. Read `isOnlineProvider` for «محتاج نت».
- **M12:** read the cached entitlements and `isOnlineProvider`, and send its purchase verification
  through `AuthorizedApi`.
- **M13:**
  - the `Returning` dialog on `ComebackGift`;
  - `daily` from `server_info`;
  - map `stats` and `longest_streak`.
- **M14:**
  - Google sign-in and the linking screens on `AccountService.link`;
  - what `account_deleted` shows;
  - account deletion;
  - push tokens through `AuthorizedApi`.
- **M15:** report the set-aside, rejected and dropped operations and the renewal failures, from the
  engine's event stream.
- **M17:** the subscriber's tank from the cached entitlements and the wallet's `fuel_max`.
- **B10:**
  - the maintenance answer and its `details.until` (R19);
  - `426` (R18).
