// المعلم's fuel lesson (specs/012-m07-onboarding/contracts/fuel-lesson.md):
// once, before the tutorial's last trip or on an empty tank in it, a card
// that explains fuel, a gauge that sweeps from the tank to full, and one
// button that takes the tutorial gift, marks the lesson and opens the trip.
// Built to the `FuelLesson` artboard. Nothing is written before the button,
// so a kill shows the lesson again.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/art/rive_art.dart';
import 'package:wassal/core/config/config_providers.dart';
import 'package:wassal/core/config/tunable.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/characters.dart';
import 'package:wassal/core/theme/components/system_bars.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/features/onboarding/presentation/onboarding_card.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class FuelLessonScreen extends ConsumerStatefulWidget {
  const FuelLessonScreen({required this.then, super.key});

  /// The trip that opens after the lesson, as the link gave it.
  final String? then;

  static const ctaKey = ValueKey('fuel-lesson-cta');
  static const gaugeKey = ValueKey('fuel-lesson-gauge');
  static const avatarKey = ValueKey('fuel-lesson-avatar');

  @override
  ConsumerState<FuelLessonScreen> createState() => _FuelLessonScreenState();
}

class _FuelLessonScreenState extends ConsumerState<FuelLessonScreen>
    with SingleTickerProviderStateMixin {
  late final _sweep = AnimationController(
    vsync: this,
    duration: DesignExtras.fuelLessonSweep,
  );
  late final Animation<double> _swept = CurvedAnimation(
    parent: _sweep,
    curve: DesignExtras.fuelLessonSweepCurve,
  );

  /// The tank when the lesson opened; the gauge sweeps from it.
  late final int _from = ref.read(economyViewProvider).fuel.liters;
  late final int _max = ref.read(economyViewProvider).fuel.max;
  Timer? _start;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _start?.cancel();
      _sweep.value = 1;
    } else if (_sweep.isDismissed && _start == null) {
      // After the card has come in.
      _start = Timer(MotionTokens.dialogIn, () {
        if (mounted) unawaited(_sweep.forward());
      });
    }
  }

  @override
  void dispose() {
    _start?.cancel();
    _sweep.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_busy) return;
    setState(() => _busy = true);
    final economy = ref.read(economyProvider).requireValue;
    final flags = ref.read(firstSessionFlagsProvider.notifier);
    final outcome = await economy.grantTutorialGift(economy.newRequestId());
    final granted = switch (outcome) {
      OpApplied() => true,
      // Granted meanwhile (a restore, another phone): the tank is the
      // server's, and the lesson is learnt all the same.
      OpRefused(code: EconomyRefusal.alreadyGranted) => true,
      _ => false,
    };
    if (!granted) {
      // Nothing was written: the player may press again.
      if (mounted) setState(() => _busy = false);
      return;
    }
    try {
      await flags.markFuelLessonDone();
    } on Exception catch (error, stack) {
      // The tank is full; only the flag is missing. Leaving would bring
      // the lesson straight back, so the button comes back instead: another
      // press finds the gift granted and writes the flag again.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'onboarding',
        ),
      );
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (!mounted) return;
    context.go(safeThen('/trip/${widget.then}'));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final minutes = ref
        .watch(configSourceProvider)
        .read(Tunable.fuelRegenMinutes);
    return PopScope(
      canPop: false,
      child: SystemBars(
        bottom: ColorTokens.ground,
        child: Scaffold(
          backgroundColor: ColorTokens.ground,
          body: Stack(
            children: [
              const Positioned.fill(
                child: CustomPaint(painter: OnboardingCircles()),
              ),
              LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        LayoutTokens.gutter,
                        0,
                        LayoutTokens.gutter,
                        OnboardingCard.screenBottom,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [_card(l10n, numbers, minutes)],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(AppLocalizations l10n, NumberFormatter numbers, int minutes) {
    return _CardIn(
      child: OnboardingCard(
        character: 'moallem',
        avatarKey: FuelLessonScreen.avatarKey,
        children: [
          Text(
            l10n.fuelLessonTitle,
            textAlign: TextAlign.center,
            style: TypeTokens.displayL.copyWith(color: ColorTokens.ink),
          ),
          SpeechBubble(
            text: l10n.fuelLessonLine,
            name: l10n.fuelLessonSpeaker,
            variant: SpeechBubbleVariant.character,
            tail: false,
            fill: ColorTokens.ground,
            scaled: true,
          ),
          AnimatedBuilder(
            animation: _swept,
            builder: (context, _) {
              final liters = (_from + (_max - _from) * _swept.value).round();
              final share = _max == 0
                  ? 1.0
                  : (_from + (_max - _from) * _swept.value) / _max;
              return Center(
                child: _Gauge(
                  key: FuelLessonScreen.gaugeKey,
                  share: share,
                  value: numbers.ratio(liters, _max),
                  label: l10n.fuelLessonGauge(
                    numbers.integer(liters),
                    numbers.integer(_max),
                  ),
                  empty: l10n.fuelGaugeEmpty,
                  full: l10n.fuelGaugeFull,
                ),
              );
            },
          ),
          Text(
            l10n.fuelLessonRefill(minutes, numbers.integer(minutes)),
            textAlign: TextAlign.center,
            style: DesignExtras.fuelLessonRefill.copyWith(
              color: ColorTokens.inkMuted,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: SpaceTokens.s4),
            child: AppButton.primary(
              key: FuelLessonScreen.ctaKey,
              label: l10n.fuelLessonCta,
              size: AppButtonSize.l,
              height: DesignExtras.nameCtaHeight,
              labelStyle: DesignExtras.nameCtaLabel,
              loading: _busy,
              onTap: () => unawaited(_go()),
            ),
          ),
        ],
      ),
    );
  }
}

/// The card comes in as a dialog does (`dialogIn`); at once under reduced
/// motion.
class _CardIn extends StatelessWidget {
  const _CardIn({required this.child});

  final Widget child;

  static const double _from = 0.92;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: MotionTokens.dialogIn,
      curve: MotionTokens.dialogInCurve,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0, 1),
        alwaysIncludeSemantics: true,
        child: Transform.scale(scale: _from + (1 - _from) * t, child: child),
      ),
      child: child,
    );
  }
}

/// Box 9: the gauge at [share] of full, with the pump inside its arc and
/// the [empty] and [full] marks under its ends, and [value] under it; one
/// node for a screen reader, [label].
class _Gauge extends StatelessWidget {
  const _Gauge({
    required this.share,
    required this.value,
    required this.label,
    required this.empty,
    required this.full,
    super.key,
  });

  final double share;
  final String value;
  final String label;
  final String empty;
  final String full;

  /// A mark's box, centred under its end of the arc.
  static const double _mark = 24;

  @override
  Widget build(BuildContext context) {
    const hub = DesignExtras.fuelLessonHub;
    const pump = DesignExtras.fuelLessonPump;
    Widget mark(String text, double dx, Color color) => Positioned(
      left: hub.dx + dx - _mark / 2,
      width: _mark,
      bottom: 0,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: DesignExtras.fuelLessonMark.copyWith(color: color),
      ),
    );
    return Semantics(
      container: true,
      label: label,
      excludeSemantics: true,
      child: Column(
        spacing: SpaceTokens.s2,
        children: [
          SizedBox.fromSize(
            size: DesignExtras.fuelLessonGauge,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fromRect(
                  rect: DesignExtras.fuelLessonArt,
                  child: RiveArtView(
                    artboard: 'FuelGauge',
                    bind: (model) => model.number('level')?.value = share * 100,
                    fallback: CustomPaint(painter: _GaugePainter(share)),
                  ),
                ),
                Positioned(
                  left: hub.dx - pump / 2,
                  top: hub.dy - DesignExtras.fuelLessonPumpRise - pump / 2,
                  child: const AppIcon('fuel', size: pump),
                ),
                // The board's E and F stay where a car's gauge has them,
                // whatever the reading direction.
                mark(
                  empty,
                  -DesignExtras.fuelLessonRadius,
                  ColorTokens.dangerInk,
                ),
                mark(full, DesignExtras.fuelLessonRadius, ColorTokens.ink),
              ],
            ),
          ),
          Text(
            value,
            style: DesignExtras.fuelLessonValue.copyWith(
              color: ColorTokens.ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// The static gauge, in Rive's box ([DesignExtras.fuelLessonArt]): a half
/// ring on `track`, filled in the third station's green to [share], and an
/// `ink` needle on its hub, between its tips at empty and full.
class _GaugePainter extends CustomPainter {
  const _GaugePainter(this.share);

  final double share;

  /// The tip's angle at full (it points up and right); empty mirrors it.
  static final double _fullAngle = DesignExtras.fuelLessonNeedleTip.direction;
  static final double _emptyAngle = -math.pi - _fullAngle;

  @override
  void paint(Canvas canvas, Size size) {
    const arc = DesignExtras.fuelLessonArc;
    final centre =
        DesignExtras.fuelLessonHub - DesignExtras.fuelLessonArt.topLeft;
    final rect = Rect.fromCircle(
      center: centre,
      radius: DesignExtras.fuelLessonRadius,
    );
    Paint stroke(Color color, double width) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    final filled = share.clamp(0.0, 1.0);
    canvas
      ..drawArc(rect, math.pi, math.pi, false, stroke(ColorTokens.track, arc))
      ..drawArc(
        rect,
        math.pi,
        math.pi * filled,
        false,
        stroke(StationColors.all[2].bg, arc),
      );
    final angle = _emptyAngle + (_fullAngle - _emptyAngle) * filled;
    final tip =
        centre +
        Offset.fromDirection(angle, DesignExtras.fuelLessonNeedleTip.distance);
    canvas
      ..drawLine(
        centre,
        tip,
        stroke(ColorTokens.ink, DesignExtras.fuelLessonNeedle),
      )
      ..drawCircle(
        centre,
        DesignExtras.fuelLessonHubRadius,
        Paint()..color = ColorTokens.ink,
      );
  }

  @override
  bool shouldRepaint(_GaugePainter oldDelegate) => oldDelegate.share != share;
}
