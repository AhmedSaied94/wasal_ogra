// The result's breakdown (specs/013-m08-home-result, `Result` block 6,
// FR-039): the fares collected, the tips, the change over-paid and the
// fights, each the result's own figure.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/components/containers.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/result/domain/summary.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class BreakdownCard extends ConsumerWidget {
  const BreakdownCard({required this.breakdown, super.key});

  final Breakdown breakdown;

  static const faresKey = Key('BreakdownCard.fares');
  static const tipsKey = Key('BreakdownCard.tips');
  static const overpaidKey = Key('BreakdownCard.overpaid');
  static const fightsKey = Key('BreakdownCard.fights');

  /// `Result` block 6: padding 7 16, rows of 32.5 between 2 pt dividers.
  static const double _padV = 7;
  static const double _rowHeight = 32.5;
  static const double _divider = 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final rows = [
      (
        faresKey,
        l10n.resultFares,
        numbers.piasters(breakdown.faresPiasters),
        ColorTokens.ink,
        true,
      ),
      (
        tipsKey,
        l10n.resultTips,
        l10n.resultPlus(numbers.piasters(breakdown.tipsPiasters)),
        ColorTokens.primary,
        true,
      ),
      (
        overpaidKey,
        l10n.resultOverpaid,
        l10n.resultMinus(numbers.piasters(breakdown.overpaidPiasters)),
        ColorTokens.dangerInk,
        true,
      ),
      (
        fightsKey,
        l10n.resultFights,
        numbers.integer(breakdown.fights),
        ColorTokens.ink,
        false,
      ),
    ];
    return AppCard(
      padding: const EdgeInsets.symmetric(
        vertical: _padV,
        horizontal: SpaceTokens.s16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, (key, label, value, color, money))
              in rows.indexed) ...[
            if (i > 0)
              const SizedBox(
                height: _divider,
                child: ColoredBox(color: ColorTokens.track),
              ),
            Semantics(
              key: key,
              container: true,
              label: money
                  ? l10n.resultA11yBreakdownRow(label, value)
                  : l10n.resultA11yCountRow(label, value),
              excludeSemantics: true,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: _rowHeight),
                child: Row(
                  spacing: SpaceTokens.s8,
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: DesignExtras.resultRow.copyWith(
                          color: ColorTokens.ink,
                        ),
                      ),
                    ),
                    Text(
                      value,
                      style: DesignExtras.resultRow
                          .weight(700)
                          .copyWith(color: color),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
