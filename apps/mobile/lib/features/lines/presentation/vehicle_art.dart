// Each vehicle's static drawing (specs/014-m09-lines-vehicles, research
// R10): the fallback under `VehicleSprite`, and the tiles' art.
import 'package:content_models/content_models.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

String vehicleArtAsset(VehicleId vehicle) =>
    'assets/illustrations/vehicles/${switch (vehicle) {
      VehicleId.tuktuk => 'tuktuk',
      VehicleId.microOld => 'microbus_old',
      VehicleId.microNew => 'microbus_new',
      VehicleId.microSafar => 'microbus_travel',
    }}.svg';

class VehicleArt extends StatelessWidget {
  const VehicleArt({required this.vehicle, super.key});

  final VehicleId vehicle;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    vehicleArtAsset(vehicle),
    fit: BoxFit.contain,
    excludeFromSemantics: true,
  );
}
