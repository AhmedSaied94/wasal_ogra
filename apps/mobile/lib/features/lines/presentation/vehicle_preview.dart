// The vehicle sheet's preview (specs/014-m09-lines-vehicles, research R10,
// HANDOFF `BuyVehicle` block 2c): the vehicle on the sky and the kerb,
// decorative; the drawing brings its own sun. No «بزينتك»: there are no cosmetics before M16.
import 'package:content_models/content_models.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rive/rive.dart' as rive;
import 'package:wassal/core/theme/components/vehicle_sprite.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/lines/presentation/vehicle_art.dart';

class VehiclePreview extends StatelessWidget {
  const VehiclePreview({required this.vehicle, super.key});

  final VehicleId vehicle;

  static const double height = 190;
  static const double _kerb = 40;
  static const double _shadowWidth = 200;
  static const double _shadowHeight = 14;

  /// The vehicle stands on the kerb, as wide as the board draws it.
  static const Size _vehicle = Size(322, 150);

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(RadiusTokens.xl),
      child: SizedBox(
        height: height,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            const Positioned.fill(
              child: ColoredBox(color: ColorTokens.sceneSky),
            ),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: _kerb,
              child: ColoredBox(color: ColorTokens.sceneKerb),
            ),
            Positioned(
              bottom: _kerb - _shadowHeight / 2,
              child: Container(
                width: _shadowWidth,
                height: _shadowHeight,
                decoration: const BoxDecoration(
                  color: ColorTokens.sceneShadow,
                  borderRadius: BorderRadius.all(
                    Radius.elliptical(_shadowWidth / 2, _shadowHeight / 2),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: SpaceTokens.s12,
              height: _vehicle.height,
              width: _vehicle.width,
              child: VehicleSprite(
                vehicle: vehicle,
                // The box is wider than the 236×150 artboard: keep its
                // aspect rather than stretch the vehicle (FR-031).
                fit: rive.Fit.contain,
                fallback: VehicleArt(vehicle: vehicle),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
