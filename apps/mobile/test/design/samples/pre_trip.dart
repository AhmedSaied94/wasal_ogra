import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Size;
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/routing/router.dart';

import '../../helpers/progress.dart';
import 'c_home.dart';

// `PreTrip` over `C-Home`: trip 12 of خط الجامعة, three stops (الكوبري ٤٫٥،
// المستشفى ٧، الجامعة ٩), the student rule at half, أبو سمّاعة new, and the
// boosters 1, 1, 0, 2, so the chip offers صحّي النايم at 8.
//
// The board also shows two stars, which can't hold with «جديد»: a trip at
// a star counts its passengers as met (research R5). The sample keeps the
// new card, and the stars read «لسه»; the block is the same height.

/// The board's trip, made from line_gamaa.02's stops and riders: أبو
/// سمّاعة first, then a student, at the half fare.
void boardTrip12(Map<String, Object?> json) {
  final twelve = entry(json, 'trips', 'trip_id', 'line_gamaa.12');
  // The board's pack copies line_gamaa.01 thirty times; the sample's own
  // line_gamaa.02 has the three stops.
  final two = entry(sampleJsonCopy(), 'trips', 'trip_id', 'line_gamaa.02');
  final riders = [
    for (final p in two['passengers']! as List<Object?>)
      {...p! as Map<String, Object?>},
  ];
  riders[0]
    ..['archetype'] = 'headphones'
    ..['skin'] = 'headphones';
  riders[1]
    ..['archetype'] = 'student'
    ..['skin'] = 'student_cap';
  twelve
    ..['stations'] = two['stations']
    ..['seats'] = two['seats']
    ..['passengers'] = riders
    ..['events'] = <Object?>[]
    ..['rules'] = {
      ...two['rules']! as Map<String, Object?>,
      'student_discount_pct': 50,
    };
}

Future<void> pumpPreTrip(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
}) async {
  final container = await pumpCHome(
    tester,
    digits: digits,
    size: size,
    textScale: textScale,
    editPack: boardTrip12,
    editState: (state) => state.copyWith(
      inventory: {
        BoosterId.changeBag: 1,
        BoosterId.ledgerPeek: 1,
        BoosterId.trafficJam: 2,
      },
    ),
  );
  container.read(routerProvider).go('/home/pre-trip/line_gamaa.12');
  // The sheet rises; Home's countdown keeps ticking under it.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
