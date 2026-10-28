import 'package:flutter_test/flutter_test.dart';

import 'design_check.dart';
import 'samples/home_states.dart';

// `HomeStates` against its measured boxes (specs/013-m08-home-result,
// research R12, R20): out of fuel, offline and chapter 2 together. The
// fuel pill's label rounds to minutes (R11), where the board's says «١٢
// دقيقة و٣٠ ثانية». Three are paired: the line card's label also says
// its stars, and «البنزين خلص» and «الخطوط» are also parts of other
// labels. What needs the network stays a control, disabled: the
// BONAT pill and the shop tab, which the board measures as text. The
// testers' button is the app's own (internal builds).

void main() {
  testWidgets('HomeStates: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpHomeStates(tester);
    expectLayoutMatches(
      tester,
      'HomeStates',
      pairings: const {
        10: 'البنزين خلص، اللتر الجاي بعد ١٣ دقيقة',
        34: 'الخطوط: خط الحي، المشوار ٨ من ٢٠، النجوم ١٤ من ٦٠',
        43: 'البنزين خلص، افتح البنزين',
        65: 'الخطوط',
      },
      appOnly: const {
        'البونات ٤٠، المحل محتاج نت',
        'المحل، محتاج نت',
        'لوحة التجربة',
      },
    );
    semantics.dispose();
  });
}
