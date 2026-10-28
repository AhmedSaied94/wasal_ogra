import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';

import '../../design/design_check.dart';
import '../../design/samples/intro.dart';

// `Intro` as the app draws it, beside docs/design/png/Intro.png
// (specs/012-m07-onboarding/contracts/ci-checks.md), in both digit styles.
// Reviewed 2026-10-27 with DESIGN_COMPARE; expected differences:
// - none in layout: the header, panel, caption, bubble, dots and «يلا» sit
//   on the board's boxes (intro_layout_test);
// - the bubble's line breaks follow Flutter's text shaping, a word apart
//   from the browser's at most.

void main() {
  for (final digits in DigitStyle.values) {
    testWidgets('Intro, ${digits.name}', (tester) async {
      await pumpIntro(tester, digits: digits);
      await expectDesignGolden(tester, find.byType(WassalApp), 'Intro', digits);
    });
  }
}
