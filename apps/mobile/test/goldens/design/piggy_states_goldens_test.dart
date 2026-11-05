import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';

import '../../design/design_check.dart';
import '../../design/samples/piggy_states.dart';

// M11's piggy boards as the app draws them, beside
// docs/design/png/{PiggyArrived,PiggyUsed,PiggyLater}.png
// (specs/018-m11-ads, T064), in both digit styles.

void main() {
  for (final digits in DigitStyle.values) {
    testWidgets('PiggyArrived, ${digits.name}', (tester) async {
      await pumpPiggyArrived(tester, digits: digits);
      await expectDesignGolden(
        tester,
        find.byType(WassalApp),
        'PiggyArrived',
        digits,
      );
    });

    for (final (board, later) in [('PiggyUsed', false), ('PiggyLater', true)]) {
      testWidgets('$board, ${digits.name}', (tester) async {
        await pumpPiggyToast(tester, later: later, digits: digits);
        await expectDesignGolden(tester, find.byType(WassalApp), board, digits);
      });
    }
  }
}
