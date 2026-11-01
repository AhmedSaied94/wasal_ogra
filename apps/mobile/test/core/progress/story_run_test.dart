// The story's whole run (specs/015-m10-apartment-story, SC-005, T135): a
// player from the first open to the end of chapter 4, scripted through the
// real economy. Every scene becomes waiting at its moment exactly once, goal
// scenes are due or offered where contracts/story-flow.md says, and the
// album holds every scene at the end.
//
// The player starts with a full purse: the trips' earnings are the economy's
// own tests, and this run is about the scenes. It plays the trips the goals
// and the story trips need, buys what the goals ask, and watches each scene
// the moment it waits.
//
// A third group runs the same script over a built pack file, for the first
// release's pack before it is promoted:
//
//   fvm flutter test test/core/progress/story_run_test.dart \
//     --dart-define=STORY_RUN_PACK=<path to a .json.gz>
import 'dart:convert';
import 'dart:io';

import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/content/pack_content_source.dart';
import 'package:wassal/core/economy/domain/wire.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/progress/application/player_progress_provider.dart';
import 'package:wassal/core/progress/domain/playable.dart' show tripPlayable;
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/core/progress/domain/story.dart';
import 'package:wassal/core/progress/domain/unlocks.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/features/story/application/story_due_watcher.dart';
import 'package:wassal/features/story/domain/album.dart';

import '../../helpers/economy.dart';
import '../../helpers/lines.dart';
import '../../helpers/synthetic_packs.dart';

/// The built pack the third group plays, from `--dart-define`.
const _packFile = String.fromEnvironment('STORY_RUN_PACK');

/// Enough for every goal the packs ask.
const _purse = 1000000;

/// The step before any operation: the first open.
const _open = 'open';

/// The goal scenes the watcher made due, with the step that did.
final class _Flags extends FirstSessionFlagsNotifier {
  _Flags(this._log, this._step);

  final List<(String, String)> _log;
  final String Function() _step;

  @override
  Future<void> addSceneDue(String sceneId) async =>
      _log.add((sceneId, _step()));
}

/// One scripted player and what the run saw.
final class _Run {
  _Run(this.e, this.content) {
    watcher = StoryDueWatcher(content, _Flags(due, () => step));
  }

  final TestEconomy e;
  final ContentSource content;
  late final StoryDueWatcher watcher;

  String step = _open;

  /// `(scene, step)` for each scene the watcher made due.
  final due = <(String, String)>[];

  /// The step each scene first stopped being locked, by scene id.
  final waitingAt = <String, String>{};

  /// The step each chapter first was complete.
  final completeAt = <ChapterId, String>{};

  PlayerProgress get progress => playerProgressOf(e.service.view, content);

  /// Applies an operation, lets the watcher see it, and notes what became
  /// waiting before the player watches it.
  Future<OpApplied> apply(
    String label,
    Future<OpOutcome> Function() operation,
  ) async {
    final before = e.service.view;
    final outcome = await operation();
    if (outcome is! OpApplied) fail('$label: $outcome');
    step = label;
    await watcher.onView(before, outcome.view);
    observe();
    return outcome;
  }

  /// The scenes' states and the chapters' completion now.
  void observe() {
    final view = e.service.view;
    final now = progress;
    for (final (chapter, scene) in scenesInStoryOrder(content)) {
      final state = sceneState(content, now, view.scenesSeen, chapter, scene);
      if (state != SceneState.locked) {
        waitingAt.putIfAbsent(scene.sceneId, () => step);
      } else if (waitingAt.containsKey(scene.sceneId)) {
        fail('${scene.sceneId} went back to locked at $step');
      }
    }
    for (final chapter in chaptersInOrder(content)) {
      if (chapterComplete(content, now, chapter.chapterId)) {
        completeAt.putIfAbsent(chapter.chapterId, () => step);
      }
    }
  }

  /// The player watches every waiting scene, in story order.
  Future<void> watch() async {
    for (final (chapter, scene) in waitingScenes(
      content,
      progress,
      e.service.view.scenesSeen,
    )) {
      final outcome = await e.service.recordScene(
        e.service.newRequestId(),
        chapterId: chapter.chapterId,
        sceneId: scene.sceneId,
      );
      expect(outcome, isA<OpApplied>(), reason: scene.sceneId);
    }
  }

  /// A trip played to its end at three stars and its most JENEHAT.
  Future<void> play(String tripId) async {
    e.passTime(const Duration(minutes: 30));
    final start = e.service.newRequestId();
    final started = await apply(
      'start:$tripId',
      () => e.service.startTrip(start, tripId: tripId),
    );
    final most = started.view.unfinished!.maxEarningsJenehat;
    await apply(
      'result:$tripId',
      () => e.service.recordResult(
        e.service.newRequestId(),
        start: start,
        result: tripResult(tripId: tripId, earnings: most),
      ),
    );
    await watch();
  }

  Future<void> buy(
    String label,
    SkuKind kind,
    String skuId, {
    String? variantId,
  }) async {
    await apply(
      label,
      () => e.service.buy(
        e.service.newRequestId(),
        kind: kind,
        skuId: skuId,
        variantId: variantId,
      ),
    );
    await watch();
  }

  /// Meets [chapter]'s goal, then plays the story trip it names.
  Future<void> meetGoal(Chapter chapter) async {
    final goal = chapter.goal;
    switch (goal.kind) {
      case GoalKind.completeLine:
        for (final trip in content.tripsOf(goal.lineId!)) {
          if (trip.kind != TripKind.regular) continue;
          if (progress.starsOf(trip.tripId) == 0) await play(trip.tripId);
        }
      case GoalKind.ownVehicle:
        await buy(
          'buy:vehicle:${vehicleWire[goal.vehicleId]}',
          SkuKind.vehicle,
          vehicleWire[goal.vehicleId]!,
        );
      case GoalKind.purchase:
        await buy(
          'buy:chapter:${chapterWire[chapter.chapterId]}',
          SkuKind.chapter,
          chapterWire[chapter.chapterId]!,
        );
      case GoalKind.completeRoom:
        for (final item in content.itemsOf(goal.roomId!)) {
          await buy(
            'buy:item:${item.itemId}',
            SkuKind.item,
            item.itemId,
            variantId: item.variants.first.variantId,
          );
        }
    }
    expect(
      chapterComplete(content, progress, chapter.chapterId),
      isTrue,
      reason: '${chapter.chapterId.name}\'s goal was met',
    );
    if (chapter.storyTripId case final trip?) {
      if (tripPlayable(content, progress, trip)) await play(trip);
    }
  }
}

/// A new player plays [content] from the first open to the last chapter's
/// end.
Future<_Run> _script(ContentSource content) async {
  final e = await testEconomy(
    content: content,
    firstState: playerState(jenehat: _purse),
  );
  final run = _Run(e, content)..observe();
  await run.watch();
  for (final chapter in chaptersInOrder(content)) {
    await run.meetGoal(chapter);
  }
  return run;
}

/// What SC-005 asks of a finished [run].
void _expectStoryRun(_Run run) {
  final content = run.content;
  final view = run.e.service.view;
  final progress = run.progress;
  final scenes = scenesInStoryOrder(content);
  expect(scenes, isNotEmpty);

  for (final (chapter, scene) in scenes) {
    final id = scene.sceneId;
    // Waiting at its moment, once.
    final moment = switch (momentOf(scene)) {
      Opening() => _open,
      AfterTrip(:final tripId) => 'result:$tripId',
      GoalMet() => run.completeAt[chapter.chapterId],
    };
    expect(run.waitingAt[id], moment, reason: '$id waited at its moment');

    // Due by the watcher for a goal that isn't a room, else offered by the
    // room's own RoomDone (which `StoryDueWatcher` leaves alone).
    final dueAt = [
      for (final (sceneId, step) in run.due)
        if (sceneId == id) step,
    ];
    final watched =
        momentOf(scene) is GoalMet &&
        chapter.goal.kind != GoalKind.completeRoom;
    expect(
      dueAt,
      watched ? [moment] : isEmpty,
      reason: '$id is due ${watched ? 'once, at its moment' : 'never'}',
    );

    // Seen once: the economy holds it, and a second record stores nothing.
    expect(
      view.scenesSeen[chapterWire[chapter.chapterId]],
      contains(id),
      reason: '$id was recorded',
    );
  }

  // Each scene stored one op.
  final stored = [for (final (_, scene) in scenes) scene.sceneId];
  expect(
    stored.toSet(),
    hasLength(stored.length),
    reason: 'scene ids are unique',
  );

  // The story is at its end, and the album holds every scene.
  final last = chaptersInOrder(content).last;
  expect(chapterComplete(content, progress, last.chapterId), isTrue);
  expect(waitingScenes(content, progress, view.scenesSeen), isEmpty);
  final (cards, unlocked, total) = album(content, progress);
  expect(total, scenes.length);
  expect(unlocked, total);
  expect(cards.whereType<LockedCard>(), isEmpty);
}

void main() {
  test('the first release\'s story shape, from the first open to chapter 4\'s '
      'end', () async {
    final content = PackContentSource(Pack.fromJson(storyShaped()));
    _expectStoryRun(await _script(content));
  });

  test('the sample pack, from the first open to chapter 4\'s end', () async {
    _expectStoryRun(await _script(sampleContent()));
  });

  test(
    'the built pack file, from the first open to the last chapter\'s end',
    () async {
      final bytes = gzip.decode(File(_packFile).readAsBytesSync());
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      _expectStoryRun(await _script(PackContentSource(Pack.fromJson(json))));
    },
    skip: _packFile.isEmpty
        ? 'no pack file: pass --dart-define=STORY_RUN_PACK=<path to a '
              '.json.gz> (tasks.md T135)'
        : null,
  );
}
