// A parity fixture (replay-and-fixtures.md §5): one trip's inputs and the
// result they must replay to, in Dart and in the Python mirror.
import 'dart:convert';

import 'package:content_models/content_models.dart';

import 'commands.dart';
import 'json_read.dart';
import 'model/result.dart';
import 'params.dart';
import 'replay.dart';

const _what = 'a fixture';
const _result = 'expected_result';
const _inputKeys = {'command_log', 'definition', 'params', 'seed'};

final class ParityFixture {
  ParityFixture({
    required this.definition,
    required this.seed,
    required this.params,
    required List<LoggedCommand> commandLog,
    required this.expectedResult,
  }) : commandLog = List.unmodifiable(commandLog);

  ParityFixture._of(_Inputs inputs, TripResult expectedResult)
    : this(
        definition: inputs.definition,
        seed: inputs.seed,
        params: inputs.params,
        commandLog: inputs.commandLog,
        expectedResult: expectedResult,
      );

  /// The wire form, with exactly the five keys. Throws [FormatException].
  factory ParityFixture.fromJson(Object? json) {
    final object = asObject(json, _what);
    expectKeys(object, {..._inputKeys, _result}, _what);
    return ParityFixture._of(
      _readInputs(object),
      TripResult.fromJson(readObject(object, _result)),
    );
  }

  /// The fixture of [json]'s inputs with the result they replay to today,
  /// for `tool/fixtures.dart update`. Whatever `expected_result` holds is
  /// ignored, and it may be missing while a fixture is being written. Throws
  /// [FormatException] or [RebuildRefused].
  factory ParityFixture.recomputed(Object? json) {
    final object = asObject(json, _what);
    expectKeys({...object}..remove(_result), _inputKeys, _what);
    final inputs = _readInputs(object);
    return ParityFixture._of(
      inputs,
      replay(inputs.definition, inputs.params, inputs.seed, inputs.commandLog),
    );
  }

  final TripDefinition definition;
  final int seed;
  final TripParams params;
  final List<LoggedCommand> commandLog;
  final TripResult expectedResult;

  Map<String, Object?> toJson() => {
    'command_log': [for (final entry in commandLog) entry.toJson()],
    'definition': definition.toJson(),
    _result: expectedResult.toJson(),
    'params': params.toJson(),
    'seed': seed,
  };

  /// The file form: keys sorted at every level, a two-space indent and a
  /// final newline.
  String encode() =>
      '${const JsonEncoder.withIndent('  ').convert(_sorted(toJson()))}\n';

  /// How replaying the inputs differs from [expectedResult], one line per
  /// field, in key order. Empty when the fixture holds. Throws
  /// [RebuildRefused] if the log no longer replays.
  List<String> differences() {
    final actual = replay(definition, params, seed, commandLog).toJson();
    final expected = expectedResult.toJson();
    final keys = {...expected.keys, ...actual.keys}.toList()..sort();
    return [
      for (final key in keys)
        if (canonicalJson(expected[key]) != canonicalJson(actual[key]))
          '$key: expected ${canonicalJson(expected[key])}, '
              'got ${canonicalJson(actual[key])}',
    ];
  }
}

typedef _Inputs = ({
  TripDefinition definition,
  int seed,
  TripParams params,
  List<LoggedCommand> commandLog,
});

_Inputs _readInputs(Map<String, Object?> object) => (
  definition: readDefinition(object, 'definition'),
  seed: readInt(object, 'seed'),
  params: TripParams.fromJson(readObject(object, 'params')),
  commandLog: decodeCommandLog(object['command_log']),
);

Object? _sorted(Object? value) => switch (value) {
  Map<String, Object?>() => {
    for (final key in value.keys.toList()..sort()) key: _sorted(value[key]),
  },
  List<Object?>() => [for (final item in value) _sorted(item)],
  _ => value,
};
