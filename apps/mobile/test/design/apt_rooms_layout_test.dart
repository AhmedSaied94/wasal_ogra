import 'package:flutter_test/flutter_test.dart';

import 'design_check.dart';
import 'samples/apt_rooms.dart';

// `AptRooms` against its measured boxes (specs/015-m10-apartment-story,
// T065, again for T131). Expected differences:
// - the rewards chip now sits in the header row beside the coins pill (the
//   boards of 2026-10-31), so the bar, the tabs and the requests button sit
//   where the board draws them and no longer 18 pt lower;
// - the two chips follow their slots in the drawing, and the grid's cards
//   are one control each whose label is their text; the board measures the
//   chips at its own places. The goldens keep the drawn result;
// - the tabs are drawn 36 high but hit 44 (the board's 4 above and below the
//   face, SC-006), so their boxes are 4 taller each way (tolerance 4.5);
// - the synthetic pack names the chapter «الصالون», the board «الصالة», and
//   the grid's order and cards are the pack's, not the board's.

void main() {
  testWidgets('AptRooms: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpAptRooms(tester);
    expectLayoutMatches(
      tester,
      'AptRooms',
      pairings: const {
        4: 'الفصل ٤: الصالون، جهّزت ٢ من ٤، كل الفصول',
        11: 'الصالة',
        12: 'المطبخ، مقفولة',
        14: 'أوضة النوم، مقفولة',
        16: 'طلبات أهل العروسة، ٢ مفتوحين',
      },
      tolerances: const {11: 4.5, 12: 4.5, 14: 4.5},
      skip: const {
        21: 'the chip follows its slot in the drawing',
        24: 'the chip follows its slot in the drawing',
        34: 'the grid card is one control, labelled by its text',
        39: 'the grid card is one control, labelled by its text',
      },
      appOnly: const {
        'الأنتريه، ٣٬٢٠٠ جنيه',
        'النجفة، ٢٬٤٠٠ جنيه',
        'الأنتريه\nناقصك ١٬٨٧٥',
        'النجفة\n٢٬٤٠٠ ج',
        'الأنتريه، ناقصك ١٬٨٧٥ جنيه',
      },
    );
    semantics.dispose();
  });
}
