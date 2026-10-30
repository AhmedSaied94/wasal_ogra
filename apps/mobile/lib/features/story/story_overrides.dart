// M10's overrides of M08's slots (specs/015-m10-apartment-story,
// contracts/story-flow.md "Changes to merged code"): a waiting scene makes
// the savings card say so. M08's files stay as they are; the scene after a
// result joins here with its service (T088).
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/economy/domain/wire.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/progress/application/player_progress_provider.dart';
import 'package:wassal/core/progress/domain/story.dart';
import 'package:wassal/features/home/application/home_slots.dart';
import 'package:wassal/features/onboarding/domain/first_session.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';

/// The scenes seen, by chapter wire name: the projection's, plus M07's own
/// record of the opening and the scenes it played (research R3). An install
/// from before `StoryService.backfill` (T088) has the second and not the
/// first, so without it the sample's opening always reads as waiting.
Map<String, Set<String>> seenScenesOf(
  ContentSource content,
  EconomyView view,
  FirstSessionFlags flags,
) {
  final seen = <String, Set<String>>{
    for (final MapEntry(:key, :value) in view.scenesSeen.entries)
      key: {...value},
  };
  // The opening is what writes `openingDoneAtMs` (M07), so a store that
  // predates `scenesSeen` still tells it was seen.
  final opening = flags.openingDoneAtMs == null
      ? null
      : sessionScenesOf(content).opening;
  final byM07 = <String>{...flags.scenesSeen, ?opening};
  for (final sceneId in byM07) {
    final chapter = chapterOfScene(content, sceneId);
    if (chapter == null) continue;
    (seen[chapterWire[chapter.chapterId]!] ??= <String>{}).add(sceneId);
  }
  return seen;
}

/// The overrides M10 gives the app and its tests.
List<Override> storyOverrides() => [
  storySceneWaitingProvider.overrideWith((ref) {
    final content = ref.watch(contentSourceProvider);
    return waitingScenes(
      content,
      ref.watch(playerProgressProvider),
      seenScenesOf(
        content,
        ref.watch(economyViewProvider),
        ref.watch(firstSessionFlagsProvider).value ?? FirstSessionFlags.empty,
      ),
    ).isNotEmpty;
  }),
];
