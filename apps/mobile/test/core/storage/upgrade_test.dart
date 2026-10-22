import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/trusted_time.dart';
import 'package:wassal/core/storage/app_database.dart';
import 'package:wassal/core/storage/connection.dart';

import '../../helpers/economy.dart';

// Schema upgrades are all or nothing (FR-003): a step that fails or is
// killed leaves the file at the version before it, whole, and that
// version's code opens it. drift_schemas/ and test/drift/ cover v1's shape.

/// A later app, with one step to v2.
final class _V2 extends AppDatabase {
  _V2(super.e, this._step);

  final Future<void> Function(Migrator m) _step;

  @override
  int get schemaVersion => 2;

  @override
  Map<int, UpgradeStep> get upgradeSteps => {2: _step};
}

/// Two versions later, one step each.
final class _V3 extends AppDatabase {
  _V3(super.e, this._toV2, this._toV3);

  final Future<void> Function(Migrator m) _toV2;
  final Future<void> Function(Migrator m) _toV3;

  @override
  int get schemaVersion => 3;

  @override
  Map<int, UpgradeStep> get upgradeSteps => {2: _toV2, 3: _toV3};
}

/// The process dying mid-step.
final class _Kill implements Exception {
  const _Kill();
}

/// A later app with no step to v2.
final class _V2WithoutStep extends AppDatabase {
  _V2WithoutStep(super.e);

  @override
  int get schemaVersion => 2;
}

final _first = FirstOpen(
  state: EconomyState.newPlayer(fuelMax: 5, nowMs: testEpochMs),
  anchor: firstAnchor(null, testEpochMs),
);

QueryExecutor _connect(File file) =>
    NativeDatabase(file, setup: configureConnection);

/// A v1 file with an economy in it, and its rows.
Future<(File, Map<String, List<Map<String, Object?>>>)> _v1File() async {
  final file = tempDbFile();
  final economy = await testEconomy(
    dbFile: file,
    firstState: (nowMs) =>
        EconomyState.newPlayer(fuelMax: 5, nowMs: nowMs).copyWith(bonat: 40),
  );
  final start = economy.service.newRequestId();
  await economy.service.startTrip(start, tripId: 'line_hay.01');
  await economy.service.recordResult(
    economy.service.newRequestId(),
    start: start,
    result: tripResult(tripId: 'line_hay.01'),
  );
  final rows = await dumpTables(economy.db);
  await economy.close();
  return (file, rows);
}

Future<Object?> _userVersion(AppDatabase db) async =>
    (await db.customSelect('PRAGMA user_version').getSingle())
        .data
        .values
        .single;

Future<bool> _hasTable(AppDatabase db, String name) async =>
    (await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
              variables: [Variable(name)],
            )
            .get())
        .isNotEmpty;

/// The v1 code opens [file]; its rows and version are as they were.
Future<void> _expectWholeV1(
  File file,
  Map<String, List<Map<String, Object?>>> rows,
) async {
  final db = AppDatabase(_connect(file), firstOpen: () => _first);
  addTearDown(db.close);
  expect(await _userVersion(db), 1);
  expect(await _hasTable(db, 'extra'), isFalse);
  expect(await dumpTables(db), rows);
  await db.close();
}

void main() {
  test('a step that fails leaves v1 whole, and v1 opens it', () async {
    final (file, rows) = await _v1File();
    final db = _V2(_connect(file), (m) async {
      await m.database.customStatement('CREATE TABLE extra (id INTEGER)');
      await m.database.customStatement('UPDATE wallet SET jenehat = 999');
      throw StateError('the step failed');
    });
    addTearDown(db.close);
    await expectLater(db.customSelect('SELECT 1').get(), throwsStateError);
    await db.close();

    await _expectWholeV1(file, rows);
  });

  test('a kill in a later step keeps the steps before it', () async {
    final (file, rows) = await _v1File();
    final db = _V3(
      _connect(file),
      (m) async {
        await m.database.customStatement('CREATE TABLE extra (id INTEGER)');
      },
      (m) async {
        await m.database.customStatement('CREATE TABLE later (id INTEGER)');
        throw const _Kill();
      },
    );
    addTearDown(db.close);
    await expectLater(db.customSelect('SELECT 1').get(), throwsA(isA<_Kill>()));
    await db.close();

    // At v2, whole: the v2 code opens it with nothing to do.
    final v2 = _V2(_connect(file), (_) => fail('v2 is already applied'));
    addTearDown(v2.close);
    expect(await _userVersion(v2), 2);
    expect(await _hasTable(v2, 'extra'), isTrue);
    expect(await _hasTable(v2, 'later'), isFalse);
    expect(await dumpTables(v2), rows);
  });

  test('a step that succeeds commits with its version', () async {
    final (file, rows) = await _v1File();
    final db = _V2(_connect(file), (m) async {
      await m.database.customStatement('CREATE TABLE extra (id INTEGER)');
    });
    addTearDown(db.close);
    expect(await _userVersion(db), 2);
    expect(await _hasTable(db, 'extra'), isTrue);
    expect(await dumpTables(db), rows);
  });

  test('a version with no step refuses to open, and leaves v1 whole', () async {
    final (file, rows) = await _v1File();
    final db = _V2WithoutStep(_connect(file));
    addTearDown(db.close);
    await expectLater(db.customSelect('SELECT 1').get(), throwsStateError);
    await db.close();

    await _expectWholeV1(file, rows);
  });
}
