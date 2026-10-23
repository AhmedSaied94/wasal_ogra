// The engine's only stateful object: a thin shell over the pure rules
// (research R2). It holds the current state and the accepted-command log.
import 'dart:collection';

import 'package:content_models/content_models.dart';

import 'commands.dart';
import 'events.dart';
import 'model/result.dart';
import 'model/state.dart';
import 'params.dart';
import 'replay.dart';
import 'rules/command_handlers.dart';
import 'rules/course.dart';
import 'rules/settled.dart' as rules;
import 'rules/step.dart';
import 'rules/transition.dart';
import 'validation.dart';

final class TripEngine {
  TripEngine._(this._course, this._params, this.seed, this._state);

  /// Starts a trip. Throws [TripRefused] listing every problem (rules.md
  /// §2). [seed] defaults to the definition's.
  factory TripEngine.start(
    TripDefinition definition,
    TripParams params, {
    int? seed,
  }) {
    final start = seed ?? definition.seed;
    final refusals = validate(definition, params, start);
    if (refusals.isNotEmpty) throw TripRefused(refusals);
    final course = Course(definition);
    return TripEngine._(course, params, start, initialState(course, start));
  }

  /// Rebuilds a trip from its replay record (research R10): each command at
  /// its time, then steps to the record's clock, stopping early if the trip
  /// ends. The events on the way are discarded, and a running trip comes
  /// back paused. Throws [RebuildRefused].
  factory TripEngine.rebuild(ReplayRecord record) {
    final log = record.commandLog;
    if (record.tMs < 0 || record.tMs % stepMs != 0) {
      throw RebuildRefused('t_ms ${record.tMs} is not a step of the clock');
    }
    if (log.isNotEmpty && record.tMs < log.last.tMs) {
      throw RebuildRefused(
        't_ms ${record.tMs} is before the last command, at ${log.last.tMs}',
      );
    }
    final engine = startReplay(record.definition, record.params, record.seed);
    playLog(engine, log);
    engine
      ..stepTo(record.tMs)
      ..pause();
    return engine;
  }

  final Course _course;
  final TripParams _params;

  /// The PRNG seed the trip started from.
  final int seed;
  TripState _state;
  final List<LoggedCommand> _log = [];

  TripDefinition get definition => _course.definition;

  TripParams get params => _params;

  /// Immutable; read freely.
  TripState get state => _state;

  TripStatus get status => _state.status;

  /// Set when the trip finishes, fails or is abandoned.
  TripResult? get result => _state.result;

  /// Nothing is left for the player (rules.md §16): with no command, the
  /// rest of the trip only reaches its stations.
  bool get isSettled => rules.isSettled(_course, _state);

  /// The accepted commands, unmodifiable.
  List<LoggedCommand> get commandLog => UnmodifiableListView(_log);

  /// What M02 saves to resume this trip exactly: the replay tuple and the
  /// clock.
  ReplayRecord get replayRecord => ReplayRecord(
    definition: definition,
    seed: seed,
    params: _params,
    commandLog: _log,
    tMs: _state.tMs,
  );

  /// Advances one 33 ms logic step. Returns [] when the trip isn't running.
  List<DomainEvent> step() {
    final (next, events) = stepTrip(
      _course,
      _params,
      _state,
      () => commandLogHash(_log),
    );
    _state = next;
    return List.unmodifiable(events);
  }

  /// Steps until the clock reaches [tMs] or the trip stops running.
  List<DomainEvent> stepTo(int tMs) {
    final events = <DomainEvent>[];
    while (_state.status == TripStatus.running && _state.tMs < tMs) {
      events.addAll(step());
    }
    return List.unmodifiable(events);
  }

  /// Applies [command] at the current clock (rules.md §4).
  CommandOutcome apply(Command command) {
    final entry = LoggedCommand(_state.tMs, command);
    final applied = applyCommand(
      _course,
      _params,
      _state,
      command,
      () => commandLogHash([..._log, entry]),
    );
    if (applied.rejection case final rejection?) return Rejected(rejection);
    _state = applied.state;
    _log.add(entry);
    return Accepted(List.unmodifiable(applied.events));
  }

  /// running → paused. A no-op otherwise, and never logged.
  void pause() => _setStatus(TripStatus.running, TripStatus.paused);

  /// paused → running. A no-op otherwise, and never logged.
  void resume() => _setStatus(TripStatus.paused, TripStatus.running);

  void _setStatus(TripStatus from, TripStatus to) {
    if (_state.status != from) return;
    _state = (Transition(
      _course,
      _params,
      _state,
      () => commandLogHash(_log),
    )..status = to).freeze();
  }
}

/// Test hooks. Not exported: tests import this file directly.
extension TripEngineDebug on TripEngine {
  /// Edits the state through a transition, outside the rules, so a test can
  /// set up a situation (a passenger asleep, traffic active, reputation 0).
  void debugEdit(void Function(Transition tx) edit) {
    final tx = Transition(_course, _params, _state, () => commandLogHash(_log));
    edit(tx);
    _state = tx.freeze();
  }
}
