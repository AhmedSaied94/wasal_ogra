// What went wrong, on the result (specs/013-m08-home-result, `Result`
// block 7, research R15): a summary of which stars it cost, opening to one
// line per mistake with the passenger's face, then the counts.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/avatars.dart';
import 'package:wassal/core/theme/components/containers.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/result/domain/summary.dart';
import 'package:wassal/features/trip/presentation/trip_text.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// [summary] as the card's first row says it.
String mistakesSummaryText(
  AppLocalizations l10n,
  NumberFormatter numbers,
  MistakesSummary summary,
) {
  final n = numbers.integer(summary.count);
  return switch (summary.family) {
    SummaryFamily.fights => l10n.resultSummaryFights(summary.count, n),
    SummaryFamily.mistakes => l10n.resultSummaryMistakes(summary.count, n),
    SummaryFamily.losses => l10n.resultSummaryLosses(summary.count, n),
  };
}

/// [line] as a sentence.
String mistakeText(
  AppLocalizations l10n,
  NumberFormatter numbers,
  MistakeLine line,
) => switch (line) {
  PassengerMistake(:final kind) => () {
    final who = l10n.lookLabel(line.labelKey);
    final size = line.size.name;
    final amount = numbers.piasters(line.amountPiasters);
    final feminine = '${line.feminine}';
    return switch (kind) {
      MistakeKind.over => l10n.mistakeOver(who, size, amount),
      MistakeKind.notOwed => l10n.mistakeNotOwed(who, size, amount, feminine),
      MistakeKind.unreturned => l10n.mistakeUnreturned(
        who,
        feminine,
        size,
        amount,
      ),
    };
  }(),
  CountLine(:final kind, :final count) => switch (kind) {
    CountKind.fights => l10n.mistakeFights(count, numbers.integer(count)),
    CountKind.missedStops => l10n.mistakeMissedStops(
      count,
      numbers.integer(count),
    ),
    CountKind.lostFares => l10n.mistakeLostFares(count, numbers.integer(count)),
  },
};

class MistakesCard extends ConsumerStatefulWidget {
  const MistakesCard({required this.summary, required this.lines, super.key});

  final MistakesSummary summary;
  final List<MistakeLine> lines;

  static const summaryKey = Key('MistakesCard.summary');
  static Key lineKey(int index) => ValueKey('MistakesCard.line.$index');

  @override
  ConsumerState<MistakesCard> createState() => _MistakesCardState();
}

class _MistakesCardState extends ConsumerState<MistakesCard> {
  /// `Result` draws it open.
  bool _open = true;

  /// `Result` boxes 33–37.
  static const double _summaryHeight = 44;
  static const double _chevron = 18;
  static const double _countIcon = 22;
  static const double _endGap = SpaceTokens.s4;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final summary = mistakesSummaryText(l10n, numbers, widget.summary);
    final radius = BorderRadius.circular(RadiusTokens.card);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Pressable(
            key: MistakesCard.summaryKey,
            onTap: () => setState(() => _open = !_open),
            borderRadius: radius,
            semanticLabel: _open
                ? l10n.resultA11yMistakesOpen(summary)
                : l10n.resultA11yMistakesClosed(summary),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _summaryHeight),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SpaceTokens.s14,
                ),
                child: Row(
                  spacing: SpaceTokens.s8,
                  children: [
                    Expanded(
                      child: Text(
                        summary,
                        style: DesignExtras.resultRow
                            .weight(700)
                            .copyWith(color: ColorTokens.ink),
                      ),
                    ),
                    AppIcon(
                      _open ? 'chevron_up' : 'chevron_down',
                      size: _chevron,
                      color: ColorTokens.inkMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_open)
            for (final (i, line) in widget.lines.indexed)
              Padding(
                key: MistakesCard.lineKey(i),
                padding: const EdgeInsets.fromLTRB(
                  SpaceTokens.s14,
                  0,
                  SpaceTokens.s14,
                  SpaceTokens.s10,
                ),
                child: Row(
                  spacing: SpaceTokens.s10,
                  children: [
                    switch (line) {
                      PassengerMistake(:final look) => PassengerAvatar(
                        lookId: look.id,
                        person: look.rive,
                        size: PassengerAvatarSize.mistake,
                        mistake: true,
                      ),
                      CountLine(:final kind) => Container(
                        width: PassengerAvatarSize.mistake.side,
                        height: PassengerAvatarSize.mistake.side,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: ColorTokens.dangerSoft,
                          shape: BoxShape.circle,
                        ),
                        child: AppIcon(switch (kind) {
                          CountKind.fights => 'warning',
                          CountKind.missedStops => 'route_bold',
                          CountKind.lostFares => 'coin',
                        }, size: _countIcon),
                      ),
                    },
                    Expanded(
                      child: Text(
                        mistakeText(l10n, numbers, line),
                        style: DesignExtras.resultRow.copyWith(
                          color: ColorTokens.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          // The board's open card is 96 high with one line: 14 under it.
          if (_open) const SizedBox(height: _endGap),
        ],
      ),
    );
  }
}
