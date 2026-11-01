// The apartment card on the result (specs/013-m08-home-result, `Result`
// block 11, FR-043, research R19): the target Home's savings card shows,
// after the pay. Its bar fills from the balance before the trip to the
// balance now, after the pay has counted up, with this trip's gain in
// `sun`; then what is still missing, or «تقدر تشتري …!». Opens the
// apartment.
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/routing/nav_guard.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/home/domain/savings_target.dart';
import 'package:wassal/features/home/presentation/savings_card.dart';
import 'package:wassal/features/result/application/result_model.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class ApartmentCard extends ConsumerWidget {
  const ApartmentCard({required this.progress, super.key});

  final ApartmentProgress progress;

  static const barKey = Key('ApartmentCard.bar');
  static const fillKey = Key('ApartmentCard.fill');
  static const gainKey = Key('ApartmentCard.gain');
  static const noteKey = Key('ApartmentCard.note');

  /// `Result` boxes 47–55.
  static const double _minHeight = 80;
  static const double _tile = 52;
  static const double _tileIcon = 32;
  static const double _tileRadius = 18;
  static const double _rowGap = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final target = progress.target;
    final (:title, :amount, :figures, :goal, :label) = switch (target) {
      ApartmentPieceTarget(:final itemName, :final progress) => (
        title: itemName,
        amount: progress,
        figures: progressFigures(l10n, numbers, progress),
        goal: false,
        label: l10n.resultA11yApt(
          itemName,
          numbers.integer(progress.have),
          numbers.integer(progress.of),
        ),
      ),
      ChapterGoalTarget(:final progress) => (
        title: goalTitle(l10n, target),
        amount: progress is Amount ? progress : null,
        figures: progressFigures(l10n, numbers, progress),
        goal: true,
        label: switch (progress) {
          Amount(:final have, of: final price) => l10n.resultA11yApt(
            goalTitle(l10n, target),
            numbers.integer(have),
            numbers.integer(price),
          ),
          Count() => goalTitle(l10n, target),
        },
      ),
      StoryEndTarget() || NoTarget() => (
        title: '',
        amount: null,
        figures: '',
        goal: false,
        label: '',
      ),
    };
    if (target is NoTarget || target is StoryEndTarget) {
      return const SizedBox.shrink();
    }
    final to = switch (target) {
      ChapterGoalTarget(:final progress) => progress.fraction,
      _ => amount?.fraction ?? 0,
    };
    final from = switch ((amount, progress.fromJenehat)) {
      (final Amount amount, final int before) when amount.of > 0 => math.min(
        (before / amount.of).clamp(0, 1).toDouble(),
        to,
      ),
      _ => to,
    };
    final note = switch (amount) {
      _? when target.affordable => switch (target) {
        ApartmentPieceTarget(:final itemName) => l10n.resultAptAffordable(
          itemName,
        ),
        _ => l10n.resultAptGoalAffordable,
      },
      final amount? => l10n.resultAptRemaining(
        numbers.integer(amount.of - amount.have),
      ),
      null => null,
    };
    final radius = BorderRadius.circular(RadiusTokens.card);
    return Pressable(
      onTap: () => NavGuard.go(context, '/apartment'),
      lip: LipTokens.card,
      borderRadius: radius,
      semanticLabel: label,
      child: Container(
        constraints: const BoxConstraints(minHeight: _minHeight),
        padding: const EdgeInsets.symmetric(
          horizontal: SpaceTokens.s14,
          vertical: SpaceTokens.s10,
        ),
        decoration: BoxDecoration(
          color: ColorTokens.paper,
          borderRadius: radius,
        ),
        child: Row(
          spacing: SpaceTokens.s12,
          children: [
            Container(
              width: _tile,
              height: _tile,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: goal ? ColorTokens.primarySoft : ColorTokens.sunSoft,
                borderRadius: BorderRadius.circular(_tileRadius),
              ),
              child: switch (target) {
                final ChapterGoalTarget goal => goalGlyph(
                  goal,
                  size: _tileIcon,
                ),
                _ => const AppIcon('ring_gem', size: _tileIcon),
              },
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: _rowGap,
                children: [
                  Row(
                    spacing: SpaceTokens.s8,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: DesignExtras.resultRow
                              .weight(600)
                              .copyWith(color: ColorTokens.ink),
                        ),
                      ),
                      Text(
                        figures,
                        style: DesignExtras.resultRow
                            .weight(700)
                            .copyWith(color: ColorTokens.ink),
                      ),
                    ],
                  ),
                  _GainBar(from: from, to: to),
                  if (note != null)
                    Text(
                      note,
                      key: noteKey,
                      style: TypeTokens.label
                          .weight(500)
                          .copyWith(
                            color: target.affordable
                                ? ColorTokens.primary
                                : ColorTokens.inkMuted,
                          ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A gold bar filling from [from] to [to] after the pay's count-up, with
/// the part between them in `sun`: this trip's gain.
class _GainBar extends StatefulWidget {
  const _GainBar({required this.from, required this.to});

  final double from;
  final double to;

  @override
  State<_GainBar> createState() => _GainBarState();
}

class _GainBarState extends State<_GainBar>
    with SingleTickerProviderStateMixin {
  /// `Result` box 52.
  static const double _height = 12;

  late final AnimationController _fill = AnimationController(
    vsync: this,
    duration: DesignExtras.payCountUp + DesignExtras.aptBarFill,
  );

  late final Animation<double> _progress = CurvedAnimation(
    parent: _fill,
    curve: Interval(
      DesignExtras.payCountUp.inMilliseconds / _fill.duration!.inMilliseconds,
      1,
      curve: DesignExtras.aptBarFillCurve,
    ),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _fill.value = 1;
    } else if (_fill.value == 0 && !_fill.isAnimating) {
      _fill.forward();
    }
  }

  @override
  void dispose() {
    _fill.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    key: ApartmentCard.barKey,
    height: _height,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final pill = BorderRadius.circular(RadiusTokens.pill);
        return ClipRRect(
          borderRadius: pill,
          child: AnimatedBuilder(
            animation: _progress,
            builder: (context, _) {
              final value =
                  widget.from + (widget.to - widget.from) * _progress.value;
              return Stack(
                children: [
                  const Positioned.fill(
                    child: ColoredBox(color: ColorTokens.track),
                  ),
                  PositionedDirectional(
                    key: ApartmentCard.fillKey,
                    start: 0,
                    top: 0,
                    bottom: 0,
                    width: width * value,
                    child: const ColoredBox(color: ColorTokens.gold),
                  ),
                  PositionedDirectional(
                    key: ApartmentCard.gainKey,
                    start: width * widget.from,
                    top: 0,
                    bottom: 0,
                    width: width * (value - widget.from),
                    child: const ColoredBox(color: ColorTokens.sun),
                  ),
                ],
              );
            },
          ),
        );
      },
    ),
  );
}
