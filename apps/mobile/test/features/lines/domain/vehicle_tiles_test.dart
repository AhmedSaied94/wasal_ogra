// The vehicle strip's tiles (specs/014-m09-lines-vehicles, data-model
// `VehicleTile`, FR-002, FR-003, FR-016).
import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/features/lines/domain/vehicle_tiles.dart';

import '../../../helpers/progress.dart';

const _microNew = (SkuKind.vehicle, 'micro_new');

Map<VehicleId, TileState> _states(PlayerProgress p) => {
  for (final tile in vehicleTiles(artboardContent(), p))
    tile.vehicle: tile.state,
};

void main() {
  test('a new player: the starter current, the next for sale, the rest '
      'not', () {
    expect(_states(PlayerProgress.empty), {
      VehicleId.tuktuk: const TileCurrent(),
      VehicleId.microOld: const TileForSale(1500),
      VehicleId.microNew: const TileNotForSale(),
      VehicleId.microSafar: const TileNotForSale(),
    });
  });

  test('after the microbus: the starter done, the microbus current', () {
    expect(_states(player({}, {microOld})), {
      VehicleId.tuktuk: const TileDone(),
      VehicleId.microOld: const TileCurrent(),
      VehicleId.microNew: const TileForSale(5000),
      VehicleId.microSafar: const TileNotForSale(),
    });
  });

  test('the current is the last owned by order', () {
    expect(_states(player({}, {microOld, _microNew})), {
      VehicleId.tuktuk: const TileDone(),
      VehicleId.microOld: const TileDone(),
      VehicleId.microNew: const TileCurrent(),
      VehicleId.microSafar: const TileForSale(12000),
    });
  });

  test('a rollback makes the vehicle for sale again', () {
    final before = _states(player({}, {microOld}));
    final after = _states(PlayerProgress.empty);
    expect(before[VehicleId.microOld], const TileCurrent());
    expect(after[VehicleId.microOld], const TileForSale(1500));
    expect(after[VehicleId.tuktuk], const TileCurrent());
  });

  test('tiles carry the names from content, in pack order', () {
    final tiles = vehicleTiles(artboardContent(), PlayerProgress.empty);
    expect(
      [for (final t in tiles) t.vehicle],
      [
        VehicleId.tuktuk,
        VehicleId.microOld,
        VehicleId.microNew,
        VehicleId.microSafar,
      ],
    );
    expect(tiles.first.shortName, 'توكتوك');
    expect(tiles.first.name, 'توكتوك المعلم');
    expect(tiles[2].shortName, 'جديد');
  });
}
