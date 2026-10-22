// `use_booster` (contracts/operations.md). M02 calls it only after the engine
// accepted `UseBooster`.
import 'package:content_models/content_models.dart';
import 'package:wassal/core/economy/domain/economy_refusal.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/rules.dart';
import 'package:wassal/core/economy/domain/wire.dart';

Decision validateUseBooster(
  EconomyState s,
  UseBoosterRequest request,
  RuleContext ctx,
) {
  final unfinished = s.unfinished;
  if (unfinished == null) return const Declined(EconomyRefusal.noTrip);
  final booster = request.booster;
  if (!inTripBoosters.contains(booster)) {
    return const Declined(EconomyRefusal.unknownSku);
  }
  if ((s.inventory[booster] ?? 0) < 1) {
    return const Declined(EconomyRefusal.noneLeft);
  }
  return Validated(
    ctx.op(OpType.useBooster, {
      'booster_id': boosterWire[booster]!,
      'ref': unfinished.startTxn.value,
    }, ref: unfinished.startTxn),
  );
}

BoosterId _boosterOf(Op op) => fromWire(boosterWire, op.payload['booster_id'])!;

EconomyState applyUseBooster(EconomyState s, Op op) {
  final booster = _boosterOf(op);
  return s.copyWith(
    inventory: {...s.inventory, booster: (s.inventory[booster] ?? 0) - 1},
  );
}

/// Left out of a fold when none of that booster is left (research R6).
bool useBoosterStillValid(EconomyState s, Op op) =>
    (s.inventory[_boosterOf(op)] ?? 0) >= 1;
