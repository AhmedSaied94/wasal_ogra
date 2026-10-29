// A line on the map (specs/014-m09-lines-vehicles, contracts/lines.md
// "Layout", HANDOFF `Lines` blocks 3a–3c): current with «كمّل», done with
// its stars, or locked with what opens it. Long text wraps and the card
// grows (§9.1 #10).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/containers.dart';
import 'package:wassal/core/theme/components/pills.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/lines/domain/line_standing.dart';
import 'package:wassal/features/lines/presentation/fare_chip.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';
import 'package:content_models/content_models.dart';

class LineCard extends ConsumerWidget {
  const LineCard({
    required this.standing,
    required this.onOpen,
    this.reason,
    this.onContinue,
    super.key,
  });

  final LineStanding standing;

  /// The card's tap: the details, or what opens a locked line.
  final VoidCallback onOpen;

  /// A locked card's «محتاج …» or «بعد …», as the pack names it.
  final String? reason;

  /// «كمّل»: starts the next trip (Clarifications Q3).
  final VoidCallback? onContinue;

  static Key keyOf(LineId line) => Key('LineCard.${line.name}');
  static Key continueKeyOf(LineId line) => Key('LineCard.${line.name}.go');

  static const double minHeight = 92;

  /// «كمّل» as drawn (box 51).
  static const Size continueSize = Size(63, 44);
  static const double _star = 16;
  static const double _side = SpaceTokens.s14;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final s = standing;
    final earned = numbers.integer(s.starsEarned);
    final max = numbers.integer(s.starsMax);
    // One isolate around the ratio keeps «٢٧/٩٠» in its order.
    final stars = numbers.ratio(s.starsEarned, s.starsMax);
    final radius = BorderRadius.circular(RadiusTokens.card);

    switch (s.state) {
      case LineLocked():
        final reason = this.reason;
        final text = reason == null
            ? s.whatsNew
            : l10n.linesReasonWithNew(reason, s.whatsNew);
        return Pressable(
          key: keyOf(s.line),
          onTap: onOpen,
          borderRadius: radius,
          semanticLabel: l10n.linesCardA11y(
            s.name,
            l10n.linesStandingLocked,
            reason ?? s.whatsNew,
          ),
          child: AppCard(
            locked: true,
            padding: const EdgeInsets.symmetric(horizontal: _side),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: minHeight),
              child: Row(
                spacing: SpaceTokens.s12,
                children: [
                  Expanded(
                    child: _Lines(
                      title: s.name,
                      children: [
                        Text(
                          text,
                          style: DesignExtras.linesCardText.copyWith(
                            color: ColorTokens.ink2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FareChip(farePiasters: s.farePiasters, plain: true),
                ],
              ),
            ),
          ),
        );
      case LineDone():
        return _Tappable(
          key: keyOf(s.line),
          onTap: onOpen,
          label: l10n.linesCardA11y(
            s.name,
            l10n.linesStandingDone,
            l10n.linesDetailStars(earned, max),
          ),
          child: Row(
            spacing: SpaceTokens.s12,
            children: [
              Expanded(
                child: _Lines(
                  title: s.name,
                  chip: StatusChip.done(label: l10n.linesStandingDone),
                  children: [
                    _StarLine(
                      text: s.allThree
                          ? l10n.linesStars(stars)
                          : l10n.linesStarsDone(stars),
                    ),
                  ],
                ),
              ),
              FareChip(farePiasters: s.farePiasters, plain: true),
            ],
          ),
        );
      case LineCurrent(:final next):
        final n = numbers.integer(next.number);
        final card = _Tappable(
          key: keyOf(s.line),
          onTap: onOpen,
          selected: true,
          label: l10n.linesCardA11y(
            s.name,
            l10n.linesStandingCurrent,
            l10n.linesDetailCurrent(
              earned,
              max,
              n,
              numbers.integer(next.total),
            ),
          ),
          child: Row(
            spacing: SpaceTokens.s10,
            children: [
              Expanded(
                child: _Lines(
                  title: s.name,
                  chip: FareChip(farePiasters: s.farePiasters),
                  children: [
                    Text(
                      s.whatsNew,
                      style: DesignExtras.linesCardText.copyWith(
                        color: ColorTokens.ink2,
                      ),
                    ),
                    _StarLine(
                      text: l10n.linesStarsCurrent(
                        stars,
                        n,
                        numbers.integer(next.total),
                      ),
                    ),
                  ],
                ),
              ),
              // «كمّل»'s place: it is its own button, over the card.
              SizedBox(width: continueSize.width),
            ],
          ),
        );
        // «كمّل» is a sibling over the card, so a screen reader finds it
        // after the card (FR-049) and its tap is its own.
        return Stack(
          alignment: AlignmentDirectional.centerEnd,
          children: [
            card,
            PositionedDirectional(
              end: _side,
              child: Pressable(
                key: continueKeyOf(s.line),
                onTap: onContinue,
                lip: LipTokens.primaryS,
                borderRadius: BorderRadius.circular(RadiusTokens.m),
                semanticLabel: l10n.linesContinueA11y(n),
                child: Container(
                  constraints: BoxConstraints(
                    minWidth: continueSize.width,
                    minHeight: continueSize.height,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: SpaceTokens.s16,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: ColorTokens.primary,
                    borderRadius: BorderRadius.circular(RadiusTokens.m),
                  ),
                  child: Text(
                    l10n.linesContinue,
                    style: DesignExtras.linesContinue.copyWith(
                      color: ColorTokens.paper,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
    }
  }
}

/// A white card with the card lip, pressed as one; the current one with
/// the 3 pt `primary` ring.
class _Tappable extends StatelessWidget {
  const _Tappable({
    required this.onTap,
    required this.label,
    required this.child,
    this.selected = false,
    super.key,
  });

  final VoidCallback onTap;
  final String label;
  final Widget child;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(RadiusTokens.card);
    return Pressable(
      onTap: onTap,
      lip: LipTokens.card,
      borderRadius: radius,
      semanticLabel: label,
      child: Container(
        constraints: const BoxConstraints(minHeight: LineCard.minHeight),
        padding: const EdgeInsets.symmetric(horizontal: LineCard._side),
        decoration: BoxDecoration(
          color: ColorTokens.paper,
          borderRadius: radius,
          border: selected ? RingTokens.selected.border : null,
        ),
        child: child,
      ),
    );
  }
}

/// The title with its chip, over the card's lines.
class _Lines extends StatelessWidget {
  const _Lines({required this.title, required this.children, this.chip});

  final String title;
  final Widget? chip;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: SpaceTokens.s12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: SpaceTokens.s4,
      children: [
        Wrap(
          spacing: SpaceTokens.s8,
          runSpacing: SpaceTokens.s4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(title, style: DesignExtras.linesCardTitle),
            ?chip,
          ],
        ),
        ...children,
      ],
    ),
  );
}

class _StarLine extends StatelessWidget {
  const _StarLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    spacing: SpaceTokens.s4,
    children: [
      const AppIcon('star', size: LineCard._star, color: ColorTokens.gold),
      Flexible(
        child: Text(
          text,
          style: DesignExtras.linesCardStars.copyWith(color: ColorTokens.ink),
        ),
      ),
    ],
  );
}
