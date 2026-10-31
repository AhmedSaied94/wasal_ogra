// The price on a buy button (specs/015-m10-apartment-story, `AptGoalReady`,
// `AptGoalVehicle` and `PieceAffordable`): a `sun` pill, 32 high, with
// «−{n} ج» in `ink`.
import 'package:flutter/widgets.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

class PriceChip extends StatelessWidget {
  const PriceChip({required this.label, super.key});

  /// Preformatted, for example «−١٬٠٥٠ ج».
  final String label;

  static const double height = 32;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.s10),
    decoration: BoxDecoration(
      color: ColorTokens.sun,
      borderRadius: BorderRadius.circular(RadiusTokens.pill),
    ),
    child: Center(
      child: Text(
        label,
        maxLines: 1,
        style: DesignExtras.compactLabel.copyWith(color: ColorTokens.ink),
      ),
    ),
  );
}
