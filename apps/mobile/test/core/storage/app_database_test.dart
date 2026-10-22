import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:content_models/content_models.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/trusted_time.dart';
import 'package:wassal/core/storage/app_database.dart';
import 'package:wassal/core/storage/connection.dart';

import '../../helpers/economy.dart';

// The app database's file, schema and constraints (contracts/storage.md,
// data-model.md "Tables"), on a real file.

const _tables = {
  'ledger_ops',
  'wallet',
  'inventory',
  'ownership',
  'trip_progress',
  'trip_session',
  'projection_base',
  'clock_anchor',
  // v2: the trip's records (specs/008-m02-trip-screen).
  'trip_record',
  'trip_record_command',
  'trip_intent',
};

final _anchor = firstAnchor(
  const BootSnapshot(elapsedRealtimeMs: testBootElapsedMs, bootCount: 3),
  testEpochMs,
);

final _player = EconomyState.newPlayer(fuelMax: 5, nowMs: _anchor.anchorMs);

AppDatabase _open(File file) => AppDatabase(
  NativeDatabase(file, setup: configureConnection),
  firstOpen: () => FirstOpen(state: _player, anchor: _anchor),
);

/// Opens [file] and runs the migration, closing it after the test.
Future<AppDatabase> _opened(File file) async {
  final db = _open(file);
  addTearDown(db.close);
  await db.customSelect('SELECT 1').get();
  return db;
}

Future<List<Map<String, Object?>>> _rows(AppDatabase db, String sql) async => [
  for (final row in await db.customSelect(sql).get()) row.data,
];

String _sha256(File file) => sha256.convert(file.readAsBytesSync()).toString();

void main() {
  group('first open', () {
    test('creates exactly the 11 tables', () async {
      final db = await _opened(tempDbFile());
      final names = await _rows(
        db,
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%'",
      );
      expect({for (final row in names) row['name']}, _tables);
    });

    test('writes the first rows', () async {
      final db = await _opened(tempDbFile());

      expect(await _rows(db, 'SELECT * FROM wallet'), [
        {
          'id': 1,
          'jenehat': 0,
          'bonat': 0,
          'fuel': 5,
          'fuel_counted_from_ms': _anchor.anchorMs,
          'fuel_unlimited_until_ms': null,
          'last_seq': 0,
        },
      ]);

      final session = await _rows(db, 'SELECT * FROM trip_session');
      expect(session, hasLength(1));
      expect(session.single['id'], 1);
      expect(
        ({...session.single}..remove('id')).values,
        everyElement(isNull),
        reason: 'no trip and no result yet',
      );

      expect(await _rows(db, 'SELECT * FROM projection_base'), [
        {
          'id': 1,
          'state': canonicalJson(_player.toJson()),
          'after_seq': 0,
          'kind': 'new_player',
          'state_version': null,
          'taken_at_ms': _anchor.anchorMs,
        },
      ]);

      expect(await _rows(db, 'SELECT * FROM clock_anchor'), [
        {
          'id': 1,
          'anchor_ms': testEpochMs,
          'anchor_elapsed_ms': testBootElapsedMs,
          'boot_count': 3,
          'source': 'device',
          'latest_trusted_ms': testEpochMs,
        },
      ]);

      for (final table in ['ledger_ops', 'inventory', 'ownership']) {
        expect(await _rows(db, 'SELECT * FROM $table'), isEmpty, reason: table);
      }
      expect(await _rows(db, 'SELECT * FROM trip_progress'), isEmpty);
    });

    test('holds a new player only', () {
      expect(
        () => FirstOpen(
          state: _player.copyWith(
            progress: const {
              'line_hay.01': TripProgress(bestStars: 1, plays: 1),
            },
          ),
          anchor: _anchor,
        ),
        throwsAssertionError,
      );
      expect(
        FirstOpen(
          state: _player.copyWith(bonat: 9),
          anchor: _anchor,
        ).state.bonat,
        9,
      );
    });

    test('stamps schema version 2', () async {
      final db = await _opened(tempDbFile());
      expect(await _rows(db, 'PRAGMA user_version'), [
        {'user_version': 2},
      ]);
    });
  });

  test('every connection is WAL, synchronous FULL, foreign keys on', () async {
    final db = await _opened(tempDbFile());
    expect(
      (await _rows(db, 'PRAGMA journal_mode')).single.values.single,
      'wal',
    );
    expect((await _rows(db, 'PRAGMA synchronous')).single.values.single, 2);
    expect((await _rows(db, 'PRAGMA foreign_keys')).single.values.single, 1);
  });

  test('every column is INTEGER or TEXT, never REAL', () async {
    final db = await _opened(tempDbFile());
    for (final table in _tables) {
      final columns = await _rows(db, 'PRAGMA table_info($table)');
      expect(columns, isNotEmpty, reason: table);
      for (final column in columns) {
        expect(
          column['type'],
          anyOf('INTEGER', 'TEXT'),
          reason: '$table.${column['name']}',
        );
      }
    }
  });

  group('CHECK constraints reject', () {
    late AppDatabase db;

    setUp(() async {
      db = await _opened(tempDbFile());
    });

    void rejects(String what, String sql) {
      test(what, () async {
        await expectLater(
          db.customStatement(sql),
          throwsA(isA<SqliteException>()),
        );
      });
    }

    const op =
        'INSERT INTO ledger_ops (txn_id, op_type, payload, occurred_at_ms, '
        'content_version, fuel_max, fuel_regen_minutes, sync_status) VALUES ';

    rejects('a negative jenehat', 'UPDATE wallet SET jenehat = -1');
    rejects('a negative bonat', 'UPDATE wallet SET bonat = -1');
    rejects('a negative fuel', 'UPDATE wallet SET fuel = -1');
    rejects(
      'a negative inventory count',
      "INSERT INTO inventory (booster_id, count) VALUES ('change_bag', -1)",
    );
    rejects(
      'a booster outside the four',
      "INSERT INTO inventory (booster_id, count) VALUES ('refuel_full', 1)",
    );
    rejects(
      'best_stars = 4',
      'INSERT INTO trip_progress (trip_id, best_stars, plays) '
          "VALUES ('line_hay.01', 4, 1)",
    );
    rejects(
      "sync_status = 'x'",
      "$op('a', 'trip_start', '{}', 0, 1, 5, 20, 'x')",
    );
    rejects("op_type = 'x'", "$op('a', 'x', '{}', 0, 1, 5, 20, 'pending')");
    rejects(
      'an ownership kind upgrade',
      'INSERT INTO ownership (kind, sku_id, acquired_at_ms, acquired_by) '
          "VALUES ('upgrade', 'x', 0, 'a')",
    );
    rejects(
      'a second wallet row',
      'INSERT INTO wallet (id, jenehat, bonat, fuel, fuel_counted_from_ms, '
          'last_seq) VALUES (2, 0, 0, 0, 0, 0)',
    );
    rejects(
      'a second trip_session row',
      'INSERT INTO trip_session (id) VALUES (2)',
    );
    rejects(
      'a second projection_base row',
      'INSERT INTO projection_base (id, state, after_seq, kind, taken_at_ms) '
          "VALUES (2, '{}', 0, 'new_player', 0)",
    );
    rejects(
      'a second clock_anchor row',
      'INSERT INTO clock_anchor (id, anchor_ms, anchor_elapsed_ms, source, '
          "latest_trusted_ms) VALUES (2, 0, 0, 'device', 0)",
    );
  });

  group('a file the app cannot open stays as it is', () {
    test('user_version 3 fails with DatabaseFromNewerApp', () async {
      final file = tempDbFile();
      final first = _open(file);
      await first.customSelect('SELECT 1').get();
      await first.close();
      sqlite3.open(file.path)
        ..execute('PRAGMA user_version = 3')
        ..close();
      final before = _sha256(file);

      final db = _open(file);
      addTearDown(db.close);
      await expectLater(
        db.customSelect('SELECT 1').get(),
        throwsA(
          isA<DatabaseFromNewerApp>()
              .having((e) => e.fileVersion, 'fileVersion', 3)
              .having((e) => e.appVersion, 'appVersion', 2),
        ),
      );
      await db.close();
      expect(_sha256(file), before);
    });

    test('random bytes fail to open', () async {
      final file = tempDbFile();
      final random = Random(20261022);
      file.writeAsBytesSync(
        Uint8List.fromList([
          for (var i = 0; i < 8192; i++) random.nextInt(256),
        ]),
      );
      final before = _sha256(file);

      final db = _open(file);
      addTearDown(db.close);
      await expectLater(db.customSelect('SELECT 1').get(), throwsA(anything));
      await db.close();
      expect(_sha256(file), before);
    });
  });
}
