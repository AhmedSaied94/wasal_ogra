import 'package:flutter_test/flutter_test.dart';

import 'design_check.dart';
import 'samples/buy_vehicle.dart';

// `BuyVehicle` against its measured boxes (specs/014-m09-lines-vehicles,
// T058, research R12): ✕ (box 9, «قفل» in the app), «اشتريها» (32) and
// «لسه» (33). The preview has no «بزينتك» (R10) and the impact line is
// reworded (Clarifications Q4); neither is tappable.

void main() {
  testWidgets('BuyVehicle: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpBuyVehicle(tester);
    expectLayoutMatches(
      tester,
      'BuyVehicle',
      pairings: const {9: 'قفل'},
      scrim: 'قفل',
    );
    semantics.dispose();
  });
}
