// A sheet's status in the button's place (specs/014-m09-lines-vehicles;
// `BuyVehicleOwned` box 14, `BuyVehicleNotForSale` box 25,
// `LineDetailsLocked` box 75): a tick on `primary.soft` for the player's own
// vehicle, or the locked look with a lock for what isn't open yet. Read,
// never tapped.
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/lines/presentation/locked_fill.dart';

class StatusRow extends StatelessWidget {
  const StatusRow.owned({required this.text, super.key}) : locked = false;
  const StatusRow.locked({required this.text, super.key}) : locked = true;

  final String text;
  final bool locked;

  static const double _icon = 24;
  static const double _tick = 14;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(RadiusTokens.bubble);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SpaceTokens.s12,
        vertical: SpaceTokens.s10,
      ),
      decoration: locked
          ? lockedFill(radius)
          : BoxDecoration(color: ColorTokens.primarySoft, borderRadius: radius),
      child: Row(
        spacing: SpaceTokens.s10,
        children: [
          if (locked)
            const LockGlyph(size: _icon)
          else
            Container(
              width: _icon,
              height: _icon,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: ColorTokens.primary,
                shape: BoxShape.circle,
              ),
              child: const AppIcon(
                'check',
                size: _tick,
                color: ColorTokens.paper,
              ),
            ),
          Expanded(
            child: Text(
              text,
              style: DesignExtras.linesStatusRow.copyWith(
                color: locked ? ColorTokens.ink2 : ColorTokens.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
