import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';

import '../../helpers/trip.dart';

// The trip screen's US5 goldens (tasks.md T080): the boosters row, the
// purchase card, «حد معاه فكة؟», the ledger's badges and بلية's hint, on
// the three trip surfaces, in RTL, in both digit styles, with the stand-in
// art. Generated on Linux.

void main() {
  for (final state in us5TripCases()) {
    for (final surface in TripSurface.values) {
      for (final digits in DigitStyle.values) {
        final name = '${state.name}_${surface.name}_${digits.name}';
        testWidgets(name, (tester) async {
          await openTripCase(tester, state, surface: surface, digits: digits);
          await expectLater(
            find.byType(WassalApp),
            matchesGoldenFile('goldens/$name.png'),
          );
        });
      }
    }
  }
}
