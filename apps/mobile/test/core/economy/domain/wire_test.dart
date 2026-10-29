import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/economy/domain/wire.dart';

import '../../../helpers/economy.dart';

// The economy spells the generated enums' wire names out; each must be what
// content_models (or, for boosters, the trip engine) reads.

void main() {
  test('every SKU kind decodes as itself', () {
    for (final kind in SkuKind.values) {
      final price = CatalogPrice.fromJson({
        'sku_kind': skuKindWire[kind],
        'sku_id': 'x',
        'currency': 'JENEHAT',
        'amount': 1,
      });
      expect(price.skuKind, kind);
    }
  });

  test('every vehicle decodes as itself', () {
    for (final id in VehicleId.values) {
      final vehicle = Vehicle.fromJson({
        'vehicle_id': vehicleWire[id],
        'name': {'ar-EG': 'x'},
        'short_name': {'ar-EG': 'x'},
        'order': 1,
        'starter': false,
        'seats': <Object>[],
      });
      expect(vehicle.vehicleId, id);
    }
  });

  test('every chapter decodes as itself', () {
    for (final id in ChapterId.values) {
      final room = Room.fromJson({
        'room_id': 'salon',
        'name': {'ar-EG': 'x'},
        'order': 1,
        'chapter_id': chapterWire[id],
        'completion_bonat': 0,
      });
      expect(room.chapterId, id);
    }
  });

  test('every booster decodes as itself in a trip result', () {
    for (final id in BoosterId.values) {
      final json = tripResult(tripId: 'line_hay.01').toJson();
      final result = TripResult.fromJson({
        ...json,
        'boosters_used': [boosterWire[id]],
      });
      expect(result.boostersUsed, [id]);
    }
  });

  test('fromWire finds a name, or null', () {
    expect(fromWire(boosterWire, 'wake_all'), BoosterId.wakeAll);
    expect(fromWire(boosterWire, 'nope'), isNull);
  });
}
