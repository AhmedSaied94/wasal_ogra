// The gifts the device applies. Neither ever adds BONAT.
// - `comeback_gift` (specs/011-m06-identity-sync, contracts/sync.md "The
//   comeback gift", research R16): the tank to its maximum and one
//   `change_bag`. Its guard is `ComebackGift`'s; the rule itself accepts,
//   and a full tank only gets the booster.
// - `tutorial_gift` (specs/012-m07-onboarding/contracts/fuel-lesson.md "The
//   operation"): the tank to its maximum, once per player.
import 'package:content_models/content_models.dart';
import 'package:wassal/core/economy/domain/economy_refusal.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/fuel.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/rules.dart';

Decision validateComebackGift(
  EconomyState s,
  ComebackGiftRequest request,
  RuleContext ctx,
) => Validated(
  ctx.op(OpType.comebackGift, const {}, fuelDelta: _fillDelta(s, ctx)),
);

/// The liters a fill to [EconomyState.fuel]'s maximum adds.
int _fillDelta(EconomyState s, RuleContext ctx) =>
    s.fuel.liters < ctx.fuelMax ? ctx.fuelMax - s.fuel.liters : 0;

Decision validateTutorialGift(
  EconomyState s,
  TutorialGiftRequest request,
  RuleContext ctx,
) => s.tutorialGranted
    ? const Declined(EconomyRefusal.alreadyGranted)
    : Validated(
        ctx.op(OpType.tutorialGift, const {}, fuelDelta: _fillDelta(s, ctx)),
      );

EconomyState applyTutorialGift(EconomyState s, Op op) => s.copyWith(
  fuel: fillToMax(s.fuel, op.occurredAtMs, max: op.fuelMax) ?? s.fuel,
  tutorialGranted: true,
);

/// A grant that reached the base (the server's, on a restore) drops a
/// pending local one.
bool tutorialGiftStillValid(EconomyState s, Op op) => !s.tutorialGranted;

EconomyState applyComebackGift(EconomyState s, Op op) => s.copyWith(
  fuel: fillToMax(s.fuel, op.occurredAtMs, max: op.fuelMax) ?? s.fuel,
  inventory: {
    ...s.inventory,
    BoosterId.changeBag: (s.inventory[BoosterId.changeBag] ?? 0) + 1,
  },
);
