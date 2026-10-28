// Requests and the operations they become (data-model.md "OpRequest → Op",
// contracts/operations.md). Wire names are backend §7.2–§7.4's, spelled
// exactly, because M06 sends them unchanged.
import 'package:content_models/content_models.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/economy/domain/txn_id.dart';

/// The `op_type`s the economy applies (backend §7.4).
enum OpType {
  tripStart('trip_start'),
  tripResult('trip_result'),
  adReward('ad_reward'),
  spendJenehat('spend_jenehat'),
  spendBonat('spend_bonat'),
  useBooster('use_booster'),

  /// The comeback gift (specs/011-m06-identity-sync research R16).
  comebackGift('comeback_gift'),

  /// The driver's name (specs/012-m07-onboarding research R8).
  settingsUpdate('settings_update'),

  /// The fuel lesson's full tank, once per player (M07 research R8, R9).
  tutorialGift('tutorial_gift');

  const OpType(this.wire);

  final String wire;
}

/// The `reason` of a JENEHAT or BONAT effect (backend §7.2, research R7).
enum LedgerReason {
  tripEarnings('trip_earnings'),
  adResultDouble('ad_result_double'),
  itemPurchase('item_purchase'),
  vehiclePurchase('vehicle_purchase'),
  chapterPurchase('chapter_purchase'),
  boosterPurchase('booster_purchase'),
  fuelPurchase('fuel_purchase'),
  revivePurchase('revive_purchase'),
  fuelUnlimitedPurchase('fuel_unlimited_purchase');

  const LedgerReason(this.wire);

  final String wire;
}

/// Rewarded ad placements (glossary §3.4).
enum AdPlacement {
  resultDouble('result_double'),
  fuelRefill('fuel_refill'),
  tripRevive('trip_revive'),
  trafficJam('traffic_jam'),
  morningPiggy('morning_piggy');

  const AdPlacement(this.wire);

  final String wire;
}

/// How a `trip_start` pays for itself. `challenge` is M13's.
enum FuelMode {
  fuel('fuel'),
  unlimited('unlimited');

  const FuelMode(this.wire);

  final String wire;
}

/// Where an operation is in sync (data-model.md "SyncStatus"). Only M06 moves
/// it, and never back to [pending].
enum SyncStatus {
  pending('pending'),
  accepted('accepted'),
  rejected('rejected');

  const SyncStatus(this.wire);

  final String wire;
}

/// The value of [values] whose `wire` is [wire], or null.
T? byWire<T extends Enum>(
  List<T> values,
  String Function(T) wireOf,
  Object? wire,
) {
  for (final value in values) {
    if (wireOf(value) == wire) return value;
  }
  return null;
}

/// What a caller asks the economy for (contracts/economy-api.md).
sealed class OpRequest {
  const OpRequest();
}

final class StartTripRequest extends OpRequest {
  const StartTripRequest(this.tripId);

  final String tripId;
}

final class RecordResultRequest extends OpRequest {
  const RecordResultRequest({required this.start, required this.result});

  final TxnId start;
  final TripResult result;
}

/// A purchase. [variantId] is required for an item, and null otherwise.
final class BuyRequest extends OpRequest {
  const BuyRequest({required this.kind, required this.skuId, this.variantId});

  final SkuKind kind;
  final String skuId;
  final String? variantId;
}

final class UseBoosterRequest extends OpRequest {
  const UseBoosterRequest(this.booster);

  final BoosterId booster;
}

final class AdRewardRequest extends OpRequest {
  const AdRewardRequest(this.placement);

  final AdPlacement placement;
}

/// The comeback gift. Only `ComebackGift` asks for it, through
/// `EconomySync`, behind its guard (specs/011-m06-identity-sync R16).
final class ComebackGiftRequest extends OpRequest {
  const ComebackGiftRequest();
}

/// The driver's name, as typed: the rules normalize it (M07 contracts/
/// name.md "The operation").
final class SettingsUpdateRequest extends OpRequest {
  const SettingsUpdateRequest(this.name);

  final String name;
}

/// The fuel lesson's gift (M07 contracts/fuel-lesson.md).
final class TutorialGiftRequest extends OpRequest {
  const TutorialGiftRequest();
}

/// An operation: what a request became once validated, and what is stored
/// and applied. [payload] is the wire payload, integers and strings only.
final class Op {
  const Op({
    required this.txnId,
    required this.type,
    required this.payload,
    required this.occurredAtMs,
    required this.contentVersion,
    required this.fuelMax,
    required this.fuelRegenMinutes,
    this.jenehatDelta = 0,
    this.bonatDelta = 0,
    this.fuelDelta = 0,
    this.reason,
    this.ref,
    this.maxEarningsJenehat,
  });

  final TxnId txnId;
  final OpType type;
  final Map<String, Object> payload;
  final int jenehatDelta;
  final int bonatDelta;

  /// What this operation changed in the tank, for M06 and for reading the
  /// log. The fold recomputes fuel from the times (research R8).
  final int fuelDelta;
  final LedgerReason? reason;

  /// The trip start this operation belongs to.
  final TxnId? ref;

  /// Trusted time (research R9).
  final int occurredAtMs;
  final int contentVersion;

  /// The fuel tunables this operation applied (research R4).
  final int fuelMax;
  final int fuelRegenMinutes;

  /// `trip_start` only: the trip's bound, from the pack at the start. Local,
  /// never sent.
  final int? maxEarningsJenehat;

  String string(String key) => payload[key]! as String;

  int integer(String key) => payload[key]! as int;

  @override
  String toString() => 'Op(${type.wire} $txnId)';
}

/// A stored operation, as M06 reads and sends it (contracts/operations.md
/// "What M06 sends").
final class LedgerOp {
  const LedgerOp({
    required this.seq,
    required this.op,
    required this.syncStatus,
    this.syncReason,
  });

  /// The order operations were applied in, and the order M06 sends them in.
  final int seq;
  final Op op;
  final SyncStatus syncStatus;
  final String? syncReason;

  @override
  String toString() => 'LedgerOp($seq ${op.type.wire} ${syncStatus.wire})';
}
