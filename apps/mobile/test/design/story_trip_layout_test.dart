import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/trip/presentation/dashboard/dashboard.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import 'design_check.dart';
import 'samples/story_trip.dart';
import 'trip_labels.dart';

// `StoryTrip` against its measured boxes (contracts/design-checks.md), with
// `TripEvents`' pairings: «×N» tray cells, and passengers that aren't taps
// here.

const _noMegaphone =
    'the artboard drops the megaphone; the app keeps C-Trip\'s call button';

void main() {
  testWidgets('StoryTrip: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpStoryTrip(tester);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(TripDashboard)),
    );
    expectLayoutMatches(
      tester,
      'StoryTrip',
      skip: {45: _noMegaphone, 50: _noMegaphone},
      pairings: trayPairings(tester, [53, 55, 57, 59, 61, 63, 65, 67]),
      appOnly: {
        l10n.tripDebugOpen,
        ...megaphoneLabels(tester),
        ...passengerLabels(tester, [
          for (final p in storyTripView().passengers) p.passengerId,
        ]),
      },
    );
    semantics.dispose();
  });
}
