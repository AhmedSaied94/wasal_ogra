// The pay on the result (specs/013-m08-home-result, `Result` block 8,
// research R19): «قبضت», the coin and the JENEHAT, counting up from 0, and
// the BONAT a task finished in this trip gave (M13's slot).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class PayBlock extends ConsumerWidget {
  const PayBlock({required this.payJenehat, this.bonat, super.key});

  final int payJenehat;

  /// The task's BONAT, on a chip after the pay; none without a task.
  final int? bonat;

  static const amountKey = Key('PayBlock.amount');
  static const bonatKey = Key('PayBlock.bonat');

  /// `Result` boxes 39, 41.
  static const double _coin = 34;

  /// `Result` block 10's row, the amount centred in it.
  static const double _minHeight = 64;
  static const EdgeInsets _chipPadding = EdgeInsets.symmetric(
    vertical: SpaceTokens.s2,
    horizontal: SpaceTokens.s10,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final style = DesignExtras.resultPay.copyWith(color: ColorTokens.ink);
    Widget amount(int value) =>
        Text(numbers.integer(value), key: amountKey, style: style);
    return Semantics(
      container: true,
      label: l10n.resultA11yPay(numbers.integer(payJenehat)),
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: _minHeight),
        alignment: Alignment.center,
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: SpaceTokens.s12,
          children: [
            Text(
              l10n.resultPaid,
              style: DesignExtras.resultPayLabel.copyWith(
                color: ColorTokens.ink,
              ),
            ),
            const AppIcon('coin', size: _coin),
            if (MediaQuery.disableAnimationsOf(context))
              amount(payJenehat)
            else
              // From 0 the first time, then from the last value (the ×2).
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: payJenehat.toDouble()),
                duration: DesignExtras.payCountUp,
                builder: (context, value, _) => amount(value.round()),
              ),
            if (bonat case final bonat?)
              Container(
                key: bonatKey,
                padding: _chipPadding,
                decoration: BoxDecoration(
                  color: ColorTokens.primarySoft,
                  borderRadius: BorderRadius.circular(RadiusTokens.pill),
                ),
                child: Text(
                  l10n.resultBonatChip(numbers.integer(bonat)),
                  style: DesignExtras.resultRow
                      .weight(700)
                      .copyWith(color: ColorTokens.primary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
