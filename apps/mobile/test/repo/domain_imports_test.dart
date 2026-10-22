import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_source.dart';

// Domain folders are pure Dart (constitution I): no Flutter, no plugin and no
// dart:io, so their rules run anywhere and stay deterministic. Each folder
// lists what it may import.

/// The content domain: the generated models only
/// (specs/006-m04-content-loader/contracts/content-source.md).
bool _contentAllowed(String uri) =>
    uri == 'dart:core' ||
    uri == 'dart:collection' ||
    uri.startsWith('package:content_models/');

/// The economy domain (specs/007-m05-local-economy, research R16): the
/// content domain, the trip engine's results, and its own folder.
bool _economyAllowed(String uri) =>
    _contentAllowed(uri) ||
    uri.startsWith('package:trip_engine/') ||
    uri.startsWith('package:wassal/core/content/domain/') ||
    uri.startsWith('package:wassal/core/economy/domain/') ||
    _sameFolder(uri);

/// A file of the same folder, by relative path.
bool _sameFolder(String uri) =>
    !uri.contains(':') && !uri.contains('/') && !uri.contains('..');

const _domains = <String, bool Function(String)>{
  'lib/core/content/domain': _contentAllowed,
  'lib/core/economy/domain': _economyAllowed,
};

final _directive = RegExp(
  r'''^[ \t]*(?:import|export)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

List<String> forbiddenImports(
  String source, [
  bool Function(String uri) allowed = _contentAllowed,
]) {
  final stripped = stripComments(source);
  return [
    for (final match in _directive.allMatches(stripped))
      if (!allowed(match[1]!))
        '${'\n'.allMatches(stripped.substring(0, match.start)).length + 1}: '
            '${match[1]}',
  ];
}

void main() {
  for (final MapEntry(key: folder, value: allowed) in _domains.entries) {
    test('$folder imports only what it allows', () {
      final dir = Directory(folder);
      expect(dir.existsSync(), isTrue, reason: '$folder must exist');
      final files = dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      expect(files, isNotEmpty);
      final violations = [
        for (final file in files)
          for (final hit in forbiddenImports(file.readAsStringSync(), allowed))
            '${file.path}:$hit',
      ];
      expect(violations, isEmpty, reason: violations.join('\n'));
    });
  }

  test('every domain folder under lib/ has its list', () {
    final folders = {
      for (final dir in Directory('lib').listSync(recursive: true))
        if (dir is Directory &&
            dir.path.endsWith('${Platform.pathSeparator}domain'))
          dir.path.replaceAll(r'\', '/'),
    };
    expect(folders, _domains.keys.toSet());
  });

  test('the content scan catches forbidden imports and ignores the rest', () {
    expect(forbiddenImports("import 'package:flutter/foundation.dart';"), [
      '1: package:flutter/foundation.dart',
    ]);
    expect(forbiddenImports("library;\n\nimport 'dart:io';"), ['3: dart:io']);
    expect(forbiddenImports("export 'package:dio/dio.dart';"), hasLength(1));
    expect(
      forbiddenImports("import 'package:wassal/core/x.dart';"),
      hasLength(1),
    );
    expect(
      forbiddenImports("import 'package:trip_engine/trip_engine.dart';"),
      hasLength(1),
    );
    expect(
      forbiddenImports(
        "import 'package:content_models/content_models.dart';\n"
        "import 'dart:collection';\n"
        "import 'dart:core';",
      ),
      isEmpty,
    );
    expect(forbiddenImports("// import 'dart:io';"), isEmpty);
  });

  test('the economy scan allows its list and refuses the rest', () {
    List<String> scan(String uri) =>
        forbiddenImports("import '$uri';", _economyAllowed);
    for (final ok in [
      'fuel.dart',
      'package:wassal/core/economy/domain/fuel.dart',
      'package:wassal/core/content/domain/content_source.dart',
      'package:trip_engine/trip_engine.dart',
      'package:content_models/content_models.dart',
      'dart:collection',
    ]) {
      expect(scan(ok), isEmpty, reason: ok);
    }
    for (final bad in [
      '../economy.dart',
      'sub/fuel.dart',
      'package:wassal/core/economy/economy.dart',
      'package:wassal/core/storage/app_database.dart',
      'package:uuid/uuid.dart',
      'package:drift/drift.dart',
      'package:flutter/foundation.dart',
      'dart:io',
      'dart:math',
    ]) {
      expect(scan(bad), hasLength(1), reason: bad);
    }
  });
}
