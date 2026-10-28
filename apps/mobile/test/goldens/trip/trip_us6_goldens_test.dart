import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';

import '../../helpers/trip.dart';

// The trip screen's US6 goldens (tasks.md T088): the failure card with
// and without the revive, affordable and not, and the story strip, on the
// trip surfaces but `mid`, in RTL, in both digit styles, with the
// stand-in art. Generated on Linux.

void main() {
  for (final state in us6TripCases()) {
    for (final surface in tripGoldenSurfaces(state)) {
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
