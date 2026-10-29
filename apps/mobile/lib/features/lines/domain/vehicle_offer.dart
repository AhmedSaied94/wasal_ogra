// What the vehicle sheet shows (specs/014-m09-lines-vehicles, data-model
// `VehicleOffer`, contracts/buy-vehicle.md): the seats against the current
// vehicle's, the line it opens, its sale state, the price against the
// player's JENEHAT, and the purchase's impact.
import 'package:content_models/content_models.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/progress/domain/playable.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';

import 'package:wassal/features/lines/domain/impact.dart';

final class VehicleOffer {
  const VehicleOffer({
    required this.vehicle,
    required this.name,
    required this.starter,
    required this.seats,
    required this.currentSeats,
    required this.opensLine,
    required this.sale,
    required this.jenehat,
    required this.impact,
  });

  final VehicleId vehicle;
  final String name;

  /// The starter: «دي عربية المعلم» when owned.
  final bool starter;
  final int seats;

  /// The current vehicle's seats: «كرسي بدل {currentSeats}».
  final int currentSeats;

  /// The first line, by order, this vehicle opens; null hides «بيفتح».
  final LineId? opensLine;
  final VehicleSale sale;

  /// The player's JENEHAT.
  final int jenehat;
  final Impact? impact;

  /// The catalog price, only when for sale.
  int? get price => switch (sale) {
    ForSale(:final priceJenehat) => priceJenehat,
    _ => null,
  };

  /// What [jenehat] lacks of the price; null when it covers it or there is
  /// none.
  int? get shortfall => switch (price) {
    final price? when price > jenehat => price - jenehat,
    _ => null,
  };

  /// For sale, and [jenehat] covers it.
  bool get affordable => price != null && shortfall == null;

  @override
  bool operator ==(Object other) =>
      other is VehicleOffer &&
      other.vehicle == vehicle &&
      other.name == name &&
      other.starter == starter &&
      other.seats == seats &&
      other.currentSeats == currentSeats &&
      other.opensLine == opensLine &&
      other.sale == sale &&
      other.jenehat == jenehat &&
      other.impact == impact;

  @override
  int get hashCode => Object.hash(
    vehicle,
    name,
    starter,
    seats,
    currentSeats,
    opensLine,
    sale,
    jenehat,
    impact,
  );

  @override
  String toString() => 'VehicleOffer(${vehicle.name}, $sale, $jenehat)';
}

/// [vehicle]'s offer, or null when the pack lacks it.
VehicleOffer? vehicleOffer(
  ContentSource c,
  PlayerProgress p,
  int jenehat,
  VehicleId vehicle,
) {
  final v = c.vehicle(vehicle);
  if (v == null) return null;
  LineId? opens;
  for (final line in c.lines) {
    if (line.unlock.kind == UnlockKind.vehicle &&
        line.unlock.vehicleId == vehicle) {
      opens = line.lineId;
      break;
    }
  }
  return VehicleOffer(
    vehicle: vehicle,
    name: v.name.arEg,
    starter: v.starter,
    seats: v.seats.length,
    currentSeats: currentVehicle(c, p)?.seats.length ?? 0,
    opensLine: opens,
    sale: vehicleSale(c, p, vehicle),
    jenehat: jenehat,
    impact: impactAfterPurchase(c, p, jenehat, vehicle),
  );
}
