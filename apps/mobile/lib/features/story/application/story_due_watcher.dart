// The goal scenes due (specs/015-m10-apartment-story, contracts/
// story-flow.md "Due", research R3): a chapter completed on this phone makes
// its goal scene due; a room's completion doesn't (RoomDone offers it), and
// a completion the server's state brought makes nothing due.
import 'package:content_models/content_models.dart';
import 'package:flutter/foundation.dart' show FlutterError, FlutterErrorDetails;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/progress/application/player_progress_provider.dart';
import 'package:wassal/core/progress/domain/story.dart';
import 'package:wassal/core/progress/domain/unlocks.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';

part 'story_due_watcher.g.dart';

final class StoryDueWatcher {
  StoryDueWatcher(this._content, this._flags);

  final ContentSource _content;
  final FirstSessionFlagsNotifier _flags;

  /// The economy's view went from [previous] to [next]: a chapter that is
  /// complete now but not in the confirmed base was completed here.
  Future<void> onView(EconomyView previous, EconomyView next) async {
    final before = playerProgressOf(previous, _content);
    final after = playerProgressOf(next, _content);
    final confirmed = playerProgressOfConfirmed(next.confirmed, _content);
    for (final chapter in chaptersInOrder(_content)) {
      if (chapter.goal.kind == GoalKind.completeRoom) continue;
      if (!chapterComplete(_content, after, chapter.chapterId)) continue;
      if (chapterComplete(_content, confirmed, chapter.chapterId)) continue;
      if (chapterComplete(_content, before, chapter.chapterId)) continue;
      final scene = goalSceneOf(chapter);
      if (scene == null) continue;
      await _due(scene.sceneId);
    }
  }

  /// The view's listener doesn't await [onView], so a failed write is
  /// reported here rather than left as an unhandled error; the scene then
  /// isn't offered after this completion.
  Future<void> _due(String sceneId) async {
    try {
      await _flags.addSceneDue(sceneId);
    } on Exception catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack, library: 'story'),
      );
    }
  }
}

@Riverpod(keepAlive: true)
StoryDueWatcher storyDueWatcher(Ref ref) {
  final watcher = StoryDueWatcher(
    ref.watch(contentSourceProvider),
    ref.watch(firstSessionFlagsProvider.notifier),
  );
  ref.listen(economyViewProvider, (previous, next) {
    if (previous == null) return;
    watcher.onView(previous, next);
  });
  return watcher;
}
