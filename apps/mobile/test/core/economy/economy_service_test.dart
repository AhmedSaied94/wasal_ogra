import 'package:content_models/content_models.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/rules.dart';
import 'package:wassal/core/economy/drift_economy_store.dart';
import 'package:wassal/core/economy/economy.dart';

import '../../helpers/economy.dart';

// The service's generic behaviour (contracts/economy-api.md "Behaviour"),
// with rules that accept any trip and refuse the one called 'refuse'. Every
// accepted request adds 1 JENEHAT, so the order of applying shows.

final class _FlagRules implements Rules {
  const _FlagRules();

  @override
  Decision validate(EconomyState state, OpRequest request, RuleContext ctx) =>
      switch (request) {
        StartTripRequest(tripId: 'refuse') => const Declined(
          EconomyRefusal.unknownTrip,
        ),
        StartTripRequest(:final tripId) => Validated(
          ctx.op(OpType.tripStart, {
            'trip_id': tripId,
            'seen': state.jenehat,
          }, jenehatDelta: 1),
        ),
        _ => const Declined(EconomyRefusal.serverOnly),
      };

  @override
  EconomyState apply(EconomyState state, Op op) =>
      state.copyWith(jenehat: state.jenehat + op.jenehatDelta);

  @override
  bool stillValid(EconomyState state, Op op) => true;
}

Future<int> _rowCount(TestEconomy economy) async =>
    (await dumpTables(economy.db))['ledger_ops']!.length;

void main() {
  test('an applied request writes one row and emits one view', () async {
    late final TestEconomy economy;
    final seenInside = <int>[];
    economy = await testEconomy(
      rules: const _FlagRules(),
      onKillPoint: (point) {
        if (point == EconomyKillPoint.afterAnchor) {
          seenInside.add(economy.service.view.jenehat);
        }
      },
    );
    final views = <EconomyView>[];
    final subscription = economy.service.views.listen(views.add);
    addTearDown(subscription.cancel);

    final outcome = await economy.service.startTrip(
      economy.service.newRequestId(),
      tripId: 'a',
    );
    await pumpEventQueue();

    expect(outcome, isA<OpApplied>());
    final applied = outcome as OpApplied;
    expect(applied.repeated, isFalse);
    expect(applied.op.seq, 1);
    expect(applied.view.jenehat, 1);
    expect(await _rowCount(economy), 1);
    expect([for (final view in views) view.jenehat], [1]);
    // Inside the transaction the view still showed the state before it.
    expect(seenInside, [0]);
    expect(economy.service.view.jenehat, 1);
  });

  test('a refused request writes nothing and emits nothing', () async {
    final economy = await testEconomy(rules: const _FlagRules());
    final views = <EconomyView>[];
    final subscription = economy.service.views.listen(views.add);
    addTearDown(subscription.cancel);
    final before = await dumpTables(economy.db);

    final outcome = await economy.service.startTrip(
      economy.service.newRequestId(),
      tripId: 'refuse',
    );
    await pumpEventQueue();

    expect(outcome, isA<OpRefused>());
    expect((outcome as OpRefused).code, EconomyRefusal.unknownTrip);
    expect(await dumpTables(economy.db), before);
    expect(views, isEmpty);
    expect(economy.service.view.jenehat, 0);
  });

  test('a repeated id returns the stored op and writes nothing', () async {
    final economy = await testEconomy(rules: const _FlagRules());
    final id = economy.service.newRequestId();
    final first = await economy.service.startTrip(id, tripId: 'a') as OpApplied;
    economy.passTime(minute);
    final before = await dumpTables(economy.db);

    final again = await economy.service.startTrip(id, tripId: 'a');

    expect(again, isA<OpApplied>());
    final repeated = again as OpApplied;
    expect(repeated.repeated, isTrue);
    expect(repeated.op.seq, first.op.seq);
    expect(repeated.op.op.txnId, id);
    expect(repeated.op.op.occurredAtMs, first.op.op.occurredAtMs);
    expect(repeated.view.jenehat, 1);
    expect(await dumpTables(economy.db), before);
  });

  test(
    'requests started together apply one after the other, in order',
    () async {
      final economy = await testEconomy(rules: const _FlagRules());
      final service = economy.service;
      final ids = [for (var i = 0; i < 5; i++) service.newRequestId()];

      final outcomes = await Future.wait([
        for (final (i, id) in ids.indexed) service.startTrip(id, tripId: 't$i'),
      ]);

      for (final (i, outcome) in outcomes.indexed) {
        final applied = outcome as OpApplied;
        expect(applied.op.seq, i + 1);
        expect(applied.op.op.txnId, ids[i]);
        // Each validated against the state the one before it left.
        expect(applied.op.op.payload['seen'], i);
        expect(applied.view.jenehat, i + 1);
      }
      expect(service.view.jenehat, 5);
      expect(await _rowCount(economy), 5);
    },
  );

  test('a full disk fails the write and changes nothing', () async {
    final failing = FailingInterceptor();
    final economy = await testEconomy(
      rules: const _FlagRules(),
      dbFile: tempDbFile(),
      executor: (inner) => inner.interceptWith(failing),
    );
    final views = <EconomyView>[];
    final subscription = economy.service.views.listen(views.add);
    addTearDown(subscription.cancel);
    final before = await dumpTables(economy.db);
    final id = economy.service.newRequestId();

    failing.failInserts = true;
    final outcome = await economy.service.startTrip(id, tripId: 'a');
    failing.failInserts = false;
    await pumpEventQueue();

    expect(outcome, isA<OpWriteFailed>());
    expect(failing.failures, 1);
    expect(economy.service.state.jenehat, 0);
    expect(views, isEmpty);
    expect(await dumpTables(economy.db), before);

    // The next request, even with the same id, applies.
    final retry = await economy.service.startTrip(id, tripId: 'a');
    expect(retry, isA<OpApplied>());
    expect((retry as OpApplied).repeated, isFalse);
    expect(retry.op.seq, 1);
    expect(economy.service.view.jenehat, 1);
  });

  test('every op is stamped with trusted now, never going back', () async {
    final economy = await testEconomy(rules: const _FlagRules());
    final service = economy.service;
    final times = <int>[];

    Future<void> start(String tripId) async {
      final now = economy.clock.nowMs();
      final outcome = await service.startTrip(
        service.newRequestId(),
        tripId: tripId,
      ) as OpApplied;
      expect(outcome.op.op.occurredAtMs, now);
      times.add(outcome.op.op.occurredAtMs);
    }

    await start('a');
    economy.passTime(minute * 3);
    await start('b');
    // The device clock going back changes nothing while the phone is on.
    economy.device.advance(const Duration(hours: -5));
    await start('c');
    economy.passTime(minute);
    await start('d');

    expect(times, [
      testEpochMs,
      testEpochMs + 3 * 60000,
      testEpochMs + 3 * 60000,
      testEpochMs + 4 * 60000,
    ]);
    for (var i = 1; i < times.length; i++) {
      expect(times[i], greaterThanOrEqualTo(times[i - 1]));
    }
  });

  test('ops a rule gives no meaning to are refused, not thrown', () async {
    final economy = await testEconomy(rules: const _FlagRules());
    final outcome = await economy.service.applyAdReward(
      economy.service.newRequestId(),
      placement: AdPlacement.morningPiggy,
    );
    expect(outcome, isA<OpRefused>());
    expect(await _rowCount(economy), 0);
  });

  group('the story calls (M10)', () {
    test('recordScene applies and stores one row', () async {
      final economy = await testEconomy();
      final id = economy.service.newRequestId();

      final outcome = await economy.service.recordScene(
        id,
        chapterId: ChapterId.ch1FirstJob,
        sceneId: 'the_stand',
      );

      expect(outcome, isA<OpApplied>());
      final applied = outcome as OpApplied;
      expect(applied.repeated, isFalse);
      expect(applied.op.op.type, OpType.storyProgress);
      expect(applied.view.scenesSeen['ch1_first_job'], {'the_stand'});
      expect(await _rowCount(economy), 1);
    });

    test('the same TxnId again is a repeat that stores nothing', () async {
      final economy = await testEconomy();
      final id = economy.service.newRequestId();
      final first = await economy.service.recordScene(
        id,
        chapterId: ChapterId.ch1FirstJob,
        sceneId: 'the_stand',
      ) as OpApplied;
      final before = await dumpTables(economy.db);
      economy.passTime(minute);

      final again = await economy.service.recordScene(
        id,
        chapterId: ChapterId.ch1FirstJob,
        sceneId: 'the_stand',
      );

      expect(again, isA<OpApplied>());
      expect((again as OpApplied).repeated, isTrue);
      expect(again.op.seq, first.op.seq);
      expect(await dumpTables(economy.db), before);
    });

    test('a refused repeat (already_recorded) stores no row', () async {
      final economy = await testEconomy();
      final first = await economy.service.recordScene(
        economy.service.newRequestId(),
        chapterId: ChapterId.ch1FirstJob,
        sceneId: 'the_stand',
      );
      expect(first, isA<OpApplied>());
      final before = await dumpTables(economy.db);

      final second = await economy.service.recordScene(
        economy.service.newRequestId(),
        chapterId: ChapterId.ch1FirstJob,
        sceneId: 'the_stand',
      );

      expect(second, isA<OpRefused>());
      expect((second as OpRefused).code, EconomyRefusal.alreadyRecorded);
      expect(await dumpTables(economy.db), before);
      expect(await _rowCount(economy), 1);
    });

    test(
      'claimRequest applies, stores one row and leaves BONAT alone',
      () async {
        final economy = await testEconomy(
          firstState: (nowMs) =>
              EconomyState.newPlayer(fuelMax: 8, nowMs: nowMs).copyWith(
                bonat: 4,
                ownership: {
                  (SkuKind.item, 'salon.nish'): Owned(
                    kind: SkuKind.item,
                    variantId: 'crystal',
                    acquiredAtMs: nowMs,
                  ),
                },
              ),
        );
        final id = economy.service.newRequestId();

        final outcome = await economy.service.claimRequest(
          id,
          requestId: 'req_nish_crystal',
        );

        expect(outcome, isA<OpApplied>());
        final applied = outcome as OpApplied;
        expect(applied.op.op.type, OpType.claimRequest);
        expect(applied.view.requestsClaimed, {'req_nish_crystal'});
        expect(applied.view.bonat, 4);
        expect(await _rowCount(economy), 1);
        expect(economy.service.view.bonat, 4);
      },
    );

    test('a refused claim (already_granted) stores no row', () async {
      final economy = await testEconomy(
        firstState: (nowMs) =>
            EconomyState.newPlayer(fuelMax: 8, nowMs: nowMs).copyWith(
              ownership: {
                (SkuKind.item, 'salon.nish'): Owned(
                  kind: SkuKind.item,
                  variantId: 'crystal',
                  acquiredAtMs: nowMs,
                ),
              },
            ),
      );
      await economy.service.claimRequest(
        economy.service.newRequestId(),
        requestId: 'req_nish_crystal',
      );
      final before = await dumpTables(economy.db);

      final again = await economy.service.claimRequest(
        economy.service.newRequestId(),
        requestId: 'req_nish_crystal',
      );

      expect(again, isA<OpRefused>());
      expect((again as OpRefused).code, EconomyRefusal.alreadyGranted);
      expect(await dumpTables(economy.db), before);
    });
  });

  test('a QueryExecutor wrapper sees the commit as one transaction', () async {
    final counting = _CountingInterceptor();
    final economy = await testEconomy(
      rules: const _FlagRules(),
      executor: (inner) => inner.interceptWith(counting),
    );
    counting.begins = 0;
    await economy.service.startTrip(
      economy.service.newRequestId(),
      tripId: 'a',
    );
    expect(counting.begins, 1);
  });
}

final class _CountingInterceptor extends QueryInterceptor {
  int begins = 0;

  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    begins++;
    return super.beginTransaction(parent);
  }
}
