// The card's prices block (specs/013-m08-home-result, `PreTrip` boxes
// 13–28, FR-027, FR-028): one cell per stop, right to left in drop-off
// order, each with its station's colour and letter, its name and fare;
// then the fare rules the trip applies. Each tag sits beside its name while
// every word of every name fits there; otherwise the row's cells stack
// their tags over their names, so a name wraps between its words rather
// than inside one (the edge case "a trip with four stops").
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/station_tag.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/pre_trip/domain/briefing.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class StopPrices extends ConsumerWidget {
  const StopPrices({required this.stops, required this.ruleLines, super.key});

  final List<StopPrice> stops;
  final List<RuleLine> ruleLines;

  static Key cellKey(int slot) => ValueKey('StopPrices.cell.$slot');

  /// From a stacked cell's tag to its name.
  static const double stackGap = SpaceTokens.s4;

  static const double _gap = SpaceTokens.s8;
  static const double _ruleIcon = 20;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        SpaceTokens.s12,
        SpaceTokens.s12,
        SpaceTokens.s12,
        SpaceTokens.s10,
      ),
      decoration: BoxDecoration(
        color: ColorTokens.ground,
        borderRadius: BorderRadius.circular(RadiusTokens.l),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: SpaceTokens.s10,
        children: [
          Text(
            l10n.preTripPrices,
            style: DesignExtras.preTripLine.copyWith(
              color: ColorTokens.inkMuted,
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final width =
                  (constraints.maxWidth - _gap * (stops.length - 1)) /
                  stops.length;
              final beside = stops.every(
                (stop) => _Cell.fitsBeside(
                  context,
                  name: stop.stationName,
                  fare: l10n.preTripFare(numbers.piasters(stop.farePiasters)),
                  width: width,
                ),
              );
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: _gap,
                  children: [
                    for (final stop in stops)
                      Expanded(
                        child: _Cell(
                          stop: stop,
                          numbers: numbers,
                          beside: beside,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          for (final line in ruleLines)
            Row(
              spacing: SpaceTokens.s8,
              children: [
                const AppIcon('student_card', size: _ruleIcon),
                Expanded(
                  child: Text(
                    _ruleText(l10n, numbers, line),
                    style: TypeTokens.caption.copyWith(color: ColorTokens.ink),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static String _ruleText(
    AppLocalizations l10n,
    NumberFormatter numbers,
    RuleLine line,
  ) => switch (line) {
    StudentLine(percent: 50) => l10n.preTripStudentHalf,
    StudentLine(:final percent) => l10n.preTripStudentPercent(
      numbers.integer(percent),
    ),
    BagLine(:final farePiasters) => l10n.preTripBag(
      numbers.piasters(farePiasters),
    ),
    ChildFreeLine(:final age) => l10n.preTripChildFree(numbers.integer(age)),
  };
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.stop,
    required this.numbers,
    required this.beside,
  });

  final StopPrice stop;
  final NumberFormatter numbers;

  /// The tag beside the name, as `PreTrip` draws it, or over it.
  final bool beside;

  static const double _tag = 30;
  static const double _pad = SpaceTokens.s8;

  /// Whether every word of [name], and [fare], fits beside the tag in a
  /// cell [width] wide, at the phone's text size.
  static bool fitsBeside(
    BuildContext context, {
    required String name,
    required String fare,
    required double width,
  }) {
    final room = width - _pad - _tag - _pad - _pad;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    bool fits(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        textScaler: scaler,
      )..layout();
      final fitting = painter.width <= room;
      painter.dispose();
      return fitting;
    }

    return name
            .split(RegExp(r'\s+'))
            .every((word) => fits(word, DesignExtras.preTripStation)) &&
        fits(fare, DesignExtras.preTripFare);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fare = numbers.piasters(stop.farePiasters);
    final tag = StationTag(slot: stop.slot - 1, size: _tag, bordered: false);
    final name = Text(
      stop.stationName,
      style: DesignExtras.preTripStation.copyWith(color: ColorTokens.ink),
    );
    final fareText = Text(
      l10n.preTripFare(fare),
      style: DesignExtras.preTripFare.copyWith(color: ColorTokens.ink),
    );
    return Semantics(
      key: StopPrices.cellKey(stop.slot),
      container: true,
      label: l10n.preTripA11yPrice(stop.stationName, fare),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(_pad),
        decoration: BoxDecoration(
          color: ColorTokens.paper,
          borderRadius: BorderRadius.circular(RadiusTokens.m),
        ),
        child: beside
            ? Row(
                spacing: _pad,
                children: [
                  tag,
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [name, fareText],
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  tag,
                  const SizedBox(height: StopPrices.stackGap),
                  name,
                  fareText,
                ],
              ),
      ),
    );
  }
}
