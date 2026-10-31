import 'package:flutter_test/flutter_test.dart';

import 'design_check.dart';
import 'samples/apt_goal.dart';

// `AptGoal` and `AptGoalReady` against their measured boxes (specs/015-m10-
// apartment-story, T049): the chapter bar (box 4, the whole bar a control)
// and the ready state's buy CTA (box 21). The card, its art, row, bar, line
// and teaser are inert, as the boards draw them. The ready state's CTA sits
// under the card, where the board puts it.
//
// Expected difference (T131, after the 2026-10-31 boards drew the character
// line 66 high when it is one line): the sample's ready line is one line,
// where `AptGoalReady`'s «يعني جاهز؟ وريني بقى ذوقك يا ابني» wraps to two, so
// the line box is 66 and not 81.8 and the CTA sits 15.8 higher.

void main() {
  testWidgets('AptGoal: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpAptGoal(tester);
    expectLayoutMatches(
      tester,
      'AptGoal',
      pairings: const {4: 'الفصل ٣: الشبكة، كل الفصول'},
    );
    semantics.dispose();
  });

  testWidgets('AptGoalReady: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpAptGoal(tester, ready: true);
    expectLayoutMatches(
      tester,
      'AptGoalReady',
      pairings: const {
        4: 'الفصل ٣: الشبكة، كل الفصول',
        // The app's a11y label carries the price (M09's pattern).
        21: 'اشتري الشبكة بـ٦٬٠٠٠ جنيه',
      },
      offsets: const {21: Offset(0, -15.8)},
    );
    semantics.dispose();
  });
}
