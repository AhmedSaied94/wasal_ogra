import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Size;
import 'package:wassal/core/l10n/digit_style.dart';

import '../../helpers/lines.dart';
import '../../helpers/progress.dart';
import '../../helpers/surfaces.dart';
import '../../helpers/synthetic_packs.dart';
import '../design_check.dart';

// `Piece` as the board draws it (T065): the أنتريه at 3,200 with 1,325 in
// hand, so the sheet offers its three styles and «اطلع مشوار».

Future<ProviderContainer> pumpPiece(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
}) async {
  final (container, _) = await pumpLinesApp(
    tester,
    pack: artboardSalon(),
    digits: digits,
    textScale: textScale,
    location: '/apartment/item/salon.antreeh',
    settle: false,
    state: playerState(
      jenehat: 1325,
      stars: hayDone,
      owned: {
        microOld,
        shabka,
        (SkuKind.item, 'salon.nish'),
        (SkuKind.item, 'salon.sitara'),
      },
      styles: const {'salon.nish': 'crystal', 'salon.sitara': 'plain'},
    ),
  );
  if (size == null) {
    applyDesignSurface(tester, const Size(390, 844), topInset: designTopInset);
  } else {
    applySurfaceSize(tester, size);
  }
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return container;
}
