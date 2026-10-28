// The scenes' Rive panels as the app draws them (specs/012.5-m22-animated-
// scenes, FR-021): each panel's first frame beside its drawing, which it
// starts from. Drawn with `Factory.flutter`. Generated on Linux; CI's run is
// the reference. Needs Rive's Linux library.
@Tags(['rive'])
library;

import 'dart:io' as io;

import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rive/rive.dart' as rive;
import 'package:wassal/core/art/rive_scenes.dart';

/// `scene.sky`, the panel's ground.
const _sky = Color(0xFFE8F4FB);

/// The gap between the two halves of a sheet.
const double _gap = 16;

class _Paint extends CustomPainter {
  _Paint(this.draw);

  final void Function(Canvas canvas) draw;

  @override
  void paint(Canvas canvas, Size size) => draw(canvas);

  @override
  bool shouldRepaint(_Paint oldDelegate) => false;
}

void main() {
  late rive.File file;

  setUpAll(() async {
    await rive.RiveNative.init();
    final bytes = io.File(riveScenesAsset).readAsBytesSync();
    file = (await rive.File.decode(bytes, riveFactory: rive.Factory.flutter))!;
  });

  tearDownAll(() => file.dispose());

  for (final slug in scenePanelSlugs) {
    testWidgets('$slug: its first frame, beside its drawing', (tester) async {
      final drawing = (await tester.runAsync(
        () => vg.loadPicture(
          SvgStringLoader(
            io.File('assets/illustrations/panels/$slug.svg').readAsStringSync(),
          ),
          null,
        ),
      ))!;
      addTearDown(drawing.picture.dispose);

      final artboard = file.artboard(slug)!;
      final machine = artboard.stateMachine(scenePanelMachine)!;
      final model = file.defaultArtboardViewModel(artboard)!;
      final instance = model.createDefaultInstance()!;
      model.dispose();
      machine
        ..bindViewModelInstance(instance)
        ..advanceAndApply(0);
      addTearDown(() {
        instance.dispose();
        machine.dispose();
        artboard.dispose();
      });

      tester.view
        ..physicalSize = Size(
          scenePanelSize.width * 2 + _gap,
          scenePanelSize.height,
        )
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              child: ColoredBox(
                color: _sky,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: _gap,
                  children: [
                    CustomPaint(
                      size: scenePanelSize,
                      painter: _Paint((canvas) {
                        final renderer = rive.Renderer.make(canvas);
                        renderer.align(
                          rive.Fit.fill,
                          Alignment.topLeft,
                          rive.AABB.fromValues(
                            0,
                            0,
                            scenePanelSize.width,
                            scenePanelSize.height,
                          ),
                          artboard.bounds,
                          1,
                        );
                        artboard.draw(renderer);
                        renderer.dispose();
                      }),
                    ),
                    CustomPaint(
                      size: scenePanelSize,
                      painter: _Paint((canvas) {
                        canvas.drawPicture(drawing.picture);
                      }),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await expectLater(
        find.byType(RepaintBoundary).first,
        matchesGoldenFile('goldens/rive_scene_$slug.png'),
      );
    });
  }
}
