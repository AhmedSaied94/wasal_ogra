import 'dart:convert';
import 'dart:io';

import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/trip/domain/skin_looks.dart';

/// Every `skin` in the trips under [root], if it exists.
Set<String> skinsUnder(String root) {
  final dir = Directory(root);
  if (!dir.existsSync()) return {};
  return {
    for (final file in dir.listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.json') && file.path.contains('/trips/'))
        for (final passenger
            in ((jsonDecode(file.readAsStringSync())
                        as Map<String, Object?>)['passengers']
                    as List<Object?>? ??
                const []))
          (passenger! as Map<String, Object?>)['skin']! as String,
  };
}

void main() {
  test('every skin in the sample pack and content/source has a look', () {
    final skins = {
      ...skinsUnder('../../content/examples/sample'),
      ...skinsUnder('../../content/source'),
    };
    expect(skins, isNotEmpty);
    for (final skin in skins) {
      expect(skinLooks, contains(skin), reason: skin);
    }
  });

  test('an unknown skin falls back by archetype with the neutral label', () {
    for (final archetype in Archetype.values) {
      final look = lookFor('unknown_skin', archetype);
      expect(look.skin, 'unknown_skin');
      expect(look.labelKey, passengerLabelKey);
    }
    expect(lookFor('x', Archetype.hajja).accessory, Accessory.glasses);
    expect(lookFor('x', Archetype.headphones).accessory, Accessory.headphones);
    expect(lookFor('x', Archetype.falseClaimer).shirt, Shirt.plain);
    expect(lookFor('x', Archetype.falseClaimer).accessory, Accessory.none);
  });

  test('a known skin keeps its look whatever the archetype', () {
    for (final archetype in Archetype.values) {
      expect(lookFor('effendi_suit', archetype), skinLooks['effendi_suit']);
    }
  });

  test('no label is named after an archetype', () {
    final archetypeWords = {
      for (final a in Archetype.values) a.name.toLowerCase(),
    }..removeAll({'hajja', 'student'});
    for (final look in skinLooks.values) {
      final label = look.labelKey.replaceFirst('tripLook', '').toLowerCase();
      expect(archetypeWords, isNot(contains(label)), reason: look.labelKey);
    }
  });

  test('accessories are exactly the Rive file values', () {
    expect(Accessory.values.map((a) => a.name), [
      'none',
      'cap',
      'glasses',
      'headphones',
      'tie',
      'scarf',
      'headscarf',
    ]);
  });

  test('look-alike shirt pairs come from shared accessories', () {
    final pairs = shirtPairsToSeparate();
    expect(pairs, contains((Shirt.effendi, Shirt.worker)));
    expect(pairs, contains((Shirt.student, Shirt.young)));
  });
}
