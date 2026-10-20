// Money tokens and the passing chain (rules.md §5).
import 'package:content_models/content_models.dart';

import '../events.dart';
import '../model/counters.dart';
import '../model/passenger.dart';
import '../model/token.dart';
import '../money.dart';
import 'change.dart';
import 'course.dart';
import 'fares.dart';
import 'transition.dart';

/// Whether [holder] can pass or take money: the driver, or an able
/// passenger.
bool canAct(Transition tx, Holder holder) =>
    holder.isDriver ||
    tx.passenger(tx.course.indexOf(holder.passengerId)).isAble;

/// Who [token] goes to next from where it is (§5.2), worked out each time a
/// hop is about to start.
Holder nextHolder(Transition tx, MoneyToken token) {
  if (token.kind == TokenKind.redirect) return token.target;
  if (token.kind.towardDriver) return _ahead(tx, token.holder);
  return _behind(tx, token.holder, token.target);
}

// Toward the driver: the nearest occupied seat ahead in the same column, or
// the driver from rows front and A.
Holder _ahead(Transition tx, Holder from) {
  final (row, col) = _place(tx, from.passengerId);
  for (var r = row - 1; r >= Course.lastNearRow; r--) {
    if (_occupant(tx, r, col) case final occupant?) return occupant;
  }
  return Holder.driver;
}

// Toward passenger [target]: the next occupied seat of their column between
// the holder and them, or the target.
Holder _behind(Transition tx, Holder from, Holder target) {
  final (row, col) = _place(tx, target.passengerId);
  final start = from.isDriver
      ? Course.lastNearRow
      : _place(tx, from.passengerId).$1 + 1;
  for (var r = start; r < row; r++) {
    if (_occupant(tx, r, col) case final occupant?) return occupant;
  }
  return target;
}

(int, SeatCol) _place(Transition tx, String passengerId) {
  final seat = tx.passenger(tx.course.indexOf(passengerId)).seatId;
  return (tx.course.seatRow[seat] ?? 0, tx.course.seatCol[seat] ?? SeatCol.r);
}

Holder? _occupant(Transition tx, int row, SeatCol col) {
  final seat = tx.course.seatAt[(row, col)];
  if (seat == null) return null;
  final passenger = tx.occupant(seat);
  if (passenger == null) return null;
  return Holder.passenger(tx.passenger(passenger).passengerId);
}

/// How long a hop from [from] takes (§5.4).
int hopDuration(Transition tx, MoneyToken token, Holder from) {
  if (token.kind == TokenKind.redirect) return tx.params.tripGroupRedirectHopMs;
  var duration = tx.params.tripHopMs;
  if (from.isDriver) return duration;
  final holder = tx.course.indexOf(from.passengerId);
  if (tx.course.archetype(holder) == Archetype.hajja) {
    duration = scale(duration, tx.params.tripHopPctHajja);
  }
  if (_chattyRow(tx, tx.course.seatRow[tx.passenger(holder).seatId])) {
    duration = scale(duration, tx.params.tripHopPctChattyRow);
  }
  return duration;
}

// Whether an able chatty passenger sits in [row].
bool _chattyRow(Transition tx, int? row) {
  for (var q = 0; q < tx.passengers.length; q++) {
    if (tx.course.archetype(q) == Archetype.chatty &&
        tx.passenger(q).isAble &&
        tx.course.seatRow[tx.passenger(q).seatId] == row) {
      return true;
    }
  }
  return false;
}

/// Starts [token]'s next hop if both ends can act, otherwise marks it
/// blocked (§5.3).
void tryStartHop(Transition tx, MoneyToken token) {
  final from = token.holder;
  final to = nextHolder(tx, token);
  final blocker = !canAct(tx, from)
      ? from.passengerId
      : !canAct(tx, to)
      ? to.passengerId
      : null;
  if (blocker != null) {
    if (token.blockedBy == null) {
      tx.emit(TokenBlocked(tx.tMs, tokenId: token.tokenId, by: blocker));
    }
    if (token.blockedBy != blocker) {
      tx.setToken(token.copyWith(blockedBy: blocker));
    }
    return;
  }
  if (token.blockedBy != null) {
    tx.emit(TokenUnblocked(tx.tMs, tokenId: token.tokenId));
  }
  final duration = hopDuration(tx, token, from);
  tx
    ..setToken(
      token.copyWith(
        blockedBy: null,
        hop: Hop(to: to, elapsedMs: 0, durationMs: duration),
      ),
    )
    ..emit(
      TokenHopStarted(
        tx.tMs,
        tokenId: token.tokenId,
        from: from,
        to: to,
        durationMs: duration,
      ),
    );
}

/// Phase 5 of a step (§3): the tokens that exist at its start, in id order,
/// hop on, arrive, and are delivered. Tokens made here move next step.
void moveTokens(Transition tx) {
  for (final id in [for (final token in tx.tokens) token.tokenId]) {
    var token = tx.token(id);
    if (token == null || token.isDropped) continue;
    if (token.hop case final hop?) {
      final elapsed = hop.elapsedMs + stepMs;
      if (elapsed < hop.durationMs) {
        tx.setToken(
          token.copyWith(
            hop: Hop(
              to: hop.to,
              elapsedMs: elapsed,
              durationMs: hop.durationMs,
            ),
          ),
        );
        continue;
      }
      token = token.copyWith(
        holder: hop.to,
        hopsDone: token.hopsDone + 1,
        hop: null,
      );
      tx.setToken(token);
      if (token.holder == token.target) {
        deliver(tx, token);
        continue;
      }
    }
    tryStartHop(tx, token);
  }
}

/// [token] reached its target (§5.5).
void deliver(Transition tx, MoneyToken token) {
  switch (token.kind) {
    case TokenKind.fare:
    case TokenKind.returned:
    case TokenKind.breakIn:
      atDriver(tx, token);
    case TokenKind.change:
    case TokenKind.redirect:
      tx.removeToken(token.tokenId);
      judgeChange(tx, token);
    case TokenKind.breakOut:
      tx.removeToken(token.tokenId);
      tx.newToken(
        kind: TokenKind.breakIn,
        pieces: _oneNote(token),
        owner: token.owner,
        target: Holder.driver,
        holder: token.target,
      );
  }
}

// The passenger's note: what the break-out token's pieces add up to.
Pieces _oneNote(MoneyToken token) => Pieces({token.pieces.total: 1});

/// [token]'s pieces enter the tray at the driver. A fare counts as paid in.
void atDriver(Transition tx, MoneyToken token) {
  tx
    ..removeToken(token.tokenId)
    ..tray = tx.tray.plus(token.pieces)
    ..emit(
      MoneyArrivedAtDriver(
        tx.tMs,
        tokenId: token.tokenId,
        kind: token.kind,
        amountPiasters: token.pieces.total,
      ),
    );
  final owner = tx.course.indexOf(token.owner);
  switch (token.kind) {
    case TokenKind.fare:
      final state = tx.passenger(owner);
      tx.setPassenger(
        owner,
        state.copyWith(paidIn: state.paidIn + token.pieces.total),
      );
    case TokenKind.returned:
      tx.emit(
        ExcessReturned(
          tx.tMs,
          passengerId: token.owner,
          amountPiasters: token.pieces.total,
        ),
      );
    case TokenKind.breakIn:
      tx.emit(ChangeRequestCompleted(tx.tMs, passengerId: token.owner));
    case TokenKind.change || TokenKind.redirect || TokenKind.breakOut:
      break;
  }
}

/// The bump (§8): every mid-hop token drops to the floor, in id order.
void dropMidHop(Transition tx) {
  for (final token in List.of(tx.tokens)) {
    if (token.hop == null) continue;
    tx
      ..setToken(
        token.copyWith(
          hop: null,
          droppedUntilMs: tx.tMs + tx.params.tripBumpCollectMs,
        ),
      )
      ..emit(MoneyDropped(tx.tMs, tokenId: token.tokenId));
  }
}

/// Phase 2.5 (§3): dropped tokens whose time is up are lost, in id order.
void dropDeadlines(Transition tx) {
  for (final token in List.of(tx.tokens)) {
    if (token.droppedUntilMs case final until? when until <= tx.tMs) {
      loseDropped(tx, token);
    }
  }
}

/// `CollectDropped` (§5.7): a fare arrives at the driver; anything else goes
/// into the tray, and a `break_in` completes its request.
void collectDropped(Transition tx, MoneyToken token) {
  tx.emit(DroppedCollected(tx.tMs, tokenId: token.tokenId));
  switch (token.kind) {
    case TokenKind.fare:
      atDriver(tx, token);
    case TokenKind.breakIn:
      toTray(tx, token);
      tx.emit(ChangeRequestCompleted(tx.tMs, passengerId: token.owner));
    case TokenKind.change ||
        TokenKind.returned ||
        TokenKind.redirect ||
        TokenKind.breakOut:
      toTray(tx, token);
  }
}

/// A dropped token is lost (§5.7). A lost fare never reaches the driver and
/// a lost return is overpaid; any other money is simply gone.
void loseDropped(Transition tx, MoneyToken token) {
  tx
    ..removeToken(token.tokenId)
    ..emit(DroppedLost(tx.tMs, tokenId: token.tokenId));
  if (token.kind == TokenKind.returned) {
    tx.counters = tx.counters.copyWith(
      overpaidPiasters: tx.counters.overpaidPiasters + token.pieces.total,
    );
  }
}

/// [token]'s pieces go back into the tray, with no event.
void toTray(Transition tx, MoneyToken token) {
  tx
    ..removeToken(token.tokenId)
    ..tray = tx.tray.plus(token.pieces);
}

/// Passenger [passenger] gets off (§5.8): tokens they hold, or that are
/// hopping to them on the way elsewhere, are handed to the driver; tokens for
/// them go back to the tray. Dropped tokens stay on the floor.
void handOverTokens(Transition tx, int passenger) {
  final holder = Holder.passenger(tx.passenger(passenger).passengerId);
  for (final token in List.of(tx.tokens)) {
    if (token.isDropped) continue;
    if (token.target == holder) {
      toTray(tx, token);
    } else if (token.holder == holder || token.hop?.to == holder) {
      if (token.kind == TokenKind.fare) {
        atDriver(tx, token);
      } else {
        toTray(tx, token);
      }
    }
  }
}
