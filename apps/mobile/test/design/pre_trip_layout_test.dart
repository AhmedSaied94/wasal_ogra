import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/pre_trip/presentation/stop_prices.dart';

import 'design_check.dart';
import 'samples/pre_trip.dart';

// `PreTrip` against its measured boxes (specs/013-m08-home-result,
// research R20): ✕ (box 11, «قفل» in the app), the buy chip (box 56,
// which opens the spend confirmation, not the shop) and «اطلع» (box 58).
// The scrim, a box on the board, is also «قفل». The board's «المستشفى»
// (box 21) runs 13 pt out of its cell, beside its tag; the app stacks the
// row's tags over their names instead (FR-027), so the sheet, which sizes
// to its content, is a tag and its gap taller and its header that much
// higher.

/// A stacked cell's tag and the gap under it (`PreTrip` box 16).
const _stacked = 30 + StopPrices.stackGap;

void main() {
  testWidgets('PreTrip: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpPreTrip(tester);
    expectLayoutMatches(
      tester,
      'PreTrip',
      pairings: const {11: 'قفل'},
      tolerances: const {11: 2 + _stacked},
      scrim: 'قفل',
    );
    semantics.dispose();
  });
}
