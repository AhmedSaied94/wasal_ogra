// Where the app database lives and how it is opened (contracts/storage.md
// "The file and its connection").
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// `<app support>/db/`, which device backup leaves out (research R14).
const databaseDirName = 'db';
const databaseFileName = 'wassal.sqlite';

/// The database file, with its directory created if missing. Nothing
/// deletes, renames or recreates it (FR-004).
Future<File> appDatabaseFile() async {
  final support = await getApplicationSupportDirectory();
  final dir = Directory('${support.path}/$databaseDirName');
  await dir.create(recursive: true);
  return File('${dir.path}/$databaseFileName');
}

/// [file] opened on its own isolate, so no query blocks a frame (FR-005).
QueryExecutor openDatabaseFile(File file) =>
    NativeDatabase.createInBackground(file, setup: configureConnection);

/// The pragmas of every connection (research R2): readers don't wait for
/// the writer, and a committed operation survives a power cut.
void configureConnection(Database database) {
  database
    ..execute('PRAGMA journal_mode = WAL')
    ..execute('PRAGMA synchronous = FULL')
    ..execute('PRAGMA foreign_keys = ON');
}
