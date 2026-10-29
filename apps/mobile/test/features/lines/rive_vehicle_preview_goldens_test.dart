// The BuyVehicle preview as the app draws it with `wassal.riv` (specs/
// 014-m09-lines-vehicles, FR-031, T102, R1-7): the 236×150 `Vehicle`
// artboard inside a 322×150 box keeps its aspect, centred, rather than
// stretched across it. Drawn with `Factory.flutter`. Generated on Linux;
// CI's run is the reference.
@Tags(['rive'])
library;

import 'dart:io' as io;

import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rive/rive.dart' as rive;
import 'package:wassal/core/art/rive_art.dart';
import 'package:wassal/features/lines/presentation/vehicle_preview.dart';

void main() {
  late rive.File file;
  late RiveArt art;

  setUpAll(() async {
    await rive.RiveNative.init();
    file = (await rive.File.decode(
      io.File(riveArtAsset).readAsBytesSync(),
      riveFactory: rive.Factory.flutter,
    ))!;
    art = checkRiveArt(file);
  });

  tearDownAll(() => file.dispose());

  testWidgets('the vehicle keeps the artboard\'s aspect', (tester) async {
    // The sheet's content width (390 − 2 × 16) and the preview's height.
    tester.view
      ..physicalSize = const Size(358, VehiclePreview.height)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.rtl,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(358, VehiclePreview.height)),
          child: RiveArtScope(
            art: art,
            child: const RepaintBoundary(
              child: VehiclePreview(vehicle: VehicleId.microOld),
            ),
          ),
        ),
      ),
    );
    // Let the state machine settle.
    await tester.pump(const Duration(seconds: 1));
    await expectLater(
      find.byType(RepaintBoundary).first,
      matchesGoldenFile('goldens/rive_vehicle_preview.png'),
    );
  });
}
