import 'package:flutter_test/flutter_test.dart';

import 'design_check.dart';
import 'samples/line_details.dart';

// `LineDetails` against its measured boxes (specs/014-m09-lines-vehicles,
// T046, research R12). Expected differences: ✕ is «قفل» (M08's pairing),
// the cells read «خلص بـ…» and the story cell «…، مشوار قصة» after the
// state (R13), and the real Lines sits under the scrim.

void main() {
  testWidgets('LineDetails: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpLineDetails(tester);
    expectLayoutMatches(
      tester,
      'LineDetails',
      pairings: const {
        12: 'قفل',
        15: 'المشوار ١، خلص بتلات نجوم',
        18: 'المشوار ٢، خلص بتلات نجوم',
        21: 'المشوار ٣، خلص بنجمتين',
        25: 'المشوار ٤، خلص بتلات نجوم',
        28: 'المشوار ٥، خلص بنجمتين',
        32: 'المشوار ٦، خلص بنجمتين',
        36: 'المشوار ٧، خلص بنجمة',
        40: 'المشوار ٨، خلص بتلات نجوم',
        43: 'المشوار ٩، خلص بنجمتين',
        47: 'المشوار ١٠، خلص بتلات نجوم، مشوار قصة',
        51: 'المشوار ١١، خلص بنجمة',
      },
      scrim: 'قفل',
    );
    semantics.dispose();
  });
}
