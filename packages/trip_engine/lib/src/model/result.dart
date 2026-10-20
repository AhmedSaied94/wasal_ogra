// The outcome of a trip (data-model.md "TripResult", FR-058). B03 reads it in
// `trip_result`, and fixtures pin it.
import 'dart:collection';

import 'package:content_models/content_models.dart';

import '../json_read.dart';
import '../wire.dart';
import 'counters.dart';

enum TripOutcome {
  finished,
  failed,
  abandoned;

  String get wire => name;
}

final class StarFlags {
  const StarFlags({
    required this.reached,
    required this.noFights,
    required this.noMistakes,
  });

  final bool reached;
  final bool noFights;
  final bool noMistakes;

  Map<String, Object> toJson() => {
    'reached': reached,
    'no_fights': noFights,
    'no_mistakes': noMistakes,
  };
}

final class TripResult {
  TripResult._({
    required this.tripId,
    required this.rev,
    required this.outcome,
    required this.stars,
    required this.starFlags,
    required this.faresCollectedPiasters,
    required this.overpaidPiasters,
    required this.tipsPiasters,
    required this.earningsJenehat,
    required this.fights,
    required this.lostFares,
    required this.missedStops,
    required this.impatient,
    required this.caughtLiars,
    required List<Mistake> mistakes,
    required this.reputation,
    required Map<RepCause, int> reputationLost,
    required this.durationMs,
    required List<BoosterId> boostersUsed,
    required this.revived,
    required this.commandLogHash,
  }) : mistakes = List.unmodifiable(mistakes),
       reputationLost = UnmodifiableMapView({
         for (final cause in RepCause.values) cause: ?reputationLost[cause],
       }),
       boostersUsed = List.unmodifiable(boostersUsed);

  /// The wire form. Throws [FormatException] for anything malformed.
  factory TripResult.fromJson(Map<String, Object?> json) {
    expectKeys(json, _keys, 'TripResult');
    final flags = readObject(json, 'star_flags');
    expectKeys(flags, const {
      'reached',
      'no_fights',
      'no_mistakes',
    }, 'star_flags');
    final lost = readObject(json, 'reputation_lost');
    return TripResult._(
      tripId: readString(json, 'trip_id'),
      rev: readInt(json, 'rev'),
      outcome: readWire(
        TripOutcome.values,
        (o) => o.wire,
        json['outcome'],
        'outcome',
      ),
      stars: readInt(json, 'stars'),
      starFlags: StarFlags(
        reached: readBool(flags, 'reached'),
        noFights: readBool(flags, 'no_fights'),
        noMistakes: readBool(flags, 'no_mistakes'),
      ),
      faresCollectedPiasters: readInt(json, 'fares_collected_piasters'),
      overpaidPiasters: readInt(json, 'overpaid_piasters'),
      tipsPiasters: readInt(json, 'tips_piasters'),
      earningsJenehat: readInt(json, 'earnings_jenehat'),
      fights: readInt(json, 'fights'),
      lostFares: readInt(json, 'lost_fares'),
      missedStops: readInt(json, 'missed_stops'),
      impatient: readInt(json, 'impatient'),
      caughtLiars: readInt(json, 'caught_liars'),
      mistakes: [
        for (final item in readList(json, 'mistakes'))
          _mistake(asObject(item, 'mistake')),
      ],
      reputation: readInt(json, 'reputation'),
      reputationLost: {
        for (final MapEntry(:key, :value) in lost.entries)
          readWire(
            RepCause.values,
            (c) => c.wire,
            key,
            'reputation_lost',
          ): switch (value) {
            final int amount => amount,
            _ => throw FormatException(
              'reputation_lost.$key must be an integer',
            ),
          },
      },
      durationMs: readInt(json, 'duration_ms'),
      boostersUsed: [
        for (final item in readList(json, 'boosters_used'))
          readWire(BoosterId.values, wireName, item, 'boosters_used'),
      ],
      revived: readBool(json, 'revived'),
      commandLogHash: readString(json, 'command_log_hash'),
    );
  }

  static Mistake _mistake(Map<String, Object?> json) {
    expectKeys(json, const {
      'passenger_id',
      'kind',
      'amount_piasters',
    }, 'mistake');
    return Mistake(
      passengerId: readString(json, 'passenger_id'),
      kind: readWire(
        MistakeKind.values,
        (k) => k.wire,
        json['kind'],
        'mistake.kind',
      ),
      amountPiasters: readInt(json, 'amount_piasters'),
    );
  }

  static const _keys = {
    'trip_id',
    'rev',
    'outcome',
    'stars',
    'star_flags',
    'fares_collected_piasters',
    'overpaid_piasters',
    'tips_piasters',
    'earnings_jenehat',
    'fights',
    'lost_fares',
    'missed_stops',
    'impatient',
    'caught_liars',
    'mistakes',
    'reputation',
    'reputation_lost',
    'duration_ms',
    'boosters_used',
    'revived',
    'command_log_hash',
  };

  final String tripId;
  final int rev;
  final TripOutcome outcome;

  /// 0..3, and 0 unless finished.
  final int stars;
  final StarFlags starFlags;

  /// Σ `min(fare, paid_in)` over passengers who sent their fare.
  final int faresCollectedPiasters;
  final int overpaidPiasters;
  final int tipsPiasters;

  /// 0 unless finished.
  final int earningsJenehat;
  final int fights;
  final int lostFares;
  final int missedStops;
  final int impatient;
  final int caughtLiars;
  final List<Mistake> mistakes;

  /// The final reputation, 0..100.
  final int reputation;

  /// Penalties by cause; only causes with a loss.
  final Map<RepCause, int> reputationLost;

  /// The clock when the trip ended.
  final int durationMs;
  final List<BoosterId> boostersUsed;
  final bool revived;

  /// Lowercase hex SHA-256 of the command log (research R9).
  final String commandLogHash;

  Map<String, Object> toJson() => {
    'trip_id': tripId,
    'rev': rev,
    'outcome': outcome.wire,
    'stars': stars,
    'star_flags': starFlags.toJson(),
    'fares_collected_piasters': faresCollectedPiasters,
    'overpaid_piasters': overpaidPiasters,
    'tips_piasters': tipsPiasters,
    'earnings_jenehat': earningsJenehat,
    'fights': fights,
    'lost_fares': lostFares,
    'missed_stops': missedStops,
    'impatient': impatient,
    'caught_liars': caughtLiars,
    'mistakes': [for (final mistake in mistakes) mistake.toJson()],
    'reputation': reputation,
    'reputation_lost': reputationLostJson(reputationLost),
    'duration_ms': durationMs,
    'boosters_used': [for (final booster in boostersUsed) wireName(booster)],
    'revived': revived,
    'command_log_hash': commandLogHash,
  };
}

/// A result as the rules build it (rules.md §11).
TripResult makeTripResult({
  required String tripId,
  required int rev,
  required TripOutcome outcome,
  required int stars,
  required StarFlags starFlags,
  required int faresCollectedPiasters,
  required int overpaidPiasters,
  required int tipsPiasters,
  required int earningsJenehat,
  required Counters counters,
  required List<Mistake> mistakes,
  required int reputation,
  required Map<RepCause, int> reputationLost,
  required int durationMs,
  required List<BoosterId> boostersUsed,
  required bool revived,
  required String commandLogHash,
}) => TripResult._(
  tripId: tripId,
  rev: rev,
  outcome: outcome,
  stars: stars,
  starFlags: starFlags,
  faresCollectedPiasters: faresCollectedPiasters,
  overpaidPiasters: overpaidPiasters,
  tipsPiasters: tipsPiasters,
  earningsJenehat: earningsJenehat,
  fights: counters.fights,
  lostFares: counters.lostFares,
  missedStops: counters.missedStops,
  impatient: counters.impatient,
  caughtLiars: counters.caughtLiars,
  mistakes: mistakes,
  reputation: reputation,
  reputationLost: reputationLost,
  durationMs: durationMs,
  boostersUsed: boostersUsed,
  revived: revived,
  commandLogHash: commandLogHash,
);
