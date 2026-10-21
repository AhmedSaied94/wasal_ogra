// The strict reader refuses what the Python loader refuses (B04 research R2),
// so the app reads exactly the documents the server accepts
// (specs/006-m04-content-loader/research.md R3).
import 'dart:convert';
import 'dart:io';

import 'package:content_models/content_models.dart';
import 'package:test/test.dart';

const _safe = 9007199254740991;

Matcher _refusedAt(String path) =>
    throwsA(isA<ContentJsonError>().having((e) => e.path, 'path', path));

String _nested(int depth) => '${'{"a":' * (depth - 1)}{}${'}' * (depth - 1)}';

void main() {
  group('decodeContentJson', () {
    final vectors = jsonDecode(
      File('../../content/examples/canonical-vectors.json').readAsStringSync(),
    ) as List<dynamic>;
    // A document is an object, so the vectors with another root are refused.
    for (final vector in vectors.cast<Map<String, dynamic>>()) {
      final canonical = vector['canonical'] as String;
      if (vector['input'] is Map) {
        test('reads the canonical vector "${vector['name']}"', () {
          expect(decodeContentJson(canonical), vector['input']);
        });
      } else {
        test('refuses the canonical vector "${vector['name']}"', () {
          expect(() => decodeContentJson(canonical), _refusedAt(r'$'));
        });
      }
    }

    test('returns the object', () {
      expect(decodeContentJson('{"a":[1,"b",true]}'), {
        'a': [1, 'b', true],
      });
    });

    test('accepts integers at ±(2^53 - 1)', () {
      expect(decodeContentJson('{"a":$_safe,"b":-$_safe}'), {
        'a': _safe,
        'b': -_safe,
      });
    });

    test('refuses null', () {
      expect(() => decodeContentJson('{"a":null}'), _refusedAt(r'$.a'));
      expect(() => decodeContentJson('{"a":[1,null]}'), _refusedAt(r'$.a[1]'));
    });

    test('refuses every non-integer number token', () {
      expect(() => decodeContentJson('{"a":1.0}'), _refusedAt(r'$.a'));
      expect(() => decodeContentJson('{"a":1.5}'), _refusedAt(r'$.a'));
      expect(() => decodeContentJson('{"a":1e3}'), _refusedAt(r'$.a'));
      expect(
        () => decodeContentJson('{"a":{"b":[0,-2.5]}}'),
        _refusedAt(r'$.a.b[1]'),
      );
    });

    test('refuses integers outside ±(2^53 - 1)', () {
      expect(() => decodeContentJson('{"a":${_safe + 1}}'), _refusedAt(r'$.a'));
      expect(
        () => decodeContentJson('{"a":${-_safe - 1}}'),
        _refusedAt(r'$.a'),
      );
      expect(
        () => decodeContentJson('{"a":123456789012345678901234567890}'),
        _refusedAt(r'$.a'),
      );
      // The 64-bit extremes, which int.abs() would get wrong.
      expect(
        () => decodeContentJson('{"a":[-9223372036854775808]}'),
        _refusedAt(r'$.a[0]'),
      );
      expect(
        () => decodeContentJson('{"a":9223372036854775807}'),
        _refusedAt(r'$.a'),
      );
    });

    test('reads a wide document under a long key in linear time', () {
      final key = 'k' * (1 << 20);
      final wide = [for (var i = 0; i < 100000; i++) '"$i":1'].join(',');
      final decoded = decodeContentJson('{"$key":{$wide}}');
      expect((decoded[key]! as Map).length, 100000);
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('refuses lone surrogates in values and keys', () {
      expect(() => decodeContentJson(r'{"a":"x\ud800"}'), _refusedAt(r'$.a'));
      expect(() => decodeContentJson(r'{"a":"\udc00y"}'), _refusedAt(r'$.a'));
      expect(() => decodeContentJson(r'{"\ud83d":1}'), _refusedAt(r'$'));
      expect(decodeContentJson('{"a":"\\ud83d\\ude00"}'), {'a': '\u{1F600}'});
    });

    test('accepts 32 levels of nesting and refuses 33', () {
      expect(decodeContentJson(_nested(32)), isA<Map<String, dynamic>>());
      expect(
        () => decodeContentJson(_nested(33)),
        throwsA(isA<ContentJsonError>()),
      );
      expect(
        () => decodeContentJson('{"a":${'[' * 32}${']' * 32}}'),
        throwsA(isA<ContentJsonError>()),
      );
    });

    test('refuses a root that is not an object', () {
      expect(() => decodeContentJson('[1]'), _refusedAt(r'$'));
      expect(() => decodeContentJson('"s"'), _refusedAt(r'$'));
      expect(() => decodeContentJson('1'), _refusedAt(r'$'));
    });

    test('wraps text that is not JSON', () {
      expect(() => decodeContentJson('nope'), _refusedAt(r'$'));
      expect(() => decodeContentJson('{"a":1'), _refusedAt(r'$'));
      expect(() => decodeContentJson(''), _refusedAt(r'$'));
    });

    test('says what it refused', () {
      expect(
        () => decodeContentJson('{"a":1.5}'),
        throwsA(
          isA<ContentJsonError>().having(
            (e) => e.toString(),
            'toString',
            allOf(contains(r'$.a'), contains('integer')),
          ),
        ),
      );
    });
  });
}
