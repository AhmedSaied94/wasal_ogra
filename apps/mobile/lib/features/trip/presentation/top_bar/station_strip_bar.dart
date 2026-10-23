// The station strip (HANDOFF §3.4, `C-Trip` boxes 7–23, research R9): a
// white card with the track filling from the depot at the start end, each
// stop's dot at `at_ms / the last at_ms` in its colour with its letter, the
// vehicle marker at the trip clock's share, and under them the names and
// fares. The next stop wears a `danger` ring and its countdown chip, which
// pulses under 8 s (steady under reduced motion); passed stops fade to 35%;
// a raised fare shows the old one struck through beside the new.
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/trip_colors.dart';
import 'package:wassal/features/trip/presentation/trip_motion.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/features/trip/presentation/trip_text.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// The bus icon's rounded nose and window corners, in its view box.
const _iconNose = 2.0;
const _iconWindow = 1.0;

/// The card's height, and the track row's and the labels row's.
const stripHeight = 64.0;
const _trackRow = 26.0;
const _labelsRow = 28.0;

/// Inside the card's 14 pt padding, the track keeps 14 more on each side.
const _inset = SpaceTokens.s14;

const _dot = 24.0;
const _depot = 14.0;
const _track = 6.0;
const _trackTop = 10.0;
const Size _vehicle = Size(28, 26);

/// How much the countdown chip grows on its beat.
const _countdownPulse = 0.12;

/// A label's room around its stop.
const _labelWidth = 132.0;

class StationStrip extends StatelessWidget {
  const StationStrip({super.key});

  static const trackKey = ValueKey('strip-track');
  static const vehicleKey = ValueKey('strip-vehicle');
  static const countdownKey = ValueKey('strip-countdown');
  static ValueKey<String> dotKey(int slot) => ValueKey('strip-dot-$slot');
  static ValueKey<String> raisedKey(int slot) => ValueKey('strip-raised-$slot');

  @override
  Widget build(BuildContext context) => SizedBox(
    height: stripHeight,
    child: DecoratedBox(
      decoration: const BoxDecoration(
        color: ColorTokens.paper,
        borderRadius: BorderRadius.all(Radius.circular(RadiusTokens.l)),
        boxShadow: [LipTokens.cardSmall],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          SpaceTokens.s14 + _inset,
          5,
          SpaceTokens.s14 + _inset,
          0,
        ),
        child: TripSelector<(StationStripView?, int)>(
          select: (model) => (model.view?.strip, model.view?.tMs ?? 0),
          builder: (context, selected) {
            final (strip, tMs) = selected;
            if (strip == null || strip.chips.isEmpty) {
              return const SizedBox.shrink();
            }
            return LayoutBuilder(
              builder: (context, constraints) =>
                  _Strip(strip: strip, tMs: tMs, width: constraints.maxWidth),
            );
          },
        ),
      ),
    ),
  );
}

class _Strip extends ConsumerWidget {
  const _Strip({required this.strip, required this.tMs, required this.width});

  final StationStripView strip;
  final int tMs;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final numbers = ref.watch(numberFormatterProvider);
    final l10n = AppLocalizations.of(context);
    final last = strip.chips.last.atMs;
    double share(int atMs) => last <= 0 ? 0 : (atMs / last).clamp(0.0, 1.0);
    final vehicle = share(tMs) * width;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _trackRow,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Positioned(
                left: 0,
                right: 0,
                top: _trackTop,
                height: _track,
                child: DecoratedBox(
                  key: StationStrip.trackKey,
                  decoration: BoxDecoration(
                    color: ColorTokens.track,
                    borderRadius: BorderRadius.all(
                      Radius.circular(RadiusTokens.pill),
                    ),
                  ),
                ),
              ),
              PositionedDirectional(
                start: 0,
                top: _trackTop,
                height: _track,
                width: vehicle,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    color: ColorTokens.primary,
                    borderRadius: BorderRadius.all(
                      Radius.circular(RadiusTokens.pill),
                    ),
                  ),
                ),
              ),
              // The depot, centred on the start end.
              const PositionedDirectional(
                start: -_depot / 2,
                top: _trackTop + _track / 2 - _depot / 2,
                width: _depot,
                height: _depot,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: ColorTokens.groundLip,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              for (final chip in strip.chips)
                PositionedDirectional(
                  start: share(chip.atMs) * width - _dot / 2,
                  top: 1,
                  width: _dot,
                  height: _dot,
                  child: _Dot(
                    chip: chip,
                    label: _chipLabel(l10n, numbers, chip),
                  ),
                ),
              PositionedDirectional(
                start: vehicle - _vehicle.width / 2,
                top: 0,
                width: _vehicle.width,
                height: _vehicle.height,
                child: const _VehicleMarker(key: StationStrip.vehicleKey),
              ),
            ],
          ),
        ),
        const SizedBox(height: SpaceTokens.s2),
        SizedBox(
          height: _labelsRow,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomMultiChildLayout(
                  delegate: _LabelsLayout(
                    centers: [
                      0,
                      for (final chip in strip.chips) share(chip.atMs) * width,
                    ],
                    textDirection: Directionality.of(context),
                  ),
                  children: [
                    LayoutId(
                      id: 0,
                      child: ExcludeSemantics(
                        child: Text(
                          l10n.destHome,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.visible,
                          style: TypeTokens.label.copyWith(
                            color: ColorTokens.inkMuted,
                          ),
                        ),
                      ),
                    ),
                    for (final (i, chip) in strip.chips.indexed)
                      LayoutId(
                        id: i + 1,
                        child: ExcludeSemantics(
                          child: _Label(
                            chip: chip,
                            countdownMs: chip.next ? strip.countdownMs : null,
                            numbers: numbers,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (strip.countdownMs case final countdown?)
                if (strip.chips.any((c) => c.next))
                  // The countdown speaks for itself, live while warned.
                  Semantics(
                    label: l10n.tripStripCountdown(
                      numbers.countdown(Duration(milliseconds: countdown)),
                    ),
                    liveRegion: strip.warning,
                    child: const SizedBox.shrink(),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  String _chipLabel(
    AppLocalizations l10n,
    NumberFormatter numbers,
    StationChip chip,
  ) {
    final letter = l10n.stationLetter(chip.slot);
    final fare = numbers.piasters(chip.farePiasters);
    if (chip.reached) return l10n.tripStripReached(letter);
    final station = switch (chip.name) {
      final name? => l10n.tripStripStation(letter, name, fare),
      null => l10n.tripStripStationNoName(letter, fare),
    };
    return chip.studentIcon
        ? l10n.pairLabel(station, l10n.tripStripStudent)
        : station;
  }
}

/// A stop's dot: its colour and letter; the next one ringed in `danger`.
class _Dot extends StatelessWidget {
  const _Dot({required this.chip, required this.label});

  final StationChip chip;
  final String label;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = TripColors.station(chip.slot);
    final dot = KeyedSubtree(
      key: StationStrip.dotKey(chip.slot),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.bg,
          shape: BoxShape.circle,
          border: chip.next
              ? Border.all(
                  color: ColorTokens.paper,
                  width: 2,
                  strokeAlign: BorderSide.strokeAlignInside,
                )
              : null,
          boxShadow: chip.next ? [RingTokens.hot.spread] : null,
        ),
        child: Center(
          child: Text(
            l10n.stationLetter(chip.slot),
            style: TypeTokens.label
                .weight(700)
                .copyWith(
                  color: colors.letter,
                  fontSize: DesignExtras.stripLetterSize,
                  height: 1,
                ),
          ),
        ),
      ),
    );
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: chip.reached ? Opacity(opacity: 0.35, child: dot) : dot,
    );
  }
}

/// A stop's name over its fare (and the next one's countdown chip), or
/// «عدّت» once passed.
class _Label extends StatelessWidget {
  const _Label({
    required this.chip,
    required this.countdownMs,
    required this.numbers,
  });

  final StationChip chip;
  final int? countdownMs;
  final NumberFormatter numbers;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Two lines in the 28 pt row; scaled to 1.15 they reach into the card's
    // bottom padding.
    final base = TypeTokens.label.copyWith(color: ColorTokens.ink, height: 1.1);
    final fare = base.weight(500);
    Text line(String text, TextStyle style, {Key? key}) => Text(
      text,
      key: key,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
      style: style,
    );
    final raised = chip.farePiasters != chip.basePiasters;
    final countdown = countdownMs;
    final second = chip.reached
        ? line(l10n.tripStationPassed, fare)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (raised) ...[
                line(
                  l10n.tripStripFare(numbers.piasters(chip.basePiasters)),
                  fare.copyWith(decoration: TextDecoration.lineThrough),
                ),
                const SizedBox(width: SpaceTokens.s4),
                _Pill(
                  key: StationStrip.raisedKey(chip.slot),
                  color: ColorTokens.dangerSoft,
                  child: line(
                    l10n.tripStripFare(numbers.piasters(chip.farePiasters)),
                    base.weight(700),
                  ),
                ),
              ] else
                line(
                  l10n.tripStripFare(numbers.piasters(chip.farePiasters)),
                  fare,
                ),
              if (countdown != null) ...[
                const SizedBox(width: SpaceTokens.s4),
                _Countdown(ms: countdown, numbers: numbers),
              ],
            ],
          );
    final label = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (chip.name case final name?) ...[
          line(name, base.weight(700)),
          // Room for the countdown's beat.
          const SizedBox(height: SpaceTokens.s2),
        ],
        second,
      ],
    );
    return chip.reached ? Opacity(opacity: 0.35, child: label) : label;
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.color, required this.child, super.key});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      borderRadius: const BorderRadius.all(Radius.circular(RadiusTokens.pill)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.s6),
      child: child,
    ),
  );
}

/// The next stop's seconds, `danger`; it pulses on the trip clock under
/// [TripMotion.countdownPulseBelow].
class _Countdown extends StatelessWidget {
  const _Countdown({required this.ms, required this.numbers});

  final int ms;
  final NumberFormatter numbers;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final chip = _Pill(
      key: StationStrip.countdownKey,
      color: ColorTokens.danger,
      child: Text(
        l10n.tripSeconds(numbers.integer((ms / 1000).ceil())),
        maxLines: 1,
        softWrap: false,
        style: TypeTokens.label.weight(700).copyWith(color: ColorTokens.ink),
      ),
    );
    if (ms >= TripMotion.countdownPulseBelow.inMilliseconds) return chip;
    return TripPulse(amplitude: _countdownPulse, child: chip);
  }
}

/// The vehicle on the strip: a `sun` tile with a small microbus.
class _VehicleMarker extends StatelessWidget {
  const _VehicleMarker({super.key});

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      color: ColorTokens.sun,
      borderRadius: BorderRadius.all(Radius.circular(RadiusTokens.s)),
      boxShadow: [LipTokens.sunS],
    ),
    child: Center(
      child: CustomPaint(size: Size(18, 13), painter: _MicrobusGlyph()),
    ),
  );
}

/// `C-Trip` box 15: the microbus glyph, drawn from its 32×24 view box.
class _MicrobusGlyph extends CustomPainter {
  const _MicrobusGlyph();

  @override
  void paint(Canvas canvas, Size size) {
    const box = Size(32, 24);
    final scale = size.height / box.height < size.width / box.width
        ? size.height / box.height
        : size.width / box.width;
    canvas
      ..translate(
        (size.width - box.width * scale) / 2,
        (size.height - box.height * scale) / 2,
      )
      ..scale(scale);
    final body = Path()
      ..moveTo(3, 17)
      ..lineTo(3, 9)
      ..quadraticBezierTo(4, 5, 8, 4)
      ..lineTo(27, 4)
      ..arcToPoint(
        const Offset(29, 6),
        radius: const Radius.circular(_iconNose),
      )
      ..lineTo(29, 17)
      ..close();
    final window = Paint()..color = ColorTokens.paper;
    final wheel = Paint()..color = ColorTokens.ink;
    canvas
      ..drawPath(body, Paint()..color = ColorTokens.primary)
      ..drawRRect(
        RRect.fromLTRBR(8, 6.5, 14, 11, const Radius.circular(_iconWindow)),
        window,
      )
      ..drawRRect(
        RRect.fromLTRBR(17, 6.5, 23, 11, const Radius.circular(_iconWindow)),
        window,
      )
      ..drawCircle(const Offset(9, 18), 3, wheel)
      ..drawCircle(const Offset(24, 18), 3, wheel);
  }

  @override
  bool shouldRepaint(_MicrobusGlyph oldDelegate) => false;
}

/// The labels under their stops, the depot's first: each centred on its
/// stop, pushed apart where two would touch, and kept within the card.
class _LabelsLayout extends MultiChildLayoutDelegate {
  _LabelsLayout({required this.centers, required this.textDirection});

  /// Each label's stop, from the start end.
  final List<double> centers;
  final TextDirection textDirection;

  /// Between two labels.
  static const _gap = SpaceTokens.s4;

  @override
  void performLayout(Size size) {
    final widths = [
      for (var i = 0; i < centers.length; i++)
        layoutChild(i, const BoxConstraints(maxWidth: _labelWidth)).width,
    ];
    // The card's padding is the labels' room past the track's ends.
    const reach = SpaceTokens.s14 + _inset - _gap;
    final order = [for (var i = 0; i < centers.length; i++) i]
      ..sort((a, b) => centers[a].compareTo(centers[b]));
    final starts = List.filled(centers.length, 0.0);
    var end = -reach - _gap;
    for (final i in order) {
      starts[i] = max(centers[i] - widths[i] / 2, end + _gap);
      end = starts[i] + widths[i];
    }
    var limit = size.width + reach + _gap;
    for (final i in order.reversed) {
      starts[i] = min(starts[i], limit - _gap - widths[i]);
      limit = starts[i];
    }
    for (var i = 0; i < centers.length; i++) {
      final dx = textDirection == TextDirection.rtl
          ? size.width - starts[i] - widths[i]
          : starts[i];
      positionChild(i, Offset(dx, 0));
    }
  }

  @override
  bool shouldRelayout(_LabelsLayout old) =>
      old.textDirection != textDirection || !listEquals(old.centers, centers);
}
