// The card's star goals (specs/013-m08-home-result, `PreTrip` boxes
// 35–42, FR-030): the three rows, each filled once earned, else the empty
// star and «لسه».
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class StarGoals extends StatelessWidget {
  const StarGoals({required this.earned, super.key});

  /// The trip's best stars, 0–3.
  final int earned;

  static Key rowKey(int star) => ValueKey('StarGoals.row.$star');

  static const double _star = 22;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final goals = [l10n.preTripStar1, l10n.preTripStar2, l10n.preTripStar3];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: SpaceTokens.s6,
      children: [
        Text(
          l10n.preTripStars,
          style: DesignExtras.preTripLine.copyWith(color: ColorTokens.inkMuted),
        ),
        for (final (i, goal) in goals.indexed)
          Semantics(
            key: rowKey(i + 1),
            container: true,
            label: i < earned
                ? l10n.preTripA11yStarEarned(goal)
                : l10n.preTripA11yStarNotYet(goal),
            excludeSemantics: true,
            child: Row(
              spacing: SpaceTokens.s8,
              children: [
                AppIcon(i < earned ? 'star' : 'star_outline', size: _star),
                Expanded(
                  child: Text(
                    goal,
                    style: TypeTokens.body.copyWith(color: ColorTokens.ink),
                  ),
                ),
                if (i >= earned)
                  Text(
                    l10n.preTripStarNotYet,
                    style: TypeTokens.label
                        .weight(600)
                        .copyWith(color: ColorTokens.inkMuted),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
