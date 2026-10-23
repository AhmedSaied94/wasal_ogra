// Authored events (rules.md §8): each fires once, at its at_seconds on the
// trip clock, which shifts never move.
import 'package:content_models/content_models.dart';

import '../capabilities.dart';
import '../events.dart';
import '../model/choices.dart';
import '../model/passenger.dart';
import 'chain.dart';
import 'speech.dart';
import 'stations.dart';
import 'transition.dart';

/// Phase 3 (§3): events whose time has come, in definition order. One that
/// can't apply is skipped, and never fires later.
void authoredEvents(Transition tx) {
  final events = tx.course.definition.events;
  for (var i = 0; i < events.length; i++) {
    final event = events[i];
    if (tx.eventsFired[i] || event.atSeconds * msPerSecond > tx.tMs) continue;
    tx.markFired(i);
    final named = [
      for (final id in event.passengerIds ?? const <String>[])
        tx.course.indexOf(id),
    ];
    if (!_canFire(tx, event, named)) {
      tx.emit(EventSkipped(tx.tMs, index: i, eventId: event.eventId));
      continue;
    }
    tx.emit(EventStarted(tx.tMs, index: i, eventId: event.eventId));
    _fire(tx, i, event, named);
  }
}

// Everyone named must be aboard, or waiting for a pickup; a passenger has
// at most one open change request; and a dispute needs a liar: exactly one
// of the two has paid.
bool _canFire(Transition tx, TripEvent event, List<int> named) {
  final presence = event.eventId == EventId.roadsidePickup
      ? Presence.waiting
      : Presence.aboard;
  if (named.any((q) => tx.passenger(q).presence != presence)) return false;
  return switch (event.eventId) {
    EventId.changeRequest => !named.any(
      (q) => tx.changeRequests.containsKey(tx.passenger(q).passengerId),
    ),
    EventId.paymentDispute =>
      named.where((q) => tx.passenger(q).fareSent).length == 1,
    _ => true,
  };
}

// The parameters were validated at start (content-contract.md §2), so the
// last case is never reached.
void _fire(Transition tx, int index, TripEvent event, List<int> named) {
  switch (event) {
    case TripEvent(eventId: EventId.bump):
      dropMidHop(tx);
    case TripEvent(eventId: EventId.traffic, :final seconds?):
      shiftSchedule(tx, seconds * msPerSecond);
      tx.trafficActive = true;
    case TripEvent(eventId: EventId.openRoad, :final seconds?):
      shiftSchedule(tx, -seconds * msPerSecond);
    case TripEvent(eventId: EventId.fareIncrease, :final amountPiasters?):
      _fareIncrease(tx, amountPiasters, named);
    case TripEvent(eventId: EventId.dropMeHere, :final seconds):
      _dropMeHere(tx, named.single, seconds);
    case TripEvent(eventId: EventId.paymentDispute):
      _dispute(tx, index, named);
    case TripEvent(eventId: EventId.changeRequest, :final amountPiasters?):
      _changeRequest(tx, named.single, amountPiasters);
    case TripEvent(eventId: EventId.roadsidePickup):
      for (final q in named) {
        tx.setPassenger(q, tx.passenger(q).copyWith(pickupDue: true));
        boardIfFree(tx, q);
      }
    case _:
      break;
  }
}

void _fareIncrease(Transition tx, int amount, List<int> named) {
  tx.fareIncreasePiasters += amount;
  for (final q in named) {
    tx.addOldFarePayer(tx.passenger(q).passengerId);
  }
  tx.emit(
    FareIncreased(
      tx.tMs,
      amountPiasters: amount,
      totalIncreasePiasters: tx.fareIncreasePiasters,
    ),
  );
}

void _dropMeHere(Transition tx, int q, int? seconds) {
  final deadline =
      tx.tMs +
      (seconds == null
          ? tx.params.tripStationWarningMs
          : seconds * msPerSecond);
  final state = tx.passenger(q);
  tx
    ..setPassenger(q, state.copyWith(deadlineMs: deadline))
    ..emit(
      StopChanged(tx.tMs, passengerId: state.passengerId, deadlineMs: deadline),
    );
  say(tx, q, SpeechSlot.dropMeHere);
}

void _dispute(Transition tx, int index, List<int> named) {
  final [a, b] = [for (final q in named) tx.passenger(q).passengerId];
  tx
    ..openDispute(index, Dispute(a: a, b: b))
    ..emit(DisputeRaised(tx.tMs, disputeId: index, passengerIds: [a, b]));
  for (final q in named) {
    say(tx, q, SpeechSlot.dispute);
  }
}

void _changeRequest(Transition tx, int q, int note) {
  final id = tx.passenger(q).passengerId;
  tx
    ..openChangeRequest(id, ChangeRequest(notePiasters: note))
    ..emit(ChangeRequestRaised(tx.tMs, passengerId: id, amountPiasters: note));
  say(tx, q, SpeechSlot.changeRequest, amount: note);
}
