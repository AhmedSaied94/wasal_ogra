// The base of every value the trip screen draws (data-model.md "The view").
// Riverpod's `select` compares slices of the view with ==, so every view type
// is immutable and compared by its fields. The same field map lets a test
// list each type's fields without reflection (research R10).

/// An immutable value compared by its [fields].
abstract class ViewValue {
  const ViewValue();

  /// Every field, by name, in declaration order.
  Map<String, Object?> get fields;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other.runtimeType == runtimeType &&
          other is ViewValue &&
          deepEquals(fields, other.fields));

  @override
  int get hashCode => deepHash(fields);

  @override
  String toString() => '$runtimeType$fields';
}

/// Equality that looks inside lists, sets and maps.
bool deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  switch ((a, b)) {
    case (final List<Object?> x, final List<Object?> y):
      if (x.length != y.length) return false;
      for (var i = 0; i < x.length; i++) {
        if (!deepEquals(x[i], y[i])) return false;
      }
      return true;
    case (final Set<Object?> x, final Set<Object?> y):
      return x.length == y.length && x.containsAll(y);
    case (final Map<Object?, Object?> x, final Map<Object?, Object?> y):
      if (x.length != y.length) return false;
      for (final MapEntry(:key, :value) in x.entries) {
        if (!y.containsKey(key) || !deepEquals(value, y[key])) return false;
      }
      return true;
    default:
      return a == b;
  }
}

/// A hash consistent with [deepEquals].
int deepHash(Object? value) => switch (value) {
  final List<Object?> list => Object.hashAll(list.map(deepHash)),
  final Set<Object?> set => Object.hashAllUnordered(set.map(deepHash)),
  final Map<Object?, Object?> map => Object.hashAllUnordered(
    map.entries.map((e) => Object.hash(deepHash(e.key), deepHash(e.value))),
  ),
  _ => value.hashCode,
};
