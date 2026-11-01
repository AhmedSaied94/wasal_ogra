# Contract: `story_progress` and `claim_request` on the Phone, and the Confirmed View

The two operations M10 records through M05's economy, their wire form for M06's sync, the server's
`story` block mapped into the phone's state, schema 5, and how the phone tells a pending reward from
a received one. Research R5, R6; spec FR-024, FR-044, FR-052–FR-055. Tests first (constitution
XIII).

## Operations (`lib/core/economy/domain/`)

### `op.dart`

```dart
enum OpType {
  // … existing …
  storyProgress('story_progress'),
  claimRequest('claim_request'),
}

final class StoryProgressRequest extends OpRequest {
  const StoryProgressRequest({required this.chapterId, required this.sceneId});
  final ChapterId chapterId;
  final String sceneId;
}

final class ClaimRequest extends OpRequest {
  const ClaimRequest({required this.requestId});
  final String requestId;
}
```

### `story_rules.dart` (new, beside `profile_rules.dart` and `gift_rules.dart`)

| Op | `validate` (first failure wins) | `apply` | `stillValid` (on replay over a new base) |
| --- | --- | --- | --- |
| `story_progress` | the chapter and the scene are in the active pack, the scene in that chapter → else `unknown_sku`; the scene not in `scenesSeen[chapter]` → else `already_recorded` | `scenesSeen[chapter] += sceneId` | unknown ids are kept (M04's rule); seen again in the new base → no-op |
| `claim_request` | the request is in the pack → else `unknown_sku`; not in `requestsClaimed` → else `already_granted`; its item owned and, when it names a variant, `variantOf(item) == variant` → else `not_eligible` | `requestsClaimed += requestId`; balances unchanged | claimed in the new base → no-op; no longer eligible → dropped like other invalid ops (M06's rule) |

- `already_recorded` and `already_granted` are refusals that store nothing (`OpRefused`), so a replay
  of a scene or a double tap writes no row.
- `EconomyRefusal` gains `alreadyRecorded('already_recorded')`. `unknownSku`, `alreadyGranted` and
  `notEligible` exist (M05, M07).
- **Unlock order is the caller's rule,** as for M05's `buy`:
  - the economy domain may not import `core/progress/domain/` (`domain_imports_test`), so
    `story_progress` doesn't check that the chapter is unlocked;
  - `StoryService.recordSeen` records only a scene whose `sceneState` isn't `locked` (story-flow.md);
  - the server still refuses `not_unlocked`, through M06's rollback.
- `requestMatches` (same id, same request): the request's fields compared as M07's rules do.
- `Economy` gains two calls that take a held id, as `buy` does:

```dart
Future<OpOutcome> recordScene(TxnId id, {required ChapterId chapterId, required String sceneId});
Future<OpOutcome> claimRequest(TxnId id, {required String requestId});
```

### `economy_state.dart`

```dart
final Map<String, Set<String>> scenesSeen;   // chapter wire → scene ids
final Set<String> requestsClaimed;
```

- Both are unmodifiable and part of `==`/`hashCode`.
- In the canonical JSON (`projection_base.state`) they are written as `"scenes_seen": {"ch1_first_job":
  ["opening", …]}`, sorted, and `"requests_claimed": [ … ]`, sorted.
- `EconomyState.newPlayer` starts both empty.

### `economy.dart` (`EconomyView`)

```dart
Map<String, Set<String>> get scenesSeen;   // the projection's, from EconomyState
Set<String> get requestsClaimed;           // the projection's
final ConfirmedState confirmed;            // the base, read only

final class ConfirmedState {
  bool owns(SkuKind kind, String skuId);
  String? variantOf(String itemId);
  Map<String, TripProgress> get progress;
  Map<String, Set<String>> get scenesSeen;
  Set<String> get requestsClaimed;
}
```

`playerProgressOf` gains an overload over `ConfirmedState`, so the progress rules run on the base the
same way they run on the projection.

## Storage (schema 5)

| Change | Step `_toV5` |
| --- | --- |
| `ledger_ops.op_type`'s `isIn` list gains the two types | `alterTable(TableMigration(schema.ledgerOps))`, M07's step 4 way; rows kept |
| `player_state` + `scenes_seen TEXT NOT NULL DEFAULT '{}'`, `requests_claimed TEXT NOT NULL DEFAULT '[]'` | `alterTable(TableMigration(schema.playerState))` |

- Run `fvm dart run drift_dev make-migrations`, then commit `drift_schemas/app/drift_schema_v5.json`,
  the generated steps and `test/drift/app/` tests.
- `DriftEconomyStore` writes and reads the two columns in the same transaction as the rest of
  `player_state`, and `takeServerState` writes them from the server's state. It stays the only writer
  (`economy_writes_test`).

## Wire (`lib/core/sync/domain/op_wire.dart`)

```dart
const contentVersionTypes = {
  OpType.tripStart, OpType.spendJenehat, OpType.spendBonat,
  OpType.storyProgress, OpType.claimRequest,   // M10
};
```

| Op | Payload sent | Server (B03, unchanged) |
| --- | --- | --- |
| `story_progress` | `{"chapter_id": "ch4_salon", "scene_id": "family_visit", "content_version": 12}` | `ops/story.py`: `unknown_sku`, `not_unlocked`; a repeat is accepted unchanged; then `pay_completions` |
| `claim_request` | `{"request_id": "req_nagafa_crystal", "content_version": 12}` | `ops/grants.py`: `unknown_sku`, `already_granted`, `not_eligible`; grants `reward_bonat` (`request_reward`) |

- M06 treats the server's refusals as for any operation: roll back, with one neutral message (M06's
  rules). A refused `claim_request` puts the request back in the list.

## The server's state (`lib/core/sync/domain/state_snapshot.dart`)

`StateSnapshot` gains a typed `story` from the existing OpenAPI shape (`Story`, `ChapterState`):

```dart
final class StateStory {
  final List<StateChapter> chapters;     // chapter_id, status, scenes_seen
  final List<String> requestsClaimed;
}
```

- `stateFromSnapshot` maps `chapters[].scenes_seen` into `scenesSeen`, keyed by `chapter_id`, and
  `requests_claimed` into `requestsClaimed`.
- `status` isn't stored: completion is derived (FR-051).
- A chapter or scene the active pack lacks is kept.
- The doc comment "`story` … isn't mapped yet (M10, M13)" becomes "`stats` isn't mapped yet (M13)".

## Pending rewards (`lib/core/progress/domain/rewards.dart`, pure)

```dart
sealed class RewardSource { }   // RoomReward(roomId), ChapterReward(chapterId), RequestReward(requestId)

final class PendingReward { final RewardSource source; final int bonat; }

List<PendingReward> pendingRewards(
  ContentSource c, PlayerProgress projection, PlayerProgress confirmed,
  Set<String> claimed, Set<String> claimedConfirmed);
```

| Source | Pending when | `bonat` |
| --- | --- | --- |
| room | `roomComplete(c, projection, r)` and not `roomComplete(c, confirmed, r)` | `room.completion_bonat` |
| chapter | `chapterComplete(c, projection, ch)` and not `chapterComplete(c, confirmed, ch)` | `chapter.completion_bonat` |
| request | in `claimed` and not in `claimedConfirmed` | `request.reward_bonat` |

- `pendingRewardsProvider` watches `economyViewProvider` and `contentSourceProvider`.
- A new player before the first sync has an empty base, so every completion is pending until then.

## Tests (first)

- `test/core/economy/domain/story_rules_test.dart`: every refusal in order; apply; replay over a base
  that already has it; the claim never changes `bonat`.
- `test/core/economy/economy_service_test.dart`: the two calls, a held id repeated (`repeated: true`),
  the refused repeat storing no row.
- `test/core/economy/domain/economy_state_test.dart`: the canonical JSON round trip with the two
  fields.
- `test/core/sync/domain/op_wire_test.dart`: both payloads with `content_version`.
- `test/core/sync/domain/state_snapshot_test.dart`: `story` mapped; unknown ids kept.
- `test/drift/app/migration_test.dart` (generated) and a v4 database with rows opened at v5.
- `test/core/progress/rewards_test.dart`: each source pending, then received after the base moves.
- `test/backend/story_sync_test.dart` (tag `backend`): a scene recorded and a claim granted once
  against the dev stack; a state replacement restores both.
