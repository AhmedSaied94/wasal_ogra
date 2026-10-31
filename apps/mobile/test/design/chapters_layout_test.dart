import 'package:flutter_test/flutter_test.dart';

import 'design_check.dart';
import 'samples/chapters.dart';

// `Chapters` against its measured boxes (specs/015-m10-apartment-story,
// T109): the back control, the album pill and the three «شوف المشهد»
// buttons, which a screen reader hears with their chapter's number, so each
// is paired to its label. Expected differences:
// - the current row's description names the pack's pieces: the sample's
//   ستارة, where the board has «الستاير»;
// - the row, rail and node boxes aren't controls, so the check leaves them
//   to the goldens and to chapters_page_test.dart.

void main() {
  testWidgets('Chapters: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpChapters(tester);
    expectLayoutMatches(
      tester,
      'Chapters',
      pairings: const {
        15: 'شوف المشهد: سلمى في الموقف',
        23: 'شوف المشهد: «بتشتغل إيه؟»',
        31: 'شوف المشهد: قراءة الفاتحة',
      },
    );
    semantics.dispose();
  });
}
