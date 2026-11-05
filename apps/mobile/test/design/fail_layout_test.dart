import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/features/trip/presentation/cards/failure_card.dart';

import 'design_check.dart';
import 'samples/fail.dart';

// `Fail` against its measured boxes (contracts/design-checks.md). Box 12 is
// the rewarded-ad revive (M11), checked also by rect, as are the faces and
// the reason chip.

void main() {
  testWidgets('Fail: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpFail(tester);
    // Box 12 is drawn without a label; the app reads its two lines.
    expectLayoutMatches(
      tester,
      'Fail',
      pairings: {
        12: 'صالح الركاب، إعلان قصير · السمعة ترجع ٤٠٪ وتكمّل من نفس النقطة',
      },
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

    expectRect(
      find.byKey(FailureCard.facesKey),
      const Rect.fromLTWH(90, 140, 210, 70),
    );
    expectRect(
      find.byKey(FailureCard.adSlotKey),
      const Rect.fromLTWH(34, 320, 322, 66),
    );
    final chip = tester.getRect(find.byKey(FailureCard.reasonKey));
    expect(chip.top, closeTo(286, 2));
    expect(chip.height, closeTo(22, 2));
    expect(chip.center.dx, closeTo(195, 2));
    semantics.dispose();
  });
}
