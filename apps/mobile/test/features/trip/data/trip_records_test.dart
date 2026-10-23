import 'dart:async';
import 'dart:convert';

import 'package:content_models/content_models.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/economy/domain/txn_id.dart';
import 'package:wassal/core/storage/app_database.dart';
import 'package:wassal/features/trip/data/drift_trip_records.dart';
import 'package:wassal/features/trip/data/trip_kill_point.dart';
import 'package:wassal/features/trip/data/trip_records.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/trip.dart';

final class _Kill implements Exception {
  const _Kill();
}

AppDatabase _memoryDb({QueryInterceptor? interceptor}) {
  final inner = NativeDatabase.memory();
  final db = AppDatabase(
    interceptor == null ? inner : inner.interceptWith(interceptor),
  );
  addTearDown(db.close);
  return db;
}

TripRecordHeader _header(TxnId start, {String tripId = 'line_hay.02'}) {
  final definition = sampleTrip(tripId);
  return TripRecordHeader(
    startTxn: start,
    tripId: tripId,
    contentVersion: 3,
    definition: definition,
    seed: definition.seed,
    params: bundledParams(definition.lineId),
    createdAtMs: testEpochMs,
  );
}

Future<int> _count(AppDatabase db, String table) async =>
    (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle())
        .read<int>('n');

void main() {
  final a = txnIdOf(1);
  final b = txnIdOf(2);

  test('create, append and load: commands in order, the last clock', () async {
    final records = DriftTripRecords(_memoryDb());
    expect(await records.create(_header(a)), isTrue);
    final commands = [
      const LoggedCommand(0, PickFromTray(100)),
      const LoggedCommand(33, PickFromTray(50)),
      const LoggedCommand(66, ReturnHand()),
      const LoggedCommand(99, PickFromTray(500)),
    ];
    for (final command in commands) {
      expect(await records.appendCommand(a, command), isTrue);
    }
    final stored = (await records.load(a))!;
    expect(stored.tripId, 'line_hay.02');
    expect(stored.contentVersion, 3);
    expect(stored.tMs, 99);
    expect(stored.commandJsons, [
      for (final c in commands) jsonEncode(c.toJson()),
    ]);
    expect(stored.intents, isEmpty);
    expect(
      stored.toReplayRecord().commandLog.map((c) => c.toJson()),
      commands.map((c) => c.toJson()),
    );
    expect(await records.load(b), isNull);
  });

  test('saveClock moves the clock only', () async {
    final records = DriftTripRecords(_memoryDb());
    await records.create(_header(a));
    await records.appendCommand(a, const LoggedCommand(33, PickFromTray(50)));
    await records.saveClock(a, 4950);
    final stored = (await records.load(a))!;
    expect(stored.tMs, 4950);
    expect(stored.commandJsons, hasLength(1));
  });

  test('a booster use writes the command and the intent together', () async {
    final records = DriftTripRecords(_memoryDb());
    await records.create(_header(a));
    final intent = TripIntent(
      requestTxn: txnIdOf(9),
      startTxn: a,
      booster: BoosterId.changeBag,
    );
    expect(
      await records.appendBoosterUse(
        a,
        const LoggedCommand(66, UseBooster(BoosterId.changeBag)),
        intent,
      ),
      isTrue,
    );
    var stored = (await records.load(a))!;
    expect(stored.commandJsons, hasLength(1));
    expect(stored.intents, [intent]);
    expect(stored.tMs, 66);

    await records.deleteIntent(intent.requestTxn);
    stored = (await records.load(a))!;
    expect(stored.intents, isEmpty);
    expect(stored.commandJsons, hasLength(1));
  });

  test(
    'a kill between the command row and the intent leaves neither',
    () async {
      final db = _memoryDb();
      final records = DriftTripRecords(
        db,
        onKillPoint: (point) {
          if (point == TripKillPoint.boosterCommandRow) throw const _Kill();
        },
      );
      await records.create(_header(a));
      await expectLater(
        records.appendBoosterUse(
          a,
          const LoggedCommand(66, UseBooster(BoosterId.wakeAll)),
          TripIntent(
            requestTxn: txnIdOf(9),
            startTxn: a,
            booster: BoosterId.wakeAll,
          ),
        ),
        throwsA(isA<_Kill>()),
      );
      final stored = (await DriftTripRecords(db).load(a))!;
      expect(stored.commandJsons, isEmpty);
      expect(stored.intents, isEmpty);
      expect(stored.tMs, 0);
    },
  );

  test('delete removes the record, its commands and its intents', () async {
    final db = _memoryDb();
    final records = DriftTripRecords(db);
    await records.create(_header(a));
    await records.create(_header(b));
    await records.appendBoosterUse(
      a,
      const LoggedCommand(0, UseBooster(BoosterId.changeBag)),
      TripIntent(
        requestTxn: txnIdOf(9),
        startTxn: a,
        booster: BoosterId.changeBag,
      ),
    );
    await records.appendCommand(b, const LoggedCommand(0, PickFromTray(50)));
    await records.delete(a);
    expect(await records.load(a), isNull);
    expect((await records.load(b))!.commandJsons, hasLength(1));
    expect(await _count(db, 'trip_intent'), 0);
    expect(await _count(db, 'trip_record_command'), 1);
  });

  test('deleteAllExcept keeps one record, or none', () async {
    final db = _memoryDb();
    final records = DriftTripRecords(db);
    for (final start in [a, b, txnIdOf(3)]) {
      await records.create(_header(start));
      await records.appendCommand(
        start,
        const LoggedCommand(0, PickFromTray(50)),
      );
    }
    // An intent whose record is gone.
    await records.appendBoosterUse(
      txnIdOf(3),
      const LoggedCommand(33, UseBooster(BoosterId.changeBag)),
      TripIntent(
        requestTxn: txnIdOf(9),
        startTxn: txnIdOf(3),
        booster: BoosterId.changeBag,
      ),
    );
    await records.deleteAllExcept(b);
    expect(await records.load(a), isNull);
    expect(await records.load(txnIdOf(3)), isNull);
    expect(await records.load(b), isNotNull);
    expect(await _count(db, 'trip_intent'), 0);
    expect(await _count(db, 'trip_record_command'), 1);

    await records.deleteAllExcept(null);
    expect(await _count(db, 'trip_record'), 0);
    expect(await _count(db, 'trip_record_command'), 0);
  });

  test('the stored record rebuilds to the live state at its clock', () async {
    final fixture = loadFixture('sample__line_hay_02_three_stars');
    final records = DriftTripRecords(_memoryDb());
    await records.create(
      TripRecordHeader(
        startTxn: a,
        tripId: fixture.definition.tripId,
        contentVersion: 1,
        definition: fixture.definition,
        seed: fixture.seed,
        params: fixture.params,
        createdAtMs: testEpochMs,
      ),
    );
    final live = TripEngine.start(
      fixture.definition,
      fixture.params,
      seed: fixture.seed,
    );
    final half = fixture.commandLog.length ~/ 2;
    for (final entry in fixture.commandLog.take(half)) {
      live.stepTo(entry.tMs);
      expect(live.apply(entry.command), isA<Accepted>());
      unawaited(records.appendCommand(a, live.commandLog.last));
    }
    live.stepTo(live.state.tMs + 990);
    unawaited(records.saveClock(a, live.state.tMs));

    final stored = (await records.load(a))!;
    // A rebuilt trip comes back paused.
    final rebuilt = TripEngine.rebuild(stored.toReplayRecord())..resume();
    expect(rebuilt.state.toJson(), live.state.toJson());
  });

  test('writes issued without waiting land in order', () async {
    final records = DriftTripRecords(_memoryDb());
    unawaited(records.create(_header(a)));
    for (var i = 0; i < 30; i++) {
      unawaited(
        records.appendCommand(a, LoggedCommand(i * 33, const PickFromTray(50))),
      );
    }
    final stored = (await records.load(a))!;
    expect(stored.commandJsons, [
      for (var i = 0; i < 30; i++) jsonEncode([i * 33, 'PickFromTray', 50]),
    ]);
    expect(stored.tMs, 29 * 33);
  });

  test('a failed write stays queued and lands before the next', () async {
    final interceptor = FailingInterceptor();
    final records = DriftTripRecords(_memoryDb(interceptor: interceptor));
    await records.create(_header(a));
    interceptor.failInserts = true;
    expect(
      await records.appendCommand(a, const LoggedCommand(0, PickFromTray(50))),
      isFalse,
    );
    interceptor.failInserts = false;
    expect(
      await records.appendCommand(
        a,
        const LoggedCommand(33, PickFromTray(100)),
      ),
      isTrue,
    );
    final stored = (await records.load(a))!;
    expect(stored.commandJsons, [
      jsonEncode([0, 'PickFromTray', 50]),
      jsonEncode([33, 'PickFromTray', 100]),
    ]);
  });

  test('a record that does not read is refused on rebuild', () {
    final stored = StoredTrip(
      startTxn: a,
      tripId: 'line_hay.01',
      contentVersion: 1,
      definitionJson: '{"broken": true}',
      seed: 1,
      paramsJson: '{}',
      commandJsons: const [],
      tMs: 0,
      createdAtMs: 0,
      intents: const [],
    );
    expect(stored.toReplayRecord, throwsA(isA<RebuildRefused>()));
  });
}
