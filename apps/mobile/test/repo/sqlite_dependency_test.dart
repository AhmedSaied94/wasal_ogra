import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// SQLite comes from sqlite3 3.x's build hook, not from the end-of-life
// sqlite3_flutter_libs stubs (specs/007-m05-local-economy, research R1).

void main() {
  final lock = File('pubspec.lock').readAsStringSync();

  String? versionOf(String package) => RegExp(
    '^  $package:\\n(?:    .*\\n)*?    version: "([^"]+)"',
    multiLine: true,
  ).firstMatch(lock)?[1];

  test('sqlite3 is locked at major version 3', () {
    expect(versionOf('sqlite3'), startsWith('3.'));
  });

  test('no plugin bundles another SQLite', () {
    for (final package in [
      'sqlite3_flutter_libs',
      'sqlcipher_flutter_libs',
      'drift_flutter',
    ]) {
      expect(versionOf(package), isNull, reason: package);
    }
  });
}
