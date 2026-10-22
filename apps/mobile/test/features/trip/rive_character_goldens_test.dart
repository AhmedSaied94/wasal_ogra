// The owner's character in each mood and pose, at the near-row and back-row
// face sizes (tasks.md T058, contracts/rive-character.md "Tests"), drawn
// with `Factory.flutter`. Fails until `assets/rive/passenger.riv` is
// committed (owner action T059). Generated on Linux; CI's run is the
// reference.
@Tags(['rive'])
library;

import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rive/rive.dart' as rive;
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/domain/skin_looks.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/scene/passenger_art.dart';
import 'package:wassal/features/trip/presentation/scene/rive_passenger_art.dart';

/// The poses: each mood, then asleep, headphones and talking.
const _poses =
    <String, ({int mood, bool asleep, bool headphones, bool talking})>{
      'mood0': (mood: 0, asleep: false, headphones: false, talking: false),
      'mood1': (mood: 1, asleep: false, headphones: false, talking: false),
      'mood2': (mood: 2, asleep: false, headphones: false, talking: false),
      'mood3': (mood: 3, asleep: false, headphones: false, talking: false),
      'asleep': (mood: 0, asleep: true, headphones: false, talking: false),
      'headphones': (mood: 0, asleep: false, headphones: true, talking: false),
      'talking': (mood: 0, asleep: false, headphones: false, talking: true),
    };

/// The face's height for its width, as the scene draws it.
const _faceAspect = 1.2;

class _ArtPainter extends CustomPainter {
  _ArtPainter(this.art);

  final PassengerArt art;

  @override
  void paint(Canvas canvas, Size size) =>
      art.render(canvas, Offset.zero & size);

  @override
  bool shouldRepaint(_ArtPainter oldDelegate) => false;
}

void main() {
  late rive.File file;

  setUpAll(() async {
    await rive.RiveNative.init();
    final bytes = io.File(passengerRiveAsset).readAsBytesSync();
    file = (await rive.File.decode(bytes, riveFactory: rive.Factory.flutter))!;
  });

  tearDownAll(() => file.dispose());

  for (final MapEntry(key: name, value: pose) in _poses.entries) {
    for (final width in [nearFaceMin, backFaceMin]) {
      testWidgets('$name at ${width.toInt()} pt', (tester) async {
        final art =
            RivePassengerArtFactory(file)
                .create(skinLooks['worker_blue']!, WassalTokens.standard)
              ..update(
                PassengerView(
                  passengerId: 'p1',
                  seatId: 'A_r',
                  presence: PresenceView.aboard,
                  look: skinLooks['worker_blue']!,
                  slot: 0,
                  mood: pose.mood,
                  talking: pose.talking,
                  asleep: pose.asleep,
                  waking: false,
                  headphones: pose.headphones,
                  attentive: false,
                  nearStopPulse: false,
                  dropMeHere: false,
                  ledgerBadge: null,
                  outcome: null,
                ),
              );
        addTearDown(art.dispose);
        // Past the 200 ms blend, in frames.
        for (var i = 0; i < 30; i++) {
          art.advance(1 / 60);
        }
        await tester.pumpWidget(
          Center(
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size(width, width * _faceAspect),
                painter: _ArtPainter(art),
              ),
            ),
          ),
        );
        await expectLater(
          find.byType(RepaintBoundary).first,
          matchesGoldenFile('goldens/rive_${name}_${width.toInt()}.png'),
        );
      });
    }
  }
}
