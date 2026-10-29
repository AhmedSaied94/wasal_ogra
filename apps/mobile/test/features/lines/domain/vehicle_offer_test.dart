// The vehicle sheet's offer (specs/014-m09-lines-vehicles, data-model
// `VehicleOffer`, FR-030–FR-035).
import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/progress/domain/playable.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/features/lines/domain/vehicle_offer.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/progress.dart';

void main() {
  test('the seats against the current vehicle\'s', () {
    final c = artboardContent();
    final offer = vehicleOffer(
      c,
      player({}, {microOld}),
      0,
      VehicleId.microNew,
    )!;
    expect(offer.seats, 12);
    expect(offer.currentSeats, 10);
    expect(
      vehicleOffer(
        c,
        PlayerProgress.empty,
        0,
        VehicleId.microOld,
      )!.currentSeats,
      3,
    );
  });

  test('the line it opens, the first by order, or none', () {
    final c = artboardContent();
    expect(
      vehicleOffer(c, PlayerProgress.empty, 0, VehicleId.microNew)!.opensLine,
      LineId.lineSouq,
    );
    expect(
      vehicleOffer(c, PlayerProgress.empty, 0, VehicleId.microOld)!.opensLine,
      LineId.lineGamaa,
    );
    expect(
      vehicleOffer(c, PlayerProgress.empty, 0, VehicleId.tuktuk)!.opensLine,
      isNull,
    );
  });

  test('each sale state', () {
    final c = artboardContent();
    final p = player({}, {microOld});
    expect(vehicleOffer(c, p, 0, VehicleId.tuktuk)!.sale, const Owned());
    expect(vehicleOffer(c, p, 0, VehicleId.microOld)!.sale, const Owned());
    expect(
      vehicleOffer(c, p, 0, VehicleId.microNew)!.sale,
      const ForSale(5000),
    );
    expect(
      vehicleOffer(c, p, 0, VehicleId.microSafar)!.sale,
      const NeedsFirst(VehicleId.microNew),
    );
    expect(vehicleOffer(c, p, 0, VehicleId.microSafar)!.price, isNull);
  });

  test('the list price whatever the sale state, never a shortfall from '
      'it (BuyVehicleNotForSale, T078)', () {
    final c = artboardContent();
    final p = player({}, {microOld});
    final needsFirst = vehicleOffer(c, p, 1240, VehicleId.microSafar)!;
    expect(needsFirst.listPrice, 12000);
    expect(needsFirst.shortfall, isNull);
    expect(needsFirst.affordable, isFalse);
    // Owned, and still the sample's 1,500.
    expect(vehicleOffer(c, p, 0, VehicleId.microOld)!.listPrice, 1500);
    expect(vehicleOffer(c, p, 0, VehicleId.microNew)!.listPrice, 5000);
    // The starter has no catalog price.
    expect(vehicleOffer(c, p, 0, VehicleId.tuktuk)!.listPrice, isNull);
  });

  test('the shortfall; exactly enough leaves none', () {
    final c = artboardContent();
    final p = player({}, {microOld});
    final short = vehicleOffer(c, p, 4700, VehicleId.microNew)!;
    expect(short.shortfall, 300);
    expect(short.affordable, isFalse);
    final exact = vehicleOffer(c, p, 5000, VehicleId.microNew)!;
    expect(exact.shortfall, isNull);
    expect(exact.affordable, isTrue);
    expect(vehicleOffer(c, p, 0, VehicleId.microOld)!.shortfall, isNull);
  });

  test('a vehicle the pack lacks has no offer', () {
    expect(
      vehicleOffer(
        sampleContent(),
        PlayerProgress.empty,
        0,
        VehicleId.microNew,
      ),
      isNull,
    );
  });
}
