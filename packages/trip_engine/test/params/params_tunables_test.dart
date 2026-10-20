// Every TripParams key resolves from the app's bundled tunables
// (contracts/tunables.md "Checks"), so the engine and the app share one
// source of defaults.
import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/default_params.dart';

void main() {
  final tunables = bundledTunables();

  test('trip_hop_ms resolves per line', () {
    const hop = {
      LineId.lineHay: 1300,
      LineId.lineGamaa: 1100,
      LineId.lineSouq: 900,
      LineId.lineMasyaf: 900,
      LineId.lineSafar: 900,
    };
    for (final MapEntry(key: line, value: ms) in hop.entries) {
      expect(TripParams.fromTunables(tunables, line).tripHopMs, ms);
    }
  });

  test('every other key is the tunable of the same name', () {
    final params = TripParams.fromTunables(tunables, LineId.lineHay).toJson();
    for (final MapEntry(:key, :value) in params.entries) {
      if (key == 'trip_hop_ms') continue;
      expect(tunables[key], value, reason: key);
    }
  });

  test('the bundled defaults are valid params for every line', () {
    for (final line in LineId.values) {
      final params = TripParams.fromTunables(tunables, line);
      expect(params.problems(), isEmpty, reason: '$line');
      expect(TripParams.fromJson(params.toJson()).toJson(), params.toJson());
    }
  });

  test('a missing or mistyped tunable is a FormatException naming it', () {
    final missing = Map.of(tunables)..remove('trip_patience_ms');
    expect(
      () => TripParams.fromTunables(missing, LineId.lineHay),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('trip_patience_ms'),
        ),
      ),
    );
    final mistyped = Map.of(tunables)..['trip_hop_ms_line_hay'] = 'fast';
    expect(
      () => TripParams.fromTunables(mistyped, LineId.lineHay),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('trip_hop_ms_line_hay'),
        ),
      ),
    );
  });

  test('presentation keys are not params', () {
    final keys = TripParams.fromTunables(
      tunables,
      LineId.lineHay,
    ).toJson().keys;
    expect(keys.where((key) => key.startsWith('trip_bubble_min_ms')), isEmpty);
    expect(keys.where((key) => key.startsWith('trip_hints_mode')), isEmpty);
    expect(keys.where((key) => key.startsWith('fuel_')), isEmpty);
  });
}
