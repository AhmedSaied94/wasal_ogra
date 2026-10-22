// `trip_start` and `trip_result` (contracts/operations.md, research R12).
// Each rule gets the state with its fuel already regenerated to the time it
// applies at.
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/economy/domain/economy_refusal.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/fuel.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/rules.dart';
import 'package:wassal/core/economy/domain/txn_id.dart';

/// Every start costs a liter, replays included (FR-029), unless an
/// unlimited-fuel window runs.
Decision validateTripStart(
  EconomyState s,
  StartTripRequest request,
  RuleContext ctx,
) {
  final trip = ctx.content.trip(request.tripId);
  if (trip == null) return const Declined(EconomyRefusal.unknownTrip);
  if (s.unfinished != null) {
    return const Declined(EconomyRefusal.tripUnfinished);
  }
  final unlimited = isUnlimited(s.fuel, ctx.nowMs);
  if (!unlimited && s.fuel.liters < 1) {
    return const Declined(EconomyRefusal.noFuel);
  }
  final mode = unlimited ? FuelMode.unlimited : FuelMode.fuel;
  return Validated(
    ctx.op(
      OpType.tripStart,
      {
        'trip_id': request.tripId,
        'content_version': ctx.contentVersion,
        'fuel_mode': mode.wire,
      },
      fuelDelta: unlimited ? 0 : -1,
      maxEarningsJenehat: trip.maxEarningsJenehat,
    ),
  );
}

/// A start inside a window spends nothing. On an empty tank, which only a
/// fold can meet, fuel holds at 0 (research R6).
EconomyState applyTripStart(EconomyState s, Op op) {
  final t = op.occurredAtMs;
  return s.copyWith(
    fuel: isUnlimited(s.fuel, t)
        ? s.fuel
        : spendOne(s.fuel, t, max: op.fuelMax),
    unfinished: () => UnfinishedTrip(
      startTxn: op.txnId,
      tripId: op.string('trip_id'),
      contentVersion: op.contentVersion,
      maxEarningsJenehat: op.maxEarningsJenehat ?? 0,
      startedAtMs: t,
    ),
  );
}

/// One result per start, within the trip's bounds (FR-032). The economy
/// checks bounds only; the engine decided the result (constitution I).
Decision validateTripResult(
  EconomyState s,
  RecordResultRequest request,
  RuleContext ctx,
) {
  final RecordResultRequest(:start, :result) = request;
  if (s.lastResult?.startTxn == start) {
    return const Declined(EconomyRefusal.resultExists);
  }
  final unfinished = s.unfinished;
  if (unfinished == null || unfinished.startTxn != start) {
    return const Declined(EconomyRefusal.noTripStart);
  }
  if (result.tripId != unfinished.tripId) {
    return const Declined(EconomyRefusal.tripMismatch);
  }
  final finished = result.outcome == TripOutcome.finished;
  final stars = result.stars;
  if (stars < 0 || stars > maxStars || (!finished && stars != 0)) {
    return const Declined(EconomyRefusal.starsOutOfBounds);
  }
  final earnings = result.earningsJenehat;
  if (earnings < 0 ||
      earnings > unfinished.maxEarningsJenehat ||
      (!finished && earnings != 0)) {
    return const Declined(EconomyRefusal.earningsOutOfBounds);
  }
  return Validated(
    ctx.op(
      OpType.tripResult,
      {'trip_start_txn': start.value, 'result': result.toJson()},
      jenehatDelta: earnings,
      reason: LedgerReason.tripEarnings,
      ref: start,
    ),
  );
}

EconomyState applyTripResult(EconomyState s, Op op) {
  final result = op.payload['result']! as Map<String, Object?>;
  final tripId = result['trip_id']! as String;
  final outcome = byWire(TripOutcome.values, (o) => o.wire, result['outcome'])!;
  final finished = outcome == TripOutcome.finished;
  final stars = finished ? result['stars']! as int : 0;
  final duration = result['duration_ms']! as int;
  final old = s.progress[tripId];
  final bestTime = old?.bestTimeMs;
  final progress = TripProgress(
    bestStars: _max(old?.bestStars ?? 0, stars),
    bestTimeMs: !finished
        ? bestTime
        : bestTime == null || duration < bestTime
        ? duration
        : bestTime,
    plays: (old?.plays ?? 0) + 1,
    firstCompletedAtMs:
        old?.firstCompletedAtMs ?? (finished ? op.occurredAtMs : null),
  );
  return s.copyWith(
    jenehat: s.jenehat + op.jenehatDelta,
    progress: {...s.progress, tripId: progress},
    unfinished: () => null,
    lastResult: () => LastResult(
      startTxn: TxnId.parse(op.string('trip_start_txn')),
      outcome: outcome,
      earningsJenehat: op.jenehatDelta,
    ),
  );
}

/// Left out of a fold when its start was left out, or already has a result.
bool tripResultStillValid(EconomyState s, Op op) =>
    s.unfinished?.startTxn == op.ref && s.lastResult?.startTxn != op.ref;

int _max(int a, int b) => a > b ? a : b;
