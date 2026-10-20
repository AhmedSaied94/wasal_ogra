// Money: pieces of the glossary §3.2 denominations, and the fixed tables of
// rules.md §14. Every amount is integer piasters (constitution II).
import 'dart:collection';

/// The denominations, ascending.
const List<int> denominations = [50, 100, 500, 1000, 2000, 5000, 10000, 20000];

bool isDenomination(int piasters) => denominations.contains(piasters);

/// A multiset of denominations: each held at least once, in ascending order.
final class Pieces {
  Pieces._(Map<int, int> ascending)
    : counts = UnmodifiableMapView(ascending),
      total = _sum(ascending);

  /// Pieces from a map of denomination to count. Throws [ArgumentError] for
  /// anything that isn't a denomination or a count below 1.
  factory Pieces(Map<int, int> counts) {
    for (final MapEntry(:key, :value) in counts.entries) {
      if (!isDenomination(key)) {
        throw ArgumentError.value(key, 'counts', 'not a denomination');
      }
      if (value < 1) {
        throw ArgumentError.value(value, 'counts[$key]', 'below 1');
      }
    }
    return Pieces._({
      for (final denomination in denominations)
        denomination: ?counts[denomination],
    });
  }

  /// Pieces from a list such as an authored payment.
  factory Pieces.ofList(Iterable<int> pieces) {
    final counts = <int, int>{};
    for (final piece in pieces) {
      counts[piece] = (counts[piece] ?? 0) + 1;
    }
    return Pieces(counts);
  }

  /// Pieces from their wire form, `{"100": 2}`. Throws [FormatException].
  factory Pieces.fromJson(Map<String, Object?> json) {
    final counts = <int, int>{};
    for (final MapEntry(:key, :value) in json.entries) {
      final denomination = int.tryParse(key);
      if (denomination == null || !isDenomination(denomination)) {
        throw FormatException('not a denomination: $key');
      }
      if (value is! int || value < 1) {
        throw FormatException('the count of $key must be an integer ≥ 1');
      }
      counts[denomination] = value;
    }
    return Pieces(counts);
  }

  static final Pieces empty = Pieces._(const {});

  /// Denomination to count, ascending and unmodifiable.
  final Map<int, int> counts;

  /// The sum in piasters.
  final int total;

  int count(int denomination) => counts[denomination] ?? 0;

  bool get isEmpty => counts.isEmpty;

  /// The number of pieces.
  int get length => counts.values.fold(0, (sum, count) => sum + count);

  bool contains(Pieces other) =>
      other.counts.entries.every((entry) => count(entry.key) >= entry.value);

  Pieces plus(Pieces other) => Pieces._({
    for (final denomination in denominations)
      if (count(denomination) + other.count(denomination) case final n
          when n > 0)
        denomination: n,
  });

  Pieces plusOne(int denomination) => plus(Pieces({denomination: 1}));

  /// These pieces without [other]. Throws [ArgumentError] if one is missing.
  Pieces minus(Pieces other) {
    if (!contains(other)) {
      throw ArgumentError.value(other, 'other', 'not all held');
    }
    return Pieces._({
      for (final denomination in denominations)
        if (count(denomination) - other.count(denomination) case final n
            when n > 0)
          denomination: n,
    });
  }

  Pieces minusOne(int denomination) => minus(Pieces({denomination: 1}));

  /// Every piece, ascending.
  List<int> toList() => [
    for (final MapEntry(:key, :value) in counts.entries)
      for (var i = 0; i < value; i++) key,
  ];

  Map<String, int> toJson() => {
    for (final MapEntry(:key, :value) in counts.entries) '$key': value,
  };

  @override
  bool operator ==(Object other) =>
      other is Pieces &&
      other.counts.length == counts.length &&
      counts.entries.every((entry) => other.count(entry.key) == entry.value);

  @override
  int get hashCode => Object.hashAll([
    for (final MapEntry(:key, :value) in counts.entries) ...[key, value],
  ]);

  @override
  String toString() => 'Pieces(${toJson()})';

  static int _sum(Map<int, int> counts) =>
      counts.entries.fold(0, (sum, entry) => sum + entry.key * entry.value);
}

/// The fewest pieces for [amount], a multiple of 50 (§14.3): greedy from the
/// largest denomination, with unlimited supply.
Pieces fewestPieces(int amount) {
  if (amount < 0 || amount % 50 != 0) {
    throw ArgumentError.value(amount, 'amount', 'not a multiple of 50 ≥ 0');
  }
  var rest = amount;
  final counts = <int, int>{};
  for (final denomination in denominations.reversed) {
    if (rest ~/ denomination case final count when count > 0) {
      counts[denomination] = count;
      rest -= count * denomination;
    }
  }
  return Pieces(counts);
}

/// What a note comes back as from «حد معاه فكة؟» (§14.1, clarification 4).
const Map<int, Map<int, int>> breakDownTable = {
  1000: {500: 1, 100: 4, 50: 2},
  2000: {1000: 1, 500: 1, 100: 4, 50: 2},
  5000: {2000: 2, 500: 1, 100: 4, 50: 2},
  10000: {5000: 1, 2000: 2, 500: 1, 100: 4, 50: 2},
  20000: {10000: 1, 5000: 1, 2000: 2, 500: 1, 100: 4, 50: 2},
};

/// The break-down of [note], or null when it has no row.
Pieces? breakDown(int note) => switch (breakDownTable[note]) {
  final row? => Pieces(row),
  null => null,
};

/// The `change_bag` booster's contents (§14.2, glossary §3.3).
final Pieces changeBag = Pieces({50: 2, 100: 3, 500: 2});

/// The tray's pieces for a change request of [note] (§14.4): a depth-first
/// search over the denominations below [note], largest first, each count
/// tried from the most available down. The first exact total wins. Branches
/// that can't reach the total are cut, which never changes that answer.
Pieces? changeRequestPieces(int note, Pieces tray) {
  final options = [
    for (final denomination in denominations.reversed)
      if (denomination < note) denomination,
  ];
  // What the denominations from index i on can still make.
  final reach = List.filled(options.length + 1, 0);
  for (var i = options.length - 1; i >= 0; i--) {
    reach[i] = reach[i + 1] + options[i] * tray.count(options[i]);
  }
  final chosen = <int, int>{};

  bool search(int index, int rest) {
    if (rest == 0) return true;
    if (index == options.length || rest > reach[index]) return false;
    final denomination = options[index];
    final most = rest ~/ denomination;
    final held = tray.count(denomination);
    for (var count = held < most ? held : most; count >= 0; count--) {
      if (count > 0) {
        chosen[denomination] = count;
      } else {
        chosen.remove(denomination);
      }
      if (search(index + 1, rest - count * denomination)) return true;
    }
    return false;
  }

  return search(0, note) ? Pieces(chosen) : null;
}
