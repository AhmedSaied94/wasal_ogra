import 'package:flutter_test/flutter_test.dart';

import 'design_check.dart';
import 'samples/piece.dart';

// `Piece` against its measured boxes (specs/015-m10-apartment-story, T065).
// Expected differences:
// - ✕ is «قفل» (M08's pairing), and the real apartment sits under the scrim;
// - the fuel chip is «−١» with the fuel icon (§9.1 #4), where the board
//   writes «−١ لتر» (a text node of its own, with no box in the check);
// - the sheet's bottom padding is 14 where the board leaves 11 under the
//   button, so the button starts 3 higher and ends at the same place.

void main() {
  testWidgets('Piece: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpPiece(tester);
    expectLayoutMatches(
      tester,
      'Piece',
      pairings: const {10: 'قفل'},
      tolerances: const {33: 3},
      scrim: 'قفل',
    );
    semantics.dispose();
  });
}
