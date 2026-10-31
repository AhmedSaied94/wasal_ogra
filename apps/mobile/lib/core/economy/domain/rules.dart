// Validate and apply, per operation (contracts/operations.md, research R5,
// R6). Pure functions: the service applies them step by step, and the fold
// replays them over a base.
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/economy/domain/ad_rules.dart';
import 'package:wassal/core/economy/domain/booster_rules.dart';
import 'package:wassal/core/economy/domain/economy_refusal.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/fuel.dart';
import 'package:wassal/core/economy/domain/gift_rules.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/profile_rules.dart';
import 'package:wassal/core/economy/domain/spend_rules.dart';
import 'package:wassal/core/economy/domain/story_rules.dart';
import 'package:wassal/core/economy/domain/trip_rules.dart';
import 'package:wassal/core/economy/domain/txn_id.dart';
import 'package:wassal/core/economy/domain/wire.dart';

/// What a request is validated against: trusted now, the active pack and the
/// fuel tunables, read when the request applies.
final class RuleContext {
  const RuleContext({
    required this.nowMs,
    required this.content,
    required this.contentVersion,
    required this.fuelMax,
    required this.fuelRegenMinutes,
    required this.txnId,
  });

  final int nowMs;
  final ContentSource content;
  final int contentVersion;
  final int fuelMax;
  final int fuelRegenMinutes;
  final TxnId txnId;

  int get regenMs => regenMsOf(fuelRegenMinutes);

  /// The operation this request becomes, stamped with this context.
  Op op(
    OpType type,
    Map<String, Object> payload, {
    int jenehatDelta = 0,
    int bonatDelta = 0,
    int fuelDelta = 0,
    LedgerReason? reason,
    TxnId? ref,
    int? maxEarningsJenehat,
  }) => Op(
    txnId: txnId,
    type: type,
    payload: payload,
    jenehatDelta: jenehatDelta,
    bonatDelta: bonatDelta,
    fuelDelta: fuelDelta,
    reason: reason,
    ref: ref,
    occurredAtMs: nowMs,
    contentVersion: contentVersion,
    fuelMax: fuelMax,
    fuelRegenMinutes: fuelRegenMinutes,
    maxEarningsJenehat: maxEarningsJenehat,
  );
}

sealed class Decision {
  const Decision();
}

final class Validated extends Decision {
  const Validated(this.op);

  final Op op;
}

final class Declined extends Decision {
  const Declined(this.code);

  final EconomyRefusal code;
}

abstract interface class Rules {
  /// Refuses [request], or gives the operation it becomes. [state] is the
  /// current state; the rules regenerate its fuel to now first.
  Decision validate(EconomyState state, OpRequest request, RuleContext ctx);

  /// [state] after [op], with fuel regenerated to the op's time first.
  EconomyState apply(EconomyState state, Op op);

  /// Whether [op] still applies to [state] in a fold. Balance, ownership,
  /// inventory and trip-linkage checks are repeated; content and catalog
  /// checks aren't, and fuel is lenient (research R6).
  bool stillValid(EconomyState state, Op op);
}

final class ProductionRules implements Rules {
  const ProductionRules();

  @override
  Decision validate(EconomyState state, OpRequest request, RuleContext ctx) {
    final s = state.copyWith(
      fuel: regenerate(
        state.fuel,
        ctx.nowMs,
        max: ctx.fuelMax,
        regenMs: ctx.regenMs,
      ),
    );
    return switch (request) {
      StartTripRequest() => validateTripStart(s, request, ctx),
      RecordResultRequest() => validateTripResult(s, request, ctx),
      AdRewardRequest() => validateAdReward(s, request, ctx),
      BuyRequest() => validateBuy(s, request, ctx),
      UseBoosterRequest() => validateUseBooster(s, request, ctx),
      ComebackGiftRequest() => validateComebackGift(s, request, ctx),
      SettingsUpdateRequest() => validateSettingsUpdate(s, request, ctx),
      TutorialGiftRequest() => validateTutorialGift(s, request, ctx),
      StoryProgressRequest() => validateStoryProgress(s, request, ctx),
      ClaimRequest() => validateClaimRequest(s, request, ctx),
    };
  }

  @override
  EconomyState apply(EconomyState state, Op op) {
    final s = state.copyWith(
      fuel: regenerate(
        state.fuel,
        op.occurredAtMs,
        max: op.fuelMax,
        regenMs: regenMsOf(op.fuelRegenMinutes),
      ),
    );
    return switch (op.type) {
      OpType.tripStart => applyTripStart(s, op),
      OpType.tripResult => applyTripResult(s, op),
      OpType.adReward => applyAdReward(s, op),
      OpType.spendJenehat || OpType.spendBonat => applySpend(s, op),
      OpType.useBooster => applyUseBooster(s, op),
      OpType.comebackGift => applyComebackGift(s, op),
      OpType.settingsUpdate => applySettingsUpdate(s, op),
      OpType.tutorialGift => applyTutorialGift(s, op),
      OpType.storyProgress => applyStoryProgress(s, op),
      OpType.claimRequest => applyClaimRequest(s, op),
    };
  }

  @override
  bool stillValid(EconomyState state, Op op) => switch (op.type) {
    OpType.tripStart => true,
    OpType.tripResult => tripResultStillValid(state, op),
    OpType.adReward => adRewardStillValid(state, op),
    OpType.spendJenehat || OpType.spendBonat => spendStillValid(state, op),
    OpType.useBooster => useBoosterStillValid(state, op),
    OpType.comebackGift => true,
    OpType.settingsUpdate => true,
    OpType.tutorialGift => tutorialGiftStillValid(state, op),
    OpType.storyProgress => storyProgressStillValid(state, op),
    OpType.claimRequest => claimRequestStillValid(state, op),
  };
}

/// Whether [op] is what [request] would have become: a repeated id must
/// carry the same intent (research R10). Checked in debug builds only.
bool requestMatches(Op op, OpRequest request) => switch (request) {
  StartTripRequest(:final tripId) =>
    op.type == OpType.tripStart && op.payload['trip_id'] == tripId,
  RecordResultRequest(:final start) =>
    op.type == OpType.tripResult && op.payload['trip_start_txn'] == start.value,
  AdRewardRequest(:final placement) =>
    op.type == OpType.adReward && op.payload['ad_placement'] == placement.wire,
  BuyRequest(:final kind, :final skuId, :final variantId) =>
    (op.type == OpType.spendJenehat || op.type == OpType.spendBonat) &&
        op.payload['sku_kind'] == skuKindWire[kind] &&
        op.payload['sku_id'] == skuId &&
        op.payload['variant'] == variantId,
  UseBoosterRequest(:final booster) =>
    op.type == OpType.useBooster &&
        op.payload['booster_id'] == boosterWire[booster],
  ComebackGiftRequest() => op.type == OpType.comebackGift,
  SettingsUpdateRequest() => settingsUpdateMatches(op, request),
  TutorialGiftRequest() => op.type == OpType.tutorialGift,
  StoryProgressRequest(:final chapterId, :final sceneId) =>
    op.type == OpType.storyProgress &&
        op.payload['chapter_id'] == chapterWire[chapterId] &&
        op.payload['scene_id'] == sceneId,
  ClaimRequest(:final requestId) =>
    op.type == OpType.claimRequest && op.payload['request_id'] == requestId,
};
