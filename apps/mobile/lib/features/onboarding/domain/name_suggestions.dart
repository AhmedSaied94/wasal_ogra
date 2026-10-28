// The Name card's suggested names (specs/012-m07-onboarding/contracts/
// name.md "Suggestions"): the pool from `namePool`, a first pick from a
// seed, and the dice's picks, never the name showing.
import 'dart:math';

/// The Arabic comma, «،», between the pool's names.
const _separator = '\u060C';

/// The names in [pool], separated by «،», each trimmed, empty parts dropped.
List<String> namePoolOf(String pool) => List.unmodifiable([
  for (final part in pool.split(_separator))
    if (part.trim() case final name when name.isNotEmpty) name,
]);

final class NameSuggestions {
  NameSuggestions(this.pool, {required int seed}) : _random = Random(seed);

  final List<String> pool;
  final Random _random;

  late final String first = pool.isEmpty
      ? ''
      : pool[_random.nextInt(pool.length)];

  /// A pooled name other than [showing], when the pool has another.
  String another(String showing) {
    final others = [
      for (final name in pool)
        if (name != showing) name,
    ];
    if (others.isEmpty) return pool.isEmpty ? '' : pool.first;
    return others[_random.nextInt(others.length)];
  }
}
