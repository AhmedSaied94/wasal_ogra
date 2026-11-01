import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';

import '../design/samples/name.dart';
import '../helpers/economy.dart';
import '../helpers/pump_app.dart';
import '../helpers/routing.dart';
import '../helpers/screens.dart';
import '../helpers/trip.dart' show economyOverridesOf;

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
          case Destination(name: RouteNames.result):
            // Opened bare, it shows the last trip's pay (M08 FR-036).
            await pumpWassalApp(
              tester,
              initialLocation: d.location,
              digits: digits,
              economy: economyOverridesOf(await lastFinishedEconomy()),
            );
            expect(currentLocation(tester), d.location);
          case Destination(name: RouteNames.storyScene):
            // The sample's `the_stand` waits for «المعلم»'s story trip; a
            // locked scene leaves to the apartment (M10 story-flow.md).
            await pumpWassalApp(
              tester,
              initialLocation: d.location,
              digits: digits,
              economy: economyOverridesOf(
                await testEconomy(firstState: standPlayedState),
              ),
            );
            expect(currentLocation(tester), d.location);
          case Destination(name: RouteNames.apartmentItem):
            // A piece in a locked room (the default player) leaves to the
            // tab, as the router does (M10 T064).
            await pumpWassalApp(
              tester,
              initialLocation: d.location,
              digits: digits,
            );
            expect(currentLocation(tester), '/apartment');
          case _:
            await pumpWassalApp(
              tester,
              initialLocation: d.location,
              digits: digits,
              // The Name card's suggestion, else the clock's.
              overrides: [nameSeedProvider.overrideWithValue(nameSampleSeed)],
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
