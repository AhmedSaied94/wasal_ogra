// `spend_jenehat` and `spend_bonat` (contracts/operations.md, research R13).
// The price comes from the active catalog when the purchase applies, never
// from the caller (constitution VII).
import 'package:content_models/content_models.dart';
import 'package:wassal/core/economy/domain/economy_refusal.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/fuel.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/rules.dart';
import 'package:wassal/core/economy/domain/wire.dart';

/// The kind decides the currency, so no content error can open a
/// BONAT-for-JENEHAT path (constitution IV, research R7).
const kindCurrency = <SkuKind, Currency>{
  SkuKind.item: Currency.jenehat,
  SkuKind.vehicle: Currency.jenehat,
  SkuKind.chapter: Currency.jenehat,
  SkuKind.booster: Currency.bonat,
  SkuKind.fuel: Currency.bonat,
  SkuKind.revive: Currency.bonat,
  SkuKind.fuelUnlimited: Currency.bonat,
};

/// The one SKU of each single-product kind (glossary §3.3).
const refuelFullSku = 'refuel_full';
const fuelUnlimitedSku = 'fuel_unlimited_1h';
const reviveSku = 'revive';

const _reasons = <SkuKind, LedgerReason>{
  SkuKind.item: LedgerReason.itemPurchase,
  SkuKind.vehicle: LedgerReason.vehiclePurchase,
  SkuKind.chapter: LedgerReason.chapterPurchase,
  SkuKind.booster: LedgerReason.boosterPurchase,
  SkuKind.fuel: LedgerReason.fuelPurchase,
  SkuKind.revive: LedgerReason.revivePurchase,
  SkuKind.fuelUnlimited: LedgerReason.fuelUnlimitedPurchase,
};

/// Refusals in the order contracts/operations.md lists them. The kind's own
/// state checks (`tank_full`, `no_trip`, `already_revived`) come after
/// `already_owned` and before `insufficient_funds`, so a purchase that can't
/// apply is never reported as unaffordable.
Decision validateBuy(EconomyState s, BuyRequest request, RuleContext ctx) {
  final BuyRequest(:kind, :skuId, :variantId) = request;
  final price = ctx.content.price(kind, skuId);
  if (price == null) return const Declined(EconomyRefusal.notForSale);
  final currency = kindCurrency[kind]!;
  if (price.currency != currency || price.amount < 0) {
    return const Declined(EconomyRefusal.catalogMismatch);
  }
  if (!_knownSku(kind, skuId, ctx)) {
    return const Declined(EconomyRefusal.unknownSku);
  }
  if (!_validVariant(kind, skuId, variantId, ctx)) {
    return const Declined(EconomyRefusal.unknownVariant);
  }
  if (ownableKinds.contains(kind) && s.ownership.containsKey((kind, skuId))) {
    return const Declined(EconomyRefusal.alreadyOwned);
  }
  final unfinished = s.unfinished;
  final stateRefusal = switch (kind) {
    SkuKind.fuel when s.fuel.liters >= ctx.fuelMax => EconomyRefusal.tankFull,
    SkuKind.revive when unfinished == null => EconomyRefusal.noTrip,
    SkuKind.revive when unfinished?.revived ?? false =>
      EconomyRefusal.alreadyRevived,
    _ => null,
  };
  if (stateRefusal != null) return Declined(stateRefusal);
  final balance = currency == Currency.jenehat ? s.jenehat : s.bonat;
  if (balance < price.amount) {
    return const Declined(EconomyRefusal.insufficientFunds);
  }
  final ref = kind == SkuKind.revive ? unfinished?.startTxn : null;
  return Validated(
    ctx.op(
      currency == Currency.jenehat ? OpType.spendJenehat : OpType.spendBonat,
      {
        'sku_kind': skuKindWire[kind]!,
        'sku_id': skuId,
        'variant': ?variantId,
        'price': price.amount,
        'ref': ?ref?.value,
      },
      jenehatDelta: currency == Currency.jenehat ? -price.amount : 0,
      bonatDelta: currency == Currency.bonat ? -price.amount : 0,
      fuelDelta: kind == SkuKind.fuel ? ctx.fuelMax - s.fuel.liters : 0,
      reason: _reasons[kind],
      ref: ref,
    ),
  );
}

bool _knownSku(SkuKind kind, String skuId, RuleContext ctx) => switch (kind) {
  SkuKind.item => ctx.content.item(skuId) != null,
  SkuKind.vehicle => switch (fromWire(vehicleWire, skuId)) {
    final id? => ctx.content.vehicle(id) != null,
    null => false,
  },
  SkuKind.chapter => switch (fromWire(chapterWire, skuId)) {
    final id? => ctx.content.chapter(id) != null,
    null => false,
  },
  SkuKind.booster => inTripBoosters.contains(fromWire(boosterWire, skuId)),
  SkuKind.fuel => skuId == refuelFullSku,
  SkuKind.fuelUnlimited => skuId == fuelUnlimitedSku,
  SkuKind.revive => skuId == reviveSku,
};

/// An item names one of its variants; nothing else names one.
bool _validVariant(
  SkuKind kind,
  String skuId,
  String? variantId,
  RuleContext ctx,
) {
  if (kind != SkuKind.item) return variantId == null;
  final variants = ctx.content.item(skuId)?.variants ?? const <ItemVariant>[];
  return variants.any((v) => v.variantId == variantId);
}

SkuKind _kindOf(Op op) => fromWire(skuKindWire, op.payload['sku_kind'])!;

EconomyState applySpend(EconomyState s, Op op) {
  final kind = _kindOf(op);
  final skuId = op.string('sku_id');
  final t = op.occurredAtMs;
  final paid = s.copyWith(
    jenehat: s.jenehat + op.jenehatDelta,
    bonat: s.bonat + op.bonatDelta,
  );
  switch (kind) {
    case SkuKind.item || SkuKind.vehicle || SkuKind.chapter:
      return paid.copyWith(
        ownership: {
          ...s.ownership,
          (kind, skuId): Owned(
            kind: kind,
            variantId: op.payload['variant'] as String?,
            acquiredAtMs: t,
            acquiredBy: op.txnId,
          ),
        },
      );
    case SkuKind.booster:
      final booster = fromWire(boosterWire, skuId)!;
      return paid.copyWith(
        inventory: {...s.inventory, booster: (s.inventory[booster] ?? 0) + 1},
      );
    case SkuKind.fuel:
      // A refill the fold finds on a full tank adds nothing (research R6).
      return paid.copyWith(
        fuel: fillToMax(s.fuel, t, max: op.fuelMax) ?? s.fuel,
      );
    case SkuKind.fuelUnlimited:
      return paid.copyWith(fuel: extendUnlimited(s.fuel, t));
    case SkuKind.revive:
      return paid.copyWith(
        unfinished: () => s.unfinished?.copyWith(revived: true),
      );
  }
}

/// Left out of a fold when a balance would go below 0, the SKU is already
/// owned, or a revive's trip was left out.
bool spendStillValid(EconomyState s, Op op) {
  if (s.jenehat + op.jenehatDelta < 0 || s.bonat + op.bonatDelta < 0) {
    return false;
  }
  final kind = _kindOf(op);
  if (ownableKinds.contains(kind)) {
    return !s.ownership.containsKey((kind, op.string('sku_id')));
  }
  if (kind == SkuKind.revive) {
    final unfinished = s.unfinished;
    return unfinished != null &&
        unfinished.startTxn == op.ref &&
        !unfinished.revived;
  }
  return true;
}
