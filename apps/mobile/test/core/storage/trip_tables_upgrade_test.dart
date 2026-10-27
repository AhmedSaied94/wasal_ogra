import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/drift_economy_store.dart';

import '../../helpers/economy.dart';
import '../../helpers/older_schema.dart';

// Schema v2 adds the trip's records (specs/008-m02-trip-screen,
// contracts/trip-records.md "Schema"). A player's v1 file keeps every
// economy row, through every later step too.

const _tripTables = ['trip_record', 'trip_record_command', 'trip_intent'];

void main() {
  test('a v1 file with an economy opens as the current version, every row '
      'kept', () async {
    final economy = await testEconomy();
    await seedOps(
      economy.db,
      DriftEconomyStore(economy.db),
      count: 40,
      bonat: 25,
    );
    final rows = await dumpTables(economy.db);

    final db = await olderFile(1, rows);
    addTearDown(db.close);
    await olderSchemas.migrateAndValidate(db, db.schemaVersion);
    expect(await dumpTables(db), rows);
    for (final table in _tripTables) {
      expect(await db.customSelect('SELECT * FROM $table').get(), isEmpty);
    }
  });
}
