import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/data/drift_trip_records.dart';
import 'package:wassal/features/trip/data/trip_kill_point.dart';
import 'package:wassal/features/trip/data/trip_records.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/trip.dart';

// Pausing, leaving and restarting (tasks.md T045, contracts/trip-controller.md
// "Pausing and lifecycle", "Leave", "Restart").

/// The record's saved clock.
Future<int?> savedClock(TestEconomy economy, TxnId start) async =>
    (await DriftTripRecords(economy.db).load(start))?.tMs;

/// The start id of the one record left.
Future<String> recordStart(TestEconomy economy) async =>
    (await economy.db
            .customSelect('SELECT start_txn FROM trip_record')
            .getSingle())
        .read<String>('start_txn');

void main() {
  for (final reason in [
    PauseReason.lifecycle,
    PauseReason.button,
    PauseReason.back,
  ]) {
    test('pause(${reason.name}) stops the clock and saves it', () async {
      final economy = await testEconomy();
      final c = testController(economy);
      await c.open('line_hay.01');
      advanceMs(c, 3003);
      c.advance(const Duration(milliseconds: 16));
      expect(c.alpha, greaterThan(0));

      c.pause(reason);
      final tMs = c.engine!.state.tMs;
      expect(c.phase, TripPhase.paused);
      expect(c.model.pauseReason, reason);
      expect(c.engine!.status, TripStatus.paused);
      expect(c.alpha, 0);
      await settle();
      expect(await savedClock(economy, c.session!.startTxn), tMs);

      advanceMs(c, 1000);
      expect(c.engine!.state.tMs, tMs);

      c.resume();
      expect(c.phase, TripPhase.running);
      expect(c.model.pauseReason, isNull);
      expect(c.engine!.status, TripStatus.running);
      advanceMs(c, 33);
      expect(c.engine!.state.tMs, tMs + 33);
    });
  }

  test('leave from paused: abandoned, recorded, record gone, Home', () async {
    final economy = await testEconomy();
    final records = _SpyRecords(DriftTripRecords(economy.db));
    final c = testController(economy, records: records);
    await c.open('line_hay.01');
    final fuel = economy.service.view.fuel.liters;
    advanceMs(c, 3000);
    c.pause(PauseReason.button);

    await c.leave();
    await settle();
    expect(records.appended.last.command, isA<Abandon>());
    expect(records.appended.last.tMs, c.engine!.state.tMs);
    expect(c.phase, TripPhase.ended);
    expect(c.model.exit, const ExitToHome());
    expect(economy.service.view.lastResult!.outcome, TripOutcome.abandoned);
    expect(economy.service.view.unfinished, isNull);
    expect(await rowCount(economy, 'trip_record'), 0);
    expect(await rowCount(economy, 'trip_record_command'), 0);
    // A trip left is a liter spent.
    expect(economy.service.view.fuel.liters, fuel);
  });

  test('restart: the run recorded abandoned, then a fresh start', () async {
    final economy = await testEconomy();
    final c = testController(economy);
    await c.open('line_hay.01');
    final first = c.session!.startTxn;
    final fuel = economy.service.view.fuel.liters;
    advanceMs(c, 3000);
    c.pick(500);
    c.pause(PauseReason.button);
    expect(c.model.restartEnabled, isTrue);

    await c.restart();
    await settle();
    expect(c.phase, TripPhase.running);
    expect(c.session!.startTxn, isNot(first));
    expect(c.engine!.state.tMs, 0);
    expect(c.engine!.commandLog, isEmpty);
    expect(c.view!.hand.isEmpty, isTrue);
    expect(economy.service.view.unfinished!.startTxn, c.session!.startTxn);
    expect(economy.service.view.lastResult!.outcome, TripOutcome.abandoned);
    expect(await opCount(economy, 'trip_result'), 1);
    expect(await opCount(economy, 'trip_start'), 2);
    expect(economy.service.view.fuel.liters, fuel - 1);
    expect(await recordStart(economy), c.session!.startTxn.value);
  });

  group('restart is unavailable on an empty tank', () {
    Future<TestEconomy> lastLiter({int? unlimitedForMs}) => testEconomy(
      firstState: (nowMs) =>
          EconomyState.newPlayer(fuelMax: 5, nowMs: nowMs).copyWith(
            fuel: FuelState(
              liters: 1,
              countedFromMs: nowMs,
              unlimitedUntilMs: unlimitedForMs == null
                  ? null
                  : nowMs + unlimitedForMs,
            ),
          ),
    );

    test('with no unlimited window', () async {
      final economy = await lastLiter();
      final c = testController(economy);
      await c.open('line_hay.01');
      expect(economy.service.view.fuel.liters, 0);
      c.pause(PauseReason.button);
      expect(c.model.restartEnabled, isFalse);

      await c.restart();
      await settle();
      expect(c.phase, TripPhase.paused);
      expect(economy.service.view.unfinished, isNotNull);
      expect(await opCount(economy, 'trip_result'), 0);
    });

    test('but not while an unlimited window runs', () async {
      final economy = await lastLiter(unlimitedForMs: 3600000);
      final c = testController(economy);
      await c.open('line_hay.01');
      c.pause(PauseReason.button);
      expect(c.model.restartEnabled, isTrue);
    });
  });

  group('a write failure while restarting', () {
    test(
      'on the abandoned result: ending, then a retry that goes on',
      () async {
        final interceptor = FailingInterceptor();
        final economy = await testEconomy(
          executor: (inner) => inner.interceptWith(interceptor),
        );
        final c = testController(economy);
        await c.open('line_hay.01');
        final fuel = economy.service.view.fuel.liters;
        advanceMs(c, 3000);
        c.pause(PauseReason.button);
        await settle();

        interceptor.failInserts = true;
        await c.restart();
        await settle();
        interceptor.failInserts = false;
        expect(c.phase, TripPhase.ending);
        expect(c.model.retry, TripRetry.result);
        expect(await opCount(economy, 'trip_start'), 1);

        await c.retry();
        await settle();
        expect(c.phase, TripPhase.running);
        expect(c.engine!.state.tMs, 0);
        expect(await opCount(economy, 'trip_result'), 1);
        expect(await opCount(economy, 'trip_start'), 2);
        expect(economy.service.view.fuel.liters, fuel - 1);
        expect(await rowCount(economy, 'trip_record'), 1);
      },
    );

    test('on the new start: opening, then the same start id', () async {
      final interceptor = FailingInterceptor();
      var armed = false;
      final economy = await testEconomy(
        executor: (inner) => inner.interceptWith(interceptor),
      );
      final c = testController(
        economy,
        onKillPoint: (point) {
          if (armed && point == TripKillPoint.recordCreated) {
            interceptor.failInserts = true;
          }
        },
      );
      await c.open('line_hay.01');
      final fuel = economy.service.view.fuel.liters;
      advanceMs(c, 3000);
      c.pause(PauseReason.button);
      await settle();

      armed = true;
      await c.restart();
      await settle();
      armed = false;
      interceptor.failInserts = false;
      expect(c.phase, TripPhase.opening);
      expect(c.model.retry, TripRetry.start);
      expect(await opCount(economy, 'trip_result'), 1);
      expect(await opCount(economy, 'trip_start'), 1);
      final kept = await recordStart(economy);

      await c.retry();
      await settle();
      expect(c.phase, TripPhase.running);
      expect(economy.service.view.unfinished!.startTxn.value, kept);
      expect(await opCount(economy, 'trip_result'), 1);
      expect(await opCount(economy, 'trip_start'), 2);
      expect(economy.service.view.fuel.liters, fuel - 1);
    });
  });
}

/// The store, recording the commands appended.
final class _SpyRecords implements TripRecords {
  _SpyRecords(this._inner);

  final TripRecords _inner;
  final appended = <LoggedCommand>[];

  @override
  Future<bool> create(TripRecordHeader header) => _inner.create(header);

  @override
  Future<bool> appendCommand(TxnId start, LoggedCommand command) {
    appended.add(command);
    return _inner.appendCommand(start, command);
  }

  @override
  Future<bool> appendBoosterUse(
    TxnId start,
    LoggedCommand command,
    TripIntent intent,
  ) {
    appended.add(command);
    return _inner.appendBoosterUse(start, command, intent);
  }

  @override
  Future<bool> saveClock(TxnId start, int tMs) => _inner.saveClock(start, tMs);

  @override
  Future<bool> deleteIntent(TxnId request) => _inner.deleteIntent(request);

  @override
  Future<StoredTrip?> load(TxnId start) => _inner.load(start);

  @override
  Future<bool> delete(TxnId start) => _inner.delete(start);

  @override
  Future<bool> deleteAllExcept(TxnId? keep) => _inner.deleteAllExcept(keep);
}
