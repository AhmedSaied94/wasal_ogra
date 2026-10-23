import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/application/trip_settings.dart';

import '../../helpers/memory_settings_store.dart';
import '../../helpers/trip.dart';
import 'c_trip.dart';

// `Pause`'s sample state (HANDOFF §11 `Pause`): `C-Trip`'s cabin under the
// pause card, sound on and vibration off, a liter in the tank for «عيد
// المشوار». The engine never sees it.

TripModel pauseModel() => TripModel(
  phase: TripPhase.paused,
  view: cTripView(phase: TripPhase.paused),
  pauseReason: PauseReason.button,
  restartEnabled: true,
);

/// The trip screen on the reference frame, paused as `Pause` draws it.
Future<void> pumpPause(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
}) async {
  await pumpTrip(
    tester,
    tripId: cTripId,
    digits: digits,
    settingsStore: MemorySettingsStore({tripHapticsKey: 'off'}),
  );
  controllerOf(tester).debugShowModel(pauseModel());
  await tester.pumpAndSettle();
}
