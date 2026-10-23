// The engine's state and the screen's memory, turned into what the screen
// draws (contracts/trip-view.md "The projection"). The engine reports who
// has paid; this is the one place that decides what of it may show
// (FR-033, research R10).
import 'package:content_models/content_models.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/features/trip/domain/fail_summary.dart';
import 'package:wassal/features/trip/domain/presentation_memory.dart';
import 'package:wassal/features/trip/domain/station_strip.dart';
import 'package:wassal/features/trip/domain/trip_facts.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';

/// Reputation below this shows in orange.
const reputationLowBelow = 40;

/// Patience shares (‰) under which a face frowns more.
const _frownAt = 333;
const _impatientAt = 666;

/// What the controller adds: its phase, the dashboard's modes and the
/// economy's numbers the boosters and the revive show.
final class TripScreenState {
  const TripScreenState({
    required this.phase,
    this.breakMode = false,
    this.controlsLocked = false,
    this.inventory = const {},
    this.boosterPrices = const {},
    this.disabledBoosters = const {},
    this.revive,
    this.rejection,
  });

  final TripPhase phase;
  final bool breakMode;
  final bool controlsLocked;

  /// The economy's booster stock.
  final Map<BoosterId, int> inventory;

  /// The catalog's prices in BONAT; a booster without one isn't for sale.
  final Map<BoosterId, int> boosterPrices;

  /// Boosters the economy refused to sell for this trip.
  final Set<BoosterId> disabledBoosters;

  /// Shown on the failure card, or null.
  final ReviveOffer? revive;
  final RejectionLine? rejection;
}

/// [hint] is بلية's hint on screen; [dispute] the dispute being asked.
TripView projectTripView(
  TripState state,
  PresentationMemory memory,
  TripFacts facts,
  TripScreenState screen, {
  HintView? hint,
  int? dispute,
}) {
  final running =
      state.status == TripStatus.running &&
      screen.phase == TripPhase.running &&
      !screen.controlsLocked;
  return TripView(
    tMs: state.tMs,
    phase: screen.phase,
    topBar: TopBarView(
      lineName: facts.line?.name.arEg,
      tripNumber: facts.tripNumber,
      reputation: state.reputation,
      reputationLow: state.reputation < reputationLowBelow,
    ),
    strip: stationStrip(state, facts),
    passengers: _passengers(state, memory, facts),
    tokens: [for (final token in state.tokens) _token(state, token)],
    dropped: [
      for (final token in state.tokens)
        if (token.droppedUntilMs case final until?)
          _dropped(state, token, until),
    ],
    windows: WindowsView(
      road: state.trafficActive
          ? Road.traffic
          : memory.openRoad
          ? Road.open
          : Road.normal,
      waveAtMs: memory.waveAtMs,
    ),
    hand: HandView(
      pieces: Map.unmodifiable(state.hand.counts),
      totalPiasters: state.hand.total,
    ),
    tray: [
      for (final denomination in trayDenominations)
        TraySlotView(
          denomination: denomination,
          count: state.tray.count(denomination),
          breakable:
              screen.breakMode &&
              denomination >= facts.params.tripBreakMinPiasters &&
              state.tray.count(denomination) > 0,
        ),
    ],
    breakButton: BreakButtonView(
      left: state.breaksLeft,
      enabled: running && state.breaksLeft > 0,
    ),
    boosters: [
      for (final booster in tripBoosters)
        _booster(state, facts, screen, booster, running: running),
    ],
    undoUntilMs: state.undoAvailableUntilMs,
    choices: _choices(state, dispute),
    bubbles: memory.bubbles.visible,
    log: memory.log.lines,
    hint: hint,
    banner: memory.banner,
    storyCondition: facts.storyNoFights ? state.counters.fights == 0 : null,
    failSummary: state.status == TripStatus.failed
        ? failSummary(state.reputationLost, facts, screen.revive)
        : null,
    rejection: switch (screen.rejection) {
      final line? when line.untilMs > state.tMs => line,
      _ => null,
    },
    breakMode: screen.breakMode,
    controlsLocked: screen.controlsLocked,
  );
}

List<ChoiceView> _choices(TripState state, int? dispute) => [
  for (final passengerId in state.claims.keys)
    ClaimChoice(passengerId: passengerId),
  for (final MapEntry(key: passengerId, value: request)
      in state.changeRequests.entries)
    ChangeRequestChoice(
      passengerId: passengerId,
      notePiasters: request.notePiasters,
    ),
  if (dispute != null)
    if (state.disputes[dispute] case final asked?)
      DisputeChoice(disputeId: dispute, a: asked.a, b: asked.b),
];

List<PassengerView> _passengers(
  TripState state,
  PresentationMemory memory,
  TripFacts facts,
) {
  final peek = state.ledgerPeekActive;
  final warning = memory.warning;
  final nextStation = state.nextStation?.stationId;
  final failed = state.status == TripStatus.failed;
  final views = <PassengerView>[];
  for (final p in state.passengers) {
    final walk = memory.walks[p.passengerId];
    final walking = walk != null && state.tMs - walk.startMs < walkMs;
    final presence = switch (p.presence) {
      Presence.aboard when walking && walk.kind == WalkKind.boarding =>
        PresenceView.boarding,
      Presence.aboard => PresenceView.aboard,
      Presence.gone when walking && walk.kind == WalkKind.leaving =>
        PresenceView.leaving,
      _ => null,
    };
    if (presence == null) continue;
    final leaving = presence == PresenceView.leaving;
    views.add(
      PassengerView(
        passengerId: p.passengerId,
        seatId: p.seatId,
        presence: presence,
        look: facts.looks[p.passengerId]!,
        slot: facts.slotOf(p.passengerId),
        mood: _mood(p, failed: failed),
        talking: memory.bubbles.isTalking(p.passengerId),
        asleep: p.alertness == Alertness.asleep,
        waking: p.alertness == Alertness.waking,
        headphones: p.alertness == Alertness.muted,
        attentive: p.alertness == Alertness.attentive,
        nearStopPulse:
            !leaving &&
            warning != null &&
            warning.stationId == nextStation &&
            warning.owed.contains(p.passengerId) &&
            p.isOwed,
        dropMeHere: !leaving && p.deadlineMs != null,
        ledgerBadge: peek && !leaving ? _badge(state, facts, p) : null,
        outcome: leaving ? p.outcome : null,
      ),
    );
  }
  return views;
}

int _mood(PassengerState p, {required bool failed}) {
  if (failed || p.impatient || p.outcome == AlightOutcome.fight) return 3;
  return switch (p.patiencePermille) {
    final share? when share <= _frownAt => 2,
    final share? when share <= _impatientAt => 1,
    _ => 0,
  };
}

/// Paid when their fare (or their group payer's) is sent and nothing is
/// owed to them.
LedgerBadge _badge(TripState state, TripFacts facts, PassengerState p) {
  final sent = facts
      .groupOf(p.passengerId)
      .any((id) => state.passenger(id)?.fareSent ?? false);
  return sent && !p.isOwed ? LedgerBadge.paid : LedgerBadge.unpaid;
}

String? _seatOf(TripState state, Holder holder) =>
    holder.isDriver ? null : state.passenger(holder.passengerId)?.seatId;

TokenView _token(TripState state, MoneyToken token) {
  final from = _seatOf(state, token.holder);
  final hop = token.hop;
  return TokenView(
    tokenId: token.tokenId,
    kind: token.kind == TokenKind.fare ? TokenTint.fare : TokenTint.change,
    amountPiasters: token.pieces.total,
    from: from,
    to: hop == null ? from : _seatOf(state, hop.to),
    progressPermille: token.progressPermille ?? 0,
    hopMs: hop?.durationMs ?? 0,
    blocked: token.blockedBy != null,
    dropped: token.isDropped,
    atHolder: hop == null,
  );
}

DroppedMoneyView _dropped(TripState state, MoneyToken token, int untilMs) {
  final from = _seatOf(state, token.holder);
  final hop = token.hop;
  return DroppedMoneyView(
    tokenId: token.tokenId,
    amountPiasters: token.pieces.total,
    from: from,
    to: hop == null ? from : _seatOf(state, hop.to),
    progressPermille: token.progressPermille ?? 0,
    untilMs: untilMs,
  );
}

BoosterSlotView _booster(
  TripState state,
  TripFacts facts,
  TripScreenState screen,
  BoosterId booster, {
  required bool running,
}) {
  final count = screen.inventory[booster] ?? 0;
  final price = count == 0 ? screen.boosterPrices[booster] : null;
  final jamsUsed = state.boostersUsed
      .where((b) => b == BoosterId.trafficJam)
      .length;
  final atLimit =
      booster == BoosterId.trafficJam &&
      jamsUsed >= facts.params.boosterTrafficJamMaxPerTrip;
  return BoosterSlotView(
    booster: booster,
    count: count,
    priceBonat: price,
    enabled:
        running &&
        !atLimit &&
        !screen.disabledBoosters.contains(booster) &&
        (count > 0 || price != null),
    adOffered: false,
  );
}
