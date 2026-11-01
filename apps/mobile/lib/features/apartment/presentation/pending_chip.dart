// The rewards on their way (specs/015-m10-apartment-story, contracts/
// apartment.md "The pending chip", research R6, `AptRoomsAffordable`): a
// `sun.soft` pill in the rooms header, between the title and the coins pill.
// It is a status, not a button: the BONAT icon beside «+٥ بون» over «في
// الطريق», and under 360 pt only the icon, «+٥» and a clock mark. Hidden
// when nothing is pending.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/progress/application/pending_rewards_provider.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class PendingChip extends ConsumerWidget {
  const PendingChip({super.key});

  /// The chip's least height: the coins pill's.
  static const height = 40.0;

  /// The width under which the chip shrinks to its icon, the amount and a
  /// clock.
  static const narrowBelow = 360.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = ref.watch(pendingRewardTotalProvider);
    if (total == 0) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final narrow = MediaQuery.sizeOf(context).width < narrowBelow;
    final amount = l10n.pendingRewards(numbers.integer(total));
    return Semantics(
      label: l10n.pendingRewardsA11y(total, numbers.integer(total)),
      liveRegion: true,
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: height),
        padding: const EdgeInsetsDirectional.fromSTEB(
          SpaceTokens.s8,
          3,
          SpaceTokens.s12,
          3,
        ),
        decoration: BoxDecoration(
          color: ColorTokens.sunSoft,
          borderRadius: BorderRadius.circular(RadiusTokens.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: SpaceTokens.s6,
          children: [
            const AppIcon('bonat', size: 20),
            if (narrow) ...[
              Text(
                amount,
                style: TypeTokens.caption
                    .weight(700)
                    .copyWith(color: ColorTokens.ink),
              ),
              const AppIcon('clock', size: 14, color: ColorTokens.inkMuted),
            ] else
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    amount,
                    style: TypeTokens.caption
                        .weight(700)
                        .copyWith(color: ColorTokens.ink, height: 1.15),
                  ),
                  Text(
                    l10n.pendingRewardsWay,
                    style: TypeTokens.label
                        .weight(600)
                        .copyWith(color: ColorTokens.inkMuted, height: 1.15),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
