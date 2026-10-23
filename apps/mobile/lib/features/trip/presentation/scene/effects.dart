// The scene's effects (contracts/scene-layout.md layer 4): the shake on a
// bump or a fight, the glint under money on the floor, and the glow on a
// passenger before a throw. Reduced motion skips the shake and keeps the
// glint and the glow without their pulse.
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/domain/cues.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/presentation/scene/trip_game.dart';
import 'package:wassal/features/trip/presentation/trip_motion.dart';

/// The stage's offset while it shakes, on the screen's own time: a trip
/// that stops on the shake (a fight that fails it) still settles.
final class ShakeController {
  double _left = 0;
  double _total = 0;

  bool get shaking => _left > 0;

  void start(int durationMs) {
    _total = durationMs / 1000;
    _left = _total;
  }

  /// The offset after [dt] more seconds.
  Vector2 offset(double dt) {
    if (_left <= 0) return Vector2.zero();
    _left = math.max(0, _left - dt);
    final t = _total - _left;
    final decay = _left / _total;
    return Vector2(
      TripMotion.shakeAmplitude * math.sin(t * math.pi * 2 * 12) * decay,
      TripMotion.shakeAmplitude * 0.5 * math.cos(t * math.pi * 2 * 9) * decay,
    );
  }
}

/// A glow around the passenger about to receive a throw, on the trip clock.
class HighlightComponent extends Component with HasGameReference<TripGame> {
  String? _passengerId;
  double _startMs = 0;

  void start(String passengerId, double clockMs) {
    _passengerId = passengerId;
    _startMs = clockMs;
  }

  @override
  void render(Canvas canvas) {
    final id = _passengerId;
    final layout = game.layout;
    final view = game.view;
    if (id == null || layout == null || view == null) return;
    final elapsed = game.clockMs - _startMs;
    if (elapsed < 0 || elapsed >= highlightMs) return;
    final seat = layout.seats[view.passenger(id)?.seatId];
    if (seat == null) return;
    final pulse = game.reduceMotion
        ? 1.0
        : 0.6 + 0.4 * math.sin(elapsed / highlightMs * math.pi * 2);
    // A `sun.glow` ring around the head (HANDOFF §5.4 `targeted`).
    canvas.drawCircle(
      Offset(seat.face.x, seat.face.y),
      seat.faceWidth / 2 + 4,
      Paint()
        ..color = ColorTokens.sunGlow.withValues(alpha: 0.9 * pulse)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
  }
}

/// A note on the floor's glint fades over its last this long, so it is
/// gone when the note is lost.
const glintFadeMs = 1000;

/// A glint under each note on the floor, on the trip clock.
class GlintComponent extends Component with HasGameReference<TripGame> {
  @override
  void render(Canvas canvas) {
    final layout = game.layout;
    final view = game.view;
    if (layout == null || view == null) return;
    final clockMs = game.clockMs;
    for (final note in view.dropped) {
      final left = note.untilMs - clockMs;
      if (left <= 0) continue;
      final fade = (left / glintFadeMs).clamp(0.0, 1.0);
      final twinkle = game.reduceMotion
          ? 1.0
          : 0.8 + 0.2 * math.sin(clockMs / 1000 * math.pi * 4);
      final at = layout.floorAt(note.from, note.to, note.progressPermille);
      _star(
        canvas,
        Offset(at.x, at.y),
        rigHeadRadius * layout.scale * 0.9 * twinkle,
        Paint()..color = ColorTokens.sun.withValues(alpha: 0.9 * fade),
      );
    }
  }

  /// A four-pointed sparkle of [radius] around [center].
  void _star(Canvas canvas, Offset center, double radius, Paint paint) {
    final waist = radius * 0.28;
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final r = i.isEven ? radius : waist;
      final point = center + Offset.fromDirection(i * math.pi / 4, r);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(path..close(), paint);
  }
}
