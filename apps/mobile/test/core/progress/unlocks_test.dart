// The phone's unlock and completion rules (specs/013-m08-home-result,
// contracts/progress-rules.md, research R2): every case of
// backend/apps/progress/tests/test_unlocks.py, one Dart test each, named
// after the Python test. When the Python file changes, this port changes in
// the same PR, and so does lib/core/progress/domain/unlocks.dart.
//
// The Python tests change the rules document; these change the sample
// pack's JSON the same way (`sampleWith`). Where Python feeds a kind the
// schema doesn't know, the Dart models refuse to build the pack at all,
// which is the phone's way of never meeting it.
import 'dart:convert';
import 'dart:io';

import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/core/progress/domain/unlocks.dart';

import '../../helpers/economy.dart';
import '../../helpers/progress.dart';

const _sampleLayout = '../../content/examples/sample';

/// Every JSON file of the layout's [folder], decoded.
List<Map<String, Object?>> _layoutFiles(String folder) => [
  for (final file
      in Directory('$_sampleLayout/$folder')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.json')))
    (jsonDecode(file.readAsStringSync()) as Map<String, dynamic>)
        .cast<String, Object?>(),
];

/// The completions `newly_completed` lists with nothing granted: rooms, then
/// chapters, each in order, that are complete. The grant records are the
/// server's bookkeeping; the phone has the rules they come from.
List<(String, String, int)> _completions(ContentSource c, PlayerProgress p) => [
  for (final room in c.rooms)
    if (roomComplete(c, p, room.roomId))
      ('room', room.roomId.name, room.completionBonat),
  for (final chapter in chaptersInOrder(c))
    if (chapterComplete(c, p, chapter.chapterId))
      ('chapter', chapter.chapterId.name, chapter.completionBonat),
];

void main() {
  late ContentSource c;

  setUp(() => c = sampleContent());

  test('test_the_published_rules_are_the_assembled_ones', () {
    // The bundled sample is what a publish of content/examples/sample
    // writes: what the rules read of it matches the layout's files.
    final lines = _layoutFiles('lines').map(Line.fromJson).toList();
    expect(lines, hasLength(c.lines.length));
    for (final file in lines) {
      final line = c.line(file.lineId)!;
      expect((file.order, file.unlock), (line.order, line.unlock));
    }
    final trips = _layoutFiles('trips').map(TripDefinition.fromJson).toList();
    expect(trips, hasLength(c.lines.expand((l) => c.tripsOf(l.lineId)).length));
    for (final file in trips) {
      final trip = c.trip(file.tripId)!;
      expect(
        (file.kind, file.lineId, file.vehicleId),
        (trip.kind, trip.lineId, trip.vehicleId),
      );
    }
    final chapters = _layoutFiles('chapters').map(Chapter.fromJson).toList();
    expect(chapters, hasLength(4));
    for (final file in chapters) {
      final chapter = c.chapter(file.chapterId)!;
      expect(
        (file.order, file.goal, file.storyTripId),
        (chapter.order, chapter.goal, chapter.storyTripId),
      );
    }
    for (final file in _layoutFiles('vehicles').map(Vehicle.fromJson)) {
      expect(c.vehicle(file.vehicleId)?.starter, file.starter);
    }
    expect(c.rooms.single.roomId, RoomId.salon);
    expect(
      [for (final item in c.itemsOf(RoomId.salon)) item.itemId],
      ['salon.nish', 'salon.sitara'],
    );
  });

  // -- vehicles and lines ----------------------------------------------------

  test('test_a_vehicle_is_owned_by_its_starter_flag_or_by_ownership', () {
    expect(vehicleOwned(c, player(), VehicleId.tuktuk), isTrue);
    expect(vehicleOwned(c, player(), VehicleId.microOld), isFalse);
    expect(vehicleOwned(c, player({}, {microOld}), VehicleId.microOld), isTrue);
    // The sample has no micro_safar: an unknown vehicle.
    expect(vehicleOwned(c, player(), VehicleId.microSafar), isFalse);
  });

  test('test_a_line_unlocks_at_start_or_with_its_vehicle', () {
    expect(lineUnlocked(c, player(), LineId.lineHay), isTrue);
    expect(lineUnlocked(c, player(), LineId.lineGamaa), isFalse);
    expect(lineUnlocked(c, player({}, {microOld}), LineId.lineGamaa), isTrue);
    expect(lineUnlocked(c, player(), LineId.lineSouq), isFalse);
  });

  test('test_a_line_can_unlock_when_another_line_is_complete', () {
    final changed = sampleWith((json) {
      entry(json, 'lines', 'line_id', 'line_gamaa')['unlock'] = {
        'kind': 'line_complete',
        'line_id': 'line_hay',
      };
    });
    expect(
      lineUnlocked(changed, player({'line_hay.01': 1}), LineId.lineGamaa),
      isFalse,
    );
    expect(lineUnlocked(changed, player(hayDone), LineId.lineGamaa), isTrue);
    // An unknown kind: the models refuse the pack.
    expect(
      () => sampleWith((json) {
        entry(json, 'lines', 'line_id', 'line_gamaa')['unlock'] = {
          'kind': 'unknown',
        };
      }),
      throwsA(anything),
    );
  });

  test('test_a_line_is_complete_when_every_regular_trip_has_a_star', () {
    expect(lineComplete(c, player(), LineId.lineHay), isFalse);
    expect(
      lineComplete(c, player({'line_hay.01': 3}), LineId.lineHay),
      isFalse,
    );
    // The story trip line_hay.03 doesn't count.
    expect(lineComplete(c, player(hayDone), LineId.lineHay), isTrue);
    expect(
      lineComplete(
        c,
        player({'line_hay.01': 1, 'line_hay.02': 0}),
        LineId.lineHay,
      ),
      isFalse,
    );
    expect(lineComplete(c, player(hayDone), LineId.lineSouq), isFalse);
  });

  test('test_a_line_without_regular_trips_is_never_complete', () {
    final changed = sampleWith((json) {
      for (final trip in entries(json, 'trips')) {
        if (trip['line_id'] == 'line_hay') trip['kind'] = 'story';
      }
    });
    expect(lineComplete(changed, player(hayDone), LineId.lineHay), isFalse);
  });

  // -- trips -----------------------------------------------------------------

  test('test_the_first_trip_of_a_line_is_free', () {
    expect(tripUnlocked(c, player(), 'line_hay.01'), isTrue);
  });

  test('test_a_later_trip_needs_the_previous_regular_one_at_a_star', () {
    expect(tripUnlocked(c, player(), 'line_hay.02'), isFalse);
    expect(tripUnlocked(c, player({'line_hay.01': 0}), 'line_hay.02'), isFalse);
    expect(tripUnlocked(c, player({'line_hay.01': 1}), 'line_hay.02'), isTrue);
  });

  test('test_a_trip_needs_its_line_and_its_vehicle', () {
    expect(tripUnlocked(c, player(), 'line_gamaa.01'), isFalse);
    final owner = player({}, {microOld});
    expect(tripUnlocked(c, owner, 'line_gamaa.01'), isTrue);
    expect(tripUnlocked(c, owner, 'line_gamaa.02'), isFalse);
    expect(
      tripUnlocked(
        c,
        player({'line_gamaa.01': 2}, {microOld}),
        'line_gamaa.02',
      ),
      isTrue,
    );
    // Its own vehicle: a line unlocked another way doesn't lend it.
    final changed = sampleWith((json) {
      entry(json, 'lines', 'line_id', 'line_gamaa')['unlock'] = {
        'kind': 'start',
      };
    });
    expect(tripUnlocked(changed, player(), 'line_gamaa.01'), isFalse);
  });

  test('test_a_story_trip_needs_only_its_chapter', () {
    // ch1 is the first chapter, so line_hay.03 is open before line_hay.02
    // is played.
    expect(tripUnlocked(c, player(), 'line_hay.03'), isTrue);
    final changed = sampleWith((json) {
      entry(json, 'chapters', 'chapter_id', 'ch2_her_father')['story_trip_id'] =
          'line_hay.03';
      entry(
        json,
        'chapters',
        'chapter_id',
        'ch1_first_job',
      ).remove('story_trip_id');
    });
    expect(tripUnlocked(changed, player(), 'line_hay.03'), isFalse);
    expect(tripUnlocked(changed, player(hayDone), 'line_hay.03'), isTrue);
  });

  test('test_a_story_trip_no_chapter_names_follows_the_line', () {
    final changed = sampleWith((json) {
      entry(
        json,
        'chapters',
        'chapter_id',
        'ch1_first_job',
      ).remove('story_trip_id');
    });
    expect(tripUnlocked(changed, player(), 'line_hay.03'), isFalse);
    expect(
      tripUnlocked(changed, player({'line_hay.02': 1}), 'line_hay.03'),
      isTrue,
    );
  });

  test('test_an_unknown_trip_is_locked', () {
    expect(tripUnlocked(c, player(hayDone), 'line_hay.99'), isFalse);
  });

  // -- chapters, rooms, items ------------------------------------------------

  test('test_the_first_chapter_is_always_unlocked', () {
    expect(chapterUnlocked(c, player(), ChapterId.ch1FirstJob), isTrue);
    expect(chapterUnlocked(c, player(), ChapterId.ch2HerFather), isFalse);
    // The sample has no ch7: an unknown chapter.
    expect(chapterUnlocked(c, player(), ChapterId.ch7Wedding), isFalse);
  });

  test('test_chapters_complete_in_order_for_each_goal_kind', () {
    // complete_line
    expect(chapterComplete(c, player(), ChapterId.ch1FirstJob), isFalse);
    expect(chapterComplete(c, player(hayDone), ChapterId.ch1FirstJob), isTrue);
    expect(chapterUnlocked(c, player(hayDone), ChapterId.ch2HerFather), isTrue);
    // own_vehicle: met, but ch1 isn't complete, so ch2 isn't either.
    expect(
      chapterComplete(c, player({}, {microOld}), ChapterId.ch2HerFather),
      isFalse,
    );
    expect(
      chapterComplete(c, player(hayDone, {microOld}), ChapterId.ch2HerFather),
      isTrue,
    );
    // purchase
    expect(
      chapterComplete(c, player(hayDone, {microOld}), ChapterId.ch3Shabka),
      isFalse,
    );
    expect(
      chapterComplete(
        c,
        player(hayDone, {microOld, shabka}),
        ChapterId.ch3Shabka,
      ),
      isTrue,
    );
    expect(
      chapterUnlocked(
        c,
        player(hayDone, {microOld, shabka}),
        ChapterId.ch4Salon,
      ),
      isTrue,
    );
    // complete_room
    final allOwned = {microOld, shabka, ...salon};
    expect(
      chapterComplete(
        c,
        player(hayDone, {microOld, shabka, salonNish}),
        ChapterId.ch4Salon,
      ),
      isFalse,
    );
    expect(
      chapterComplete(c, player(hayDone, allOwned), ChapterId.ch4Salon),
      isTrue,
    );
    expect(
      chapterComplete(c, player(hayDone, allOwned), ChapterId.ch7Wedding),
      isFalse,
    );
  });

  test('test_an_unknown_goal_kind_is_never_met', () {
    // The models refuse a goal kind the schema doesn't know, so no pack
    // the phone plays can hold one.
    expect(
      () => sampleWith((json) {
        entry(json, 'chapters', 'chapter_id', 'ch1_first_job')['goal'] = {
          'kind': 'unknown',
        };
      }),
      throwsA(anything),
    );
  });

  test('test_a_room_is_complete_when_every_item_is_owned', () {
    expect(roomComplete(c, player(), RoomId.salon), isFalse);
    expect(roomComplete(c, player({}, {salonNish}), RoomId.salon), isFalse);
    expect(roomComplete(c, player({}, salon), RoomId.salon), isTrue);
    expect(roomComplete(c, player({}, salon), RoomId.kitchen), isFalse);
    // A room without items: the pack's items name another room.
    final changed = sampleWith((json) {
      json['items'] = [
        for (final item in entries(json, 'items'))
          if (item['room_id'] != 'salon') item,
      ];
    });
    expect(roomComplete(changed, player({}, salon), RoomId.salon), isFalse);
  });

  test('test_an_item_is_purchasable_when_its_rooms_chapter_is_unlocked', () {
    expect(itemPurchasable(c, player(), 'salon.nish'), isFalse);
    final ready = player(hayDone, {microOld, shabka});
    expect(itemPurchasable(c, ready, 'salon.nish'), isTrue);
    expect(itemPurchasable(c, ready, 'kitchen.oven'), isFalse);
    final changed = sampleWith((json) {
      entry(json, 'items', 'item_id', 'salon.nish')['room_id'] = 'kitchen';
    });
    expect(itemPurchasable(changed, ready, 'salon.nish'), isFalse);
  });

  test(
    'test_newly_completed_lists_rooms_before_chapters_and_skips_granted',
    () {
      final everything = player(hayDone, {microOld, shabka, ...salon});
      expect(_completions(c, everything), [
        ('room', 'salon', 20),
        ('chapter', 'ch1FirstJob', 5),
        ('chapter', 'ch2HerFather', 10),
        ('chapter', 'ch3Shabka', 10),
        ('chapter', 'ch4Salon', 15),
      ]);
      expect(_completions(c, player()), isEmpty);
    },
  );

  test('test_the_current_chapter_is_the_open_one_else_the_last_done', () {
    expect(currentChapter(c, player())?.chapterId, ChapterId.ch1FirstJob);
    expect(
      currentChapter(c, player(hayDone))?.chapterId,
      ChapterId.ch2HerFather,
    );
    expect(
      currentChapter(c, player(hayDone, {microOld}))?.chapterId,
      ChapterId.ch3Shabka,
    );
    final done = player(hayDone, {microOld, shabka, ...salon});
    expect(currentChapter(c, done)?.chapterId, ChapterId.ch4Salon);
    final noChapters = sampleWith((json) => json['chapters'] = <Object?>[]);
    expect(currentChapter(noChapters, done), isNull);
  });

  group('apartmentOpens (phone only)', () {
    test('is the first chapter by order whose goal is a room', () {
      expect(apartmentOpens(c)?.chapterId, ChapterId.ch4Salon);
    });

    test('is null for a pack with no room goal', () {
      final changed = sampleWith((json) {
        json['chapters'] = [
          for (final chapter in entries(json, 'chapters'))
            if (chapter['chapter_id'] != 'ch4_salon') chapter,
        ];
      });
      expect(apartmentOpens(changed), isNull);
    });
  });
}
