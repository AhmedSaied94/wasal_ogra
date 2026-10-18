import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/routing/routes.dart';

import '../helpers/pump_app.dart';
import '../helpers/routing.dart';
import '../helpers/screens.dart';

// Every destination in the route table, from its sample parameters, at the
// reference surface and text scale 1.0, in both digit styles (constitution
// X, FR-040). A destination added to the table gets a golden here.

void main() {
  for (final d in destinations) {
    for (final digits in DigitStyle.values) {
      final name = '${d.name}_${digits.name}';
      testWidgets(name, (tester) async {
        switch (d) {
          case Destination(name: RouteNames.boot):
            await pumpWassalApp(
              tester,
              overrides: pendingStartup(),
              digits: digits,
            );
          case Destination(presentation: Presentation.overlay):
            // The only overlay is the trip pause, opened by back on the trip.
            await pumpWassalApp(
              tester,
              initialLocation: destinationNamed(RouteNames.trip).location,
              digits: digits,
            );
            await pressBack(tester);
          case _:
            await pumpWassalApp(
              tester,
              initialLocation: d.location,
              digits: digits,
            );
            expect(currentLocation(tester), d.location);
        }
        await expectLater(
          find.byType(WassalApp),
          matchesGoldenFile('goldens/all/$name.png'),
        );
      });
    }
  }
}
