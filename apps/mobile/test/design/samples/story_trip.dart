import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';

import '../../helpers/trip.dart';
import 'c_trip.dart';

// `StoryTrip`'s sample state (HANDOFF §11 `StoryTrip`): a story trip in
// `C-Trip`'s cabin, at 18% with الكوبري 31 s away, the hurried one asking
// for his change, the hand at 5.5. Content gives a story trip no title or
// character (research R11), so the HUD keeps the line's title under the
// chip, and the front seat holds a passenger. The engine never sees it.

TraySlotView _slot(int denomination, int count) =>
    TraySlotView(denomination: denomination, count: count, breakable: false);

BoosterSlotView _booster(BoosterId booster, int count, {int? price}) =>
    BoosterSlotView(
      booster: booster,
      count: count,
      priceBonat: price,
      enabled: true,
      adOffered: false,
    );

TripView storyTripView({bool kept = true, bool fastForward = false}) =>
    cTripView(
      reputation: 88,
      strip: cTripStrip(countdownMs: 31000, vehiclePermille: 180),
      passengers: cTripPassengers(talking: const {'C_l'}),
      tokens: const [],
      hand: const HandView(pieces: {500: 1, 50: 1}, totalPiasters: 550),
      tray: [
        _slot(50, 1),
        _slot(100, 2),
        _slot(500, 1),
        _slot(1000, 2),
        _slot(2000, 1),
        _slot(5000, 0),
        _slot(10000, 0),
        _slot(20000, 0),
      ],
      boosters: [
        _booster(BoosterId.changeBag, 2),
        _booster(BoosterId.ledgerPeek, 1),
        _booster(BoosterId.wakeAll, 1),
        _booster(BoosterId.trafficJam, 0, price: 5),
      ],
      bubbles: const [
        BubbleView(
          passengerId: 'p_C_l',
          text: 'الباقي يا أسطى!',
          style: BubbleStyle.warning,
          shownAtMs: 35000,
        ),
      ],
      storyCondition: kept,
      fastForward: fastForward,
    );

/// The trip screen on the reference frame, showing `StoryTrip`'s state.
Future<void> pumpStoryTrip(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
}) async {
  await pumpTrip(tester, tripId: cTripId, digits: digits);
  controllerOf(tester).debugShowModel(cTripModel(storyTripView()));
  await tester.pumpAndSettle();
}
