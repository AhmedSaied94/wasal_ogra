import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';

import '../../helpers/trip.dart';
import 'c_trip.dart';

// `Fail`'s sample state (HANDOFF §11 `Fail`): `C-Trip`'s cabin lost, every
// face frowning; two fights and a missed stop cost the reputation; three
// angry faces, the effendi first; the rewarded-ad revive ready (M11), and
// the BONAT revive at 20, affordable. The engine never sees it.

/// The faces the card draws, in the summary's order.
const failFaces = ['p_A_m', 'p_C_l', 'p_B_r'];

/// The revive's price on the artboard.
const failRevivePrice = 20;

FailSummary failSummary({
  ReviveOffer? revive = _revive,
  AdSlot reviveAd = AdSlot.ready,
}) => FailSummary(
  causes: const [
    FailCause(cause: RepCause.fight, count: 2),
    FailCause(cause: RepCause.missedStop, count: 1),
  ],
  revive: revive,
  reviveAd: revive == null ? AdSlot.hidden : reviveAd,
  angryFaces: failFaces,
);

const _revive = ReviveOffer(priceBonat: failRevivePrice, affordable: true);

TripModel failModel({
  ReviveOffer? revive = _revive,
  AdSlot reviveAd = AdSlot.ready,
}) => TripModel(
  phase: TripPhase.failed,
  view: cTripView(
    reputation: 0,
    phase: TripPhase.failed,
    passengers: cTripPassengers(
      talking: const {},
      moods: {for (final s in cTripSeats) s.seatId: 3},
      hot: null,
    ),
    bubbles: const [],
    tokens: const [],
    failSummary: failSummary(revive: revive, reviveAd: reviveAd),
  ),
  restartEnabled: true,
);

/// The trip screen on the reference frame, failed as `Fail` draws it.
Future<void> pumpFail(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  AdSlot reviveAd = AdSlot.ready,
}) async {
  await pumpTrip(tester, tripId: cTripId, digits: digits);
  controllerOf(tester).debugShowModel(failModel(reviveAd: reviveAd));
  await tester.pumpAndSettle();
}
