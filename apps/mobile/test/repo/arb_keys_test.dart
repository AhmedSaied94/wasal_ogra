import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The ARB's keys must be unique (specs/015-m10-apartment-story, T033): a JSON
// decoder keeps the last of two `"destPreTrip"` pairs, so a copy-pasted key
// silently retitles another screen, and a stricter generator fails `pub get`.

/// Every key [text] declares at its top level, in order. A nested object's
/// keys (a placeholder, a description) come deeper, so they aren't keys of the
/// resource map.
List<String> topLevelKeys(String text) {
  final keys = <String>[];
  var depth = 0;
  var i = 0;
  while (i < text.length) {
    final char = text[i];
    if (char == '"') {
      final start = i + 1;
      var end = start;
      while (end < text.length) {
        if (text[end] == r'\') {
          end += 2;
          continue;
        }
        if (text[end] == '"') break;
        end++;
      }
      if (depth == 1) {
        var after = end + 1;
        while (after < text.length && text[after].trim().isEmpty) {
          after++;
        }
        if (after < text.length && text[after] == ':') {
          keys.add(text.substring(start, end));
        }
      }
      i = end + 1;
      continue;
    }
    if (char == '{' || char == '[') depth++;
    if (char == '}' || char == ']') depth--;
    i++;
  }
  return keys;
}

/// The keys [keys] declares more than once.
List<String> duplicatesOf(List<String> keys) {
  final seen = <String>{};
  final repeated = <String>[];
  for (final key in keys) {
    if (!seen.add(key) && !repeated.contains(key)) repeated.add(key);
  }
  return repeated;
}

void main() {
  test('app_ar.arb declares every key once', () {
    final keys = topLevelKeys(File('lib/l10n/app_ar.arb').readAsStringSync());
    final repeated = duplicatesOf(keys);
    expect(repeated, isEmpty, reason: 'duplicate keys: ${repeated.join(', ')}');
    expect(keys, contains('destPreTrip'));
  });

  test('the scan finds a repeated key and skips a nested one', () {
    const arb = '''
{
  "one": "أ",
  "two": "ب",
  "one": "ج",
  "@two": {
    "description": "one"
  }
}''';
    expect(duplicatesOf(topLevelKeys(arb)), ['one']);
  });
}
