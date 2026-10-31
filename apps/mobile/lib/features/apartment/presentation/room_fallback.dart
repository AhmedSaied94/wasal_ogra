// The room's and a piece's drawn fallbacks (specs/015-m10-apartment-story,
// research R17): a pack without art still draws a room and its pieces.
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

/// The empty room: the wall's colour over the floor, as the boards draw the
/// room (`AptRooms`: the wall down to 196 of 300, the floor under it).
class RoomFallback extends StatelessWidget {
  const RoomFallback({super.key});

  /// The floor's height in the 358 x 300 design space.
  static const double floorHeight = 104;

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(color: ColorTokens.sceneRoom),
    child: Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        height: floorHeight,
        width: double.infinity,
        child: ColoredBox(color: ColorTokens.sceneFloor),
      ),
    ),
  );
}

/// A piece with no drawing: a soft block in its slot.
class PieceFallback extends StatelessWidget {
  const PieceFallback({super.key});

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      color: ColorTokens.groundLip,
      borderRadius: BorderRadius.all(Radius.circular(RadiusTokens.s)),
    ),
  );
}
