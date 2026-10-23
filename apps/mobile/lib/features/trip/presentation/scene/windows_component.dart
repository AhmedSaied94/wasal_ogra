// The windows (layer 1, HANDOFF §4.1): the street passing on the trip
// clock in one layer, crawling past stopped cars in traffic and rushing on
// the open road, someone waving from the roadside by the door, and the next
// station's sign in its colour growing as it comes closer (its name and
// letter are on the strip, which is Flutter text). The microbus has two
// side windows, the tuktuk its windscreen.
import 'dart:math' as math;

import 'package:content_models/content_models.dart';
import 'package:flame/components.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/domain/presentation_memory.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/scene/scene_space.dart';
import 'package:wassal/features/trip/presentation/scene/trip_game.dart';
import 'package:wassal/features/trip/presentation/trip_colors.dart';
import 'package:wassal/features/trip/presentation/trip_motion.dart';

/// The sign shows from this long before its station.
const signLeadMs = 8000;

/// The street's buildings repeat every this many design points.
const _blockWidth = 30.0;

/// The street's speed on [road], in points per second.
double streetSpeedOf(Road road) => switch (road) {
  Road.normal => TripMotion.streetSpeed,
  Road.traffic => TripMotion.streetSpeed * TripMotion.trafficCrawl,
  Road.open => TripMotion.streetSpeed * TripMotion.openRoadRush,
};

/// One pane of glass and the way the street moves across it.
typedef _Pane = ({Path glass, Rect bounds, double direction});

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

  /// The panes: the street moves toward the back on both sides.
  List<_Pane> _panes(SceneLayout layout) {
    if (layout.vehicle == VehicleId.tuktuk) {
      final glass = Path()..addRRect(layout.rrectOf(70, 62, 250, 118, 24));
      return [(glass: glass, bounds: glass.getBounds(), direction: 1)];
    }
    Path side(double edge, double sign) {
      Offset p(double dx, double y) => layout.at(edge + sign * dx, y);
      final a = p(0, 34);
      final b = p(90, 50);
      final c = p(94, 55);
      final d = p(94, 136);
      final e = p(90, 141);
      final f = p(0, 176);
      final corner = p(94, 51);
      final corner2 = p(94, 140);
      return Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy)
        ..quadraticBezierTo(corner.dx, corner.dy, c.dx, c.dy)
        ..lineTo(d.dx, d.dy)
        ..quadraticBezierTo(corner2.dx, corner2.dy, e.dx, e.dy)
        ..lineTo(f.dx, f.dy)
        ..close();
    }

    final left = side(0, 1);
    final right = side(390, -1);
    return [
      (glass: left, bounds: left.getBounds(), direction: 1),
      (glass: right, bounds: right.getBounds(), direction: -1),
    ];
  }

  @override
  void render(Canvas canvas) {
    final layout = game.layout;
    if (layout == null) return;
    final panes = _panes(layout);
    for (final (i, pane) in panes.indexed) {
      canvas
        ..save()
        ..clipPath(pane.glass)
        ..drawRect(pane.bounds, Paint()..color = ColorTokens.sceneSky);
      if (layout.vehicle == VehicleId.tuktuk) {
        canvas.drawCircle(
          layout.at(190, 92),
          layout.across(14),
          Paint()..color = ColorTokens.sunGlow,
        );
      }
      _drawStreet(canvas, layout, pane);
      switch (road) {
        case Road.traffic:
          _drawCars(canvas, layout, pane);
        case Road.open:
          _drawRush(canvas, layout, pane);
        case Road.normal:
          break;
      }
      // The door is on the right: the waving passenger stands there.
      if (i == panes.length - 1) _drawWave(canvas, layout, pane);
      canvas.restore();
    }
    _drawSign(canvas, layout);
  }

  /// Buildings scrolling with the trip, their feet on the pane's bottom.
  void _drawStreet(Canvas canvas, SceneLayout layout, _Pane pane) {
    final block = layout.across(_blockWidth);
    final shift = (_distance * pane.direction) % block;
    final ground = pane.bounds.bottom;
    final height = pane.bounds.height;
    final radius = Radius.circular(layout.across(5));
    var i = 0;
    for (
      var x = pane.bounds.left - block + shift;
      x < pane.bounds.right;
      x += block, i++
    ) {
      // A fixed pattern along the street, so the same building comes back.
      final n = ((_distance * pane.direction) / block).floor() - i;
      final tall = 0.4 + 0.3 * (n * 7919 % 4).abs() / 3;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            x + layout.across(3),
            ground - height * tall,
            x + block - layout.across(3),
            ground,
          ),
          radius,
        ),
        Paint()
          ..color = DesignExtras
              .sceneBuildings[(n % DesignExtras.sceneBuildings.length).abs()],
      );
    }
  }

  /// Stopped cars along the street.
  void _drawCars(Canvas canvas, SceneLayout layout, _Pane pane) {
    final h = layout.across(18);
    final w = h * 2.2;
    final colors = [
      ColorTokens.danger,
      ColorTokens.primary,
      ColorTokens.noteFare,
    ];
    for (final (i, share) in const [0.1, 0.6].indexed) {
      final left = pane.bounds.left + pane.bounds.width * share;
      final bottom = pane.bounds.bottom - layout.across(4);
      final body = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, bottom - h, w, h * 0.65),
        Radius.circular(h * 0.25),
      );
      final cabin = RRect.fromRectAndRadius(
        Rect.fromLTWH(left + w * 0.2, bottom - h * 1.3, w * 0.5, h * 0.45),
        Radius.circular(h * 0.2),
      );
      canvas
        ..drawRRect(cabin, Paint()..color = ColorTokens.paper)
        ..drawRRect(body, Paint()..color = colors[i % colors.length]);
      for (final x in [left + w * 0.25, left + w * 0.75]) {
        canvas.drawCircle(
          Offset(x, bottom - h * 0.3),
          h * 0.2,
          Paint()..color = ColorTokens.sceneTyre,
        );
      }
    }
  }

  /// Speed lines over the rushing street.
  void _drawRush(Canvas canvas, SceneLayout layout, _Pane pane) {
    final paint = Paint()
      ..color = ColorTokens.paper.withValues(alpha: 0.8)
      ..strokeWidth = layout.across(2)
      ..strokeCap = StrokeCap.round;
    final length = layout.across(22);
    final gap = 3 * length;
    for (final (row, share) in const [0.3, 0.55, 0.8].indexed) {
      final y = pane.bounds.top + pane.bounds.height * share;
      final offset = (_distance * 2 * pane.direction + row * length) % gap;
      for (
        var x = pane.bounds.left - gap + offset;
        x < pane.bounds.right;
        x += gap
      ) {
        canvas.drawLine(Offset(x, y), Offset(x + length, y), paint);
      }
    }
  }

  /// Someone on the roadside by the door, waving the bus down.
  void _drawWave(Canvas canvas, SceneLayout layout, _Pane pane) {
    final since = game.view?.windows.waveAtMs;
    if (since == null) return;
    final elapsed = game.clockMs - since;
    final h = pane.bounds.height * 0.55;
    final x = pane.bounds.center.dx;
    final ground = pane.bounds.bottom;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(x - h * 0.17, ground - h * 0.6, h * 0.34, h * 0.6),
      Radius.circular(h * 0.14),
    );
    final head = Offset(x, ground - h * 0.76);
    final swing = game.reduceMotion
        ? 0.0
        : 0.45 * math.sin(elapsed / waveMs * math.pi * 6);
    final shoulder = Offset(x + h * 0.12, ground - h * 0.52);
    final hand =
        shoulder + Offset.fromDirection(-math.pi / 2 + 0.35 + swing, h * 0.4);
    canvas
      ..drawLine(
        shoulder,
        hand,
        Paint()
          ..color = ColorTokens.characterShirtDefault
          ..strokeWidth = h * 0.1
          ..strokeCap = StrokeCap.round,
      )
      ..drawRRect(body, Paint()..color = ColorTokens.characterShirtDefault)
      ..drawCircle(head, h * 0.17, Paint()..color = DesignExtras.driverSkin);
  }

  /// The next station's sign: in the left window of `C-Trip` (box 30), the
  /// windscreen's left of a tuktuk. It slides in and grows over the last
  /// [signLeadMs]; under reduced motion it stands in place.
  void _drawSign(Canvas canvas, SceneLayout layout) {
    final strip = game.view?.strip;
    final countdown = strip?.countdownMs;
    if (strip == null || countdown == null || countdown > signLeadMs) return;
    final next = strip.chips.where((c) => c.next).firstOrNull;
    if (next == null) return;
    final near = game.reduceMotion ? 1.0 : 1 - countdown / signLeadMs;
    final tuktuk = layout.vehicle == VehicleId.tuktuk;
    final (bx, by, px, py, ph) = tuktuk
        ? (80.0, 110.0, 116.0, 140.0, 40.0)
        : (10.0, 76.0, 46.0, 106.0, 34.0);
    final grow = 0.6 + 0.4 * near;
    final slide = layout.across(-50 * (1 - near));
    final foot = layout.at(px + 2, py + ph);
    canvas
      ..save()
      ..translate(foot.dx + slide, foot.dy)
      ..scale(grow)
      ..translate(-foot.dx, -foot.dy)
      ..drawRRect(
        layout.rrectOf(px, py, 4, ph, 2),
        Paint()..color = ColorTokens.iconOff,
      )
      ..drawRRect(
        layout.rrectOf(bx, by, 76, 30, 10),
        Paint()..color = TripColors.station(next.slot).bg,
      )
      ..restore();
  }
}
