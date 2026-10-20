// Strict readers for the engine's JSON inputs: results, replay records and
// fixtures. Anything malformed is a FormatException naming the field.
import 'package:content_models/content_models.dart';

/// [json] as an object, or a FormatException naming [what].
Map<String, Object?> asObject(Object? json, String what) {
  if (json is Map<String, Object?>) return json;
  if (json is Map && json.keys.every((key) => key is String)) {
    return json.cast<String, Object?>();
  }
  throw FormatException('$what must be an object');
}

/// Throws unless [json] has exactly [keys].
void expectKeys(Map<String, Object?> json, Set<String> keys, String what) {
  for (final key in json.keys) {
    if (!keys.contains(key)) {
      throw FormatException('$what has an unknown key: $key');
    }
  }
  for (final key in keys) {
    if (!json.containsKey(key)) throw FormatException('$what is missing $key');
  }
}

T _read<T>(Map<String, Object?> json, String key, String type) {
  final value = json[key];
  if (value is T) return value;
  throw FormatException('$key must be $type');
}

int readInt(Map<String, Object?> json, String key) =>
    _read<int>(json, key, 'an integer');

bool readBool(Map<String, Object?> json, String key) =>
    _read<bool>(json, key, 'a boolean');

String readString(Map<String, Object?> json, String key) =>
    _read<String>(json, key, 'a string');

List<Object?> readList(Map<String, Object?> json, String key) =>
    _read<List<Object?>>(json, key, 'a list');

Map<String, Object?> readObject(Map<String, Object?> json, String key) =>
    asObject(json[key], key);

/// The enum value of [values] whose [wire] name is [json], or a
/// FormatException naming [what].
T readWire<T>(
  List<T> values,
  String Function(T) wire,
  Object? json,
  String what,
) {
  for (final value in values) {
    if (wire(value) == json) return value;
  }
  throw FormatException('$what is not a known value: $json');
}

/// [json]'s [key] as a trip definition. The generated decoder is unchecked
/// (content_models' build.yaml), so a value of the wrong type surfaces as a
/// TypeError and an unknown enum value as an ArgumentError. At this input
/// boundary both mean malformed JSON, and become a FormatException.
TripDefinition readDefinition(Map<String, Object?> json, String key) {
  final object = readObject(json, key);
  try {
    return TripDefinition.fromJson(object);
  } on TypeError catch (error) {
    throw FormatException('$key is not a trip definition: $error');
  } on ArgumentError catch (error) {
    throw FormatException('$key is not a trip definition: ${error.message}');
  }
}
