// The result placeholder until M08 (research R21): the outcome, the stars
// with their three conditions, and the pay, from the TripResult the trip
// hands the route; opened another way, the economy's last result (outcome
// and pay only).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class ResultSummary extends ConsumerWidget {
  const ResultSummary({required this.result, super.key});

  /// The route's `extra`, when the trip passed it.
  final TripResult? result;

  static const starsKey = ValueKey('trip-result-stars');

  /// A star condition (`reached`, `no_fights`, `no_mistakes`), met or not.
  static Key conditionKey(String condition, {required bool met}) =>
      ValueKey('trip-result-$condition-${met ? 'met' : 'unmet'}');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final shown = result;
    final last = shown == null
        ? ref.watch(economyViewProvider).lastResult
        : null;
    final outcome = shown?.outcome ?? last?.outcome;
    final pay = shown?.earningsJenehat ?? last?.earningsJenehat;
    if (outcome == null) return const SizedBox.shrink();
    final body = TypeTokens.body.copyWith(color: ColorTokens.ink);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: SpaceTokens.s4,
      children: [
        Text(switch (outcome) {
          TripOutcome.finished => l10n.tripPlaytestFinished,
          TripOutcome.failed => l10n.tripPlaytestFailed,
          TripOutcome.abandoned => l10n.tripPlaytestAbandoned,
        }, style: TypeTokens.displayS.copyWith(color: ColorTokens.ink)),
        if (shown != null) ...[
          Text(
            l10n.tripPlaytestStars(numbers.integer(shown.stars)),
            key: starsKey,
            style: body,
          ),
          for (final (condition, label, met) in [
            ('reached', l10n.tripPlaytestReached, shown.starFlags.reached),
            ('no_fights', l10n.tripPlaytestNoFights, shown.starFlags.noFights),
            (
              'no_mistakes',
              l10n.tripPlaytestNoMistakes,
              shown.starFlags.noMistakes,
            ),
          ])
            _Condition(
              key: conditionKey(condition, met: met),
              label: label,
              met: met,
            ),
        ],
        if (pay != null)
          Text(l10n.tripPlaytestPay(numbers.integer(pay)), style: body),
      ],
    );
  }
}

class _Condition extends StatelessWidget {
  const _Condition({required this.label, required this.met, super.key});

  final String label;
  final bool met;

  static const _icon = 20.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: met ? l10n.tripPlaytestMet(label) : l10n.tripPlaytestNotMet(label),
      excludeSemantics: true,
      child: Row(
        spacing: SpaceTokens.s8,
        children: [
          AppIcon(
            met ? 'check' : 'close',
            size: _icon,
            color: met ? ColorTokens.successInk : ColorTokens.danger,
          ),
          Expanded(
            child: Text(
              label,
              style: TypeTokens.body.copyWith(color: ColorTokens.ink),
            ),
          ),
        ],
      ),
    );
  }
}
