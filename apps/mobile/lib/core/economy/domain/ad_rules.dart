// `ad_reward`, applied after the ad's reward callback (contracts/operations.md
// "ad_reward"). The daily caps are M11's; the per-trip caps the economy can
// see are enforced here (FR-037).
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/economy/domain/economy_refusal.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/fuel.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/rules.dart';

Decision validateAdReward(
  EconomyState s,
  AdRewardRequest request,
  RuleContext ctx,
) {
  final placement = request.placement;
  switch (placement) {
    case AdPlacement.resultDouble:
      // Only the latest result, once, and only a finished one that paid
      // (FR-035).
      final last = s.lastResult;
      if (last == null) return const Declined(EconomyRefusal.noResult);
      if (last.outcome != TripOutcome.finished || last.earningsJenehat <= 0) {
        return const Declined(EconomyRefusal.notDoublable);
      }
      if (last.doubled) return const Declined(EconomyRefusal.alreadyDoubled);
      return Validated(
        ctx.op(
          OpType.adReward,
          {'ad_placement': placement.wire, 'ref': last.startTxn.value},
          jenehatDelta: last.earningsJenehat,
          reason: LedgerReason.adResultDouble,
          ref: last.startTxn,
        ),
      );
    case AdPlacement.fuelRefill:
      // Belongs to no trip, so it carries no `ref` (research R21).
      if (s.fuel.liters >= ctx.fuelMax) {
        return const Declined(EconomyRefusal.tankFull);
      }
      return Validated(
        ctx.op(OpType.adReward, {
          'ad_placement': placement.wire,
        }, fuelDelta: ctx.fuelMax - s.fuel.liters),
      );
    case AdPlacement.tripRevive:
      final unfinished = s.unfinished;
      if (unfinished == null) return const Declined(EconomyRefusal.noTrip);
      if (unfinished.revived) {
        return const Declined(EconomyRefusal.alreadyRevived);
      }
      return Validated(
        ctx.op(OpType.adReward, {
          'ad_placement': placement.wire,
          'ref': unfinished.startTxn.value,
        }, ref: unfinished.startTxn),
      );
    case AdPlacement.trafficJam:
      final unfinished = s.unfinished;
      if (unfinished == null) return const Declined(EconomyRefusal.noTrip);
      if (unfinished.trafficJamAds >= trafficJamAdsPerTrip) {
        return const Declined(EconomyRefusal.capReached);
      }
      return Validated(
        ctx.op(OpType.adReward, {
          'ad_placement': placement.wire,
          'ref': unfinished.startTxn.value,
        }, ref: unfinished.startTxn),
      );
    case AdPlacement.morningPiggy:
      // It grants BONAT, which only the server's SSV may do (constitution IV).
      return const Declined(EconomyRefusal.serverOnly);
  }
}

AdPlacement? _placementOf(Op op) =>
    byWire(AdPlacement.values, (p) => p.wire, op.payload['ad_placement']);

EconomyState applyAdReward(EconomyState s, Op op) {
  switch (_placementOf(op)) {
    case AdPlacement.resultDouble:
      final last = s.lastResult;
      return s.copyWith(
        jenehat: s.jenehat + op.jenehatDelta,
        lastResult: () => last == null
            ? null
            : LastResult(
                startTxn: last.startTxn,
                outcome: last.outcome,
                earningsJenehat: last.earningsJenehat,
                doubled: true,
              ),
      );
    case AdPlacement.fuelRefill:
      // A refill on a tank the fold finds full adds nothing (research R6).
      return s.copyWith(
        fuel: fillToMax(s.fuel, op.occurredAtMs, max: op.fuelMax) ?? s.fuel,
      );
    case AdPlacement.tripRevive:
      return s.copyWith(
        unfinished: () => s.unfinished?.copyWith(revived: true),
      );
    case AdPlacement.trafficJam:
      final unfinished = s.unfinished;
      return s.copyWith(
        unfinished: () =>
            unfinished?.copyWith(trafficJamAds: unfinished.trafficJamAds + 1),
      );
    case AdPlacement.morningPiggy || null:
      return s;
  }
}

bool adRewardStillValid(EconomyState s, Op op) {
  final unfinished = s.unfinished;
  return switch (_placementOf(op)) {
    AdPlacement.resultDouble =>
      s.lastResult?.startTxn == op.ref && s.lastResult?.doubled == false,
    AdPlacement.fuelRefill => true,
    AdPlacement.tripRevive =>
      unfinished?.startTxn == op.ref && unfinished?.revived == false,
    AdPlacement.trafficJam =>
      unfinished != null &&
          unfinished.startTxn == op.ref &&
          unfinished.trafficJamAds < trafficJamAdsPerTrip,
    AdPlacement.morningPiggy || null => false,
  };
}
