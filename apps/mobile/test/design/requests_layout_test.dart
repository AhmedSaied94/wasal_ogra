import 'package:flutter_test/flutter_test.dart';

import 'design_check.dart';
import 'samples/requests.dart';

// `Requests` against its measured boxes (specs/015-m10-apartment-story,
// T117). Expected differences:
// - ✕ is «قفل» (M08's pairing), and the real apartment sits under the scrim;
// - the counted row (boxes 27 to 35, «٣ مشاوير بتلات نجوم») is not built:
//   the server's `claim_request` checks only a piece and its style
//   (B03 R9, research R11). It draws no control, so no tap box is left out;
//   the goldens show the list without it;
// - the open row's condition reads «النجفة بشكل «كريستال»», where the board
//   has «اختار شكل «كريستال» للنجفة» (R11: no preposition joins a name);
// - «خد» is 44 wide, where the browser measured Marhey's «خد» at 49.9 (the
//   button is the label with 12 at each side, and Flutter measures the label
//   narrower); its start edge and height match.

void main() {
  testWidgets('Requests: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpRequests(tester);
    expectLayoutMatches(
      tester,
      'Requests',
      pairings: const {11: 'قفل'},
      tolerances: const {19: 6},
      scrim: 'قفل',
    );
    semantics.dispose();
  });
}
