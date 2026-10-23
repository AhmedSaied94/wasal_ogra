import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/trip/presentation/dashboard/dashboard.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import 'design_check.dart';
import 'samples/trip_events.dart';
import 'trip_labels.dart';

// `TripEvents` against its measured boxes (contracts/design-checks.md). The
// tray cells are drawn as «×N» alone, so each is paired with the app's
// label for it. The passengers aren't taps in this artboard.

/// The artboard has no megaphone on the call button (HANDOFF `TripEvents`
/// block 8: "keep it as in `C-Trip`"), so it and the hand beside it are
/// drawn narrower than the app's.
const _noMegaphone =
    'the artboard drops the megaphone; the app keeps C-Trip\'s call button';

void main() {
  testWidgets('TripEvents: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpTripEvents(tester);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(TripDashboard)),
    );
    final view = tripEventsView();
    expectLayoutMatches(
      tester,
      'TripEvents',
      skip: {45: _noMegaphone, 48: _noMegaphone},
      pairings: trayPairings(tester, [51, 53, 55, 57, 59, 61, 63, 65]),
      appOnly: {
        l10n.tripDebugOpen,
        ...megaphoneLabels(tester),
        ...passengerLabels(tester, [
          for (final p in view.passengers) p.passengerId,
        ]),
      },
    );
    semantics.dispose();
  });
}
