import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/economy_refusal.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/fold.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/rules.dart';

import '../../../helpers/economy.dart';

// `ad_reward` with `fuel_refill` (contracts/operations.md "ad_reward").

const _rules = ProductionRules();

EconomyState _player(int liters) => EconomyState(
  jenehat: 0,
  bonat: 0,
  fuel: FuelState(liters: liters, countedFromMs: testEpochMs),
);

Decision _refill(EconomyState s, {int fuelMax = 5}) => _rules.validate(
  s,
  const AdRewardRequest(AdPlacement.fuelRefill),
  ruleContext(fuelMax: fuelMax),
);

void main() {
  test('the payload names the placement, with no ref and no reason', () {
    final op = validatedOp(_refill(_player(1)));
    expect(op.type, OpType.adReward);
    expect(canonicalJson(op.payload), '{"ad_placement":"fuel_refill"}');
    expect(op.ref, isNull);
    expect(op.reason, isNull);
    expect(op.jenehatDelta, 0);
    expect(op.bonatDelta, 0);
  });

  test('it fills to the maximum, counting from now', () {
    for (final liters in [0, 1, 4]) {
      final op = validatedOp(_refill(_player(liters)));
      expect(op.fuelDelta, 5 - liters, reason: '$liters liters');
      expect(
        _rules.apply(_player(liters), op).fuel,
        const FuelState(liters: 5, countedFromMs: testEpochMs),
      );
    }
  });

  test('a full or overfull tank refuses it with tank_full', () {
    expect(declinedCode(_refill(_player(5))), EconomyRefusal.tankFull);
    expect(declinedCode(_refill(_player(6))), EconomyRefusal.tankFull);
    // fuel_max lowered under the tank.
    expect(
      declinedCode(_refill(_player(4), fuelMax: 4)),
      EconomyRefusal.tankFull,
    );
  });

  test('in a fold it stays, and adds nothing to a full tank', () {
    final op = validatedOp(_refill(_player(2)));
    expect(_rules.stillValid(_player(5), op), isTrue);
    final folded = fold(_player(5), [op], _rules);
    expect(folded.leftOut, isEmpty);
    expect(folded.state.fuel.liters, 5);
  });
}
