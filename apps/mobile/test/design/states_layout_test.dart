import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../helpers/design_component.dart';
import 'boxes.dart';
import 'design_check.dart';
import 'samples/states.dart';

// The `States` board's ten tap boxes against the sample's tappables
// (contracts/design-checks.md). The undo button's hit area is taller than
// it is drawn, so its box is checked against the drawn button.

void main() {
  testWidgets('States: every tap box', (tester) async {
    final semantics = tester.ensureSemantics();
    final board = loadBoard('States');
    await pumpDesignComponent(
      tester,
      StatesSample(board: board, digits: DigitStyle.arabicIndic),
      size: StatesSample.size,
      background: ColorTokens.ground,
    );
    await tester.pump(const Duration(milliseconds: 300));
    final l10n = AppLocalizations.of(tester.element(find.byType(StatesSample)));
    final undo = l10n.undoCountdown('٣');
    expectLayoutMatches(
      tester,
      'States',
      board: board,
      skip: {
        19:
            'the undo button is drawn 40 high, but its hit area is the '
            '44 pt touch minimum; the drawn button is checked by rect',
      },
      appOnly: {undo},
    );
    final drawn = tester.getRect(
      find
          .descendant(
            of: find.bySemanticsLabel(undo),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect(drawn.left, closeTo(30, 2));
    expect(drawn.width, closeTo(67.3, 2));
    expect(drawn.height, closeTo(40, 0.5));
    semantics.dispose();
  });
}
