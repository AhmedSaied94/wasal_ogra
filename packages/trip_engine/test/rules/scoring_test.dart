// The result (rules.md §11): stars, earnings, duration, reputation and the
// fingerprint.
import 'package:test/test.dart';
import 'package:trip_engine/src/model/counters.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/builders.dart';
import '../support/edits.dart';
import '../support/scripts.dart';

/// One station at 1 s and a passenger who never pays: no fares, no fights,
/// no mistakes unless a test adds them.
TripEngine _trip({int maxEarnings = 100}) => startTrip(
  (TripBuilder()
        ..maxEarnings(maxEarnings)
        ..station('kobri', 1)
        ..passenger('p1', seat: 'A_r', dest: 'kobri', payment: [1000]))
      .build(),
);

TripResult _finish(TripEngine engine) {
  engine.stepToSeconds(2);
  expect(engine.status, TripStatus.finished);
  return engine.result!;
}

void main() {
  group('stars', () {
    test('3 with no fights and no mistakes', () {
      final result = _finish(_trip());
      expect(result.stars, 3);
      expect(result.starFlags.toJson(), {
        'reached': true,
        'no_fights': true,
        'no_mistakes': true,
      });
    });

    test('2 with a mistake and no fights', () {
      final engine = _trip();
      addMistake(
        engine,
        const Mistake(
          passengerId: 'p1',
          kind: MistakeKind.over,
          amountPiasters: 50,
        ),
      );
      final result = _finish(engine);
      expect(result.stars, 2);
      expect(result.starFlags.noMistakes, isFalse);
      expect(result.mistakes.single.amountPiasters, 50);
    });

    test('1 with a fight, mistakes or not', () {
      final engine = _trip();
      editCounters(engine, (c) => c.copyWith(fights: 1));
      expect(_finish(engine).stars, 1);
      final both = _trip();
      editCounters(both, (c) => c.copyWith(fights: 1));
      addMistake(
        both,
        const Mistake(
          passengerId: 'p1',
          kind: MistakeKind.unreturned,
          amountPiasters: 50,
        ),
      );
      final result = _finish(both);
      expect(result.stars, 1);
      expect(result.starFlags.toJson(), {
        'reached': true,
        'no_fights': false,
        'no_mistakes': false,
      });
    });
  });

  group('earnings', () {
    test('whole pounds, rounded down: 2549 piasters is 25 JENEHAT', () {
      final engine = _trip();
      editCounters(engine, (c) => c.copyWith(tipsPiasters: 2549));
      expect(_finish(engine).earningsJenehat, 25);
    });

    test('fares minus overpaid plus tips, never below 0', () {
      final engine = _trip();
      editCounters(
        engine,
        (c) => c.copyWith(overpaidPiasters: 500, tipsPiasters: 200),
      );
      final result = _finish(engine);
      expect(result.earningsJenehat, 0);
      expect(result.overpaidPiasters, 500);
      expect(result.tipsPiasters, 200);
    });

    test('capped at max_earnings_jenehat', () {
      final engine = _trip(maxEarnings: 10);
      editCounters(engine, (c) => c.copyWith(tipsPiasters: 5000));
      expect(_finish(engine).earningsJenehat, 10);
    });
  });

  test('duration, reputation and counters', () {
    final engine = _trip();
    setReputation(engine, 77);
    final result = _finish(engine);
    expect(result.durationMs, 1023);
    expect(result.reputation, 77);
    expect(result.lostFares, 1);
    expect(result.outcome, TripOutcome.finished);
    expect(result.tripId, 'line_gamaa.01');
    expect(result.rev, 1);
    expect(result.revived, isFalse);
    expect(result.boostersUsed, isEmpty);
  });

  test('the fingerprint is the command log hash', () {
    final engine = _trip()
      ..ok(const PickFromTray(100))
      ..ok(const ReturnHand());
    final result = _finish(engine);
    expect(result.commandLogHash, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(result.commandLogHash, commandLogHash(engine.commandLog));
  });
}
