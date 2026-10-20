// One step or one command, worked on a private copy of the state (research
// R2). The rules read and change the transition; `freeze` builds the next
// immutable TripState, sharing every collection that didn't change. The
// input state is never touched, and a rejected command's transition is
// simply dropped.
import 'dart:collection';

import 'package:content_models/content_models.dart';

import '../events.dart';
import '../model/choices.dart';
import '../model/counters.dart';
import '../model/passenger.dart';
import '../model/result.dart';
import '../model/state.dart';
import '../model/station.dart';
import '../model/token.dart';
import '../money.dart';
import '../params.dart';
import 'course.dart';

export '../clock.dart' show stepMs;

/// Authored times are in seconds, the clock in milliseconds.
const int msPerSecond = 1000;

final class Transition {
  Transition(this.course, this.params, TripState state, this._logHash)
    : tMs = state.tMs,
      status = state.status,
      reputation = state.reputation,
      tray = state.tray,
      hand = state.hand,
      nextTokenId = state.nextTokenId,
      nextStationIndex = state.nextStationIndex,
      fareIncreasePiasters = state.fareIncreasePiasters,
      trafficActive = state.trafficActive,
      breaksUsed = state.breaksUsed,
      ledgerPeekUntilMs = state.ledgerPeekUntilMs,
      lastSend = state.lastSend,
      counters = state.counters,
      revived = state.revived,
      revivable = state.revivable,
      commandsAccepted = state.commandsAccepted,
      prng = state.prng,
      result = state.result,
      _passengers = _CowList(state.passengers),
      _tokens = _CowList(state.tokens),
      _schedule = _CowList(state.schedule),
      _eventsFired = _CowList(state.eventsFired),
      _pendingBreaks = _CowList(state.pendingBreaks),
      _mistakes = _CowList(state.mistakes),
      _boostersUsed = _CowList(state.boostersUsed),
      _oldFarePayers = _CowSet(state.oldFarePayers),
      _claims = _CowMap(state.claims),
      _disputes = _CowMap(state.disputes),
      _changeRequests = _CowMap(state.changeRequests),
      _reputationLost = _CowMap(state.reputationLost);

  final Course course;
  final TripParams params;
  final String Function() _logHash;

  /// What happened, in order.
  final List<DomainEvent> events = [];

  int tMs;
  TripStatus status;
  int reputation;
  Pieces tray;
  Pieces hand;
  int nextTokenId;
  int nextStationIndex;
  int fareIncreasePiasters;
  bool trafficActive;
  int breaksUsed;
  int? ledgerPeekUntilMs;
  LastSend? lastSend;
  Counters counters;
  bool revived;
  bool revivable;
  int commandsAccepted;
  int prng;
  TripResult? result;

  final _CowList<PassengerState> _passengers;
  final _CowList<MoneyToken> _tokens;
  final _CowList<StationState> _schedule;
  final _CowList<bool> _eventsFired;
  final _CowList<PendingBreak> _pendingBreaks;
  final _CowList<Mistake> _mistakes;
  final _CowList<BoosterId> _boostersUsed;
  final _CowSet<String> _oldFarePayers;
  final _CowMap<String, Claim> _claims;
  final _CowMap<int, Dispute> _disputes;
  final _CowMap<String, ChangeRequest> _changeRequests;
  final _CowMap<RepCause, int> _reputationLost;

  // Seat → aboard passenger, rebuilt after anyone boards or leaves.
  Map<String, int>? _occupants;

  void emit(DomainEvent event) => events.add(event);

  /// The fingerprint of the command log, including the command being
  /// applied (rules.md §11).
  String logHash() => _logHash();

  // Passengers.

  List<PassengerState> get passengers => _passengers.read;

  PassengerState passenger(int index) => _passengers.read[index];

  void setPassenger(int index, PassengerState passenger) {
    if (_passengers.read[index].presence != passenger.presence) {
      _occupants = null;
    }
    _passengers.write[index] = passenger;
  }

  /// The passenger aboard in [seatId], or null.
  int? occupant(String seatId) {
    final occupants = _occupants ??= {
      for (final (i, passenger) in _passengers.read.indexed)
        if (passenger.presence == Presence.aboard) passenger.seatId: i,
    };
    return occupants[seatId];
  }

  // Tokens, in id order.

  List<MoneyToken> get tokens => _tokens.read;

  MoneyToken? token(int tokenId) {
    for (final token in _tokens.read) {
      if (token.tokenId == tokenId) return token;
    }
    return null;
  }

  /// Creates a token at [holder] with the next id.
  MoneyToken newToken({
    required TokenKind kind,
    required Pieces pieces,
    required String owner,
    required Holder target,
    required Holder holder,
  }) {
    final token = makeMoneyToken(
      tokenId: nextTokenId++,
      kind: kind,
      pieces: pieces,
      owner: owner,
      target: target,
      holder: holder,
    );
    _tokens.write.add(token);
    return token;
  }

  void setToken(MoneyToken token) {
    final list = _tokens.write;
    list[list.indexWhere((t) => t.tokenId == token.tokenId)] = token;
  }

  void removeToken(int tokenId) =>
      _tokens.write.removeWhere((t) => t.tokenId == tokenId);

  // The schedule.

  List<StationState> get schedule => _schedule.read;

  void setStation(int index, StationState station) =>
      _schedule.write[index] = station;

  // Authored events.

  List<bool> get eventsFired => _eventsFired.read;

  void markFired(int index) => _eventsFired.write[index] = true;

  Set<String> get oldFarePayers => _oldFarePayers.read;

  void addOldFarePayer(String passengerId) =>
      _oldFarePayers.write.add(passengerId);

  // Open choices.

  Map<String, Claim> get claims => _claims.read;

  void openClaim(String passengerId, Claim claim) =>
      _claims.write[passengerId] = claim;

  void closeClaim(String passengerId) => _claims.write.remove(passengerId);

  Map<int, Dispute> get disputes => _disputes.read;

  void openDispute(int index, Dispute dispute) =>
      _disputes.write[index] = dispute;

  void closeDispute(int index) => _disputes.write.remove(index);

  Map<String, ChangeRequest> get changeRequests => _changeRequests.read;

  void openChangeRequest(String passengerId, ChangeRequest request) =>
      _changeRequests.write[passengerId] = request;

  void closeChangeRequest(String passengerId) =>
      _changeRequests.write.remove(passengerId);

  List<PendingBreak> get pendingBreaks => _pendingBreaks.read;

  void addPendingBreak(PendingBreak pending) =>
      _pendingBreaks.write.add(pending);

  void removePendingBreak(int index) => _pendingBreaks.write.removeAt(index);

  // Records.

  List<Mistake> get mistakes => _mistakes.read;

  void addMistake(Mistake mistake) => _mistakes.write.add(mistake);

  Map<RepCause, int> get reputationLost => _reputationLost.read;

  void addReputationLost(RepCause cause, int amount) {
    final lost = _reputationLost.write;
    lost[cause] = (lost[cause] ?? 0) + amount;
  }

  List<BoosterId> get boostersUsed => _boostersUsed.read;

  void addBoosterUsed(BoosterId booster) => _boostersUsed.write.add(booster);

  /// The next immutable state.
  TripState freeze() => makeTripState(
    tMs: tMs,
    status: status,
    reputation: reputation,
    tray: tray,
    hand: hand,
    passengers: _passengers.freeze(),
    tokens: _tokens.freeze(),
    nextTokenId: nextTokenId,
    schedule: _schedule.freeze(),
    nextStationIndex: nextStationIndex,
    eventsFired: _eventsFired.freeze(),
    fareIncreasePiasters: fareIncreasePiasters,
    oldFarePayers: _oldFarePayers.freeze(),
    trafficActive: trafficActive,
    claims: _claims.freeze(),
    disputes: _disputes.freeze(),
    changeRequests: _changeRequests.freeze(),
    pendingBreaks: _pendingBreaks.freeze(),
    breaksUsed: breaksUsed,
    ledgerPeekUntilMs: ledgerPeekUntilMs,
    lastSend: lastSend,
    counters: counters,
    mistakes: _mistakes.freeze(),
    reputationLost: _reputationLost.freeze(),
    boostersUsed: _boostersUsed.freeze(),
    revived: revived,
    revivable: revivable,
    commandsAccepted: commandsAccepted,
    prng: prng,
    result: result,
    maxBreakRequests: course.rules.maxBreakRequests,
  );
}

/// The first state of a trip (rules.md §2.2–§2.5).
TripState initialState(Course course, int seed) {
  final definition = course.definition;
  return makeTripState(
    tMs: 0,
    status: TripStatus.running,
    reputation: maxReputation,
    tray: Pieces.fromJson(definition.initialTray),
    hand: Pieces.empty,
    passengers: List.unmodifiable([
      for (final (i, spec) in definition.passengers.indexed)
        makePassengerState(
          passengerId: spec.passengerId,
          presence: spec.boardStationId == null && !course.pickedUp.contains(i)
              ? Presence.aboard
              : Presence.waiting,
          seatId: spec.seatId,
          alertness: initialAlertness(spec.archetype),
        ),
    ]),
    tokens: const [],
    nextTokenId: 1,
    schedule: List.unmodifiable([
      for (final station in definition.stations)
        makeStationState(
          stationId: station.stationId,
          atMs: station.atSeconds * msPerSecond,
          farePiasters: station.farePiasters,
        ),
    ]),
    nextStationIndex: 0,
    eventsFired: List.unmodifiable(
      List.filled(definition.events.length, false),
    ),
    fareIncreasePiasters: 0,
    oldFarePayers: const {},
    trafficActive: false,
    claims: const {},
    disputes: const {},
    changeRequests: const {},
    pendingBreaks: const [],
    breaksUsed: 0,
    ledgerPeekUntilMs: null,
    lastSend: null,
    counters: Counters.zero,
    mistakes: const [],
    reputationLost: const {},
    boostersUsed: const [],
    revived: false,
    revivable: true,
    commandsAccepted: 0,
    prng: seed,
    result: null,
    maxBreakRequests: definition.rules.maxBreakRequests,
  );
}

/// The reputation scale (rules.md §1.4).
const int maxReputation = 100;

/// `asleep` for a sleeper, `muted` for headphones, `awake` otherwise (§2.4).
Alertness initialAlertness(Archetype archetype) => switch (archetype) {
  Archetype.sleeper => Alertness.asleep,
  Archetype.headphones => Alertness.muted,
  _ => Alertness.awake,
};

final class _CowList<T> {
  _CowList(this._list);

  List<T> _list;
  bool _owned = false;

  List<T> get read => _list;

  List<T> get write {
    if (!_owned) {
      _list = List.of(_list);
      _owned = true;
    }
    return _list;
  }

  List<T> freeze() => _owned ? UnmodifiableListView(_list) : _list;
}

final class _CowSet<T> {
  _CowSet(this._set);

  Set<T> _set;
  bool _owned = false;

  Set<T> get read => _set;

  Set<T> get write {
    if (!_owned) {
      _set = Set.of(_set);
      _owned = true;
    }
    return _set;
  }

  Set<T> freeze() => _owned ? UnmodifiableSetView(_set) : _set;
}

final class _CowMap<K, V> {
  _CowMap(this._map);

  Map<K, V> _map;
  bool _owned = false;

  Map<K, V> get read => _map;

  Map<K, V> get write {
    if (!_owned) {
      _map = Map.of(_map);
      _owned = true;
    }
    return _map;
  }

  Map<K, V> freeze() => _owned ? UnmodifiableMapView(_map) : _map;
}
