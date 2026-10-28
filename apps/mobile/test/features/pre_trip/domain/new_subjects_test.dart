// The new card's closed tables (specs/013-m08-home-result, research R5):
// every archetype the engine supports but `regular`, and the eight in-trip
// events, each with its name and sentence in the ARB; the rule lines'
// archetype tables, empty while the engine has none; and an icon for each
// event.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/pre_trip/domain/new_subjects.dart';

Map<String, Object?> _json(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

/// `big_note` → `BigNote`.
String _pascal(String wire) =>
    wire.split('_').map((w) => '${w[0].toUpperCase()}${w.substring(1)}').join();

void main() {
  final capabilities = _json('../../content/engine/capabilities.json');
  final archetypes = (capabilities['archetypes']! as List<Object?>)
      .cast<String>();
  final events = (capabilities['events']! as Map<String, Object?>).keys;

  test('the subjects: the engine archetypes but regular, and its events', () {
    expect(newCardArchetypes.values.toSet(), {
      ...archetypes.where((a) => a != 'regular'),
    });
    expect(newCardEvents.values.toSet(), events.toSet());
    expect(newCardEvents, hasLength(8));
    expect(newCardSubjects, {...newCardArchetypes.values, ...events});
  });

  test('every subject has its name and sentence in the ARB', () {
    final arb = _json('lib/l10n/app_ar.arb');
    for (final id in newCardSubjects) {
      for (final key in [newCardNameKey(id), newCardTextKey(id)]) {
        expect(arb[key], isA<String>(), reason: key);
      }
      expect(newCardNameKey(id), 'newCard${_pascal(id)}');
      expect(newCardTextKey(id), 'newCard${_pascal(id)}Text');
    }
  });

  test("the rule lines' archetypes are ones the engine lists (none today)", () {
    final listed = newCardArchetypes.keys.toSet();
    expect(bagArchetypes.difference(listed), isEmpty);
    expect(childArchetypes.difference(listed), isEmpty);
    expect(bagArchetypes, isEmpty);
    expect(childArchetypes, isEmpty);
  });

  test('every event has an icon that exists', () {
    expect(eventIcons.keys.toSet(), newCardEvents.keys.toSet());
    for (final icon in eventIcons.values) {
      expect(File('assets/icons/$icon.svg').existsSync(), isTrue, reason: icon);
    }
  });
}
