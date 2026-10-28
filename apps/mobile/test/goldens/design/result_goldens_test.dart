import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';

import '../../design/design_check.dart';
import '../../design/samples/result.dart';

// `Result` as the app draws it over `C-Home`, beside
// docs/design/png/Result.png (specs/013-m08-home-result, research R20),
// on the board's 390×1100, in both digit styles. The task banner and the
// ×2 offer are fakes in their slots. Expected differences:
// - the pay's BONAT chip reads «+٥ بون», the HANDOFF's short form, where
//   the board's reads «بونات»;
// - the apartment card's tile is the ring, as on Home's savings card,
//   until the apartment (M09) brings the pieces' art.

void main() {
  for (final digits in DigitStyle.values) {
    testWidgets('Result, ${digits.name}', (tester) async {
      await pumpResult(tester, digits: digits);
      await expectDesignGolden(
        tester,
        find.byType(WassalApp),
        'Result',
        digits,
      );
    });
  }
}
