// A panel's fallback over the real scenes file (specs/012.5-m22-animated-
// scenes, spec FR-006, contracts/rive-scenes.md "Checking an artboard"): an
// artboard that fails its check draws its drawing, alone, and reduced motion
// draws every drawing. Needs Rive's Linux library.
@Tags(['rive'])
library;

import 'dart:io' as io;

import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rive/rive.dart' as rive;
import 'package:wassal/core/art/panel_art.dart';
import 'package:wassal/core/art/rive_art.dart';
import 'package:wassal/core/art/rive_scenes.dart';

import '../../helpers/design_component.dart';

Future<void> _pump(
  WidgetTester tester,
  String slug,
  RiveArt scenes, {
  bool reducedMotion = false,
}) => pumpDesignComponent(
  tester,
  RiveArtScope(
    art: null,
    scenes: scenes,
    child: SizedBox(
      width: 358,
      height: 540,
      child: PanelArt(slug: slug, speakers: const [], animate: true),
    ),
  ),
  reducedMotion: reducedMotion,
);

void main() {
  late rive.File file;

  setUpAll(() async {
    await rive.RiveNative.init();
    final bytes = io.File(riveScenesAsset).readAsBytesSync();
    file = (await rive.File.decode(bytes, riveFactory: rive.Factory.flutter))!;
  });

  tearDownAll(() => file.dispose());

  testWidgets('opening_key failing its check: its drawing, and opening_stand '
      'animates', (tester) async {
    final contract = RiveContract(
      asset: sceneContract.asset,
      artboards: {
        ...sceneContract.artboards,
        'opening_key': (
          size: const Size(360, 540),
          machine: scenePanelMachine,
          viewModel: scenePanelViewModel,
          properties: sceneContract.artboards['opening_key']!.properties,
        ),
      },
      known: sceneContract.known,
    );
    final scenes = checkRiveArt(file, contract);
    await _pump(tester, 'opening_key', scenes);
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.byType(rive.RiveWidget), findsNothing);
    await _pump(tester, 'opening_stand', scenes);
    expect(find.byType(rive.RiveWidget), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('under reduced motion: every panel its drawing, though every '
      'artboard is usable', (tester) async {
    final scenes = checkRiveArt(file, sceneContract);
    expect(scenes.usable, {...scenePanelSlugs});
    for (final slug in scenePanelSlugs) {
      await _pump(tester, slug, scenes, reducedMotion: true);
      expect(find.byType(SvgPicture), findsOneWidget, reason: slug);
      expect(find.byType(rive.RiveWidget), findsNothing, reason: slug);
    }
  });
}
