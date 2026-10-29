import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/features/lines/presentation/line_card.dart';
import 'package:wassal/features/lines/presentation/line_map.dart';

import '../../design/design_check.dart';
import '../../design/samples/lines.dart';

// The Lines boards as the app draws them, beside docs/design/png/
// (specs/014-m09-lines-vehicles, research R12), in both digit styles.
// Expected differences from `Lines`:
// - the locked look on the tiles (HANDOFF §9.1 #6), not the dashed ones;
// - «كمّل» is its own button (Clarifications Q3);
// - the safar microbus isn't for sale before the new one: no price;
// - خط الجامعة's stars read 25, the `LineDetails` board's cells (R4);
// - the cards stand on the map's bottom under the road's end, padded as
//   the boards of 2026-10-29 pad them;
// - long text wraps (§9.1 #10); and no apartment dot in the sample.
// From `LinesFirst` and `LinesOwned`: the old microbus keeps its bead row
// (the vehicles' own art), and no apartment dot in the sample.

void main() {
  for (final digits in DigitStyle.values) {
    testWidgets('Lines, ${digits.name}', (tester) async {
      await pumpLines(tester, digits: digits);
      await expectDesignGolden(tester, find.byType(WassalApp), 'Lines', digits);
    });

    testWidgets('LinesFirst, ${digits.name}', (tester) async {
      await pumpLinesFirst(tester, digits: digits);
      await expectDesignGolden(
        tester,
        find.byType(WassalApp),
        'LinesFirst',
        digits,
      );
    });

    testWidgets('LinesOwned, ${digits.name}', (tester) async {
      await pumpLinesOwned(tester, digits: digits);
      await expectDesignGolden(
        tester,
        find.byType(WassalApp),
        'LinesOwned',
        digits,
      );
    });

    // The states no board draws (T104, R12).
    testWidgets('LinesDoneAtThree, ${digits.name}', (tester) async {
      await pumpLinesDoneAtThree(tester, digits: digits);
      await expectDesignGolden(
        tester,
        find.byType(WassalApp),
        'LinesDoneAtThree',
        digits,
      );
    });

    testWidgets('LinesOffline, ${digits.name}', (tester) async {
      await pumpLinesOffline(tester, digits: digits);
      await expectDesignGolden(
        tester,
        find.byType(WassalApp),
        'LinesOffline',
        digits,
      );
    });

    testWidgets('LinesSmall, ${digits.name}', (tester) async {
      await pumpLinesSmall(tester, digits: digits);
      // The focus card in view, as a 360×640 phone opens Lines (T112).
      final map = tester.getRect(find.byKey(LineMap.scrollKey));
      final focus = tester.getRect(
        find.byKey(LineCard.keyOf(LineId.lineGamaa)),
      );
      expect(focus.top, greaterThanOrEqualTo(map.top - 0.5));
      expect(focus.bottom, lessThanOrEqualTo(map.bottom + 0.5));
      await expectDesignGolden(
        tester,
        find.byType(WassalApp),
        'LinesSmall',
        digits,
      );
    });
  }
}
