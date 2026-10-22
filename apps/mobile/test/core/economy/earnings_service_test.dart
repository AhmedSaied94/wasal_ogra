import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart' show TripOutcome;
import 'package:wassal/core/economy/economy.dart';

import '../../helpers/economy.dart';

// US2 through the real service over SQLite (spec.md User Story 2).

const _minuteMs = 60000;

Future<TxnId> _start(TestEconomy e, String tripId) async {
  final id = e.service.newRequestId();
  expect(await e.service.startTrip(id, tripId: tripId), isA<OpApplied>());
  return id;
}

Future<OpOutcome> _result(
  TestEconomy e,
  TxnId start, {
  String tripId = 'line_hay.01',
  TripOutcome outcome = TripOutcome.finished,
  int stars = 3,
  int earnings = 15,
  int durationMs = 90000,
}) => e.service.recordResult(
  e.service.newRequestId(),
  start: start,
  result: tripResult(
    tripId: tripId,
    outcome: outcome,
    stars: stars,
    earnings: earnings,
    durationMs: durationMs,
  ),
);

Future<int> _rows(TestEconomy e) async =>
    (await dumpTables(e.db))['ledger_ops']!.length;

void main() {
  test('1. a result adds its earnings and progress in one step', () async {
    var e = await testEconomy(dbFile: tempDbFile());
    final start = await _start(e, 'line_hay.01');
    final outcome = await _result(e, start, earnings: 18) as OpApplied;
    expect(outcome.view.jenehat, 18);
    expect(outcome.view.progress['line_hay.01']?.plays, 1);
    expect(outcome.view.unfinished, isNull);
    expect(outcome.view.lastResult?.startTxn, start);
    expect(await _rows(e), 2);

    // A failed trip pays 0 and still counts as a play.
    final failed = await _start(e, 'line_hay.01');
    await _result(
      e,
      failed,
      outcome: TripOutcome.failed,
      stars: 0,
      earnings: 0,
    );
    expect(e.service.view.jenehat, 18);
    expect(e.service.view.progress['line_hay.01']?.plays, 2);

    e = await reopen(e);
    expect(e.service.view.jenehat, 18);
    expect(e.service.view.progress['line_hay.01']?.plays, 2);
    expect(e.service.view.progress['line_hay.01']?.bestStars, 3);
  });

  test(
    '2. best stars and time only improve; the first completion stays',
    () async {
      final e = await testEconomy();
      await _result(
        e,
        await _start(e, 'line_hay.01'),
        stars: 2,
        durationMs: 80000,
      );
      final first = e.service.view.progress['line_hay.01']!;
      expect(first.firstCompletedAtMs, testEpochMs);

      e.passTime(minute * 30);
      await _result(
        e,
        await _start(e, 'line_hay.01'),
        stars: 1,
        durationMs: 95000,
      );
      e.passTime(minute * 30);
      await _result(
        e,
        await _start(e, 'line_hay.01'),
        stars: 3,
        durationMs: 85000,
      );

      final progress = e.service.view.progress['line_hay.01']!;
      expect(progress.bestStars, 3);
      expect(progress.bestTimeMs, 80000);
      expect(progress.plays, 3);
      expect(progress.firstCompletedAtMs, testEpochMs);
      expect(e.clock.nowMs(), testEpochMs + 60 * _minuteMs);
    },
  );

  group('3. results that are refused change nothing', () {
    test('no recorded start', () async {
      final e = await testEconomy();
      final before = await dumpTables(e.db);
      final outcome = await _result(e, txnIdOf(42));
      expect((outcome as OpRefused).code, EconomyRefusal.noTripStart);
      expect(await dumpTables(e.db), before);
    });

    test('a second result for the same start', () async {
      final e = await testEconomy();
      final start = await _start(e, 'line_hay.01');
      await _result(e, start);
      final before = await dumpTables(e.db);
      final outcome = await _result(e, start);
      expect((outcome as OpRefused).code, EconomyRefusal.resultExists);
      expect(await dumpTables(e.db), before);
      expect(e.service.view.jenehat, 15);
    });

    test('earnings above the max or below 0', () async {
      final e = await testEconomy();
      final start = await _start(e, 'line_hay.01');
      final before = await dumpTables(e.db);
      for (final earnings in [21, -1]) {
        final outcome = await _result(e, start, earnings: earnings);
        expect(
          (outcome as OpRefused).code,
          EconomyRefusal.earningsOutOfBounds,
          reason: '$earnings',
        );
      }
      expect(await dumpTables(e.db), before);
      expect(e.service.view.unfinished?.startTxn, start);
    });
  });

  group('4. ×2 pays once, and only for a paid finished trip', () {
    test('a paid finished trip doubles once', () async {
      var e = await testEconomy(dbFile: tempDbFile());
      await _result(
        e,
        await _start(e, 'line_gamaa.02'),
        tripId: 'line_gamaa.02',
        earnings: 40,
      );
      Future<OpOutcome> double() => e.service.applyAdReward(
        e.service.newRequestId(),
        placement: AdPlacement.resultDouble,
      );
      final doubled = await double() as OpApplied;
      expect(doubled.op.op.jenehatDelta, 40);
      expect(doubled.view.jenehat, 80);
      expect(
        ((await double()) as OpRefused).code,
        EconomyRefusal.alreadyDoubled,
      );

      e = await reopen(e);
      expect(e.service.view.jenehat, 80);
      expect(e.service.view.lastResult?.doubled, isTrue);
      expect(
        ((await double()) as OpRefused).code,
        EconomyRefusal.alreadyDoubled,
      );
    });

    test('failed, abandoned or unpaid trips are refused', () async {
      final e = await testEconomy();
      for (final (outcome, stars) in [
        (TripOutcome.failed, 0),
        (TripOutcome.abandoned, 0),
        (TripOutcome.finished, 1),
      ]) {
        await _result(
          e,
          await _start(e, 'line_hay.01'),
          outcome: outcome,
          stars: stars,
          earnings: 0,
        );
        final refused = await e.service.applyAdReward(
          e.service.newRequestId(),
          placement: AdPlacement.resultDouble,
        );
        expect(
          (refused as OpRefused).code,
          EconomyRefusal.notDoublable,
          reason: outcome.name,
        );
      }
      expect(e.service.view.jenehat, 0);
    });
  });

  test(
    '5. entries the active pack lacks are kept and skipped (FR-034)',
    () async {
      final e = await testEconomy(
        firstState: (nowMs) => EconomyState(
          jenehat: 0,
          bonat: 0,
          fuel: FuelState(liters: 5, countedFromMs: nowMs),
          progress: const {'line_hay.99': TripProgress(bestStars: 2, plays: 3)},
          ownership: {
            (SkuKind.item, 'salon.missing'): Owned(
              kind: SkuKind.item,
              variantId: 'gold',
              acquiredAtMs: nowMs,
              acquiredBy: txnIdOf(77),
            ),
          },
        ),
      );
      final content = e.content;
      final view = e.service.view;
      for (final line in content.lines) {
        for (final trip in content.tripsOf(line.lineId)) {
          expect(view.progress[trip.tripId], isNull, reason: trip.tripId);
        }
      }
      for (final room in content.rooms) {
        for (final item in content.itemsOf(room.roomId)) {
          expect(view.owns(SkuKind.item, item.itemId), isFalse);
          expect(view.variantOf(item.itemId), isNull);
        }
      }
      expect(view.progress['line_hay.99']?.plays, 3);
      expect(view.owns(SkuKind.item, 'salon.missing'), isTrue);
      expect(view.variantOf('salon.missing'), 'gold');

      // Play still works around them.
      await _result(e, await _start(e, 'line_hay.01'));
      expect(
        e.service.view.progress.keys,
        containsAll(['line_hay.99', 'line_hay.01']),
      );
    },
  );
}
