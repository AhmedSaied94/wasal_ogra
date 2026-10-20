// The whole trip at one moment (data-model.md "TripState"). Immutable: each
// step or command returns a new one, sharing what didn't change (research R2).
import 'package:content_models/content_models.dart';

import '../money.dart';
import '../wire.dart';
import 'choices.dart';
import 'counters.dart';
import 'passenger.dart';
import 'result.dart';
import 'station.dart';
import 'token.dart';

enum TripStatus {
  running,
  paused,
  failed,
  finished,
  abandoned;

  String get wire => name;
}

final class TripState {
  const TripState._({
    required this.tMs,
    required this.status,
    required this.reputation,
    required this.tray,
    required this.hand,
    required this.passengers,
    required this.tokens,
    required this.nextTokenId,
    required this.schedule,
    required this.nextStationIndex,
    required this.eventsFired,
    required this.fareIncreasePiasters,
    required this.oldFarePayers,
    required this.trafficActive,
    required this.claims,
    required this.disputes,
    required this.changeRequests,
    required this.pendingBreaks,
    required this.breaksUsed,
    required this.ledgerPeekUntilMs,
    required this.lastSend,
    required this.counters,
    required this.mistakes,
    required this.reputationLost,
    required this.boostersUsed,
    required this.revived,
    required this.revivable,
    required this.commandsAccepted,
    required this.prng,
    required this.result,
    required this._maxBreakRequests,
  });

  /// The clock, a multiple of 33.
  final int tMs;
  final TripStatus status;

  /// 0..100 as reported. It goes below 0 only in the change that fails the
  /// trip.
  final int reputation;
  final Pieces tray;
  final Pieces hand;

  /// In definition order, including those not yet aboard and those gone.
  final List<PassengerState> passengers;

  /// Live tokens in id order.
  final List<MoneyToken> tokens;
  final int nextTokenId;

  /// One per trip station, in order.
  final List<StationState> schedule;

  /// The index of the next unprocessed station; the station count once all
  /// are done.
  final int nextStationIndex;

  /// Per authored event: fired or skipped.
  final List<bool> eventsFired;
  final int fareIncreasePiasters;

  /// Passengers listed by any `fare_increase`.
  final Set<String> oldFarePayers;

  /// From a `traffic` event until the next station is reached.
  final bool trafficActive;
  final Map<String, Claim> claims;

  /// Keyed by the event's index.
  final Map<int, Dispute> disputes;
  final Map<String, ChangeRequest> changeRequests;
  final List<PendingBreak> pendingBreaks;
  final int breaksUsed;

  /// While [tMs] is below this, who has paid is readable.
  final int? ledgerPeekUntilMs;
  final LastSend? lastSend;
  final Counters counters;
  final List<Mistake> mistakes;

  /// Penalties applied, by cause.
  final Map<RepCause, int> reputationLost;
  final List<BoosterId> boostersUsed;
  final bool revived;

  /// False after a story-trip fight, or once revived.
  final bool revivable;

  /// Against the cap of 1,200, which `Abandon` is exempt from.
  final int commandsAccepted;

  /// The xorshift32 state.
  final int prng;

  /// Set when the trip finishes, fails or is abandoned.
  final TripResult? result;

  final int _maxBreakRequests;

  bool get ledgerPeekActive => switch (ledgerPeekUntilMs) {
    final until? => tMs < until,
    null => false,
  };

  /// The undo deadline, or null when `UndoLastSend` would be rejected.
  int? get undoAvailableUntilMs {
    final send = lastSend;
    if (send == null || status != TripStatus.running || tMs > send.untilMs) {
      return null;
    }
    final sent = token(send.tokenId);
    if (sent == null || sent.isDropped || sent.hopsDone != 0) return null;
    return send.untilMs;
  }

  /// The next unprocessed station, or null.
  StationState? get nextStation =>
      nextStationIndex < schedule.length ? schedule[nextStationIndex] : null;

  /// `rules.max_break_requests − breaks_used`.
  int get breaksLeft => _maxBreakRequests - breaksUsed;

  PassengerState? passenger(String passengerId) {
    for (final passenger in passengers) {
      if (passenger.passengerId == passengerId) return passenger;
    }
    return null;
  }

  MoneyToken? token(int tokenId) {
    for (final token in tokens) {
      if (token.tokenId == tokenId) return token;
    }
    return null;
  }

  /// The canonical form the rebuild test compares (SC-009).
  Map<String, Object> toJson() => {
    't_ms': tMs,
    'status': status.wire,
    'reputation': reputation,
    'tray': tray.toJson(),
    'hand': hand.toJson(),
    'passengers': [for (final passenger in passengers) passenger.toJson()],
    'tokens': [for (final token in tokens) token.toJson()],
    'next_token_id': nextTokenId,
    'schedule': [for (final station in schedule) station.toJson()],
    'next_station': nextStationIndex,
    'events_fired': eventsFired,
    'fare_increase_piasters': fareIncreasePiasters,
    'old_fare_payers': oldFarePayers.toList()..sort(),
    'traffic_active': trafficActive,
    'claims': {
      for (final MapEntry(:key, :value) in claims.entries) key: value.toJson(),
    },
    'disputes': {
      for (final MapEntry(:key, :value) in disputes.entries)
        '$key': value.toJson(),
    },
    'change_requests': {
      for (final MapEntry(:key, :value) in changeRequests.entries)
        key: value.toJson(),
    },
    'pending_breaks': [for (final pending in pendingBreaks) pending.toJson()],
    'breaks_used': breaksUsed,
    'ledger_peek_until_ms': ?ledgerPeekUntilMs,
    if (lastSend case final send?) 'last_send': send.toJson(),
    'counters': counters.toJson(),
    'mistakes': [for (final mistake in mistakes) mistake.toJson()],
    'reputation_lost': reputationLostJson(reputationLost),
    'boosters_used': [for (final booster in boostersUsed) wireName(booster)],
    'revived': revived,
    'revivable': revivable,
    'commands_accepted': commandsAccepted,
    'prng': prng,
    if (result case final result?) 'result': result.toJson(),
  };
}

/// Builds a state. Only the rules call it (`rules/transition.dart`), with
/// unmodifiable collections.
TripState makeTripState({
  required int tMs,
  required TripStatus status,
  required int reputation,
  required Pieces tray,
  required Pieces hand,
  required List<PassengerState> passengers,
  required List<MoneyToken> tokens,
  required int nextTokenId,
  required List<StationState> schedule,
  required int nextStationIndex,
  required List<bool> eventsFired,
  required int fareIncreasePiasters,
  required Set<String> oldFarePayers,
  required bool trafficActive,
  required Map<String, Claim> claims,
  required Map<int, Dispute> disputes,
  required Map<String, ChangeRequest> changeRequests,
  required List<PendingBreak> pendingBreaks,
  required int breaksUsed,
  required int? ledgerPeekUntilMs,
  required LastSend? lastSend,
  required Counters counters,
  required List<Mistake> mistakes,
  required Map<RepCause, int> reputationLost,
  required List<BoosterId> boostersUsed,
  required bool revived,
  required bool revivable,
  required int commandsAccepted,
  required int prng,
  required TripResult? result,
  required int maxBreakRequests,
}) => TripState._(
  tMs: tMs,
  status: status,
  reputation: reputation,
  tray: tray,
  hand: hand,
  passengers: passengers,
  tokens: tokens,
  nextTokenId: nextTokenId,
  schedule: schedule,
  nextStationIndex: nextStationIndex,
  eventsFired: eventsFired,
  fareIncreasePiasters: fareIncreasePiasters,
  oldFarePayers: oldFarePayers,
  trafficActive: trafficActive,
  claims: claims,
  disputes: disputes,
  changeRequests: changeRequests,
  pendingBreaks: pendingBreaks,
  breaksUsed: breaksUsed,
  ledgerPeekUntilMs: ledgerPeekUntilMs,
  lastSend: lastSend,
  counters: counters,
  mistakes: mistakes,
  reputationLost: reputationLost,
  boostersUsed: boostersUsed,
  revived: revived,
  revivable: revivable,
  commandsAccepted: commandsAccepted,
  prng: prng,
  result: result,
  maxBreakRequests: maxBreakRequests,
);
