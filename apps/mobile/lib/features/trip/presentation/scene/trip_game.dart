// The Flame scene (contracts/trip-layout.md, layers 1–4): the cabin, the
// windows, the benches, the passengers, the driver's hand and the effects.
// It draws no text (M02 research R3); money, bubbles and labels are Flutter
// overlays that read the same `SceneLayout`.
import 'dart:async';

import 'package:content_models/content_models.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/domain/cues.dart';
import 'package:wassal/features/trip/domain/poses.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/domain/step_accumulator.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/scene/cabin_component.dart';
import 'package:wassal/features/trip/presentation/scene/effects.dart';
import 'package:wassal/features/trip/presentation/scene/hand_component.dart';
import 'package:wassal/features/trip/presentation/scene/passenger_art.dart';
import 'package:wassal/features/trip/presentation/scene/passenger_component.dart';
import 'package:wassal/features/trip/presentation/scene/windows_component.dart';

class TripGame extends FlameGame {
  TripGame({
    required this.controller,
    required this.seats,
    required this.vehicle,
    required this.art,
    required this.reduceMotion,
    required this.drivesClock,
  }) {
    // Without the clock, nothing ticks: the screen steps the scene once per
    // change (widget tests and goldens).
    if (!drivesClock) paused = true;
  }

  final TripController controller;
  final List<Seat> seats;
  final VehicleId vehicle;

  /// Each seat makes its passenger's art again when this changes.
  PassengerArtFactory art;

  /// Whether the screen's frames drive the trip's clock.
  final bool drivesClock;
  bool reduceMotion;

  SceneLayout? _layout;
  StreamSubscription<TripCue>? _cues;
  late final TripStage stage;

  /// Null until the game has a size.
  SceneLayout? get layout => _layout;

  TripView? get view => controller.view;

  /// The trip clock, smoothed between engine steps.
  double get clockMs {
    final view = this.view;
    if (view == null) return 0;
    final moving = view.phase == TripPhase.running;
    return view.tMs + (moving ? controller.alpha * engineStepMs : 0);
  }

  @override
  Color backgroundColor() => ColorTokens.ground;

  @override
  Future<void> onLoad() async {
    stage = TripStage();
    await add(stage);
    _cues = controller.cues.listen(stage.onCue);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _layout = SceneLayout(
      seats,
      vehicle: vehicle,
      width: size.x,
      height: size.y,
    );
  }

  @override
  void update(double dt) {
    if (drivesClock) {
      controller.advance(Duration(microseconds: (dt * 1e6).round()));
    }
    super.update(dt);
  }

  @override
  void onRemove() {
    unawaited(_cues?.cancel());
    super.onRemove();
  }
}

/// Layers 1–4 in one parent, so the shake moves them together.
class TripStage extends PositionComponent with HasGameReference<TripGame> {
  late final ShakeController _shake = ShakeController();
  late final HighlightComponent _highlight;
  late final HandComponent _hand;
  late final List<PassengerComponent> _seats;

  /// One-shots for passengers whose art isn't made yet (a cue can come
  /// before the frame that seats them), by passenger.
  final _pendingTriggers = <String, List<CharacterTrigger>>{};

  @override
  Future<void> onLoad() async {
    _highlight = HighlightComponent();
    _hand = HandComponent();
    _seats = [
      for (final seat in game.seats)
        PassengerComponent(seat)..priority = PassengerComponent.depth(seat),
    ];
    await addAll([
      CabinComponent(CabinPart.back)..priority = 1,
      WindowsComponent()..priority = 2,
      CabinComponent(CabinPart.benches)..priority = 3,
      ..._seats,
      GlintComponent()..priority = 140,
      _highlight..priority = 150,
      _hand..priority = 200,
    ]);
  }

  void onCue(TripCue cue) {
    switch (cue) {
      case ShakeCue(:final durationMs) when !game.reduceMotion:
        _shake.start(durationMs);
      case HighlightCue(:final passengerId):
        _highlight.start(passengerId, game.clockMs);
        _hand.reach(passengerId, game.clockMs);
      case CharacterCue(:final passengerId, :final trigger):
        if (!_seats.any((seat) => seat.play(passengerId, trigger))) {
          (_pendingTriggers[passengerId] ??= []).add(trigger);
        }
      default:
    }
  }

  /// The one-shots [passengerId]'s new art should play.
  List<CharacterTrigger> takeTriggers(String passengerId) =>
      _pendingTriggers.remove(passengerId) ?? const [];

  @override
  void update(double dt) {
    position.setFrom(_shake.offset(dt));
  }
}
