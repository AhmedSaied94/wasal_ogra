// Claims (rules.md §4.6, §7.4, §10.1): a false claimer says they paid
// instead of paying, and a tap on a passenger who has paid makes them say so
// truthfully. The driver insists or believes them.
import 'package:content_models/content_models.dart';

import '../capabilities.dart';
import '../events.dart';
import '../model/choices.dart';
import '../model/counters.dart';
import '../model/passenger.dart';
import 'fares.dart';
import 'reputation.dart';
import 'speech.dart';
import 'transition.dart';

/// Whether [q] is a false claimer who hasn't had a claim resolved yet.
bool claimsInsteadOfPaying(Transition tx, int q) =>
    tx.course.archetype(q) == Archetype.falseClaimer &&
    !tx.passenger(q).claimResolved;

/// [q] says they have paid, and the claim stays open until resolved.
void openClaim(Transition tx, int q, {required bool truthful}) {
  final id = tx.passenger(q).passengerId;
  tx
    ..openClaim(id, Claim(truthful: truthful))
    ..emit(ClaimRaised(tx.tMs, passengerId: id));
  say(tx, q, SpeechSlot.claimsPaid);
}

/// `ResolveClaim` on [q]'s open [claim] (§4.6).
void resolveClaim(Transition tx, int q, Claim claim, {required bool insist}) {
  if (!insist) {
    acceptClaim(tx, q);
    return;
  }
  _close(tx, q);
  if (claim.truthful) {
    falseAccusation(tx, q);
    return;
  }
  catchLiar(tx, q);
  payNow(tx, q);
}

/// [q] lied about paying and is caught (§4.6, §4.7). They pay next.
void catchLiar(Transition tx, int q) {
  gainReputation(tx, RepCause.liarCaught, tx.params.repLiarCaught);
  tx
    ..counters = tx.counters.copyWith(caughtLiars: tx.counters.caughtLiars + 1)
    ..emit(LiarCaught(tx.tMs, passengerId: tx.passenger(q).passengerId));
  say(tx, q, SpeechSlot.caught);
}

/// The driver believes [q]'s open claim, at a `ResolveClaim` or when [q] gets
/// off (§9.3.1): a false claimer then never pays.
void acceptClaim(Transition tx, int q) {
  final falseClaim = tx.claims[tx.passenger(q).passengerId]?.truthful == false;
  _close(tx, q);
  final state = tx.passenger(q);
  if (falseClaim) tx.setPassenger(q, state.copyWith(neverPays: true));
  tx.emit(ClaimAccepted(tx.tMs, passengerId: state.passengerId));
}

void _close(Transition tx, int q) {
  final state = tx.passenger(q);
  tx
    ..closeClaim(state.passengerId)
    ..setPassenger(q, state.copyWith(claimResolved: true));
}

/// The driver wrongly accuses [q] (§10.1): reputation, and a fight in the
/// sense of FR-057.
void falseAccusation(Transition tx, int q) {
  loseReputation(tx, RepCause.falseAccusation, tx.params.repFalseAccusation);
  tx
    ..counters = tx.counters.copyWith(fights: tx.counters.fights + 1)
    ..emit(FalseAccusation(tx.tMs, passengerId: tx.passenger(q).passengerId));
  say(tx, q, SpeechSlot.accused);
}
