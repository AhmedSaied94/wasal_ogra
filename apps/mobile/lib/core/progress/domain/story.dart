// The story's scenes: their moment, whether they unlocked, and whether they
// are waiting or seen (specs/015-m10-apartment-story, contracts/story-flow.md
// "The rules", research R2-R4). Pure: the screens, the due watcher and the
// album all read these.
//
// `seen` is the economy's `scenesSeen`, never M07's first-session flags
// (research R3).
import 'package:content_models/content_models.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/economy/domain/wire.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/core/progress/domain/unlocks.dart';

/// When a scene plays by itself.
sealed class SceneMoment {
  const SceneMoment();
}

/// At the first open, before the Name card (M07).
final class Opening extends SceneMoment {
  const Opening();
}

/// Right after the trip's first finish (M07).
final class AfterTrip extends SceneMoment {
  const AfterTrip(this.tripId);

  final String tripId;
}

/// When the chapter's goal is met: a scene without `plays` (M10).
final class GoalMet extends SceneMoment {
  const GoalMet();
}

enum SceneState { locked, waiting, seen }

/// [scene]'s moment: `plays` says so, and its absence means the chapter's
/// goal met it (M10).
SceneMoment momentOf(Scene scene) => switch (scene.plays?.kind) {
  ScenePlaysKind.opening => const Opening(),
  ScenePlaysKind.afterTrip => AfterTrip(scene.plays?.tripId ?? ''),
  null => const GoalMet(),
};

/// Whether [scene] can play: always for the opening, after its trip's first
/// finish, or once [chapter] is complete.
bool sceneUnlocked(
  ContentSource c,
  PlayerProgress p,
  Chapter chapter,
  Scene scene,
) => switch (momentOf(scene)) {
  Opening() => true,
  AfterTrip(:final tripId) => p.finished(tripId),
  GoalMet() => chapterComplete(c, p, chapter.chapterId),
};

/// A scene nobody has unlocked is locked; an unlocked one is seen or
/// waiting.
SceneState sceneState(
  ContentSource c,
  PlayerProgress p,
  Map<String, Set<String>> seen,
  Chapter chapter,
  Scene scene,
) {
  if (!sceneUnlocked(c, p, chapter, scene)) return SceneState.locked;
  final chapterWireName = chapterWire[chapter.chapterId]!;
  return seen[chapterWireName]?.contains(scene.sceneId) ?? false
      ? SceneState.seen
      : SceneState.waiting;
}

/// Every scene of the pack in story order: chapters by `(order, chapter_id)`,
/// then each chapter's own list order.
List<(Chapter, Scene)> scenesInStoryOrder(ContentSource c) => [
  for (final chapter in chaptersInOrder(c))
    for (final scene in chapter.scenes) (chapter, scene),
];

/// The scenes waiting to play, in story order.
List<(Chapter, Scene)> waitingScenes(
  ContentSource c,
  PlayerProgress p,
  Map<String, Set<String>> seen,
) => [
  for (final (chapter, scene) in scenesInStoryOrder(c))
    if (sceneState(c, p, seen, chapter, scene) == SceneState.waiting)
      (chapter, scene),
];

/// The chapter's goal scene: its one scene without `plays` (V-C10), else
/// null.
Scene? goalSceneOf(Chapter chapter) {
  for (final scene in chapter.scenes) {
    if (momentOf(scene) is GoalMet) return scene;
  }
  return null;
}

/// The scene that plays after [tripId]'s first finish (V-C4), else null.
Scene? afterTripSceneOf(ContentSource c, String tripId) {
  for (final (_, scene) in scenesInStoryOrder(c)) {
    if (momentOf(scene) case AfterTrip(tripId: final id) when id == tripId) {
      return scene;
    }
  }
  return null;
}
