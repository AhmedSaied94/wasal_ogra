import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Size;
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/sync/server_status.dart';

import '../../design/design_check.dart';
import '../../design/samples/apt_rooms.dart';

// `AptRooms` as the app draws it, beside docs/design/png/AptRooms.png
// (specs/015-m10-apartment-story, T065), in both digit styles. Two states no
// board draws (research R18): offline, and a 360×640 phone at 1.3×.

void main() {
  for (final digits in DigitStyle.values) {
    testWidgets('AptRooms, ${digits.name}', (tester) async {
      await pumpAptRooms(tester, digits: digits);
      await expectDesignGolden(
        tester,
        find.byType(WassalApp),
        'AptRooms',
        digits,
      );
    });

    testWidgets('AptRoomsOffline, ${digits.name}', (tester) async {
      await pumpAptRooms(
        tester,
        digits: digits,
        serverStatus: const ServerStatusState(reach: Reach.offline),
      );
      await expectDesignGolden(
        tester,
        find.byType(WassalApp),
        'AptRoomsOffline',
        digits,
      );
    });

    testWidgets('AptRoomsSmall, ${digits.name}', (tester) async {
      await pumpAptRooms(
        tester,
        digits: digits,
        size: const Size(360, 640),
        textScale: 1.3,
      );
      await expectDesignGolden(
        tester,
        find.byType(WassalApp),
        'AptRoomsSmall',
        digits,
      );
    });
  }
}
