import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';

import '../../design/design_check.dart';
import '../../design/samples/story_trip.dart';
import '../../helpers/trip.dart';

// `StoryTrip` as the app draws it, beside docs/design/png/StoryTrip.png
// (contracts/design-checks.md), in both digit styles. And, since M10, the
// sample's own story trip with its chapter's content (specs/015-m10-apartment-
// story, contracts/story-trip.md): the title under the chip, the condition on
// the strip and المعلم in his seat. The design draws none of it, so that
// one is the app's own golden.

void main() {
  for (final digits in DigitStyle.values) {
    testWidgets('StoryTrip, ${digits.name}', (tester) async {
      await pumpStoryTrip(tester, digits: digits);
      await expectDesignGolden(
        tester,
        find.byType(WassalApp),
        'StoryTrip',
        digits,
      );
    });

    testWidgets('StoryTripContent, ${digits.name}', (tester) async {
      await pumpTrip(tester, tripId: 'line_hay.03', digits: digits);
      await expectLater(
        find.byType(WassalApp),
        matchesGoldenFile('goldens/StoryTripContent_${digits.name}.png'),
      );
    });
  }
}
