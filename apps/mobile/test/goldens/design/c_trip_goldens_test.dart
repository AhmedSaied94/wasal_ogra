import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';

import '../../design/design_check.dart';
import '../../design/samples/c_trip.dart';

// `C-Trip` as the app draws it, beside docs/design/png/C-Trip.png
// (contracts/design-checks.md), in both digit styles. The static passenger
// art stands in for Rive (research R17).

void main() {
  for (final digits in DigitStyle.values) {
    testWidgets('C-Trip, ${digits.name}', (tester) async {
      await pumpCTrip(tester, digits: digits);
      await expectDesignGolden(
        tester,
        find.byType(WassalApp),
        'C-Trip',
        digits,
      );
    });
  }
}
