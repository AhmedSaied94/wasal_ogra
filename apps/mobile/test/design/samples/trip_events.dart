import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/features/trip/domain/looks.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';

import '../../helpers/trip.dart';
import 'c_trip.dart';

// `TripEvents`' sample state (HANDOFF §11 `TripEvents`): `C-Trip`'s cabin a
// moment later, with three events at once: the fare of المستشفى raised from
// 7 to 8, the ledger open with 4 s left, and the effendi on A_m insisting
// he paid. The engine never sees it.

/// The drawn moment.
const tripEventsMs = 60000;

/// The claimer, on A_m.
const tripEventsClaimer = 'p_A_m';

/// The ledger's badges by seat (block 5), the claimer's and the front
/// seat's included: the app badges everyone aboard.
const tripEventsLedger = <String, LedgerBadge>{
  'C_l': LedgerBadge.paid,
  'C_m': LedgerBadge.unpaid,
  'C_r': LedgerBadge.paid,
  'B_l': LedgerBadge.onFriend,
  'B_m': LedgerBadge.paid,
  'B_r': LedgerBadge.unpaid,
  'A_l': LedgerBadge.paid,
  'A_m': LedgerBadge.unpaid,
  'A_r': LedgerBadge.paid,
  'front_r': LedgerBadge.paid,
};

TraySlotView _slot(int denomination, int count) =>
    TraySlotView(denomination: denomination, count: count, breakable: false);

BoosterSlotView _booster(
  BoosterId booster,
  int count, {
  int? price,
  int? activeUntilMs,
}) => BoosterSlotView(
  booster: booster,
  count: count,
  priceBonat: price,
  enabled: true,
  adOffered: false,
  activeUntilMs: activeUntilMs,
);

TripView tripEventsView() => cTripView(
  tMs: tripEventsMs,
  reputation: 64,
  strip: cTripStrip(
    next: 1,
    countdownMs: 22000,
    raisedTo: 800,
    vehiclePermille: 460,
  ),
  passengers: cTripPassengers(
    talking: const {'A_m'},
    moods: const {'A_m': 2},
    hot: 'A_m',
    ledger: tripEventsLedger,
  ),
  tokens: const [],
  hand: const HandView(pieces: {}, totalPiasters: 0),
  tray: [
    _slot(50, 3),
    _slot(100, 5),
    _slot(500, 2),
    _slot(1000, 3),
    _slot(2000, 1),
    _slot(5000, 2),
    _slot(10000, 0),
    _slot(20000, 0),
  ],
  breakButton: const BreakButtonView(left: 1, enabled: true),
  boosters: [
    _booster(BoosterId.changeBag, 1),
    _booster(BoosterId.ledgerPeek, 0, activeUntilMs: tripEventsMs + 4000),
    _booster(BoosterId.wakeAll, 0, price: 8),
    _booster(BoosterId.trafficJam, 0, price: 5),
  ],
  bubbles: const [
    BubbleView(
      passengerId: tripEventsClaimer,
      text: 'أنا دافع!',
      style: BubbleStyle.plain,
      shownAtMs: tripEventsMs - 1500,
    ),
  ],
  choices: const [ClaimChoice(passengerId: tripEventsClaimer)],
  banner: const BannerView(
    oldPiasters: 700,
    newPiasters: 800,
    shownAtMs: tripEventsMs - 1000,
  ),
  log: [
    const LogLine(kind: LogKind.fareUp, amountPiasters: 800),
    LogLine(
      kind: LogKind.speech,
      speaker: SpeakerLabel(labelKey: looks['effendi_200']!.labelKey),
      text: 'أنا دافع!',
    ),
  ],
);

/// The trip screen on the reference frame, showing `TripEvents`' state.
Future<void> pumpTripEvents(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
}) async {
  await pumpTrip(tester, tripId: cTripId, digits: digits);
  controllerOf(tester).debugShowModel(cTripModel(tripEventsView()));
  await tester.pumpAndSettle();
}
