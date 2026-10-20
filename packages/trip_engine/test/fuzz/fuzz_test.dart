// Fuzzing the sample trips (research R16): random command logs from a seeded
// Xorshift32, chosen among the commands that could apply in each state.
// Nothing throws, money is conserved after every step and command, and every
// run replays to the same result.
import 'dart:convert';
import 'dart:io';

import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/src/prng.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/default_params.dart';

const _seed = 20261020;
const _runsPerTrip = 200;
const _samples = [
  'line_hay/line_hay.01.json',
  'line_hay/line_hay.02.json',
  'line_hay/line_hay.03.json',
  'line_gamaa/line_gamaa.01.json',
  'line_gamaa/line_gamaa.02.json',
];

// The change_bag booster's total (rules.md §14.2).
const _changeBagTotal = 50 * 2 + 100 * 3 + 500 * 2;

final class _Random {
  _Random(int seed) : _prng = Xorshift32(seed);

  Xorshift32 _prng;

  /// A value in 0 ..< [n].
  int below(int n) {
    final (value, next) = _prng.next();
    _prng = next;
    return value % n;
  }

  T pick<T>(List<T> items) => items[below(items.length)];
}

/// Tracks where the money should be: the initial tray plus everything that
/// came in from passengers or a change bag, minus everything handed out or
/// lost.
final class _Ledger {
  _Ledger(this.expected);

  int expected;

  void record(TripState before, List<DomainEvent> events) {
    for (final event in events) {
      switch (event) {
        case FareSent(:final amountPiasters):
          expected += amountPiasters;
        case PassengerSpeaks(
          slot: SpeechSlot.returnsExcess,
          :final amountPiasters?,
        ):
          expected += amountPiasters;
        case BoosterUsed(boosterId: BoosterId.changeBag):
          expected += _changeBagTotal;
        case ChangeDelivered(:final amountPiasters):
          expected -= amountPiasters;
        case DroppedLost(:final tokenId):
          expected -= before.token(tokenId)?.pieces.total ?? 0;
        default:
          break;
      }
    }
  }

  /// The money the state holds: tray, hand, tokens and notes out for a
  /// break.
  static int held(TripState state) =>
      state.tray.total +
      state.hand.total +
      state.tokens.fold<int>(0, (sum, token) => sum + token.pieces.total) +
      state.pendingBreaks.fold<int>(
        0,
        (sum, pending) => sum + pending.denomination,
      );
}

const _inTripBoosters = [
  BoosterId.changeBag,
  BoosterId.wakeAll,
  BoosterId.ledgerPeek,
  BoosterId.trafficJam,
];

/// The commands that could apply now. Some are still rejected, which is
/// part of what is tested.
List<Command> _candidates(TripState state, _Random random) {
  final aboard = [
    for (final passenger in state.passengers)
      if (passenger.presence == Presence.aboard) passenger.passengerId,
  ];
  if (state.status == TripStatus.failed) {
    return [if (state.revivable) const Revive(), const Abandon()];
  }
  return [
    for (final denomination in state.tray.counts.keys)
      PickFromTray(denomination),
    if (!state.hand.isEmpty) const ReturnHand(),
    if (!state.hand.isEmpty)
      for (final id in aboard) SendHand(id),
    if (state.undoAvailableUntilMs != null) const UndoLastSend(),
    for (final id in aboard) Tap(id),
    for (final id in state.claims.keys)
      ResolveClaim(id, insist: random.below(2) == 0),
    for (final MapEntry(:key, :value) in state.disputes.entries)
      ResolveDispute(key, random.below(2) == 0 ? value.a : value.b),
    for (final id in state.changeRequests.keys)
      ResolveChangeRequest(id, agree: random.below(3) != 0),
    if (state.breaksLeft > 0)
      for (final denomination in state.tray.counts.keys)
        if (denomination >= 1000) RequestBreak(denomination),
    for (final token in state.tokens)
      if (token.isDropped) CollectDropped(token.tokenId),
    UseBooster(random.pick(_inTripBoosters)),
  ];
}

void _expectIntegers(Object? json, String where) {
  switch (json) {
    case double():
      fail('a double in $where: $json');
    case Map<String, Object?>():
      for (final MapEntry(:key, :value) in json.entries) {
        _expectIntegers(value, '$where.$key');
      }
    case List<Object?>():
      for (final (i, item) in json.indexed) {
        _expectIntegers(item, '$where[$i]');
      }
  }
}

/// One random run of [definition], checked as it goes.
TripEngine _run(TripDefinition definition, TripParams params, _Random random) {
  final engine = TripEngine.start(definition, params);
  final ledger = _Ledger(_Ledger.held(engine.state));
  void check(TripState before, List<DomainEvent> events, String what) {
    ledger.record(before, events);
    expect(
      _Ledger.held(engine.state),
      ledger.expected,
      reason: 'money after $what at ${engine.state.tMs}',
    );
  }

  while (engine.status == TripStatus.running ||
      engine.status == TripStatus.failed && engine.state.revivable) {
    if (engine.status == TripStatus.running && random.below(3) != 0) {
      for (var steps = random.below(45); steps >= 0; steps--) {
        final before = engine.state;
        check(before, engine.step(), 'a step');
        if (engine.status != TripStatus.running) break;
      }
      continue;
    }
    final command = random.pick(_candidates(engine.state, random));
    if (command is Abandon && random.below(20) != 0) continue;
    final before = engine.state;
    final outcome = engine.apply(command);
    if (outcome case Accepted(:final events)) {
      check(before, events, command.name);
    } else {
      expect(engine.state, same(before), reason: 'a rejected $command');
    }
  }
  return engine;
}

TripDefinition _sample(String path) => TripDefinition.fromJson(
  jsonDecode(
    File('../../content/examples/sample/trips/$path').readAsStringSync(),
  ) as Map<String, dynamic>,
);

void main() {
  final random = _Random(_seed);
  for (final path in _samples) {
    test('200 random runs of $path', () {
      final definition = _sample(path);
      final params = defaultParams(definition.lineId);
      for (var run = 0; run < _runsPerTrip; run++) {
        final engine = _run(definition, params, random);
        final result = engine.result;
        if (result == null) fail('run $run ended without a result');
        _expectIntegers(engine.state.toJson(), 'state');
        _expectIntegers(result.toJson(), 'result');
        expect(
          replay(definition, params, engine.seed, engine.commandLog).toJson(),
          result.toJson(),
          reason: 'run $run replays',
        );
      }
    });
  }
}
