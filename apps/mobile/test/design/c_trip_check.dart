import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/features/trip/domain/looks.dart';
import 'package:wassal/features/trip/presentation/dashboard/dashboard.dart';
import 'package:wassal/features/trip/presentation/trip_text.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../helpers/trip.dart';
import 'boxes.dart';
import 'design_check.dart';
import 'samples/c_trip.dart';

// `C-Trip`'s layout check, against its measured boxes or [board]
// (contracts/design-checks.md). The passengers' boxes carry the design's
// labels, which name their type; the app's name their look, seat and stop
// (spec FR-036, M02 FR-033), so each is paired with the app's label for
// that seat. So is the hand's: the shared formatter writes 15.5 as a
// number, not «١٥ ونص».

/// Checks the pumped `C-Trip` sample against [board], `C-Trip`'s own boxes
/// by default.
void expectCTripLayout(WidgetTester tester, {DesignBoard? board}) {
  final l10n = AppLocalizations.of(tester.element(find.byType(TripDashboard)));
  const numbers = NumberFormatter(DigitStyle.arabicIndic);
  final seats = {
    for (final seat in sampleTrip(cTripId).seats) seat.seatId: seat,
  };
  expectLayoutMatches(
    tester,
    'C-Trip',
    board: board,
    skip: {95: 'للنموذج بس: the link to Result is prototype navigation'},
    pairings: {
      for (final s in cTripSeats)
        s.box: l10n.passengerLabel(
          lookKey: looks[s.look]!.labelKey,
          row: seats[s.seatId]!.row,
          col: seats[s.seatId]!.col,
          slot: s.slot,
          stopName: cTripStopName(s.slot),
          owed: s.seatId == 'C_l',
        ),
      55: l10n.tripHandSemantics(numbers.piasters(1550)),
    },
    appOnly: {l10n.tripDebugOpen},
  );
}
