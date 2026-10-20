// Wire names of enums. The generated content_models enums keep theirs only in
// `@JsonValue` annotations, so they are derived here from the Dart names;
// `capabilities_test.dart` checks the result against the schemas.
import 'package:content_models/content_models.dart';

/// The snake_case wire name of [value]: `bigNote` → `big_note`,
/// `fuelUnlimited1h` → `fuel_unlimited_1h`.
String wireName(Enum value) {
  final name = value.name;
  final out = StringBuffer();
  for (var i = 0; i < name.length; i++) {
    final char = name[i];
    final upper = char != char.toLowerCase();
    final digitAfterLetter = _isDigit(char) && i > 0 && !_isDigit(name[i - 1]);
    if (upper || digitAfterLetter) out.write('_');
    out.write(char.toLowerCase());
  }
  return out.toString();
}

bool _isDigit(String char) => '0123456789'.contains(char);

/// The value of [values] whose wire name is [wire], or null.
T? byWire<T extends Enum>(List<T> values, Object? wire) {
  for (final value in values) {
    if (wireName(value) == wire) return value;
  }
  return null;
}

/// The piasters of a generated [Denomination] (`v500` → 500).
int denominationValue(Denomination denomination) =>
    int.parse(denomination.name.substring(1));

/// The generated [Denomination] for [piasters], or null.
Denomination? denominationOf(int piasters) {
  for (final denomination in Denomination.values) {
    if (denominationValue(denomination) == piasters) return denomination;
  }
  return null;
}
