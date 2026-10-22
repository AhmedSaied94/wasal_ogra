import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/economy_refusal.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/rules.dart';

import '../../../helpers/economy.dart';

// `trip_start` (contracts/operations.md), against the sample pack.

const _rules = ProductionRules();
const _minuteMs = 60000;

EconomyState _player({int liters = 5, int? unlimitedUntilMs}) => EconomyState(
  jenehat: 0,
  bonat: 0,
  fuel: FuelState(
    liters: liters,
    countedFromMs: testEpochMs,
    unlimitedUntilMs: unlimitedUntilMs,
  ),
);

Decision _start(EconomyState s, String tripId, {int nowMs = testEpochMs}) =>
    _rules.validate(s, StartTripRequest(tripId), ruleContext(nowMs: nowMs));

final _unfinished = UnfinishedTrip(
  startTxn: txnIdOf(9),
  tripId: 'line_hay.02',
  contentVersion: 1,
  maxEarningsJenehat: 30,
  startedAtMs: testEpochMs,
);

void main() {
  group('refusals, in order', () {
    test('unknown_trip comes first', () {
      final s = _player(liters: 0).copyWith(unfinished: () => _unfinished);
      expect(
        declinedCode(_start(s, 'line_nope.01')),
        EconomyRefusal.unknownTrip,
      );
    });

    test('then trip_unfinished', () {
      final s = _player(liters: 0).copyWith(unfinished: () => _unfinished);
      expect(
        declinedCode(_start(s, 'line_hay.01')),
        EconomyRefusal.tripUnfinished,
      );
    });

    test('then no_fuel: 0 liters and no window', () {
      expect(
        declinedCode(_start(_player(liters: 0), 'line_hay.01')),
        EconomyRefusal.noFuel,
      );
    });

    test('a liter that came back by now is there to spend', () {
      final s = _player(liters: 0);
      expect(
        declinedCode(
          _start(s, 'line_hay.01', nowMs: testEpochMs + 19 * _minuteMs),
        ),
        EconomyRefusal.noFuel,
      );
      final op = validatedOp(
        _start(s, 'line_hay.01', nowMs: testEpochMs + 20 * _minuteMs),
      );
      expect(op.fuelDelta, -1);
    });
  });

  test('in fuel mode: one liter, and the canonical payload', () {
    final op = validatedOp(_start(_player(), 'line_hay.01'));
    expect(op.type, OpType.tripStart);
    expect(op.fuelDelta, -1);
    expect(op.jenehatDelta, 0);
    expect(op.bonatDelta, 0);
    expect(op.reason, isNull);
    expect(op.ref, isNull);
    expect(
      canonicalJson(op.payload),
      '{"content_version":1,"fuel_mode":"fuel","trip_id":"line_hay.01"}',
    );
    expect(op.txnId, txnIdOf(1));
    expect(op.occurredAtMs, testEpochMs);
    expect(op.contentVersion, 1);
    expect(op.fuelMax, 5);
    expect(op.fuelRegenMinutes, 20);

    final after = _rules.apply(_player(), op);
    expect(after.fuel, const FuelState(liters: 4, countedFromMs: testEpochMs));
  });

  test('inside a window: unlimited, and no liter spent', () {
    final s = _player(
      liters: 0,
      unlimitedUntilMs: testEpochMs + 30 * _minuteMs,
    );
    final op = validatedOp(_start(s, 'line_hay.01'));
    expect(op.payload['fuel_mode'], 'unlimited');
    expect(op.fuelDelta, 0);
    expect(_rules.apply(s, op).fuel.liters, 0);
  });

  test('at the end of the window, a liter again', () {
    final s = _player(liters: 2, unlimitedUntilMs: testEpochMs);
    final op = validatedOp(_start(s, 'line_hay.01'));
    expect(op.payload['fuel_mode'], 'fuel');
    expect(op.fuelDelta, -1);
  });

  test("maxEarningsJenehat is the pack's, not the request's", () {
    expect(
      validatedOp(_start(_player(), 'line_hay.01')).maxEarningsJenehat,
      20,
    );
    expect(
      validatedOp(_start(_player(), 'line_gamaa.02')).maxEarningsJenehat,
      60,
    );
  });

  test('the start becomes the unfinished trip', () {
    const now = testEpochMs + 7 * _minuteMs;
    final op = validatedOp(_start(_player(), 'line_gamaa.01', nowMs: now));
    final after = _rules.apply(_player(), op);
    expect(
      after.unfinished,
      UnfinishedTrip(
        startTxn: txnIdOf(1),
        tripId: 'line_gamaa.01',
        contentVersion: 1,
        maxEarningsJenehat: 25,
        startedAtMs: now,
      ),
    );
    expect(after.lastResult, isNull);
  });

  test('a trip already at 3 stars still costs one liter (FR-029)', () {
    final s = _player().copyWith(
      progress: {'line_hay.01': const TripProgress(bestStars: 3, plays: 4)},
    );
    final op = validatedOp(_start(s, 'line_hay.01'));
    expect(op.fuelDelta, -1);
    expect(_rules.apply(s, op).fuel.liters, 4);
  });

  test('apply regenerates to the op time with its tunables first', () {
    final s = _player(liters: 3);
    const now = testEpochMs + 25 * _minuteMs;
    final op = validatedOp(_start(s, 'line_hay.01', nowMs: now));
    // 3 → 4 at +20 min, then the start: 3, still counting from +20 min.
    expect(
      _rules.apply(s, op).fuel,
      const FuelState(liters: 3, countedFromMs: testEpochMs + 20 * _minuteMs),
    );
  });

  test('stillValid is always true, and an empty tank holds at 0', () {
    final op = validatedOp(_start(_player(), 'line_hay.01'));
    final empty = _player(liters: 0).copyWith(unfinished: () => _unfinished);
    expect(_rules.stillValid(empty, op), isTrue);
    expect(_rules.apply(empty, op).fuel.liters, 0);
  });

  test('the content version is the active one', () {
    final op = validatedOp(
      _rules.validate(
        _player(),
        const StartTripRequest('line_hay.01'),
        ruleContext(contentVersion: 4),
      ),
    );
    expect(op.payload['content_version'], 4);
    expect(op.contentVersion, 4);
  });

  test('the payload holds exactly the three fields', () {
    final op = validatedOp(_start(_player(), 'line_hay.01'));
    expect(
      op.payload.keys,
      unorderedEquals(['trip_id', 'content_version', 'fuel_mode']),
    );
  });
}
