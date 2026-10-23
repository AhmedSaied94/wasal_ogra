import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/features/trip/domain/looks.dart';
import 'package:wassal/features/trip/domain/trip_facts.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';

import '../../helpers/trip.dart';
import 'c_trip.dart';

// The hint of `Tutorial` (HANDOFF §11 `Tutorial` blocks 5–7, research R12)
// on the tuktuk of `line_hay.01`: الحاجة paid 10 for 7 and بلية says she is
// owed, pointing at her. The scrim, the hole and the locked boosters are
// M07's; the hint takes no touch. The engine never sees it.

/// The trip the sample opens, for its tuktuk.
const tutorialTripId = 'line_hay.01';

/// The one بلية's hint is about.
const tutorialTarget = 'p_A_m';

PassengerView _rider(String seatId, String look, int slot) => PassengerView(
  passengerId: 'p_$seatId',
  seatId: seatId,
  presence: PresenceView.aboard,
  look: looks[look]!,
  slot: slot,
  mood: 0,
  talking: false,
  asleep: false,
  waking: false,
  headphones: false,
  attentive: false,
  nearStopPulse: false,
  dropMeHere: false,
  ledgerBadge: null,
  outcome: null,
);

TraySlotView _slot(int denomination, int count) =>
    TraySlotView(denomination: denomination, count: count, breakable: false);

BoosterSlotView _booster(BoosterId booster) => BoosterSlotView(
  booster: booster,
  count: 1,
  priceBonat: null,
  enabled: true,
  adOffered: false,
);

TripView tutorialView({String hintKey = 'tripHintOwed'}) => TripView(
  tMs: 12000,
  phase: TripPhase.running,
  topBar: const TopBarView(
    lineName: 'خط الحي',
    tripNumber: 1,
    reputation: 100,
    reputationLow: false,
  ),
  strip: const StationStripView(
    chips: [
      StationChip(
        stationId: 'madrasa',
        slot: 0,
        name: 'المدرسة',
        farePiasters: 700,
        basePiasters: 700,
        atMs: 30000,
        studentIcon: false,
        reached: false,
        next: true,
      ),
      StationChip(
        stationId: 'forn',
        slot: 1,
        name: 'الفرن',
        farePiasters: 700,
        basePiasters: 700,
        atMs: 60000,
        studentIcon: false,
        reached: false,
        next: false,
      ),
    ],
    vehiclePermille: 300,
    countdownMs: 24000,
    warning: false,
  ),
  passengers: [_rider('A_m', 'hagga', 1), _rider('A_l', 'regular', 0)],
  tokens: const [],
  dropped: const [],
  windows: WindowsView.normal,
  hand: const HandView(pieces: {}, totalPiasters: 0),
  tray: [
    _slot(50, 2),
    _slot(100, 4),
    _slot(500, 2),
    _slot(1000, 1),
    _slot(2000, 0),
    _slot(5000, 0),
    _slot(10000, 0),
    _slot(20000, 0),
  ],
  breakButton: const BreakButtonView(left: 2, enabled: true),
  boosters: [for (final b in tripBoosters) _booster(b)],
  undoUntilMs: null,
  choices: const [],
  bubbles: const [],
  log: [
    LogLine(
      kind: LogKind.speech,
      speaker: SpeakerLabel(labelKey: looks['hagga']!.labelKey),
      text: 'اتفضل يا ابني، سبعة',
    ),
    const LogLine(kind: LogKind.fareArrived, amountPiasters: 1000),
  ],
  hint: HintView(key: hintKey, targetPassengerId: tutorialTarget),
  banner: null,
  storyCondition: null,
  failSummary: null,
  rejection: null,
  breakMode: false,
  controlsLocked: false,
);

/// The trip screen on the reference frame, showing the hint.
Future<void> pumpTutorialHint(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
}) async {
  await pumpTrip(tester, tripId: tutorialTripId, digits: digits);
  controllerOf(tester).debugShowModel(cTripModel(tutorialView()));
  await tester.pumpAndSettle();
}
