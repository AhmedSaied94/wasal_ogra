import 'package:flutter_test/flutter_test.dart';

import 'design_check.dart';
import 'samples/c_home.dart';

// `C-Home` against its measured boxes (specs/013-m08-home-result,
// research R20). The garage (box 16) is phase 2 (FR-008). The fuel pill's
// label rounds to minutes (R11), where the board's says «١٢ دقيقة و٣٠
// ثانية»; the morning piggy (box 59) has no label on the board. Three
// bottom-bar cells are paired, as their text is also part of the line
// card's and the BONAT pill's labels; the apartment's dot reads «جديد»
// (M03). The BONAT pill follows the fuel pill, which Flutter's digits make
// 1.5 pt wider, and is 1.5 pt wider itself: each edge is within 2 pt but
// the right, within 3.5. The testers' button is the app's own (internal
// builds).

void main() {
  testWidgets('C-Home: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpCHome(tester);
    expectLayoutMatches(
      tester,
      'C-Home',
      skip: const {16: 'the garage is phase 2 (FR-008)'},
      pairings: const {
        10: 'البنزين ٤ من ٥، اللتر الجاي بعد ١٣ دقيقة',
        59: 'حصّالة الصبح',
        69: 'الخطوط',
        71: 'الشقة، جديد',
        74: 'المحل',
      },
      tolerances: const {8: 3.5},
      appOnly: const {'لوحة التجربة'},
    );
    semantics.dispose();
  });
}
