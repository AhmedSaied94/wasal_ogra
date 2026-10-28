import 'package:flutter_test/flutter_test.dart';

import 'design_check.dart';
import 'samples/result.dart';

// `Result` against its measured boxes (specs/013-m08-home-result,
// research R20), on the board's 390×1100 as one tall surface. The ×2
// offer (box 42) and the apartment card (box 47) have no text on the
// board, so they are paired with their labels. The mistakes' summary row
// opens and closes the lines, a `<summary>` the board measures as text.

void main() {
  testWidgets('Result: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpResult(tester);
    expectLayoutMatches(
      tester,
      'Result',
      pairings: const {42: 'اقبض ×٢', 47: 'الأنتريه، ١٬٣٢٥ من ٣٬٢٠٠ جنيه'},
      appOnly: const {'غلطة واحدة ضيّعت النجمة التالتة، اقفل التفاصيل'},
    );
    semantics.dispose();
  });
}
