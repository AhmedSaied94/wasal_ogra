// The passengers' static art (research R17): each look's SVG, decoded once
// and drawn into the seat, with its motion in code. It stands in wherever
// Rive doesn't draw a passenger, and in every trip golden.
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Picture;

import 'package:content_models/content_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/domain/looks.dart';
import 'package:wassal/features/trip/domain/poses.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/scene/passenger_art.dart';
import 'package:wassal/features/trip/presentation/trip_motion.dart';

/// The sweat drop's round bottom, in the art's units.
const _sweatDropRound = 5.0;

/// Every passenger SVG shares `viewBox="-70 -66 140 156"`, with the head's
/// centre at its origin and a head radius of [rigHeadRadius]. The decoded
/// picture starts at the view box's corner.
const passengerViewBox = Rect.fromLTWH(-70, -66, 140, 156);

/// The look whose art is already asleep (its head is tilted in the file).
const _asleepLook = 'sleeper';

final class SvgPassengerArtFactory implements PassengerArtFactory {
  const SvgPassengerArtFactory();

  static final _pictures = <String, PictureInfo>{};
  static final _loads = <String, Future<void>>{};

  /// Decodes every look's art once. A passenger draws nothing until its
  /// look is in, so tests await this (in `runAsync`) before their first
  /// frame.
  /// A decode still in flight starts again: one begun where nothing could
  /// finish it (a test's fake clock) would hold the wait forever.
  static Future<void> preload() => Future.wait([
    for (final look in looks.values)
      if (!_pictures.containsKey(look.svg))
        _loads[look.svg] = _decode(look.svg),
  ]);

  /// The decoded art of [look], or null until it has loaded.
  static PictureInfo? pictureOf(Look look) {
    unawaited(_load(look.svg));
    return _pictures[look.svg];
  }

  static Future<void> _load(String asset) => _loads[asset] ??= _decode(asset);

  static Future<void> _decode(String asset) async {
    try {
      final source = await rootBundle.loadString(asset);
      _pictures[asset] = await vg.loadPicture(
        SvgStringLoader(withAppFonts(source)),
        null,
      );
      // A look without its file draws nothing; the trip still plays.
    } on Object catch (error) {
      debugPrint('$asset: $error');
    }
  }

  /// The art names the design's font stacks («Readex Pro, sans-serif», the
  /// notes some passengers hold); the SVG compiler takes the attribute as
  /// one family name, so point it at the app's families.
  @visibleForTesting
  static String withAppFonts(String svg) => svg
      .replaceAll(
        'font-family="Readex Pro, sans-serif"',
        'font-family="${TypeTokens.readexPro}"',
      )
      .replaceAll(
        'font-family="Marhey, sans-serif"',
        'font-family="${TypeTokens.marhey}"',
      );

  @override
  PassengerArt create(
    Look look, {
    SeatRow row = SeatRow.a,
    bool reduceMotion = false,
  }) {
    unawaited(_load(look.svg));
    return SvgPassengerArt(look);
  }
}

/// Where the art sits and what it shows at a moment: offsets in points,
/// everything else in the art's own units.
@immutable
final class ArtPose {
  const ArtPose({
    required this.offset,
    required this.tilt,
    required this.tinted,
    required this.snoring,
    required this.sweating,
    required this.music,
    required this.marksPhase,
  });

  /// The bob and the shake.
  final Offset offset;

  /// The head's tilt, in radians.
  final double tilt;

  /// Frowning or angry: the face reddens and sweats.
  final bool tinted;
  final bool snoring;
  final bool sweating;
  final bool music;

  /// 0–1 around the marks' float; 0 under reduced motion.
  final double marksPhase;
}

/// How [view] is drawn [clockS] seconds after the art was made.
ArtPose artPoseOf(
  Look look,
  PassengerView? view,
  double clockS, {
  required bool reduceMotion,
}) {
  final t = reduceMotion ? 0.0 : clockS;
  final asleep = view?.asleep ?? false;
  final fighting = view?.outcome == AlightOutcome.fight;
  final bobPeriod = TripMotion.artBob.inMicroseconds / 1e6;
  final shakePeriod = TripMotion.shake.inMicroseconds / 1e6 / 4;
  final bob =
      -TripMotion.artBobReach * (1 - math.cos(2 * math.pi * t / bobPeriod)) / 2;
  final shake = fighting
      ? TripMotion.shakeAmplitude * math.sin(2 * math.pi * t / shakePeriod)
      : 0.0;
  final mood = view?.mood ?? 0;
  return ArtPose(
    offset: Offset(shake, bob),
    tilt: asleep && look.id != _asleepLook ? TripMotion.artSleepTilt : 0,
    tinted: mood >= 2 || fighting,
    snoring: asleep,
    sweating: mood >= 2 || fighting,
    music: (view?.headphones ?? false) && !asleep,
    marksPhase: (t / (2 * bobPeriod)) % 1,
  );
}

/// One passenger's look, from its SVG.
final class SvgPassengerArt implements PassengerArt {
  SvgPassengerArt(this.look);

  final Look look;

  @override
  bool reduceMotion = false;

  PassengerView? _view;
  double _clock = 0;

  /// The pose last drawn, for tests.
  ArtPose get pose =>
      artPoseOf(look, _view, _clock, reduceMotion: reduceMotion);

  @override
  void update(PassengerView view) => _view = view;

  /// The static art has no one-shots: boarding and getting off slide and
  /// fade in code (passenger_component.dart), and the glow is the scene's.
  @override
  void play(CharacterTrigger trigger) {}

  @override
  void advance(double dt) => _clock += dt;

  @override
  void dispose() {}

  @override
  void render(Canvas canvas, Rect box) {
    final picture = SvgPassengerArtFactory.pictureOf(look)?.picture;
    if (picture == null) return;
    final pose = this.pose;
    canvas
      ..save()
      ..translate(
        box.center.dx + pose.offset.dx,
        box.center.dy + pose.offset.dy,
      )
      ..scale(box.width / (2 * rigHeadRadius));
    if (pose.tinted) canvas.saveLayer(passengerViewBox, Paint());
    if (pose.tilt == 0) {
      _draw(canvas, picture);
    } else {
      _drawTilted(canvas, picture, pose.tilt);
    }
    if (pose.tinted) {
      canvas
        ..drawCircle(Offset.zero, rigHeadRadius, _tint)
        ..restore();
    }
    if (pose.snoring) _drawSnore(canvas, pose.marksPhase);
    if (pose.sweating) _drawSweat(canvas, pose.marksPhase);
    if (pose.music) _drawMusic(canvas, pose.marksPhase);
    canvas.restore();
  }

  static void _draw(Canvas canvas, Picture picture) => canvas
    ..save()
    ..translate(passengerViewBox.left, passengerViewBox.top)
    ..drawPicture(picture)
    ..restore();

  /// The head tilts on the shoulders: the body is drawn as it is, the head
  /// (a circle a little wider than the face, for hair and hats) turned
  /// about its centre.
  static void _drawTilted(Canvas canvas, Picture picture, double tilt) {
    final head = Path()
      ..addOval(Rect.fromCircle(center: Offset.zero, radius: _headClip));
    canvas
      ..save()
      ..clipPath(
        Path.combine(
          PathOperation.difference,
          Path()..addRect(passengerViewBox),
          head,
        ),
      );
    _draw(canvas, picture);
    canvas
      ..restore()
      ..save()
      ..clipPath(head)
      ..rotate(tilt);
    _draw(canvas, picture);
    canvas.restore();
  }

  /// Hair and headwear reach a little past the face.
  static const double _headClip = rigHeadRadius + 8;

  static final _tint = Paint()
    ..color = ColorTokens.danger.withValues(alpha: 0.3)
    ..blendMode = BlendMode.srcATop;

  static Paint _stroke(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  /// Two «z» marks rising to the end side (`C-Trip` box 37), painted, not
  /// written: the scene draws no text.
  static void _drawSnore(Canvas canvas, double phase) {
    for (final (i, (at, side)) in const [
      (Offset(30, -42), 14.0),
      (Offset(48, -66), 18.0),
    ].indexed) {
      final dy = -2 * math.sin(2 * math.pi * (phase + i / 4));
      final o = at.translate(0, dy - side);
      canvas.drawPath(
        Path()
          ..moveTo(o.dx, o.dy)
          ..lineTo(o.dx + side, o.dy)
          ..lineTo(o.dx, o.dy + side)
          ..lineTo(o.dx + side, o.dy + side),
        _stroke(ColorTokens.lavender, side * 0.2),
      );
    }
  }

  /// A drop on the temple, sliding down a little.
  static void _drawSweat(Canvas canvas, double phase) {
    final c = Offset(34, -22 + 3 * phase);
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy - 8)
        ..cubicTo(c.dx + 2, c.dy - 4, c.dx + 5, c.dy - 1, c.dx + 5, c.dy + 2)
        ..arcToPoint(
          Offset(c.dx - 5, c.dy + 2),
          radius: const Radius.circular(_sweatDropRound),
        )
        ..cubicTo(c.dx - 5, c.dy - 1, c.dx - 2, c.dy - 4, c.dx, c.dy - 8)
        ..close(),
      Paint()..color = DesignExtras.passengerSweat,
    );
  }

  /// Two eighth notes by the start-side ear.
  static void _drawMusic(Canvas canvas, double phase) {
    final fill = Paint()..color = ColorTokens.lavender;
    final stem = _stroke(ColorTokens.lavender, 2.5);
    for (final (i, at) in const [Offset(-56, -26), Offset(-44, -50)].indexed) {
      final o = at.translate(0, -3 * math.sin(2 * math.pi * (phase + i / 3)));
      canvas
        ..save()
        ..translate(o.dx, o.dy)
        ..rotate(-0.35)
        ..drawOval(const Rect.fromLTWH(-5, -3.5, 10, 7), fill)
        ..restore()
        ..drawLine(o.translate(4, -1), o.translate(4, -16), stem)
        ..drawLine(o.translate(4, -16), o.translate(10, -11), stem);
    }
  }
}
