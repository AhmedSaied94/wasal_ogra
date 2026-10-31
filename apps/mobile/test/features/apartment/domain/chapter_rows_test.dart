// The timeline's rows (specs/015-m10-apartment-story, data-model "Apartment",
// contracts/scene-viewer.md "The timeline", T099): seven rows by the
// glossary's order, the done row's thumbnail, the current row's goal for each
// kind, and the end of the story.
import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/core/progress/domain/story.dart';
import 'package:wassal/features/apartment/domain/chapter_rows.dart';
import 'package:wassal/features/story/domain/panel_ref.dart';

import '../../../helpers/progress.dart';

/// The sample with chapters 1 to 3 met: the salon is the current chapter.
final _atSalon = player(hayDone, {microOld, shabka});

void main() {
  group('the seven rows', () {
    test('follow the glossary\'s order and number from one', () {
      final rows = chapterRows(sampleWith((_) {}), player(), jenehat: 0);
      expect(
        [for (final row in rows) row.chapterId],
        [
          ChapterId.ch1FirstJob,
          ChapterId.ch2HerFather,
          ChapterId.ch3Shabka,
          ChapterId.ch4Salon,
          ChapterId.ch5Kitchen,
          ChapterId.ch6Bedroom,
          ChapterId.ch7Wedding,
        ],
      );
      expect([for (final row in rows) row.number], [1, 2, 3, 4, 5, 6, 7]);
    });

    test('carry the pack\'s titles; a chapter the pack lacks has none, '
        'for the ARB name', () {
      final rows = chapterRows(sampleWith((_) {}), player(), jenehat: 0);
      expect(
        [for (final row in rows) row.name],
        [
          'أول شغلانة',
          'الكلام مع أبوها',
          'الشبكة',
          'الصالون',
          null,
          null,
          null,
        ],
      );
      expect(rows.skip(4), everyElement(isA<LockedRow>()));
    });

    test('a pack with no chapters is seven locked rows', () {
      final content = sampleWith((json) => json['chapters'] = <Object?>[]);
      final rows = chapterRows(content, player(), jenehat: 0);
      expect(rows, hasLength(7));
      expect(rows, everyElement(isA<LockedRow>()));
    });
  });

  group('at the salon', () {
    final content = artboardSalonContent();
    final progress = player(hayDone, {
      microOld,
      shabka,
      salonNish,
      salonSitara,
    });
    final rows = chapterRows(content, progress, jenehat: 0);

    test('chapters 1 to 3 are done, 4 is current, 5 to 7 are locked', () {
      expect(
        [for (final row in rows) row.runtimeType],
        [
          DoneRow,
          DoneRow,
          DoneRow,
          CurrentRow,
          LockedRow,
          LockedRow,
          LockedRow,
        ],
      );
      // The pack has chapters 5 to 7: their own titles.
      expect(
        [for (final row in rows.skip(4)) row.name],
        ['المطبخ', 'أوضة النوم', 'الفرح'],
      );
    });

    test('the current row counts the pieces and names the goal scene', () {
      final current = rows[3] as CurrentRow;
      final pieces = content.itemsOf(RoomId.salon);
      expect(
        current.goal,
        RoomGoal(
          owned: 2,
          total: pieces.length,
          itemNames: [for (final item in pieces) item.name.arEg],
          sceneTitle: goalSceneOf(content.chapter(ChapterId.ch4Salon)!)!
              .title
              .arEg,
        ),
      );
      expect(pieces, hasLength(4));
    });

    test('the pieces are named in the pack\'s order', () {
      final names = ((rows[3] as CurrentRow).goal! as RoomGoal).itemNames;
      final byOrder = [...content.itemsOf(RoomId.salon)]
        ..sort((a, b) => a.order.compareTo(b.order));
      expect(names, [for (final item in byOrder) item.name.arEg]);
    });

    test('a done row without scenes has no button', () {
      // The sample's chapter 3 has no scene.
      final shabkaRow = rows[2] as DoneRow;
      expect(shabkaRow.hasScenes, isFalse);
      expect(shabkaRow.thumb, isNull);
    });

    test('a done row\'s thumbnail is the first panel of its last unlocked '
        'scene', () {
      // Chapter 1: the opening, and `the_stand` once line_hay.03 is finished.
      final before = rows[0] as DoneRow;
      expect(before.hasScenes, isTrue);
      expect(before.thumb?.art, 'opening_key');

      final after =
          chapterRows(
                content,
                player(
                  {...hayDone, 'line_hay.03': 1},
                  {microOld, shabka, salonNish, salonSitara},
                ),
                jenehat: 0,
              ).first
              as DoneRow;
      expect(
        after.thumb,
        const PanelRef(art: 'stand_morning', speakers: ['usta']),
      );
    });

    test('chapter 2\'s goal scene is its thumbnail', () {
      final father = rows[1] as DoneRow;
      expect(father.hasScenes, isTrue);
      expect(father.thumb?.art, 'opening_key');
    });
  });

  group('the current row\'s goal', () {
    final content = sampleWith((_) {});

    CurrentGoal? goalOf(int jenehat, [PlayerProgress? p]) {
      final rows = chapterRows(content, p ?? player(), jenehat: jenehat);
      return rows.whereType<CurrentRow>().single.goal;
    }

    test('a line: the trips finished of its regular trips', () {
      expect(goalOf(0), const CountGoal(title: 'خط الحي', done: 0, of: 2));
      expect(
        goalOf(0, player({'line_hay.01': 1})),
        const CountGoal(title: 'خط الحي', done: 1, of: 2),
      );
    });

    test('a vehicle: the JENEHAT saved of its price', () {
      expect(
        goalOf(700, player(hayDone)),
        const AmountGoal(title: 'الميكروباص القديم', have: 700, of: 1500),
      );
    });

    test('a purchase: the chapter\'s own title and price', () {
      expect(
        goalOf(250, player(hayDone, {microOld})),
        const AmountGoal(title: 'الشبكة', have: 250, of: 900),
      );
    });

    test('a room: the pieces and the scene', () {
      final goal = goalOf(0, _atSalon);
      expect(goal, isA<RoomGoal>());
      final room = goal! as RoomGoal;
      expect(room.owned, 0);
      expect(room.total, 2);
      expect(room.itemNames, ['النيش', 'الستارة']);
      expect(room.sceneTitle, 'العيلة في الصالون');
    });

    test('a room without a goal scene has none to name', () {
      final bare = sampleWith((json) {
        for (final chapter in entries(json, 'chapters')) {
          if (chapter['chapter_id'] == 'ch4_salon') {
            chapter['scenes'] = <Object?>[];
          }
        }
      });
      final rows = chapterRows(bare, _atSalon, jenehat: 0);
      final goal = rows.whereType<CurrentRow>().single.goal! as RoomGoal;
      expect(goal.sceneTitle, isNull);
    });
  });

  group('the end of the story', () {
    test('every chapter of the pack done: no current row', () {
      final content = sampleWith((_) {});
      final done = player(hayDone, {microOld, shabka, salonNish, salonSitara});
      final rows = chapterRows(content, done, jenehat: 0);
      expect(rows.whereType<CurrentRow>(), isEmpty);
      expect(
        [for (final row in rows) row.runtimeType],
        [DoneRow, DoneRow, DoneRow, DoneRow, LockedRow, LockedRow, LockedRow],
      );
    });

    test('all seven done', () {
      final content = artboardSalonContent();
      final done = player(hayDone, {
        microOld,
        shabka,
        for (final item in content.itemsOf(RoomId.salon))
          (SkuKind.item, item.itemId),
        (SkuKind.chapter, 'ch5_kitchen'),
        (SkuKind.chapter, 'ch6_bedroom'),
        (SkuKind.chapter, 'ch7_wedding'),
      });
      final rows = chapterRows(content, done, jenehat: 0);
      expect(rows, everyElement(isA<DoneRow>()));
    });
  });
}
