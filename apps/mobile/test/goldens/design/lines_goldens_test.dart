import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';

import '../../design/design_check.dart';
import '../../design/samples/lines.dart';

// `Lines` as the app draws it, beside docs/design/png/Lines.png
// (specs/014-m09-lines-vehicles, research R12), in both digit styles.
// Expected differences:
// - the locked look on the tiles (HANDOFF §9.1 #6), not the dashed ones;
// - «كمّل» is its own button (Clarifications Q3);
// - the safar microbus isn't for sale before the new one: no price;
// - خط الجامعة's stars read 25, the `LineDetails` board's cells (R4);
// - long text wraps (§9.1 #10); and no apartment dot in the sample.

void main() {
  for (final digits in DigitStyle.values) {
    testWidgets('Lines, ${digits.name}', (tester) async {
      await pumpLines(tester, digits: digits);
      await expectDesignGolden(tester, find.byType(WassalApp), 'Lines', digits);
    });
  }
}
