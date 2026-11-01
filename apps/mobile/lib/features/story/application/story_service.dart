// Recording a scene as seen (specs/015-m10-apartment-story,
// contracts/story-flow.md "Recording a scene", research R3): M07's flag and
// one `story_progress` through the economy, with one held request per scene.
import 'package:content_models/content_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/progress/application/player_progress_provider.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/core/progress/domain/story.dart';
import 'package:wassal/features/onboarding/domain/first_session.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';

part 'story_service.g.dart';

/// Marks a scene seen for M07 and the projection (research R3).
final class StoryService {
  StoryService(
    this._economy,
    this._content,
    this._flags,
    this._progress,
    this._seen,
  );

  final Economy _economy;
  final ContentSource _content;
  final FirstSessionFlagsNotifier _flags;
  final PlayerProgress Function() _progress;
  final Set<String> Function() _seen;

  /// The request id held per scene, so a retry after a failed write sends
  /// the same intent.
  final _held = <String, TxnId>{};

  /// Records [sceneId]: M07's flag, then a `story_progress`. A replay, or a
  /// scene the pack lacks or hasn't unlocked, sends nothing.
  Future<void> recordSeen(String sceneId) => _record(sceneId, markFlag: true);

  /// [recordSeen], with M07's flag written only when [markFlag]: the
  /// backfill sends scenes M07 already holds, so it leaves the flag alone.
  Future<void> _record(String sceneId, {required bool markFlag}) async {
    final chapter = _chapterOf(sceneId);
    if (chapter == null) return;
    final scene = chapter.scenes.firstWhere((s) => s.sceneId == sceneId);
    if (!sceneUnlocked(_content, _progress(), chapter, scene)) return;
    if (_seen().contains(sceneId)) {
      // M07 may still lack it: write its flag, send nothing.
      if (markFlag) await _flags.markSceneSeen(sceneId);
      return;
    }
    // M07 first: its step only rises, and its write never blocks the op.
    if (markFlag) await _flags.markSceneSeen(sceneId);
    final id = _held[sceneId] ??= _economy.newRequestId();
    final outcome = await _economy.recordScene(
      id,
      chapterId: chapter.chapterId,
      sceneId: sceneId,
    );
    switch (outcome) {
      case OpApplied() || OpRefused():
        _held.remove(sceneId);
      case OpWriteFailed():
        break;
    }
  }

  /// Every scene M07 saw that the projection lacks (FR-052), once.
  Future<void> backfill() async {
    final opening = _flags.current.openingDoneAtMs == null
        ? null
        : sessionScenesOf(_content).opening;
    for (final sceneId in {..._flags.current.scenesSeen, ?opening}) {
      if (_seen().contains(sceneId)) continue;
      await _record(sceneId, markFlag: false);
    }
  }

  Chapter? _chapterOf(String sceneId) {
    for (final chapter in _content.chapters) {
      if (chapter.scenes.any((s) => s.sceneId == sceneId)) return chapter;
    }
    return null;
  }
}

@Riverpod(keepAlive: true)
StoryService storyService(Ref ref) {
  final economy = ref.watch(economyProvider).requireValue;
  final content = ref.watch(contentSourceProvider);
  return StoryService(
    economy,
    content,
    ref.watch(firstSessionFlagsProvider.notifier),
    () => ref.read(playerProgressProvider),
    () => {
      for (final scenes in ref.read(economyViewProvider).scenesSeen.values)
        ...scenes,
    },
  );
}
