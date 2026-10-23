import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/storage/app_database.dart';

import 'generated/schema.dart';

// The schema the code creates is the one exported for its version, and a
// file at an exported version opens without a migration. The steps between
// versions are tested in migration_test.dart.

void main() {
  final verifier = SchemaVerifier(GeneratedHelper());

  test('a new database has the exported v2 schema', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 2);
  });

  test(
    'a v2 database opens without a migration and keeps its schema',
    () async {
      final db = AppDatabase(await verifier.startAt(2));
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 2);
    },
  );
}
