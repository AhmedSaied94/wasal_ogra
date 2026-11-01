import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';

import '../../design/design_check.dart';
import '../../design/samples/scene_viewer.dart';

// `SceneViewer` as the app draws it, beside docs/design/png/SceneViewer.png
// (specs/015-m10-apartment-story, T094), in both digit styles.

void main() {
  for (final digits in DigitStyle.values) {
    testWidgets('SceneViewer, ${digits.name}', (tester) async {
      await pumpSceneViewer(tester, digits: digits);
      await expectDesignGolden(
        tester,
        find.byType(WassalApp),
        'SceneViewer',
        digits,
      );
    });
  }
}
