import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';

import '../../design/design_check.dart';
import '../../design/samples/pre_trip.dart';

// `PreTrip` as the app draws it over `C-Home`, beside
// docs/design/png/PreTrip.png (specs/013-m08-home-result, research R20),
// in both digit styles. Expected differences:
// - the stars read «لسه»: a trip at a star has nothing new (R5);
// - the price cells stack their tags over the names: «المستشفى» doesn't fit
//   beside its tag (FR-027);
// - the station letters are أ ب ج (008.5 R1), not the stations' initials;
// - أبو سمّاعة's sentence says nothing of routing money (Q3).

void main() {
  for (final digits in DigitStyle.values) {
    testWidgets('PreTrip, ${digits.name}', (tester) async {
      await pumpPreTrip(tester, digits: digits);
      await expectDesignGolden(
        tester,
        find.byType(WassalApp),
        'PreTrip',
        digits,
      );
    });
  }
}
