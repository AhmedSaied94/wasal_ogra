part of '../events.dart';

/// A passenger sent a fare token of [amountPiasters].
final class FareSent extends DomainEvent {
  const FareSent(
    super.tMs, {
    required this.passengerId,
    required this.tokenId,
    required this.amountPiasters,
  });

  final String passengerId;
  final int tokenId;
  final int amountPiasters;

  @override
  String get name => 'FareSent';

  @override
  Map<String, Object> get payload => {
    'passenger_id': passengerId,
    'token_id': tokenId,
    'amount_piasters': amountPiasters,
  };
}

/// The driver sent the hand as change to a passenger.
final class ChangeSent extends DomainEvent {
  const ChangeSent(
    super.tMs, {
    required this.passengerId,
    required this.tokenId,
    required this.amountPiasters,
  });

  final String passengerId;
  final int tokenId;
  final int amountPiasters;

  @override
  String get name => 'ChangeSent';

  @override
  Map<String, Object> get payload => {
    'passenger_id': passengerId,
    'token_id': tokenId,
    'amount_piasters': amountPiasters,
  };
}

final class SendUndone extends DomainEvent with _OneToken {
  const SendUndone(super.tMs, {required this.tokenId});

  @override
  final int tokenId;

  @override
  String get name => 'SendUndone';
}

final class TokenHopStarted extends DomainEvent {
  const TokenHopStarted(
    super.tMs, {
    required this.tokenId,
    required this.from,
    required this.to,
    required this.durationMs,
  });

  final int tokenId;
  final Holder from;
  final Holder to;
  final int durationMs;

  @override
  String get name => 'TokenHopStarted';

  @override
  Map<String, Object> get payload => {
    'token_id': tokenId,
    'from': from.wire,
    'to': to.wire,
    'duration_ms': durationMs,
  };
}

/// A token can't move because the passenger [by] isn't able.
final class TokenBlocked extends DomainEvent {
  const TokenBlocked(super.tMs, {required this.tokenId, required this.by});

  final int tokenId;
  final String by;

  @override
  String get name => 'TokenBlocked';

  @override
  Map<String, Object> get payload => {'token_id': tokenId, 'by': by};
}

final class TokenUnblocked extends DomainEvent with _OneToken {
  const TokenUnblocked(super.tMs, {required this.tokenId});

  @override
  final int tokenId;

  @override
  String get name => 'TokenUnblocked';
}

/// A token reached the driver, and its pieces entered the tray.
final class MoneyArrivedAtDriver extends DomainEvent {
  const MoneyArrivedAtDriver(
    super.tMs, {
    required this.tokenId,
    required this.kind,
    required this.amountPiasters,
  });

  final int tokenId;
  final TokenKind kind;
  final int amountPiasters;

  @override
  String get name => 'MoneyArrivedAtDriver';

  @override
  Map<String, Object> get payload => {
    'token_id': tokenId,
    'kind': kind.wire,
    'amount_piasters': amountPiasters,
  };
}

/// How change reaching a passenger was judged (rules.md §6.5).
enum ChangeResult {
  exact,
  short,
  over,
  notOwed;

  String get wire => wireName(this);
}

final class ChangeDelivered extends DomainEvent {
  const ChangeDelivered(
    super.tMs, {
    required this.tokenId,
    required this.passengerId,
    required this.result,
    required this.amountPiasters,
  });

  final int tokenId;
  final String passengerId;
  final ChangeResult result;
  final int amountPiasters;

  @override
  String get name => 'ChangeDelivered';

  @override
  Map<String, Object> get payload => {
    'token_id': tokenId,
    'passenger_id': passengerId,
    'result': result.wire,
    'amount_piasters': amountPiasters,
  };
}

/// An honest passenger's returned money reached the tray.
final class ExcessReturned extends DomainEvent {
  const ExcessReturned(
    super.tMs, {
    required this.passengerId,
    required this.amountPiasters,
  });

  final String passengerId;
  final int amountPiasters;

  @override
  String get name => 'ExcessReturned';

  @override
  Map<String, Object> get payload => {
    'passenger_id': passengerId,
    'amount_piasters': amountPiasters,
  };
}

final class MoneyDropped extends DomainEvent with _OneToken {
  const MoneyDropped(super.tMs, {required this.tokenId});

  @override
  final int tokenId;

  @override
  String get name => 'MoneyDropped';
}

final class DroppedCollected extends DomainEvent with _OneToken {
  const DroppedCollected(super.tMs, {required this.tokenId});

  @override
  final int tokenId;

  @override
  String get name => 'DroppedCollected';
}

final class DroppedLost extends DomainEvent with _OneToken {
  const DroppedLost(super.tMs, {required this.tokenId});

  @override
  final int tokenId;

  @override
  String get name => 'DroppedLost';
}

final class BreakRequested extends DomainEvent {
  const BreakRequested(
    super.tMs, {
    required this.denomination,
    required this.completesAtMs,
  });

  final int denomination;
  final int completesAtMs;

  @override
  String get name => 'BreakRequested';

  @override
  Map<String, Object> get payload => {
    'denomination': denomination,
    'completes_at_ms': completesAtMs,
  };
}

final class BreakCompleted extends DomainEvent {
  const BreakCompleted(
    super.tMs, {
    required this.denomination,
    required this.pieces,
  });

  final int denomination;
  final Pieces pieces;

  @override
  String get name => 'BreakCompleted';

  @override
  Map<String, Object> get payload => {
    'denomination': denomination,
    'pieces': pieces.toJson(),
  };
}
