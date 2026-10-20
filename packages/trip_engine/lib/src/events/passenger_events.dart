part of '../events.dart';

final class PassengerBoarded extends DomainEvent {
  const PassengerBoarded(
    super.tMs, {
    required this.passengerId,
    required this.seatId,
  });

  final String passengerId;
  final String seatId;

  @override
  String get name => 'PassengerBoarded';

  @override
  Map<String, Object> get payload => {
    'passenger_id': passengerId,
    'seat_id': seatId,
  };
}

/// A passenger says [slot]. The app shows line `variant % lines.length` of
/// the pool [speechKey], filling `{amount}` and `{station}`.
final class PassengerSpeaks extends DomainEvent {
  const PassengerSpeaks(
    super.tMs, {
    required this.passengerId,
    required this.slot,
    required this.speechKey,
    required this.variant,
    this.amountPiasters,
    this.stationId,
  });

  final String passengerId;
  final SpeechSlot slot;
  final String speechKey;

  /// The PRNG draw for this line (rules.md §12, §13).
  final int variant;
  final int? amountPiasters;
  final String? stationId;

  @override
  String get name => 'PassengerSpeaks';

  @override
  Map<String, Object> get payload => {
    'passenger_id': passengerId,
    'slot': slot.wire,
    'speech_key': speechKey,
    'variant': variant,
    'amount_piasters': ?amountPiasters,
    'station_id': ?stationId,
  };
}

final class PassengerWaking extends DomainEvent with _OnePassenger {
  const PassengerWaking(super.tMs, {required this.passengerId});

  @override
  final String passengerId;

  @override
  String get name => 'PassengerWaking';
}

final class PassengerWoke extends DomainEvent with _OnePassenger {
  const PassengerWoke(super.tMs, {required this.passengerId});

  @override
  final String passengerId;

  @override
  String get name => 'PassengerWoke';
}

final class PassengerFellAsleep extends DomainEvent with _OnePassenger {
  const PassengerFellAsleep(super.tMs, {required this.passengerId});

  @override
  final String passengerId;

  @override
  String get name => 'PassengerFellAsleep';
}

/// A muted passenger was tapped, [taps] times so far.
final class PassengerCalled extends DomainEvent {
  const PassengerCalled(
    super.tMs, {
    required this.passengerId,
    required this.taps,
  });

  final String passengerId;
  final int taps;

  @override
  String get name => 'PassengerCalled';

  @override
  Map<String, Object> get payload => {
    'passenger_id': passengerId,
    'taps': taps,
  };
}

final class PassengerAttentive extends DomainEvent with _OnePassenger {
  const PassengerAttentive(super.tMs, {required this.passengerId});

  @override
  final String passengerId;

  @override
  String get name => 'PassengerAttentive';
}

final class PassengerMuted extends DomainEvent with _OnePassenger {
  const PassengerMuted(super.tMs, {required this.passengerId});

  @override
  final String passengerId;

  @override
  String get name => 'PassengerMuted';
}

final class PatienceRanOut extends DomainEvent with _OnePassenger {
  const PatienceRanOut(super.tMs, {required this.passengerId});

  @override
  final String passengerId;

  @override
  String get name => 'PatienceRanOut';
}

/// `drop_me_here`: the passenger now gets off at [deadlineMs].
final class StopChanged extends DomainEvent {
  const StopChanged(
    super.tMs, {
    required this.passengerId,
    required this.deadlineMs,
  });

  final String passengerId;
  final int deadlineMs;

  @override
  String get name => 'StopChanged';

  @override
  Map<String, Object> get payload => {
    'passenger_id': passengerId,
    'deadline_ms': deadlineMs,
  };
}

final class PassengerAlighted extends DomainEvent {
  const PassengerAlighted(
    super.tMs, {
    required this.passengerId,
    required this.outcome,
  });

  final String passengerId;
  final AlightOutcome outcome;

  @override
  String get name => 'PassengerAlighted';

  @override
  Map<String, Object> get payload => {
    'passenger_id': passengerId,
    'outcome': outcome.wire,
  };
}
