import 'dart:convert';

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

// `Requests` as the board draws it (specs/015-m10-apartment-story, T117): the
// red curtain in, so the first request is done and claimable; the نجفة not
// bought, so the second is open; and the نيش in another style, so its request
// is missed and not listed. The board's second request is أم العروسة's (the
// pack's is her husband's, as `Piece` has it), so the sample gives it to her.

Map<String, Object?> requestsPack() {
  final json = jsonDecode(jsonEncode(artboardSalon())) as Map<String, Object?>;
  for (final request in json['family_requests']! as List<Object?>) {
    final map = request! as Map<String, Object?>;
    if (map['request_id'] == 'req_nagfa_crystal') {
      map['character'] = 'bride_mother';
    }
  }
  return json;
}

Future<ProviderContainer> pumpRequests(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
}) async {
  final (container, _) = await pumpLinesApp(
    tester,
    pack: requestsPack(),
    digits: digits,
    textScale: textScale,
    location: '/apartment/requests',
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
      styles: const {'salon.nish': 'classic', 'salon.sitara': 'red'},
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
