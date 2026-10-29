// What the purchase leaves for the savings goal (specs/014-m09-lines-
// vehicles, research R7, HANDOFF `BuyVehicle` block 2f): «بعد الشرا، فاضل
// {amount} ج على {goal}» on `sun.soft`.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/lines/domain/impact.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class ImpactLine extends ConsumerWidget {
  const ImpactLine({required this.impact, super.key});

  final Impact impact;

  static const double _icon = 24;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: SpaceTokens.s12,
      vertical: SpaceTokens.s10,
    ),
    decoration: BoxDecoration(
      color: ColorTokens.sunSoft,
      borderRadius: BorderRadius.circular(RadiusTokens.bubble),
    ),
    child: Row(
      spacing: SpaceTokens.s10,
      children: [
        const AppIcon('ring_gem', size: _icon),
        Expanded(
          child: Text(
            AppLocalizations.of(context).buyVehicleImpact(
              ref.watch(numberFormatterProvider).integer(impact.amount),
              impact.goalName,
            ),
            style: DesignExtras.buyVehicleImpact.copyWith(
              color: ColorTokens.ink,
            ),
          ),
        ),
      ],
    ),
  );
}
