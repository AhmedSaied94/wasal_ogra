// Replaying a command log and fingerprinting it (replay-and-fixtures.md §2 to
// §4, research R9 and R10).
import 'dart:convert';

import 'package:content_models/content_models.dart';
import 'package:crypto/crypto.dart';

import 'commands.dart';
import 'engine.dart';
import 'events.dart';
import 'json_read.dart';
import 'model/result.dart';
import 'model/state.dart';
import 'params.dart';
import 'validation.dart';

/// `lowercase_hex(sha256(utf8(canonical_json(log))))`.
String commandLogHash(List<LoggedCommand> log) => sha256
    .convert(
      utf8.encode(canonicalJson([for (final entry in log) entry.toJson()])),
    )
    .toString();

/// A replay or rebuild the engine can't follow: the trip is refused, the log
/// goes back in time, an entry comes after the trip stopped, or an entry is
/// rejected.
final class RebuildRefused implements Exception {
  const RebuildRefused(this.reason, {this.index, this.refusals = const []});

  final String reason;

  /// The log entry refused, or null when the trip or the record is.
  final int? index;

  /// The trip's problems, when it is refused at the start.
  final List<Refusal> refusals;

  @override
  String toString() =>
      'RebuildRefused: $reason${index == null ? '' : ' (log entry $index)'}';
}

/// Replays [log] to its end (engine-api.md "Entry points"): each command at
/// its time, then steps until the trip finishes, fails or is abandoned.
/// Throws [RebuildRefused].
TripResult replay(
  TripDefinition definition,
  TripParams params,
  int seed,
  List<LoggedCommand> log,
) {
  final engine = replayEngine(definition, params, seed, log);
  return engine.result ??
      (throw StateError('a replayed trip always ends with a result'));
}

/// [replay], returning the engine at the end. [onEvents] receives every
/// event in order, for the fixture tool and tests.
TripEngine replayEngine(
  TripDefinition definition,
  TripParams params,
  int seed,
  List<LoggedCommand> log, {
  void Function(List<DomainEvent> events)? onEvents,
}) {
  final engine = startReplay(definition, params, seed);
  playLog(engine, log, onEvents: onEvents);
  while (engine.status == TripStatus.running) {
    final events = engine.step();
    onEvents?.call(events);
  }
  return engine;
}

/// Starts a trip to replay, refusing it as a [RebuildRefused].
TripEngine startReplay(TripDefinition definition, TripParams params, int seed) {
  try {
    return TripEngine.start(definition, params, seed: seed);
  } on TripRefused catch (refused) {
    throw RebuildRefused('the trip is refused', refusals: refused.refusals);
  }
}

/// Steps [engine] to each entry of [log] and applies it. Every entry must be
/// accepted at exactly its `t_ms`.
void playLog(
  TripEngine engine,
  List<LoggedCommand> log, {
  void Function(List<DomainEvent> events)? onEvents,
}) {
  for (var i = 0; i < log.length; i++) {
    final entry = log[i];
    if (i > 0 && entry.tMs < log[i - 1].tMs) {
      throw RebuildRefused('t_ms goes down along the log', index: i);
    }
    final events = engine.stepTo(entry.tMs);
    onEvents?.call(events);
    if (engine.state.tMs != entry.tMs) {
      throw RebuildRefused(
        'the clock stopped at ${engine.state.tMs}, before ${entry.tMs}',
        index: i,
      );
    }
    switch (engine.apply(entry.command)) {
      case Rejected(:final rejection):
        throw RebuildRefused(
          '${entry.command.name} was rejected: ${rejection.code.wire}',
          index: i,
        );
      case Accepted(:final events):
        onEvents?.call(events);
    }
  }
}

/// The record M02 saves to resume a trip exactly (research R10): a replay
/// tuple and the clock it reached.
final class ReplayRecord {
  ReplayRecord({
    required this.definition,
    required this.seed,
    required this.params,
    required List<LoggedCommand> commandLog,
    required this.tMs,
  }) : commandLog = List.unmodifiable(commandLog);

  /// The wire form. Throws [FormatException] for anything malformed.
  factory ReplayRecord.fromJson(Object? json) {
    const what = 'a replay record';
    final object = asObject(json, what);
    expectKeys(object, const {
      'command_log',
      'definition',
      'params',
      'seed',
      't_ms',
    }, what);
    return ReplayRecord(
      definition: readDefinition(object, 'definition'),
      seed: readInt(object, 'seed'),
      params: TripParams.fromJson(readObject(object, 'params')),
      commandLog: decodeCommandLog(object['command_log']),
      tMs: readInt(object, 't_ms'),
    );
  }

  final TripDefinition definition;
  final int seed;
  final TripParams params;
  final List<LoggedCommand> commandLog;
  final int tMs;

  Map<String, Object?> toJson() => {
    'definition': definition.toJson(),
    'seed': seed,
    'params': params.toJson(),
    'command_log': [for (final entry in commandLog) entry.toJson()],
    't_ms': tMs,
  };
}
