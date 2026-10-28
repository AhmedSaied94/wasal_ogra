// What the player saves for (specs/013-m08-home-result, research R4): the
// chapter's goal before the apartment opens, then the next piece; nothing
// for a pack without chapters; and when it is affordable.
import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/home/domain/savings_target.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/progress.dart';

void main() {
  final c = sampleContent();

  group('ChapterGoalTarget, by goal kind', () {
    test('complete_line: a Count of the regular trips finished', () {
      final target = savingsTarget(c, player({'line_hay.01': 2}), 50);
      expect(target, isA<ChapterGoalTarget>());
      target as ChapterGoalTarget;
      expect(target.chapter.chapterId, ChapterId.ch1FirstJob);
      expect(target.goalKind, GoalKind.completeLine);
      expect(target.subjectName, 'خط الحي');
      // The story trip line_hay.03 isn't one of them.
      expect(target.progress, const Count(done: 1, of: 2));
      expect(target.opensInChapter, 4);
      expect(target.affordable, isFalse);
    });

    test('own_vehicle: an Amount of JENEHAT over its price', () {
      final target = savingsTarget(c, player(hayDone), 1240);
      target as ChapterGoalTarget;
      expect(target.chapter.chapterId, ChapterId.ch2HerFather);
      expect(target.goalKind, GoalKind.ownVehicle);
      // The content's full name, ellipsized on screen (R4).
      expect(target.subjectName, 'الميكروباص القديم');
      expect(target.progress, const Amount(have: 1240, of: 1500));
      expect(target.affordable, isFalse);
    });

    test('purchase: the chapter at its catalog price', () {
      final target = savingsTarget(c, player(hayDone, {microOld}), 900);
      target as ChapterGoalTarget;
      expect(target.chapter.chapterId, ChapterId.ch3Shabka);
      expect(target.goalKind, GoalKind.purchase);
      expect(target.subjectName, 'الشبكة');
      expect(target.progress, const Amount(have: 900, of: 900));
      expect(target.affordable, isTrue);
    });

    test('complete_room: the apartment opens with the first room goal, so '
        'it is always the next piece', () {
      // The room goal moved to chapter 2: the apartment opens there.
      final early = sampleWith((json) {
        entry(json, 'chapters', 'chapter_id', 'ch2_her_father')['goal'] = {
          'kind': 'complete_room',
          'room_id': 'salon',
        };
        entry(json, 'chapters', 'chapter_id', 'ch4_salon')['goal'] = {
          'kind': 'own_vehicle',
          'vehicle_id': 'micro_old',
        };
      });
      final target = savingsTarget(early, player(hayDone), 100);
      target as ApartmentPieceTarget;
      expect(target.chapter.chapterId, ChapterId.ch2HerFather);
      expect(target.progress, const Amount(have: 100, of: 400));
      // Before it, the goal names the chapter it opens in.
      final before = savingsTarget(early, player(), 0) as ChapterGoalTarget;
      expect(before.opensInChapter, 2);
    });

    test('no room goal: the apartment never opens', () {
      final never = sampleWith((json) {
        entry(json, 'chapters', 'chapter_id', 'ch4_salon')['goal'] = {
          'kind': 'own_vehicle',
          'vehicle_id': 'micro_old',
        };
      });
      final target = savingsTarget(never, player(), 0) as ChapterGoalTarget;
      expect(target.opensInChapter, isNull);
    });
  });

  group('ApartmentPieceTarget from the apartment on', () {
    final ch4 = player(hayDone, {microOld, shabka});

    test('the first unowned item by order, at its price', () {
      final target = savingsTarget(c, ch4, 320);
      target as ApartmentPieceTarget;
      expect(target.chapter.chapterId, ChapterId.ch4Salon);
      expect(target.itemId, 'salon.nish');
      expect(target.itemName, 'النيش');
      expect(target.priceJenehat, 400);
      expect(target.progress, const Amount(have: 320, of: 400));
      expect(target.affordable, isFalse);
    });

    test('an owned piece is skipped', () {
      final target = savingsTarget(
        c,
        player(hayDone, {microOld, shabka, salonNish}),
        150,
      );
      target as ApartmentPieceTarget;
      expect(target.itemId, 'salon.sitara');
      expect(target.affordable, isTrue);
    });

    test('every piece owned: nothing left to save for', () {
      expect(
        savingsTarget(c, player(hayDone, {microOld, shabka, ...salon}), 0),
        const NoTarget(),
      );
    });
  });

  test('NoTarget for a pack without chapters', () {
    final none = sampleWith((json) => json['chapters'] = <Object?>[]);
    expect(savingsTarget(none, player(), 1000), const NoTarget());
    expect(const NoTarget().affordable, isFalse);
  });

  group('affordable', () {
    test('an Amount with have ≥ of', () {
      for (final (have, want) in [(1499, false), (1500, true), (1600, true)]) {
        expect(
          savingsTarget(c, player(hayDone), have).affordable,
          want,
          reason: '$have of 1500',
        );
      }
    });

    test('a line goal never, even when its trips are all done', () {
      final target = ChapterGoalTarget(
        chapter: c.chapter(ChapterId.ch1FirstJob)!,
        goalKind: GoalKind.completeLine,
        subjectName: 'خط الحي',
        progress: const Count(done: 2, of: 2),
      );
      expect(target.affordable, isFalse);
    });

    test('the bar is capped at full', () {
      expect(const Amount(have: 3000, of: 1500).fraction, 1);
      expect(const Amount(have: 600, of: 1500).fraction, closeTo(0.4, 1e-9));
      expect(const Count(done: 1, of: 2).fraction, 0.5);
    });
  });
}
