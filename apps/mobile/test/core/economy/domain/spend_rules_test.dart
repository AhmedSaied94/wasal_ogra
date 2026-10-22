import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/content/pack_content_source.dart';
import 'package:wassal/core/economy/domain/economy_refusal.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/fuel.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/rules.dart';
import 'package:wassal/core/economy/domain/wire.dart';

import '../../../helpers/content.dart';
import '../../../helpers/economy.dart';

// `spend_jenehat` and `spend_bonat` (contracts/operations.md, research R13),
// against the sample pack and a pack whose catalog is broken.

const _rules = ProductionRules();
const _minuteMs = 60000;

/// Plenty of both currencies, 2 liters, no trip.
final _rich = EconomyState(
  jenehat: 10000,
  bonat: 1000,
  fuel: const FuelState(liters: 2, countedFromMs: testEpochMs),
);

final _trip = UnfinishedTrip(
  startTxn: txnIdOf(50),
  tripId: 'line_hay.01',
  contentVersion: 1,
  maxEarningsJenehat: 20,
  startedAtMs: testEpochMs,
);

/// The sample pack, with these catalog entries changed or added: the
/// mismatches and the SKUs no content names.
ContentSource _brokenCatalog() {
  final json = samplePackJson();
  final catalog = (json['catalog']! as Map<String, Object?>)
      .cast<String, Object?>();
  final prices = [
    for (final price in catalog['prices']! as List<Object?>)
      if (price case {'sku_id': final String id} when id != 'wake_all')
        {...price as Map<String, Object?>},
  ];
  void set(String kind, String id, String currency, int amount) {
    prices
      ..removeWhere((p) => p['sku_kind'] == kind && p['sku_id'] == id)
      ..add({
        'sku_kind': kind,
        'sku_id': id,
        'currency': currency,
        'amount': amount,
      });
  }

  set('item', 'salon.nish', 'BONAT', 40);
  set('booster', 'change_bag', 'JENEHAT', 10);
  set('item', 'salon.sitara', 'JENEHAT', -1);
  set('item', 'salon.ghost', 'JENEHAT', 10);
  set('vehicle', 'bus_big', 'JENEHAT', 10);
  set('chapter', 'ch9_villa', 'JENEHAT', 10);
  set('booster', 'revive', 'BONAT', 10);
  set('fuel', 'refuel_half', 'BONAT', 10);
  return PackContentSource(
    Pack.fromJson({
      ...json,
      'catalog': {...catalog, 'prices': prices},
    }),
  );
}

Decision _buy(
  EconomyState s,
  SkuKind kind,
  String skuId, {
  String? variantId,
  ContentSource? content,
  int nowMs = testEpochMs,
}) => _rules.validate(
  s,
  BuyRequest(kind: kind, skuId: skuId, variantId: variantId),
  ruleContext(content: content, nowMs: nowMs, id: 7),
);

void main() {
  group('each kind', () {
    test('item, with its variant', () {
      final op = validatedOp(
        _buy(_rich, SkuKind.item, 'salon.nish', variantId: 'classic'),
      );
      expect(op.type, OpType.spendJenehat);
      expect(
        canonicalJson(op.payload),
        '{"price":400,"sku_id":"salon.nish","sku_kind":"item",'
        '"variant":"classic"}',
      );
      expect(op.jenehatDelta, -400);
      expect(op.bonatDelta, 0);
      expect(op.reason, LedgerReason.itemPurchase);
      expect(op.contentVersion, 1);
      expect(op.ref, isNull);

      final after = _rules.apply(_rich, op);
      expect(after.jenehat, 9600);
      expect(
        after.ownership[(SkuKind.item, 'salon.nish')],
        Owned(
          kind: SkuKind.item,
          variantId: 'classic',
          acquiredAtMs: testEpochMs,
          acquiredBy: txnIdOf(7),
        ),
      );
    });

    test('vehicle micro_old', () {
      final op = validatedOp(_buy(_rich, SkuKind.vehicle, 'micro_old'));
      expect(
        canonicalJson(op.payload),
        '{"price":1500,"sku_id":"micro_old","sku_kind":"vehicle"}',
      );
      expect(op.jenehatDelta, -1500);
      expect(op.reason, LedgerReason.vehiclePurchase);
      final owned = _rules
          .apply(_rich, op)
          .ownership[(SkuKind.vehicle, 'micro_old')];
      expect(owned?.variantId, isNull);
    });

    test('chapter ch3_shabka', () {
      final op = validatedOp(_buy(_rich, SkuKind.chapter, 'ch3_shabka'));
      expect(
        canonicalJson(op.payload),
        '{"price":900,"sku_id":"ch3_shabka","sku_kind":"chapter"}',
      );
      expect(op.jenehatDelta, -900);
      expect(op.reason, LedgerReason.chapterPurchase);
      expect(
        _rules.apply(_rich, op).ownership.keys,
        contains((SkuKind.chapter, 'ch3_shabka')),
      );
    });

    test('each of the four boosters', () {
      const prices = {
        BoosterId.changeBag: 10,
        BoosterId.ledgerPeek: 12,
        BoosterId.trafficJam: 8,
        BoosterId.wakeAll: 8,
      };
      for (final MapEntry(key: booster, value: price) in prices.entries) {
        final id = boosterWire[booster]!;
        final op = validatedOp(_buy(_rich, SkuKind.booster, id));
        expect(op.type, OpType.spendBonat, reason: id);
        expect(
          canonicalJson(op.payload),
          '{"price":$price,"sku_id":"$id","sku_kind":"booster"}',
        );
        expect(op.bonatDelta, -price);
        expect(op.jenehatDelta, 0);
        expect(op.reason, LedgerReason.boosterPurchase);
        final once = _rules.apply(_rich, op);
        expect(once.inventory[booster], 1);
        expect(_rules.apply(once, op).inventory[booster], 2);
      }
    });

    test('fuel refuel_full fills the tank', () {
      final op = validatedOp(_buy(_rich, SkuKind.fuel, 'refuel_full'));
      expect(
        canonicalJson(op.payload),
        '{"price":30,"sku_id":"refuel_full","sku_kind":"fuel"}',
      );
      expect(op.bonatDelta, -30);
      expect(op.fuelDelta, 3);
      expect(op.reason, LedgerReason.fuelPurchase);
      expect(
        _rules.apply(_rich, op).fuel,
        const FuelState(liters: 5, countedFromMs: testEpochMs),
      );
    });

    test('fuel_unlimited fuel_unlimited_1h opens a window', () {
      final op = validatedOp(
        _buy(_rich, SkuKind.fuelUnlimited, 'fuel_unlimited_1h'),
      );
      expect(
        canonicalJson(op.payload),
        '{"price":80,"sku_id":"fuel_unlimited_1h","sku_kind":"fuel_unlimited"}',
      );
      expect(op.bonatDelta, -80);
      expect(op.reason, LedgerReason.fuelUnlimitedPurchase);
      expect(
        _rules.apply(_rich, op).fuel.unlimitedUntilMs,
        testEpochMs + unlimitedWindowMs,
      );
    });

    test('revive, with its ref', () {
      final s = _rich.copyWith(unfinished: () => _trip);
      final op = validatedOp(_buy(s, SkuKind.revive, 'revive'));
      expect(
        canonicalJson(op.payload),
        '{"price":20,"ref":"${_trip.startTxn.value}","sku_id":"revive",'
        '"sku_kind":"revive"}',
      );
      expect(op.ref, _trip.startTxn);
      expect(op.bonatDelta, -20);
      expect(op.reason, LedgerReason.revivePurchase);
      final after = _rules.apply(s, op);
      expect(after.unfinished?.revived, isTrue);
      expect(after.fuel, s.fuel);
    });
  });

  group('refusals, in order', () {
    final broken = _brokenCatalog();
    final poor = EconomyState(
      jenehat: 0,
      bonat: 0,
      fuel: const FuelState(liters: 5, countedFromMs: testEpochMs),
    );

    test('not_for_sale: no price, even for a SKU that exists', () {
      expect(
        declinedCode(_buy(poor, SkuKind.vehicle, 'tuktuk')),
        EconomyRefusal.notForSale,
      );
      expect(
        declinedCode(_buy(poor, SkuKind.booster, 'wake_all', content: broken)),
        EconomyRefusal.notForSale,
      );
    });

    test('catalog_mismatch: the wrong currency, or a negative price', () {
      for (final (kind, id) in [
        (SkuKind.item, 'salon.nish'),
        (SkuKind.booster, 'change_bag'),
        (SkuKind.item, 'salon.sitara'),
      ]) {
        expect(
          declinedCode(_buy(poor, kind, id, content: broken)),
          EconomyRefusal.catalogMismatch,
          reason: id,
        );
      }
    });

    test('unknown_sku: priced, but no content names it', () {
      for (final (kind, id) in [
        (SkuKind.item, 'salon.ghost'),
        (SkuKind.vehicle, 'bus_big'),
        (SkuKind.chapter, 'ch9_villa'),
        (SkuKind.booster, 'revive'),
        (SkuKind.fuel, 'refuel_half'),
      ]) {
        expect(
          declinedCode(_buy(poor, kind, id, content: broken)),
          EconomyRefusal.unknownSku,
          reason: id,
        );
      }
    });

    test('unknown_variant: none, an unknown one, or one on a vehicle', () {
      expect(
        declinedCode(_buy(poor, SkuKind.item, 'salon.nish')),
        EconomyRefusal.unknownVariant,
      );
      expect(
        declinedCode(_buy(poor, SkuKind.item, 'salon.nish', variantId: 'gold')),
        EconomyRefusal.unknownVariant,
      );
      expect(
        declinedCode(
          _buy(poor, SkuKind.vehicle, 'micro_old', variantId: 'red'),
        ),
        EconomyRefusal.unknownVariant,
      );
    });

    test('already_owned, before insufficient_funds', () {
      final owner = _rules.apply(
        _rich,
        validatedOp(_buy(_rich, SkuKind.vehicle, 'micro_old')),
      );
      final broke = owner.copyWith(jenehat: 0);
      expect(
        declinedCode(_buy(broke, SkuKind.vehicle, 'micro_old')),
        EconomyRefusal.alreadyOwned,
      );
      // Another variant of an owned item is owned too.
      final withItem = _rules.apply(
        _rich,
        validatedOp(
          _buy(_rich, SkuKind.item, 'salon.nish', variantId: 'classic'),
        ),
      );
      expect(
        declinedCode(
          _buy(withItem, SkuKind.item, 'salon.nish', variantId: 'modern'),
        ),
        EconomyRefusal.alreadyOwned,
      );
    });

    test('insufficient_funds last, one short of the price', () {
      final short = _rich.copyWith(jenehat: 399, bonat: 9);
      expect(
        declinedCode(
          _buy(short, SkuKind.item, 'salon.nish', variantId: 'classic'),
        ),
        EconomyRefusal.insufficientFunds,
      );
      expect(
        declinedCode(_buy(short, SkuKind.booster, 'change_bag')),
        EconomyRefusal.insufficientFunds,
      );
      validatedOp(
        _buy(
          short.copyWith(jenehat: 400),
          SkuKind.item,
          'salon.nish',
          variantId: 'classic',
        ),
      );
    });

    test('a kind\'s own state checks come before insufficient_funds', () {
      expect(
        declinedCode(_buy(poor, SkuKind.fuel, 'refuel_full')),
        EconomyRefusal.tankFull,
      );
      expect(
        declinedCode(_buy(poor, SkuKind.revive, 'revive')),
        EconomyRefusal.noTrip,
      );
      final revived = poor.copyWith(
        unfinished: () => _trip.copyWith(revived: true),
      );
      expect(
        declinedCode(_buy(revived, SkuKind.revive, 'revive')),
        EconomyRefusal.alreadyRevived,
      );
    });
  });

  group('fuel effects', () {
    test('refuel_full is refused on a full or overfull tank', () {
      for (final liters in [5, 6]) {
        final s = _rich.copyWith(
          fuel: FuelState(liters: liters, countedFromMs: testEpochMs),
        );
        expect(
          declinedCode(_buy(s, SkuKind.fuel, 'refuel_full')),
          EconomyRefusal.tankFull,
        );
      }
    });

    test('refuel_full counts regenerated liters first', () {
      // 2 liters, then 40 minutes: 4, so the refill adds 1.
      final op = validatedOp(
        _buy(
          _rich,
          SkuKind.fuel,
          'refuel_full',
          nowMs: testEpochMs + 40 * _minuteMs,
        ),
      );
      expect(op.fuelDelta, 1);
    });

    test('fuel_unlimited_1h extends a running window from its end', () {
      final running = _rich.copyWith(
        fuel: const FuelState(
          liters: 2,
          countedFromMs: testEpochMs,
          unlimitedUntilMs: testEpochMs + 30 * _minuteMs,
        ),
      );
      final op = validatedOp(
        _buy(running, SkuKind.fuelUnlimited, 'fuel_unlimited_1h'),
      );
      expect(
        _rules.apply(running, op).fuel.unlimitedUntilMs,
        testEpochMs + 90 * _minuteMs,
      );
    });
  });

  group('stillValid', () {
    test('false when a balance would go below 0', () {
      final jenehat = validatedOp(
        _buy(_rich, SkuKind.item, 'salon.nish', variantId: 'classic'),
      );
      expect(_rules.stillValid(_rich, jenehat), isTrue);
      expect(_rules.stillValid(_rich.copyWith(jenehat: 399), jenehat), isFalse);
      final bonat = validatedOp(_buy(_rich, SkuKind.booster, 'change_bag'));
      expect(_rules.stillValid(_rich.copyWith(bonat: 9), bonat), isFalse);
    });

    test('false when the SKU is already owned', () {
      final op = validatedOp(_buy(_rich, SkuKind.vehicle, 'micro_old'));
      final owner = _rules.apply(_rich, op);
      expect(_rules.stillValid(owner, op), isFalse);
    });

    test('a revive needs its trip, not yet revived', () {
      final s = _rich.copyWith(unfinished: () => _trip);
      final op = validatedOp(_buy(s, SkuKind.revive, 'revive'));
      expect(_rules.stillValid(s, op), isTrue);
      expect(_rules.stillValid(_rich, op), isFalse);
      expect(_rules.stillValid(_rules.apply(s, op), op), isFalse);
    });

    test('a refill on a full tank stays, and adds nothing', () {
      final op = validatedOp(_buy(_rich, SkuKind.fuel, 'refuel_full'));
      final full = _rich.copyWith(
        fuel: const FuelState(liters: 5, countedFromMs: testEpochMs),
      );
      expect(_rules.stillValid(full, op), isTrue);
      final after = _rules.apply(full, op);
      expect(after.fuel.liters, 5);
      expect(after.bonat, 970);
    });
  });
}
