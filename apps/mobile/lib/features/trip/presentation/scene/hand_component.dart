// The driver's hand (layer 3): it rises from the bottom left holding what
// is in the player's hand, and reaches toward a passenger on a throw.
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/tokens/shape.dart';
import 'package:wassal/features/trip/presentation/scene/trip_game.dart';
import 'package:wassal/features/trip/presentation/trip_motion.dart';

class HandComponent extends Component with HasGameReference<TripGame> {
  String? _target;
  double _startMs = 0;

  /// Reaches toward [passengerId], from [clockMs] on the trip clock.
  void reach(String passengerId, double clockMs) {
    _target = passengerId;
    _startMs = clockMs;
  }

  @override
  void render(Canvas canvas) {
    final layout = game.layout;
    final view = game.view;
    if (layout == null || view == null) return;
    final tokens = game.tokens;
    final rest = Offset(layout.driverAnchor.x, layout.driverAnchor.y);
    var at = rest;
    final target = _target;
    if (target != null) {
      final reachMs = TripMotion.throwReach.inMilliseconds;
      final t = (game.clockMs - _startMs) / reachMs;
      final seat = layout.seats[view.passenger(target)?.seatId];
      if (t >= 0 && t < 1 && seat != null) {
        final toward = Offset(seat.tokenAnchor.x, seat.tokenAnchor.y);
        // Out and back.
        final k = math.sin(t * math.pi) * 0.35;
        at = Offset.lerp(rest, toward, k)!;
      } else if (t >= 1) {
        _target = null;
      }
    }

    final size = math.min(48.0, layout.width * 0.13);
    // The palm rises from under the dashboard and holds the notes at the
    // anchor, so it never covers the near row's faces.
    final palmAt = at + Offset(0, size * 0.5);
    const line = ShapeTokens.borderCard;
    final arm = Path()
      ..moveTo(palmAt.dx - size * 0.25, palmAt.dy + size * 0.3)
      ..lineTo(rest.dx - size * 0.4, layout.height + size)
      ..lineTo(rest.dx + size * 0.4, layout.height + size)
      ..lineTo(palmAt.dx + size * 0.25, palmAt.dy + size * 0.3)
      ..close();
    final sleeve = Paint()
      ..color = Color.lerp(tokens.waraq, tokens.hibr, 0.15)!;
    final ink = Paint()
      ..color = tokens.hibr
      ..style = PaintingStyle.stroke
      ..strokeWidth = line
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawPath(arm, sleeve)
      ..drawPath(arm, ink);

    // What the hand holds: a small stack of notes in the change color,
    // without amounts (the dashboard shows them).
    if (!view.hand.isEmpty) {
      final notes = math.min(
        3,
        view.hand.pieces.values.fold(0, (a, b) => a + b),
      );
      for (var i = notes - 1; i >= 0; i--) {
        final note = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: palmAt + Offset(i * 4, -size * 0.4 - i * 3),
            width: size * 0.9,
            height: size * 0.45,
          ),
          Radius.circular(size * 0.06),
        );
        canvas
          ..drawRRect(note, Paint()..color = tokens.primary)
          ..drawRRect(note, ink);
      }
    }

    final palm = Rect.fromCenter(
      center: palmAt,
      width: size * 0.8,
      height: size * 0.7,
    );
    final skin = Paint()..color = Color.lerp(tokens.gold, tokens.waraq, 0.55)!;
    canvas
      ..drawOval(
        palm.shift(const Offset(-line, line)),
        Paint()..color = tokens.hibr,
      )
      ..drawOval(palm, skin)
      ..drawOval(palm, ink);
  }
}
