import 'package:content_models/content_models.dart';
import 'package:drift/drift.dart' show ApplyInterceptor;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/storage/connection.dart';

import '../../helpers/economy.dart';

// A full disk (US4 scenario 3, research R11): the write fails, nothing
// changes in memory or on disk, and the next request applies.

typedef _Arm = void Function(FailingInterceptor failing, bool on);

final _points = <String, _Arm>{
  'the op row': (f, on) => f.failInserts = on,
  'the wallet update': (f, on) => f.failUpdates = on,
  'the commit': (f, on) => f.failCommits = on,
};

/// A disk with no room past the pages the file already has.
void _capped(Database database) {
  configureConnection(database);
  final pages = database.select('PRAGMA page_count').single.values.single;
  database.execute('PRAGMA max_page_count = $pages');
}

void main() {
  for (final MapEntry(key: where, value: arm) in _points.entries) {
    test(
      'SQLITE_FULL at $where gives OpWriteFailed and changes nothing',
      () async {
        final failing = FailingInterceptor();
        var e = await testEconomy(
          dbFile: tempDbFile(),
          executor: (inner) => inner.interceptWith(failing),
          firstState: (nowMs) => EconomyState.newPlayer(
            fuelMax: 5,
            nowMs: nowMs,
          ).copyWith(bonat: 50),
        );
        final views = <EconomyView>[];
        final subscription = e.service.views.listen(views.add);
        addTearDown(subscription.cancel);
        final before = await dumpTables(e.db);
        final state = e.service.state;
        final id = e.service.newRequestId();

        arm(failing, true);
        final outcome = await e.service.buy(
          id,
          kind: SkuKind.booster,
          skuId: 'change_bag',
        );
        arm(failing, false);
        await pumpEventQueue();

        expect(outcome, isA<OpWriteFailed>());
        expect(failing.failures, 1);
        expect(e.service.state, state);
        expect(views, isEmpty);
        expect(await dumpTables(e.db), before);
        expect(await e.store.findOp(id), isNull);

        // The next request, the same one, applies; and survives a relaunch.
        final retry = await e.service.buy(
          id,
          kind: SkuKind.booster,
          skuId: 'change_bag',
        );
        expect((retry as OpApplied).repeated, isFalse);
        expect(e.service.view.bonat, 40);
        e = await reopen(e);
        expect(e.service.view.bonat, 40);
        expect(e.service.view.inventory[BoosterId.changeBag], 1);
      },
    );
  }

  test(
    'a failed trip start leaves the tank and the trip as they were',
    () async {
      final failing = FailingInterceptor();
      final e = await testEconomy(
        executor: (inner) => inner.interceptWith(failing),
      );
      failing.failUpdates = true;
      final outcome = await e.service.startTrip(
        e.service.newRequestId(),
        tripId: 'line_hay.01',
      );
      failing.failUpdates = false;
      expect(outcome, isA<OpWriteFailed>());
      expect(e.service.view.fuel.liters, 5);
      expect(e.service.view.unfinished, isNull);
    },
  );

  group('a failing anchor write at a lifecycle change', () {
    // The anchor is saved again at the next op or pause (research R11).
    test('pausing completes, and the time stays', () async {
      final failing = FailingInterceptor();
      final e = await testEconomy(
        executor: (inner) => inner.interceptWith(failing),
      );
      e.passTime(minute);
      final now = e.clock.nowMs();

      failing.failUpdates = true;
      await e.service.handleLifecycle(AppLifecycleState.paused);
      failing.failUpdates = false;

      expect(failing.failures, 1);
      expect(e.clock.nowMs(), now);
    });

    test('a restart seen on resume keeps time going, and emits', () async {
      final failing = FailingInterceptor();
      final e = await testEconomy(
        executor: (inner) => inner.interceptWith(failing),
      );
      final views = <EconomyView>[];
      final subscription = e.service.views.listen(views.add);
      addTearDown(subscription.cancel);
      e.passTime(minute * 5);
      final before = e.clock.nowMs();
      await e.service.handleLifecycle(AppLifecycleState.paused);

      e.uptime.restart();
      failing.failUpdates = true;
      await e.service.handleLifecycle(AppLifecycleState.resumed);
      failing.failUpdates = false;
      await pumpEventQueue();

      expect(failing.failures, 1);
      expect(views, hasLength(1));
      // The device clock didn't move, so neither does trusted time.
      expect(e.clock.nowMs(), before);
      e.passTime(minute);
      expect(e.clock.nowMs(), before + minute.inMilliseconds);
    });
  });

  group('on the background connection the app uses', () {
    // A file on its own isolate, where SQLite's errors come back wrapped
    // (connection.dart).
    Future<TestEconomy> background() async {
      final file = tempDbFile();
      await (await testEconomy(
        dbFile: file,
        firstState: (nowMs) => EconomyState.newPlayer(
          fuelMax: 5,
          nowMs: nowMs,
        ).copyWith(bonat: 100000),
      )).close();
      return testEconomy(
        dbFile: file,
        executor: (_) =>
            NativeDatabase.createInBackground(file, setup: _capped),
      );
    }

    Future<OpOutcome> buy(TestEconomy e) => e.service.buy(
      e.service.newRequestId(),
      kind: SkuKind.booster,
      skuId: 'change_bag',
    );

    test('a full disk gives OpWriteFailed and changes nothing', () async {
      final e = await background();
      late EconomyState state;
      late Map<String, List<Map<String, Object?>>> before;
      OpOutcome? outcome;
      for (var i = 0; i < 1000 && outcome is! OpWriteFailed; i++) {
        state = e.service.state;
        before = await dumpTables(e.db);
        outcome = await buy(e);
      }
      expect(outcome, isA<OpWriteFailed>());
      expect(e.service.state, state);
      expect(await dumpTables(e.db), before);

      // SQLite rolled the transaction back itself; with room again, the
      // same connection goes on.
      await e.db.customStatement('PRAGMA max_page_count = 1000000');
      expect(await buy(e), isA<OpApplied>());
      final e2 = await reopen(e);
      expect(e2.service.view.bonat, state.bonat - 10);
    });

    test(
      'a write error SQLite doesn\'t roll back gives OpWriteFailed',
      () async {
        final e = await background();
        await e.db.customStatement(
          'CREATE TEMP TRIGGER refuse BEFORE INSERT ON ledger_ops '
          "BEGIN SELECT RAISE(ABORT, 'refused'); END",
        );
        final state = e.service.state;
        final before = await dumpTables(e.db);

        expect(await buy(e), isA<OpWriteFailed>());
        expect(e.service.state, state);
        expect(await dumpTables(e.db), before);

        await e.db.customStatement('DROP TRIGGER refuse');
        expect(await buy(e), isA<OpApplied>());
      },
    );
  });
}
