import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';

import '../../design/design_check.dart';
import '../../design/samples/line_details.dart';

// `LineDetails` as the app draws it, beside docs/design/png/LineDetails.png
// (specs/014-m09-lines-vehicles, research R12), in both digit styles.
// Expected differences:
// - the locked look on the cells (HANDOFF §9.1 #6), not the dashed ones;
// - the summary reads 25 stars: the board's cells add up to 25 (R4);
// - the real Lines sits under the scrim;
// - ✕ is «قفل» (M08's pairing).

void main() {
  for (final digits in DigitStyle.values) {
    testWidgets('LineDetails, ${digits.name}', (tester) async {
      await pumpLineDetails(tester, digits: digits);
      await expectDesignGolden(
        tester,
        find.byType(WassalApp),
        'LineDetails',
        digits,
      );
    });
  }
}
