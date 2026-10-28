import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';

import '../../design/design_check.dart';
import '../../design/samples/c_home.dart';

// `C-Home` as the app draws it, beside docs/design/png/C-Home.png
// (specs/013-m08-home-result, research R20), in both digit styles. The
// daily row and the morning piggy are the sample's fakes (M13, M11).

void main() {
  for (final digits in DigitStyle.values) {
    testWidgets('C-Home, ${digits.name}', (tester) async {
      await pumpCHome(tester, digits: digits);
      await expectDesignGolden(
        tester,
        find.byType(WassalApp),
        'C-Home',
        digits,
      );
    });
  }
}
