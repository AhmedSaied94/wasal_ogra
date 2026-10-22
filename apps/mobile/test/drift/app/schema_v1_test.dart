import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/storage/app_database.dart';

import 'generated/schema.dart';

// The schema the code creates is the one exported to
// drift_schemas/app/drift_schema_v1.json. With a single version there is no
// step to test yet; a v2 adds `make-migrations`' generated step tests here.

void main() {
  final verifier = SchemaVerifier(GeneratedHelper());

  test('a new database has the exported v1 schema', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 1);
  });

  test(
    'a v1 database opens without a migration and keeps its schema',
    () async {
      final db = AppDatabase(await verifier.startAt(1));
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 1);
    },
  );
}
