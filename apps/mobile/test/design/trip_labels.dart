import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/trip/presentation/dashboard/hand_slot.dart';
import 'package:wassal/features/trip/presentation/dashboard/tray.dart';
import 'package:wassal/features/trip/presentation/overlays/hit_areas.dart';

// The app's labels the trip artboards pair or leave out
// (contracts/design-checks.md "Skips and pairings").

/// The drawer's denominations in reading order, as the artboards number
/// their tray boxes.
const trayDenominations = [50, 100, 500, 1000, 2000, 5000, 10000, 20000];

/// Each tray box of [boxes] (in [trayDenominations] order) paired with the
/// app's label for that cell: the artboards draw only «×N».
Map<int, String> trayPairings(WidgetTester tester, List<int> boxes) => {
  for (final (i, box) in boxes.indexed)
    box: tester
        .widget<TrayCell>(
          find.descendant(
            of: find.byKey(Tray.slotKey(trayDenominations[i])),
            matching: find.byType(TrayCell),
          ),
        )
        .semanticLabel!,
};

/// The labels of [passengerIds]' hit areas, for artboards that don't draw
/// the passengers as taps. Needs semantics on.
Set<String> passengerLabels(
  WidgetTester tester,
  Iterable<String> passengerIds,
) => {
  for (final id in passengerIds)
    tester.getSemantics(find.byKey(HitAreas.keyOf(id))).label,
};

/// The hand's and the call button's labels, for artboards that draw the
/// call button without its megaphone and so skip both. Needs semantics on.
Set<String> megaphoneLabels(WidgetTester tester) => {
  tester.getSemantics(find.byKey(HandSlot.slotKey)).label,
  tester.getSemantics(find.byKey(CallChangeButton.buttonKey)).label,
};
