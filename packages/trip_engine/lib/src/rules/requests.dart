// Payment disputes and change requests (rules.md §4.7, §4.8): the choices
// authored events open.
import '../capabilities.dart';
import '../events.dart';
import '../model/choices.dart';
import '../model/counters.dart';
import '../model/token.dart';
import '../money.dart';
import 'claims.dart';
import 'fares.dart';
import 'reputation.dart';
import 'speech.dart';
import 'transition.dart';

/// `ResolveDispute` naming [paidId] as the one who paid (§4.7). The answer
/// is right when they sent their fare and the other didn't.
void resolveDispute(
  Transition tx,
  int disputeId,
  Dispute dispute,
  String paidId,
) {
  final paid = tx.course.indexOf(paidId);
  final other = tx.course.indexOf(paidId == dispute.a ? dispute.b : dispute.a);
  final right = tx.passenger(paid).fareSent && !tx.passenger(other).fareSent;
  tx.closeDispute(disputeId);
  if (right) {
    catchLiar(tx, other);
    payNow(tx, other);
  } else {
    falseAccusation(tx, other);
  }
  tx.emit(DisputeResolved(tx.tMs, disputeId: disputeId, right: right));
}

/// `ResolveChangeRequest` agreeing (§4.8): [pieces] for the note leave the
/// tray in a `break_out` token to [q].
void agreeChangeRequest(Transition tx, int q, Pieces pieces) {
  final id = tx.passenger(q).passengerId;
  tx
    ..tray = tx.tray.minus(pieces)
    ..newToken(
      kind: TokenKind.breakOut,
      pieces: pieces,
      owner: id,
      target: Holder.passenger(id),
      holder: Holder.driver,
    );
  _resolved(tx, q, agreed: true);
}

/// [q]'s change request is declined, by the player or by [q] getting off
/// unanswered (§4.8, §9.3.1).
void declineChangeRequest(Transition tx, int q) {
  loseReputation(
    tx,
    RepCause.changeRequestDeclined,
    tx.params.repChangeRequestDeclined,
  );
  say(tx, q, SpeechSlot.changeRequestDeclined);
  _resolved(tx, q, agreed: false);
}

void _resolved(Transition tx, int q, {required bool agreed}) {
  final id = tx.passenger(q).passengerId;
  tx
    ..closeChangeRequest(id)
    ..emit(ChangeRequestResolved(tx.tMs, passengerId: id, agreed: agreed));
}
