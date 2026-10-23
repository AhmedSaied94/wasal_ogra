// A story trip's condition (HANDOFF `StoryTrip` block 3, research R11): a
// dark strip at the scene's top for the whole trip, the shield over
// «أي خناقة والمشوار يتعاد». Broken, it turns `danger` as the trip fails.
// Bubbles keep below its band (`storyBand`).
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class StoryStrip extends StatelessWidget {
  const StoryStrip({super.key});

  static const iconKey = ValueKey('trip-story-shield');

  static const double height = 40;
  static const double _radius = 14;
  static const double _icon = 20;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TripSelector<bool?>(
      select: (model) => model.view?.storyCondition,
      builder: (context, kept) {
        if (kept == null) return const SizedBox.shrink();
        return Semantics(
          container: true,
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.s12),
            decoration: BoxDecoration(
              color: kept ? ColorTokens.dashboardBg : ColorTokens.danger,
              borderRadius: BorderRadius.circular(_radius),
            ),
            child: Row(
              spacing: SpaceTokens.s8,
              children: [
                const AppIcon('shield_check', key: iconKey, size: _icon),
                Expanded(
                  child: Text(
                    l10n.tripStoryNoFights,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TypeTokens.caption
                        .weight(600)
                        .copyWith(
                          color: kept ? ColorTokens.paper : ColorTokens.ink,
                        ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
