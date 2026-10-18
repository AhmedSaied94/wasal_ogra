import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';

import '../helpers/pump_app.dart';
import '../helpers/screens.dart';
import '../helpers/surfaces.dart';

// US1 goldens (FR-040): every shell screen at both surfaces, both ends of
// the text-scale clamp and both digit styles, in RTL. Regenerate with
// `fvm flutter test --update-goldens test/goldens` and inspect every PNG.

void main() {
  for (final screen in shellScreens()) {
    for (final surface in Surface.values) {
      for (final scale in textScales) {
        for (final digits in DigitStyle.values) {
          final name = '${screen.name}_${surface.name}_${scale}_${digits.name}';
          testWidgets(name, (tester) async {
            await pumpWassalApp(
              tester,
              overrides: screen.overrides,
              initialLocation: screen.location,
              surface: surface,
              textScale: scale,
              digits: digits,
            );
            await expectLater(
              find.byType(WassalApp),
              matchesGoldenFile('goldens/$name.png'),
            );
          });
        }
      }
    }
  }
}
