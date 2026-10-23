// Fares and payments (rules.md §6.1–§6.4).
import 'package:content_models/content_models.dart';

import '../capabilities.dart';
import '../events.dart';
import '../model/passenger.dart';
import '../model/token.dart';
import '../money.dart';
import 'claims.dart';
import 'passengers.dart';
import 'speech.dart';
import 'transition.dart';

const int _percent = 100;

/// `x * pct ~/ 100` (rules.md §1.3).
int scale(int x, int pct) => x * pct ~/ _percent;

/// The current fare of [passenger]'s destination: authored plus increases.
int baseFare(Transition tx, int passenger) =>
    tx.schedule[tx.course.destIndex[passenger]].farePiasters +
    tx.fareIncreasePiasters;

/// [passenger]'s own fare: a student's is discounted and rounded up to the
/// smallest coin.
int ownFare(Transition tx, int passenger) {
  final base = baseFare(tx, passenger);
  if (tx.course.archetype(passenger) != Archetype.student) return base;
  final coin = denominations.first;
  final unit = _percent * coin;
  final discounted = base * (_percent - tx.course.rules.studentDiscountPct);
  return (discounted + unit - 1) ~/ unit * coin;
}

/// The fare [passenger] pays. A group payer pays their own, each listed
/// member's, and their own base fare for each member the trip doesn't list.
int fareOf(Transition tx, int passenger) {
  final own = ownFare(tx, passenger);
  if (!tx.course.isPayer(passenger)) return own;
  final members = tx.course.membersOf[passenger] ?? const <int>[];
  final size = tx.course.spec(passenger).groupSize ?? 1;
  var fare = own;
  for (final member in members) {
    fare += ownFare(tx, member);
  }
  return fare + (size - 1 - members.length) * baseFare(tx, passenger);
}

/// [passenger] pays now (§6.2): their authored pieces, topped up after a
/// fare increase they weren't listed by, go to the driver in a fare token.
void payNow(Transition tx, int passenger) {
  final state = tx.passenger(passenger);
  final id = state.passengerId;
  final fare = fareOf(tx, passenger);
  var payment = Pieces.ofList(tx.course.payment[passenger]);
  final oldFare = tx.oldFarePayers.contains(id);
  if (tx.fareIncreasePiasters > 0 && !oldFare && payment.total < fare) {
    payment = payment.plus(fewestPieces(fare - payment.total));
  }
  final total = payment.total;
  final hadClaim = tx.claims.containsKey(id);
  if (hadClaim) tx.closeClaim(id);
  tx.setPassenger(
    passenger,
    state.copyWith(
      fareSent: true,
      farePiasters: fare,
      balance: total - fare,
      neverPays: false,
      claimResolved: hadClaim ? true : null,
    ),
  );
  _closeDisputesWithoutLiar(tx, id);
  startPatience(tx, passenger);
  _sendFare(tx, id, payment);
  final slot = tx.course.isPayer(passenger)
      ? SpeechSlot.paysGroup
      : oldFare && total < fare
      ? SpeechSlot.paysOldFare
      : SpeechSlot.pays;
  say(tx, passenger, slot, amount: total);
}

/// Once [id] has paid, a dispute naming them whose other passenger paid too
/// has no liar left, and closes with no event (§6.2).
void _closeDisputesWithoutLiar(Transition tx, String id) {
  final settled = [
    for (final MapEntry(:key, value: dispute) in tx.disputes.entries)
      if (dispute.a == id || dispute.b == id)
        if (tx
            .passenger(
              tx.course.indexOf(dispute.a == id ? dispute.b : dispute.a),
            )
            .fareSent)
          key,
  ];
  for (final index in settled) {
    tx.closeDispute(index);
  }
}

/// A passenger who owes the driver pays the rest in the fewest pieces (§6.4).
void payRest(Transition tx, int passenger) {
  final state = tx.passenger(passenger);
  final rest = -state.balance;
  tx.setPassenger(passenger, state.copyWith(balance: 0));
  _sendFare(tx, state.passengerId, fewestPieces(rest));
  say(tx, passenger, SpeechSlot.paysRest, amount: rest);
}

void _sendFare(Transition tx, String passengerId, Pieces pieces) {
  final token = tx.newToken(
    kind: TokenKind.fare,
    pieces: pieces,
    owner: passengerId,
    target: Holder.driver,
    holder: Holder.passenger(passengerId),
  );
  tx.emit(
    FareSent(
      tx.tMs,
      passengerId: passengerId,
      tokenId: token.tokenId,
      amountPiasters: pieces.total,
    ),
  );
}

/// Scheduled payments (§3 step 4): each passenger whose time has come and
/// who is able pays, unless they have paid, have an open claim, never pay,
/// or are a group member.
void scheduledPayments(Transition tx) {
  for (var q = 0; q < tx.passengers.length; q++) {
    final at = tx.course.spec(q).paysAtSeconds;
    if (at == null || at * msPerSecond > tx.tMs) continue;
    final state = tx.passenger(q);
    if (!state.isAble ||
        state.fareSent ||
        state.neverPays ||
        tx.claims.containsKey(state.passengerId) ||
        tx.course.isMember(q)) {
      continue;
    }
    if (claimsInsteadOfPaying(tx, q)) {
      openClaim(tx, q, truthful: false);
    } else {
      payNow(tx, q);
    }
  }
}

/// Whether [passenger] is aboard.
bool isAboard(Transition tx, int passenger) =>
    tx.passenger(passenger).presence == Presence.aboard;
