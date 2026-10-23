// A vehicle in the «كرتون ناعم» style (contracts/rive-characters.md
// "Vehicles"): `wassal.riv`'s `Vehicle` with its look, bobbing in place or
// driving, facing left, the direction of travel. Without the file, and
// under reduced motion, the caller's static art draws instead.
import 'package:content_models/content_models.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rive/rive.dart' as rive;
import 'package:wassal/core/art/rive_art.dart';

class VehicleSprite extends StatelessWidget {
  const VehicleSprite({
    required this.vehicle,
    required this.fallback,
    this.driving = false,
    super.key,
  });

  final VehicleId vehicle;

  /// The static art, in the same box.
  final Widget fallback;

  /// The wheels spin; otherwise the body bobs.
  final bool driving;

  /// The artboard's size.
  static const size = Size(236, 150);

  /// Its `look` number.
  static int look(VehicleId vehicle) => switch (vehicle) {
    VehicleId.tuktuk => 0,
    VehicleId.microOld => 1,
    VehicleId.microNew => 2,
    VehicleId.microSafar => 3,
  };

  @override
  Widget build(BuildContext context) => RiveArtView(
    artboard: 'Vehicle',
    fit: rive.Fit.fill,
    bind: (model) {
      model.number('look')?.value = look(vehicle).toDouble();
      model.boolean('driving')?.value = driving;
    },
    fallback: fallback,
  );
}
