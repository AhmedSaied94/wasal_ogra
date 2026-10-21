// The strict JSON reader for content documents
// (specs/006-m04-content-loader/research.md R3), hand-written next to the
// generated models. It refuses what B04's Python loader
// (`wassal_content.loader`) refuses, so the app reads only documents the
// server would accept. The generated `fromJson` reads an integer as
// `(json['x'] as num).toInt()`, which would truncate 1.5; this reader refuses
// it first.
import 'dart:convert';

/// A content document that [decodeContentJson] refused: [path] says where,
/// as `$.lines[2].stops`.
final class ContentJsonError implements Exception {
  const ContentJsonError(this.path, this.message);

  final String path;
  final String message;

  @override
  String toString() => 'ContentJsonError at $path: $message';
}

/// The JSON object in [text], read as the Python loader reads content.
///
/// Throws [ContentJsonError] for text that isn't JSON, a root that isn't an
/// object, `null`, any number written with a fraction or an exponent,
/// integers outside ±(2^53 - 1), lone surrogates in strings or keys, and
/// nesting deeper than 32 levels. Duplicate keys aren't visible after
/// `jsonDecode` (the last one wins); research R3 says why that's acceptable.
Map<String, Object> decodeContentJson(String text) {
  final Object? value;
  try {
    value = jsonDecode(text);
  } on FormatException catch (error) {
    throw ContentJsonError(r'$', 'not JSON: ${error.message}');
  }
  if (value is! Map<String, Object?>) {
    throw const ContentJsonError(r'$', 'the root must be an object');
  }
  return _Reader().object(value, 1);
}

const _maxDepth = 32;

const _maxSafeInteger = 9007199254740991;

// A high surrogate not followed by a low one, or a low one not after a high.
final _loneSurrogate = RegExp(
  r'[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]',
);

/// Walks a decoded document. The path is kept as keys and indexes and only
/// written out for an error, so a wide document under a long key costs no
/// string per node.
final class _Reader {
  final _segments = <Object>[];

  Never _fail(String message) => throw ContentJsonError(
    [r'$', for (final s in _segments) s is int ? '[$s]' : '.$s'].join(),
    message,
  );

  Object value(Object? value, int depth) => switch (value) {
    null => _fail('null is not allowed'),
    // jsonDecode reads 1.0, 1e3 and integers past 64 bits as doubles.
    double() => _fail('every number must be an integer'),
    // Not value.abs(): it overflows for the smallest 64-bit integer.
    int() when value > _maxSafeInteger || value < -_maxSafeInteger => _fail(
      'out of range: integers are within ±(2^53 - 1)',
    ),
    String() when _loneSurrogate.hasMatch(value) => _fail(
      'a lone surrogate is not allowed',
    ),
    Map<String, Object?>() => object(value, depth + 1),
    List<Object?>() => list(value, depth + 1),
    String() || int() || bool() => value,
    _ => _fail('not a JSON value'),
  };

  Map<String, Object> object(Map<String, Object?> map, int depth) {
    _checkDepth(depth);
    final result = <String, Object>{};
    for (final MapEntry(:key, :value) in map.entries) {
      if (_loneSurrogate.hasMatch(key)) {
        _fail('a lone surrogate is not allowed in a key');
      }
      _segments.add(key);
      result[key] = this.value(value, depth);
      _segments.removeLast();
    }
    return result;
  }

  List<Object> list(List<Object?> list, int depth) {
    _checkDepth(depth);
    final result = <Object>[];
    for (final (index, item) in list.indexed) {
      _segments.add(index);
      result.add(value(item, depth));
      _segments.removeLast();
    }
    return result;
  }

  void _checkDepth(int depth) {
    if (depth > _maxDepth) _fail('nested more than $_maxDepth levels deep');
  }
}
