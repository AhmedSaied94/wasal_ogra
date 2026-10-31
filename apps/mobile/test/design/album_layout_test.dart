import 'package:flutter_test/flutter_test.dart';

import 'design_check.dart';
import 'samples/chapters.dart';

// `Album` against its measured boxes (specs/015-m10-apartment-story, T109):
// the back control and the three unlocked cards, by their labels. The album
// follows the pack's scenes, not the board's one per chapter (Q3, research
// R18): the sample's seven are the board's titles, so its cards match; a real
// pack's differ by design. The locked cards aren't controls.

void main() {
  testWidgets('Album: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpAlbum(tester);
    expectLayoutMatches(tester, 'Album');
    semantics.dispose();
  });
}
