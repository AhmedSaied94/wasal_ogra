// The app models read every valid example and write it back in canonical form
// (FR-009), and the canonical form matches the shared vectors.
import 'dart:convert';
import 'dart:io';

import 'package:content_models/content_models.dart';
import 'package:test/test.dart';

final _examples = Directory('../../content/examples');

Object? _read(File file) => jsonDecode(file.readAsStringSync());

Map<String, dynamic> _toJson(Object model) =>
    (model as dynamic).toJson() as Map<String, dynamic>;

void main() {
  final valid =
      Directory('${_examples.path}/valid')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('every part has a root parser and a valid example', () {
    final parts = {
      for (final file in valid)
        file.parent.uri.pathSegments.reversed.elementAt(1),
    };
    expect(parts, rootFromJson.keys.toSet());
    expect(schemaSetVersion, '1.0');
  });

  for (final file in valid) {
    final part = file.parent.uri.pathSegments.reversed.elementAt(1);
    final name = file.uri.pathSegments.last;
    test('$part/$name round-trips canonically', () {
      final input = _read(file)! as Map<String, dynamic>;
      final model = rootFromJson[part]!(input);
      final output = _toJson(model);
      expect(canonicalJson(output), canonicalJson(input));
      final again = rootFromJson[part]!(
        jsonDecode(jsonEncode(output)) as Map<String, dynamic>,
      );
      expect(again, model);
      expect(again.hashCode, model.hashCode);
    });
  }

  test('unknown fields are ignored (FR-008)', () {
    final file = File('${_examples.path}/valid/trip/line_gamaa.12.json');
    final input = _read(file)! as Map<String, dynamic>;
    final newer = jsonDecode(jsonEncode(input)) as Map<String, dynamic>;
    newer['future_field'] = 1;
    (newer['passengers'] as List<dynamic>).first['future_field'] = {
      'nested': [1, 2],
    };
    final model = TripDefinition.fromJson(newer);
    expect(canonicalJson(model.toJson()), canonicalJson(input));
    expect(model, TripDefinition.fromJson(input));
  });

  test('optional fields are left out, never written as null', () {
    final file = File('${_examples.path}/valid/trip/line_gamaa.12.json');
    final trip = TripDefinition.fromJson(_read(file)! as Map<String, dynamic>);
    expect(trip.passengers.first.boardStationId, isNull);
    final passenger =
        (trip.toJson()['passengers'] as List<dynamic>).first
            as Map<String, dynamic>;
    expect(passenger.containsKey('board_station_id'), isFalse);
  });

  test('a property that is not an identifier keeps its name', () {
    final text = LocalizedText.fromJson({'ar-EG': 'x'});
    expect(text.arEg, 'x');
    expect(text.toJson(), {'ar-EG': 'x'});
  });

  group('canonicalJson', () {
    final vectors =
        _read(File('${_examples.path}/canonical-vectors.json'))!
            as List<dynamic>;
    for (final vector in vectors.cast<Map<String, dynamic>>()) {
      test(vector['name'], () {
        expect(canonicalJson(vector['input']), vector['canonical']);
      });
    }

    test('refuses null, doubles, non-string keys and other values', () {
      expect(() => canonicalJson(null), throwsArgumentError);
      expect(() => canonicalJson({'a': 1.5}), throwsArgumentError);
      expect(
        () => canonicalJson([
          {'a': null},
        ]),
        throwsArgumentError,
      );
      expect(() => canonicalJson({1: 'a'}), throwsArgumentError);
      expect(() => canonicalJson({'a': DateTime(2026)}), throwsArgumentError);
    });

    test('refuses integers outside ±(2^53 - 1), as the loader does', () {
      const safe = 9007199254740991;
      expect(canonicalJson([safe, -safe]), '[$safe,-$safe]');
      expect(() => canonicalJson({'a': safe + 1}), throwsArgumentError);
      expect(() => canonicalJson({'a': -safe - 1}), throwsArgumentError);
    });

    test('refuses lone surrogates, and keeps surrogate pairs', () {
      expect(canonicalJson({'a': '\u{1F600}'}), '{"a":"\u{1F600}"}');
      expect(() => canonicalJson({'a': 'x\uD800'}), throwsArgumentError);
      expect(() => canonicalJson({'a': '\uDC00y'}), throwsArgumentError);
      expect(() => canonicalJson({'\uD83D': 1}), throwsArgumentError);
    });
  });
}
