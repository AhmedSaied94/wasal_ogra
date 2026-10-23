import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/controls.dart';
import 'package:wassal/features/trip/presentation/cards/pause_card.dart';

import 'design_check.dart';
import 'samples/pause.dart';

// `Pause` against its measured boxes (contracts/design-checks.md). The
// switches' tap boxes are their 52×30 tracks; the app's whole row toggles
// (HANDOFF §3.3, at least 44 high), so the rows are checked by their
// tracks' rects instead.

const _wholeRow = 'the whole row toggles; its track is checked by rect';

void main() {
  testWidgets('Pause: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpPause(tester);
    expectLayoutMatches(
      tester,
      'Pause',
      skip: {18: _wholeRow, 21: _wholeRow},
      appOnly: {'الصوت', 'الاهتزاز'},
    );

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

    Finder track(Key row) => find.descendant(
      of: find.byKey(row),
      matching: find.byKey(AppSwitch.trackKey),
    );
    expectRect(
      track(PauseCard.soundKey),
      const Rect.fromLTWH(200, 563, 52, 30),
    );
    expectRect(
      track(PauseCard.hapticsKey),
      const Rect.fromLTWH(34, 563, 52, 30),
    );
    expectRect(
      find.byKey(PauseCard.artKey),
      const Rect.fromLTWH(159, 192, 72, 56),
    );
    semantics.dispose();
  });
}
