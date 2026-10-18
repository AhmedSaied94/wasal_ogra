import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/tokens/shape.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// The «new» dot: a danger-colored dot with an ink outline, so it reaches
/// 3:1 on every background by its fill or its outline (FR-016a).
class NewDot extends StatelessWidget {
  const NewDot({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      label: AppLocalizations.of(context).newBadgeLabel,
      child: SizedBox.square(
        dimension: ShapeTokens.badgeSize,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.badgeNew,
            shape: BoxShape.circle,
            border: Border.all(
              color: tokens.hibr,
              width: ShapeTokens.badgeOutline,
            ),
          ),
        ),
      ),
    );
  }
}
