// Constitution I: the engine imports nothing outside the pure Dart core,
// content_models and crypto (research R1, R16).
import 'dart:io';

import 'package:test/test.dart';

import 'source_scan.dart';

const _allowed = [
  'dart:core',
  'dart:convert',
  'dart:collection',
  'package:content_models/',
  'package:crypto/',
  'package:trip_engine/',
];

bool _isAllowed(String uri) =>
    !uri.contains(':') || _allowed.any((prefix) => uri.startsWith(prefix));

void main() {
  test('the scanner finds directives and ignores commented ones', () {
    const sample = '''
import 'dart:convert';
// import 'dart:io';
/* import 'package:flutter/material.dart'; */
export "src/engine.dart" show TripEngine;
part 'events/trip_events.dart';
''';
    expect(directiveUris(sample), [
      'dart:convert',
      'src/engine.dart',
      'events/trip_events.dart',
    ]);
    expect(_isAllowed('package:flutter/material.dart'), isFalse);
    expect(_isAllowed('dart:io'), isFalse);
    expect(_isAllowed('../model/state.dart'), isTrue);
  });

  for (final file in libSources()) {
    test('${file.path} imports only allowed libraries', () {
      final uris = directiveUris(file.readAsStringSync());
      expect(uris.where((uri) => !_isAllowed(uri)), isEmpty);
    });
  }

  test('pubspec.yaml has no flutter key and only the two dependencies', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(
      RegExp(r'^\s*flutter\s*:', multiLine: true).hasMatch(pubspec),
      isFalse,
    );
    final dependencies = RegExp(
      r'^dependencies:\n((?:  .*\n)+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1)!;
    final names = RegExp(
      r'^  (\w+):',
      multiLine: true,
    ).allMatches(dependencies).map((match) => match.group(1)).toSet();
    expect(names, {'content_models', 'crypto'});
  });
}
