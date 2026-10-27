// A database file as an older app version wrote it, for the upgrade tests:
// the generated schema of that version, holding rows the current code
// wrote, minus the columns that version didn't have.
import 'package:drift_dev/api/migrations_native.dart';
import 'package:wassal/core/storage/app_database.dart';

import '../drift/app/generated/schema.dart';

final olderSchemas = SchemaVerifier(GeneratedHelper());

/// The app's database over a file at schema [version] holding [rows] (table
/// to rows, as `dumpTables` gives them). Opening it runs the upgrade steps.
Future<AppDatabase> olderFile(
  int version,
  Map<String, List<Map<String, Object?>>> rows,
) async {
  final older = await olderSchemas.schemaAt(version);
  final raw = older.rawDatabase;
  for (final MapEntry(key: table, value: tableRows) in rows.entries) {
    final columns = {
      for (final c in raw.select('PRAGMA table_info($table)'))
        c['name'] as String,
    };
    raw.execute('DELETE FROM $table');
    for (final row in tableRows) {
      final kept = {
        for (final MapEntry(:key, :value) in row.entries)
          if (columns.contains(key)) key: value,
      };
      raw.execute(
        'INSERT INTO $table (${kept.keys.join(', ')}) '
        'VALUES (${List.filled(kept.length, '?').join(', ')})',
        kept.values.toList(),
      );
    }
  }
  return AppDatabase(older.newConnection());
}
