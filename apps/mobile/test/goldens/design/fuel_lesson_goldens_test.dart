import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';

import '../../design/design_check.dart';
import '../../design/samples/fuel_lesson.dart';

// `FuelLesson` as the app draws it, beside docs/design/png/FuelLesson.png
// (specs/012-m07-onboarding/contracts/ci-checks.md), in both digit styles,
// the gauge settled at full.
// Reviewed 2026-10-28 with DESIGN_COMPARE; expected differences:
// - the avatar is `CharacterAvatar('moallem')`'s head-and-shoulders crop,
//   as on `Name`, not the board's own close-up;
// - المعلم's line is a `SpeechBubble`, with its lip; the board's box has
//   none;
// - the pump is the design's `fuel` icon, in its own red, not the board's
//   ink drawing.

void main() {
  for (final digits in DigitStyle.values) {
    testWidgets('FuelLesson, ${digits.name}', (tester) async {
      await pumpFuelLesson(tester, digits: digits);
      await expectDesignGolden(
        tester,
        find.byType(WassalApp),
        'FuelLesson',
        digits,
      );
    });
  }
}
