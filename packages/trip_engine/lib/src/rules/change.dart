// Judging change that reaches a passenger (rules.md §6.5).
import 'package:content_models/content_models.dart';

import '../capabilities.dart';
import '../events.dart';
import '../model/counters.dart';
import '../model/passenger.dart';
import '../model/token.dart';
import '../money.dart';
import 'reputation.dart';
import 'speech.dart';
import 'transition.dart';

/// A `change` or `redirect` [token] of total A reached its target.
void judgeChange(Transition tx, MoneyToken token) {
  final p = tx.course.indexOf(token.target.passengerId);
  if (token.kind == TokenKind.change && _redirect(tx, p, token)) return;
  final state = tx.passenger(p);
  final amount = token.pieces.total;
  final honest = tx.course.archetype(p) == Archetype.honest;

  void delivered(ChangeResult result) => tx.emit(
    ChangeDelivered(
      tx.tMs,
      tokenId: token.tokenId,
      passengerId: state.passengerId,
      result: result,
      amountPiasters: amount,
    ),
  );

  if (!state.fareSent || state.balance <= 0) {
    delivered(ChangeResult.notOwed);
    _mistake(tx, state.passengerId, MistakeKind.notOwed, amount);
    if (honest) {
      _giveBack(tx, p, token.pieces);
    } else {
      _overpaid(tx, amount);
    }
    return;
  }
  if (amount == state.balance) {
    tx.setPassenger(p, state.copyWith(balance: 0));
    delivered(ChangeResult.exact);
    gainReputation(tx, RepCause.exactChange, tx.params.repExactChange);
    say(tx, p, SpeechSlot.thanks);
  } else if (amount < state.balance) {
    final balance = state.balance - amount;
    tx.setPassenger(p, state.copyWith(balance: balance));
    delivered(ChangeResult.short);
    loseReputation(tx, RepCause.shortChange, tx.params.repShortChange);
    say(tx, p, SpeechSlot.shortChange, amount: balance);
  } else {
    final excess = amount - state.balance;
    tx.setPassenger(p, state.copyWith(balance: 0));
    delivered(ChangeResult.over);
    _mistake(tx, state.passengerId, MistakeKind.over, excess);
    if (honest) {
      _giveBack(tx, p, fewestPieces(excess));
    } else {
      _overpaid(tx, excess);
    }
  }
}

// §6.5.1: change that reaches a group member goes on to their payer in a
// `redirect` token, if the payer is still aboard to receive it. Otherwise it
// is judged at the member, who is owed nothing.
bool _redirect(Transition tx, int member, MoneyToken token) {
  final payer = tx.course.payerOf[member];
  if (payer == null || tx.passenger(payer).presence != Presence.aboard) {
    return false;
  }
  final payerId = tx.passenger(payer).passengerId;
  tx.newToken(
    kind: TokenKind.redirect,
    pieces: token.pieces,
    owner: payerId,
    target: Holder.passenger(payerId),
    holder: token.target,
  );
  return true;
}

void _mistake(Transition tx, String passengerId, MistakeKind kind, int amount) {
  tx
    ..addMistake(
      Mistake(passengerId: passengerId, kind: kind, amountPiasters: amount),
    )
    ..emit(
      MistakeMade(
        tx.tMs,
        passengerId: passengerId,
        kind: kind,
        amountPiasters: amount,
      ),
    );
}

void _overpaid(Transition tx, int amount) => tx.counters = tx.counters.copyWith(
  overpaidPiasters: tx.counters.overpaidPiasters + amount,
);

// An honest passenger sends [pieces] back to the driver.
void _giveBack(Transition tx, int p, Pieces pieces) {
  final id = tx.passenger(p).passengerId;
  tx.newToken(
    kind: TokenKind.returned,
    pieces: pieces,
    owner: id,
    target: Holder.driver,
    holder: Holder.passenger(id),
  );
  say(tx, p, SpeechSlot.returnsExcess, amount: pieces.total);
}
