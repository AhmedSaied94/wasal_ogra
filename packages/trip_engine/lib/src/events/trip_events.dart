part of '../events.dart';

final class EventStarted extends DomainEvent {
  const EventStarted(super.tMs, {required this.index, required this.eventId});

  /// The authored event's index in the definition.
  final int index;
  final EventId eventId;

  @override
  String get name => 'EventStarted';

  @override
  Map<String, Object> get payload => {
    'index': index,
    'event_id': wireName(eventId),
  };
}

/// An authored event whose passengers weren't where it needed them.
final class EventSkipped extends DomainEvent {
  const EventSkipped(super.tMs, {required this.index, required this.eventId});

  final int index;
  final EventId eventId;

  @override
  String get name => 'EventSkipped';

  @override
  Map<String, Object> get payload => {
    'index': index,
    'event_id': wireName(eventId),
  };
}

final class FareIncreased extends DomainEvent {
  const FareIncreased(
    super.tMs, {
    required this.amountPiasters,
    required this.totalIncreasePiasters,
  });

  final int amountPiasters;
  final int totalIncreasePiasters;

  @override
  String get name => 'FareIncreased';

  @override
  Map<String, Object> get payload => {
    'amount_piasters': amountPiasters,
    'total_increase_piasters': totalIncreasePiasters,
  };
}

/// The remaining stations moved by [deltaMs] (after any clamp).
final class ScheduleShifted extends DomainEvent {
  const ScheduleShifted(super.tMs, {required this.deltaMs});

  final int deltaMs;

  @override
  String get name => 'ScheduleShifted';

  @override
  Map<String, Object> get payload => {'delta_ms': deltaMs};
}

final class StationWarning extends DomainEvent {
  const StationWarning(
    super.tMs, {
    required this.stationId,
    required this.atMs,
    required this.alighting,
    required this.owed,
  });

  final String stationId;
  final int atMs;

  /// Who gets off there.
  final List<String> alighting;

  /// The owed subset of [alighting].
  final List<String> owed;

  @override
  String get name => 'StationWarning';

  @override
  Map<String, Object> get payload => {
    'station_id': stationId,
    'at_ms': atMs,
    'alighting': alighting,
    'owed': owed,
  };
}

final class StationReached extends DomainEvent {
  const StationReached(super.tMs, {required this.stationId});

  final String stationId;

  @override
  String get name => 'StationReached';

  @override
  Map<String, Object> get payload => {'station_id': stationId};
}

/// Reputation changed by [delta] to [value]. [value] is below 0 only in the
/// change that fails the trip.
final class ReputationChanged extends DomainEvent {
  const ReputationChanged(
    super.tMs, {
    required this.delta,
    required this.cause,
    required this.value,
  });

  final int delta;
  final RepCause cause;
  final int value;

  @override
  String get name => 'ReputationChanged';

  @override
  Map<String, Object> get payload => {
    'delta': delta,
    'cause': cause.wire,
    'value': value,
  };
}

final class MistakeMade extends DomainEvent {
  const MistakeMade(
    super.tMs, {
    required this.passengerId,
    required this.kind,
    required this.amountPiasters,
  });

  final String passengerId;
  final MistakeKind kind;
  final int amountPiasters;

  @override
  String get name => 'MistakeMade';

  @override
  Map<String, Object> get payload => {
    'passenger_id': passengerId,
    'kind': kind.wire,
    'amount_piasters': amountPiasters,
  };
}

final class BoosterUsed extends DomainEvent {
  const BoosterUsed(super.tMs, {required this.boosterId});

  final BoosterId boosterId;

  @override
  String get name => 'BoosterUsed';

  @override
  Map<String, Object> get payload => {'booster_id': wireName(boosterId)};
}

final class LedgerPeekStarted extends DomainEvent {
  const LedgerPeekStarted(super.tMs, {required this.untilMs});

  final int untilMs;

  @override
  String get name => 'LedgerPeekStarted';

  @override
  Map<String, Object> get payload => {'until_ms': untilMs};
}

final class LedgerPeekEnded extends DomainEvent {
  const LedgerPeekEnded(super.tMs);

  @override
  String get name => 'LedgerPeekEnded';

  @override
  Map<String, Object> get payload => const {};
}

final class TripFailed extends DomainEvent {
  const TripFailed(
    super.tMs, {
    required this.reputationLost,
    required this.revivable,
  });

  final Map<RepCause, int> reputationLost;
  final bool revivable;

  @override
  String get name => 'TripFailed';

  @override
  Map<String, Object> get payload => {
    'reputation_lost': reputationLostJson(reputationLost),
    'revivable': revivable,
  };
}

final class TripRevived extends DomainEvent {
  const TripRevived(super.tMs, {required this.reputation});

  final int reputation;

  @override
  String get name => 'TripRevived';

  @override
  Map<String, Object> get payload => {'reputation': reputation};
}

final class TripFinished extends DomainEvent {
  const TripFinished(super.tMs, {required this.result});

  final TripResult result;

  @override
  String get name => 'TripFinished';

  @override
  Map<String, Object> get payload => {'result': result.toJson()};
}

final class TripAbandoned extends DomainEvent {
  const TripAbandoned(super.tMs, {required this.result});

  final TripResult result;

  @override
  String get name => 'TripAbandoned';

  @override
  Map<String, Object> get payload => {'result': result.toJson()};
}
