// What a trip counts: the counters, the mistakes and the reputation causes
// (data-model.md "Counters", "Mistake", "RepCause").
import '../wire.dart';

final class Counters {
  const Counters._({
    required this.fights,
    required this.lostFares,
    required this.missedStops,
    required this.impatient,
    required this.caughtLiars,
    required this.tipsPiasters,
    required this.overpaidPiasters,
  });

  static const Counters zero = Counters._(
    fights: 0,
    lostFares: 0,
    missedStops: 0,
    impatient: 0,
    caughtLiars: 0,
    tipsPiasters: 0,
    overpaidPiasters: 0,
  );

  /// Fights at stops and false accusations.
  final int fights;
  final int lostFares;
  final int missedStops;
  final int impatient;
  final int caughtLiars;
  final int tipsPiasters;
  final int overpaidPiasters;

  Map<String, Object> toJson() => {
    'fights': fights,
    'lost_fares': lostFares,
    'missed_stops': missedStops,
    'impatient': impatient,
    'caught_liars': caughtLiars,
    'tips_piasters': tipsPiasters,
    'overpaid_piasters': overpaidPiasters,
  };
}

extension CountersUpdate on Counters {
  Counters copyWith({
    int? fights,
    int? lostFares,
    int? missedStops,
    int? impatient,
    int? caughtLiars,
    int? tipsPiasters,
    int? overpaidPiasters,
  }) => Counters._(
    fights: fights ?? this.fights,
    lostFares: lostFares ?? this.lostFares,
    missedStops: missedStops ?? this.missedStops,
    impatient: impatient ?? this.impatient,
    caughtLiars: caughtLiars ?? this.caughtLiars,
    tipsPiasters: tipsPiasters ?? this.tipsPiasters,
    overpaidPiasters: overpaidPiasters ?? this.overpaidPiasters,
  );
}

enum MistakeKind {
  /// Gave more than was owed; the amount is the excess.
  over,

  /// Gave change to a passenger who hadn't paid or was owed nothing; the
  /// amount is the whole token.
  notOwed,

  /// A passenger got off still owed change; the amount is what they were
  /// owed.
  unreturned;

  String get wire => wireName(this);
}

final class Mistake {
  const Mistake({
    required this.passengerId,
    required this.kind,
    required this.amountPiasters,
  });

  final String passengerId;
  final MistakeKind kind;
  final int amountPiasters;

  Map<String, Object> toJson() => {
    'passenger_id': passengerId,
    'kind': kind.wire,
    'amount_piasters': amountPiasters,
  };
}

/// Why reputation changed. Losses are recorded in `reputation_lost`; gains
/// are not.
enum RepCause {
  fight(loss: true),
  falseAccusation(loss: true),
  missedStop(loss: true),
  shortChange(loss: true),
  impatient(loss: true),
  changeRequestDeclined(loss: true),
  exactChange(loss: false),
  liarCaught(loss: false),
  revive(loss: false);

  const RepCause({required this.loss});

  final bool loss;

  String get wire => wireName(this);
}

/// [lost] in wire form, in [RepCause] order.
Map<String, int> reputationLostJson(Map<RepCause, int> lost) => {
  for (final cause in RepCause.values) cause.wire: ?lost[cause],
};
