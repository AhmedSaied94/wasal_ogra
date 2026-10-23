import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';

import '../../design/design_check.dart';
import '../../design/samples/tutorial_hint.dart';

// `Tutorial`'s hint as the app draws it, beside docs/design/png/Tutorial.png;
// the scrim and the locked boosters are M07's
// (contracts/design-checks.md), in both digit styles.

void main() {
  for (final digits in DigitStyle.values) {
    testWidgets('Tutorial, ${digits.name}', (tester) async {
      await pumpTutorialHint(tester, digits: digits);
      await expectDesignGolden(
        tester,
        find.byType(WassalApp),
        'Tutorial',
        digits,
      );
    });
  }
}
