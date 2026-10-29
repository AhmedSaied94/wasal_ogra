import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/bootstrap/app.dart' show appLocale;
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../design/samples/lines.dart';
import '../helpers/screens.dart';
import 'minimum_sizes_test.dart'
    show
        UncutTextContrastGuideline,
        clippedText,
        effectiveFontSizes,
        minTextSize;

// `Lines`'s minimum sizes (specs/014-m09-lines-vehicles, T031, T047,
// T058; constitution XI): targets ≥ 44×44 and text ≥ 12 at text scale 1.0
// and 1.3, on the small, the tall-narrow and the reference phone, with
// nothing cut short.

const _phones = [Size(360, 640), Size(360, 800), Size(390, 844)];

void main() {
  late Set<String> titles;

  setUpAll(() async {
    final l10n = await AppLocalizations.delegate.load(appLocale);
    titles = {for (final d in destinations) d.title(l10n)};
  });

  for (final size in _phones) {
    for (final scale in textScales) {
      testWidgets('Lines · ${size.width.round()}×${size.height.round()} · '
          '×$scale', (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpLines(tester, size: size, textScale: scale);
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
        semantics.dispose();
      });
    }
  }
}
