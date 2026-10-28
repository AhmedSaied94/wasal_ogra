// The testers' tools on Home (specs/013-m08-home-result, US6, research
// R21): on dev and staging, the debug button opens the sheet with every
// trip, the sync card, the first session's card and the gallery, and a
// trip there starts at once, with no card and no checkpoint. Prod has
// neither the button nor the sheet.
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/features/dev/gallery/gallery_entry.dart';
import 'package:wassal/features/dev/onboarding_card.dart';
import 'package:wassal/features/dev/sync_status_card.dart';
import 'package:wassal/features/home/application/checkpoint.dart';
import 'package:wassal/features/home/presentation/debug_sheet.dart';
import 'package:wassal/features/home/presentation/home_screen.dart';
import 'package:wassal/features/pre_trip/presentation/pre_trip_card.dart';
import 'package:wassal/features/trip/presentation/playtest/trip_list.dart';

import '../../helpers/home.dart';
import '../../helpers/pump_app.dart';

/// Counts its passes, and never holds.
final class _Checkpoint implements BetweenTripsCheckpoint {
  int passes = 0;

  @override
  Future<void> pass() async => passes++;
}

void main() {
  for (final flavor in [Flavor.dev, Flavor.staging]) {
    group(flavor.name, () {
      testWidgets('the button opens the sheet with every tool', (tester) async {
        await pumpWassalApp(tester, flavor: flavor, settle: false);
        await pumpFrames(tester);
        await openDebugSheet(tester);
        expect(find.byType(HomeDebugSheet), findsOneWidget);
        for (final tool in [
          TripList,
          SyncStatusCard,
          OnboardingCard,
          GalleryEntry,
        ]) {
          expect(find.byType(tool), findsOneWidget, reason: '$tool');
        }
      });

      testWidgets('a trip there starts at once: no card, no checkpoint', (
        tester,
      ) async {
        final checkpoint = _Checkpoint();
        await pumpWassalApp(
          tester,
          flavor: flavor,
          settle: false,
          overrides: [
            betweenTripsCheckpointProvider.overrideWithValue(checkpoint),
          ],
        );
        await pumpFrames(tester);
        await openDebugSheet(tester);
        final trip = find.byKey(TripList.tripKey('line_hay.02'));
        await tester.ensureVisible(trip);
        await tester.pump();
        await tester.tap(trip);
        await pumpFrames(tester);
        expect(currentLocation(tester), '/trip/line_hay.02');
        expect(find.byType(PreTripCard), findsNothing);
        expect(checkpoint.passes, 0);
      });
    });
  }

  testWidgets('prod: no button, no sheet', (tester) async {
    await pumpWassalApp(tester, flavor: Flavor.prod, settle: false);
    await pumpFrames(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byKey(HomeDebugButton.buttonKey), findsNothing);
    expect(find.byType(HomeDebugSheet), findsNothing);
  });
}
