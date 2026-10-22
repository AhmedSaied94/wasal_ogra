import 'package:content_models/content_models.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/fuel.dart';
import 'package:wassal/core/economy/economy.dart';

import '../../helpers/economy.dart';

// US1 through the real service over SQLite (spec.md User Story 1), and the
// next-liter timer under fake time.

const _minuteMs = 60000;
const _regenMs = 20 * _minuteMs;

Future<TxnId> _start(TestEconomy e, [String tripId = 'line_hay.01']) async {
  final id = e.service.newRequestId();
  expect(await e.service.startTrip(id, tripId: tripId), isA<OpApplied>());
  return id;
}

/// A start and its result, so the next start isn't refused as unfinished.
Future<void> _play(TestEconomy e, [String tripId = 'line_hay.01']) async {
  final start = await _start(e, tripId);
  final outcome = await e.service.recordResult(
    e.service.newRequestId(),
    start: start,
    result: tripResult(tripId: tripId),
  );
  expect(outcome, isA<OpApplied>());
}

Future<int> _rows(TestEconomy e) async =>
    (await dumpTables(e.db))['ledger_ops']!.length;

FuelView _fuel(TestEconomy e) => e.service.view.fuel;

EconomyState Function(int) _withBonat(int bonat) =>
    (nowMs) =>
        EconomyState.newPlayer(fuelMax: 5, nowMs: nowMs).copyWith(bonat: bonat);

void main() {
  test('1. a new player has a full tank and no countdown', () async {
    final e = await testEconomy();
    expect(_fuel(e), const FuelView(liters: 5, max: 5));
  });

  test(
    '2. a start spends exactly one liter, in the step that records it',
    () async {
      final e = await testEconomy();
      final id = e.service.newRequestId();
      final outcome =
          await e.service.startTrip(id, tripId: 'line_hay.01') as OpApplied;
      expect(outcome.op.op.fuelDelta, -1);
      expect(outcome.view.fuel.liters, 4);
      expect(await _rows(e), 1);

      // A replay of the trip just completed costs a liter too.
      await e.service.recordResult(
        e.service.newRequestId(),
        start: id,
        result: tripResult(tripId: 'line_hay.01'),
      );
      await _start(e);
      expect(_fuel(e).liters, 3);
    },
  );

  test('3. a liter per 20 minutes, open, closed and offline', () async {
    var e = await testEconomy(dbFile: tempDbFile());
    await _play(e);
    await _play(e);
    expect(_fuel(e).liters, 3);

    e.passTime(minute * 19);
    expect(_fuel(e).liters, 3);
    e.passTime(minute);
    expect(_fuel(e).liters, 4);

    // Closed for 20 minutes, with the phone on.
    await e.service.handleLifecycle(AppLifecycleState.paused);
    await e.close();
    e.passTime(minute * 20);
    e = await reopen(e);
    expect(_fuel(e).liters, 5);
    expect(_fuel(e).nextLiterAtMs, isNull);
  });

  test(
    '4. a start from full starts the countdown; below full it keeps it',
    () async {
      final e = await testEconomy();
      await _play(e);
      expect(_fuel(e).nextLiterAtMs, testEpochMs + _regenMs);
      expect(_fuel(e).fullAtMs, testEpochMs + _regenMs);

      e.passTime(minute * 7);
      await _play(e);
      expect(_fuel(e).liters, 3);
      expect(_fuel(e).nextLiterAtMs, testEpochMs + _regenMs);
      expect(_fuel(e).fullAtMs, testEpochMs + 2 * _regenMs);
    },
  );

  test('5. the view gives liters, max, next liter and full times', () async {
    final e = await testEconomy();
    for (var i = 0; i < 3; i++) {
      await _play(e);
    }
    expect(
      _fuel(e),
      const FuelView(
        liters: 2,
        max: 5,
        nextLiterAtMs: testEpochMs + _regenMs,
        fullAtMs: testEpochMs + 3 * _regenMs,
      ),
    );
    e.passTime(minute * 45);
    expect(
      _fuel(e),
      const FuelView(
        liters: 4,
        max: 5,
        nextLiterAtMs: testEpochMs + 3 * _regenMs,
        fullAtMs: testEpochMs + 3 * _regenMs,
      ),
    );
    e.passTime(minute * 15);
    expect(_fuel(e), const FuelView(liters: 5, max: 5));
  });

  test('6. an empty tank refuses a start, and nothing changes', () async {
    final e = await testEconomy();
    for (var i = 0; i < 5; i++) {
      await _play(e);
    }
    expect(_fuel(e).liters, 0);
    final before = await dumpTables(e.db);

    final outcome = await e.service.startTrip(
      e.service.newRequestId(),
      tripId: 'line_hay.01',
    );
    expect(outcome, isA<OpRefused>());
    expect((outcome as OpRefused).code, EconomyRefusal.noFuel);
    expect(await dumpTables(e.db), before);
    expect(_fuel(e).liters, 0);
  });

  group('7. refills', () {
    Future<TestEconomy> empty({int bonat = 0}) async {
      final e = await testEconomy(firstState: _withBonat(bonat));
      for (var i = 0; i < 5; i++) {
        await _play(e);
      }
      expect(_fuel(e).liters, 0);
      return e;
    }

    test('a rewarded ad fills the tank', () async {
      final e = await empty();
      final outcome = await e.service.applyAdReward(
        e.service.newRequestId(),
        placement: AdPlacement.fuelRefill,
      );
      expect((outcome as OpApplied).op.op.fuelDelta, 5);
      expect(_fuel(e), const FuelView(liters: 5, max: 5));
    });

    test('refuel_full for 30 BONAT fills the tank', () async {
      final e = await empty(bonat: 100);
      final outcome = await e.service.buy(
        e.service.newRequestId(),
        kind: SkuKind.fuel,
        skuId: 'refuel_full',
      );
      expect((outcome as OpApplied).op.op.bonatDelta, -30);
      expect(_fuel(e).liters, 5);
      expect(e.service.view.bonat, 70);
    });

    test('fuel_unlimited_1h makes every start in 60 minutes free', () async {
      final e = await empty(bonat: 100);
      await e.service.buy(
        e.service.newRequestId(),
        kind: SkuKind.fuelUnlimited,
        skuId: 'fuel_unlimited_1h',
      );
      expect(_fuel(e).unlimitedUntilMs, testEpochMs + unlimitedWindowMs);
      for (var i = 0; i < 3; i++) {
        await _play(e);
        e.passTime(minute * 19);
      }
      // 57 minutes in: still free, and the tank refilled on its own.
      expect(_fuel(e).liters, 2);
      await _play(e);
      expect(_fuel(e).liters, 2);

      e.passTime(minute * 3);
      expect(_fuel(e).unlimitedUntilMs, isNull);
      await _play(e);
      expect(_fuel(e).liters, 2);
    });
  });

  group('8. a trip that continues spends nothing', () {
    test(
      'rebuilt after a relaunch: unfinished is set, no op is written',
      () async {
        var e = await testEconomy(dbFile: tempDbFile());
        final start = await _start(e);
        final rows = await _rows(e);
        e = await reopen(e);
        expect(e.service.view.unfinished?.startTxn, start);
        expect(_fuel(e).liters, 4);
        expect(await _rows(e), rows);
      },
    );

    test('a revive, by ad or by BONAT, spends no fuel', () async {
      final e = await testEconomy(firstState: _withBonat(50));
      await _start(e);
      final ad = await e.service.applyAdReward(
        e.service.newRequestId(),
        placement: AdPlacement.tripRevive,
      );
      expect((ad as OpApplied).op.op.fuelDelta, 0);
      expect(_fuel(e).liters, 4);
      expect(e.service.view.unfinished?.revived, isTrue);

      await e.service.recordResult(
        e.service.newRequestId(),
        start: e.service.view.unfinished!.startTxn,
        result: tripResult(tripId: 'line_hay.01', revived: true),
      );
      await _start(e);
      final bought = await e.service.buy(
        e.service.newRequestId(),
        kind: SkuKind.revive,
        skuId: 'revive',
      );
      expect((bought as OpApplied).op.op.fuelDelta, 0);
      expect(bought.op.op.bonatDelta, -20);
      expect(_fuel(e).liters, 3);
    });
  });

  test(
    '9. moving the device clock ±3 h with the same boot changes nothing',
    () async {
      var e = await testEconomy(dbFile: tempDbFile());
      await _play(e);
      e.passTime(minute * 5);
      final before = _fuel(e);

      for (final shift in [
        const Duration(hours: 3),
        const Duration(hours: -6),
      ]) {
        e.device.advance(shift);
        expect(_fuel(e), before);
        e = await reopen(e);
        expect(_fuel(e), before);
      }
      e.passTime(minute * 15);
      expect(_fuel(e).liters, 5);
    },
  );

  group('the next-liter timer', () {
    /// Completes [future] inside fake time.
    T settle<T>(FakeAsync async, Future<T> future) {
      T? value;
      Object? error;
      var done = false;
      future.then(
        (v) {
          value = v;
          done = true;
        },
        onError: (Object e) {
          error = e;
          done = true;
        },
      );
      for (var i = 0; i < 100 && !done; i++) {
        async
          ..flushMicrotasks()
          ..elapse(Duration.zero);
      }
      if (error case final e?) throw e;
      if (!done) fail('Did not complete in fake time.');
      return value as T;
    }

    /// Time passes with the app open, a minute at a time.
    void pass(FakeAsync async, TestEconomy e, Duration by) {
      for (var i = 0; i < by.inMinutes; i++) {
        e.passTime(minute);
        async.elapse(minute);
      }
    }

    void play(FakeAsync async, TestEconomy e) => settle(async, _play(e));

    test('emits a view when the next liter arrives, and re-arms', () {
      fakeAsync((async) {
        final e = settle(async, testEconomy());
        final views = <EconomyView>[];
        e.service.views.listen(views.add);
        expect(
          async.pendingTimers,
          isEmpty,
          reason: 'a full tank waits for nothing',
        );

        play(async, e);
        pass(async, e, minute * 10);
        play(async, e);
        views.clear();

        pass(async, e, minute * 9);
        expect(views, isEmpty);
        pass(async, e, minute);
        expect([for (final v in views) v.fuel.liters], [4]);
        pass(async, e, minute * 20);
        expect([for (final v in views) v.fuel.liters], [4, 5]);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('an op re-arms it to the new next liter', () {
      fakeAsync((async) {
        final e = settle(async, testEconomy());
        play(async, e);
        expect(async.pendingTimers, hasLength(1));
        expect(
          async.pendingTimers.single.duration,
          const Duration(milliseconds: _regenMs),
        );
        pass(async, e, minute * 5);
        settle(
          async,
          e.service.applyAdReward(
            e.service.newRequestId(),
            placement: AdPlacement.fuelRefill,
          ),
        );
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('a running unlimited window ends with a view', () {
      fakeAsync((async) {
        final e = settle(async, testEconomy(firstState: _withBonat(80)));
        final views = <EconomyView>[];
        e.service.views.listen(views.add);
        settle(
          async,
          e.service.buy(
            e.service.newRequestId(),
            kind: SkuKind.fuelUnlimited,
            skuId: 'fuel_unlimited_1h',
          ),
        );
        expect(views.last.fuel.unlimitedUntilMs, isNotNull);
        pass(async, e, const Duration(minutes: 60));
        expect(views.last.fuel.unlimitedUntilMs, isNull);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('paused or hidden cancels it; resumed resyncs and re-arms', () {
      for (final away in [AppLifecycleState.paused, AppLifecycleState.hidden]) {
        fakeAsync((async) {
          final e = settle(async, testEconomy());
          final views = <EconomyView>[];
          e.service.views.listen(views.add);
          play(async, e);
          views.clear();

          settle(async, e.service.handleLifecycle(away));
          expect(async.pendingTimers, isEmpty, reason: away.name);
          // In the background the CPU sleeps: only the uptime counter moves.
          e.uptime.sleep(minute * 30);
          e.device.advance(minute * 30);
          async.elapse(minute * 30);
          expect(views, isEmpty, reason: away.name);

          settle(async, e.service.handleLifecycle(AppLifecycleState.resumed));
          expect(views.single.fuel.liters, 5, reason: away.name);
          expect(e.clock.nowMs(), testEpochMs + 30 * _minuteMs);
          expect(async.pendingTimers, isEmpty);
        });
      }
    });

    test('paused stores the latest trusted time', () {
      fakeAsync((async) {
        final e = settle(async, testEconomy());
        pass(async, e, minute * 7);
        settle(async, e.service.handleLifecycle(AppLifecycleState.paused));
        final anchor = settle(async, e.store.loadAnchor());
        expect(anchor.latestTrustedMs, testEpochMs + 7 * _minuteMs);
      });
    });

    test('inactive and detached change nothing', () {
      fakeAsync((async) {
        final e = settle(async, testEconomy());
        play(async, e);
        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.detached,
        ]) {
          settle(async, e.service.handleLifecycle(state));
          expect(async.pendingTimers, hasLength(1), reason: state.name);
        }
      });
    });

    test('dispose cancels it', () {
      fakeAsync((async) {
        final e = settle(async, testEconomy());
        play(async, e);
        e.service.dispose();
        expect(async.pendingTimers, isEmpty);
      });
    });
  });
}
