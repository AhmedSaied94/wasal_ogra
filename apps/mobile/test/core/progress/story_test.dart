// The story rules (specs/015-m10-apartment-story, contracts/story-flow.md
// "The rules"): each moment, its unlock, the state, the order, the waiting
// scenes, and the two lookups.
import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/core/progress/domain/story.dart';

import '../../helpers/economy.dart';

/// The sample pack: chapter 1 opens with `opening` and plays `the_stand`
/// after `line_hay.03`; chapter 2's `father_visit` and chapter 4's
/// `family_visit` are goal scenes.
ContentSource _content() => sampleContent();

Chapter _chapter(ContentSource c, ChapterId id) => c.chapter(id)!;

Scene _scene(Chapter chapter, String sceneId) =>
    chapter.scenes.firstWhere((s) => s.sceneId == sceneId);

/// A player who finished `line_hay.03`, and one who hasn't.
const _finished = PlayerProgress(bestStars: {'line_hay.03': 1});

void main() {
  final c = _content();

  group('momentOf', () {
    test('an opening scene', () {
      expect(
        momentOf(_scene(_chapter(c, ChapterId.ch1FirstJob), 'opening')),
        isA<Opening>(),
      );
    });

    test('an after_trip scene names its trip', () {
      final moment = momentOf(
        _scene(_chapter(c, ChapterId.ch1FirstJob), 'the_stand'),
      );
      expect(moment, isA<AfterTrip>());
      expect((moment as AfterTrip).tripId, 'line_hay.03');
    });

    test('a scene without plays is the goal moment', () {
      expect(
        momentOf(_scene(_chapter(c, ChapterId.ch2HerFather), 'father_visit')),
        isA<GoalMet>(),
      );
    });
  });

  group('sceneUnlocked', () {
    test('the opening is always unlocked', () {
      final chapter = _chapter(c, ChapterId.ch1FirstJob);
      expect(
        sceneUnlocked(
          c,
          PlayerProgress.empty,
          chapter,
          _scene(chapter, 'opening'),
        ),
        isTrue,
      );
    });

    test('an after_trip scene waits for its trip\'s first finish', () {
      final chapter = _chapter(c, ChapterId.ch1FirstJob);
      final scene = _scene(chapter, 'the_stand');
      expect(sceneUnlocked(c, PlayerProgress.empty, chapter, scene), isFalse);
      expect(sceneUnlocked(c, _finished, chapter, scene), isTrue);
    });

    test('a goal scene waits for its chapter', () {
      final chapter = _chapter(c, ChapterId.ch2HerFather);
      final scene = _scene(chapter, 'father_visit');
      expect(sceneUnlocked(c, PlayerProgress.empty, chapter, scene), isFalse);
      // The chapter's goal is the microbus; chapter 1's line is complete.
      expect(
        sceneUnlocked(
          c,
          PlayerProgress(
            bestStars: {
              for (final trip in c.tripsOf(LineId.lineHay)) trip.tripId: 1,
            },
            owned: const {(SkuKind.vehicle, 'micro_old')},
          ),
          chapter,
          scene,
        ),
        isTrue,
      );
    });
  });

  group('sceneState', () {
    final chapter = _chapter(c, ChapterId.ch1FirstJob);
    final opening = _scene(chapter, 'opening');

    test('locked, waiting and seen', () {
      expect(
        sceneState(
          c,
          PlayerProgress.empty,
          const {},
          chapter,
          _scene(chapter, 'the_stand'),
        ),
        SceneState.locked,
      );
      expect(
        sceneState(c, PlayerProgress.empty, const {}, chapter, opening),
        SceneState.waiting,
      );
      expect(
        sceneState(
          c,
          PlayerProgress.empty,
          const {
            'ch1_first_job': {'opening'},
          },
          chapter,
          opening,
        ),
        SceneState.seen,
      );
    });

    test('seen is the economy\'s, keyed by the chapter\'s wire name', () {
      final state = sceneState(
        c,
        PlayerProgress.empty,
        const {
          'ch1_first_job': {'opening'},
        },
        chapter,
        opening,
      );
      expect(state, SceneState.seen);
      // Another chapter's entry says nothing about this one.
      expect(
        sceneState(
          c,
          PlayerProgress.empty,
          const {
            'ch4_salon': {'opening'},
          },
          chapter,
          opening,
        ),
        SceneState.waiting,
      );
    });
  });

  test('scenesInStoryOrder: chapters by order, then the list order', () {
    final order = [
      for (final (chapter, scene) in scenesInStoryOrder(c))
        '${chapter.chapterId.name}/${scene.sceneId}',
    ];
    expect(order, [
      'ch1FirstJob/opening',
      'ch1FirstJob/the_stand',
      'ch2HerFather/father_visit',
      'ch4Salon/family_visit',
    ]);
  });

  test('waitingScenes: only what is unlocked and unseen, in story order', () {
    expect(
      [
        for (final (_, scene) in waitingScenes(
          c,
          PlayerProgress.empty,
          const {},
        ))
          scene.sceneId,
      ],
      ['opening'],
    );
    expect(
      [
        for (final (_, scene) in waitingScenes(c, _finished, const {
          'ch1_first_job': {'opening'},
        }))
          scene.sceneId,
      ],
      ['the_stand'],
    );
  });

  test('goalSceneOf is the one scene without plays', () {
    expect(goalSceneOf(_chapter(c, ChapterId.ch1FirstJob)), isNull);
    expect(
      goalSceneOf(_chapter(c, ChapterId.ch2HerFather))?.sceneId,
      'father_visit',
    );
    expect(
      goalSceneOf(_chapter(c, ChapterId.ch4Salon))?.sceneId,
      'family_visit',
    );
  });

  test('afterTripSceneOf finds the scene a trip plays', () {
    expect(afterTripSceneOf(c, 'line_hay.03')?.sceneId, 'the_stand');
    expect(afterTripSceneOf(c, 'line_hay.01'), isNull);
  });
}
