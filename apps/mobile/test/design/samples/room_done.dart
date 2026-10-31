import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Size;
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/features/apartment/presentation/piece_sheet.dart';

import '../../helpers/lines.dart';
import '../../helpers/progress.dart';
import '../../helpers/surfaces.dart';
import '../../helpers/synthetic_packs.dart';
import '../design_check.dart';

// `RoomDone` as the board draws it (T073): the salon's last piece bought,
// so the room and chapter 4 complete, and the dialog opens over the tab.

Future<ProviderContainer> pumpRoomDone(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
}) async {
  final all = [
    for (final item in artboardSalonContent().itemsOf(RoomId.salon))
      item.itemId,
  ];
  final (container, _) = await pumpLinesApp(
    tester,
    pack: artboardSalon(),
    digits: digits,
    textScale: textScale,
    location: '/apartment/item/${all.last}',
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
  if (size == null) {
    applyDesignSurface(tester, const Size(390, 844), topInset: designTopInset);
  } else {
    applySurfaceSize(tester, size);
  }
  await tester.tap(find.byKey(PieceSheet.buyKey));
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return container;
}
