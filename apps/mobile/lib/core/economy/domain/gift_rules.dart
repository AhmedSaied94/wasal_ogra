// `comeback_gift` (specs/011-m06-identity-sync, contracts/sync.md "The
// comeback gift", research R16): the tank to its maximum and one
// `change_bag`. It never adds BONAT. Its guard is `ComebackGift`'s; the
// rule itself accepts, and a full tank only gets the booster.
import 'package:content_models/content_models.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/fuel.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/rules.dart';

Decision validateComebackGift(
  EconomyState s,
  ComebackGiftRequest request,
  RuleContext ctx,
) => Validated(
  ctx.op(
    OpType.comebackGift,
    const {},
    fuelDelta: s.fuel.liters < ctx.fuelMax ? ctx.fuelMax - s.fuel.liters : 0,
  ),
);

EconomyState applyComebackGift(EconomyState s, Op op) => s.copyWith(
  fuel: fillToMax(s.fuel, op.occurredAtMs, max: op.fuelMax) ?? s.fuel,
  inventory: {
    ...s.inventory,
    BoosterId.changeBag: (s.inventory[BoosterId.changeBag] ?? 0) + 1,
  },
);
