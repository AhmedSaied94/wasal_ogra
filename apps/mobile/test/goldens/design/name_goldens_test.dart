import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';

import '../../design/design_check.dart';
import '../../design/samples/name.dart';

// `Name` as the app draws it, beside docs/design/png/Name.png
// (specs/012-m07-onboarding/contracts/ci-checks.md), in both digit styles.
// Reviewed 2026-10-27 with DESIGN_COMPARE; expected differences:
// - the avatar is `CharacterAvatar('usta')`'s head-and-shoulders crop
//   (contracts/name.md), not the board's own close-up of the face;
// - the name sits 14 pt in from the field's edge (`AppTextField`), the
//   board's 16.

void main() {
  for (final digits in DigitStyle.values) {
    testWidgets('Name, ${digits.name}', (tester) async {
      await pumpName(tester, digits: digits);
      await expectDesignGolden(tester, find.byType(WassalApp), 'Name', digits);
    });
  }
}
