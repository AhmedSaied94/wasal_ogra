import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/characters.dart';
import 'package:wassal/core/theme/components/containers.dart';
import 'package:wassal/features/onboarding/presentation/fuel_lesson_screen.dart';

import 'design_check.dart';
import 'samples/fuel_lesson.dart';

// `FuelLesson` against its measured boxes (specs/012-m07-onboarding/
// contracts/fuel-lesson.md, ci-checks.md): «يلا على المشوار» (box 13) by its
// tap; the card (2), the avatar (3), المعلم's bubble (6) and the gauge with
// its value (9) by their rects.

void main() {
  testWidgets('FuelLesson: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpFuelLesson(tester);
    expectLayoutMatches(tester, 'FuelLesson');

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
      find.byType(AppCard),
      const Rect.fromLTWH(16, 174.8, 358, 502.5),
    );
    expectRect(
      find.byKey(FuelLessonScreen.avatarKey),
      const Rect.fromLTWH(139, 118.8, 112, 112),
    );
    expectRect(
      find.byType(SpeechBubble),
      const Rect.fromLTWH(36, 298.4, 318, 82.9),
    );
    expectRect(
      find.byKey(FuelLessonScreen.gaugeKey),
      const Rect.fromLTWH(85, 395.2, 220, 150),
    );
    semantics.dispose();
  });
}
