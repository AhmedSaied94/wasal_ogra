import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart' show TripOutcome, TripResult;
import 'package:wassal/core/economy/domain/economy_refusal.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/rules.dart';
import 'package:wassal/core/economy/domain/txn_id.dart';

import '../../../helpers/economy.dart';

// `trip_result` (contracts/operations.md), against the sample pack, where
// line_hay.01 pays at most 20 JENEHAT.

const _rules = ProductionRules();
const _minuteMs = 60000;

final _start = txnIdOf(1);

/// A player with line_hay.01 started by [_start].
EconomyState _running({TxnId? start, LastResult? last}) => EconomyState(
  jenehat: 100,
  bonat: 0,
  fuel: const FuelState(liters: 50, countedFromMs: testEpochMs),
  unfinished: UnfinishedTrip(
    startTxn: start ?? _start,
    tripId: 'line_hay.01',
    contentVersion: 1,
    maxEarningsJenehat: 20,
    startedAtMs: testEpochMs,
  ),
  lastResult: last,
);

Decision _record(EconomyState s, TripResult result, {TxnId? start}) =>
    _rules.validate(
      s,
      RecordResultRequest(start: start ?? _start, result: result),
      ruleContext(id: 2),
    );

/// A start and a result at [minutes] past the epoch.
EconomyState _play(EconomyState s, TripResult result, int minutes) {
  final now = testEpochMs + minutes * _minuteMs;
  final start = validatedOp(
    _rules.validate(
      s,
      StartTripRequest(result.tripId),
      ruleContext(nowMs: now, id: 1000 + 2 * minutes),
    ),
  );
  final started = _rules.apply(s, start);
  final op = validatedOp(
    _rules.validate(
      started,
      RecordResultRequest(start: start.txnId, result: result),
      ruleContext(nowMs: now, id: 1001 + 2 * minutes),
    ),
  );
  return _rules.apply(started, op);
}

TripResult _hay({
  TripOutcome outcome = TripOutcome.finished,
  int stars = 3,
  int earnings = 15,
  int durationMs = 90000,
}) => tripResult(
  tripId: 'line_hay.01',
  outcome: outcome,
  stars: stars,
  earnings: earnings,
  durationMs: durationMs,
);

void main() {
  group('refusals, in order', () {
    test('result_exists: the latest result already belongs to this start', () {
      final s = _running(
        start: txnIdOf(5),
        last: LastResult(
          startTxn: _start,
          outcome: TripOutcome.finished,
          earningsJenehat: 15,
        ),
      );
      expect(declinedCode(_record(s, _hay())), EconomyRefusal.resultExists);
      // With no trip running at all, too.
      expect(
        declinedCode(_record(s.copyWith(unfinished: () => null), _hay())),
        EconomyRefusal.resultExists,
      );
    });

    test('no_trip_start: no unfinished trip, or another start', () {
      final none = _running().copyWith(unfinished: () => null);
      expect(declinedCode(_record(none, _hay())), EconomyRefusal.noTripStart);
      expect(
        declinedCode(_record(_running(), _hay(), start: txnIdOf(7))),
        EconomyRefusal.noTripStart,
      );
    });

    test('trip_mismatch: a result for another trip', () {
      expect(
        declinedCode(_record(_running(), tripResult(tripId: 'line_hay.02'))),
        EconomyRefusal.tripMismatch,
      );
    });

    test('stars_out_of_bounds: −1, 4, and any star on a failed trip', () {
      for (final result in [
        _hay(stars: -1),
        _hay(stars: 4),
        _hay(outcome: TripOutcome.failed, stars: 1, earnings: 0),
        // Checked before earnings.
        _hay(stars: 4, earnings: 99),
      ]) {
        expect(
          declinedCode(_record(_running(), result)),
          EconomyRefusal.starsOutOfBounds,
        );
      }
    });

    test(
      'earnings_out_of_bounds: −1, the max + 1, any on an abandoned trip',
      () {
        for (final result in [
          _hay(earnings: -1),
          _hay(earnings: 21),
          _hay(outcome: TripOutcome.abandoned, stars: 0, earnings: 5),
        ]) {
          expect(
            declinedCode(_record(_running(), result)),
            EconomyRefusal.earningsOutOfBounds,
          );
        }
      },
    );

    test('the bounds are the start\'s, inclusive', () {
      validatedOp(_record(_running(), _hay(earnings: 20)));
      validatedOp(_record(_running(), _hay(earnings: 0, stars: 0)));
      validatedOp(
        _record(
          _running(),
          _hay(outcome: TripOutcome.failed, stars: 0, earnings: 0),
        ),
      );
    });
  });

  test('the payload holds the start and the whole result', () {
    final result = _hay();
    final op = validatedOp(_record(_running(), result));
    expect(op.type, OpType.tripResult);
    expect(
      canonicalJson(op.payload),
      '{"result":${canonicalJson(result.toJson())},'
      '"trip_start_txn":"${_start.value}"}',
    );
    expect(op.reason, LedgerReason.tripEarnings);
    expect(op.ref, _start);
    expect(op.jenehatDelta, 15);
    expect(op.bonatDelta, 0);
    expect(op.fuelDelta, 0);
  });

  test('apply adds the earnings, clears the trip and sets the last result', () {
    final op = validatedOp(_record(_running(), _hay(earnings: 12)));
    final after = _rules.apply(_running(), op);
    expect(after.jenehat, 112);
    expect(after.unfinished, isNull);
    expect(
      after.lastResult,
      LastResult(
        startTxn: _start,
        outcome: TripOutcome.finished,
        earningsJenehat: 12,
      ),
    );
    expect(after.fuel, _running().fuel);
  });

  group('progress', () {
    final player = EconomyState(
      jenehat: 0,
      bonat: 0,
      fuel: const FuelState(liters: 50, countedFromMs: testEpochMs),
    );

    test('best stars only rise; best time is the fastest finished run', () {
      var s = _play(player, _hay(stars: 2, durationMs: 90000), 0);
      expect(
        s.progress['line_hay.01'],
        const TripProgress(
          bestStars: 2,
          bestTimeMs: 90000,
          plays: 1,
          firstCompletedAtMs: testEpochMs,
        ),
      );

      // A failed run, shorter: counts as a play only.
      s = _play(
        s,
        _hay(
          outcome: TripOutcome.failed,
          stars: 0,
          earnings: 0,
          durationMs: 30000,
        ),
        5,
      );
      expect(
        s.progress['line_hay.01'],
        const TripProgress(
          bestStars: 2,
          bestTimeMs: 90000,
          plays: 2,
          firstCompletedAtMs: testEpochMs,
        ),
      );

      // Fewer stars, faster.
      s = _play(s, _hay(stars: 1, durationMs: 80000), 10);
      expect(s.progress['line_hay.01']?.bestStars, 2);
      expect(s.progress['line_hay.01']?.bestTimeMs, 80000);

      // More stars, slower.
      s = _play(s, _hay(stars: 3, durationMs: 100000), 15);
      expect(
        s.progress['line_hay.01'],
        const TripProgress(
          bestStars: 3,
          bestTimeMs: 80000,
          plays: 4,
          firstCompletedAtMs: testEpochMs,
        ),
      );
      expect(s.jenehat, 45);
    });

    test('the first completion is set once, by the first finished run', () {
      var s = _play(
        player,
        _hay(outcome: TripOutcome.abandoned, stars: 0, earnings: 0),
        0,
      );
      expect(
        s.progress['line_hay.01'],
        const TripProgress(bestStars: 0, plays: 1),
      );
      s = _play(s, _hay(), 7);
      expect(
        s.progress['line_hay.01']?.firstCompletedAtMs,
        testEpochMs + 7 * _minuteMs,
      );
      s = _play(s, _hay(), 9);
      expect(
        s.progress['line_hay.01']?.firstCompletedAtMs,
        testEpochMs + 7 * _minuteMs,
      );
    });

    test('each trip keeps its own progress', () {
      var s = _play(player, _hay(), 0);
      s = _play(s, tripResult(tripId: 'line_hay.02', stars: 1), 1);
      expect(s.progress.keys, unorderedEquals(['line_hay.01', 'line_hay.02']));
      expect(s.progress['line_hay.02']?.bestStars, 1);
    });
  });

  group('stillValid', () {
    final op = validatedOp(_record(_running(), _hay()));

    test('holds while its start is the unfinished trip', () {
      expect(_rules.stillValid(_running(), op), isTrue);
    });

    test('is false with no matching unfinished start', () {
      expect(
        _rules.stillValid(_running().copyWith(unfinished: () => null), op),
        isFalse,
      );
      expect(_rules.stillValid(_running(start: txnIdOf(8)), op), isFalse);
    });

    test('is false when the start already has its result', () {
      final done = _rules.apply(_running(), op);
      expect(_rules.stillValid(done, op), isFalse);
    });
  });
}
