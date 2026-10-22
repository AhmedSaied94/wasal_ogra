import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wassal/core/economy/drift_economy_store.dart';
import 'package:wassal/core/storage/app_database.dart';
import 'package:wassal/core/storage/connection.dart';

import '../../drift/app/generated/schema.dart';
import '../../helpers/economy.dart';

// Schema v2 adds the trip's records (specs/008-m02-trip-screen,
// contracts/trip-records.md "Schema"). A player's v1 file keeps every
// economy row.

const _tripTables = ['trip_record', 'trip_record_command', 'trip_intent'];

void main() {
  test('a v1 file with an economy opens as v2, every row kept', () async {
    final file = tempDbFile();
    final economy = await testEconomy(dbFile: file);
    await seedOps(
      economy.db,
      DriftEconomyStore(economy.db),
      count: 40,
      bonat: 25,
    );
    final rows = await dumpTables(economy.db);
    await economy.close();

    // The same file as v1 wrote it: without the trip tables, at version 1.
    final raw = sqlite3.open(file.path);
    for (final table in _tripTables) {
      raw.execute('DROP TABLE $table');
    }
    raw
      ..execute('PRAGMA user_version = 1')
      ..close();

    final db = AppDatabase(NativeDatabase(file, setup: configureConnection));
    addTearDown(db.close);
    await SchemaVerifier(GeneratedHelper()).migrateAndValidate(db, 2);
    expect(await dumpTables(db), rows);
    for (final table in _tripTables) {
      expect(await db.customSelect('SELECT * FROM $table').get(), isEmpty);
    }
  });
}
