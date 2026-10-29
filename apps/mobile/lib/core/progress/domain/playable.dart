// The phone-only progression rules (specs/014-m09-lines-vehicles,
// contracts/progress-rules.md, research R1): beside the port of the
// server's rules in unlocks.dart, which stays a one-to-one copy. Each rule
// here is only ever stricter than the server's, so the phone never offers
// what the server would refuse (playable_test.dart proves it).
import 'package:content_models/content_models.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/economy/domain/wire.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/core/progress/domain/unlocks.dart';

/// Whether [tripId] may start (FR-006, FR-007). A story trip a chapter
/// names comes at its moment in the story: its line open, its vehicle the
/// player's, and its chapter's goal met (Clarifications Q1). Any other trip
/// is [tripUnlocked]. An unknown id is never playable.
bool tripPlayable(ContentSource c, PlayerProgress p, String tripId) {
  final trip = c.trip(tripId);
  if (trip == null) return false;
  if (trip.kind == TripKind.story) {
    for (final chapter in chaptersInOrder(c)) {
      if (chapter.storyTripId != tripId) continue;
      return lineUnlocked(c, p, trip.lineId) &&
          vehicleOwned(c, p, trip.vehicleId) &&
          chapterComplete(c, p, chapter.chapterId);
    }
  }
  return tripUnlocked(c, p, tripId);
}

/// The player's vehicle (FR-002): the last of theirs by `order`. Null for a
/// pack without vehicles.
Vehicle? currentVehicle(ContentSource c, PlayerProgress p) {
  Vehicle? current;
  for (final vehicle in c.vehicles) {
    if (vehicleOwned(c, p, vehicle.vehicleId)) current = vehicle;
  }
  return current;
}

/// Whether the player can buy a vehicle, and at what price (FR-003,
/// FR-035).
sealed class VehicleSale {
  const VehicleSale();
}

/// The player's already: a starter, or bought.
final class Owned extends VehicleSale {
  const Owned();

  @override
  bool operator ==(Object other) => other is Owned;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'Owned()';
}

/// For sale at its catalog price.
final class ForSale extends VehicleSale {
  const ForSale(this.priceJenehat);

  final int priceJenehat;

  @override
  bool operator ==(Object other) =>
      other is ForSale && other.priceJenehat == priceJenehat;

  @override
  int get hashCode => priceJenehat.hashCode;

  @override
  String toString() => 'ForSale($priceJenehat)';
}

/// Vehicles are sold in pack order: [vehicle], an earlier one, comes first.
final class NeedsFirst extends VehicleSale {
  const NeedsFirst(this.vehicle);

  final VehicleId vehicle;

  @override
  bool operator ==(Object other) =>
      other is NeedsFirst && other.vehicle == vehicle;

  @override
  int get hashCode => vehicle.hashCode;

  @override
  String toString() => 'NeedsFirst(${vehicle.name})';
}

/// No JENEHAT price in the catalog, or a vehicle the pack lacks.
final class NoPrice extends VehicleSale {
  const NoPrice();

  @override
  bool operator ==(Object other) => other is NoPrice;

  @override
  int get hashCode => 1;

  @override
  String toString() => 'NoPrice()';
}

/// [vehicleId]'s sale state for [p]. The economy and the server accept any
/// order, so this is the only vehicle-order check there is (research R1).
VehicleSale vehicleSale(
  ContentSource c,
  PlayerProgress p,
  VehicleId vehicleId,
) {
  final vehicle = c.vehicle(vehicleId);
  if (vehicle == null) return const NoPrice();
  if (vehicleOwned(c, p, vehicleId)) return const Owned();
  for (final earlier in c.vehicles) {
    if (earlier.order >= vehicle.order) break;
    if (!vehicleOwned(c, p, earlier.vehicleId)) {
      return NeedsFirst(earlier.vehicleId);
    }
  }
  return switch (c.price(SkuKind.vehicle, vehicleWire[vehicleId]!)) {
    CatalogPrice(currency: Currency.jenehat, :final amount) => ForSale(amount),
    _ => const NoPrice(),
  };
}
