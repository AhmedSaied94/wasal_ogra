// The windows (layer 1): the street passing on the trip clock, crawling
// past stopped cars in traffic and rushing on the open road, someone
// waving from the roadside, and the next station's sign growing as it
// comes closer. The sign shows the station's color; its letter is on the
// strip, which is Flutter text.
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/tokens/shape.dart';
import 'package:wassal/features/trip/domain/presentation_memory.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/scene/trip_game.dart';
import 'package:wassal/features/trip/presentation/trip_motion.dart';

/// The sign shows from this long before its station.
const signLeadMs = 8000;

/// The street's buildings repeat every this many points.
const _blockWidth = 64.0;

/// The street's speed on [road], in points per second.
double streetSpeedOf(Road road) => switch (road) {
  Road.normal => TripMotion.streetSpeed,
  Road.traffic => TripMotion.streetSpeed * TripMotion.trafficCrawl,
  Road.open => TripMotion.streetSpeed * TripMotion.openRoadRush,
};

class WindowsComponent extends Component with HasGameReference<TripGame> {
  /// How far the street has passed, in points: the speed changes with the
  /// road, so the distance adds up on the trip clock.
  double _distance = 0;
  double? _lastClockMs;

  Road get road => game.view?.windows.road ?? Road.normal;

  /// The street's speed now, in points per second.
  double get speed => streetSpeedOf(road);

  /// Someone waves from the roadside.
  bool get waving => game.view?.windows.waveAtMs != null;

  @override
  void update(double dt) {
    final clockMs = game.clockMs;
    final last = _lastClockMs;
    _distance = last == null
        ? clockMs / 1000 * TripMotion.streetSpeed
        : _distance + math.max(0, clockMs - last) / 1000 * speed;
    _lastClockMs = clockMs;
  }

  @override
  void render(Canvas canvas) {
    final layout = game.layout;
    if (layout == null) return;
    final tokens = game.tokens;
    final r = layout.windows;
    final glass = Rect.fromLTWH(r.left, r.top, r.width, r.height);
    canvas
      ..save()
      ..clipRect(glass)
      ..drawRect(
        glass,
        Paint()..color = Color.lerp(tokens.waraq, tokens.primary, 0.16)!,
      );

    // Buildings, scrolling with the trip.
    final shift = _distance % _blockWidth;
    final ground = glass.bottom;
    final building = Paint()
      ..color = Color.lerp(tokens.waraq, tokens.tablouh, 0.28)!;
    final windowDot = Paint()..color = tokens.waraq.withValues(alpha: 0.7);
    for (var i = -1; i * _blockWidth < glass.width + _blockWidth; i++) {
      final x = i * _blockWidth + shift;
      final tall = 0.45 + 0.35 * ((i * 7919) % 5) / 4;
      final rect = Rect.fromLTRB(
        x + 4,
        ground - glass.height * tall,
        x + _blockWidth - 6,
        ground,
      );
      canvas.drawRect(rect, building);
      for (var row = rect.top + 8; row < ground - 10; row += 14) {
        canvas.drawRect(Rect.fromLTWH(rect.left + 8, row, 8, 6), windowDot);
        canvas.drawRect(Rect.fromLTWH(rect.right - 16, row, 8, 6), windowDot);
      }
    }
    switch (road) {
      case Road.traffic:
        _drawCars(canvas, glass);
      case Road.open:
        _drawRush(canvas, glass);
      case Road.normal:
        break;
    }
    _drawWave(canvas, glass);
    _drawSign(canvas, glass);
    canvas.restore();
  }

  /// Stopped cars along the street.
  void _drawCars(Canvas canvas, Rect glass) {
    final tokens = game.tokens;
    final h = glass.height * 0.3;
    final w = h * 2.2;
    final line = math.max(1.5, h * 0.08);
    final ink = Paint()
      ..color = tokens.hibr
      ..style = PaintingStyle.stroke
      ..strokeWidth = line;
    final colors = [tokens.danger, tokens.primary, tokens.fare];
    for (final (i, share) in const [0.08, 0.42, 0.76].indexed) {
      final left = glass.left + glass.width * share;
      final body = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, glass.bottom - h * 1.1, w, h * 0.7),
        Radius.circular(h * 0.2),
      );
      final cabin = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          left + w * 0.2,
          glass.bottom - h * 1.45,
          w * 0.5,
          h * 0.4,
        ),
        Radius.circular(h * 0.15),
      );
      canvas
        ..drawRRect(cabin, Paint()..color = tokens.waraq)
        ..drawRRect(cabin, ink)
        ..drawRRect(body, Paint()..color = colors[i % colors.length])
        ..drawRRect(body, ink);
      for (final x in [left + w * 0.25, left + w * 0.75]) {
        canvas.drawCircle(
          Offset(x, glass.bottom - h * 0.4),
          h * 0.22,
          Paint()..color = tokens.hibr,
        );
      }
    }
  }

  /// Speed lines over the rushing street.
  void _drawRush(Canvas canvas, Rect glass) {
    final paint = Paint()
      ..color = game.tokens.waraq.withValues(alpha: 0.8)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const length = 28.0;
    const gap = 3 * length;
    for (final (row, share) in const [0.3, 0.55, 0.8].indexed) {
      final y = glass.top + glass.height * share;
      final offset = (_distance * 2 + row * length) % gap;
      for (var x = glass.left - gap + offset; x < glass.right; x += gap) {
        canvas.drawLine(Offset(x, y), Offset(x + length, y), paint);
      }
    }
  }

  /// Someone on the roadside by the door, waving the bus down.
  void _drawWave(Canvas canvas, Rect glass) {
    final since = game.view?.windows.waveAtMs;
    if (since == null) return;
    final elapsed = game.clockMs - since;
    final tokens = game.tokens;
    final h = glass.height * 0.7;
    final x = glass.right - glass.width * 0.12;
    final ground = glass.bottom;
    final line = math.max(2.0, h * 0.07);
    final ink = Paint()
      ..color = tokens.hibr
      ..strokeWidth = line
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(x - h * 0.16, ground - h * 0.62, h * 0.32, h * 0.62),
      Radius.circular(h * 0.1),
    );
    final head = Offset(x, ground - h * 0.78);
    final swing = game.reduceMotion
        ? 0.0
        : 0.45 * math.sin(elapsed / waveMs * math.pi * 6);
    final shoulder = Offset(x + h * 0.12, ground - h * 0.55);
    final hand =
        shoulder + Offset.fromDirection(-math.pi / 2 + 0.35 + swing, h * 0.42);
    canvas
      ..drawLine(shoulder, hand, ink)
      ..drawRRect(body, Paint()..color = tokens.primary)
      ..drawRRect(body, ink)
      ..drawCircle(
        head,
        h * 0.16,
        Paint()..color = Color.lerp(tokens.gold, tokens.waraq, 0.55)!,
      )
      ..drawCircle(head, h * 0.16, ink);
  }

  void _drawSign(Canvas canvas, Rect glass) {
    final strip = game.view?.strip;
    final countdown = strip?.countdownMs;
    if (strip == null || countdown == null || countdown > signLeadMs) return;
    final next = strip.chips.where((c) => c.next).firstOrNull;
    if (next == null) return;
    final near = 1 - countdown / signLeadMs;
    final tokens = game.tokens;
    final size = glass.height * (0.3 + 0.35 * near);
    final x = glass.left + glass.width * (0.1 + 0.55 * near);
    final pole = Paint()
      ..color = tokens.hibr
      ..strokeWidth = math.max(2, size * 0.08);
    canvas.drawLine(
      Offset(x, glass.bottom),
      Offset(x, glass.bottom - size * 1.2),
      pole,
    );
    final board = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(x, glass.bottom - size * 1.2),
        width: size * 1.3,
        height: size * 0.8,
      ),
      Radius.circular(size * 0.15),
    );
    canvas
      ..drawRRect(
        board.shift(Offset(-size * 0.06, size * 0.06)),
        Paint()..color = tokens.hibr,
      )
      ..drawRRect(
        board,
        Paint()
          ..color = tokens.stations[next.slot % tokens.stations.length].fill,
      )
      ..drawRRect(
        board,
        Paint()
          ..color = tokens.hibr
          ..style = PaintingStyle.stroke
          ..strokeWidth = ShapeTokens.borderCard,
      );
  }
}
