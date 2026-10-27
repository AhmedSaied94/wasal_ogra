import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_source.dart';

// Every change to the economy goes through the one service, and only its
// store writes the tables (specs/007-m05-local-economy FR-013, FR-015): the
// client side of constitution IV's scan for direct Wallet writes.

const _store = 'lib/core/economy/drift_economy_store.dart';
const _providers = 'lib/core/economy/economy_providers.dart';
const _storage = 'lib/core/storage/';

// The trip screen's record store (specs/008-m02-trip-screen/contracts/
// trip-records.md "Guards"): only it writes the trip tables, and it never
// writes the economy's.
const _tripStore = 'lib/features/trip/data/drift_trip_records.dart';
const _tripProviders = 'lib/features/trip/trip_providers.dart';
const _tripTables = [
  'tripRecordTable',
  'tripRecordCommandTable',
  'tripIntentTable',
];

// The account's store (specs/011-m06-identity-sync, data-model.md "Tables
// (schema v3)"): only it writes the account and the last bootstrap, and it
// never writes the economy's or the trip's tables.
const _accountStore = 'lib/core/account/drift_account_store.dart';
const _accountProviders = 'lib/core/account/account_providers.dart';
const _accountTables = ['accountTable', 'serverInfoTable'];

const _tables = [
  'ledgerOps',
  'walletTable',
  'inventoryTable',
  'ownershipTable',
  'tripProgressTable',
  'tripSessionTable',
  'projectionBaseTable',
  'clockAnchorTable',
];

final _importsDatabase = RegExp(
  r'''^[ \t]*import\s+['"][^'"]*app_database\.dart['"]''',
  multiLine: true,
);

final _tableWrite = RegExp(
  '\\b(?:into|update|delete)\\(\\s*(?:[\\w.]+\\.)?(?:${_tables.join('|')})\\b',
);
final _tripTableWrite = RegExp(
  '\\b(?:into|update|delete)\\(\\s*(?:[\\w.]+\\.)?(?:${_tripTables.join('|')})\\b',
);
final _accountTableWrite = RegExp(
  '\\b(?:into|update|delete)\\(\\s*(?:[\\w.]+\\.)?(?:${_accountTables.join('|')})\\b',
);
final _rawWrite = RegExp(
  r'\.batch\(|\bcustomStatement\(|\bcustomUpdate\(|\bcustomInsert\(',
);
final _ledgerUpdate = RegExp(r'\bupdate\(\s*(?:[\w.]+\.)?ledgerOps\b');
final _ledgerDelete = RegExp(r'\bdelete\(\s*(?:[\w.]+\.)?ledgerOps\b');
final _ledgerCompanion = RegExp(r'\bLedgerOpsCompanion\(');

String _path(File file) => file.path.replaceAll(r'\', '/');

bool _mayImportDatabase(String path) =>
    path.startsWith(_storage) ||
    path == _store ||
    path == _providers ||
    path == _tripStore ||
    path == _tripProviders ||
    path == _accountStore ||
    path == _accountProviders;

bool _mayWrite(String path) => path.startsWith(_storage) || path == _store;

/// Lines of [source] that write an economy table directly.
List<String> directWrites(String source) {
  final lines = stripComments(source).split('\n');
  return [
    for (var i = 0; i < lines.length; i++)
      if (_tableWrite.hasMatch(lines[i]) || _rawWrite.hasMatch(lines[i]))
        '${i + 1}: ${lines[i].trim()}',
  ];
}

/// Lines of [source] that write an account table.
List<String> accountTableWrites(String source) {
  final lines = stripComments(source).split('\n');
  return [
    for (var i = 0; i < lines.length; i++)
      if (_accountTableWrite.hasMatch(lines[i]) || _rawWrite.hasMatch(lines[i]))
        '${i + 1}: ${lines[i].trim()}',
  ];
}

/// Lines of [source] that write a trip table.
List<String> tripTableWrites(String source) {
  final lines = stripComments(source).split('\n');
  return [
    for (var i = 0; i < lines.length; i++)
      if (_tripTableWrite.hasMatch(lines[i]) || _rawWrite.hasMatch(lines[i]))
        '${i + 1}: ${lines[i].trim()}',
  ];
}

/// The body of the method [name] declared in [source], braces included, or
/// null. Calls of it are skipped: a declaration's parameters are followed by
/// its body.
String? methodBody(String source, String name) {
  final start = RegExp('\\b$name\\([^()]*\\)\\s*(?:async\\s*)?\\{')
      .firstMatch(source);
  if (start == null) return null;
  final open = start.end - 1;
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}' && --depth == 0) {
      return source.substring(open, i + 1);
    }
  }
  return null;
}

/// What lies between the parenthesis at [open] in [source] and its match.
String parenthesized(String source, int open) {
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '(') depth++;
    if (source[i] == ')' && --depth == 0) {
      return source.substring(open + 1, i);
    }
  }
  return source.substring(open + 1);
}

/// What breaks the ledger's append-only rule in the store's [source].
List<String> ledgerRuleBreaks(String source) {
  final stripped = stripComments(source);
  final body = methodBody(stripped, '_setSyncStatus') ?? '';
  final breaks = <String>[];
  final updates = _ledgerUpdate.allMatches(stripped).length;
  if (updates != _ledgerUpdate.allMatches(body).length) {
    breaks.add('update(ledgerOps) outside _setSyncStatus');
  }
  final companions = _ledgerCompanion.allMatches(stripped).length;
  if (companions != _ledgerCompanion.allMatches(body).length) {
    breaks.add('LedgerOpsCompanion( outside _setSyncStatus');
  }
  for (final match in _ledgerCompanion.allMatches(body)) {
    final args = parenthesized(body, match.end - 1);
    for (final arg in RegExp(r'(\w+):').allMatches(args)) {
      if (arg[1] != 'syncStatus' && arg[1] != 'syncReason') {
        breaks.add('LedgerOpsCompanion sets ${arg[1]}');
      }
    }
  }
  if (_ledgerDelete.hasMatch(stripped)) breaks.add('delete(ledgerOps)');
  return breaks;
}

void main() {
  final files = libDartFiles().where((f) => !f.path.endsWith('.g.dart'));

  test('the store exists, so the rules below scan real code', () {
    expect(File(_store).existsSync(), isTrue);
  });

  test('only storage, the store and the providers import the database', () {
    final violations = [
      for (final file in files)
        if (!_mayImportDatabase(_path(file)) &&
            _importsDatabase.hasMatch(stripComments(file.readAsStringSync())))
          _path(file),
    ];
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('nothing but storage and the store writes an economy table', () {
    final violations = [
      for (final file in files)
        if (!_mayWrite(_path(file)))
          for (final hit in directWrites(file.readAsStringSync()))
            '${_path(file)}:$hit',
    ];
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('the trip store exists, so the trip rules scan real code', () {
    expect(File(_tripStore).existsSync(), isTrue);
  });

  test('nothing but storage and the trip store writes a trip table', () {
    final violations = [
      for (final file in files)
        if (!_path(file).startsWith(_storage) && _path(file) != _tripStore)
          for (final hit in tripTableWrites(file.readAsStringSync()))
            '${_path(file)}:$hit',
    ];
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('the trip store writes no economy table', () {
    expect(directWrites(File(_tripStore).readAsStringSync()), isEmpty);
  });

  test('the account store exists, so the account rules scan real code', () {
    expect(File(_accountStore).existsSync(), isTrue);
  });

  test('nothing but storage and the account store writes an account table', () {
    final violations = [
      for (final file in files)
        if (!_path(file).startsWith(_storage) && _path(file) != _accountStore)
          for (final hit in accountTableWrites(file.readAsStringSync()))
            '${_path(file)}:$hit',
    ];
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('the account store writes no economy or trip table', () {
    final source = File(_accountStore).readAsStringSync();
    expect(directWrites(source), isEmpty);
    expect(tripTableWrites(source), isEmpty);
  });

  test('ledger_ops rows change only in their sync columns', () {
    expect(ledgerRuleBreaks(File(_store).readAsStringSync()), isEmpty);
    final deletes = [
      for (final file in files)
        if (_ledgerDelete.hasMatch(stripComments(file.readAsStringSync())))
          _path(file),
    ];
    expect(deletes, isEmpty);
  });

  test('the scans catch direct writes and ignore the rest', () {
    expect(directWrites('db.into(db.walletTable).insert(x);'), hasLength(1));
    expect(directWrites('await update(clockAnchorTable).write(x);'), [
      '1: await update(clockAnchorTable).write(x);',
    ]);
    expect(directWrites('_db.delete(_db.inventoryTable).go();'), hasLength(1));
    expect(directWrites('db.batch((b) {});'), hasLength(1));
    expect(directWrites("db.customStatement('DELETE');"), hasLength(1));
    expect(directWrites('db.select(db.walletTable).get();'), isEmpty);
    expect(directWrites('map.update(key, (v) => v);'), isEmpty);
    expect(directWrites('await file.delete();'), isEmpty);
    expect(directWrites('// db.into(db.walletTable)'), isEmpty);
  });

  test('the trip scan catches trip-table writes and ignores the rest', () {
    expect(
      tripTableWrites('db.into(db.tripRecordTable).insert(x);'),
      hasLength(1),
    );
    expect(
      tripTableWrites('await update(tripRecordCommandTable).write(x);'),
      hasLength(1),
    );
    expect(
      tripTableWrites('_db.delete(_db.tripIntentTable).go();'),
      hasLength(1),
    );
    expect(tripTableWrites('db.batch((b) {});'), hasLength(1));
    expect(tripTableWrites('db.select(db.tripRecordTable).get();'), isEmpty);
    expect(tripTableWrites('// db.into(db.tripIntentTable)'), isEmpty);
    expect(directWrites('db.into(db.tripRecordTable).insert(x);'), isEmpty);
  });

  test(
    'the account scan catches account-table writes and ignores the rest',
    () {
      expect(
        accountTableWrites('db.into(db.accountTable).insert(x);'),
        hasLength(1),
      );
      expect(
        accountTableWrites('await _db.update(_db.serverInfoTable).write(x);'),
        hasLength(1),
      );
      expect(accountTableWrites('db.select(db.accountTable).get();'), isEmpty);
      expect(accountTableWrites('// db.into(db.serverInfoTable)'), isEmpty);
      expect(directWrites('db.into(db.accountTable).insert(x);'), isEmpty);
    },
  );

  test('the ledger scan catches every way around _setSyncStatus', () {
    const ok = '''
Future<bool> _setSyncStatus(TxnId id) async {
  await (_db.update(_db.ledgerOps)..where((t) => t.x)).write(
    LedgerOpsCompanion(syncStatus: Value(s), syncReason: Value(r)),
  );
  return true;
}''';
    expect(ledgerRuleBreaks(ok), isEmpty);
    expect(
      ledgerRuleBreaks('$ok\nvoid f() { _db.update(_db.ledgerOps); }'),
      contains('update(ledgerOps) outside _setSyncStatus'),
    );
    expect(
      ledgerRuleBreaks(ok.replaceFirst('syncReason:', 'payload:')),
      hasLength(1),
    );
    expect(
      ledgerRuleBreaks('$ok\nvoid f() { _db.delete(_db.ledgerOps).go(); }'),
      contains('delete(ledgerOps)'),
    );
  });
}
