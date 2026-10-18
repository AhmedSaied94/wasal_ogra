import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/tokens/shape.dart';
import 'package:wassal/core/theme/tokens/space.dart';

/// A ورق card with a حبر border and a hard shadow (no blur).
class StickerCard extends StatelessWidget {
  const StickerCard({
    required this.child,
    this.padding = const EdgeInsets.all(SpaceTokens.l),
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.waraq,
        border: Border.all(color: tokens.hibr, width: ShapeTokens.borderCard),
        borderRadius: BorderRadius.circular(ShapeTokens.radiusCard),
        boxShadow: [
          BoxShadow(
            color: tokens.hibr,
            offset: hardShadowOffset(
              ShapeTokens.shadowCard,
              Directionality.of(context),
            ),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
