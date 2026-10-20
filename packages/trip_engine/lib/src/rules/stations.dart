// Stations: the warning, getting off, boarding, and the end of the trip
// (rules.md §9, §11).
import 'package:content_models/content_models.dart';

import '../capabilities.dart';
import '../events.dart';
import '../model/counters.dart';
import '../model/passenger.dart';
import '../model/result.dart';
import '../model/state.dart';
import '../model/station.dart';
import '../model/token.dart';
import 'chain.dart';
import 'claims.dart';
import 'requests.dart';
import 'reputation.dart';
import 'scoring.dart';
import 'speech.dart';
import 'transition.dart';

/// Phase 7 (§3, §9.2): the next station's warning, once.
void warnStation(Transition tx) {
  final i = tx.nextStationIndex;
  if (i >= tx.course.stationCount) return;
  final station = tx.schedule[i];
  if (station.warned ||
      tx.tMs < station.atMs - tx.params.tripStationWarningMs) {
    return;
  }
  tx.setStation(i, station.copyWith(warned: true));
  final alighting = [
    for (var q = 0; q < tx.passengers.length; q++)
      if (_alightsAt(tx, q, i, station.atMs)) q,
  ];
  tx.emit(
    StationWarning(
      tx.tMs,
      stationId: station.stationId,
      atMs: station.atMs,
      alighting: [for (final q in alighting) tx.passenger(q).passengerId],
      owed: [
        for (final q in alighting)
          if (tx.passenger(q).isOwed) tx.passenger(q).passengerId,
      ],
    ),
  );
  if (alighting.isNotEmpty) {
    say(tx, alighting.first, SpeechSlot.stopNear, station: station.stationId);
  }
}

// Aboard, bound for station [i], and not getting off earlier at a deadline.
bool _alightsAt(Transition tx, int q, int i, int atMs) {
  final state = tx.passenger(q);
  if (state.presence != Presence.aboard || tx.course.destIndex[q] != i) {
    return false;
  }
  final deadline = state.deadlineMs;
  return deadline == null || deadline >= atMs;
}

/// Phase 8.2 (§3): every station reached is processed, in order. The station
/// counts as processed from the moment its processing starts.
void reachStations(Transition tx) {
  while (tx.nextStationIndex < tx.course.stationCount &&
      tx.tMs >= tx.schedule[tx.nextStationIndex].atMs) {
    final i = tx.nextStationIndex++;
    _process(tx, i);
  }
}

// §9.4
void _process(Transition tx, int i) {
  tx.emit(StationReached(tx.tMs, stationId: tx.schedule[i].stationId));
  for (var q = 0; q < tx.passengers.length; q++) {
    if (tx.passenger(q).presence == Presence.aboard &&
        tx.course.destIndex[q] == i) {
      getOff(tx, q);
    }
  }
  for (var q = 0; q < tx.passengers.length; q++) {
    final state = tx.passenger(q);
    if (state.presence == Presence.waiting && tx.course.boardIndex[q] == i) {
      tx.setPassenger(q, state.copyWith(pickupDue: true));
      boardIfFree(tx, q);
    }
  }
  tx.trafficActive = false;
}

/// Passenger [p] gets off, at their station or their deadline (§9.3).
void getOff(Transition tx, int p) {
  closeChoices(tx, p);
  final state = tx.passenger(p);
  final AlightOutcome outcome;
  final unpaid = !state.fareSent && !tx.course.isMember(p);
  if (state.alertness == Alertness.asleep ||
      state.alertness == Alertness.waking) {
    outcome = AlightOutcome.missedStop;
    loseReputation(tx, RepCause.missedStop, tx.params.repMissedStop);
    tx.counters = tx.counters.copyWith(
      missedStops: tx.counters.missedStops + 1,
      lostFares: tx.counters.lostFares + (unpaid ? 1 : 0),
    );
    if (state.isOwed) _unreturned(tx, p);
    say(
      tx,
      p,
      SpeechSlot.missedStop,
      station: tx.schedule[tx.course.destIndex[p]].stationId,
    );
  } else if (state.isOwed) {
    outcome = AlightOutcome.fight;
    loseReputation(tx, RepCause.fight, tx.params.repFight);
    tx.counters = tx.counters.copyWith(fights: tx.counters.fights + 1);
    _unreturned(tx, p);
    say(tx, p, SpeechSlot.fight, amount: state.balance);
  } else if (unpaid) {
    outcome = AlightOutcome.leftUnpaid;
    tx.counters = tx.counters.copyWith(lostFares: tx.counters.lostFares + 1);
  } else {
    outcome = AlightOutcome.thanked;
    _tip(tx, p);
  }
  handOverTokens(tx, p);
  tx
    ..setPassenger(
      p,
      tx.passenger(p).copyWith(presence: Presence.gone, outcome: outcome),
    )
    ..emit(
      PassengerAlighted(
        tx.tMs,
        passengerId: state.passengerId,
        outcome: outcome,
      ),
    );
  _boardFreed(tx, state.seatId);
}

// [p] leaves owed: the unreturned balance is a mistake.
void _unreturned(Transition tx, int p) {
  final state = tx.passenger(p);
  final mistake = Mistake(
    passengerId: state.passengerId,
    kind: MistakeKind.unreturned,
    amountPiasters: state.balance,
  );
  tx
    ..addMistake(mistake)
    ..emit(
      MistakeMade(
        tx.tMs,
        passengerId: mistake.passengerId,
        kind: mistake.kind,
        amountPiasters: mistake.amountPiasters,
      ),
    );
}

// §9.3: a regular customer who leaves thanked and not impatient tips.
void _tip(Transition tx, int p) {
  if (tx.course.archetype(p) != Archetype.regularCustomer ||
      tx.passenger(p).impatient) {
    return;
  }
  final tip = tx.params.tripTipPiastersRegularCustomer;
  tx.counters = tx.counters.copyWith(
    tipsPiasters: tx.counters.tipsPiasters + tip,
  );
  say(tx, p, SpeechSlot.tip, amount: tip);
}

/// [p]'s open choices close as they get off (§9.3.1): a claim is accepted,
/// a change request declined, and a dispute dropped.
void closeChoices(Transition tx, int p) {
  final id = tx.passenger(p).passengerId;
  if (tx.claims.containsKey(id)) acceptClaim(tx, p);
  if (tx.changeRequests.containsKey(id)) declineChangeRequest(tx, p);
  final disputes = [
    for (final MapEntry(:key, :value) in tx.disputes.entries)
      if (value.a == id || value.b == id) key,
  ];
  for (final index in disputes) {
    tx.closeDispute(index);
  }
}

/// Shifts the schedule by [delta] from the next station on (§9.1). An
/// earlier arrival is clamped so the next station stays at least
/// `trip_station_warning_ms` away.
void shiftSchedule(Transition tx, int delta) {
  final next = tx.nextStationIndex;
  if (next >= tx.course.stationCount) return;
  var applied = delta;
  if (delta < 0) {
    final at = tx.schedule[next].atMs;
    final soonest = tx.tMs + tx.params.tripStationWarningMs;
    final target = at + delta > soonest ? at + delta : soonest;
    applied = target < at ? target - at : 0;
  }
  for (var j = next; j < tx.course.stationCount; j++) {
    final station = tx.schedule[j];
    tx.setStation(j, station.copyWith(atMs: station.atMs + applied));
  }
  tx.emit(ScheduleShifted(tx.tMs, deltaMs: applied));
}

/// Phase 8.1 (§3): passengers whose `drop_me_here` deadline has come get
/// off, in passenger order.
void reachDeadlines(Transition tx) {
  for (var q = 0; q < tx.passengers.length; q++) {
    final state = tx.passenger(q);
    final deadline = state.deadlineMs;
    if (state.presence == Presence.aboard &&
        deadline != null &&
        deadline <= tx.tMs) {
      getOff(tx, q);
    }
  }
}

// Step 5 of §9.3: a waiting passenger whose pickup has come takes the seat.
void _boardFreed(Transition tx, String seatId) {
  for (var q = 0; q < tx.passengers.length; q++) {
    if (tx.passenger(q).seatId == seatId) boardIfFree(tx, q);
  }
}

/// Boards [q] if they are waiting, their pickup has come, their seat is free
/// and their destination is still ahead (§9.5).
void boardIfFree(Transition tx, int q) {
  final state = tx.passenger(q);
  if (state.presence != Presence.waiting ||
      !state.pickupDue ||
      tx.occupant(state.seatId) != null ||
      tx.course.destIndex[q] < tx.nextStationIndex) {
    return;
  }
  tx
    ..setPassenger(
      q,
      state.copyWith(
        presence: Presence.aboard,
        alertness: initialAlertness(tx.course.archetype(q)),
        alertUntilMs: null,
        taps: 0,
        pickupDue: false,
      ),
    )
    ..emit(
      PassengerBoarded(
        tx.tMs,
        passengerId: state.passengerId,
        seatId: state.seatId,
      ),
    );
  say(tx, q, SpeechSlot.boards);
}

/// Phase 10 (§3, §11): once every station is processed, the money still in
/// transit is settled and the trip finishes.
void endCheck(Transition tx) {
  if (tx.status != TripStatus.running ||
      tx.nextStationIndex < tx.course.stationCount) {
    return;
  }
  for (final token in List.of(tx.tokens)) {
    if (token.isDropped) {
      loseDropped(tx, token);
    } else if (token.kind == TokenKind.fare) {
      atDriver(tx, token);
    } else {
      toTray(tx, token);
    }
  }
  final result = buildResult(tx, TripOutcome.finished);
  tx
    ..status = TripStatus.finished
    ..result = result
    ..emit(TripFinished(tx.tMs, result: result));
}
