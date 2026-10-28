// The result's stars (specs/013-m08-home-result, `Result` block 4, research
// R19): three columns right to left, the middle star larger, each over its
// condition with ✓ or ✕. `wassal.riv`'s `Stars` pops the earned ones one by
// one and each condition fades in with its star; the static stars draw
// under reduced motion, without the file, and in goldens.
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/art/rive_art.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/pills.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/result/domain/summary.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// [condition]'s words under its star.
String starConditionLabel(AppLocalizations l10n, StarCondition condition) =>
    switch (condition) {
      StarCondition.reached => l10n.resultStar1,
      StarCondition.noFights => l10n.resultStar2,
      StarCondition.noMistakes => l10n.resultStar3,
    };

class ResultStars extends StatefulWidget {
  const ResultStars({required this.stars, required this.rows, super.key});

  /// The stars earned: the first [stars], right to left.
  final int stars;

  /// Each star's condition and whether it was met.
  final List<StarRow> rows;

  static const groupKey = Key('ResultStars.group');
  static Key rowKey(StarCondition condition) =>
      ValueKey('ResultStars.${condition.name}');

  /// `Result` boxes 9, 12, 15: the side stars and the middle one.
  static const sizes = [58.0, 72.0, 58.0];

  /// `Result` box 8: the stars' part of the block, over the conditions.
  static const double starsHeight = 93;

  @override
  State<ResultStars> createState() => _ResultStarsState();
}

class _ResultStarsState extends State<ResultStars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _labels = AnimationController(
    vsync: this,
    duration: DesignExtras.starLabelStagger * (ResultStars.sizes.length + 1),
  );

  static const double _gap = SpaceTokens.s8;
  static const double _labelGap = SpaceTokens.s4;
  static const double _glyph = 14;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _labels.value = 1;
    } else if (!_labels.isAnimating && _labels.value == 0) {
      _labels.forward();
    }
  }

  @override
  void dispose() {
    _labels.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    final staticStars = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      spacing: _gap,
      children: [
        for (final (i, size) in ResultStars.sizes.indexed)
          Expanded(
            child: Center(
              child: Star(earned: i < widget.stars, size: size),
            ),
          ),
      ],
    );
    final steps = ResultStars.sizes.length + 1;
    return Semantics(
      key: ResultStars.groupKey,
      container: true,
      label: l10n.resultA11yStars(widget.stars),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: _labelGap,
        children: [
          SizedBox(
            height: ResultStars.starsHeight,
            child: ExcludeSemantics(
              child: still
                  ? staticStars
                  : RiveArtView(
                      artboard: 'Stars',
                      alignment: Alignment.bottomCenter,
                      bind: (model) => model.number('stars')?.value = widget
                          .stars
                          .toDouble(),
                      fallback: staticStars,
                    ),
            ),
          ),
          Row(
            spacing: _gap,
            children: [
              for (final (i, row) in widget.rows.indexed)
                Expanded(
                  child: FadeTransition(
                    opacity: CurvedAnimation(
                      parent: _labels,
                      curve: Interval(i / steps, (i + 1) / steps),
                    ),
                    child: _Label(
                      key: ResultStars.rowKey(row.condition),
                      row: row,
                      earned: i < widget.stars,
                      glyph: _glyph,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({
    required this.row,
    required this.earned,
    required this.glyph,
    super.key,
  });

  final StarRow row;

  /// The star above was earned.
  final bool earned;
  final double glyph;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final condition = starConditionLabel(l10n, row.condition);
    return Semantics(
      container: true,
      label: earned
          ? l10n.resultA11yStarEarned(condition)
          : l10n.resultA11yStarMissed(condition),
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: SpaceTokens.s4,
        children: [
          AppIcon(
            row.earned ? 'check' : 'close',
            size: glyph,
            color: row.earned ? ColorTokens.primary : ColorTokens.dangerInk,
          ),
          Flexible(
            child: Text(
              condition,
              textAlign: TextAlign.center,
              style: DesignExtras.resultStarLabel.copyWith(
                color: ColorTokens.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
