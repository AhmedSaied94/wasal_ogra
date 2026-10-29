import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';

import '../../design/design_check.dart';
import '../../design/samples/line_details.dart';

// The LineDetails boards as the app draws them, beside docs/design/png/
// (specs/014-m09-lines-vehicles, research R12), in both digit styles.
// Expected differences:
// - the locked look on the cells (HANDOFF §9.1 #6), not `LineDetails`'
//   dashed ones;
// - `LineDetails`' summary reads 25 stars: the board's cells add up to 25
//   (R4);
// - the cells' stars are `LineDetails`' icons, not the later boards' text
//   stars;
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

    testWidgets('LineDetailsStory, ${digits.name}', (tester) async {
      await pumpLineDetailsStory(tester, digits: digits);
      await expectDesignGolden(
        tester,
        find.byType(WassalApp),
        'LineDetailsStory',
        digits,
      );
    });

    // A state no board draws (T104, R12).
    testWidgets('LineDetailsShort, ${digits.name}', (tester) async {
      await pumpLineDetailsShort(tester, digits: digits);
      await expectDesignGolden(
        tester,
        find.byType(WassalApp),
        'LineDetailsShort',
        digits,
      );
    });

    testWidgets('LineDetailsDone, ${digits.name}', (tester) async {
      await pumpLineDetailsDone(tester, digits: digits);
      await expectDesignGolden(
        tester,
        find.byType(WassalApp),
        'LineDetailsDone',
        digits,
      );
    });

    testWidgets('LineDetailsLocked, ${digits.name}', (tester) async {
      await pumpLineDetailsLocked(tester, digits: digits);
      await expectDesignGolden(
        tester,
        find.byType(WassalApp),
        'LineDetailsLocked',
        digits,
      );
    });
  }
}
