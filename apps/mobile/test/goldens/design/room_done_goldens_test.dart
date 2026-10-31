import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';

import '../../design/design_check.dart';
import '../../design/samples/room_done.dart';

// `RoomDone` as the app draws it, beside docs/design/png/RoomDone.png
// (specs/015-m10-apartment-story, T073), in both digit styles.

void main() {
  for (final digits in DigitStyle.values) {
    testWidgets('RoomDone, ${digits.name}', (tester) async {
      await pumpRoomDone(tester, digits: digits);
      await expectDesignGolden(
        tester,
        find.byType(WassalApp),
        'RoomDone',
        digits,
      );
    });
  }
}
