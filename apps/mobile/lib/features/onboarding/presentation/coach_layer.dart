// بلية's coach over the trip (specs/012-m07-onboarding/contracts/coach.md
// "The overlay"): while a step shows, the scrim with its hole on the step's
// target, the ring and the hand, and only the target answers a tap; بلية
// and his bubble at the door, from the presentation memory's بلية bubble.
// After a step ends early, only بلية and the bubble stay, untouchable,
// until the bubble's time is up. Screen readers hear the step once and
// reach only the target.
import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/theme/components/story.dart';
import 'package:wassal/features/onboarding/domain/tutorial_coach.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/domain/trip_facts.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/overlays/hint_layer.dart';
import 'package:wassal/features/trip/presentation/overlays/hit_areas.dart';
import 'package:wassal/features/trip/presentation/trip_motion.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/features/trip/presentation/trip_text.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// What the layer draws: the step showing, بلية's line, and the view the
/// targets' places and labels come from.
typedef _Coached = ({CoachView? step, CoachLine? line, TripView? view});

/// One place a tap may land while a step shows, with what it says to a
/// screen reader and what it does there.
typedef _Opening = ({Rect rect, String label, VoidCallback? onTap, Key key});

class CoachLayer extends ConsumerStatefulWidget {
  const CoachLayer({required this.zones, super.key});

  /// Where the scene sits in this layer, which covers the screen.
  final TripZones zones;

  static const markKey = ValueKey('coach-mark');
  static const catcherKey = ValueKey('coach-catcher');
  static const headKey = ValueKey('coach-head');
  static const bubbleKey = ValueKey('coach-bubble');

  /// The screen reader's way to [target] while the step shows.
  static Key targetKey(CoachTarget target) =>
      ValueKey(('coach-target', target));

  @override
  ConsumerState<CoachLayer> createState() => _CoachLayerState();
}

class _CoachLayerState extends ConsumerState<CoachLayer> {
  /// The step already announced: once per step.
  CoachStepId? _announced;

  /// The target focused, until the step hides (a pause brings it back).
  CoachTarget? _focused;

  @override
  Widget build(BuildContext context) {
    final scope = TripScope.of(context);
    // A box that stays while the layer comes and goes: the targets' rects
    // are made local against it.
    return SizedBox.expand(child: _selector(scope));
  }

  Widget _selector(TripScope scope) {
    return TripSelector<_Coached?>(
      select: (model) => model.coach == null && model.coachBubble == null
          ? null
          : (step: model.coach, line: model.coachBubble, view: model.view),
      builder: (context, coached) {
        if (coached == null || coached.view == null) {
          _focused = null;
          return const SizedBox.shrink();
        }
        return ListenableBuilder(
          listenable: scope.anchors,
          builder: (context, _) => _build(context, scope, coached),
        );
      },
    );
  }

  Widget _build(BuildContext context, TripScope scope, _Coached coached) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final facts = scope.controller.session?.facts;
    String say(CoachLine line) =>
        l10n.coachLine(line, numbers, (id) => facts?.stationName(id) ?? '');
    final step = coached.step;
    if (step == null) {
      _focused = null;
    } else {
      _speak(step, l10n.coachAnnouncement(say(step.line)));
    }
    final zones = widget.zones;
    final line = coached.line;
    final belya = line == null
        ? null
        : Positioned(
            left: zones.left,
            top: zones.sceneTop,
            width: zones.width,
            height: zones.scene,
            child: IgnorePointer(
              child: BelyaSays(
                text: say(line),
                name: l10n.coachName,
                headTop: BelyaSays.headTopIn(zones.scene),
                semanticsLabel: step == null
                    ? l10n.coachAnnouncement(say(line))
                    : null,
                headKey: CoachLayer.headKey,
                bubbleKey: CoachLayer.bubbleKey,
              ),
            ),
          );
    if (step == null) {
      return Stack(children: [?belya]);
    }
    final openings = _openings(
      scope,
      step,
      coached.view!,
      facts,
      l10n,
      numbers,
    );
    final hole = openings.firstOrNull?.rect;
    final catcher = step.endsOnAnyTap
        ? Positioned.fill(
            child: Semantics(
              key: CoachLayer.catcherKey,
              container: true,
              button: true,
              label: l10n.coachAnnouncement(say(step.line)),
              onTap: scope.controller.coachTapped,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: scope.controller.coachTapped,
              ),
            ),
          )
        : null;
    // Painted first, the rest of the trip is silent to screen readers.
    return BlockSemantics(
      child: Stack(
        children: [
          if (hole != null)
            Positioned.fill(
              child: ExcludeSemantics(
                child: _Mark(key: CoachLayer.markKey, step: step, hole: hole),
              ),
            ),
          if (!step.endsOnAnyTap)
            for (final opening in openings)
              Positioned.fromRect(
                rect: opening.rect,
                child: Semantics(
                  key: opening.key,
                  container: true,
                  button: opening.onTap != null,
                  label: opening.label,
                  onTap: opening.onTap,
                  child: const SizedBox.expand(),
                ),
              ),
          ?belya,
          ?catcher,
        ],
      ),
    );
  }

  /// The places of [step]'s active target in this layer: a cell, the
  /// drawer's full cells, a rider, the countdown. None before it is laid
  /// out.
  List<_Opening> _openings(
    TripScope scope,
    CoachView step,
    TripView view,
    TripFacts? facts,
    AppLocalizations l10n,
    NumberFormatter numbers,
  ) {
    // The layer's own box, laid out since the screen opened.
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return const [];
    Rect? local(CoachTarget target) => switch (scope.anchors.rectOf(target)) {
      final rect? => rect.shift(box.globalToLocal(Offset.zero)),
      null => null,
    };
    final controls = scope.controls;
    _Opening? cell(TraySlotView slot) {
      final target = TrayCellTarget(slot.denomination);
      final rect = local(target);
      if (rect == null) return null;
      final d = slot.denomination;
      return (
        rect: rect,
        label: l10n.tripTraySlot(
          d == 100 ? 'pound' : 'other',
          l10n.trayLabel(d, numbers),
          numbers.integer(slot.count),
        ),
        onTap: () => controls.pick(d),
        key: CoachLayer.targetKey(target),
      );
    }

    switch (step.target) {
      case TrayCellTarget(:final denomination):
        final slot = view.tray
            .where((s) => s.denomination == denomination)
            .firstOrNull;
        final opening = slot == null ? null : cell(slot);
        return [?opening];
      case TrayTarget():
        final whole = local(const TrayTarget());
        if (whole == null) return const [];
        // The hole is the drawer; a screen reader reaches each full cell.
        final cells = [
          for (final slot in view.tray)
            if (slot.count > 0) ?cell(slot),
        ];
        return [
          (
            rect: whole,
            label: '',
            onTap: null,
            key: CoachLayer.targetKey(const TrayTarget()),
          ),
          ...cells,
        ];
      case StationCountdownTarget():
        final rect = local(const StationCountdownTarget());
        final countdown = view.strip.countdownMs;
        if (rect == null || countdown == null) return const [];
        return [
          (
            rect: rect,
            label: l10n.tripStripCountdown(
              numbers.countdown(Duration(milliseconds: countdown)),
            ),
            onTap: null,
            key: CoachLayer.targetKey(const StationCountdownTarget()),
          ),
        ];
      case PassengerTarget(:final passengerId):
        final p = view.passenger(passengerId);
        final definition = facts?.definition;
        if (p == null || definition == null) return const [];
        final zones = widget.zones;
        final seat = SceneLayout(
          definition.seats,
          vehicle: definition.vehicleId,
          width: zones.width,
          height: zones.scene,
        ).seats[p.seatId];
        if (seat == null) return const [];
        return [
          (
            rect: Rect.fromLTWH(
              seat.hit.left + zones.left,
              seat.hit.top + zones.sceneTop,
              seat.hit.width,
              seat.hit.height,
            ),
            label: HitAreas.labelOf(
              l10n,
              seat,
              lookKey: p.look.labelKey,
              slot: p.slot,
              stopName: stopNameOf(view, p.slot),
              owed: p.nearStopPulse,
              ledger: p.ledgerBadge,
            ),
            onTap: () => controls.tapPassenger(passengerId),
            key: CoachLayer.targetKey(step.target),
          ),
        ];
    }
  }

  /// Announces a new step once, and focuses its target on the next frame.
  void _speak(CoachView step, String announcement) {
    if (_announced != step.lessonStep) {
      _announced = step.lessonStep;
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          announcement,
          Directionality.of(context),
        ),
      );
    }
    final target = step.target;
    if (_focused == target) return;
    _focused = target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = step.endsOnAnyTap
          ? CoachLayer.catcherKey
          : CoachLayer.targetKey(target);
      _find(key)?.sendSemanticsEvent(const FocusSemanticEvent());
    });
  }

  /// The render object under the widget keyed [key] in this layer.
  RenderObject? _find(Key key) {
    RenderObject? found;
    void visit(Element element) {
      if (found != null) return;
      if (element.widget.key == key) {
        found = element.renderObject;
        return;
      }
      element.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    return found;
  }
}

/// The scrim, the hole moving to [hole], the ring and the hand; it fades
/// in when a step starts.
class _Mark extends StatelessWidget {
  const _Mark({required this.step, required this.hole, super.key});

  final CoachView step;
  final Rect hole;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      key: ValueKey(step.lessonStep),
      tween: Tween(begin: 0, end: 1),
      duration: TripMotion.coachScrimFade,
      builder: (context, opacity, child) =>
          Opacity(opacity: opacity, child: child),
      child: TweenAnimationBuilder<Rect?>(
        tween: RectTween(end: hole),
        duration: reduced ? Duration.zero : TripMotion.coachHoleMove,
        curve: TripMotion.coachHoleCurve,
        builder: (context, rect, _) =>
            CoachMark(target: rect ?? hole, pulse: true),
      ),
    );
  }
}
