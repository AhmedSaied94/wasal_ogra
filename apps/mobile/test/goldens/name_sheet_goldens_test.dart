import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/features/onboarding/presentation/name_sheet.dart';

import '../helpers/economy.dart';
import '../helpers/pump_app.dart';
import '../helpers/trip.dart';

// The Name sheet over Home (specs/012-m07-onboarding/contracts/name.md "The
// re-ask"), after a refusal, in RTL at 390×844 with both digit styles. No
// artboard draws it: the `Name` card's blocks in the `Components` sheet.

void main() {
  for (final digits in DigitStyle.values) {
    testWidgets('the Name sheet, refused, ${digits.name}', (tester) async {
      await pumpWassalApp(
        tester,
        digits: digits,
        economy: economyOverridesOf(await testEconomy()),
        overrides: [nameSeedProvider.overrideWithValue(24)],
      );
      unawaited(showNameSheet(appContext(tester), refused: true));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(WassalApp),
        matchesGoldenFile('goldens/name_sheet_refused_${digits.name}.png'),
      );
    });
  }
}
