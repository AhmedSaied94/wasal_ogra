import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';

import '../../design/design_check.dart';
import '../../design/samples/buy_vehicle.dart';

// The BuyVehicle boards as the app draws them, beside docs/design/png/
// (specs/014-m09-lines-vehicles, research R12), in both digit styles.
// Expected differences:
// - the plain preview, with no «بزينتك» (R10);
// - the impact line reworded: «فاضل {amount} ج على {goal}» (Q4);
// - «لسه» is the secondary button;
// - the old microbus keeps its bead row (the vehicles' own art);
// - the real Lines sits under the scrim.

void main() {
  for (final digits in DigitStyle.values) {
    for (final (artboard, pump) in [
      ('BuyVehicle', pumpBuyVehicle),
      ('BuyVehicleShort', pumpBuyVehicleShort),
      ('BuyVehicleOwned', pumpBuyVehicleOwned),
      ('BuyVehicleNotForSale', pumpBuyVehicleNotForSale),
      // The states no board draws (T104, R12).
      ('BuyVehiclePlain', pumpBuyVehiclePlain),
      ('BuyVehicleNoPrice', pumpBuyVehicleNoPrice),
    ]) {
      testWidgets('$artboard, ${digits.name}', (tester) async {
        await pump(tester, digits: digits);
        await expectDesignGolden(
          tester,
          find.byType(WassalApp),
          artboard,
          digits,
        );
      });
    }
  }
}
