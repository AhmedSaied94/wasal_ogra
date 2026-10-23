import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/domain/looks.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/scene/svg_passenger_art.dart';
import 'package:wassal/features/trip/presentation/trip_motion.dart';

// The passengers' static art (research R17): each look's SVG decoded once,
// and the motion and marks it gets in code.

PassengerView _view({
  PresenceView presence = PresenceView.aboard,
  int mood = 0,
  bool asleep = false,
  bool headphones = false,
  AlightOutcome? outcome,
}) => PassengerView(
  passengerId: 'p1',
  seatId: 'A_r',
  presence: presence,
  look: looks['regular']!,
  slot: 0,
  mood: mood,
  talking: false,
  asleep: asleep,
  waking: false,
  headphones: headphones,
  attentive: false,
  nearStopPulse: false,
  dropMeHere: false,
  ledgerBadge: null,
  outcome: outcome,
);

ArtPose _pose(
  PassengerView view, {
  double at = 0,
  bool reduceMotion = false,
  String look = 'regular',
}) => artPoseOf(looks[look]!, view, at, reduceMotion: reduceMotion);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every passenger SVG shares the view box, head centre at 0,0', () {
    final viewBox = RegExp('viewBox="([^"]+)"');
    for (final look in looks.values) {
      final svg = File(look.svg).readAsStringSync();
      expect(
        viewBox.firstMatch(svg)?.group(1),
        '-70 -66 140 156',
        reason: look.svg,
      );
    }
    expect(passengerViewBox, const Rect.fromLTWH(-70, -66, 140, 156));
  });

  test('preload decodes every look once, at the view box size', () async {
    await SvgPassengerArtFactory.preload();
    for (final look in looks.values) {
      final picture = SvgPassengerArtFactory.pictureOf(look);
      expect(picture, isNotNull, reason: look.id);
      expect(picture!.size, passengerViewBox.size, reason: look.id);
      expect(
        SvgPassengerArtFactory.pictureOf(look),
        same(picture),
        reason: look.id,
      );
    }
  });

  test('the art draws into the head square once loaded', () async {
    await SvgPassengerArtFactory.preload();
    final art = const SvgPassengerArtFactory().create(looks['hagga']!)
      ..update(_view(mood: 3, asleep: true, headphones: true))
      ..advance(0.4);
    final recorder = PictureRecorder();
    art.render(Canvas(recorder), const Rect.fromLTWH(10, 20, 84, 84));
    final picture = recorder.endRecording();
    expect(picture.approximateBytesUsed, greaterThan(0));
    picture.dispose();
    art.dispose();
  });

  group('motion', () {
    test('an idle bob of 2 pt every 1.2 s', () {
      final period = TripMotion.artBob.inMicroseconds / 1e6;
      expect(_pose(_view()).offset, Offset.zero);
      expect(_pose(_view(), at: period / 2).offset.dy, closeTo(-2, 1e-9));
      expect(_pose(_view(), at: period).offset.dy, closeTo(0, 1e-9));
      for (var t = 0.0; t < period; t += 0.05) {
        final dy = _pose(_view(), at: t).offset.dy;
        expect(dy, inInclusiveRange(-2, 0));
      }
    });

    test('a fight shakes 6 pt side to side', () {
      final fight = _view(
        presence: PresenceView.leaving,
        outcome: AlightOutcome.fight,
      );
      var reach = 0.0;
      for (var t = 0.0; t < 0.3; t += 0.005) {
        reach = math.max(reach, _pose(fight, at: t).offset.dx.abs());
      }
      expect(reach, closeTo(6, 0.1));
      expect(_pose(fight).tinted, isTrue);
      expect(
        _pose(_view(outcome: AlightOutcome.thanked), at: 0.02).offset.dx,
        0,
      );
    });

    test('under reduced motion nothing moves and the marks hold still', () {
      final view = _view(mood: 3, asleep: true, outcome: AlightOutcome.fight);
      for (final t in [0.0, 0.1, 0.6, 1.3]) {
        final pose = _pose(view, at: t, reduceMotion: true);
        expect(pose.offset, Offset.zero);
        expect(pose.marksPhase, 0);
        expect(pose.snoring, isTrue);
        expect(pose.sweating, isTrue);
      }
    });
  });

  group('marks', () {
    test('asleep: tilted 18° with «z», except the sleeper drawn asleep', () {
      final pose = _pose(_view(asleep: true));
      expect(pose.tilt, closeTo(18 * math.pi / 180, 1e-12));
      expect(pose.snoring, isTrue);
      final sleeper = _pose(_view(asleep: true), look: 'sleeper');
      expect(sleeper.tilt, 0);
      expect(sleeper.snoring, isTrue);
      expect(_pose(_view()).snoring, isFalse);
      expect(_pose(_view()).tilt, 0);
    });

    test('mood 2–3: the sweat drop and the red tint', () {
      for (final mood in [0, 1]) {
        expect(_pose(_view(mood: mood)).sweating, isFalse);
        expect(_pose(_view(mood: mood)).tinted, isFalse);
      }
      for (final mood in [2, 3]) {
        expect(_pose(_view(mood: mood)).sweating, isTrue);
        expect(_pose(_view(mood: mood)).tinted, isTrue);
      }
    });

    test('headphones on: music notes, but not in sleep', () {
      expect(_pose(_view(headphones: true)).music, isTrue);
      expect(_pose(_view()).music, isFalse);
      expect(_pose(_view(headphones: true, asleep: true)).music, isFalse);
    });
  });

  test("the art's font stacks become the app's families", () {
    const art =
        '<text font-family="Readex Pro, sans-serif">x</text>'
        '<text font-family="Marhey, sans-serif">z</text>';
    expect(
      SvgPassengerArtFactory.withAppFonts(art),
      '<text font-family="${TypeTokens.readexPro}">x</text>'
      '<text font-family="${TypeTokens.marhey}">z</text>',
    );
  });
}
