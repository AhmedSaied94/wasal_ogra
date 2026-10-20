// The player's aids (rules.md §4.4, §4.9, §4.11, §3 steps 2.4 and 2.6):
// undo, «حد معاه فكة؟», and the four in-trip boosters.
import 'package:content_models/content_models.dart';

import '../commands.dart';
import '../events.dart';
import '../model/choices.dart';
import '../model/passenger.dart';
import '../money.dart';
import 'passengers.dart';
import 'stations.dart';
import 'transition.dart';

/// `UndoLastSend` (§4.4): the last send's pieces come back to the hand while
/// its window lasts and before its first hop ends.
Rejection? undoLastSend(Transition tx) {
  final send = tx.lastSend;
  final token = send == null ? null : tx.token(send.tokenId);
  if (send == null ||
      token == null ||
      tx.tMs > send.untilMs ||
      token.isDropped ||
      token.hopsDone > 0) {
    return const Rejection(
      RejectionCode.undoUnavailable,
      'there is no send to undo',
    );
  }
  tx
    ..removeToken(token.tokenId)
    ..hand = tx.hand.plus(token.pieces)
    ..lastSend = null
    ..emit(SendUndone(tx.tMs, tokenId: token.tokenId));
  return null;
}

/// `RequestBreak` (§4.9): a note leaves the tray, and its row of §14.1 comes
/// back `trip_break_delay_ms` later.
Rejection? requestBreak(Transition tx, int note) {
  if (!isDenomination(note)) {
    return Rejection(RejectionCode.badArgument, '$note is not a denomination');
  }
  if (note < tx.params.tripBreakMinPiasters || breakDown(note) == null) {
    return Rejection(RejectionCode.breakLimit, '$note cannot be broken');
  }
  if (tx.tray.count(note) < 1) {
    return Rejection(RejectionCode.trayEmpty, 'no $note in the tray');
  }
  if (tx.breaksUsed >= tx.course.rules.maxBreakRequests) {
    return const Rejection(RejectionCode.breakLimit, 'no breaks are left');
  }
  final completesAt = tx.tMs + tx.params.tripBreakDelayMs;
  tx
    ..tray = tx.tray.minusOne(note)
    ..addPendingBreak(
      PendingBreak(denomination: note, completesAtMs: completesAt),
    )
    ..breaksUsed += 1
    ..emit(
      BreakRequested(tx.tMs, denomination: note, completesAtMs: completesAt),
    );
  return null;
}

/// Phase 2.6 (§3): pending breaks whose time has come complete, in list
/// order.
void completeBreaks(Transition tx) {
  var i = 0;
  while (i < tx.pendingBreaks.length) {
    final pending = tx.pendingBreaks[i];
    if (pending.completesAtMs > tx.tMs) {
      i++;
      continue;
    }
    final pieces =
        breakDown(pending.denomination) ??
        (throw StateError('${pending.denomination} was checked on request'));
    tx
      ..removePendingBreak(i)
      ..tray = tx.tray.plus(pieces)
      ..emit(
        BreakCompleted(
          tx.tMs,
          denomination: pending.denomination,
          pieces: pieces,
        ),
      );
  }
}

/// Phase 2.4 (§3): the ledger peek ends.
void ledgerPeekTimer(Transition tx) {
  final until = tx.ledgerPeekUntilMs;
  if (until == null || until > tx.tMs) return;
  tx
    ..ledgerPeekUntilMs = null
    ..emit(LedgerPeekEnded(tx.tMs));
}

const _inTrip = {
  BoosterId.changeBag,
  BoosterId.wakeAll,
  BoosterId.ledgerPeek,
  BoosterId.trafficJam,
};

/// `UseBooster` (§4.11).
Rejection? useBooster(Transition tx, BoosterId booster) {
  if (!_inTrip.contains(booster)) {
    return Rejection(
      RejectionCode.badArgument,
      '${booster.name} is not an in-trip booster',
    );
  }
  if (booster == BoosterId.trafficJam &&
      tx.boostersUsed.where((used) => used == booster).length >=
          tx.params.boosterTrafficJamMaxPerTrip) {
    return const Rejection(
      RejectionCode.boosterLimit,
      'no traffic jams are left',
    );
  }
  tx
    ..addBoosterUsed(booster)
    ..emit(BoosterUsed(tx.tMs, boosterId: booster));
  switch (booster) {
    case BoosterId.changeBag:
      tx.tray = tx.tray.plus(changeBag);
    case BoosterId.wakeAll:
      for (var q = 0; q < tx.passengers.length; q++) {
        final state = tx.passenger(q);
        if (state.presence == Presence.aboard &&
            (state.alertness == Alertness.asleep ||
                state.alertness == Alertness.waking)) {
          wake(tx, q);
        }
      }
    case BoosterId.ledgerPeek:
      final until = tx.tMs + tx.params.boosterLedgerPeekMs;
      tx
        ..ledgerPeekUntilMs = until
        ..emit(LedgerPeekStarted(tx.tMs, untilMs: until));
    case BoosterId.trafficJam:
      shiftSchedule(tx, tx.params.boosterTrafficJamMs);
    case BoosterId.revive || BoosterId.refuelFull || BoosterId.fuelUnlimited1h:
      break;
  }
  return null;
}
