import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/rules.dart';
import 'package:wassal/core/economy/drift_economy_store.dart';
import 'package:wassal/core/economy/economy.dart';

import '../../helpers/economy.dart';

// A kill at every point of every kind of commit (SC-002, research R11):
// once reopened, the file is exactly as before the operation, or, after the
// commit, exactly as after it. The reopen also runs the debug fold check.

typedef _Request = Future<OpOutcome> Function(TestEconomy e, TxnId id);

final class _Case {
  const _Case(this.name, this.prepare);

  final String name;

  /// Brings a stocked economy to where the request applies, and returns it.
  final Future<_Request> Function(TestEconomy e) prepare;
}

final class _Kill implements Exception {
  const _Kill();
}

EconomyState _stocked(int nowMs) => EconomyState.newPlayer(
  fuelMax: 5,
  nowMs: nowMs,
).copyWith(jenehat: 5000, bonat: 500);

Future<TxnId> _start(TestEconomy e) async {
  final id = e.service.newRequestId();
  expect(
    await e.service.startTrip(id, tripId: 'line_hay.01'),
    isA<OpApplied>(),
  );
  return id;
}

Future<void> _play(TestEconomy e) async {
  final start = await _start(e);
  expect(
    await e.service.recordResult(
      e.service.newRequestId(),
      start: start,
      result: tripResult(tripId: 'line_hay.01'),
    ),
    isA<OpApplied>(),
  );
}

_Request _buy(SkuKind kind, String skuId, [String? variantId]) =>
    (e, id) =>
        e.service.buy(id, kind: kind, skuId: skuId, variantId: variantId);

_Request _ad(AdPlacement placement) =>
    (e, id) => e.service.applyAdReward(id, placement: placement);

_Request _startTrip(String tripId) =>
    (e, id) => e.service.startTrip(id, tripId: tripId);

_Request _result(TxnId start) =>
    (e, id) => e.service.recordResult(
      id,
      start: start,
      result: tripResult(tripId: 'line_hay.01', earnings: 18),
    );

_Request _use(BoosterId booster) =>
    (e, id) => e.service.useBooster(id, booster: booster);

final _cases = [
  _Case('trip_start, fuel mode', (e) async => _startTrip('line_hay.01')),
  _Case('trip_start, unlimited mode', (e) async {
    await _buy(SkuKind.fuelUnlimited, 'fuel_unlimited_1h')(
      e,
      e.service.newRequestId(),
    );
    return _startTrip('line_gamaa.02');
  }),
  _Case('trip_result', (e) async {
    return _result(await _start(e));
  }),
  _Case('ad_reward result_double', (e) async {
    await _play(e);
    return _ad(AdPlacement.resultDouble);
  }),
  _Case('ad_reward fuel_refill', (e) async {
    await _play(e);
    return _ad(AdPlacement.fuelRefill);
  }),
  _Case('ad_reward trip_revive', (e) async {
    await _start(e);
    return _ad(AdPlacement.tripRevive);
  }),
  _Case('ad_reward traffic_jam', (e) async {
    await _start(e);
    return _ad(AdPlacement.trafficJam);
  }),
  _Case('spend_jenehat item', (e) async {
    return _buy(SkuKind.item, 'salon.nish', 'modern');
  }),
  _Case('spend_jenehat vehicle', (e) async {
    return _buy(SkuKind.vehicle, 'micro_old');
  }),
  _Case('spend_jenehat chapter', (e) async {
    return _buy(SkuKind.chapter, 'ch3_shabka');
  }),
  _Case('spend_bonat booster', (e) async {
    // An update of an inventory row, not only an insert.
    await _buy(SkuKind.booster, 'change_bag')(e, e.service.newRequestId());
    return _buy(SkuKind.booster, 'change_bag');
  }),
  _Case('spend_bonat fuel', (e) async {
    await _play(e);
    return _buy(SkuKind.fuel, 'refuel_full');
  }),
  _Case('spend_bonat fuel_unlimited', (e) async {
    return _buy(SkuKind.fuelUnlimited, 'fuel_unlimited_1h');
  }),
  _Case('spend_bonat revive', (e) async {
    await _start(e);
    return _buy(SkuKind.revive, 'revive');
  }),
  _Case('use_booster', (e) async {
    await _buy(SkuKind.booster, 'wake_all')(e, e.service.newRequestId());
    await _start(e);
    return _use(BoosterId.wakeAll);
  }),
];

void main() {
  for (final c in _cases) {
    group(c.name, () {
      for (final point in EconomyKillPoint.values) {
        final committed = point == EconomyKillPoint.afterCommit;

        test('a kill at ${point.name}', () async {
          var armed = false;
          final e = await testEconomy(
            dbFile: tempDbFile(),
            firstState: _stocked,
            onKillPoint: (p) {
              if (armed && p == point) throw const _Kill();
            },
          );
          final request = await c.prepare(e);
          e.passTime(minute * 3);
          final before = await dumpTables(e.db);
          final stateBefore = e.service.state;
          final id = e.service.newRequestId();

          armed = true;
          await expectLater(request(e, id), throwsA(isA<_Kill>()));

          final reopened = await reopen(e);
          final stored = await reopened.store.findOp(id);
          if (committed) {
            expect(stored, isNotNull);
            expect(
              reopened.service.state,
              const ProductionRules().apply(stateBefore, stored!.op),
            );
            // A retry after the relaunch finds it stored.
            final retry = await request(reopened, id) as OpApplied;
            expect(retry.repeated, isTrue);
          } else {
            expect(stored, isNull);
            expect(await dumpTables(reopened.db), before);
            expect(reopened.service.state, stateBefore);
            // A retry after the relaunch applies.
            final retry = await request(reopened, id) as OpApplied;
            expect(retry.repeated, isFalse);
          }
        });
      }
    });
  }
}
