import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/bootstrap/app.dart' show appLocale;
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/features/pre_trip/domain/briefing.dart';
import 'package:wassal/features/pre_trip/presentation/booster_tiles.dart';
import 'package:wassal/features/pre_trip/presentation/pre_trip_card.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../design/samples/pre_trip.dart';
import '../helpers/screens.dart';
import 'minimum_sizes_test.dart'
    show
        UncutTextContrastGuideline,
        clippedText,
        effectiveFontSizes,
        minTextSize;

// The pre-trip card's minimum sizes (specs/013-m08-home-result SC-006,
// constitution XI), full as `PreTrip` draws it over Home: targets ≥ 44×44
// and text ≥ 12 at text scale 1.0 and 1.3, on the small, the tall-narrow
// and the reference phone. Nothing is cut short; the ✕ and «اطلع» stay on
// screen, and the body scrolls between them. A booster's name that wraps
// makes all four tiles that much taller.

const _phones = [Size(360, 640), Size(360, 800), Size(390, 844)];

void main() {
  late Set<String> titles;

  setUpAll(() async {
    final l10n = await AppLocalizations.delegate.load(appLocale);
    titles = {for (final d in destinations) d.title(l10n)};
  });

  for (final size in _phones) {
    for (final scale in textScales) {
      testWidgets('PreTrip · ${size.width.round()}×${size.height.round()} · '
          '×$scale', (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpPreTrip(tester, size: size, textScale: scale);

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

        final screen = Offset.zero & size;
        final close = tester.getRect(find.byKey(PreTripCard.closeKey));
        final body = tester.getRect(find.byKey(PreTripCard.scrollKey));
        final go = tester.getRect(find.byKey(PreTripCard.goKey));
        for (final rect in [close, go]) {
          expect(screen.intersect(rect), rect);
        }
        expect(body.top, greaterThanOrEqualTo(close.bottom));
        expect(go.top, greaterThanOrEqualTo(body.bottom));
        final tileHeights = {
          for (final booster in boosterTileOrder)
            tester.getSize(find.byKey(BoosterTiles.tileKey(booster))).height,
        };
        expect(tileHeights, hasLength(1));
        semantics.dispose();
      });
    }
  }
}
