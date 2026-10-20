// Money in transit (data-model.md "MoneyToken", rules.md §5).
import '../money.dart';
import '../wire.dart';
import 'keep.dart';

/// Who holds or receives a token: the driver, or a passenger by id. Seats
/// are reached through their passengers.
extension type const Holder._(String wire) {
  const Holder.passenger(this.wire);

  static const Holder driver = Holder._('DRIVER');

  bool get isDriver => wire == driver.wire;

  /// The passenger id. Meaningless for the driver.
  String get passengerId => wire;
}

enum TokenKind {
  fare,
  change,
  returned,
  redirect,
  breakOut,
  breakIn;

  String get wire => this == returned ? 'return' : wireName(this);

  /// Fares, returns and the second half of a change request travel to the
  /// driver; the rest travel to a passenger.
  bool get towardDriver => this == fare || this == returned || this == breakIn;
}

/// A hop in progress, to the next holder.
final class Hop {
  const Hop({
    required this.to,
    required this.elapsedMs,
    required this.durationMs,
  });

  final Holder to;
  final int elapsedMs;
  final int durationMs;

  Map<String, Object> toJson() => {
    'to': to.wire,
    'elapsed_ms': elapsedMs,
    'duration_ms': durationMs,
  };
}

final class MoneyToken {
  const MoneyToken._({
    required this.tokenId,
    required this.kind,
    required this.pieces,
    required this.owner,
    required this.target,
    required this.holder,
    required this.hop,
    required this.hopsDone,
    required this.blockedBy,
    required this.droppedUntilMs,
  });

  /// Creation order, from 1.
  final int tokenId;
  final TokenKind kind;
  final Pieces pieces;

  /// The passenger it concerns: the payer for a fare or a return, the
  /// recipient for change.
  final String owner;
  final Holder target;
  final Holder holder;

  /// Set while moving.
  final Hop? hop;

  /// 0 while on its first hop (for undo).
  final int hopsDone;

  /// The passenger stopping it, if any.
  final String? blockedBy;

  /// Set by a bump: the deadline for `CollectDropped`.
  final int? droppedUntilMs;

  bool get isDropped => droppedUntilMs != null;

  /// `elapsed × 1000 ~/ duration` while hopping, for the scene to
  /// interpolate; null otherwise.
  int? get progressPermille => switch (hop) {
    final hop? => hop.elapsedMs * 1000 ~/ hop.durationMs,
    null => null,
  };

  Map<String, Object> toJson() => {
    'token_id': tokenId,
    'kind': kind.wire,
    'pieces': pieces.toJson(),
    'owner': owner,
    'target': target.wire,
    'holder': holder.wire,
    if (hop case final hop?) 'hop': hop.toJson(),
    'hops_done': hopsDone,
    'blocked_by': ?blockedBy,
    'dropped_until_ms': ?droppedUntilMs,
  };
}

/// A new token at its first holder.
MoneyToken makeMoneyToken({
  required int tokenId,
  required TokenKind kind,
  required Pieces pieces,
  required String owner,
  required Holder target,
  required Holder holder,
}) => MoneyToken._(
  tokenId: tokenId,
  kind: kind,
  pieces: pieces,
  owner: owner,
  target: target,
  holder: holder,
  hop: null,
  hopsDone: 0,
  blockedBy: null,
  droppedUntilMs: null,
);

extension MoneyTokenUpdate on MoneyToken {
  MoneyToken copyWith({
    Holder? holder,
    Object? hop = keep,
    int? hopsDone,
    Object? blockedBy = keep,
    Object? droppedUntilMs = keep,
  }) => MoneyToken._(
    tokenId: tokenId,
    kind: kind,
    pieces: pieces,
    owner: owner,
    target: target,
    holder: holder ?? this.holder,
    hop: kept(hop, this.hop),
    hopsDone: hopsDone ?? this.hopsDone,
    blockedBy: kept(blockedBy, this.blockedBy),
    droppedUntilMs: kept(droppedUntilMs, this.droppedUntilMs),
  );
}
