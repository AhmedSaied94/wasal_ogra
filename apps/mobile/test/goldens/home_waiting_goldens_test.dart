import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';

import '../helpers/lines.dart';

// Home with a scene waiting (specs/015-m10-apartment-story, contracts/
// story-flow.md "The waiting slot"): the savings card says «مشهد جديد
// مستنيك» in place of its bar. Its own golden, so the design boards' Home
// goldens keep the bar they draw (T153).

/// The first trip finished on this phone, its after-trip scene not played.
final _waiting = playerState(stars: {'line_hay.03': 1});

void main() {
  for (final digits in DigitStyle.values) {
    testWidgets('a waiting scene says so on Home, ${digits.name}', (
      tester,
    ) async {
      await pumpLinesApp(tester, state: _waiting, location: '/home');
      await expectLater(
        find.byType(WassalApp),
        matchesGoldenFile('goldens/home_waiting_${digits.name}.png'),
      );
    });
  }
}
