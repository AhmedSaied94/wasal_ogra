import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/content/pack_content_source.dart';

import '../../helpers/content.dart';

PackContentSource _source([Map<String, Object?>? json]) =>
    PackContentSource(Pack.fromJson(json ?? samplePackJson()));

void main() {
  late PackContentSource source;

  setUp(() => source = _source());

  test('version is the pack version', () {
    expect(source.version, 1);
  });

  test('lines are in order, and looked up by id', () {
    expect(source.lines.map((l) => l.lineId), [
      LineId.lineHay,
      LineId.lineGamaa,
    ]);
    expect(source.line(LineId.lineGamaa)?.order, 2);
    expect(source.line(LineId.lineSouq), isNull);
  });

  test("a line's trips are by trip number, whatever the pack's order", () {
    final json = samplePackJson();
    final trips = [...(json['trips']! as List<Object?>)];
    final shuffled = _source({
      ...json,
      'trips': [trips[4], trips[1], trips[2], trips[0], trips[3]],
    });
    for (final s in [source, shuffled]) {
      expect(s.tripsOf(LineId.lineHay).map((t) => t.tripId), [
        'line_hay.01',
        'line_hay.02',
        'line_hay.03',
      ]);
      expect(s.tripsOf(LineId.lineGamaa).map((t) => t.tripId), [
        'line_gamaa.01',
        'line_gamaa.02',
      ]);
    }
    expect(source.tripsOf(LineId.lineSouq), isEmpty);
  });

  test('trips are looked up by id', () {
    expect(source.trip('line_gamaa.02')?.lineId, LineId.lineGamaa);
    expect(source.trip('nope'), isNull);
  });

  test('vehicles are in order, and looked up by id', () {
    expect(source.vehicles.map((v) => v.vehicleId), [
      VehicleId.tuktuk,
      VehicleId.microOld,
    ]);
    expect(source.vehicle(VehicleId.tuktuk)?.starter, isTrue);
    expect(source.vehicle(VehicleId.microNew), isNull);
  });

  test('prices are looked up by kind and id, and a starter has none', () {
    expect(source.price(SkuKind.vehicle, 'micro_old'), isNotNull);
    expect(source.price(SkuKind.vehicle, 'tuktuk'), isNull);
    expect(source.price(SkuKind.item, 'salon.nish'), isNotNull);
    expect(source.price(SkuKind.booster, 'ledger_peek'), isNotNull);
    expect(source.price(SkuKind.item, 'ledger_peek'), isNull);
  });

  test('speech pools are looked up by key', () {
    expect(source.speechPool('passenger.pays')?.lines, isNotEmpty);
    expect(source.speechPool('passenger.nope'), isNull);
  });

  test('chapters, rooms and items are in order', () {
    expect(source.chapters.map((c) => c.chapterId), [
      ChapterId.ch1FirstJob,
      ChapterId.ch2HerFather,
      ChapterId.ch3Shabka,
      ChapterId.ch4Salon,
    ]);
    expect(source.chapter(ChapterId.ch3Shabka)?.order, 3);
    expect(source.rooms.map((r) => r.roomId), [RoomId.salon]);
    expect(source.room(RoomId.salon)?.order, 1);
    expect(source.room(RoomId.kitchen), isNull);
    expect(source.itemsOf(RoomId.salon).map((i) => i.itemId), [
      'salon.nish',
      'salon.sitara',
    ]);
    expect(source.itemsOf(RoomId.kitchen), isEmpty);
    expect(source.item('salon.nish')?.roomId, RoomId.salon);
    expect(source.item('salon.nope'), isNull);
  });

  test('items of a room follow `order`, not the pack order', () {
    final json = samplePackJson();
    final items = [...(json['items']! as List<Object?>)];
    final reversed = _source({...json, 'items': items.reversed.toList()});
    expect(reversed.itemsOf(RoomId.salon).map((i) => i.itemId), [
      'salon.nish',
      'salon.sitara',
    ]);
  });

  test('family requests, daily rewards and tasks', () {
    expect(source.familyRequests.map((r) => r.requestId), ['req_nish_crystal']);
    expect(source.dailyRewards.map((d) => d.dayIndex), [1, 2, 3, 4, 5, 6, 7]);
    expect(source.tasks.map((t) => t.taskId), [
      'task_exact_change',
      'task_three_stars',
      'task_trips_done',
    ]);
  });

  test('every list is unmodifiable', () {
    final lists = <List<Object>>[
      source.lines,
      source.tripsOf(LineId.lineHay),
      source.tripsOf(LineId.lineSouq),
      source.vehicles,
      source.chapters,
      source.rooms,
      source.itemsOf(RoomId.salon),
      source.itemsOf(RoomId.kitchen),
      source.familyRequests,
      source.dailyRewards,
      source.tasks,
    ];
    for (final list in lists) {
      expect(list.clear, throwsUnsupportedError);
      if (list.isNotEmpty) {
        expect(() => list.add(list.first), throwsUnsupportedError);
      }
    }
  });
}
