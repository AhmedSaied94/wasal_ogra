import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/economy_refusal.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/fold.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/rules.dart';

import '../../../helpers/economy.dart';

// `settings_update` (specs/012-m07-onboarding/contracts/name.md "The
// operation", research R8): the driver's name, checked by the phone's name
// rules, with no currency or fuel effect.

const _rules = ProductionRules();

final _player = EconomyState.newPlayer(fuelMax: 5, nowMs: testEpochMs);

Decision _name(String name, {EconomyState? state}) => _rules.validate(
  state ?? _player,
  SettingsUpdateRequest(name),
  ruleContext(id: 9),
);

void main() {
  group('validate', () {
    test('refuses invalid_name for every name the rules refuse', () {
      for (final bad in [
        '',
        '   ',
        'H',
        '123',
        '١٢٣',
        'Ha\u200Fmada',
        'a' * 17,
      ]) {
        expect(
          declinedCode(_name(bad)),
          EconomyRefusal.invalidName,
          reason: bad,
        );
      }
      expect(EconomyRefusal.invalidName.wire, 'invalid_name');
    });

    test('stores the normalized name as the payload, and nothing else', () {
      final op = validatedOp(_name('  Hamada   El  Usta '));
      expect(op.type, OpType.settingsUpdate);
      expect(op.type.wire, 'settings_update');
      expect(op.payload, {'display_name': 'Hamada El Usta'});
      expect(op.jenehatDelta, 0);
      expect(op.bonatDelta, 0);
      expect(op.fuelDelta, 0);
      expect(op.reason, isNull);
      expect(op.ref, isNull);
    });
  });

  group('apply', () {
    test('sets the name, and only the name', () {
      final op = validatedOp(_name('Hamada'));
      final after = _rules.apply(_player, op);
      expect(after.displayName, 'Hamada');
      expect(after.copyWith(displayName: () => null), _player);
    });

    test('a later name replaces an earlier one', () {
      final first = _rules.apply(_player, validatedOp(_name('Hamada')));
      final second = _rules.apply(first, validatedOp(_name('Sayed')));
      expect(second.displayName, 'Sayed');
    });
  });

  test('is still valid in any fold', () {
    final op = validatedOp(_name('Hamada'));
    expect(_rules.stillValid(_player, op), isTrue);
    expect(
      _rules.stillValid(_player.copyWith(displayName: () => 'Other'), op),
      isTrue,
    );
    expect(fold(_player, [op], _rules).state.displayName, 'Hamada');
  });

  test('a repeated id matches the same name only', () {
    final op = validatedOp(_name('Hamada'));
    expect(requestMatches(op, const SettingsUpdateRequest('Hamada')), isTrue);
    expect(requestMatches(op, const SettingsUpdateRequest('Sayed')), isFalse);
    expect(requestMatches(op, const TutorialGiftRequest()), isFalse);
  });
}
