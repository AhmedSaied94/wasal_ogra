import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/config/bundled_config_source.dart';
import 'package:wassal/core/config/tunable.dart';
import 'package:wassal/core/config/tunable_snapshot.dart';
import 'package:wassal/core/glossary/ids.dart' as glossary;
import 'package:wassal/features/trip/domain/line_ids.dart';

BundledConfigSource _bundled() => BundledConfigSource(
  (jsonDecode(
    File('assets/config/tunables.json').readAsStringSync(),
  ) as Map<String, Object?>).cast(),
);

void main() {
  test('holds every tunable, enums as their wire strings', () {
    final config = _bundled();
    final snapshot = tunableSnapshot(config);
    expect(snapshot.keys, unorderedEquals(Tunable.all.map((t) => t.key)));
    final hints = Tunable.tripHintsMode(glossary.LineId.lineHay);
    expect(snapshot[hints.key], config.read(hints).wire);
    expect(snapshot.values.every((v) => v is int || v is String), isTrue);
  });

  test('TripParams reads it for every line', () {
    final config = _bundled();
    final snapshot = tunableSnapshot(config);
    for (final line in glossary.LineId.values) {
      final params = TripParams.fromTunables(snapshot, toContentLine(line));
      expect(params.tripHopMs, config.read(Tunable.tripHopMs(line)));
    }
  });
}
