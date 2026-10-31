import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Size;
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/sync/server_status.dart';

import '../../design/design_check.dart';
import '../../design/samples/apt_goal.dart';

// الشقة before chapter 4 as the app draws it, beside
// docs/design/png/AptGoal.png and AptGoalReady.png (specs/015-m10-apartment-
// story, T049), in both digit styles. Two states no board draws (research
// R18): offline, and a 360×640 phone at 1.3×.

void main() {
  for (final digits in DigitStyle.values) {
    testWidgets('AptGoal, ${digits.name}', (tester) async {
      await pumpAptGoal(tester, digits: digits);
      await expectDesignGolden(
        tester,
        find.byType(WassalApp),
        'AptGoal',
        digits,
      );
    });
    testWidgets('AptGoalReady, ${digits.name}', (tester) async {
      await pumpAptGoal(tester, ready: true, digits: digits);
      await expectDesignGolden(
        tester,
        find.byType(WassalApp),
        'AptGoalReady',
        digits,
      );
    });
    testWidgets('AptGoalOffline, ${digits.name}', (tester) async {
      await pumpAptGoal(
        tester,
        digits: digits,
        serverStatus: const ServerStatusState(reach: Reach.offline),
      );
      await expectDesignGolden(
        tester,
        find.byType(WassalApp),
        'AptGoalOffline',
        digits,
      );
    });
    testWidgets('AptGoalSmall, ${digits.name}', (tester) async {
      await pumpAptGoal(
        tester,
        ready: true,
        digits: digits,
        size: const Size(360, 640),
        textScale: 1.3,
      );
      await expectDesignGolden(
        tester,
        find.byType(WassalApp),
        'AptGoalSmall',
        digits,
      );
    });
  }
}
