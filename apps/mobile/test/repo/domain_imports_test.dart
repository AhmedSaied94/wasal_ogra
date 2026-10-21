import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_source.dart';

// The content domain is pure Dart over the generated models (constitution I,
// specs/006-m04-content-loader/contracts/content-source.md): no Flutter, no
// plugin and no dart:io, so the engine's readers can use it anywhere.

const _domain = 'lib/core/content/domain';

final _directive = RegExp(
  r'''^[ \t]*(?:import|export)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

bool _allowed(String uri) =>
    uri == 'dart:core' ||
    uri == 'dart:collection' ||
    uri.startsWith('package:content_models/');

List<String> forbiddenImports(String source) {
  final stripped = stripComments(source);
  return [
    for (final match in _directive.allMatches(stripped))
      if (!_allowed(match[1]!))
        '${'\n'.allMatches(stripped.substring(0, match.start)).length + 1}: '
            '${match[1]}',
  ];
}

void main() {
  test('the content domain imports only dart:core, dart:collection and '
      'content_models', () {
    final files = Directory(_domain)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(files, isNotEmpty);
    final violations = [
      for (final file in files)
        for (final hit in forbiddenImports(file.readAsStringSync()))
          '${file.path}:$hit',
    ];
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('the scan catches forbidden imports and ignores the rest', () {
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
      forbiddenImports(
        "import 'package:content_models/content_models.dart';\n"
        "import 'dart:collection';\n"
        "import 'dart:core';",
      ),
      isEmpty,
    );
    expect(forbiddenImports("// import 'dart:io';"), isEmpty);
  });
}
