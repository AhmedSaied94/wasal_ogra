// The result of every end: finished, failed or abandoned (rules.md §11).
import '../model/result.dart';
import 'transition.dart';

/// 1 EGP = 100 piasters (glossary §3.2).
const int piastersPerPound = 100;

TripResult buildResult(Transition tx, TripOutcome outcome) {
  var fares = 0;
  for (final passenger in tx.passengers) {
    if (!passenger.fareSent) continue;
    final fare = passenger.farePiasters ?? 0;
    fares += fare < passenger.paidIn ? fare : passenger.paidIn;
  }
  final counters = tx.counters;
  final earnings = fares - counters.overpaidPiasters + counters.tipsPiasters;
  final finished = outcome == TripOutcome.finished;
  final noFights = counters.fights == 0;
  final noMistakes = tx.mistakes.isEmpty;
  final pounds = (earnings > 0 ? earnings : 0) ~/ piastersPerPound;
  final cap = tx.course.definition.maxEarningsJenehat;
  return makeTripResult(
    tripId: tx.course.definition.tripId,
    rev: tx.course.definition.rev,
    outcome: outcome,
    stars: !finished
        ? 0
        : 1 + (noFights ? 1 : 0) + (noFights && noMistakes ? 1 : 0),
    starFlags: StarFlags(
      reached: finished,
      noFights: noFights,
      noMistakes: noMistakes,
    ),
    faresCollectedPiasters: fares,
    overpaidPiasters: counters.overpaidPiasters,
    tipsPiasters: counters.tipsPiasters,
    earningsJenehat: !finished ? 0 : (pounds < cap ? pounds : cap),
    counters: counters,
    mistakes: tx.mistakes,
    reputation: tx.reputation > 0 ? tx.reputation : 0,
    reputationLost: tx.reputationLost,
    durationMs: tx.tMs,
    boostersUsed: tx.boostersUsed,
    revived: tx.revived,
    commandLogHash: tx.logHash(),
  );
}
