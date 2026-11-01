import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/story/presentation/scene_panel_view.dart';
import 'package:wassal/features/story/presentation/scene_viewer_page.dart';

import 'boxes.dart';
import 'design_check.dart';
import 'samples/scene_viewer.dart';

// `SceneViewer` against its measured boxes (specs/015-m10-apartment-story,
// T094): the tap boxes (skip 3, share 19, continue 21) by their labels, then
// the panel (4), both bubbles (6, 10) and the dots (14) by their rects.

void main() {
  testWidgets('SceneViewer: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpSceneViewer(tester);
    expectLayoutMatches(tester, 'SceneViewer');

    final board = loadBoard('SceneViewer');
    Rect rect(Finder finder) => tester.getRect(finder);
    void expectAt(String what, Rect actual, int id) {
      final box = board.byId(id);
      final want = Rect.fromLTWH(box.x, box.y, box.w, box.h);
      expect(
        (actual.left - want.left).abs() <= 2 &&
            (actual.top - want.top).abs() <= 2 &&
            (actual.width - want.width).abs() <= 2 &&
            (actual.height - want.height).abs() <= 2,
        isTrue,
        reason: '$what: design $want, app $actual',
      );
    }

    expectAt('panel', rect(find.byKey(SceneViewerPage.panelKey)), 4);
    expectAt('first bubble', rect(find.byKey(ScenePanelView.bubbleKey(0))), 6);
    expectAt(
      'second bubble',
      rect(find.byKey(ScenePanelView.bubbleKey(1))),
      10,
    );
    semantics.dispose();
  });
}
