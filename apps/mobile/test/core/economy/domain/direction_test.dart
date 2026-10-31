import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart' show TripOutcome;
import 'package:wassal/core/economy/domain/economy_refusal.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/rules.dart';
import 'package:wassal/core/economy/domain/wire.dart';

import '../../../helpers/economy.dart';

// BONAT never becomes JENEHAT (FR-012, constitution IV; contracts/
// operations.md "The direction rule"): one accepted op of every type and
// placement, each checked.

const _rules = ProductionRules();

const _bonatReasons = {
  LedgerReason.boosterPurchase,
  LedgerReason.fuelPurchase,
  LedgerReason.revivePurchase,
  LedgerReason.fuelUnlimitedPurchase,
};

final _trip = UnfinishedTrip(
  startTxn: txnIdOf(50),
  tripId: 'line_hay.01',
  contentVersion: 1,
  maxEarningsJenehat: 20,
  startedAtMs: testEpochMs,
);

/// Money, boosters, a half tank and a paid result, with no trip running.
final _stocked = EconomyState(
  jenehat: 10000,
  bonat: 1000,
  fuel: const FuelState(liters: 2, countedFromMs: testEpochMs),
  inventory: const {
    BoosterId.changeBag: 1,
    BoosterId.wakeAll: 1,
    BoosterId.ledgerPeek: 1,
    BoosterId.trafficJam: 1,
  },
  lastResult: LastResult(
    startTxn: txnIdOf(40),
    outcome: TripOutcome.finished,
    earningsJenehat: 15,
  ),
);

final _inTrip = _stocked.copyWith(unfinished: () => _trip);

/// Every accepted operation the device can make.
List<Op> _everyOp() {
  var id = 100;
  Op accept(EconomyState s, OpRequest request) =>
      validatedOp(_rules.validate(s, request, ruleContext(id: id++)));

  final unlimited = _stocked.copyWith(
    fuel: const FuelState(
      liters: 0,
      countedFromMs: testEpochMs,
      unlimitedUntilMs: testEpochMs + 60000,
    ),
  );
  return [
    accept(_stocked, const StartTripRequest('line_hay.01')),
    accept(unlimited, const StartTripRequest('line_hay.01')),
    accept(
      _inTrip,
      RecordResultRequest(
        start: _trip.startTxn,
        result: tripResult(tripId: 'line_hay.01', earnings: 20),
      ),
    ),
    for (final placement in [
      AdPlacement.resultDouble,
      AdPlacement.fuelRefill,
      AdPlacement.tripRevive,
      AdPlacement.trafficJam,
    ])
      accept(_inTrip, AdRewardRequest(placement)),
    accept(
      _stocked,
      const BuyRequest(
        kind: SkuKind.item,
        skuId: 'salon.nish',
        variantId: 'crystal',
      ),
    ),
    accept(
      _stocked,
      const BuyRequest(kind: SkuKind.vehicle, skuId: 'micro_old'),
    ),
    accept(
      _stocked,
      const BuyRequest(kind: SkuKind.chapter, skuId: 'ch3_shabka'),
    ),
    for (final booster in inTripBoosters)
      accept(
        _stocked,
        BuyRequest(kind: SkuKind.booster, skuId: boosterWire[booster]!),
      ),
    accept(
      _stocked,
      const BuyRequest(kind: SkuKind.fuel, skuId: 'refuel_full'),
    ),
    accept(
      _stocked,
      const BuyRequest(kind: SkuKind.fuelUnlimited, skuId: 'fuel_unlimited_1h'),
    ),
    accept(_inTrip, const BuyRequest(kind: SkuKind.revive, skuId: 'revive')),
    for (final booster in inTripBoosters)
      accept(_inTrip, UseBoosterRequest(booster)),
    accept(_stocked, const ComebackGiftRequest()),
    // M07: the driver's name and the tutorial gift add neither currency.
    accept(_stocked, const SettingsUpdateRequest('Hamada')),
    accept(_stocked, const TutorialGiftRequest()),
    // M10: a scene seen, and a claim of a piece the player owns.
    accept(
      _stocked,
      const StoryProgressRequest(
        chapterId: ChapterId.ch1FirstJob,
        sceneId: 'the_stand',
      ),
    ),
    accept(
      _stocked.copyWith(
        ownership: {
          (SkuKind.item, 'salon.nish'): Owned(
            kind: SkuKind.item,
            variantId: 'crystal',
            acquiredAtMs: testEpochMs,
          ),
        },
      ),
      const ClaimRequest(requestId: 'req_nish_crystal'),
    ),
  ];
}

void main() {
  final ops = _everyOp();

  test('the ops cover every type and every placement the device grants', () {
    expect({for (final op in ops) op.type}, OpType.values.toSet());
    expect({
      for (final op in ops)
        if (op.type == OpType.adReward)
          byWire(AdPlacement.values, (p) => p.wire, op.payload['ad_placement']),
    }, AdPlacement.values.toSet()..remove(AdPlacement.morningPiggy));
    expect({
      for (final op in ops)
        if (op.type == OpType.spendBonat || op.type == OpType.spendJenehat)
          fromWire(skuKindWire, op.payload['sku_kind']),
    }, SkuKind.values.toSet());
  });

  test('no op adds BONAT', () {
    for (final op in ops) {
      expect(op.bonatDelta, lessThanOrEqualTo(0), reason: '$op');
    }
  });

  test('no op spends BONAT and adds JENEHAT', () {
    for (final op in ops) {
      expect(op.bonatDelta < 0 && op.jenehatDelta > 0, isFalse, reason: '$op');
    }
  });

  test('no BONAT reason comes with a JENEHAT increase', () {
    final bonatOps = [
      for (final op in ops)
        if (_bonatReasons.contains(op.reason)) op,
    ];
    expect(bonatOps, hasLength(7));
    for (final op in bonatOps) {
      expect(op.jenehatDelta, lessThanOrEqualTo(0), reason: '$op');
      expect(op.type, OpType.spendBonat, reason: '$op');
    }
  });

  test('the one placement that grants BONAT is refused on the device', () {
    expect(
      declinedCode(
        _rules.validate(
          _inTrip,
          const AdRewardRequest(AdPlacement.morningPiggy),
          ruleContext(),
        ),
      ),
      EconomyRefusal.serverOnly,
    );
  });

  test('applying any op never raises BONAT', () {
    for (final op in ops) {
      final before = op.type == OpType.tripStart ? _stocked : _inTrip;
      final after = _rules.apply(before, op);
      expect(after.bonat, lessThanOrEqualTo(before.bonat), reason: '$op');
    }
  });
}
