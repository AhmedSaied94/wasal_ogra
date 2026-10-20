// Applying one command between steps (rules.md §4). A rejected command's
// transition is dropped, so it changes nothing and isn't logged.
import '../capabilities.dart';
import '../commands.dart';
import '../events.dart';
import '../model/choices.dart';
import '../model/counters.dart';
import '../model/passenger.dart';
import '../model/result.dart';
import '../model/state.dart';
import '../model/token.dart';
import '../money.dart';
import '../params.dart';
import 'aids.dart';
import 'chain.dart';
import 'claims.dart';
import 'course.dart';
import 'fares.dart';
import 'passengers.dart';
import 'reputation.dart';
import 'requests.dart';
import 'scoring.dart';
import 'speech.dart';
import 'transition.dart';

/// Accepted commands per trip (rules.md §4, research R9). `Abandon` is
/// exempt, so the player can always leave: a log holds at most one more.
const int commandCap = 1200;

/// A command's outcome on a state: the next state and its events, or the
/// rejection with the state unchanged.
typedef Applied = ({
  TripState state,
  List<DomainEvent> events,
  Rejection? rejection,
});

/// The statuses [command] is allowed in (data-model.md "Commands").
Set<TripStatus> allowedStatuses(Command command) => switch (command) {
  PickFromTray() ||
  ReturnHand() ||
  SendHand() ||
  UndoLastSend() ||
  Tap() ||
  RequestBreak() ||
  CollectDropped() => const {TripStatus.running},
  ResolveClaim() ||
  ResolveDispute() ||
  ResolveChangeRequest() ||
  UseBooster() => const {TripStatus.running, TripStatus.paused},
  Revive() => const {TripStatus.failed},
  Abandon() => const {TripStatus.running, TripStatus.paused, TripStatus.failed},
};

/// Applies [command] to [state] at its clock. [logHash] fingerprints the log
/// with this command appended, for a result built by it.
Applied applyCommand(
  Course course,
  TripParams params,
  TripState state,
  Command command,
  String Function() logHash,
) {
  Applied rejected(RejectionCode code, String message) =>
      (state: state, events: const [], rejection: Rejection(code, message));

  if (!allowedStatuses(command).contains(state.status)) {
    return rejected(
      RejectionCode.wrongStatus,
      '${command.name} is not allowed while ${state.status.wire}',
    );
  }
  if (command is! Abandon && state.commandsAccepted >= commandCap) {
    return rejected(
      RejectionCode.commandLimit,
      '$commandCap commands already accepted',
    );
  }
  final tx = Transition(course, params, state, logHash);
  if (_dispatch(tx, command) case final rejection?) {
    return (state: state, events: const [], rejection: rejection);
  }
  tx.commandsAccepted += 1;
  failureCheck(tx);
  return (state: tx.freeze(), events: tx.events, rejection: null);
}

Rejection? _dispatch(Transition tx, Command command) => switch (command) {
  PickFromTray(:final denomination) => _pickFromTray(tx, denomination),
  ReturnHand() => _returnHand(tx),
  SendHand(:final passengerId) => _sendHand(tx, passengerId),
  Tap(:final passengerId) => _tap(tx, passengerId),
  ResolveClaim(:final passengerId, :final insist) => _resolveClaim(
    tx,
    passengerId,
    insist,
  ),
  ResolveDispute(:final disputeId, :final paidPassengerId) => _resolveDispute(
    tx,
    disputeId,
    paidPassengerId,
  ),
  ResolveChangeRequest(:final passengerId, :final agree) =>
    _resolveChangeRequest(tx, passengerId, agree),
  CollectDropped(:final tokenId) => _collectDropped(tx, tokenId),
  UndoLastSend() => undoLastSend(tx),
  RequestBreak(:final denomination) => requestBreak(tx, denomination),
  UseBooster(:final booster) => useBooster(tx, booster),
  Revive() => _revive(tx),
  Abandon() => _abandon(tx),
};

// §4.1
Rejection? _pickFromTray(Transition tx, int denomination) {
  if (!isDenomination(denomination)) {
    return Rejection(
      RejectionCode.badArgument,
      '$denomination is not a denomination',
    );
  }
  if (tx.tray.count(denomination) < 1) {
    return Rejection(RejectionCode.trayEmpty, 'no $denomination in the tray');
  }
  tx
    ..tray = tx.tray.minusOne(denomination)
    ..hand = tx.hand.plusOne(denomination);
  return null;
}

// §4.2
Rejection? _returnHand(Transition tx) {
  if (tx.hand.isEmpty) {
    return const Rejection(RejectionCode.handEmpty, 'the hand is empty');
  }
  tx
    ..tray = tx.tray.plus(tx.hand)
    ..hand = Pieces.empty;
  return null;
}

// The index of [passengerId] if they are aboard, or null.
int? _aboard(Transition tx, String passengerId) {
  final index = tx.course.passengerIndex[passengerId];
  if (index == null || tx.passenger(index).presence != Presence.aboard) {
    return null;
  }
  return index;
}

Rejection _notAboard(String passengerId) =>
    Rejection(RejectionCode.notAboard, '$passengerId is not aboard');

// §4.3
Rejection? _sendHand(Transition tx, String passengerId) {
  if (tx.hand.isEmpty) {
    return const Rejection(RejectionCode.handEmpty, 'the hand is empty');
  }
  if (_aboard(tx, passengerId) == null) return _notAboard(passengerId);
  final token = tx.newToken(
    kind: TokenKind.change,
    pieces: tx.hand,
    owner: passengerId,
    target: Holder.passenger(passengerId),
    holder: Holder.driver,
  );
  tx
    ..hand = Pieces.empty
    ..lastSend = LastSend(
      tokenId: token.tokenId,
      untilMs: tx.tMs + tx.params.tripUndoWindowMs,
    )
    ..emit(
      ChangeSent(
        tx.tMs,
        passengerId: passengerId,
        tokenId: token.tokenId,
        amountPiasters: token.pieces.total,
      ),
    );
  return null;
}

// §4.5: the first case that applies wins. Cases 1 to 3 concern the tapped
// passenger; for 4 to 7, a group member stands for their payer.
Rejection? _tap(Transition tx, String passengerId) {
  final p = _aboard(tx, passengerId);
  if (p == null) return _notAboard(passengerId);
  switch (tx.passenger(p).alertness) {
    case Alertness.asleep:
      startWaking(tx, p);
      return null;
    case Alertness.waking:
      return Rejection(RejectionCode.noEffect, '$passengerId is waking up');
    case Alertness.muted:
      callMuted(tx, p);
      return null;
    case Alertness.awake || Alertness.attentive:
      break;
  }
  final q = tx.course.payerOf[p] ?? p;
  final payer = tx.passenger(q);
  if (payer.presence != Presence.aboard) return _notAboard(payer.passengerId);
  final claimOpen = tx.claims.containsKey(payer.passengerId);
  if (!payer.fareSent && !claimOpen) {
    if (payer.neverPays) {
      say(tx, q, SpeechSlot.claimsPaid);
    } else if (claimsInsteadOfPaying(tx, q)) {
      openClaim(tx, q, truthful: false);
    } else {
      payNow(tx, q);
    }
    return null;
  }
  if (claimOpen) {
    return Rejection(
      RejectionCode.noEffect,
      '${payer.passengerId} has an open claim',
    );
  }
  if (payer.balance < 0) {
    payRest(tx, q);
  } else if (!payer.claimResolved) {
    openClaim(tx, q, truthful: true);
  } else {
    say(tx, q, SpeechSlot.claimsPaid);
  }
  return null;
}

// §4.6
Rejection? _resolveClaim(Transition tx, String passengerId, bool insist) {
  final claim = tx.claims[passengerId];
  if (claim == null) {
    return Rejection(RejectionCode.noChoice, '$passengerId has no open claim');
  }
  resolveClaim(tx, tx.course.indexOf(passengerId), claim, insist: insist);
  return null;
}

// §4.7
Rejection? _resolveDispute(Transition tx, int disputeId, String paidId) {
  final dispute = tx.disputes[disputeId];
  if (dispute == null) {
    return Rejection(RejectionCode.noChoice, 'no open dispute $disputeId');
  }
  if (paidId != dispute.a && paidId != dispute.b) {
    return Rejection(
      RejectionCode.badArgument,
      '$paidId is not in dispute $disputeId',
    );
  }
  resolveDispute(tx, disputeId, dispute, paidId);
  return null;
}

// §4.8
Rejection? _resolveChangeRequest(
  Transition tx,
  String passengerId,
  bool agree,
) {
  final request = tx.changeRequests[passengerId];
  if (request == null) {
    return Rejection(
      RejectionCode.noChoice,
      '$passengerId has no open change request',
    );
  }
  final q = tx.course.indexOf(passengerId);
  if (!agree) {
    declineChangeRequest(tx, q);
    return null;
  }
  final pieces = changeRequestPieces(request.notePiasters, tx.tray);
  if (pieces == null) {
    return Rejection(
      RejectionCode.cannotMakeChange,
      'the tray cannot make ${request.notePiasters}',
    );
  }
  agreeChangeRequest(tx, q, pieces);
  return null;
}

// §4.10
Rejection? _collectDropped(Transition tx, int tokenId) {
  final token = tx.token(tokenId);
  if (token == null || !token.isDropped) {
    return Rejection(RejectionCode.noEffect, 'token $tokenId is not dropped');
  }
  collectDropped(tx, token);
  return null;
}

// §4.12: once per trip, and never after a fight in a no-fights trip.
Rejection? _revive(Transition tx) {
  if (!tx.revivable) {
    return const Rejection(
      RejectionCode.notRevivable,
      'the trip cannot be revived',
    );
  }
  final before = tx.reputation;
  final after = tx.params.repReviveTo;
  tx
    ..reputation = after
    ..status = TripStatus.running
    ..revived = true
    ..revivable = false
    ..result = null
    ..emit(
      ReputationChanged(
        tx.tMs,
        delta: after - before,
        cause: RepCause.revive,
        value: after,
      ),
    )
    ..emit(TripRevived(tx.tMs, reputation: after));
  return null;
}

// §4.13
Rejection? _abandon(Transition tx) {
  final result = buildResult(tx, TripOutcome.abandoned);
  tx
    ..status = TripStatus.abandoned
    ..result = result
    ..emit(TripAbandoned(tx.tMs, result: result));
  return null;
}
