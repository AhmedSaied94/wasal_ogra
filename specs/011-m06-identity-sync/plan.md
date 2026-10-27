# Implementation Plan: Identity, Bootstrap and Sync (M06)

**Branch**: `011-m06-identity-sync` | **Date**: 2026-10-27 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/011-m06-identity-sync/spec.md`

## Summary

M06 connects the app to the server that B02 and B03 built. It covers:

- **An install id that survives a re-install.** On Android it lives in Block Store, with a
  backed-up preference file as the fallback. On iOS it lives in the keychain, on this device only.
  This resolves the device side of backend §22.6 (research R1).
- **An account made in the background.**
  - `POST /v1/auth/anonymous` runs on the first contact.
  - The session sits in `flutter_secure_storage`, written in one step.
  - B02's renewal, retry-window and sign-in-again rules run in one `AuthorizedApi` that every player
    call goes through (R2–R4).
- **The first open's 3-second wait** (Clarifications Q1). A returning player's state is taken
  before boot hands over; a later restore is announced for M07 (R5, R6).
- **Account changes and deletion.**
  - A different player's state replaces the phone's, and the old operations are dropped as rejected
    `account_changed`.
  - `account_deleted` stops every player call.
  - The link request is here, and its screens are M14's (Clarifications Q3; R7, R8).
- **The sync.**
  - One runner, triggered at the moments that matter and closed while the trip screen shows
    (Clarifications Q4).
  - Batches of up to 100 operations, within the size limit, with `content_version` added.
  - Each answer is applied in one transaction that rebases the projection on the server's wallet.
  - The full state is fetched when the server is ahead.
  - Every refusal of a whole request has a defined reaction (R9–R13).
- **The bootstrap**, which anchors trusted time on the server's, caches the entitlements, daily
  state, comeback flag and app versions, and forces a pack check on a newer content version
  (R15).
- **The comeback gift**: a local operation that gives no BONAT, with a guard so a claim is never
  sent twice (R16).
- **The three states on screen.**
  - The offline banner and the maintenance card go on Home.
  - The forced and optional update cards go over everything but the trip.
  - One neutral toast follows a visible rollback (Clarifications Q2, Q5).
  - All use 008.5's components (R14, R17–R19).
- **The economy's sync calls move behind `EconomySync`**, which screens can't reach, as M05's review
  asked (R20).
- **Database v3** adds `account`, `server_info`, `projection_base.player_id`, and a nullable
  `ownership.acquired_by` (R21).

Technical approach and versions: [research.md](./research.md).

## Technical Context

**Language/Version**:

- Dart 3.13.5 with the FVM-pinned Flutter 3.47.7 (`.fvmrc`).
- Kotlin for the small `wassal/install_id` channel in `MainActivity.kt`.

**Primary Dependencies**:

- **New:**
  - `flutter_secure_storage ^11.2.0` (the locked stack's token store; a Swift Package on iOS);
  - `url_launcher ^6.3.3` (the store listing);
  - `com.google.android.gms:play-services-auth-blockstore:16.4.0` (Gradle);
  - `shared_preferences_android ^2.5.1`, already in the lock, now direct for its Android options,
    which write `wassal_install.xml` (R1).
- **Existing:** `dio`, `uuid`, `connectivity_plus`, `drift`, `shared_preferences`, Riverpod 3 with
  its generator, `content_models`.
- **Rejected:** Retrofit and OpenAPI client generation (R3); Play's in-app updates (R18).

**Storage**:

- **App database v3** (`<app support>/db/wassal.sqlite`):
  - new `account` and `server_info`;
  - `projection_base.player_id`;
  - `ownership.acquired_by` nullable;
  - `drift_schemas/app/drift_schema_v3.json` (data-model.md).
- **Secure storage:** `wassal.session`, plus `wassal.install_id` on iOS.
- **Android:** Block Store, and `wassal_install.xml`.
- **Preference store:** the dismissed optional-update version.

**Testing**:

- `flutter_test` with `FakeApi` and in-memory stores, on real SQLite.
- A seeded property test of 1,000 sequences against `ModelServer` (SC-003).
- Repo guards: sync-only access, the account tables' one writer, no secrets in logs or preferences,
  backup rules, domain imports.
- Goldens and layout checks for the placed states.
- `test/backend/` (tag `backend`) against the dev compose stack, run by the new `sync-e2e` CI job.
- Coverage ≥ 80% (R23).

**Target Platform**:

- **Android**, `minSdk 24`, `targetSdk 36`, all three flavors. Block Store needs Google Play
  services; without them, the preference file holds the id.
- **iOS 15.0** builds on Codemagic. Every new plugin is a Swift Package, so there is still no
  Podfile.
- **Linux** for CI.

**Project Type**: A mobile app feature in the `wassal` monorepo. It touches:

- `apps/mobile/lib/core/account/` (new), `lib/core/sync/` (new), `lib/core/network/api_client.dart`;
- the economy's sync interface and store;
- the boot step, the app builder and Home's status area;
- the Android channel, Gradle and backup rules;
- a CI job.

**Performance Goals**:

- Later launches add nothing to boot: cold start to Home stays under 3 s on the A06.
- The first open waits at most 3 s, and only with a network (SC-001).
- An account within 10 s of the first contact (SC-002).
- A 5,000-operation backlog of real play answered within 2 minutes, at ≥ 1 s between an answer
  and the next batch. It is never refused for rate or size, even at 8 KB per result (SC-005, R9).
- Applying an answer of 100 operations stays under 100 ms on the A06, so it never stalls a frame
  for long (it runs off the UI isolate, in drift's background connection).

**Constraints**:

- Offline-first: boot never waits except the first open's bounded wait.
- No background work.
- No sync while the trip route shows.
- Every player call through `AuthorizedApi`.
- Tokens only in secure storage, never logged.
- The install id is sent only to account creation.
- The economy tables are written only by the economy store, and the account tables only by
  `DriftAccountStore`.
- `ledger_ops` rows change only in their sync columns.
- Integer money in every DTO.
- HTTPS only outside dev.

**Scale/Scope**:

- 6 endpoints and 1 new local operation type.
- 2 new tables and 2 changed ones.
- About 30 new `lib/` files and 1 Kotlin channel.
- About 25 test files and 4 new or extended guards.
- 1 CI job, 9 strings and 5 document updates.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| # | Principle | Applies | How M06 satisfies it |
| --- | --- | --- | --- |
| I | Engine purity | No | No trip rule. The sync carries M01's `TripResult` as recorded. |
| II | Integer money | Yes | Every wire reader refuses non-integer amounts, counts and times. Times become integer milliseconds. The new columns are INTEGER or TEXT, under the no-REAL guard (R3, R21). |
| III | Parity | No | No rule, parameter or fixture change. |
| IV | Server authority | Yes | BONAT on the phone only ever comes from the server's wallet, through the rebase and the full state (R11, R12). The comeback gift adds fuel and a booster, never BONAT, and the direction test lists it (R16). Entitlements are a read-only cache, and a rejected spend rolls back through M05's fold. Every change still goes through the economy store's transactions, and `EconomySync` keeps the sync's calls out of the screens' reach (R20). |
| V | Offline-first | Yes | The account, bootstrap and sync run in the background, and play never waits for them. The one wait is the first open's ≤ 3 s, only with a network, which the owner chose (Clarifications Q1). Maintenance and outages degrade, never stop: trips work and the queue waits. A forced update isn't remembered offline (Q2), and «محتاج نت» has its signal (R17). |
| VI | Idempotency | Yes | Every operation keeps M05's UUIDv7 `client_txn_id`, and a lost answer is resent unchanged (R9, R10). The credential exchanges rely on their own credential: the install id, and the refresh token retried within 60 s (R4). Trusted time anchors on `server_time` and never moves back, and the server's state replaces the phone's (R11, R12, R15). The property test shows a replayed or retried queue converges to the server's state (R23). |
| VII | Content, not code | Yes | Prices and trips stay the pack's. `content_version` comes from each operation's recorded column (R10). The open trip's bound is read from the active pack (R12). |
| VIII | Tunable numbers | Yes | No balancing number is added. The 3 s wait, the backoff, spacing and debounce are technical bounds, as named constants. The tank size stays the tunables' (R11). |
| IX | No ads in a trip | No | No ad call. The sync also stays out of the trip (Q4). |
| X | RTL and Arabic first | Yes | Every placed state is in RTL with both digit styles, and its text is in `app_ar.arb` (server-states.md). The maintenance time follows the digit setting. |
| XI | Accessible minimums | Yes | 008.5's components already meet the minimums. Their placements keep the 44 pt targets and 12 pt text, the status semantics, and no movement under reduced motion. |
| XII | No runtime LLM | No | — |
| XIII | Small, testable features | Yes | One spec folder. Tests first for the token rules, the rebase, the state mapping and the comeback guard. A property test, guards, goldens, a migration test, and integration tests against the real stack (R23). Coverage ≥ 80%. |

**Locked stack.**

- `flutter_secure_storage` for tokens, as the constitution requires. `dio`, Riverpod with its
  generator, and drift as before.
- Each plugin sits behind an interface: `ApiClient`, `InstallIdStore`, `SessionStore`,
  `StoreLauncher`, plus M04's `ConnectivitySource`.
- The Block Store channel is Kotlin in the app, like M05's clock channel.

**Security & privacy.**

- **A security review is needed.** The constitution's list names auth, the ledger and sync, and
  this PR changes all three.
- **Tokens:** secure storage only, in one write. They are left out of Android backup, never in
  logs, preferences, analytics or crash reports, and guards check it (R2, contracts/ci-checks.md).
- **The install id** is a device credential:
  - it is sent only to account creation;
  - it is never logged or shown;
  - it is stored in the platform's private stores;
  - Android's backup, which is Google's encrypted backup, carries it, as B02 R5 decided.
- **No personal data:** the profile holds the player's own display name and level.
- **HTTPS only** outside dev, through M04's URL check (constitution 1.2.0).

**Performance budgets.**

- The cold start to Home is unchanged on later launches. The first open's bounded wait (at most
  3 s more, and only with a network) is the budget's own exception since constitution 1.6.0, so it
  is no longer a deviation.
- No background work.
- The trip's frame budget is untouched: no sync runs on the trip route.

**CI gates.**

- The mobile analyze, test and golden jobs are unchanged, with more tests.
- A new `sync-e2e` job runs against the backend's dev stack.
- The OpenAPI diff is unchanged: no backend change.

**Gate result (pre-research): PASS.** The first-open wait was first recorded below as a deviation.
`/speckit-analyze` found it had no time box, and constitution 1.6.0 (2026-10-27) made it the
cold-start budget's own exception.

**Gate result (post-design): PASS.** The re-check after Phase 1 found nothing new:

- the new domain folders import only what the extended guard allows;
- every new column is INTEGER or TEXT;
- `applyAnswer`, `replaceFromServer`, `adoptAccount` and `grantComebackGift` are store
  transactions;
- no path adds BONAT on the phone except taking the server's wallet;
- the wire payloads are B03's;
- the screens use 008.5's components unchanged.

## Project Structure

### Documentation (this feature)

```text
specs/011-m06-identity-sync/
├── plan.md                 # This file
├── research.md             # Phase 0: decisions R1–R25, hand-overs
├── data-model.md           # Phase 1: stores, domain values, tables v3, transitions, invariants
├── quickstart.md           # Phase 1: Part A automated, Part B on a device, done when
├── contracts/
│   ├── api-client.md       # ApiClient, AuthorizedApi, the token rules, what each endpoint reads
│   ├── account.md          # install id and session stores, AccountService, first open, changes, link
│   ├── sync.md             # EconomySync, the rebase, SyncEngine, gates, the wire, state mapping, comeback gift
│   ├── server-states.md    # ServerStatus, placements, StoreLauncher, strings, checks
│   └── ci-checks.md        # guards, tests, the sync-e2e job
├── checklists/requirements.md
└── tasks.md                # Phase 2 (/speckit-tasks), not created here
```

### Source Code (repository root)

```text
apps/mobile/
├── pubspec.yaml                                   # flutter_secure_storage, url_launcher
├── dart_test.yaml                                 # the `backend` tag
├── drift_schemas/app/drift_schema_v3.json         # NEW (make-migrations)
├── lib/
│   ├── bootstrap/
│   │   ├── startup.dart                           # starts AccountService.firstOpen after the database
│   │   ├── boot_progress.dart                     # BootStep.account
│   │   └── app.dart                               # SyncLifecycle; StatusOverlayHost in the builder
│   ├── core/
│   │   ├── network/
│   │   │   ├── http_client.dart                   # comment: the token is added per request (M06)
│   │   │   └── api_client.dart                    # NEW: ApiClient, ApiResult, DioApiClient
│   │   ├── account/                               # NEW
│   │   │   ├── domain/                            # InstallId, Session, Profile, AccountStatus, outcomes
│   │   │   ├── install_id_store.dart              # Android (channel + prefs), iOS (keychain), memory
│   │   │   ├── session_store.dart                 # secure storage, memory
│   │   │   ├── authorized_api.dart                # the token rules (contracts/api-client.md)
│   │   │   ├── account_service.dart               # first open, ensureSession, changes, deletion, link
│   │   │   ├── drift_account_store.dart           # the only writer of account and server_info
│   │   │   └── account_providers.dart
│   │   ├── sync/                                  # NEW
│   │   │   ├── domain/
│   │   │   │   ├── wire/                          # strict readers and writers for the six endpoints
│   │   │   │   ├── op_wire.dart                   # LedgerOp → wire (content_version)
│   │   │   │   ├── state_snapshot.dart            # /v1/state → EconomyState
│   │   │   │   └── batching.dart                  # 100 ops, 200 KiB, halving
│   │   │   ├── sync_engine.dart                   # passes, gates, triggers, backoff, refusals
│   │   │   ├── sync_lifecycle.dart                # resume, connectivity, ops recorded, trip route
│   │   │   ├── bootstrap_service.dart             # bootstrap, time anchor, cache, content check
│   │   │   ├── comeback_gift.dart                 # the guard
│   │   │   ├── server_status.dart                 # reach, maintenance, update
│   │   │   └── sync_providers.dart
│   │   ├── economy/
│   │   │   ├── economy.dart                       # sync calls removed from Economy
│   │   │   ├── economy_sync.dart                  # NEW: EconomySync
│   │   │   ├── economy_service.dart               # implements both; lifecycle work on the queue
│   │   │   ├── drift_economy_store.dart           # applyAnswer, replaceFromServer, adoptAccount, setAside
│   │   │   └── domain/                            # comeback_gift op; rebase(); Owned.acquiredBy nullable
│   │   ├── platform/store_launcher.dart           # NEW: url_launcher behind an interface
│   │   └── storage/                               # v3: tables, upgrade step
│   ├── features/
│   │   ├── home/home_status_area.dart             # NEW: banner and maintenance card on Home
│   │   ├── dev/sync_status_card.dart              # NEW: internal builds' account and sync status
│   │   └── boot/boot_screen.dart                  # waits for the first open (≤ 3 s)
│   ├── core/routing/router.dart                   # HomeStatusArea on Home; the card on playtest Home
│   └── l10n/app_ar.arb                            # nine strings (server-states.md)
├── android/app/
│   ├── build.gradle.kts                           # play-services-auth-blockstore
│   └── src/main/
│       ├── kotlin/com/wassalogra/app/MainActivity.kt   # wassal/install_id
│       └── res/xml/{data_extraction_rules,backup_rules}.xml   # the secure store's four files out; exclude-only
├── test/
│   ├── core/account/, core/sync/, core/economy/   # contracts/ci-checks.md "Tests"
│   ├── repo/                                      # new and extended guards
│   ├── goldens/server_states_goldens_test.dart
│   ├── backend/                                   # NEW: tag backend; seed_backend.py
│   └── helpers/{fake_api,model_server}.dart       # NEW
.github/workflows/mobile.yml                       # sync-e2e job
docs/architecture-mobile.md                        # §11, §12, §16
docs/architecture-backend.md                       # §22.6 note
docs/delivery-plan.md                              # step 6 resolved line; Progress
docs/owner-actions.md                              # M06 section (at /speckit-implement)
CLAUDE.md                                          # sync-e2e command; the account store in the writers rule
```

**Structure decision.**

- **`core/account/` and `core/sync/`.** Identity and sync are cross-feature state (mobile §10:
  "`core/economy` and `core/sync` providers"). Their pure parts go in `domain/` folders, under the
  domain-imports guard.
- **`features/home/` starts here** with one widget, `HomeStatusArea`, because the states belong to
  Home. M08 builds the rest of the folder.
- **No new package.** Nothing outside the app uses this code.

## Complexity Tracking

No deviations.

The first open's wait was recorded here until 2026-10-27. It lets a re-installed player land on
Home with their progress instead of replaying the intro (Clarifications Q1, FR-027, research R6).
Since constitution 1.6.0, it is the cold-start budget's own exception.
