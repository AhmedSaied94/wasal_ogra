// How a passenger is drawn (research R17): the owner's Rive character
// later, and until then, and in every golden, a stand-in painter in the
// sticker style. Both sit behind the same interface, so the art changes
// without touching behavior.
import 'dart:math' as math;
import 'dart:ui';

import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/tokens/shape.dart';
import 'package:wassal/features/trip/domain/skin_looks.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/trip_colors.dart';

/// Makes the art of each passenger.
abstract interface class PassengerArtFactory {
  PassengerArt create(SkinLook look, WassalTokens tokens);
}

/// One passenger's drawing.
abstract interface class PassengerArt {
  /// The passenger's state changed.
  void update(PassengerView view);

  /// Its own animation moved on by [dt] seconds.
  void advance(double dt);

  /// Draws head and shoulders into [box], the seat's face rectangle.
  void render(Canvas canvas, Rect box);

  void dispose();
}

final class StandInPassengerArtFactory implements PassengerArtFactory {
  const StandInPassengerArtFactory();

  @override
  PassengerArt create(SkinLook look, WassalTokens tokens) =>
      StandInPassengerArt(look, tokens);
}

/// A face and shoulders drawn in code: the look's shirt and accessory, and
/// the view's mood, talking, sleep and headphones.
final class StandInPassengerArt implements PassengerArt {
  StandInPassengerArt(this.look, this.tokens);

  final SkinLook look;
  final WassalTokens tokens;

  PassengerView? _view;
  double _clock = 0;

  /// The view last drawn, for tests.
  PassengerView? get view => _view;

  @override
  void update(PassengerView view) => _view = view;

  @override
  void advance(double dt) => _clock += dt;

  @override
  void dispose() {}

  Color get _skin => Color.lerp(tokens.gold, tokens.waraq, 0.55)!;
  Color get _shirt => shirtColor(tokens, look.shirt);

  Paint _fill(Color color) => Paint()..color = color;

  Paint _ink(double width) => Paint()
    ..color = tokens.hibr
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  void render(Canvas canvas, Rect box) {
    final view = _view;
    final w = box.width;
    final h = box.height;
    final line = math.max(1.5, w * ShapeTokens.borderCard / 40);
    final shadow = Offset(-line * 1.2, line * 1.2);
    canvas
      ..save()
      ..translate(box.left, box.top);

    // Shoulders, with a hard shadow.
    final shoulders = RRect.fromRectAndCorners(
      Rect.fromLTRB(w * 0.06, h * 0.64, w * 0.94, h * 1.02),
      topLeft: Radius.circular(w * 0.32),
      topRight: Radius.circular(w * 0.32),
    );
    canvas
      ..drawRRect(shoulders.shift(shadow), _fill(tokens.hibr))
      ..drawRRect(shoulders, _fill(_shirt))
      ..drawRRect(shoulders, _ink(line));
    _drawNeckAccessory(canvas, w, h, line, view);

    // The head tilts when asleep.
    final asleep = view?.asleep ?? false;
    final center = Offset(w * 0.5, h * 0.38);
    final radius = w * 0.3;
    canvas.save();
    if (asleep) {
      canvas
        ..translate(center.dx, center.dy + radius)
        ..rotate(-0.22)
        ..translate(-center.dx, -center.dy - radius);
    }
    canvas
      ..drawCircle(center + shadow, radius, _fill(tokens.hibr))
      ..drawCircle(center, radius, _fill(_skin));
    _drawHair(canvas, center, radius, line);
    canvas.drawCircle(center, radius, _ink(line));
    _drawFace(canvas, center, radius, line, view);
    _drawHeadAccessory(canvas, center, radius, line, view);
    canvas.restore();

    if (asleep) _drawSnore(canvas, center, radius, line);
    if (view?.headphones ?? false) _drawMusic(canvas, center, radius, line);
    canvas.restore();
  }

  void _drawHair(Canvas canvas, Offset c, double r, double line) {
    if (look.accessory == Accessory.headscarf) {
      final scarf = Path()
        ..addArc(
          Rect.fromCircle(center: c, radius: r * 1.12),
          math.pi * 0.9,
          math.pi * 1.2,
        )
        ..close();
      canvas
        ..drawPath(scarf, _fill(_shirt))
        ..drawPath(scarf, _ink(line));
      return;
    }
    final hair = Path()
      ..addArc(
        Rect.fromCircle(center: c, radius: r),
        math.pi * 1.08,
        math.pi * 0.84,
      )
      ..close();
    canvas.drawPath(hair, _fill(tokens.hibr));
  }

  void _drawFace(
    Canvas canvas,
    Offset c,
    double r,
    double line,
    PassengerView? view,
  ) {
    final mood = view?.mood ?? 0;
    final asleep = view?.asleep ?? false;
    final eyeY = c.dy + r * 0.02;
    final eyeDx = r * 0.36;
    final ink = _ink(line);
    if (asleep) {
      for (final dx in [-eyeDx, eyeDx]) {
        canvas.drawArc(
          Rect.fromCenter(
            center: Offset(c.dx + dx, eyeY),
            width: r * 0.3,
            height: r * 0.2,
          ),
          0,
          math.pi,
          false,
          ink,
        );
      }
    } else {
      final open = view?.waking ?? false ? 0.5 : 1.0;
      for (final dx in [-eyeDx, eyeDx]) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(c.dx + dx, eyeY),
            width: r * 0.16,
            height: r * 0.22 * open,
          ),
          _fill(tokens.hibr),
        );
      }
    }

    // Brows: frowning from mood 2, sharper at 3.
    if (mood >= 2) {
      final tilt = mood == 3 ? r * 0.16 : r * 0.08;
      for (final side in [-1.0, 1.0]) {
        final inner = Offset(c.dx + side * r * 0.14, eyeY - r * 0.24 + tilt);
        final outer = Offset(c.dx + side * r * 0.5, eyeY - r * 0.3);
        canvas.drawLine(inner, outer, ink);
      }
    }
    if (mood == 3) {
      final cheek = _fill(tokens.danger.withValues(alpha: 0.35));
      for (final side in [-1.0, 1.0]) {
        canvas.drawCircle(
          Offset(c.dx + side * r * 0.55, c.dy + r * 0.35),
          r * 0.16,
          cheek,
        );
      }
    }
    if (mood == 2) {
      // A sweat drop at the temple.
      final top = Offset(c.dx + r * 0.78, c.dy - r * 0.35);
      final drop = Path()
        ..moveTo(top.dx, top.dy)
        ..quadraticBezierTo(
          top.dx + r * 0.16,
          top.dy + r * 0.3,
          top.dx,
          top.dy + r * 0.34,
        )
        ..quadraticBezierTo(top.dx - r * 0.16, top.dy + r * 0.3, top.dx, top.dy)
        ..close();
      canvas
        ..drawPath(drop, _fill(tokens.bubbleThanks))
        ..drawPath(drop, _ink(line * 0.6));
    }

    // The mouth.
    final mouthY = c.dy + r * 0.45;
    final talking = (view?.talking ?? false) && !asleep;
    if (talking && (_clock * 6).floor().isEven) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(c.dx, mouthY),
          width: r * 0.36,
          height: r * 0.26,
        ),
        _fill(tokens.hibr),
      );
      return;
    }
    final mouth = Rect.fromCenter(
      center: Offset(c.dx, mouthY),
      width: r * 0.6,
      height: r * 0.3,
    );
    switch (asleep ? 1 : mood) {
      case 0:
        canvas.drawArc(
          mouth.shift(Offset(0, -r * 0.1)),
          0.15,
          math.pi - 0.3,
          false,
          ink,
        );
      case 1:
        canvas.drawLine(
          Offset(mouth.left + r * 0.1, mouthY),
          Offset(mouth.right - r * 0.1, mouthY),
          ink,
        );
      default:
        canvas.drawArc(
          mouth.shift(Offset(0, r * 0.1)),
          math.pi + 0.2,
          math.pi - 0.4,
          false,
          ink,
        );
    }
  }

  void _drawHeadAccessory(
    Canvas canvas,
    Offset c,
    double r,
    double line,
    PassengerView? view,
  ) {
    switch (look.accessory) {
      case Accessory.cap:
        final crown = Path()
          ..addArc(
            Rect.fromCircle(center: c, radius: r * 1.02),
            math.pi,
            math.pi,
          )
          ..close();
        final brim = RRect.fromRectAndRadius(
          Rect.fromLTWH(c.dx - r * 1.15, c.dy - r * 0.12, r * 1.3, r * 0.2),
          Radius.circular(r * 0.1),
        );
        final cap = look.shirt == Shirt.young ? tokens.danger : tokens.primary;
        canvas
          ..drawPath(crown, _fill(cap))
          ..drawPath(crown, _ink(line))
          ..drawRRect(brim, _fill(cap))
          ..drawRRect(brim, _ink(line));
      case Accessory.glasses:
        final ink = _ink(line * 0.8);
        for (final dx in [-r * 0.36, r * 0.36]) {
          canvas.drawCircle(Offset(c.dx + dx, c.dy + r * 0.02), r * 0.22, ink);
        }
        canvas.drawLine(
          Offset(c.dx - r * 0.14, c.dy),
          Offset(c.dx + r * 0.14, c.dy),
          ink,
        );
      case Accessory.headphones:
        if (view?.headphones ?? true) _drawHeadphones(canvas, c, r, line);
      case Accessory.none ||
          Accessory.tie ||
          Accessory.scarf ||
          Accessory.headscarf:
        break;
    }
    // A headphones passenger whose look isn't headphones still wears them
    // when the view says so.
    if (look.accessory != Accessory.headphones && (view?.headphones ?? false)) {
      _drawHeadphones(canvas, c, r, line);
    }
  }

  void _drawHeadphones(Canvas canvas, Offset c, double r, double line) {
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * 1.1),
      math.pi * 1.05,
      math.pi * 0.9,
      false,
      _ink(line * 1.6),
    );
    for (final side in [-1.0, 1.0]) {
      final cup = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(c.dx + side * r * 1.02, c.dy + r * 0.05),
          width: r * 0.32,
          height: r * 0.5,
        ),
        Radius.circular(r * 0.12),
      );
      canvas
        ..drawRRect(cup, _fill(tokens.danger))
        ..drawRRect(cup, _ink(line));
    }
  }

  void _drawNeckAccessory(
    Canvas canvas,
    double w,
    double h,
    double line,
    PassengerView? view,
  ) {
    switch (look.accessory) {
      case Accessory.tie:
        final tie = Path()
          ..moveTo(w * 0.5, h * 0.68)
          ..lineTo(w * 0.58, h * 0.78)
          ..lineTo(w * 0.5, h * 1.0)
          ..lineTo(w * 0.42, h * 0.78)
          ..close();
        canvas
          ..drawPath(tie, _fill(tokens.danger))
          ..drawPath(tie, _ink(line * 0.8));
      case Accessory.scarf:
        final scarf = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.28, h * 0.64, w * 0.44, h * 0.08),
          Radius.circular(h * 0.04),
        );
        canvas
          ..drawRRect(scarf, _fill(tokens.danger))
          ..drawRRect(scarf, _ink(line * 0.8));
      case Accessory.headphones when !(view?.headphones ?? true):
        // Around the neck while listening.
        canvas.drawArc(
          Rect.fromCenter(
            center: Offset(w * 0.5, h * 0.66),
            width: w * 0.5,
            height: h * 0.14,
          ),
          0,
          math.pi,
          false,
          _ink(line * 1.4),
        );
      default:
        break;
    }
  }

  /// "z z" above the head, drawn as zigzags.
  void _drawSnore(Canvas canvas, Offset c, double r, double line) {
    final rise = (_clock % 1.6) / 1.6 * r * 0.3;
    for (final (i, size) in [r * 0.28, r * 0.2].indexed) {
      final origin = Offset(
        c.dx + r * (0.7 + i * 0.35),
        c.dy - r * (1.0 + i * 0.4) - rise,
      );
      final z = Path()
        ..moveTo(origin.dx, origin.dy)
        ..lineTo(origin.dx + size, origin.dy)
        ..lineTo(origin.dx, origin.dy + size)
        ..lineTo(origin.dx + size, origin.dy + size);
      canvas.drawPath(z, _ink(line * 0.8));
    }
  }

  /// Music marks by the ears.
  void _drawMusic(Canvas canvas, Offset c, double r, double line) {
    final bob = math.sin(_clock * 4) * r * 0.06;
    for (final side in [-1.0, 1.0]) {
      final stem = Offset(c.dx + side * r * 1.45, c.dy - r * 0.55 + bob);
      canvas
        ..drawLine(stem, stem + Offset(0, r * 0.4), _ink(line * 0.7))
        ..drawCircle(
          stem + Offset(-r * 0.08, r * 0.42),
          r * 0.1,
          _fill(tokens.hibr),
        );
    }
  }
}
