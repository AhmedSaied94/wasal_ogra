import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';

import '../../design/design_check.dart';
import '../../design/samples/tutorial.dart';

// `Tutorial` as the app draws it, beside docs/design/png/Tutorial.png, in
// both digit styles: the coach's scrim and hole on the «١» cell, the hand,
// بلية and his bubble, and the locked boosters (M07 contracts/coach.md).
//
// Reviewed (T064); the expected differences:
// - the scene is the fixture's `line_hay.02` at the moment: its two riders,
//   one rider's line, its stops (الطالبية، التعاون), its talk log and its
//   drawer («٥» ×1 where the artboard has ×2) (008.5 R7: drawn riders are
//   the trip's);
// - the HUD keeps the debug button on internal builds, and «حد معاه فكة؟»
//   keeps C-Trip's megaphone;
// - the ring beats and the hand bobs, so both sit a little off the
//   artboard's still frame.

void main() {
  for (final digits in DigitStyle.values) {
    testWidgets('Tutorial, ${digits.name}', (tester) async {
      await pumpTutorial(tester, digits: digits);
      await expectDesignGolden(
        tester,
        find.byType(WassalApp),
        'Tutorial',
        digits,
      );
    });
  }
}
