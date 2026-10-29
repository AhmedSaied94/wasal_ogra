import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';

import '../../design/design_check.dart';
import '../../design/samples/buy_vehicle.dart';

// `BuyVehicle` as the app draws it, beside docs/design/png/BuyVehicle.png
// (specs/014-m09-lines-vehicles, research R12), in both digit styles.
// Expected differences:
// - the plain preview, with no «بزينتك» (R10);
// - the impact line reworded: «فاضل {amount} ج على {goal}» (Q4);
// - «لسه» is the secondary button;
// - the real Lines sits under the scrim.

void main() {
  for (final digits in DigitStyle.values) {
    testWidgets('BuyVehicle, ${digits.name}', (tester) async {
      await pumpBuyVehicle(tester, digits: digits);
      await expectDesignGolden(
        tester,
        find.byType(WassalApp),
        'BuyVehicle',
        digits,
      );
    });
  }
}
