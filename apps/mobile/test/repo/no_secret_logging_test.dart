import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_source.dart';
import 'economy_writes_test.dart' show parenthesized;

// The tokens and the install id stay out of logs and the preference store
// (specs/011-m06-identity-sync FR-002, FR-005, SC-008; research R2;
// contracts/ci-checks.md "Secrets stay out of logs", "Tokens never in the
// preference store").

/// The stores the secrets belong in, whose keys name them by design: the
/// install id's (its Android file, `wassal_install.xml`, is a preference
/// file, research R1) and the session's secure storage (research R2).
const _secretStores = {
  'lib/core/account/install_id_store.dart',
  'lib/core/account/session_store.dart',
};

final _logCall = RegExp(
  r'(?:\bprint|\bdebugPrint|\bdeveloper\.log|(?<![.\w])log|'
  r'\bFlutterError\.report\w*|\bFlutterError\.dumpErrorToConsole)\s*\(',
);

/// A secret's name, however it is cased or prefixed.
final _secret = RegExp(
  r'(?<![A-Za-z])(?:access|refresh|install_?id|session)',
  caseSensitive: false,
);

/// A key passed to a `SettingsStore` or `SharedPreferences` read or write.
/// Not `remove` or `containsKey`: a map has those too, and neither stores a
/// value.
final _keyArgument = RegExp(
  r'''\b(?:readString|writeString|getString|setString|getBool|setBool|'''
  r'''getInt|setInt|getStringList|setStringList)\(\s*'''
  r'''['"]([^'"]+)['"]''',
);
final _keyConstant = RegExp(r'''\b\w*[kK]eys?\s*=\s*['"]([^'"]+)['"]''');
final _keySet = RegExp(r'''\bkeys\s*=\s*\{([^}]*)\}''');
final _literal = RegExp(r'''['"]([^'"]+)['"]''');

final _forbiddenKey = RegExp(
  'token|session|access|refresh|install',
  caseSensitive: false,
);

/// Log calls in [source] whose arguments name a secret.
List<String> secretLogs(String source) {
  final stripped = stripComments(source);
  return [
    for (final call in _logCall.allMatches(stripped))
      if (_secret.hasMatch(parenthesized(stripped, call.end - 1)))
        '${'\n'.allMatches(stripped.substring(0, call.start)).length + 1}: '
            '${call[0]}',
  ];
}

/// Preference keys in [source] that name a secret.
List<String> secretKeys(String source) {
  final stripped = stripComments(source);
  final keys = {
    for (final m in _keyArgument.allMatches(stripped)) m[1]!,
    for (final m in _keyConstant.allMatches(stripped)) m[1]!,
    for (final set in _keySet.allMatches(stripped))
      for (final m in _literal.allMatches(set[1]!)) m[1]!,
  };
  return [
    for (final key in keys)
      if (_forbiddenKey.hasMatch(key)) key,
  ];
}

void main() {
  final files = libDartFiles().where((f) => !f.path.endsWith('.g.dart'));
  String path(File f) => f.path.replaceAll(r'\', '/');

  test('no log call in lib/ names a token, a session or the install id', () {
    final violations = [
      for (final file in files)
        for (final hit in secretLogs(file.readAsStringSync()))
          '${path(file)}:$hit',
    ];
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('no HTTP logging interceptor, in any flavor', () {
    final violations = [
      for (final file in files)
        if (stripComments(file.readAsStringSync()).contains('LogInterceptor'))
          path(file),
    ];
    expect(violations, isEmpty);
  });

  test('no preference key in lib/ names a token, a session or the id', () {
    final violations = [
      for (final file in files)
        if (!_secretStores.contains(path(file)))
          for (final key in secretKeys(file.readAsStringSync()))
            '${path(file)}: $key',
    ];
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('the log scan catches secrets and ignores the rest', () {
    for (final line in [
      "debugPrint('token \${session.access}');",
      "print('refresh: \$refresh');",
      "log('id \$installId');",
      'developer.log(install_id);',
      "FlutterError.reportError(details(_session));",
    ]) {
      expect(secretLogs(line), hasLength(1), reason: line);
    }
    for (final line in [
      "debugPrint('sfx \${sfx.file} did not load: \$error');",
      "debugPrint('trip result refused: \${code.wire}');",
      "debugPrint('\${tripSession.id}');",
      "catalog('access');",
      "// print(session.access);",
    ]) {
      expect(secretLogs(line), isEmpty, reason: line);
    }
  });

  test('the key scan catches secret keys and ignores the rest', () {
    expect(secretKeys("store.writeString('pref.session', v);"), [
      'pref.session',
    ]);
    expect(secretKeys("const tokenKey = 'auth.token';"), ['auth.token']);
    expect(secretKeys("static const keys = {'pref.digit_style', 'refresh'};"), [
      'refresh',
    ]);
    expect(secretKeys("store.readString('update.dismissedVersion');"), isEmpty);
    expect(secretKeys("const tripSoundKey = 'pref.trip_sound';"), isEmpty);
    expect(secretKeys("json.containsKey('access');"), isEmpty);
  });
}
