# Contract: The Story's Scenes: When They Unlock, Where They Play, How They Are Recorded

The rules that turn the pack's scenes and the player's state into locked, waiting and seen scenes;
the one service that records a scene; the watcher that makes goal scenes due; and the changes to
M07's and M08's merged code. Research R2–R4; spec FR-028–FR-033, FR-052, FR-054.

## The rules (`lib/core/progress/domain/story.dart`, pure)

Imports: content models, the content source, the wire, the progress domain (the existing allowance).

```dart
sealed class SceneMoment { }        // Opening(), AfterTrip(tripId), GoalMet()
enum SceneState { locked, waiting, seen }

SceneMoment momentOf(Scene s);                                  // plays → Opening / AfterTrip; absent → GoalMet
bool sceneUnlocked(ContentSource c, PlayerProgress p, Chapter ch, Scene s);
SceneState sceneState(ContentSource c, PlayerProgress p, Map<String, Set<String>> seen, Chapter ch, Scene s);
List<(Chapter, Scene)> scenesInStoryOrder(ContentSource c);     // chapters by (order, id), then list order
List<(Chapter, Scene)> waitingScenes(ContentSource c, PlayerProgress p, Map<String, Set<String>> seen);
Scene? goalSceneOf(Chapter ch);                                 // the one scene without plays (V-C10)
Scene? afterTripSceneOf(ContentSource c, String tripId);        // the scene played after that trip (V-C4)
```

| Moment | Unlocked when |
| --- | --- |
| `Opening` | always |
| `AfterTrip(t)` | `p.finished(t)` (best stars ≥ 1) |
| `GoalMet` | `chapterComplete(c, p, ch.chapterId)` |

`seen` is `EconomyView.scenesSeen`, never M07's flags (research R3).

## Recording a scene (`lib/features/story/application/story_service.dart`)

```dart
final class StoryService {
  /// A scene was played to its end or skipped, the first time or not.
  Future<void> recordSeen(String sceneId);
  /// Once at boot, after the economy and the content are ready.
  Future<void> backfill();
}
```

- **`recordSeen`:**
  1. Finds the scene's chapter. An unknown scene id is ignored.
  2. Calls `FirstSessionService.sceneSeen(sceneId)`, which marks M07's flag; its step only rises
     (`reachStep`).
  3. **Rules first:** a scene whose `sceneState` is `locked` sends nothing. The economy doesn't check
     unlock order (economy-ops.md).
  4. Calls `economy.recordScene(heldId, chapterId:, sceneId:)`. `already_recorded` ends quietly.
     `OpWriteFailed` keeps the held id for the next call (M09's purchase rule).
- **`backfill`** records every id in `first_session.scenesSeen` that `EconomyView.scenesSeen` lacks
  (spec FR-052). It runs from `bootstrap/app.dart` once the economy and content providers resolve.
- **Callers:**
  - M07's `ScenePage._finished`: one line, `storyService.recordSeen` in place of
    `service.sceneSeen`, keeping `afterScene` and the navigation;
  - the scene viewer (scene-viewer.md).

## Goal scenes become due (`lib/features/story/application/story_due_watcher.dart`)

`StoryDueWatcher` (keepAlive, started in `bootstrap/app.dart` beside `HomeArrivalQueue` and
`LinesDotWatcher`) listens to `economyViewProvider`:

```text
for each chapter ch with a goal scene s:
  if chapterComplete(projection, ch) && !chapterComplete(confirmed, ch)
     && ch.goal.kind != completeRoom && sceneState(s) == waiting:
    firstSessionService.addSceneDue(s.sceneId)        // idempotent
```

- A completion that exists only in the projection came from an operation on this phone: the
  microbus bought in M09's sheet, a line finished by a trip.
- A state replacement brings it into the base too, so a restore makes nothing due (spec FR-054).
- Rooms are left out: `RoomDone` offers their scene (apartment.md), and «بعدين» leaves it waiting.

## Where scenes play (research R4)

| Trigger | Code | Route |
| --- | --- | --- |
| A due scene, at the arrival at Home | M07's `DueSceneArrival` (rank 10), changed below | in the first session `/onboarding/scene/:id?then=/home`; after it `/story/scene/:id?then=/home` |
| A due scene, before a trip starts | the router's `/trip` redirect from `beforeStart`, changed below | the same choice, with `then=/trip/<tripId>` |
| A story trip's scene, from «مشوار تاني» | `StoryAfterResultImpl` (M08's `storyAfterResultProvider`) | push `/story/scene/:id`, await, then M08 goes on |
| A finished room's scene | `RoomDone`'s «شوف المشهد» | `/story/scene/:goalSceneId?then=/apartment` |
| A waiting scene, from Home | `HomeSavingsCard` tap while `sceneWaiting` (M08 change) | `/story/scene/:firstWaitingId?then=/home` |
| A waiting room scene, from the rooms view | the chapter bar's «شوف المشهد» | `/story/scene/:id?then=/apartment` |
| A replay | the timeline's «شوف المشهد», the album's «اتفرج تاني» | `/story/:chapterId`, `/story/scene/:sceneId` |

**`StoryAfterResultImpl.after(tripId)`** plays the scene from `afterTripSceneOf(c, tripId)` when it
is `waiting`; otherwise it returns at once. M08 calls it only for story trips, from «مشوار تاني». A
return to Home instead meets the same scene through `DueSceneArrival`, since M07's `onView` made it
due.

## Changes to merged code

| File | Change |
| --- | --- |
| `features/onboarding/presentation/arrival_items.dart` (`DueSceneArrival.open`) | the location by `firstSession.inFirstSession` (table above) |
| `core/routing/router.dart` (the `/trip` redirect's `DueScene` case) | the same choice |
| `features/onboarding/presentation/scene_page.dart` (`_finished`) | `recordSeen` in place of `sceneSeen` |
| `features/home/presentation/savings_card.dart` | `onTap`: the first waiting scene while `sceneWaiting`, else `/apartment` as now |
| `features/home/domain/savings_target.dart` | `StoryEndTarget` (apartment.md, "The end of the story") |
| `features/result/application/result_slots.dart` | none: M10 overrides `storyAfterResultProvider` in its providers |
| `features/home/application/home_slots.dart` | none: M10 overrides `storySceneWaitingProvider` with `waitingScenes(...).isNotEmpty` |
| `core/routing/routes.dart` | `RouteNames.storyScene` (`/story/scene/:sceneId`), `RouteNames.storyAlbum` (`/story/album`), `RouteNames.apartmentPreTrip` (`/apartment/pre-trip/:tripId`); `ParamValidators.sceneId` = `^[a-z][a-z0-9_]{1,31}$`; `sampleParams` gains `sceneId: the_stand`, `tripId` reused |
| `core/routing/router.dart` | the new routes; the album and the scene route before `/story/:chapterId` (literal segments first); the screens in `_page` in place of `PlaceholderScreen` |

M07's goldens, its first-session integration test and its arrival rules are unchanged (Q5).

## Tests

- `test/core/progress/story_test.dart`: moments, unlock per moment, state, story order (the release
  draft's chapter 2 ordering), waiting, `goalSceneOf`, `afterTripSceneOf`.
- `test/features/story/application/story_service_test.dart`: `recordSeen` marks both stores once; a
  replay stores no op; backfill sends only the missing ones; a write failure keeps the id.
- `test/features/story/application/story_due_watcher_test.dart`:
  - a vehicle bought here makes its goal scene due;
  - a room completion doesn't;
  - a restored completion doesn't;
  - a restart with a pending completion is idempotent.
- `test/features/onboarding/arrival_items_test.dart` and the router's redirect test: the first-session
  location unchanged, the viewer after it.
- `test/features/result/story_after_result_test.dart`: plays a waiting scene, not a seen one, not after
  a failed trip.
- `test/features/home/savings_card_test.dart`: the tap while waiting.
