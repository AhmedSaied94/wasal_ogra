import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wassal/core/economy/domain/rules.dart';
import 'package:wassal/core/economy/drift_economy_store.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/storage/app_database.dart';
import 'package:wassal/core/storage/connection.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../../helpers/economy.dart';
import '../../helpers/pump_app.dart';

// The debug fold check (research R5): a debug build refuses a file whose
// tables aren't the fold of its base and ops.

final _l10n = lookupAppLocalizations(const Locale('ar'));

/// A file with a few ops in it.
Future<File> _playedFile() async {
  final file = tempDbFile();
  final e = await testEconomy(dbFile: file);
  final start = e.service.newRequestId();
  await e.service.startTrip(start, tripId: 'line_hay.01');
  await e.service.recordResult(
    e.service.newRequestId(),
    start: start,
    result: tripResult(tripId: 'line_hay.01', earnings: 12),
  );
  await e.close();
  return file;
}

void _tamper(File file, String sql) {
  sqlite3.open(file.path)
    ..execute(sql)
    ..close();
}

AppDatabase _checked(File file) => AppDatabase(
  NativeDatabase(file, setup: configureConnection),
  openCheck: (db) =>
      DriftEconomyStore(db).checkProjection(const ProductionRules()),
);

void main() {
  test('a consistent file opens', () async {
    final file = await _playedFile();
    final db = _checked(file);
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
  });

  for (final (what, sql) in [
    ('a JENEHAT balance', 'UPDATE wallet SET jenehat = 999'),
    ('a fuel count', 'UPDATE wallet SET fuel = 1'),
    ('a progress row', 'UPDATE trip_progress SET plays = 7'),
    (
      'an op that was never applied',
      "UPDATE ledger_ops SET jenehat_delta = 3 WHERE op_type = 'trip_result'",
    ),
  ]) {
    test('a file with $what changed by hand fails to open', () async {
      final file = await _playedFile();
      _tamper(file, sql);
      final db = _checked(file);
      addTearDown(db.close);
      await expectLater(
        db.customSelect('SELECT 1').get(),
        throwsA(isA<ProjectionMismatch>()),
      );
    });
  }

  testWidgets('the mismatch surfaces as the boot error', (tester) async {
    final file = (await tester.runAsync(_playedFile))!;
    _tamper(file, 'UPDATE wallet SET jenehat = 999');
    await pumpWassalApp(
      tester,
      economy: [
        uptimeSourceProvider.overrideWithValue(FakeUptimeSource()),
        databaseOpenerProvider.overrideWithValue(
          () async => NativeDatabase(file, setup: configureConnection),
        ),
      ],
    );
    expect(currentLocation(tester), '/boot');
    expect(find.text(_l10n.bootErrorMessage), findsOneWidget);
  });
}
