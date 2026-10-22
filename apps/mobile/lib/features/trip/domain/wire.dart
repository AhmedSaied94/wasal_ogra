// Wire names of the generated content enums the trip shows or stores. The
// generated enums keep them only in `@JsonValue` annotations, so they are
// derived from the Dart names, as the engine does (M01 `wire.dart`).

/// The snake_case wire name of [value]: `bigNote` → `big_note`,
/// `fuelUnlimited1h` → `fuel_unlimited_1h`.
String wireOf(Enum value) {
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
T? fromWireName<T extends Enum>(List<T> values, Object? wire) {
  for (final value in values) {
    if (wireOf(value) == wire) return value;
  }
  return null;
}
