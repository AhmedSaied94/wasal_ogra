// The apartment goal view's minimum sizes (specs/015-m10-apartment-story
// SC-006, constitution XI): targets ≥ 44×44 and text ≥ 12 at text scale 1.0
// and 1.3, on the small, the tall-narrow and the reference phone, in
// chapter 1 and in the ready state. Nothing is cut short.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/bootstrap/app.dart' show appLocale;
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../helpers/lines.dart';
import '../helpers/progress.dart';
import '../helpers/screens.dart';
import 'minimum_sizes_test.dart'
    show
        UncutTextContrastGuideline,
        clippedText,
        effectiveFontSizes,
        minTextSize;

const _phones = [Size(360, 640), Size(360, 800), Size(390, 844)];

void main() {
  late Set<String> titles;

  setUpAll(() async {
    final l10n = await AppLocalizations.delegate.load(appLocale);
    titles = {for (final d in destinations) d.title(l10n)};
  });

  Future<void> expectMinimumSizes(WidgetTester tester) async {
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
  }

  for (final (label, ready) in [('chapter 1', false), ('ready', true)]) {
    for (final size in _phones) {
      for (final scale in textScales) {
        testWidgets(
          'AptGoal · $label · ${size.width.round()}×${size.height.round()} · '
          '×$scale',
          (tester) async {
            final semantics = tester.ensureSemantics();
            await pumpLinesApp(
              tester,
              pack: samplePackJsonForLines(),
              location: '/apartment',
              size: size,
              textScale: scale,
              state: ready
                  ? playerState(jenehat: 900, stars: hayDone, owned: {microOld})
                  : playerState(),
              // The bar animates: nothing settles.
              settle: false,
            );
            await expectMinimumSizes(tester);
            semantics.dispose();
          },
        );
      }
    }
  }
}
