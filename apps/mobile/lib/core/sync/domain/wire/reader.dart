// Strict reads of the server's JSON (specs/011-m06-identity-sync, research
// R3): integers must be JSON integers, and fields the app doesn't list are
// ignored (B03 "Versioning"). They follow M04's manifest reader.

/// An answer the app can't read: a missing field, or a value of the wrong
/// type. A malformed `200` counts as `server_error`.
final class WireFormatException implements Exception {
  const WireFormatException(this.message);

  final String message;

  @override
  String toString() => 'WireFormatException($message)';
}

/// One JSON object, read field by field.
final class WireObject {
  WireObject._(this.raw, this._path);

  /// [json] as an object, or a [WireFormatException] naming [path].
  factory WireObject.of(Object? json, [String path = 'body']) {
    if (json is! Map<String, Object?>) {
      throw WireFormatException('$path must be an object');
    }
    return WireObject._(json, path);
  }

  /// The object as it arrived, unknown fields included.
  final Map<String, Object?> raw;
  final String _path;

  bool has(String key) => raw[key] != null;

  int integer(String key) => _int(raw[key], '$_path.$key');

  int? optionalInteger(String key) => raw[key] == null ? null : integer(key);

  String string(String key) {
    final value = raw[key];
    if (value is! String) {
      throw WireFormatException('$_path.$key must be a string');
    }
    return value;
  }

  String? optionalString(String key) => raw[key] == null ? null : string(key);

  bool boolean(String key) {
    final value = raw[key];
    if (value is! bool) {
      throw WireFormatException('$_path.$key must be a boolean');
    }
    return value;
  }

  WireObject object(String key) => WireObject.of(raw[key], '$_path.$key');

  WireObject? optionalObject(String key) =>
      raw[key] == null ? null : object(key);

  List<Object?> list(String key) {
    final value = raw[key];
    if (value is! List<Object?>) {
      throw WireFormatException('$_path.$key must be a list');
    }
    return value;
  }

  /// A list of strings.
  List<String> strings(String key) => [
    for (final (i, value) in list(key).indexed)
      if (value is String)
        value
      else
        throw WireFormatException('$_path.$key.$i must be a string'),
  ];

  /// A list of objects.
  List<WireObject> objects(String key) => [
    for (final (i, value) in list(key).indexed)
      WireObject.of(value, '$_path.$key.$i'),
  ];
}

int _int(Object? value, String path) {
  if (value is! int) throw WireFormatException('$path must be an integer');
  return value;
}
