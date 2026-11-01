import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';

import '../../design/design_check.dart';
import '../../design/samples/chapters.dart';

// `Chapters` and `Album` as the app draws them, beside docs/design/png/
// Chapters.png and Album.png (specs/015-m10-apartment-story, T109), in both
// digit styles.

void main() {
  for (final digits in DigitStyle.values) {
    testWidgets('Chapters, ${digits.name}', (tester) async {
      await pumpChapters(tester, digits: digits);
      await expectDesignGolden(
        tester,
        find.byType(WassalApp),
        'Chapters',
        digits,
      );
    });

    testWidgets('Album, ${digits.name}', (tester) async {
      await pumpAlbum(tester, digits: digits);
      await expectDesignGolden(tester, find.byType(WassalApp), 'Album', digits);
    });
  }
}
