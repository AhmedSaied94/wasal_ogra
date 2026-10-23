// The station strip (ux-spec «شريط المحطات», research R16): the stand, then
// each station in its color with its letter, name and price (a raised price
// pops in), and the vehicle moving along it. The next station has an orange
// countdown that grows and pulses while warned (steady under reduced motion).
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/tokens/space.dart';
import 'package:wassal/core/theme/tokens/typography.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/trip_motion.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/features/trip/presentation/trip_text.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

const _dot = 22.0;
const _trackY = _dot / 2 + 2;

class StationStripBar extends StatelessWidget {
  const StationStripBar({super.key});

  @override
  Widget build(BuildContext context) {
    return TripSelector<StationStripView?>(
      select: (model) => model.view?.strip,
      builder: (context, strip) {
        if (strip == null || strip.chips.isEmpty) {
          return const SizedBox.shrink();
        }
        return LayoutBuilder(
          builder: (context, constraints) =>
              _Strip(strip: strip, width: constraints.maxWidth),
        );
      },
    );
  }
}

class _Strip extends ConsumerWidget {
  const _Strip({required this.strip, required this.width});

  final StationStripView strip;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final numbers = ref.watch(numberFormatterProvider);
    final l10n = AppLocalizations.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final n = strip.chips.length;
    // From the stand (start side) to the last station's center.
    const margin = SpaceTokens.m;
    const start = margin + _dot / 2;
    final span = width - 2 * margin - _dot / 2;
    final cell = span / n;
    double along(double distance) =>
        rtl ? width - start - distance : start + distance;
    double stationX(int i) => along(_dot / 2 + (i + 0.5) * cell);
    final k = strip.vehiclePermille * n / 1000;
    final vehicleX = along(
      k <= 1 ? k * (_dot / 2 + 0.5 * cell) : _dot / 2 + (k - 0.5) * cell,
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: margin,
          right: margin,
          top: _trackY - 1.5,
          height: 3,
          child: ColoredBox(color: tokens.hibr),
        ),
        // The stand.
        Positioned(
          left: along(0) - 6,
          top: _trackY - 6,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: tokens.hibr,
              shape: BoxShape.circle,
            ),
          ),
        ),
        for (final (i, chip) in strip.chips.indexed)
          Positioned(
            left: stationX(i) - cell / 2,
            width: cell,
            top: 0,
            child: _StationChip(
              chip: chip,
              label: _chipLabel(
                l10n,
                numbers.piasters(chip.farePiasters),
                chip,
              ),
              fare: numbers.piasters(chip.farePiasters),
            ),
          ),
        Positioned(
          left: vehicleX - 11,
          top: _trackY - 11,
          child: ExcludeSemantics(
            child: Icon(
              Icons.airport_shuttle_rounded,
              size: 22,
              color: tokens.primary,
            ),
          ),
        ),
        if (strip.countdownMs case final countdown?)
          if (strip.chips.indexWhere((c) => c.next) case final next
              when next >= 0)
            Positioned(
              left: stationX(next) + (rtl ? -_dot / 2 - 40 : _dot / 2 + 4),
              top: 0,
              width: 36,
              height: _dot,
              child: _Countdown(
                ms: countdown,
                warning: strip.warning,
                seconds: numbers.integer((countdown / 1000).ceil()),
                semantics: l10n.tripStripCountdown(
                  numbers.countdown(Duration(milliseconds: countdown)),
                ),
              ),
            ),
      ],
    );
  }

  String _chipLabel(AppLocalizations l10n, String fare, StationChip chip) {
    final letter = l10n.stationLetter(chip.slot);
    if (chip.reached) return l10n.tripStripReached(letter);
    return switch (chip.name) {
      final name? => l10n.tripStripStation(letter, name, fare),
      null => l10n.tripStripStationNoName(letter, fare),
    };
  }
}

class _StationChip extends StatelessWidget {
  const _StationChip({
    required this.chip,
    required this.label,
    required this.fare,
  });

  final StationChip chip;
  final String label;
  final String fare;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final station = tokens.stations[chip.slot % tokens.stations.length];
    final caption = TypeTokens.caption.copyWith(
      color: tokens.hibr,
      height: 1.2,
    );
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: chip.reached ? 0.55 : 1,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: _dot,
              height: _dot,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: station.fill,
                shape: BoxShape.circle,
                border: Border.all(color: tokens.hibr, width: 2),
              ),
              child: Text(
                l10n.stationLetter(chip.slot),
                textScaler: TextScaler.noScaling,
                style: caption.copyWith(
                  color: station.letter,
                  fontWeight: FontWeight.w700,
                  fontVariations: const [FontVariation('wght', 700)],
                  height: 1,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (chip.name case final name?)
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: caption,
                    ),
                  ),
                const SizedBox(width: 3),
                // A new price pops in (a fare increase).
                AnimatedSwitcher(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : TripMotion.bannerIn,
                  transitionBuilder: (child, animation) =>
                      ScaleTransition(scale: animation, child: child),
                  child: Text(
                    fare,
                    key: ValueKey(fare),
                    maxLines: 1,
                    style: caption.copyWith(
                      fontWeight: FontWeight.w700,
                      fontVariations: const [FontVariation('wght', 700)],
                    ),
                  ),
                ),
                if (chip.studentIcon)
                  Semantics(
                    label: l10n.tripStripStudent,
                    child: Icon(
                      Icons.school_rounded,
                      size: 14,
                      color: tokens.hibr,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Countdown extends StatelessWidget {
  const _Countdown({
    required this.ms,
    required this.warning,
    required this.seconds,
    required this.semantics,
  });

  final int ms;
  final bool warning;
  final String seconds;
  final String semantics;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final reduced = MediaQuery.disableAnimationsOf(context);
    // Grows, and pulses on the trip clock, while warned.
    final pulse = warning && !reduced
        ? 1 +
              0.12 *
                  sin(ms / TripMotion.countdownPulse.inMilliseconds * pi * 2)
                      .abs()
        : 1.0;
    return Semantics(
      label: semantics,
      liveRegion: warning,
      excludeSemantics: true,
      child: Transform.scale(
        scale: (warning ? 1.15 : 1) * pulse,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: warning ? tokens.danger : tokens.waraq,
            border: Border.all(color: tokens.hibr, width: 2),
            borderRadius: BorderRadius.circular(_dot / 2),
          ),
          child: Center(
            child: Text(
              seconds,
              textScaler: TextScaler.noScaling,
              style: TypeTokens.label.copyWith(color: tokens.hibr, height: 1),
            ),
          ),
        ),
      ),
    );
  }
}
