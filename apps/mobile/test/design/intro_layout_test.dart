import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/story.dart';
import 'package:wassal/features/onboarding/presentation/scene_player.dart';

import 'design_check.dart';
import 'samples/intro.dart';

// `Intro` against its measured boxes (specs/012-m07-onboarding/contracts/
// ci-checks.md): the two taps, «تخطّى» (box 2) and «يلا» (box 14), and the
// panel, its caption and bubble, and the dots by their rects.

void main() {
  testWidgets('Intro: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpIntro(tester);
    expectLayoutMatches(tester, 'Intro');

    void expectRect(Finder finder, Rect design) {
      final rect = tester.getRect(finder);
      for (final (edge, app, want) in [
        ('left', rect.left, design.left),
        ('top', rect.top, design.top),
        ('width', rect.width, design.width),
        ('height', rect.height, design.height),
      ]) {
        expect(app, closeTo(want, 2), reason: '$finder $edge');
      }
    }

    expectRect(
      find.byKey(ScenePlayer.panelKey),
      const Rect.fromLTWH(16, 96, 358, 540),
    );
    expectRect(
      find.byKey(ComicPanel.captionKey),
      const Rect.fromLTWH(30, 110, 148.4, 26),
    );
    expectRect(
      find.byKey(ComicPanel.bubbleKey(0)),
      const Rect.fromLTWH(124, 172, 236, 119.6),
    );
    expectRect(
      find.byKey(PageDots.dotKey(0)),
      const Rect.fromLTWH(200, 652, 26, 10),
    );
    expectRect(
      find.byKey(PageDots.dotKey(2)),
      const Rect.fromLTWH(164, 652, 10, 10),
    );
    semantics.dispose();
  });
}
