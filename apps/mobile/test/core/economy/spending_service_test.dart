import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/fuel.dart';
import 'package:wassal/core/economy/economy.dart';

import '../../helpers/economy.dart';

// US3 through the real service over SQLite (spec.md User Story 3).

const _minuteMs = 60000;

EconomyState Function(int) _with({int jenehat = 0, int bonat = 0}) =>
    (nowMs) => EconomyState.newPlayer(
      fuelMax: 5,
      nowMs: nowMs,
    ).copyWith(jenehat: jenehat, bonat: bonat);

Future<OpOutcome> _buy(
  TestEconomy e,
  SkuKind kind,
  String skuId, {
  String? variantId,
}) => e.service.buy(
  e.service.newRequestId(),
  kind: kind,
  skuId: skuId,
  variantId: variantId,
);

Future<TxnId> _start(TestEconomy e) async {
  final id = e.service.newRequestId();
  expect(
    await e.service.startTrip(id, tripId: 'line_hay.01'),
    isA<OpApplied>(),
  );
  return id;
}

EconomyRefusal _code(OpOutcome outcome) => (outcome as OpRefused).code;

Future<int> _rows(TestEconomy e) async =>
    (await dumpTables(e.db))['ledger_ops']!.length;

void main() {
  test(
    '1. the catalog price, in its currency, recorded with the version',
    () async {
      var e = await testEconomy(
        dbFile: tempDbFile(),
        firstState: _with(jenehat: 2000, bonat: 100),
        contentVersion: 1,
      );
      final vehicle = await _buy(e, SkuKind.vehicle, 'micro_old') as OpApplied;
      expect(vehicle.op.op.payload['price'], 1500);
      expect(vehicle.op.op.contentVersion, 1);
      expect(vehicle.view.jenehat, 500);
      expect(vehicle.view.bonat, 100);

      final booster =
          await _buy(e, SkuKind.booster, 'ledger_peek') as OpApplied;
      expect(booster.op.op.payload['price'], 12);
      expect(booster.view.bonat, 88);
      expect(booster.view.jenehat, 500);

      e = await reopen(e);
      expect(e.service.view.jenehat, 500);
      expect(e.service.view.bonat, 88);
      expect(e.service.view.owns(SkuKind.vehicle, 'micro_old'), isTrue);
    },
  );

  test('2. a product without a catalog price is not for sale', () async {
    final e = await testEconomy(firstState: _with(jenehat: 5000));
    expect(
      _code(await _buy(e, SkuKind.vehicle, 'tuktuk')),
      EconomyRefusal.notForSale,
    );
    expect(await _rows(e), 0);
  });

  test(
    '3. a balance below the price refuses, and nothing goes below 0',
    () async {
      final e = await testEconomy(firstState: _with(jenehat: 899, bonat: 7));
      expect(
        _code(await _buy(e, SkuKind.chapter, 'ch3_shabka')),
        EconomyRefusal.insufficientFunds,
      );
      expect(
        _code(await _buy(e, SkuKind.booster, 'wake_all')),
        EconomyRefusal.insufficientFunds,
      );
      expect(e.service.view.jenehat, 899);
      expect(e.service.view.bonat, 7);
      expect(await _rows(e), 0);
    },
  );

  test('4. something owned cannot be bought again', () async {
    final e = await testEconomy(firstState: _with(jenehat: 5000));
    for (final (kind, id, variant) in [
      (SkuKind.item, 'salon.sitara', 'plain'),
      (SkuKind.vehicle, 'micro_old', null),
      (SkuKind.chapter, 'ch3_shabka', null),
    ]) {
      expect(await _buy(e, kind, id, variantId: variant), isA<OpApplied>());
      expect(
        _code(await _buy(e, kind, id, variantId: variant)),
        EconomyRefusal.alreadyOwned,
        reason: id,
      );
    }
    expect(e.service.view.jenehat, 5000 - 150 - 1500 - 900);
  });

  test('5. the chosen style is recorded, at the one price', () async {
    final e = await testEconomy(firstState: _with(jenehat: 400));
    final bought = await _buy(
      e,
      SkuKind.item,
      'salon.nish',
      variantId: 'crystal',
    ) as OpApplied;
    expect(bought.op.op.payload['price'], 400);
    expect(e.service.view.variantOf('salon.nish'), 'crystal');
    expect(e.service.view.owns(SkuKind.item, 'salon.nish'), isTrue);
    expect(e.service.view.jenehat, 0);
  });

  test('6. a booster bought adds one; used in a trip takes one', () async {
    final e = await testEconomy(firstState: _with(bonat: 30));
    await _buy(e, SkuKind.booster, 'traffic_jam');
    expect(e.service.view.inventory[BoosterId.trafficJam], 1);

    expect(
      _code(
        await e.service.useBooster(
          e.service.newRequestId(),
          booster: BoosterId.trafficJam,
        ),
      ),
      EconomyRefusal.noTrip,
    );
    await _start(e);
    final used = await e.service.useBooster(
      e.service.newRequestId(),
      booster: BoosterId.trafficJam,
    );
    expect(used, isA<OpApplied>());
    expect(e.service.view.inventory[BoosterId.trafficJam], isNull);
    expect(
      _code(
        await e.service.useBooster(
          e.service.newRequestId(),
          booster: BoosterId.trafficJam,
        ),
      ),
      EconomyRefusal.noneLeft,
    );
  });

  group('7. fuel purchases', () {
    test(
      'a full refill on a full tank is refused, so nothing is spent',
      () async {
        final e = await testEconomy(firstState: _with(bonat: 100));
        expect(
          _code(await _buy(e, SkuKind.fuel, 'refuel_full')),
          EconomyRefusal.tankFull,
        );
        expect(e.service.view.bonat, 100);
      },
    );

    test(
      'another unlimited window extends the running one by 60 min',
      () async {
        final e = await testEconomy(firstState: _with(bonat: 200));
        await _buy(e, SkuKind.fuelUnlimited, 'fuel_unlimited_1h');
        e.passTime(minute * 25);
        await _buy(e, SkuKind.fuelUnlimited, 'fuel_unlimited_1h');
        expect(
          e.service.view.fuel.unlimitedUntilMs,
          testEpochMs + 2 * unlimitedWindowMs,
        );
        expect(e.service.view.bonat, 40);
        e.passTime(minute * 95);
        expect(e.service.view.fuel.unlimitedUntilMs, isNull);
        expect(e.clock.nowMs(), testEpochMs + 120 * _minuteMs);
      },
    );
  });

  test(
    '8. the same request twice charges once, with the same outcome',
    () async {
      final e = await testEconomy(firstState: _with(bonat: 100));
      final id = e.service.newRequestId();
      final [first, second] = await Future.wait([
        e.service.buy(
          id,
          kind: SkuKind.fuelUnlimited,
          skuId: 'fuel_unlimited_1h',
        ),
        e.service.buy(
          id,
          kind: SkuKind.fuelUnlimited,
          skuId: 'fuel_unlimited_1h',
        ),
      ]);
      expect((first as OpApplied).op.seq, (second as OpApplied).op.seq);
      expect(second.repeated, isTrue);
      expect(e.service.view.bonat, 20);
      expect(await _rows(e), 1);
    },
  );

  test('9. no request made on the device raises BONAT', () async {
    final e = await testEconomy(firstState: _with(jenehat: 3000, bonat: 200));
    var bonat = e.service.view.bonat;
    void noRise() {
      expect(e.service.view.bonat, lessThanOrEqualTo(bonat));
      bonat = e.service.view.bonat;
    }

    final start = await _start(e);
    noRise();
    for (final placement in AdPlacement.values) {
      await e.service.applyAdReward(
        e.service.newRequestId(),
        placement: placement,
      );
      noRise();
    }
    await _buy(e, SkuKind.revive, 'revive');
    noRise();
    await e.service.recordResult(
      e.service.newRequestId(),
      start: start,
      result: tripResult(tripId: 'line_hay.01'),
    );
    noRise();
    await e.service.applyAdReward(
      e.service.newRequestId(),
      placement: AdPlacement.resultDouble,
    );
    noRise();
    for (final (kind, id) in [
      (SkuKind.booster, 'change_bag'),
      (SkuKind.vehicle, 'micro_old'),
      (SkuKind.chapter, 'ch3_shabka'),
    ]) {
      await _buy(e, kind, id);
      noRise();
    }
    expect(bonat, lessThan(200));
  });
}
