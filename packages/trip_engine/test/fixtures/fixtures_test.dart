// Every parity fixture replays to its expected_result, field by field
// (constitution III, replay-and-fixtures.md §5). B05's pytest does the same.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/fixture_io.dart';

void main() {
  final files = fixtureFiles();

  test('there are fixtures', () => expect(files, isNotEmpty));

  for (final file in files) {
    final name = fixtureName(file);
    test('$name replays to its expected_result', () {
      final fixture = loadFixture(file);
      final differences = fixture.differences();
      expect(differences, isEmpty, reason: '$name: ${differences.join('; ')}');
    });

    test('$name is in the canonical layout', () {
      expect(loadFixture(file).encode(), file.readAsStringSync());
    });
  }

  group('the fixture codec', () {
    Map<String, Object?> wire() =>
        jsonDecode(files.first.readAsStringSync()) as Map<String, Object?>;

    test('refuses a key other than the five, and a missing one', () {
      expect(
        () => ParityFixture.fromJson({...wire(), 'notes': 'six keys'}),
        throwsFormatException,
      );
      expect(
        () => ParityFixture.fromJson(wire()..remove('expected_result')),
        throwsFormatException,
      );
      expect(() => ParityFixture.fromJson('[]'), throwsFormatException);
    });

    test('an edited expected number is a difference naming the field', () {
      final json = wire();
      final expected = json['expected_result']! as Map<String, Object?>;
      final earnings = expected['earnings_jenehat']! as int;
      final edited = ParityFixture.fromJson({
        ...json,
        'expected_result': {...expected, 'earnings_jenehat': earnings + 1},
      });
      expect(edited.differences(), [
        'earnings_jenehat: expected ${earnings + 1}, got $earnings',
      ]);
    });

    test('recomputing ignores whatever expected_result holds', () {
      final json = wire();
      final fixture = ParityFixture.fromJson(json);
      for (final placeholder in [<String, Object?>{}, null]) {
        final authored = {...json, 'expected_result': placeholder};
        expect(ParityFixture.recomputed(authored).encode(), fixture.encode());
      }
      expect(
        ParityFixture.recomputed(json..remove('expected_result')).encode(),
        fixture.encode(),
      );
    });

    test('recomputing refuses a key other than the five', () {
      expect(
        () => ParityFixture.recomputed({...wire(), 'notes': 'x'}),
        throwsFormatException,
      );
    });
  });
}
