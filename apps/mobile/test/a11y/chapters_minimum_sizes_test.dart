// The timeline's and the album's minimum sizes (specs/015-m10-apartment-
// story SC-006, constitution XI, T110): targets ≥ 44×44 and text ≥ 12 at both
// scales on the three phones, and nothing clipped or overflowing.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/bootstrap/app.dart' show appLocale;
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../design/samples/chapters.dart';
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

  for (final (name, pump) in [
    ('Chapters', pumpChapters),
    ('Album', pumpAlbum),
  ]) {
    for (final size in _phones) {
      for (final scale in textScales) {
        testWidgets(
          '$name · ${size.width.round()}×${size.height.round()} · ×$scale',
          (tester) async {
            final semantics = tester.ensureSemantics();
            await pump(tester, size: size, textScale: scale);
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
          },
        );
      }
    }
  }
}
