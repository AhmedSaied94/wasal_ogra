import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/containers.dart';
import 'package:wassal/features/boot/boot_screen.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../helpers/design_component.dart';
import 'design_check.dart';
import 'samples/loading.dart';

// `Loading` against its measured boxes (contracts/design-checks.md). The
// board's only tap is prototype navigation, so the bar and the wordmark are
// checked by their rects (HANDOFF `Loading` blocks 1 and 4).

void main() {
  testWidgets('Loading: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpDesignComponent(
      tester,
      const BootScreen(),
      overrides: loadingSampleOverrides(),
    );
    await tester.pumpAndSettle();
    expectLayoutMatches(
      tester,
      'Loading',
      skip: {9: 'the full-screen link to Intro is prototype navigation'},
    );

    final l10n = AppLocalizations.of(tester.element(find.byType(BootScreen)));
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

    expectRect(find.byType(ProgressBar), const Rect.fromLTWH(45, 668, 300, 24));
    expectRect(
      find.text(l10n.appName),
      const Rect.fromLTWH(50.5, 210, 288.9, 66),
    );
    expectRect(
      find.byKey(BootScreen.vehicleKey),
      const Rect.fromLTWH(45, 341, 300, 170),
    );
    expectRect(
      find.byKey(ProgressBar.roadMarkerKey),
      const Rect.fromLTWH(137, 658, 44, 30),
    );
    expectRect(
      find.text(l10n.loadingLine1),
      const Rect.fromLTWH(154.3, 706, 81.5, 20),
    );
    semantics.dispose();
  });
}
