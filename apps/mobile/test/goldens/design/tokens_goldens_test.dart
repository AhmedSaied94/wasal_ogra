import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

import '../../design/boxes.dart';
import '../../design/design_check.dart';
import '../../design/samples/tokens.dart';
import '../../helpers/design_component.dart';

// The `Tokens` board in the app's tokens, beside docs/design/png/Tokens.png
// (contracts/design-checks.md). It has no taps, so no layout test.

void main() {
  final board = loadBoard('Tokens');
  for (final digits in DigitStyle.values) {
    testWidgets('Tokens, ${digits.name}', (tester) async {
      await pumpDesignComponent(
        tester,
        TokensSample(board: board, digits: digits),
        size: TokensSample.size,
        background: ColorTokens.paper,
      );
      await expectDesignGolden(
        tester,
        find.byType(TokensSample),
        'Tokens',
        digits,
      );
    });
  }
}
