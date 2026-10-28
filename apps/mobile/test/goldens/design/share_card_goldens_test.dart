import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/features/result/presentation/share_card.dart';

import '../../design/design_check.dart';
import '../../design/samples/share_card.dart';

// `ShareCard`, the shared picture at its 360×360, beside
// docs/design/png/ShareCard.png (specs/013-m08-home-result, research R16,
// R20), in both digit styles. Expected differences: the coin is the app's
// (with its mark), and a missed star's outline is the `sun.lip` edge of
// the app's own star.

void main() {
  for (final digits in DigitStyle.values) {
    testWidgets('ShareCard, ${digits.name}', (tester) async {
      await pumpShareCard(tester, digits: digits);
      await expectDesignGolden(
        tester,
        find.byType(ShareCard),
        'ShareCard',
        digits,
      );
    });
  }
}
