import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Size;
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/sync/server_status.dart';

import '../../helpers/lines.dart';
import '../../helpers/progress.dart';
import '../../helpers/surfaces.dart';
import '../../helpers/synthetic_packs.dart';
import '../design_check.dart';

// `AptRooms` as the board draws it (T065): the salon with two pieces
// installed (نيش كريستال, ستاير سادة), 1,325 JENEHAT, the أنتريه next at
// 3,200 (1,875 short) and the نجفة at 2,400.
//
// The app ships no salon, نيش, ستاير or نجفة drawings yet, so those layers
// draw their token fallbacks (research R17): the golden records the
// fallbacks, and a new drawing is one entry in `ApartmentArt`.

const _nish = (SkuKind.item, 'salon.nish');
const _sitara = (SkuKind.item, 'salon.sitara');

Future<ProviderContainer> pumpAptRooms(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
  ServerStatusState serverStatus = const ServerStatusState(),
}) async {
  final (container, _) = await pumpLinesApp(
    tester,
    pack: artboardSalon(),
    digits: digits,
    textScale: textScale,
    serverStatus: serverStatus,
    location: '/apartment',
    settle: false,
    state: playerState(
      jenehat: 1325,
      stars: hayDone,
      owned: {microOld, shabka, _nish, _sitara},
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
