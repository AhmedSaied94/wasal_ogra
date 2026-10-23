// Whoever sits in a seat (layer 2). Seats draw back rows first, so nearer
// rows cover farther ones; the benches are the cabin's. Each passenger
// slides in through the door on the scene's right edge and gets off rising
// 12 pt, on the trip clock (a fade under reduced motion).
import 'package:content_models/content_models.dart';
import 'package:flame/components.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/domain/poses.dart';
import 'package:wassal/features/trip/domain/presentation_memory.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/scene/passenger_art.dart';
import 'package:wassal/features/trip/presentation/scene/trip_game.dart';
import 'package:wassal/features/trip/presentation/trip_motion.dart';

class PassengerComponent extends Component with HasGameReference<TripGame> {
  PassengerComponent(this.seat);

  final Seat seat;

  PassengerArt? _art;
  String? _passengerId;

  /// What [_art] was made by, and whether under reduced motion, which
  /// draws the static art: a change makes it again.
  PassengerArtFactory? _artFactory;
  bool _artReduced = false;
  PassengerView? _view;
  PresenceView? _presence;
  double _walkStartMs = 0;

  /// Farther rows first: the front seat is drawn last.
  static int depth(Seat seat) => 100 - seat.row.index * 10;

  @override
  void update(double dt) {
    final passenger = game.view?.passengers
        .where((p) => p.seatId == seat.seatId)
        .firstOrNull;
    if (passenger == null) {
      _release();
      return;
    }
    if (passenger.passengerId != _passengerId) {
      _release();
      _passengerId = passenger.passengerId;
      _presence = null;
    }
    if (_art == null ||
        !identical(_artFactory, game.art) ||
        _artReduced != game.reduceMotion) {
      _art?.dispose();
      _artFactory = game.art;
      _artReduced = game.reduceMotion;
      _art = game.art.create(
        passenger.look,
        row: seat.row,
        reduceMotion: _artReduced,
      );
      _view = null;
      for (final trigger in game.stage.takeTriggers(passenger.passengerId)) {
        _art?.play(trigger);
      }
    }
    if (passenger.presence != _presence) {
      _presence = passenger.presence;
      _walkStartMs = game.clockMs;
    }
    if (passenger != _view) {
      _view = passenger;
      _art?.update(passenger);
    }
    _art
      ?..reduceMotion = game.reduceMotion
      ..advance(dt);
  }

  /// Plays [trigger] if [passengerId] sits here; false otherwise.
  bool play(String passengerId, CharacterTrigger trigger) {
    final art = _art;
    if (passengerId != _passengerId || art == null) return false;
    art.play(trigger);
    return true;
  }

  void _release() {
    _art?.dispose();
    _art = null;
    _passengerId = null;
    _view = null;
    _presence = null;
  }

  /// Where the passenger is drawn now, or null with nobody to draw.
  Rect? get artBox => _placement()?.box;

  ({Rect box, double opacity})? _placement() {
    final layout = game.layout;
    final geometry = layout?.seats[seat.seatId];
    final presence = _presence;
    if (layout == null ||
        geometry == null ||
        _art == null ||
        presence == null ||
        presence == PresenceView.gone) {
      return null;
    }
    final head = geometry.head;
    var box = Rect.fromLTWH(head.left, head.top, head.width, head.height);
    var opacity = 1.0;
    final walk = ((game.clockMs - _walkStartMs) / walkMs).clamp(0.0, 1.0);
    switch (presence) {
      case PresenceView.boarding:
        opacity = walk;
        if (!game.reduceMotion) {
          // From the door: the scene's right edge.
          box = box.shift(Offset((1 - walk) * (layout.width - head.left), 0));
        }
      case PresenceView.leaving:
        opacity = 1 - walk;
        if (!game.reduceMotion) {
          box = box.shift(Offset(0, -walk * TripMotion.alightRise));
        }
      case PresenceView.aboard || PresenceView.gone:
        break;
    }
    return (box: box, opacity: opacity);
  }

  @override
  void render(Canvas canvas) {
    final art = _art;
    final placement = _placement();
    if (art == null || placement == null) return;
    final (:box, :opacity) = placement;
    if (opacity <= 0) return;
    if (opacity < 1) {
      canvas.saveLayer(
        box.inflate(box.width),
        Paint()..color = ColorTokens.ink.withValues(alpha: opacity),
      );
      art.render(canvas, box);
      canvas.restore();
    } else {
      art.render(canvas, box);
    }
  }

  @override
  void onRemove() {
    _release();
    super.onRemove();
  }
}
