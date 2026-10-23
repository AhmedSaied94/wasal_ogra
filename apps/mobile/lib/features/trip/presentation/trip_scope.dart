// What the trip screen's widgets share: the controller, the model as it
// changes, and the controls the player taps, which remember which control
// a refused command came from so it can shake (research R22).
import 'dart:async';
import 'dart:math' as math;

import 'package:content_models/content_models.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/domain/cues.dart';
import 'package:wassal/features/trip/domain/step_accumulator.dart';
import 'package:wassal/features/trip/presentation/trip_motion.dart';

/// Inside the trip, text scales at most this much (research R15).
const tripMaxTextScale = 1.3;

/// A refused tap on the control [key]; [serial] tells repeats apart.
@immutable
final class ShakeRequest {
  const ShakeRequest(this.key, this.serial);

  final String key;
  final int serial;
}

/// The player's taps, through the controller.
final class TripControls {
  TripControls(this.controller);

  final TripController controller;

  /// The last refused control, to shake.
  final shakes = ValueNotifier<ShakeRequest?>(null);
  String? _acting;
  var _serial = 0;

  static String trayKey(int denomination) => 'tray:$denomination';
  static String passengerKey(String passengerId) => 'passenger:$passengerId';
  static const handKey = 'hand';
  static const undoKey = 'undo';

  /// A drawer slot: picks a piece, or in break mode, the note to break.
  void pick(int denomination) => _act(
    trayKey(denomination),
    () => (controller.view?.breakMode ?? false)
        ? controller.pickBreak(denomination)
        : controller.pick(denomination),
  );

  static const breakKey = 'break';

  /// «حد معاه فكة؟»: into break mode, or out of it.
  void toggleBreak() => _act(
    breakKey,
    () => (controller.view?.breakMode ?? false)
        ? controller.cancelBreak()
        : controller.startBreak(),
  );

  static String boosterKey(BoosterId booster) => 'booster:${booster.name}';

  /// Uses [booster], or opens its purchase card.
  void useBooster(BoosterId booster) => _act(
    boosterKey(booster),
    () => unawaited(controller.useBooster(booster)),
  );

  void returnHand() => _act(handKey, controller.returnHand);

  void undo() => _act(undoKey, controller.undo);

  /// A tap on a passenger: throws what is in the hand, or asks, wakes or
  /// calls them when the hand is empty.
  void tapPassenger(String passengerId) {
    final handEmpty = controller.view?.hand.isEmpty ?? true;
    _act(
      passengerKey(passengerId),
      () => handEmpty
          ? controller.tap(passengerId)
          : controller.send(passengerId),
    );
  }

  /// The hand dragged onto a passenger.
  void dropOn(String passengerId) =>
      _act(passengerKey(passengerId), () => controller.send(passengerId));

  static String claimKey(String passengerId) => 'claim:$passengerId';

  /// «ماشي» (accept) or «لأ، ما دفعتش!» ([insist]) under a claim.
  void answerClaim(String passengerId, {required bool insist}) => _act(
    claimKey(passengerId),
    () => controller.answerClaim(passengerId, insist: insist),
  );

  static String changeRequestKey(String passengerId) =>
      'change-request:$passengerId';

  /// «فكّله» ([agree]) or «معلش» next to a change request.
  void answerChangeRequest(String passengerId, {required bool agree}) => _act(
    changeRequestKey(passengerId),
    () => controller.answerChangeRequest(passengerId, agree: agree),
  );

  static String droppedKey(int tokenId) => 'dropped:$tokenId';

  /// A tap on a note on the floor picks it up.
  void collect(int tokenId) =>
      _act(droppedKey(tokenId), () => controller.collect(tokenId));

  static String disputeKey(String passengerId) => 'dispute:$passengerId';

  /// The face of the one who paid, on the dispute card.
  void answerDispute(String passengerId) => _act(
    disputeKey(passengerId),
    () => controller.answerDispute(passengerId),
  );

  /// Cues arrive while the command runs, so a refusal knows its control.
  void onCue(TripCue cue) {
    final key = _acting;
    if (cue is FeedbackCue && !cue.spoken && key != null) {
      shakes.value = ShakeRequest(key, _serial++);
    }
  }

  void _act(String key, VoidCallback act) {
    _acting = key;
    try {
      act();
    } finally {
      _acting = null;
    }
  }

  void dispose() => shakes.dispose();
}

class TripScope extends InheritedWidget {
  const TripScope({
    required this.controller,
    required this.model,
    required this.controls,
    required super.child,
    super.key,
  });

  final TripController controller;
  final ValueListenable<TripModel> model;
  final TripControls controls;

  static TripScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TripScope>()!;

  @override
  bool updateShouldNotify(TripScope oldWidget) =>
      controller != oldWidget.controller ||
      model != oldWidget.model ||
      controls != oldWidget.controls;
}

/// Rebuilds only when [select] of the model changes.
class TripSelector<T> extends StatefulWidget {
  const TripSelector({
    required this.select,
    required this.builder,
    this.equals,
    super.key,
  });

  final T Function(TripModel model) select;
  final Widget Function(BuildContext context, T value) builder;

  /// How two selections compare; `==` by default. Lists need [listEquals].
  final bool Function(T a, T b)? equals;

  @override
  State<TripSelector<T>> createState() => _TripSelectorState<T>();
}

class _TripSelectorState<T> extends State<TripSelector<T>> {
  ValueListenable<TripModel>? _model;
  late T _value;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final model = TripScope.of(context).model;
    if (model == _model) return;
    _model?.removeListener(_changed);
    _model = model..addListener(_changed);
    _value = widget.select(model.value);
  }

  @override
  void didUpdateWidget(TripSelector<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _value = widget.select(_model!.value);
  }

  void _changed() {
    final value = widget.select(_model!.value);
    final same = widget.equals?.call(value, _value) ?? value == _value;
    if (!same) setState(() => _value = value);
  }

  @override
  void dispose() {
    _model?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}

/// Shakes [child] when its control's command is refused; a short fade
/// instead under reduced motion.
class Shakeable extends StatefulWidget {
  const Shakeable({required this.controlKey, required this.child, super.key});

  final String controlKey;
  final Widget child;

  @override
  State<Shakeable> createState() => _ShakeableState();
}

class _ShakeableState extends State<Shakeable>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
    vsync: this,
    duration: TripMotion.controlShake,
  );
  ValueListenable<ShakeRequest?>? _shakes;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shakes = TripScope.of(context).controls.shakes;
    if (shakes == _shakes) return;
    _shakes?.removeListener(_requested);
    _shakes = shakes..addListener(_requested);
  }

  void _requested() {
    if (_shakes?.value?.key != widget.controlKey) return;
    _animation.forward(from: 0);
  }

  @override
  void dispose() {
    _shakes?.removeListener(_requested);
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: _animation,
      child: widget.child,
      builder: (context, child) {
        final t = _animation.value;
        final shaking = _animation.isAnimating;
        final fade = shaking && reduced ? 0.5 * (1 - (2 * t - 1).abs()) : 0.0;
        final dx = shaking && !reduced
            ? 6 * (1 - t) * math.sin(t * math.pi * 6)
            : 0.0;
        // The same wrappers still and shaking, so the control underneath
        // keeps its state (a tap or a drag in progress).
        return Opacity(
          opacity: 1 - fade,
          child: Transform.translate(offset: Offset(dx, 0), child: child),
        );
      },
    );
  }
}

/// Beats [child] on the trip clock, up to [amplitude] above its size once
/// every two [TripMotion.countdownPulse]s: still while the trip is, and
/// steady under reduced motion.
class TripPulse extends StatelessWidget {
  const TripPulse({required this.amplitude, required this.child, super.key});

  final double amplitude;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final controller = TripScope.of(context).controller;
    final cycle = TripMotion.countdownPulse.inMilliseconds * 2;
    return AnimatedBuilder(
      animation: controller.frames,
      child: child,
      builder: (context, child) {
        final view = controller.view;
        final running = view?.phase == TripPhase.running;
        final t =
            (view?.tMs ?? 0) + (running ? controller.alpha * engineStepMs : 0);
        final wave = 0.5 - 0.5 * math.cos(t / cycle * 2 * math.pi);
        return Transform.scale(scale: 1 + amplitude * wave, child: child);
      },
    );
  }
}
