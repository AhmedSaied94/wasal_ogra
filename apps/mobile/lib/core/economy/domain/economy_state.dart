// Everything the operations produce (data-model.md "Domain values"). Every
// value is immutable and every amount an integer (constitution II).
import 'dart:collection';

import 'package:content_models/content_models.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/txn_id.dart';
import 'package:wassal/core/economy/domain/wire.dart';

/// The boosters a player holds and uses in a trip (glossary §3.3). The other
/// BONAT products apply at once and never sit in the inventory.
const inTripBoosters = {
  BoosterId.changeBag,
  BoosterId.wakeAll,
  BoosterId.ledgerPeek,
  BoosterId.trafficJam,
};

/// The SKU kinds a player owns once bought.
const ownableKinds = {SkuKind.item, SkuKind.vehicle, SkuKind.chapter};

/// `traffic_jam` rewarded ads per trip (glossary §3.4).
const trafficJamAdsPerTrip = 1;

/// The highest star count of a trip.
const maxStars = 3;

/// The tank (research R8).
final class FuelState {
  const FuelState({
    required this.liters,
    required this.countedFromMs,
    this.unlimitedUntilMs,
  });

  /// May exceed the maximum only when the maximum was lowered (FR-024).
  final int liters;

  /// Below the maximum: when the countdown to the next liter started. At or
  /// above it: when the tank last became full.
  final int countedFromMs;

  /// The end of the unlimited-fuel window, or null when none was bought.
  final int? unlimitedUntilMs;

  @override
  bool operator ==(Object other) =>
      other is FuelState &&
      other.liters == liters &&
      other.countedFromMs == countedFromMs &&
      other.unlimitedUntilMs == unlimitedUntilMs;

  @override
  int get hashCode => Object.hash(liters, countedFromMs, unlimitedUntilMs);

  @override
  String toString() =>
      'FuelState($liters, from $countedFromMs, until $unlimitedUntilMs)';

  Map<String, Object> toJson() => {
    'liters': liters,
    'counted_from_ms': countedFromMs,
    'unlimited_until_ms': ?unlimitedUntilMs,
  };

  factory FuelState.fromJson(Object? json) {
    final map = _object(json, 'fuel', const {
      'liters',
      'counted_from_ms',
      'unlimited_until_ms',
    });
    return FuelState(
      liters: _count(map, 'liters'),
      countedFromMs: _int(map, 'counted_from_ms'),
      unlimitedUntilMs: _optionalInt(map, 'unlimited_until_ms'),
    );
  }
}

/// One trip's record (FR-033).
final class TripProgress {
  const TripProgress({
    required this.bestStars,
    required this.plays,
    this.bestTimeMs,
    this.firstCompletedAtMs,
  });

  /// 0 to [maxStars], never decreasing.
  final int bestStars;

  /// The shortest `duration_ms` among finished runs, or null until one.
  final int? bestTimeMs;

  /// One per recorded result, of any outcome.
  final int plays;

  /// Set by the first finished result, then fixed.
  final int? firstCompletedAtMs;

  @override
  bool operator ==(Object other) =>
      other is TripProgress &&
      other.bestStars == bestStars &&
      other.bestTimeMs == bestTimeMs &&
      other.plays == plays &&
      other.firstCompletedAtMs == firstCompletedAtMs;

  @override
  int get hashCode =>
      Object.hash(bestStars, bestTimeMs, plays, firstCompletedAtMs);

  @override
  String toString() =>
      'TripProgress($bestStars★, $bestTimeMs ms, $plays plays, '
      'first $firstCompletedAtMs)';

  Map<String, Object> toJson() => {
    'best_stars': bestStars,
    'best_time_ms': ?bestTimeMs,
    'plays': plays,
    'first_completed_at_ms': ?firstCompletedAtMs,
  };

  factory TripProgress.fromJson(Object? json) {
    final map = _object(json, 'progress', const {
      'best_stars',
      'best_time_ms',
      'plays',
      'first_completed_at_ms',
    });
    final stars = _int(map, 'best_stars');
    if (stars < 0 || stars > maxStars) {
      throw FormatException('best_stars must be 0 to $maxStars', stars);
    }
    return TripProgress(
      bestStars: stars,
      bestTimeMs: _optionalInt(map, 'best_time_ms'),
      plays: _count(map, 'plays'),
      firstCompletedAtMs: _optionalInt(map, 'first_completed_at_ms'),
    );
  }
}

/// What the player owns, keyed by kind and SKU id.
typedef OwnedKey = (SkuKind kind, String skuId);

/// One owned item, vehicle or chapter goal.
final class Owned {
  /// Throws [ArgumentError] when [kind] can't be owned, when an item has no
  /// [variantId], or when anything else has one.
  Owned({
    required this.kind,
    required this.acquiredAtMs,
    this.acquiredBy,
    this.variantId,
  }) {
    if (!ownableKinds.contains(kind)) {
      throw ArgumentError.value(kind, 'kind', 'not ownable');
    }
    if ((kind == SkuKind.item) != (variantId != null)) {
      throw ArgumentError.value(
        variantId,
        'variantId',
        'required for an item, and only for an item',
      );
    }
  }

  final SkuKind kind;
  final String? variantId;
  final int acquiredAtMs;

  /// The operation that bought it, or null for a row taken from the
  /// server's state, which doesn't send it (M06 research R12). Nothing
  /// decides anything by it.
  final TxnId? acquiredBy;

  @override
  bool operator ==(Object other) =>
      other is Owned &&
      other.kind == kind &&
      other.variantId == variantId &&
      other.acquiredAtMs == acquiredAtMs &&
      other.acquiredBy == acquiredBy;

  @override
  int get hashCode => Object.hash(kind, variantId, acquiredAtMs, acquiredBy);

  @override
  String toString() => 'Owned(${skuKindWire[kind]} $variantId by $acquiredBy)';
}

/// The one trip started without a result (FR-031).
final class UnfinishedTrip {
  const UnfinishedTrip({
    required this.startTxn,
    required this.tripId,
    required this.contentVersion,
    required this.maxEarningsJenehat,
    required this.startedAtMs,
    this.revived = false,
    this.trafficJamAds = 0,
  });

  final TxnId startTxn;
  final String tripId;
  final int contentVersion;

  /// From the trip's definition at the start.
  final int maxEarningsJenehat;
  final int startedAtMs;
  final bool revived;

  /// 0 to [trafficJamAdsPerTrip].
  final int trafficJamAds;

  UnfinishedTrip copyWith({bool? revived, int? trafficJamAds}) =>
      UnfinishedTrip(
        startTxn: startTxn,
        tripId: tripId,
        contentVersion: contentVersion,
        maxEarningsJenehat: maxEarningsJenehat,
        startedAtMs: startedAtMs,
        revived: revived ?? this.revived,
        trafficJamAds: trafficJamAds ?? this.trafficJamAds,
      );

  @override
  bool operator ==(Object other) =>
      other is UnfinishedTrip &&
      other.startTxn == startTxn &&
      other.tripId == tripId &&
      other.contentVersion == contentVersion &&
      other.maxEarningsJenehat == maxEarningsJenehat &&
      other.startedAtMs == startedAtMs &&
      other.revived == revived &&
      other.trafficJamAds == trafficJamAds;

  @override
  int get hashCode => Object.hash(
    startTxn,
    tripId,
    contentVersion,
    maxEarningsJenehat,
    startedAtMs,
    revived,
    trafficJamAds,
  );

  @override
  String toString() => 'UnfinishedTrip($tripId $startTxn)';

  Map<String, Object> toJson() => {
    'start_txn': startTxn.value,
    'trip_id': tripId,
    'content_version': contentVersion,
    'max_earnings_jenehat': maxEarningsJenehat,
    'started_at_ms': startedAtMs,
    'revived': revived,
    'traffic_jam_ads': trafficJamAds,
  };

  factory UnfinishedTrip.fromJson(Object? json) {
    final map = _object(json, 'unfinished', const {
      'start_txn',
      'trip_id',
      'content_version',
      'max_earnings_jenehat',
      'started_at_ms',
      'revived',
      'traffic_jam_ads',
    });
    final ads = _int(map, 'traffic_jam_ads');
    if (ads < 0 || ads > trafficJamAdsPerTrip) {
      throw FormatException(
        'traffic_jam_ads must be 0 to $trafficJamAdsPerTrip',
        ads,
      );
    }
    return UnfinishedTrip(
      startTxn: _txnId(map, 'start_txn'),
      tripId: _string(map, 'trip_id'),
      contentVersion: _int(map, 'content_version'),
      maxEarningsJenehat: _count(map, 'max_earnings_jenehat'),
      startedAtMs: _int(map, 'started_at_ms'),
      revived: _bool(map, 'revived'),
      trafficJamAds: ads,
    );
  }
}

/// The latest recorded result, which ×2 applies to (FR-035).
final class LastResult {
  const LastResult({
    required this.startTxn,
    required this.outcome,
    required this.earningsJenehat,
    this.doubled = false,
  });

  final TxnId startTxn;
  final TripOutcome outcome;
  final int earningsJenehat;
  final bool doubled;

  @override
  bool operator ==(Object other) =>
      other is LastResult &&
      other.startTxn == startTxn &&
      other.outcome == outcome &&
      other.earningsJenehat == earningsJenehat &&
      other.doubled == doubled;

  @override
  int get hashCode => Object.hash(startTxn, outcome, earningsJenehat, doubled);

  @override
  String toString() =>
      'LastResult($startTxn ${outcome.wire} $earningsJenehat, doubled '
      '$doubled)';

  Map<String, Object> toJson() => {
    'start_txn': startTxn.value,
    'outcome': outcome.wire,
    'earnings_jenehat': earningsJenehat,
    'doubled': doubled,
  };

  factory LastResult.fromJson(Object? json) {
    final map = _object(json, 'last_result', const {
      'start_txn',
      'outcome',
      'earnings_jenehat',
      'doubled',
    });
    final outcome = byWire(TripOutcome.values, (o) => o.wire, map['outcome']);
    if (outcome == null) {
      throw FormatException('unknown outcome', map['outcome']);
    }
    return LastResult(
      startTxn: _txnId(map, 'start_txn'),
      outcome: outcome,
      earningsJenehat: _count(map, 'earnings_jenehat'),
      doubled: _bool(map, 'doubled'),
    );
  }
}

/// The balances, the tank, the inventory, ownership and progress, and since
/// M07 the driver's name and the tutorial grant (specs/012-m07-onboarding,
/// research R8). `apply(state, op)` returns a new one (research R5).
final class EconomyState {
  EconomyState({
    required this.jenehat,
    required this.bonat,
    required this.fuel,
    Map<BoosterId, int> inventory = const {},
    Map<OwnedKey, Owned> ownership = const {},
    Map<String, TripProgress> progress = const {},
    this.unfinished,
    this.lastResult,
    this.displayName,
    this.tutorialGranted = false,
    Map<String, Set<String>> scenesSeen = const {},
    Set<String> requestsClaimed = const {},
  }) : inventory = UnmodifiableMapView({
         for (final MapEntry(:key, :value) in inventory.entries)
           if (value != 0) key: value,
       }),
       ownership = UnmodifiableMapView({...ownership}),
       progress = UnmodifiableMapView({...progress}),
       scenesSeen = UnmodifiableMapView({
         for (final MapEntry(:key, :value) in scenesSeen.entries)
           if (value.isNotEmpty) key: UnmodifiableSetView({...value}),
       }),
       requestsClaimed = UnmodifiableSetView({...requestsClaimed});

  /// A new player (FR-010): a full tank, counted from [nowMs], and nothing
  /// else.
  factory EconomyState.newPlayer({required int fuelMax, required int nowMs}) =>
      EconomyState(
        jenehat: 0,
        bonat: 0,
        fuel: FuelState(liters: fuelMax, countedFromMs: nowMs),
      );

  final int jenehat;

  /// Rises only through a base from the server (FR-011).
  final int bonat;
  final FuelState fuel;

  /// The [inTripBoosters] held, with no zero counts.
  final Map<BoosterId, int> inventory;
  final Map<OwnedKey, Owned> ownership;

  /// By `trip_id`. Entries the active pack lacks are kept (FR-034).
  final Map<String, TripProgress> progress;
  final UnfinishedTrip? unfinished;
  final LastResult? lastResult;

  /// The driver's name: the server's, or a `settings_update` not refused
  /// yet. Null until one is chosen.
  final String? displayName;

  /// The tutorial gift was given (on this phone, or by the server's state).
  final bool tutorialGranted;

  /// The scenes seen per chapter, by the chapter's wire name (M10
  /// contracts/economy-ops.md). The source of truth for "seen" (R3).
  final Map<String, Set<String>> scenesSeen;

  /// The family requests taken, by `request_id`. The reward arrives with the
  /// server's base, never here (constitution IV).
  final Set<String> requestsClaimed;

  EconomyState copyWith({
    int? jenehat,
    int? bonat,
    FuelState? fuel,
    Map<BoosterId, int>? inventory,
    Map<OwnedKey, Owned>? ownership,
    Map<String, TripProgress>? progress,
    UnfinishedTrip? Function()? unfinished,
    LastResult? Function()? lastResult,
    String? Function()? displayName,
    bool? tutorialGranted,
    Map<String, Set<String>>? scenesSeen,
    Set<String>? requestsClaimed,
  }) => EconomyState(
    jenehat: jenehat ?? this.jenehat,
    bonat: bonat ?? this.bonat,
    fuel: fuel ?? this.fuel,
    inventory: inventory ?? this.inventory,
    ownership: ownership ?? this.ownership,
    progress: progress ?? this.progress,
    unfinished: unfinished == null ? this.unfinished : unfinished(),
    lastResult: lastResult == null ? this.lastResult : lastResult(),
    displayName: displayName == null ? this.displayName : displayName(),
    tutorialGranted: tutorialGranted ?? this.tutorialGranted,
    scenesSeen: scenesSeen ?? this.scenesSeen,
    requestsClaimed: requestsClaimed ?? this.requestsClaimed,
  );

  @override
  bool operator ==(Object other) =>
      other is EconomyState &&
      other.jenehat == jenehat &&
      other.bonat == bonat &&
      other.fuel == fuel &&
      _mapEquals(other.inventory, inventory) &&
      _mapEquals(other.ownership, ownership) &&
      _mapEquals(other.progress, progress) &&
      other.unfinished == unfinished &&
      other.lastResult == lastResult &&
      other.displayName == displayName &&
      other.tutorialGranted == tutorialGranted &&
      _nestedSetEquals(other.scenesSeen, scenesSeen) &&
      other.requestsClaimed.length == requestsClaimed.length &&
      other.requestsClaimed.containsAll(requestsClaimed);

  @override
  int get hashCode => Object.hash(
    jenehat,
    bonat,
    fuel,
    inventory.length,
    ownership.length,
    progress.length,
    unfinished,
    lastResult,
    displayName,
    tutorialGranted,
    scenesSeen.length,
    requestsClaimed.length,
  );

  // The name is the player's own; it stays out of logs (M07 plan "Security
  // & privacy").
  @override
  String toString() =>
      'EconomyState(J $jenehat, B $bonat, $fuel, $inventory, '
      '${ownership.length} owned, ${progress.length} trips, $unfinished, '
      '$lastResult, named ${displayName != null}, tutorial $tutorialGranted)';

  /// The base's JSON, as `projection_base.state` holds it in canonical form.
  Map<String, Object> toJson() {
    final owned = ownership.entries.toList()
      ..sort((a, b) {
        final byKind = skuKindWire[a.key.$1]!.compareTo(skuKindWire[b.key.$1]!);
        return byKind != 0 ? byKind : a.key.$2.compareTo(b.key.$2);
      });
    return {
      'jenehat': jenehat,
      'bonat': bonat,
      'fuel': fuel.toJson(),
      'inventory': {
        for (final MapEntry(:key, :value) in inventory.entries)
          boosterWire[key]!: value,
      },
      'ownership': [
        for (final MapEntry(key: (kind, skuId), :value) in owned)
          {
            'kind': skuKindWire[kind]!,
            'sku_id': skuId,
            'variant_id': ?value.variantId,
            'acquired_at_ms': value.acquiredAtMs,
            'acquired_by': ?value.acquiredBy?.value,
          },
      ],
      'progress': {
        for (final MapEntry(:key, :value) in progress.entries)
          key: value.toJson(),
      },
      'unfinished': ?unfinished?.toJson(),
      'last_result': ?lastResult?.toJson(),
      'display_name': ?displayName,
      // Absent when false, so a v3 base's JSON is unchanged.
      if (tutorialGranted) 'tutorial_granted': true,
      // M10: sorted, as the canonical form requires (contracts/economy-ops.md).
      'scenes_seen': {
        for (final key in (scenesSeen.keys.toList()..sort()))
          key: (scenesSeen[key]!.toList()..sort()),
      },
      'requests_claimed': (requestsClaimed.toList()..sort()),
    };
  }

  /// Throws [FormatException] for anything [toJson] can't have written.
  factory EconomyState.fromJson(Object? json) {
    final map = _object(json, 'state', const {
      'jenehat',
      'bonat',
      'fuel',
      'inventory',
      'ownership',
      'progress',
      'unfinished',
      'last_result',
      'display_name',
      'tutorial_granted',
      'scenes_seen',
      'requests_claimed',
    });
    final displayName = map['display_name'];
    if (displayName is! String?) {
      throw FormatException('display_name must be a string', displayName);
    }
    final inventory = <BoosterId, int>{};
    for (final MapEntry(:key, :value) in _object(
      map['inventory'],
      'inventory',
      null,
    ).entries) {
      final booster = fromWire(boosterWire, key);
      if (booster == null || !inTripBoosters.contains(booster)) {
        throw FormatException('not an in-trip booster', key);
      }
      inventory[booster] = _countValue(value, 'inventory.$key');
    }
    final ownership = <OwnedKey, Owned>{};
    final owned = map['ownership'];
    if (owned is! List<Object?>) {
      throw FormatException('ownership must be a list', owned);
    }
    for (final entry in owned) {
      final row = _object(entry, 'ownership', const {
        'kind',
        'sku_id',
        'variant_id',
        'acquired_at_ms',
        'acquired_by',
      });
      final kind = fromWire(skuKindWire, row['kind']);
      if (kind == null || !ownableKinds.contains(kind)) {
        throw FormatException('not an ownable kind', row['kind']);
      }
      final variantId = row['variant_id'];
      if (variantId is! String?) {
        throw FormatException('variant_id must be a string', variantId);
      }
      try {
        ownership[(kind, _string(row, 'sku_id'))] = Owned(
          kind: kind,
          variantId: variantId,
          acquiredAtMs: _int(row, 'acquired_at_ms'),
          acquiredBy: row['acquired_by'] == null
              ? null
              : _txnId(row, 'acquired_by'),
        );
      } on ArgumentError catch (e) {
        throw FormatException('bad ownership: ${e.message}', row);
      }
    }
    return EconomyState(
      jenehat: _count(map, 'jenehat'),
      bonat: _count(map, 'bonat'),
      fuel: FuelState.fromJson(map['fuel']),
      inventory: inventory,
      ownership: ownership,
      progress: {
        for (final MapEntry(:key, :value) in _object(
          map['progress'],
          'progress',
          null,
        ).entries)
          key: TripProgress.fromJson(value),
      },
      unfinished: map['unfinished'] == null
          ? null
          : UnfinishedTrip.fromJson(map['unfinished']),
      lastResult: map['last_result'] == null
          ? null
          : LastResult.fromJson(map['last_result']),
      displayName: displayName,
      tutorialGranted:
          map['tutorial_granted'] != null && _bool(map, 'tutorial_granted'),
      scenesSeen: _scenesSeen(map['scenes_seen']),
      requestsClaimed: _stringSet(map['requests_claimed'], 'requests_claimed'),
    );
  }
}

/// `scenes_seen`: a map of chapter wire names to scene-id arrays. Absent (a
/// base from before M10) reads as empty.
Map<String, Set<String>> _scenesSeen(Object? json) {
  if (json == null) return const {};
  final map = _object(json, 'scenes_seen', null);
  return {
    for (final MapEntry(:key, :value) in map.entries)
      key: _stringSet(value, 'scenes_seen.$key'),
  };
}

Set<String> _stringSet(Object? json, String what) {
  if (json == null) return const {};
  if (json is! List<Object?>) {
    throw FormatException('$what must be a list', json);
  }
  final values = <String>{};
  for (final value in json) {
    if (value is! String) {
      throw FormatException('$what holds a non-string', value);
    }
    values.add(value);
  }
  return values;
}

bool _nestedSetEquals(Map<String, Set<String>> a, Map<String, Set<String>> b) {
  if (a.length != b.length) return false;
  for (final MapEntry(:key, :value) in a.entries) {
    final other = b[key];
    if (other == null ||
        other.length != value.length ||
        !other.containsAll(value)) {
      return false;
    }
  }
  return true;
}

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (a.length != b.length) return false;
  for (final MapEntry(:key, :value) in a.entries) {
    if (!b.containsKey(key) || b[key] != value) return false;
  }
  return true;
}

/// [json] as an object whose keys are all in [allowed] (any key when null).
Map<String, Object?> _object(Object? json, String what, Set<String>? allowed) {
  if (json is! Map<String, Object?>) {
    throw FormatException('$what must be an object', json);
  }
  if (allowed != null) {
    for (final key in json.keys) {
      if (!allowed.contains(key)) {
        throw FormatException('$what has an unknown key', key);
      }
    }
  }
  return json;
}

int _int(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! int) throw FormatException('$key must be an integer', value);
  return value;
}

int? _optionalInt(Map<String, Object?> map, String key) =>
    map[key] == null ? null : _int(map, key);

int _count(Map<String, Object?> map, String key) => _countValue(map[key], key);

int _countValue(Object? value, String what) {
  if (value is! int) throw FormatException('$what must be an integer', value);
  if (value < 0) throw FormatException('$what must not be negative', value);
  return value;
}

String _string(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String) throw FormatException('$key must be a string', value);
  return value;
}

bool _bool(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! bool) throw FormatException('$key must be a boolean', value);
  return value;
}

TxnId _txnId(Map<String, Object?> map, String key) =>
    TxnId.parse(_string(map, key));
