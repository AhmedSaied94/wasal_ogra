import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/economy_refusal.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/fold.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/rules.dart';

import '../../../helpers/economy.dart';

// The gifts the device applies: M06's `comeback_gift` and M07's
// `tutorial_gift` (specs/012-m07-onboarding/contracts/fuel-lesson.md "The
// operation", research R8, R9). Neither adds BONAT.

const _rules = ProductionRules();

EconomyState _tank(int liters, {bool granted = false}) => EconomyState(
  jenehat: 40,
  bonat: 3,
  fuel: FuelState(liters: liters, countedFromMs: testEpochMs),
  tutorialGranted: granted,
);

Decision _gift(EconomyState s, {int nowMs = testEpochMs}) => _rules.validate(
  s,
  const TutorialGiftRequest(),
  ruleContext(id: 12, nowMs: nowMs),
);

void main() {
  group('tutorial_gift', () {
    test('validate refuses already_granted once granted', () {
      expect(
        declinedCode(_gift(_tank(1, granted: true))),
        EconomyRefusal.alreadyGranted,
      );
      expect(EconomyRefusal.alreadyGranted.wire, 'already_granted');
    });

    test('an empty payload and the fuel it adds, nothing else', () {
      final op = validatedOp(_gift(_tank(1)));
      expect(op.type, OpType.tutorialGift);
      expect(op.type.wire, 'tutorial_gift');
      expect(op.payload, isEmpty);
      expect(op.fuelDelta, 4);
      expect(op.jenehatDelta, 0);
      expect(op.bonatDelta, 0);
      expect(op.reason, isNull);
    });

    test('apply fills the tank to fuel_max and sets the grant', () {
      final op = validatedOp(_gift(_tank(1)));
      final after = _rules.apply(_tank(1), op);
      expect(after.fuel.liters, 5);
      expect(after.fuel.countedFromMs, testEpochMs);
      expect(after.tutorialGranted, isTrue);
      expect(after.jenehat, 40);
      expect(after.bonat, 3);
      expect(after.inventory, isEmpty);
    });

    test('a full tank gives a zero delta and still sets the grant', () {
      final op = validatedOp(_gift(_tank(5)));
      expect(op.fuelDelta, 0);
      final after = _rules.apply(_tank(5), op);
      expect(after.fuel.liters, 5);
      expect(after.tutorialGranted, isTrue);
    });

    test('is no longer valid once the base is granted', () {
      final op = validatedOp(_gift(_tank(1)));
      expect(_rules.stillValid(_tank(1), op), isTrue);
      expect(_rules.stillValid(_tank(1, granted: true), op), isFalse);
      final folded = fold(_tank(2, granted: true), [op], _rules);
      expect(folded.leftOut, [op.txnId]);
      expect(folded.state.fuel.liters, 2);
    });

    test('a repeated id matches the gift only', () {
      final op = validatedOp(_gift(_tank(1)));
      expect(requestMatches(op, const TutorialGiftRequest()), isTrue);
      expect(requestMatches(op, const ComebackGiftRequest()), isFalse);
    });
  });

  group('comeback_gift', () {
    test('fills the tank and adds one change_bag, never BONAT', () {
      final op = validatedOp(
        _rules.validate(
          _tank(2),
          const ComebackGiftRequest(),
          ruleContext(id: 13),
        ),
      );
      expect(op.fuelDelta, 3);
      expect(op.bonatDelta, 0);
      final after = _rules.apply(_tank(2), op);
      expect(after.fuel.liters, 5);
      expect(after.inventory, {BoosterId.changeBag: 1});
      expect(after.tutorialGranted, isFalse);
    });
  });
}
