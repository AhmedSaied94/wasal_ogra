// The vehicle strip (specs/014-m09-lines-vehicles, data-model `VehicleTile`,
// FR-016): each vehicle in pack order, done, current, for sale or not.
import 'package:content_models/content_models.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/progress/domain/playable.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';

sealed class TileState {
  const TileState();
}

/// The player's, before the current one: a tick.
final class TileDone extends TileState {
  const TileDone();

  @override
  bool operator ==(Object other) => other is TileDone;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'TileDone()';
}

/// The player's vehicle: «{short} · عربيتك».
final class TileCurrent extends TileState {
  const TileCurrent();

  @override
  bool operator ==(Object other) => other is TileCurrent;

  @override
  int get hashCode => 1;

  @override
  String toString() => 'TileCurrent()';
}

/// For sale: the locked look with the price.
final class TileForSale extends TileState {
  const TileForSale(this.priceJenehat);

  final int priceJenehat;

  @override
  bool operator ==(Object other) =>
      other is TileForSale && other.priceJenehat == priceJenehat;

  @override
  int get hashCode => priceJenehat.hashCode;

  @override
  String toString() => 'TileForSale($priceJenehat)';
}

/// Not for sale yet, or not at all: the locked look, no price.
final class TileNotForSale extends TileState {
  const TileNotForSale();

  @override
  bool operator ==(Object other) => other is TileNotForSale;

  @override
  int get hashCode => 2;

  @override
  String toString() => 'TileNotForSale()';
}

final class VehicleTile {
  const VehicleTile({
    required this.vehicle,
    required this.name,
    required this.shortName,
    required this.state,
  });

  final VehicleId vehicle;

  /// For labels and the sheet.
  final String name;

  /// On the tile.
  final String shortName;
  final TileState state;

  @override
  bool operator ==(Object other) =>
      other is VehicleTile &&
      other.vehicle == vehicle &&
      other.name == name &&
      other.shortName == shortName &&
      other.state == state;

  @override
  int get hashCode => Object.hash(vehicle, name, shortName, state);

  @override
  String toString() => 'VehicleTile(${vehicle.name}, $state)';
}

List<VehicleTile> vehicleTiles(ContentSource c, PlayerProgress p) {
  final current = currentVehicle(c, p)?.vehicleId;
  return [
    for (final vehicle in c.vehicles)
      VehicleTile(
        vehicle: vehicle.vehicleId,
        name: vehicle.name.arEg,
        shortName: vehicle.shortName.arEg,
        state: vehicle.vehicleId == current
            ? const TileCurrent()
            : switch (vehicleSale(c, p, vehicle.vehicleId)) {
                Owned() => const TileDone(),
                ForSale(:final priceJenehat) => TileForSale(priceJenehat),
                NeedsFirst() || NoPrice() => const TileNotForSale(),
              },
      ),
  ];
}
