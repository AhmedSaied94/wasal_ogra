import 'package:flutter_test/flutter_test.dart';

import 'design_check.dart';
import 'samples/result.dart';

// `Result` against its measured boxes (specs/013-m08-home-result,
// research R20), on the board's 390×1100 as one tall surface. The ×2
// offer (box 42, M11's `ResultDoubleOffer`) and the apartment card (box 47)
// have no text on the board, so they are paired with their labels; the ×2's
// joins its two lines with «، » (M11 design-briefs "Labels"). Its decline
// link (box 46) takes 44 to the touch where the board draws 36, its top 8
// higher (specs/018-m11-ads, T034). The mistakes' summary row
// opens and closes the lines, a `<summary>` the board measures as text.

void main() {
  testWidgets('Result: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpResult(tester);
    expectLayoutMatches(
      tester,
      'Result',
      pairings: const {
        42: 'اقبض ×٢، +١٧٠ بدل ٨٥',
        47: 'الأنتريه، ١٬٣٢٥ من ٣٬٢٠٠ جنيه',
      },
      tolerances: const {46: 8},
      appOnly: const {'غلطة واحدة ضيّعت النجمة التالتة، اقفل التفاصيل'},
    );
    semantics.dispose();
  });
}
