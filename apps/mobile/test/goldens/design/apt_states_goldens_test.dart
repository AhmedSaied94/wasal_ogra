import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';

import '../../design/design_check.dart';
import '../../design/samples/apt_states.dart';

// The apartment's boards of 2026-10-31 as the app draws them, beside
// docs/design/png/<Board>.png (specs/015-m10-apartment-story, T131), in both
// digit styles.

typedef _Pump = Future<ProviderContainer> Function(
  WidgetTester tester, {
  DigitStyle digits,
});

final _boards = <String, _Pump>{
  'AptGoalLine': (tester, {digits = DigitStyle.arabicIndic}) =>
      pumpAptGoalLine(tester, digits: digits),
  'AptGoalVehicle': (tester, {digits = DigitStyle.arabicIndic}) =>
      pumpAptGoalVehicle(tester, digits: digits),
  'AptRoomsAffordable': (tester, {digits = DigitStyle.arabicIndic}) =>
      pumpAptRoomsAffordable(tester, digits: digits),
  'AptRoomsBought': (tester, {digits = DigitStyle.arabicIndic}) =>
      pumpAptRoomsBought(tester, digits: digits),
  'AptRoomsDone': (tester, {digits = DigitStyle.arabicIndic}) =>
      pumpAptRoomsDone(tester, digits: digits),
  'PieceAffordable': (tester, {digits = DigitStyle.arabicIndic}) =>
      pumpPieceAffordable(tester, digits: digits),
  'RoomDonePending': (tester, {digits = DigitStyle.arabicIndic}) =>
      pumpRoomDonePending(tester, digits: digits),
};

void main() {
  for (final entry in _boards.entries) {
    for (final digits in DigitStyle.values) {
      testWidgets('${entry.key}, ${digits.name}', (tester) async {
        await entry.value(tester, digits: digits);
        await expectDesignGolden(
          tester,
          find.byType(WassalApp),
          entry.key,
          digits,
        );
      });
    }
  }
}
