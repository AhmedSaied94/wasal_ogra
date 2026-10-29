import 'package:flutter_test/flutter_test.dart';

import 'design_check.dart';
import 'samples/buy_vehicle.dart';

// The BuyVehicle boards against their measured boxes
// (specs/014-m09-lines-vehicles, T058, T078, research R12): ✕ («قفل» in the
// app), «اشتريها» and «لسه», or «تمام». The preview has no «بزينتك» (R10)
// and the impact line is reworded (Clarifications Q4); neither is
// tappable. `BuyVehicleShort` draws its disabled «اشتريها» as a <button>,
// whose default padding moves the 2:1 split 4 pt (boxes 31 and 32); the
// app splits the two as `BuyVehicle` does.

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

  testWidgets('BuyVehicleShort: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpBuyVehicleShort(tester);
    expectLayoutMatches(
      tester,
      'BuyVehicleShort',
      pairings: const {9: 'قفل'},
      tolerances: const {31: 5, 32: 5},
      scrim: 'قفل',
    );
    semantics.dispose();
  });

  testWidgets('BuyVehicleOwned: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpBuyVehicleOwned(tester);
    expectLayoutMatches(
      tester,
      'BuyVehicleOwned',
      pairings: const {10: 'قفل'},
      scrim: 'قفل',
    );
    semantics.dispose();
  });

  testWidgets('BuyVehicleNotForSale: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpBuyVehicleNotForSale(tester);
    expectLayoutMatches(
      tester,
      'BuyVehicleNotForSale',
      pairings: const {9: 'قفل'},
      scrim: 'قفل',
    );
    semantics.dispose();
  });
}
