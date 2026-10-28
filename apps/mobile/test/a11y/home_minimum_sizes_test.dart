import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/bootstrap/app.dart' show appLocale;
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/features/home/presentation/home_header.dart';
import 'package:wassal/features/home/presentation/home_screen.dart';
import 'package:wassal/features/home/presentation/line_card.dart';
import 'package:wassal/features/home/presentation/savings_card.dart';
import 'package:wassal/features/home/presentation/start_button.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../design/samples/c_home.dart';
import '../helpers/screens.dart';
import 'minimum_sizes_test.dart'
    show
        UncutTextContrastGuideline,
        clippedText,
        effectiveFontSizes,
        minTextSize;

// الموقف's minimum sizes (specs/013-m08-home-result SC-006, constitution
// XI), full as `C-Home` draws it, with the daily row and the morning piggy
// in their slots: targets ≥ 44×44 and text ≥ 12 at text scale 1.0 and
// 1.3, on the small, the tall-narrow and the reference phone. Nothing is
// cut short or overlaps, and the scene card never goes under its least
// height: below it, the column scrolls.

const _phones = [Size(360, 640), Size(360, 800), Size(390, 844)];

void main() {
  late Set<String> titles;

  setUpAll(() async {
    final l10n = await AppLocalizations.delegate.load(appLocale);
    titles = {for (final d in destinations) d.title(l10n)};
  });

  for (final size in _phones) {
    for (final scale in textScales) {
      testWidgets('Home · ${size.width.round()}×${size.height.round()} · '
          '×$scale', (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpCHome(tester, size: size, textScale: scale);

        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(
          tester,
          meetsGuideline(UncutTextContrastGuideline(tester)),
        );
        for (final span in effectiveFontSizes(tester)) {
          expect(
            span.size,
            greaterThanOrEqualTo(minTextSize),
            reason: '"${span.text}"',
          );
        }
        expect(tester.takeException(), isNull);
        expect(clippedText(tester, titles), isEmpty);

        expect(
          tester.getSize(find.byKey(HomeScreen.sceneKey)).height,
          greaterThanOrEqualTo(homeSceneMin),
        );
        // The column's blocks, top to bottom, none over the next.
        final blocks = [
          find.byType(HomeHeader),
          find.byKey(HomeScreen.sceneKey),
          find.byType(HomeLineCard),
          find.byKey(HomeStartButton.startKey),
          find.byType(HomeSavingsCard),
        ].map(tester.getRect).toList();
        for (var i = 1; i < blocks.length; i++) {
          expect(
            blocks[i].top,
            greaterThanOrEqualTo(blocks[i - 1].bottom),
            reason: 'block $i under block ${i - 1}',
          );
        }
        semantics.dispose();
      });
    }
  }
}
