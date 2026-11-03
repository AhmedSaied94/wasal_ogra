# Contract: Economy and Sync Changes

## `Economy` (M05's interface) gains

```dart
/// Records that a piggy reward was shown (research R13). A second for the same nonce is
/// `OpRefused(alreadyRecorded)` and stores nothing.
Future<OpOutcome> markAdRewardSeen(TxnId id, {required String nonce});

/// Whether an `ad_reward_seen` for [nonce] is stored, whatever its sync status.
Future<bool> adRewardSeen(String nonce);

/// Non-rejected `ad_reward` rows for [placement] whose trusted time falls on [gameDay] (R9).
Future<int> adRewardsOn(AdPlacement placement, String gameDay);

/// The count of `trip_start` rows (R10).
Future<int> tripStarts();
```

The reads go to the store's log. Startup still reads only the materialized tables (M05).

## `OpType.adRewardSeen` (`ad_reward_seen`)

- Payload `{"nonce": "<uuid>"}`. No deltas.
- `fold`: skipped. `stillValid`: always true.
- M06's `op_wire.dart` sends it like any other operation. An accepted answer changes nothing; a
  rejected one (not expected) is set aside silently.
- M06's rollback toast never counts it.

## `ad_reward`: unchanged

The four client placements, as M05 built them (`ad_rules.dart`). The daily refill cap is checked by
`AdsService` before the call (research R9), and the server refuses `cap_reached` past it. The
`morning_piggy` placement stays refused `server_only`.

## Bootstrap and `server_info`

- `BootstrapSnapshot` gains `ads: AdsBlock` (data-model.md), parsed leniently: a missing block is
  the empty block.
- `DriftAccountStore` writes the block's canonical JSON to `server_info.ads` with the rest of the
  bootstrap, and `ServerInfo.ads` reads it back.
- `adsBlockProvider` (in `sync_providers.dart`) exposes it beside `entitlementsProvider` and
  `dailyBlockProvider`.

## The piggy's lookup

`PiggyApi.lookup(String nonce) → PiggyLookup`, over `AuthorizedApi`:
`GET /v1/ads/rewards/{nonce}`.

- 200 `granted` → `Granted`.
- 200 `refused` → `Refused`.
- 404 → `NotYet`.
- Network errors and 5xx → `NotYet`.
- 401 goes through the session renewal, as every player call does.
- 426 and 503 reach M06's server-state handling, as every call does.

## `SyncTrigger.adReward`

A new trigger, which `PiggyService` requests after a granted lookup. The pass fetches the state,
because `state_version` moved, and rebases the projection (research R12).

## Schema 6

See data-model.md. `AppDatabase.upgradeSteps` gains `from5To6`, and `test/drift/` gets its schema
and migration tests.
