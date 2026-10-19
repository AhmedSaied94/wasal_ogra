// The canonical JSON form (research R4), hand-written next to the generated
// models. The Python side is `wassal_content.canonical`, and both must
// reproduce `content/examples/canonical-vectors.json`.
import 'dart:convert';

/// The canonical JSON text of [value]: object keys sorted by UTF-16 code
/// unit, no whitespace, and minimal escaping, as `jsonEncode` does it.
///
/// Throws [ArgumentError] for `null` and for doubles, which content never
/// holds: an absent field is left out, and every number is an integer. Also
/// for integers outside ±(2^53 - 1) and lone surrogates, which the Python
/// loader refuses, so both sides accept the same values.
String canonicalJson(Object? value) => jsonEncode(_sorted(value, r'$'));

const _maxSafeInteger = 9007199254740991;

// A high surrogate not followed by a low one, or a low one not after a high.
final _loneSurrogate = RegExp(
  r'[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]',
);

Object _sorted(Object? value, String path) => switch (value) {
  null => throw ArgumentError.value(value, path, 'null is not allowed'),
  double() => throw ArgumentError.value(value, path, 'a double is not allowed'),
  int() when value.abs() > _maxSafeInteger => throw ArgumentError.value(
    value,
    path,
    'out of range: integers are within ±(2^53 - 1)',
  ),
  String() when _loneSurrogate.hasMatch(value) => throw ArgumentError.value(
    value,
    path,
    'a lone surrogate is not allowed',
  ),
  Map<Object?, Object?>() => _sortedMap(value, path),
  List<Object?>() => [
    for (final (index, item) in value.indexed) _sorted(item, '$path[$index]'),
  ],
  String() || int() || bool() => value,
  _ => throw ArgumentError.value(value, path, 'not a JSON value'),
};

Map<String, Object> _sortedMap(Map<Object?, Object?> map, String path) {
  final keys = [
    for (final key in map.keys)
      if (key is! String)
        throw ArgumentError.value(key, path, 'an object key must be a string')
      else if (_loneSurrogate.hasMatch(key))
        throw ArgumentError.value(key, path, 'a lone surrogate is not allowed')
      else
        key,
  ]..sort();
  return {for (final key in keys) key: _sorted(map[key], '$path.$key')};
}
