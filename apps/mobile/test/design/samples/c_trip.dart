import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/domain/looks.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';

import '../../helpers/trip.dart';

// `C-Trip`'s sample state (HANDOFF §11 `C-Trip`, research R20), as data on
// the old microbus of `line_gamaa.01`: who sits where and gets off where,
// the notes in flight, the hand at 15.5, the drawer, the bubbles and the
// strip at the drawn moment. The engine never sees it.

/// The trip the sample opens, for its old microbus and its line.
const cTripId = 'line_gamaa.01';

/// The strip's three stops: الكوبري next in 18 s, at 24% of the trip.
const _stations = [
  (id: 'kobri', name: 'الكوبري', fare: 450, atMs: 54000),
  (id: 'mostashfa', name: 'المستشفى', fare: 700, atMs: 102000),
  (id: 'gamaa', name: 'الجامعة', fare: 900, atMs: 150000),
];

/// Who sits where, by `C-Trip`'s boxes 36–45.
const cTripSeats = <({int box, String seatId, String look, int slot})>[
  (box: 36, seatId: 'C_l', look: 'hurried', slot: 0),
  (box: 37, seatId: 'C_m', look: 'sleeper', slot: 1),
  (box: 38, seatId: 'C_r', look: 'student', slot: 2),
  (box: 39, seatId: 'B_l', look: 'group_payer', slot: 0),
  (box: 40, seatId: 'B_m', look: 'group_payer', slot: 0),
  (box: 41, seatId: 'B_r', look: 'headphones', slot: 2),
  (box: 42, seatId: 'A_l', look: 'hagga', slot: 1),
  (box: 43, seatId: 'A_m', look: 'effendi_200', slot: 1),
  (box: 44, seatId: 'A_r', look: 'regular', slot: 2),
  (box: 45, seatId: 'front_r', look: 'regular', slot: 1),
];

/// The stop's name by its slot.
String cTripStopName(int slot) => _stations[slot].name;

PassengerView _passenger(
  ({int box, String seatId, String look, int slot}) s, {
  Set<String> talking = const {'C_l', 'C_r'},
  Map<String, int> moods = const {'C_l': 2},
  String? hot = 'C_l',
  Map<String, LedgerBadge> ledger = const {},
}) => PassengerView(
  passengerId: 'p_${s.seatId}',
  seatId: s.seatId,
  presence: PresenceView.aboard,
  look: looks[s.look]!,
  slot: s.slot,
  mood: moods[s.seatId] ?? 0,
  talking: talking.contains(s.seatId),
  asleep: s.seatId == 'C_m',
  waking: false,
  headphones: s.seatId == 'B_r',
  attentive: false,
  // In `C-Trip` the hurried one's stop is next and he is owed: his tag is
  // hot.
  nearStopPulse: s.seatId == hot,
  dropMeHere: false,
  ledgerBadge: ledger[s.seatId],
  outcome: null,
);

/// The sample's passengers, with who talks, their moods, the hot tag and
/// the ledger's badges changed.
List<PassengerView> cTripPassengers({
  Set<String> talking = const {'C_l', 'C_r'},
  Map<String, int> moods = const {'C_l': 2},
  String? hot = 'C_l',
  Map<String, LedgerBadge> ledger = const {},
}) => [
  for (final s in cTripSeats)
    _passenger(s, talking: talking, moods: moods, hot: hot, ledger: ledger),
];

/// One passenger of the sample, as drawn.
PassengerView cTripPassenger(String seatId) =>
    _passenger(cTripSeats.firstWhere((s) => s.seatId == seatId));

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

/// The sample's strip: [next] is the next stop, those before it are passed.
/// The next stop's fare can show raised from [raisedFrom], or raised to
/// [raisedTo] from its own.
StationStripView cTripStrip({
  int next = 0,
  int countdownMs = 18000,
  int? raisedFrom,
  int? raisedTo,
  int vehiclePermille = 80,
}) => StationStripView(
  chips: [
    for (final (i, s) in _stations.indexed)
      StationChip(
        stationId: s.id,
        slot: i,
        name: s.name,
        farePiasters: i == next ? raisedTo ?? s.fare : s.fare,
        basePiasters: i == next ? raisedFrom ?? s.fare : s.fare,
        atMs: s.atMs,
        studentIcon: false,
        reached: i < next,
        next: i == next,
      ),
  ],
  vehiclePermille: vehiclePermille,
  countdownMs: countdownMs,
  warning: true,
);

/// `C-Trip`'s view; a test changes one part at a time.
TripView cTripView({
  int tMs = 36000,
  int reputation = 72,
  StationStripView? strip,
  List<PassengerView>? passengers,
  List<TokenView>? tokens,
  HandView? hand,
  List<TraySlotView>? tray,
  BreakButtonView breakButton = const BreakButtonView(left: 2, enabled: true),
  List<BoosterSlotView>? boosters,
  int? undoUntilMs,
  List<BubbleView>? bubbles,
  List<ChoiceView> choices = const [],
  List<DroppedMoneyView> dropped = const [],
  List<LogLine>? log,
  HintView? hint,
  BannerView? banner,
  bool? storyCondition,
  bool breakMode = false,
  TripPhase phase = TripPhase.running,
  FailSummary? failSummary,
  bool fastForward = false,
}) => TripView(
  tMs: tMs,
  phase: phase,
  topBar: TopBarView(
    lineName: 'خط الجامعة',
    tripNumber: 12,
    reputation: reputation,
    reputationLow: reputation < 40,
  ),
  strip: strip ?? cTripStrip(),
  passengers: passengers ?? cTripPassengers(),
  tokens:
      tokens ??
      const [
        // The group's 50, a fifth of the way from B_m to the driver.
        TokenView(
          tokenId: 1,
          kind: TokenTint.fare,
          amountPiasters: 5000,
          from: 'B_m',
          to: null,
          progressPermille: 200,
          hopMs: 900,
          blocked: false,
          dropped: false,
          atHolder: false,
        ),
        // The student's 10, held up by the one with headphones.
        TokenView(
          tokenId: 2,
          kind: TokenTint.change,
          amountPiasters: 1000,
          from: 'B_r',
          to: 'C_r',
          progressPermille: 600,
          hopMs: 900,
          blocked: true,
          dropped: false,
          atHolder: false,
        ),
      ],
  dropped: dropped,
  windows: WindowsView.normal,
  hand:
      hand ??
      const HandView(pieces: {1000: 1, 500: 1, 50: 1}, totalPiasters: 1550),
  tray:
      tray ??
      [
        _slot(50, 1),
        _slot(100, 3),
        _slot(500, 1),
        _slot(1000, 1),
        _slot(2000, 1),
        _slot(5000, 1),
        _slot(10000, 0),
        _slot(20000, 0),
      ],
  breakButton: breakButton,
  boosters:
      boosters ??
      [
        _booster(BoosterId.changeBag, 1),
        _booster(BoosterId.ledgerPeek, 1),
        _booster(BoosterId.wakeAll, 1),
        // The design's «إعلان» badge waits for M11; none left shows the price.
        _booster(BoosterId.trafficJam, 0, price: 5),
      ],
  undoUntilMs: undoUntilMs,
  choices: choices,
  bubbles:
      bubbles ??
      const [
        BubbleView(
          passengerId: 'p_C_l',
          text: 'الباقي يا أسطى!',
          style: BubbleStyle.warning,
          shownAtMs: 35000,
        ),
        BubbleView(
          passengerId: 'p_C_r',
          text: 'خد ١٠، طالب',
          style: BubbleStyle.plain,
          shownAtMs: 35500,
        ),
      ],
  log:
      log ??
      const [
        LogLine(
          kind: LogKind.speech,
          speaker: SpeakerLabel(labelKey: 'tripLookGroup'),
          text: 'خد ٥٠ عن تلاتة',
        ),
        LogLine(
          kind: LogKind.speech,
          speaker: SpeakerLabel(labelKey: 'tripLookStudent'),
          text: 'خد ١٠، طالب',
        ),
      ],
  hint: hint,
  banner: banner,
  storyCondition: storyCondition,
  failSummary: failSummary,
  rejection: null,
  breakMode: breakMode,
  controlsLocked: false,
  fastForward: fastForward,
);

TripModel cTripModel([TripView? view]) =>
    TripModel(phase: TripPhase.running, view: view ?? cTripView());

/// Shows [view] on the trip screen on screen.
Future<void> showTripView(WidgetTester tester, TripView view) async {
  controllerOf(tester).debugShowModel(cTripModel(view));
  await tester.pumpAndSettle();
}

/// The trip screen on the reference frame, showing `C-Trip`'s state.
Future<void> pumpCTrip(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
}) async {
  await pumpTrip(tester, tripId: cTripId, digits: digits);
  controllerOf(tester).debugShowModel(cTripModel());
  await tester.pumpAndSettle();
}
