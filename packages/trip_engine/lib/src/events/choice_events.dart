part of '../events.dart';

final class ClaimRaised extends DomainEvent with _OnePassenger {
  const ClaimRaised(super.tMs, {required this.passengerId});

  @override
  final String passengerId;

  @override
  String get name => 'ClaimRaised';
}

final class ClaimAccepted extends DomainEvent with _OnePassenger {
  const ClaimAccepted(super.tMs, {required this.passengerId});

  @override
  final String passengerId;

  @override
  String get name => 'ClaimAccepted';
}

final class LiarCaught extends DomainEvent with _OnePassenger {
  const LiarCaught(super.tMs, {required this.passengerId});

  @override
  final String passengerId;

  @override
  String get name => 'LiarCaught';
}

/// The player insisted against a passenger who had paid.
final class FalseAccusation extends DomainEvent with _OnePassenger {
  const FalseAccusation(super.tMs, {required this.passengerId});

  @override
  final String passengerId;

  @override
  String get name => 'FalseAccusation';
}

final class DisputeRaised extends DomainEvent {
  const DisputeRaised(
    super.tMs, {
    required this.disputeId,
    required this.passengerIds,
  });

  /// The authored event's index.
  final int disputeId;
  final List<String> passengerIds;

  @override
  String get name => 'DisputeRaised';

  @override
  Map<String, Object> get payload => {
    'dispute_id': disputeId,
    'passenger_ids': passengerIds,
  };
}

final class DisputeResolved extends DomainEvent {
  const DisputeResolved(
    super.tMs, {
    required this.disputeId,
    required this.right,
  });

  final int disputeId;
  final bool right;

  @override
  String get name => 'DisputeResolved';

  @override
  Map<String, Object> get payload => {'dispute_id': disputeId, 'right': right};
}

final class ChangeRequestRaised extends DomainEvent {
  const ChangeRequestRaised(
    super.tMs, {
    required this.passengerId,
    required this.amountPiasters,
  });

  final String passengerId;

  /// The note the passenger wants broken.
  final int amountPiasters;

  @override
  String get name => 'ChangeRequestRaised';

  @override
  Map<String, Object> get payload => {
    'passenger_id': passengerId,
    'amount_piasters': amountPiasters,
  };
}

final class ChangeRequestResolved extends DomainEvent {
  const ChangeRequestResolved(
    super.tMs, {
    required this.passengerId,
    required this.agreed,
  });

  final String passengerId;
  final bool agreed;

  @override
  String get name => 'ChangeRequestResolved';

  @override
  Map<String, Object> get payload => {
    'passenger_id': passengerId,
    'agreed': agreed,
  };
}

/// The passenger's note reached the tray.
final class ChangeRequestCompleted extends DomainEvent with _OnePassenger {
  const ChangeRequestCompleted(super.tMs, {required this.passengerId});

  @override
  final String passengerId;

  @override
  String get name => 'ChangeRequestCompleted';
}
