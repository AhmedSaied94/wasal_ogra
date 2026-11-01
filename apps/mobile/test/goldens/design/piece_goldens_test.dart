import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';

import '../../design/design_check.dart';
import '../../design/samples/piece.dart';

// `Piece` as the app draws it, beside docs/design/png/Piece.png
// (specs/015-m10-apartment-story, T065), in both digit styles.

void main() {
  for (final digits in DigitStyle.values) {
    testWidgets('Piece, ${digits.name}', (tester) async {
      await pumpPiece(tester, digits: digits);
      await expectDesignGolden(tester, find.byType(WassalApp), 'Piece', digits);
    });
  }
}
