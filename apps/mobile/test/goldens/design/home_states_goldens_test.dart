import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';

import '../../design/design_check.dart';
import '../../design/samples/home_states.dart';

// `HomeStates` as the app draws it, beside docs/design/png/HomeStates.png
// (specs/013-m08-home-result, research R12, R20), in both digit styles:
// out of fuel, offline and chapter 2 together. The daily row and the
// piggy are fakes in their slots. Expected differences:
// - chapter 1 is met by the tuktuk, not by خط الحي, so chapter 2 can show
//   beside trip 8 (the board's state can't hold);
// - the goal's title names the vehicle in full, «اشتري الميكروباص القديم»;
// - the shop tab is dimmed as well as said to need the network (FR-014);
// - in Western digits, the header wraps under the name (as on C-Home) and
//   so does the goal card's second row: the digits are wider.

void main() {
  for (final digits in DigitStyle.values) {
    testWidgets('HomeStates, ${digits.name}', (tester) async {
      await pumpHomeStates(tester, digits: digits);
      await expectDesignGolden(
        tester,
        find.byType(WassalApp),
        'HomeStates',
        digits,
      );
    });
  }
}
