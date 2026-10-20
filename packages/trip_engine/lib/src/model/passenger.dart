// One passenger's state (data-model.md "PassengerState").
import '../wire.dart';
import 'keep.dart';

enum Presence {
  /// Not boarded yet.
  waiting,
  aboard,
  gone;

  String get wire => name;
}

/// See the alertness state machine in data-model.md.
enum Alertness {
  asleep,
  waking,
  awake,
  muted,
  attentive;

  String get wire => name;
}

enum AlightOutcome {
  thanked,
  fight,
  leftUnpaid,
  missedStop;

  String get wire => wireName(this);
}

final class PassengerState {
  const PassengerState._({
    required this.passengerId,
    required this.presence,
    required this.seatId,
    required this.alertness,
    required this.alertUntilMs,
    required this.taps,
    required this.fareSent,
    required this.farePiasters,
    required this.balance,
    required this.paidIn,
    required this.patienceMs,
    required this.patienceStartMs,
    required this.halfPatienceSpoken,
    required this.impatient,
    required this.claimResolved,
    required this.neverPays,
    required this.deadlineMs,
    required this.pickupDue,
    required this.outcome,
  });

  final String passengerId;
  final Presence presence;

  /// Their seat. They sit in it only while aboard.
  final String seatId;
  final Alertness alertness;

  /// When `waking` ends, `awake` ends (sleeper), or `attentive` ends.
  final int? alertUntilMs;

  /// Taps while muted. Reset when attentive.
  final int taps;

  /// Their fare (or claim-free payment) has been handed over.
  final bool fareSent;

  /// Fixed when the fare is sent, including the group sum for a payer.
  final int? farePiasters;

  /// Payment minus fare: above 0 change is owed, below 0 the passenger owes.
  final int balance;

  /// Fare money from this passenger that reached the driver.
  final int paidIn;

  /// Remaining patience. Null until first owed.
  final int? patienceMs;

  /// The patience they started with, for [patiencePermille].
  final int? patienceStartMs;
  final bool halfPatienceSpoken;

  /// Patience ran out (charged once).
  final bool impatient;

  /// One resolved claim per passenger (research R7).
  final bool claimResolved;

  /// A believed false claimer.
  final bool neverPays;

  /// Set by `drop_me_here`.
  final int? deadlineMs;

  /// Waiting, with their boarding station or pickup come: they board as soon
  /// as their seat is free.
  final bool pickupDue;

  /// Set once gone.
  final AlightOutcome? outcome;

  /// Aboard, and awake or attentive.
  bool get isAble =>
      presence == Presence.aboard &&
      (alertness == Alertness.awake || alertness == Alertness.attentive);

  /// The fare is sent and change is owed.
  bool get isOwed => fareSent && balance > 0;

  /// Remaining patience × 1000 ~/ starting patience, or null. Drives the
  /// Rive `mood` input.
  int? get patiencePermille => switch ((patienceMs, patienceStartMs)) {
    (final left?, final start?) when start > 0 => left * 1000 ~/ start,
    _ => null,
  };

  Map<String, Object> toJson() => {
    'passenger_id': passengerId,
    'presence': presence.wire,
    'seat_id': seatId,
    'alertness': alertness.wire,
    'alert_until_ms': ?alertUntilMs,
    'taps': taps,
    'fare_sent': fareSent,
    'fare_piasters': ?farePiasters,
    'balance': balance,
    'paid_in': paidIn,
    'patience_ms': ?patienceMs,
    'patience_start_ms': ?patienceStartMs,
    'half_patience_spoken': halfPatienceSpoken,
    'impatient': impatient,
    'claim_resolved': claimResolved,
    'never_pays': neverPays,
    'deadline_ms': ?deadlineMs,
    'pickup_due': pickupDue,
    if (outcome case final outcome?) 'outcome': outcome.wire,
  };
}

/// A passenger as the trip starts (rules.md §2.3, §2.4).
PassengerState makePassengerState({
  required String passengerId,
  required Presence presence,
  required String seatId,
  required Alertness alertness,
}) => PassengerState._(
  passengerId: passengerId,
  presence: presence,
  seatId: seatId,
  alertness: alertness,
  alertUntilMs: null,
  taps: 0,
  fareSent: false,
  farePiasters: null,
  balance: 0,
  paidIn: 0,
  patienceMs: null,
  patienceStartMs: null,
  halfPatienceSpoken: false,
  impatient: false,
  claimResolved: false,
  neverPays: false,
  deadlineMs: null,
  pickupDue: false,
  outcome: null,
);

extension PassengerStateUpdate on PassengerState {
  PassengerState copyWith({
    Presence? presence,
    Alertness? alertness,
    Object? alertUntilMs = keep,
    int? taps,
    bool? fareSent,
    Object? farePiasters = keep,
    int? balance,
    int? paidIn,
    Object? patienceMs = keep,
    Object? patienceStartMs = keep,
    bool? halfPatienceSpoken,
    bool? impatient,
    bool? claimResolved,
    bool? neverPays,
    Object? deadlineMs = keep,
    bool? pickupDue,
    Object? outcome = keep,
  }) => PassengerState._(
    passengerId: passengerId,
    presence: presence ?? this.presence,
    seatId: seatId,
    alertness: alertness ?? this.alertness,
    alertUntilMs: kept(alertUntilMs, this.alertUntilMs),
    taps: taps ?? this.taps,
    fareSent: fareSent ?? this.fareSent,
    farePiasters: kept(farePiasters, this.farePiasters),
    balance: balance ?? this.balance,
    paidIn: paidIn ?? this.paidIn,
    patienceMs: kept(patienceMs, this.patienceMs),
    patienceStartMs: kept(patienceStartMs, this.patienceStartMs),
    halfPatienceSpoken: halfPatienceSpoken ?? this.halfPatienceSpoken,
    impatient: impatient ?? this.impatient,
    claimResolved: claimResolved ?? this.claimResolved,
    neverPays: neverPays ?? this.neverPays,
    deadlineMs: kept(deadlineMs, this.deadlineMs),
    pickupDue: pickupDue ?? this.pickupDue,
    outcome: kept(outcome, this.outcome),
  );
}
