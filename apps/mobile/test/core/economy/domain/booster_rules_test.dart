import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/economy_refusal.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/rules.dart';

import '../../../helpers/economy.dart';

// `use_booster` (contracts/operations.md).

const _rules = ProductionRules();

final _trip = UnfinishedTrip(
  startTxn: txnIdOf(50),
  tripId: 'line_hay.01',
  contentVersion: 1,
  maxEarningsJenehat: 20,
  startedAtMs: testEpochMs,
);

EconomyState _holding(Map<BoosterId, int> inventory, {bool inTrip = true}) =>
    EconomyState(
      jenehat: 0,
      bonat: 0,
      fuel: const FuelState(liters: 4, countedFromMs: testEpochMs),
      inventory: inventory,
      unfinished: inTrip ? _trip : null,
    );

Decision _use(EconomyState s, BoosterId booster) =>
    _rules.validate(s, UseBoosterRequest(booster), ruleContext(id: 8));

void main() {
  group('refusals, in order', () {
    test('no_trip first', () {
      expect(
        declinedCode(_use(_holding({}, inTrip: false), BoosterId.revive)),
        EconomyRefusal.noTrip,
      );
    });

    test('then unknown_sku for a booster no trip uses', () {
      for (final booster in [BoosterId.revive, BoosterId.refuelFull]) {
        expect(
          declinedCode(_use(_holding({}), booster)),
          EconomyRefusal.unknownSku,
        );
      }
    });

    test('then none_left', () {
      expect(
        declinedCode(
          _use(_holding({BoosterId.wakeAll: 1}), BoosterId.changeBag),
        ),
        EconomyRefusal.noneLeft,
      );
    });
  });

  test('it takes one from the inventory, and names the trip', () {
    final s = _holding({BoosterId.changeBag: 2});
    final op = validatedOp(_use(s, BoosterId.changeBag));
    expect(op.type, OpType.useBooster);
    expect(
      canonicalJson(op.payload),
      '{"booster_id":"change_bag","ref":"${_trip.startTxn.value}"}',
    );
    expect(op.ref, _trip.startTxn);
    expect(op.jenehatDelta, 0);
    expect(op.bonatDelta, 0);
    expect(op.reason, isNull);

    final once = _rules.apply(s, op);
    expect(once.inventory, {BoosterId.changeBag: 1});
    expect(_rules.apply(once, op).inventory, isEmpty);
  });

  test('stillValid is false at 0 left', () {
    final op = validatedOp(
      _use(_holding({BoosterId.ledgerPeek: 1}), BoosterId.ledgerPeek),
    );
    expect(_rules.stillValid(_holding({BoosterId.ledgerPeek: 1}), op), isTrue);
    expect(_rules.stillValid(_holding({}), op), isFalse);
  });
}
