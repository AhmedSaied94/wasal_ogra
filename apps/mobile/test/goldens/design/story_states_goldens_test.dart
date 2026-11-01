import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';

import '../../design/design_check.dart';
import '../../design/samples/story_states.dart';

// The story's boards of 2026-10-31 as the app draws them, beside
// docs/design/png/<Board>.png (specs/015-m10-apartment-story, T132), in both
// digit styles.

typedef _Pump = Future<ProviderContainer> Function(
  WidgetTester tester, {
  DigitStyle digits,
});

final _boards = <String, _Pump>{
  'ChaptersGoal': (tester, {digits = DigitStyle.arabicIndic}) =>
      pumpChaptersGoal(tester, digits: digits),
  'HomeStoryEnd': (tester, {digits = DigitStyle.arabicIndic}) =>
      pumpHomeStoryEnd(tester, digits: digits),
  'RequestsEmpty': (tester, {digits = DigitStyle.arabicIndic}) =>
      pumpRequestsEmpty(tester, digits: digits),
};

void main() {
  for (final entry in _boards.entries) {
    for (final digits in DigitStyle.values) {
      testWidgets('${entry.key}, ${digits.name}', (tester) async {
        await entry.value(tester, digits: digits);
        await expectDesignGolden(
          tester,
          find.byType(WassalApp),
          entry.key,
          digits,
        );
      });
    }
  }
}
