import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/lines/presentation/line_card.dart';

import 'boxes.dart';
import 'design_check.dart';
import 'samples/lines.dart';

// `Lines` against its measured boxes (specs/014-m09-lines-vehicles, T030,
// research R12). Expected differences:
// - the five line cards carry no label on the board (boxes 25, 31, 37, 43,
//   52): each is paired with the app's «{line}، {standing}، {detail}»;
// - «كمّل» is its own button (Clarifications Q3): checked against box 51,
//   a text box on the board;
// - the safar microbus comes after the new one, so it isn't for sale yet:
//   its tile reads «مقفولة», not its price (box 20).

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
      // The pill's hit area is 44 high, and Flutter measures its digits
      // wider than the browser did. The app's bottom bar starts 3 pt lower
      // than the board's, and the bottom-up map follows it.
      tolerances: const {4: 5, 43: 3, 52: 3},
    );
    final go = tester.getRect(
      find.byKey(LineCard.continueKeyOf(LineId.lineGamaa)),
    );
    final box = loadBoard('Lines').boxes.firstWhere((b) => b.id == 51);
    expect(go.left, closeTo(box.x, 2));
    expect(go.width, closeTo(box.w, 2));
    semantics.dispose();
  });
}
