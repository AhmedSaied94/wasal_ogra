import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

import '../../design/boxes.dart';
import '../../design/design_check.dart';
import '../../design/samples/states.dart';
import '../../helpers/design_component.dart';

// `States` as the app draws it, beside docs/design/png/States.png
// (contracts/design-checks.md), in both digit styles.

void main() {
  for (final digits in DigitStyle.values) {
    testWidgets('States, ${digits.name}', (tester) async {
      await pumpDesignComponent(
        tester,
        StatesSample(board: loadBoard('States'), digits: digits),
        size: StatesSample.size,
        background: ColorTokens.ground,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await expectDesignGolden(
        tester,
        find.byType(StatesSample),
        'States',
        digits,
      );
    });
  }
}
