// The scene after a story trip (specs/015-m10-apartment-story, contracts/
// story-flow.md "Where scenes play"): M08's result calls it from «مشوار
// تاني» for a story trip, and the scene it names plays before M08 goes on.
import 'package:content_models/content_models.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/core/progress/domain/story.dart';
import 'package:wassal/features/result/application/result_slots.dart';

/// Plays the scene that comes after [after]'s trip when it is waiting;
/// otherwise returns at once: a trip with no scene, a scene seen, or a trip
/// not finished (so its scene is still locked).
final class StoryAfterResultImpl implements StoryAfterResult {
  StoryAfterResultImpl({
    required this._content,
    required this._progress,
    required this._seen,
    required this._push,
  });

  final ContentSource Function() _content;
  final PlayerProgress Function() _progress;
  final Map<String, Set<String>> Function() _seen;

  /// Pushes a location and completes when it is popped.
  final Future<void> Function(String location) _push;

  @override
  Future<void> after(String tripId) async {
    final content = _content();
    final scene = afterTripSceneOf(content, tripId);
    if (scene == null) return;
    final chapter = _chapterOf(content, scene);
    if (chapter == null) return;
    final state = sceneState(content, _progress(), _seen(), chapter, scene);
    if (state != SceneState.waiting) return;
    await _push('/story/scene/${scene.sceneId}');
  }

  static Chapter? _chapterOf(ContentSource content, Scene scene) {
    for (final (chapter, candidate) in scenesInStoryOrder(content)) {
      if (candidate.sceneId == scene.sceneId) return chapter;
    }
    return null;
  }
}
