import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';

import '../../design/design_check.dart';
import '../../design/samples/ad_states.dart';

// M11's trip-screen boards as the app draws them, beside
// docs/design/png/{BoosterAdCard,NoFuelAd,NoFuelAdLimit}.png
// (specs/018-m11-ads, T060, T064), and the refill offer on the fuel
// sheet's stand-in, in both digit styles.

void main() {
  for (final digits in DigitStyle.values) {
    testWidgets('BoosterAdCard, ${digits.name}', (tester) async {
      await pumpBoosterAdCard(tester, digits: digits);
      await expectDesignGolden(
        tester,
        find.byType(WassalApp),
        'BoosterAdCard',
        digits,
      );
    });

    testWidgets('NoFuelAd, ${digits.name}', (tester) async {
      await pumpNoFuelAd(tester, digits: digits);
      await expectDesignGolden(
        tester,
        find.byType(WassalApp),
        'NoFuelAd',
        digits,
      );
    });

    testWidgets('NoFuelAdLimit, ${digits.name}', (tester) async {
      await pumpNoFuelAd(tester, refillsToday: 3, digits: digits);
      await expectDesignGolden(
        tester,
        find.byType(WassalApp),
        'NoFuelAdLimit',
        digits,
      );
    });

    testWidgets('FuelPlaceholder, ${digits.name}', (tester) async {
      await pumpFuelPlaceholder(tester, digits: digits);
      await expectDesignGolden(
        tester,
        find.byType(WassalApp),
        'FuelPlaceholder',
        digits,
      );
    });
  }
}
