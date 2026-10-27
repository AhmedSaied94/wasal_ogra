// How every feature changes or reads balances, fuel, boosters, ownership and
// trip progress (specs/007-m05-local-economy/contracts/economy-api.md). This
// is the only way to change those parts of the database (FR-013).
import 'package:content_models/content_models.dart';
import 'package:trip_engine/trip_engine.dart' show TripResult;
import 'package:wassal/core/economy/domain/economy_refusal.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/fuel.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/txn_id.dart';

export 'package:wassal/core/economy/domain/economy_refusal.dart';
export 'package:wassal/core/economy/domain/economy_state.dart';
export 'package:wassal/core/economy/domain/fuel.dart' show FuelView;
export 'package:wassal/core/economy/domain/op.dart'
    show AdPlacement, LedgerOp, Op, OpType, SyncStatus;
export 'package:wassal/core/economy/domain/txn_id.dart';

abstract interface class Economy {
  /// The current view. Synchronous after startup.
  EconomyView get view;

  /// A new view after every operation, every liter that arrives while the
  /// app is in the foreground, and every tunable change (research R17).
  Stream<EconomyView> get views;

  /// A fresh UUIDv7 for one player intent. Hold it, and send it again on a
  /// retry or a double tap (research R10).
  TxnId newRequestId();

  // Trips (research R12).
  Future<OpOutcome> startTrip(TxnId id, {required String tripId});
  Future<OpOutcome> recordResult(
    TxnId id, {
    required TxnId start,
    required TripResult result,
  });
  Future<OpOutcome> useBooster(TxnId id, {required BoosterId booster});

  // Purchases (research R13). [variantId] is required for an item, and must
  // be null otherwise. A revive applies to the unfinished trip.
  Future<OpOutcome> buy(
    TxnId id, {
    required SkuKind kind,
    required String skuId,
    String? variantId,
  });

  // Rewarded ads, applied after the ad's reward callback (M11).
  Future<OpOutcome> applyAdReward(TxnId id, {required AdPlacement placement});

  // The sync's calls are on `EconomySync` (economy_sync.dart), out of the
  // screens' reach (specs/011-m06-identity-sync, research R20).
}

/// What a request came to. No method throws for a refusal or a write error.
sealed class OpOutcome {
  const OpOutcome();
}

/// Stored, with its effects in [view]. [repeated] is true when the id was
/// already stored, and nothing new was written (FR-016).
final class OpApplied extends OpOutcome {
  const OpApplied({
    required this.op,
    required this.view,
    required this.repeated,
  });

  final LedgerOp op;
  final EconomyView view;
  final bool repeated;
}

/// Nothing was stored or changed (FR-019). [code] tells the screen what to
/// show.
final class OpRefused extends OpOutcome {
  const OpRefused(this.code);

  final EconomyRefusal code;

  @override
  String toString() => 'OpRefused(${code.wire})';
}

/// A full disk or another write error. Nothing changed, and a retry may
/// reuse the id (research R11).
final class OpWriteFailed extends OpOutcome {
  const OpWriteFailed();
}

/// What screens read (FR-042). [progress] and ownership may name ids the
/// active pack lacks: readers look entries up by the ids the content source
/// gives them, so those are skipped, never errors (FR-034).
final class EconomyView {
  EconomyView(EconomyState state, this.fuel)
    : jenehat = state.jenehat,
      bonat = state.bonat,
      inventory = state.inventory,
      progress = state.progress,
      unfinished = state.unfinished,
      lastResult = state.lastResult,
      _ownership = state.ownership;

  final int jenehat;
  final int bonat;
  final FuelView fuel;
  final Map<BoosterId, int> inventory;
  final Map<String, TripProgress> progress;
  final UnfinishedTrip? unfinished;
  final LastResult? lastResult;
  final Map<OwnedKey, Owned> _ownership;

  bool owns(SkuKind kind, String skuId) =>
      _ownership.containsKey((kind, skuId));

  /// The style the player chose for an owned item, or null.
  String? variantOf(String itemId) =>
      _ownership[(SkuKind.item, itemId)]?.variantId;

  @override
  String toString() =>
      'EconomyView(J $jenehat, B $bonat, $fuel, $inventory, $unfinished)';
}
