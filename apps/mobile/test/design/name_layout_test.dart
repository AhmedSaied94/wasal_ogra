import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/containers.dart';
import 'package:wassal/core/theme/components/controls.dart';
import 'package:wassal/features/onboarding/presentation/name_screen.dart';

import 'design_check.dart';
import 'samples/name.dart';

// `Name` against its measured boxes (specs/012-m07-onboarding/contracts/
// ci-checks.md): the dice (box 9) and «تمام» (box 12) by their taps; the
// field (box 8), the card and the avatar by their rects.

void main() {
  testWidgets('Name: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpName(tester);
    expectLayoutMatches(
      tester,
      'Name',
      // The board's input is a box, not a tap; it is matched by its rect.
      appOnly: {'اسمك'},
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
      find.byKey(AppTextField.frameKey),
      const Rect.fromLTWH(98, 427.3, 256, 54),
    );
    expectRect(
      find.byType(AppCard),
      const Rect.fromLTWH(16, 249.7, 358, 352.6),
    );
    expectRect(
      find.byKey(NameScreen.avatarKey),
      const Rect.fromLTWH(139, 193.7, 112, 112),
    );
    semantics.dispose();
  });
}
