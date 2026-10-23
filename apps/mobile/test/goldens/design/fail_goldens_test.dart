import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';

import '../../design/design_check.dart';
import '../../design/samples/fail.dart';

// `Fail` as the app draws it, beside docs/design/png/Fail.png
// (contracts/design-checks.md), in both digit styles.

void main() {
  for (final digits in DigitStyle.values) {
    testWidgets('Fail, ${digits.name}', (tester) async {
      await pumpFail(tester, digits: digits);
      await expectDesignGolden(tester, find.byType(WassalApp), 'Fail', digits);
    });
  }
}
