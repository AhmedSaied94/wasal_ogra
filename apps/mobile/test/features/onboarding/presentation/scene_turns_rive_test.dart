// The scene player over the real scenes file (specs/012.5-m22-animated-
// scenes, contracts/rive-scenes.md "Drawing"): an animated panel draws its
// artboard as the drawing sits, and under reduced motion it draws the
// drawing. Needs Rive's Linux library.
@Tags(['rive'])
library;

import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rive/rive.dart' as rive;
import 'package:wassal/core/art/rive_art.dart';
import 'package:wassal/core/art/rive_scenes.dart';
import 'package:wassal/features/onboarding/domain/first_session.dart';
import 'package:wassal/features/onboarding/presentation/scene_player.dart';

import '../../../helpers/design_component.dart';
import '../../../helpers/economy.dart';

void main() {
  late rive.File file;
  late RiveArt scenes;

  setUpAll(() async {
    await rive.RiveNative.init();
    final bytes = io.File(riveScenesAsset).readAsBytesSync();
    file = (await rive.File.decode(bytes, riveFactory: rive.Factory.flutter))!;
    scenes = checkRiveArt(file, sceneContract);
  });

  tearDownAll(() => file.dispose());

  Future<void> pump(WidgetTester tester, {bool reducedMotion = false}) =>
      pumpDesignComponent(
        tester,
        RiveArtScope(
          art: null,
          scenes: scenes,
          child: ScenePlayer(
            title: 'أول شغلانة',
            scene: sceneOf(sampleContent(), 'opening')!,
            driverName: 'الأسطى',
            onFinished: () {},
          ),
        ),
        center: false,
        reducedMotion: reducedMotion,
        overrides: [
          scenePanelsProvider.overrideWithValue(ScenePanels.of(scenes)),
        ],
      );

  testWidgets('an animated panel draws its artboard, filling the panel from '
      'the bottom', (tester) async {
    await pump(tester);
    await tester.pump(const Duration(milliseconds: 500));
    final widget = tester.widget<rive.RiveWidget>(find.byType(rive.RiveWidget));
    expect(widget.fit, rive.Fit.cover);
    expect(widget.alignment, Alignment.bottomCenter);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('under reduced motion: no Rive, the drawing', (tester) async {
    await pump(tester, reducedMotion: true);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(rive.RiveWidget), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
