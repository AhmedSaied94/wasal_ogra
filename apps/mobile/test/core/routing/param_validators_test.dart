import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/routing/param_validators.dart';

// Route parameter rules (contracts/routes.md, glossary §3.6, FR-022).

void main() {
  void check(
    ParamValidator validator, {
    required List<String> valid,
    required List<String> invalid,
  }) {
    for (final v in valid) {
      expect(validator(v), isTrue, reason: '"$v" should pass');
    }
    for (final v in invalid) {
      expect(validator(v), isFalse, reason: '"$v" should fail');
    }
  }

  test('tripId: <known line>.<two digits>', () {
    check(
      ParamValidators.tripId,
      valid: ['line_hay.01', 'line_safar.12', 'line_gamaa.00'],
      invalid: [
        'line_xyz.01',
        'line_hay.1',
        'line_hay.001',
        'hay.01',
        'line_hay01',
        'LINE_HAY.01',
        'line_hay.01/result',
        '',
      ],
    );
  });

  test('lineId: glossary values only', () {
    check(
      ParamValidators.lineId,
      valid: [
        'line_hay',
        'line_gamaa',
        'line_souq',
        'line_masyaf',
        'line_safar',
      ],
      invalid: ['line_xyz', 'hay', 'bad', 'vehicle', ''],
    );
  });

  test('vehicleId: glossary values only', () {
    check(
      ParamValidators.vehicleId,
      valid: ['tuktuk', 'micro_old', 'micro_new', 'micro_safar'],
      invalid: ['micro', 'bus', 'Micro_old', ''],
    );
  });

  test('itemId: <room>.<lowercase id>', () {
    check(
      ParamValidators.itemId,
      valid: ['salon.nish', 'kitchen.fridge_2', 'bedroom.bed'],
      invalid: [
        'garage.car',
        'salon.',
        'salon.Nish',
        'salon-nish',
        'salon.nish.x',
        '',
      ],
    );
  });

  test('chapterId: glossary values only', () {
    check(
      ParamValidators.chapterId,
      valid: ['ch1_first_job', 'ch4_salon', 'ch7_wedding'],
      invalid: ['ch8_honeymoon', 'ch1', 'first_job', ''],
    );
  });
}
