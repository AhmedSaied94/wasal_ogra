import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/features/boot/boot_screen.dart';

import '../../design/design_check.dart';
import '../../design/samples/loading.dart';
import '../../helpers/design_component.dart';

// `Loading` as the app draws it, beside docs/design/png/Loading.png
// (contracts/design-checks.md). It shows no number, so both digit styles
// draw the same.

void main() {
  for (final digits in DigitStyle.values) {
    testWidgets('Loading, ${digits.name}', (tester) async {
      await pumpDesignComponent(
        tester,
        const BootScreen(),
        overrides: loadingSampleOverrides(),
      );
      await tester.pumpAndSettle();
      await expectDesignGolden(
        tester,
        find.byType(BootScreen),
        'Loading',
        digits,
      );
    });
  }
}
