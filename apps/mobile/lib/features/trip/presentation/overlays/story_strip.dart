// A story trip's condition (FR-041, ux-spec «مشاوير القصة»): under the
// station strip for the whole trip, «أي خناقة والمشوار يتعاد». Broken, it
// turns red as the trip fails.
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/tokens/shape.dart';
import 'package:wassal/core/theme/tokens/space.dart';
import 'package:wassal/core/theme/tokens/typography.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class StoryStrip extends StatelessWidget {
  const StoryStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    return TripSelector<bool?>(
      select: (model) => model.view?.storyCondition,
      builder: (context, kept) {
        if (kept == null) return const SizedBox.shrink();
        return Center(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: SpaceTokens.m,
              vertical: SpaceTokens.xs,
            ),
            decoration: BoxDecoration(
              color: kept ? tokens.gold : tokens.danger,
              borderRadius: BorderRadius.circular(ShapeTokens.radiusControl),
              border: Border.all(
                color: tokens.hibr,
                width: ShapeTokens.borderCard,
              ),
            ),
            child: Text(
              l10n.tripStoryNoFights,
              textAlign: TextAlign.center,
              style: TypeTokens.label.copyWith(color: tokens.hibr),
            ),
          ),
        );
      },
    );
  }
}
