// The vehicle sheet's offer (specs/014-m09-lines-vehicles, contracts/
// buy-vehicle.md), rebuilt from the pack and the economy, so a sync or a
// rollback flips an open sheet between short and affordable, or to owned.
import 'package:content_models/content_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/progress/application/player_progress_provider.dart';
import 'package:wassal/features/lines/domain/vehicle_offer.dart';

part 'vehicle_offer_provider.g.dart';

/// Null for a vehicle the active pack lacks.
@riverpod
VehicleOffer? vehicleOfferOf(Ref ref, VehicleId vehicle) => vehicleOffer(
  ref.watch(contentSourceProvider),
  ref.watch(playerProgressProvider),
  ref.watch(economyViewProvider).jenehat,
  vehicle,
);
