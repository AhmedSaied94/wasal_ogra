import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/bootstrap/app.dart' show appLocale;
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/features/result/presentation/result_screen.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../design/samples/result.dart';
import '../helpers/screens.dart';
import 'minimum_sizes_test.dart'
    show
        UncutTextContrastGuideline,
        clippedText,
        effectiveFontSizes,
        minTextSize;

// The result's minimum sizes (specs/013-m08-home-result SC-006,
// constitution XI), as `Result` draws it with its slots empty, as this
// feature ships it: targets ≥ 44×44 and text ≥ 12 at text scale 1.0 and
// 1.3, on the small, the tall-narrow and the reference phone, at the top
// and scrolled to «مشوار تاني». Nothing is cut short.

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

  for (final size in _phones) {
    for (final scale in textScales) {
      testWidgets('Result · ${size.width.round()}×${size.height.round()} · '
          '×$scale', (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpResult(tester, size: size, textScale: scale, slots: false);
        await expectMinimumSizes(tester);
        final back = tester.getRect(find.byKey(ResultScreen.backKey));
        expect((Offset.zero & size).intersect(back), back);

        await tester.ensureVisible(find.byKey(ResultScreen.againKey));
        await tester.pump();
        await expectMinimumSizes(tester);
        semantics.dispose();
      });
    }
  }
}
