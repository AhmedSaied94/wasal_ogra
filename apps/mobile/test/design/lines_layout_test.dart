import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/lines/presentation/line_card.dart';

import 'boxes.dart';
import 'design_check.dart';
import 'samples/lines.dart';

// The Lines boards against their measured boxes
// (specs/014-m09-lines-vehicles, T030, T076, research R12).
//
// `Lines`' expected differences:
// - the five line cards carry no label on the board (boxes 25, 31, 37, 43,
//   52): each is paired with the app's «{line}، {standing}، {detail}»;
// - they sit 32 pt lower: the boards of 2026-10-29 stand the cards on the
//   map's bottom, 12 above the bar, with the road's end above them, where
//   `Lines` hung them from the top;
// - خط الجامعة's card is 4 pt taller (box 43), and the three above it 4 pt
//   higher: those boards pad a card 14 with 3 between its rows, where
//   `Lines` fixed every card at 92;
// - «كمّل» is its own button (Clarifications Q3): checked against box 51,
//   a text box on the board;
// - the safar microbus comes after the new one, so it isn't for sale yet:
//   its tile reads «مقفولة», not its price (box 20);
// - the BONAT pill is 5 pt wider than the board's (box 4): Flutter measures
//   its digits wider than the browser did, and its hit area is 44 high.
//
// `LinesFirst` and `LinesOwned` share the pill's difference, and its label
// names the shop too.

const _lower = Offset(0, 32);
const _higher = Offset(0, 32 - 4);

void main() {
  testWidgets('Lines: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpLines(tester);
    expectLayoutMatches(
      tester,
      'Lines',
      pairings: const {
        // The BONAT pill's label also names the shop.
        4: 'البونات ٨٥، افتح المحل',
        69: 'المحل',
        20: 'ميكروباص سفر، مقفولة',
        25: 'خط السفر، مقفول، محتاج ميكروباص سفر',
        31: 'خط المصيف، مقفول، بعد خط السوق',
        37: 'خط السوق، مقفول، محتاج ميكروباص جديد',
        43: 'خط الجامعة، الحالي، ٢٥ من ٩٠ نجمة، المشوار ١٢ من ٣٠',
        52: 'خط الحي، خلص، ٥٤ من ٦٠ نجمة',
      },
      appOnly: const {'كمّل المشوار ١٢', 'الجنيهات ١٬٢٤٠'},
      // The pill's digits, and خط الجامعة's card, padded as the later
      // boards pad it; the other cards pass at the standard 2 (T105).
      tolerances: const {4: 5, 43: 5},
      offsets: const {
        25: _higher,
        31: _higher,
        37: _higher,
        43: _lower,
        52: _lower,
      },
    );
    final go = tester.getRect(
      find.byKey(LineCard.continueKeyOf(LineId.lineGamaa)),
    );
    final box = loadBoard('Lines').boxes.firstWhere((b) => b.id == 51);
    expect(go.left, closeTo(box.x, 2));
    expect(go.width, closeTo(box.w, 2));
    semantics.dispose();
  });

  testWidgets('LinesFirst: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpLinesFirst(tester);
    expectLayoutMatches(
      tester,
      'LinesFirst',
      pairings: const {4: 'البونات ٨٥، افتح المحل', 42: 'المحل'},
      appOnly: const {'الجنيهات ١٬٢٤٠'},
      tolerances: const {4: 5},
    );
    semantics.dispose();
  });

  testWidgets('LinesOwned: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpLinesOwned(tester);
    expectLayoutMatches(
      tester,
      'LinesOwned',
      pairings: const {4: 'البونات ٨٥، افتح المحل', 43: 'المحل'},
      appOnly: const {'الجنيهات ١٬٢٤٠'},
      tolerances: const {4: 5},
    );
    semantics.dispose();
  });
}
