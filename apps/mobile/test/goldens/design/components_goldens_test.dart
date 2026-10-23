import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

import '../../design/boxes.dart';
import '../../design/design_check.dart';
import '../../design/samples/components.dart';
import '../../helpers/design_component.dart';

// The `Components` board as the app draws it, beside
// docs/design/png/Components.png (contracts/design-checks.md).

void main() {
  final board = loadBoard('Components');
  for (final digits in DigitStyle.values) {
    testWidgets('Components, ${digits.name}', (tester) async {
      await pumpDesignComponent(
        tester,
        ComponentsSample(board: board, digits: digits),
        size: ComponentsSample.size,
        background: ColorTokens.paper,
      );
      await tester.pump(const Duration(milliseconds: 300));
      // Box 6 is the pressed look: hold it down.
      final press = await tester.startGesture(
        tester.getCenter(find.byKey(ComponentsSample.pressedKey)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await expectDesignGolden(
        tester,
        find.byType(ComponentsSample),
        'Components',
        digits,
      );
      await press.up();
      await tester.pump(const Duration(milliseconds: 100));
    });
  }
}
