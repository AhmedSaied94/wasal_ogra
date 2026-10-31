// RoomDone's minimum sizes (specs/015-m10-apartment-story SC-006,
// constitution XI, T074): targets ≥ 44×44 and text ≥ 12 at both scales on
// the three phones.
import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/bootstrap/app.dart' show appLocale;
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/features/apartment/presentation/piece_sheet.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../helpers/lines.dart';
import '../helpers/progress.dart';
import '../helpers/screens.dart';
import '../helpers/synthetic_packs.dart';
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

  for (final size in _phones) {
    for (final scale in textScales) {
      testWidgets(
        'RoomDone · ${size.width.round()}×${size.height.round()} · ×$scale',
        (tester) async {
          final semantics = tester.ensureSemantics();
          final all = [
            for (final item in artboardSalonContent().itemsOf(RoomId.salon))
              item.itemId,
          ];
          await pumpLinesApp(
            tester,
            pack: artboardSalon(),
            location: '/apartment/item/${all.last}',
            size: size,
            textScale: scale,
            settle: false,
            state: playerState(
              jenehat: 5000,
              stars: hayDone,
              owned: {
                microOld,
                shabka,
                for (final id in all.take(3)) (SkuKind.item, id),
              },
              styles: const {
                'salon.nish': 'classic',
                'salon.sitara': 'plain',
                'salon.antreeh': 'classic',
              },
            ),
          );
          await tester.tap(find.byKey(PieceSheet.buyKey));
          for (var i = 0; i < 14; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
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
