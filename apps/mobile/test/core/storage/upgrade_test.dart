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
// version's code opens it. drift_schemas/ and test/drift/ cover each
// version's shape. These run one and two versions past the current one.

/// The app's schema version.
final _current = AppDatabase(NativeDatabase.memory()).schemaVersion;

/// A later app, with one step past the current version.
final class _Next extends AppDatabase {
  _Next(super.e, this._step);

  final Future<void> Function(Migrator m) _step;

  @override
  int get schemaVersion => _current + 1;

  @override
  Map<int, UpgradeStep> get upgradeSteps => {
    ...super.upgradeSteps,
    _current + 1: _step,
  };
}

/// Two versions later, one step each.
final class _NextTwo extends AppDatabase {
  _NextTwo(super.e, this._toNext, this._toLater);

  final Future<void> Function(Migrator m) _toNext;
  final Future<void> Function(Migrator m) _toLater;

  @override
  int get schemaVersion => _current + 2;

  @override
  Map<int, UpgradeStep> get upgradeSteps => {
    ...super.upgradeSteps,
    _current + 1: _toNext,
    _current + 2: _toLater,
  };
}

/// The process dying mid-step.
final class _Kill implements Exception {
  const _Kill();
}

/// A later app with no step to its version.
final class _NextWithoutStep extends AppDatabase {
  _NextWithoutStep(super.e);

  @override
  int get schemaVersion => _current + 1;
}

final _first = FirstOpen(
  state: EconomyState.newPlayer(fuelMax: 5, nowMs: testEpochMs),
  anchor: firstAnchor(null, testEpochMs),
);

QueryExecutor _connect(File file) =>
    NativeDatabase(file, setup: configureConnection);

/// A file at the current version with an economy in it, and its rows.
Future<(File, Map<String, List<Map<String, Object?>>>)> _currentFile() async {
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

/// The current code opens [file]; its rows and version are as they were.
Future<void> _expectWhole(
  File file,
  Map<String, List<Map<String, Object?>>> rows,
) async {
  final db = AppDatabase(_connect(file), firstOpen: () => _first);
  addTearDown(db.close);
  expect(await _userVersion(db), _current);
  expect(await _hasTable(db, 'extra'), isFalse);
  expect(await dumpTables(db), rows);
  await db.close();
}

void main() {
  test(
    'a step that fails leaves the file whole, and its version opens it',
    () async {
      final (file, rows) = await _currentFile();
      final db = _Next(_connect(file), (m) async {
        await m.database.customStatement('CREATE TABLE extra (id INTEGER)');
        await m.database.customStatement('UPDATE wallet SET jenehat = 999');
        throw StateError('the step failed');
      });
      addTearDown(db.close);
      await expectLater(db.customSelect('SELECT 1').get(), throwsStateError);
      await db.close();

      await _expectWhole(file, rows);
    },
  );

  test('a kill in a later step keeps the steps before it', () async {
    final (file, rows) = await _currentFile();
    final db = _NextTwo(
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

    // One version on, whole: that version's code opens it with nothing to do.
    final next = _Next(
      _connect(file),
      (_) => fail('the step is already applied'),
    );
    addTearDown(next.close);
    expect(await _userVersion(next), _current + 1);
    expect(await _hasTable(next, 'extra'), isTrue);
    expect(await _hasTable(next, 'later'), isFalse);
    expect(await dumpTables(next), rows);
  });

  test('a step that succeeds commits with its version', () async {
    final (file, rows) = await _currentFile();
    final db = _Next(_connect(file), (m) async {
      await m.database.customStatement('CREATE TABLE extra (id INTEGER)');
    });
    addTearDown(db.close);
    expect(await _userVersion(db), _current + 1);
    expect(await _hasTable(db, 'extra'), isTrue);
    expect(await dumpTables(db), rows);
  });

  test(
    'a version with no step refuses to open, and leaves the file whole',
    () async {
      final (file, rows) = await _currentFile();
      final db = _NextWithoutStep(_connect(file));
      addTearDown(db.close);
      await expectLater(db.customSelect('SELECT 1').get(), throwsStateError);
      await db.close();

      await _expectWhole(file, rows);
    },
  );
}
