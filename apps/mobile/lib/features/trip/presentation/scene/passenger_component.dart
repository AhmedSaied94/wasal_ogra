// One seat and whoever sits in it (layer 2). Seats draw back rows first, so
// nearer rows cover farther ones; each passenger walks in through the door
// on the scene's right edge and leaves upward, on the trip clock (a fade
// under reduced motion).
import 'dart:math' as math;

import 'package:content_models/content_models.dart';
import 'package:flame/components.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/tokens/shape.dart';
import 'package:wassal/features/trip/domain/presentation_memory.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/scene/passenger_art.dart';
import 'package:wassal/features/trip/presentation/scene/trip_game.dart';

class PassengerComponent extends Component with HasGameReference<TripGame> {
  PassengerComponent(this.seat);

  final Seat seat;

  PassengerArt? _art;
  String? _passengerId;
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
      _art = game.art.create(passenger.look, game.tokens);
      _presence = null;
    }
    if (passenger.presence != _presence) {
      _presence = passenger.presence;
      _walkStartMs = game.clockMs;
    }
    if (passenger != _view) {
      _view = passenger;
      _art?.update(passenger);
    }
    _art?.advance(dt);
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
    final face = geometry.face;
    var box = Rect.fromLTWH(face.left, face.top, face.width, face.height);
    var opacity = 1.0;
    final walk = ((game.clockMs - _walkStartMs) / walkMs).clamp(0.0, 1.0);
    switch (presence) {
      case PresenceView.boarding:
        opacity = walk;
        if (!game.reduceMotion) {
          // From the door: the scene's right edge.
          box = box.shift(Offset((1 - walk) * (layout.width - face.left), 0));
        }
      case PresenceView.leaving:
        opacity = 1 - walk;
        if (!game.reduceMotion) {
          box = box.shift(Offset(0, -walk * face.height * 0.6));
        }
      case PresenceView.aboard || PresenceView.gone:
        break;
    }
    return (box: box, opacity: opacity);
  }

  @override
  void render(Canvas canvas) {
    final geometry = game.layout?.seats[seat.seatId];
    if (geometry == null) return;
    _drawSeat(canvas, geometry);
    final art = _art;
    final placement = _placement();
    if (art == null || placement == null) return;
    final (:box, :opacity) = placement;
    final face = geometry.face;
    if (opacity <= 0) return;
    if (opacity < 1) {
      canvas.saveLayer(
        box.inflate(face.width),
        Paint()..color = game.tokens.hibr.withValues(alpha: opacity),
      );
      art.render(canvas, box);
      canvas.restore();
    } else {
      art.render(canvas, box);
    }
  }

  void _drawSeat(Canvas canvas, SeatGeometry geometry) {
    final tokens = game.tokens;
    final face = geometry.face;
    final f = face.width;
    final back = RRect.fromRectAndRadius(
      Rect.fromLTRB(
        face.left - f * 0.12,
        face.top + face.height * 0.2,
        face.right + f * 0.12,
        face.bottom + face.height * 0.04,
      ),
      Radius.circular(f * 0.22),
    );
    final line = math.max(1.5, f * ShapeTokens.borderCard / 40);
    canvas
      ..drawRRect(
        back.shift(Offset(-line * 1.2, line * 1.2)),
        Paint()..color = tokens.hibr,
      )
      ..drawRRect(
        back,
        Paint()..color = Color.lerp(tokens.shams, tokens.hibr, 0.4)!,
      )
      ..drawRRect(
        back,
        Paint()
          ..color = tokens.hibr
          ..style = PaintingStyle.stroke
          ..strokeWidth = line,
      );
  }

  @override
  void onRemove() {
    _release();
    super.onRemove();
  }
}
