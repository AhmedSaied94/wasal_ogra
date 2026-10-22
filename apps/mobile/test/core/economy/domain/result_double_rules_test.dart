import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart' show TripOutcome;
import 'package:wassal/core/economy/domain/economy_refusal.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/rules.dart';

import '../../../helpers/economy.dart';

// `ad_reward` with `result_double` (contracts/operations.md "ad_reward").

const _rules = ProductionRules();

final _start = txnIdOf(1);

EconomyState _after(
  TripOutcome outcome, {
  int earnings = 15,
  bool doubled = false,
}) => EconomyState(
  jenehat: 40,
  bonat: 0,
  fuel: const FuelState(liters: 4, countedFromMs: testEpochMs),
  lastResult: LastResult(
    startTxn: _start,
    outcome: outcome,
    earningsJenehat: earnings,
    doubled: doubled,
  ),
);

Decision _double(EconomyState s) => _rules.validate(
  s,
  const AdRewardRequest(AdPlacement.resultDouble),
  ruleContext(id: 3),
);

void main() {
  group('refusals', () {
    test('no_result before any result', () {
      final s = EconomyState.newPlayer(fuelMax: 5, nowMs: testEpochMs);
      expect(declinedCode(_double(s)), EconomyRefusal.noResult);
    });

    test('not_doublable: failed, abandoned, or paid nothing', () {
      for (final s in [
        _after(TripOutcome.failed, earnings: 0),
        _after(TripOutcome.abandoned, earnings: 0),
        _after(TripOutcome.finished, earnings: 0),
      ]) {
        expect(declinedCode(_double(s)), EconomyRefusal.notDoublable);
      }
    });

    test('already_doubled', () {
      final s = _after(TripOutcome.finished, doubled: true);
      expect(declinedCode(_double(s)), EconomyRefusal.alreadyDoubled);
    });
  });

  test('it pays the last result again, once', () {
    final s = _after(TripOutcome.finished);
    final op = validatedOp(_double(s));
    expect(op.type, OpType.adReward);
    expect(op.jenehatDelta, 15);
    expect(op.reason, LedgerReason.adResultDouble);
    expect(op.ref, _start);
    expect(
      canonicalJson(op.payload),
      '{"ad_placement":"result_double","ref":"${_start.value}"}',
    );

    final after = _rules.apply(s, op);
    expect(after.jenehat, 55);
    expect(after.lastResult?.doubled, isTrue);
    expect(after.lastResult?.earningsJenehat, 15);
    expect(declinedCode(_double(after)), EconomyRefusal.alreadyDoubled);
  });

  group('stillValid', () {
    final op = validatedOp(_double(_after(TripOutcome.finished)));

    test('holds for the same, undoubled result', () {
      expect(_rules.stillValid(_after(TripOutcome.finished), op), isTrue);
    });

    test('is false when the last result is gone or another', () {
      final none = _after(TripOutcome.finished)
          .copyWith(lastResult: () => null);
      expect(_rules.stillValid(none, op), isFalse);
      final other = _after(TripOutcome.finished).copyWith(
        lastResult: () => LastResult(
          startTxn: txnIdOf(9),
          outcome: TripOutcome.finished,
          earningsJenehat: 15,
        ),
      );
      expect(_rules.stillValid(other, op), isFalse);
    });

    test('is false when already doubled', () {
      expect(
        _rules.stillValid(_after(TripOutcome.finished, doubled: true), op),
        isFalse,
      );
    });
  });
}
