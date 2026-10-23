import 'dart:convert';
import 'dart:io';

import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/trip/domain/looks.dart';

// What a passenger looks like (specs/008.5-m21-design-refresh, data-model.md
// "Looks"): the design's twelve looks, the sample pack's skins, and the
// fallback that never gives a hidden archetype away.

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

/// The ARB file's keys.
Set<String> arbKeys() => (jsonDecode(
  File('lib/l10n/app_ar.arb').readAsStringSync(),
) as Map<String, Object?>).keys.where((k) => !k.startsWith('@')).toSet();

void main() {
  test('the twelve looks, each with its art, label and Rive look', () {
    expect(looks.keys, [
      'regular',
      'hagga',
      'sleeper',
      'effendi_200',
      'student',
      'headphones',
      'hurried',
      'claimer',
      'group_payer',
      'chatterbox',
      'regular_customer',
      'honest',
    ]);
    final keys = arbKeys();
    for (final look in looks.values) {
      expect(look.svg, 'assets/illustrations/passengers/${look.id}.svg');
      expect(File(look.svg).existsSync(), isTrue, reason: look.svg);
      expect(keys, contains(look.labelKey), reason: look.id);
    }
    // contracts/rive-characters.md "Looks".
    expect(
      {for (final l in looks.values) l.id: l.rive},
      {
        'regular': 0,
        'hagga': 1,
        'sleeper': 2,
        'hurried': 3,
        'effendi_200': 4,
        'student': 5,
        'headphones': 6,
        'claimer': 7,
        'group_payer': 8,
        'chatterbox': 9,
        'regular_customer': 16,
        'honest': 17,
      },
    );
  });

  test('only hagga, effendi_200, student and headphones have a label', () {
    expect(
      {
        for (final l in looks.values)
          if (l.labelKey != passengerLabelKey) l.id: l.labelKey,
      },
      {
        'hagga': 'tripLookHajja',
        'effendi_200': 'tripLookEffendi',
        'student': 'tripLookStudent',
        'headphones': 'tripLookHeadphones',
      },
    );
  });

  test('the alias table, exactly', () {
    expect(skinAliases, {
      'effendi_suit': 'effendi_200',
      'effendi_tie': 'effendi_200',
      'hajja_black': 'hagga',
      'student_cap': 'student',
      'worker_blue': 'regular',
      'young_cap': 'group_payer',
    });
    for (final target in skinAliases.values) {
      expect(looks, contains(target));
    }
  });

  test('every skin in the sample pack and content/source has a look', () {
    final skins = {
      ...skinsUnder('../../content/examples/sample'),
      ...skinsUnder('../../content/source'),
    };
    expect(skins, isNotEmpty);
    for (final skin in skins) {
      expect(
        looks.containsKey(skin) || skinAliases.containsKey(skin),
        isTrue,
        reason: skin,
      );
    }
  });

  test('a look id or an alias wins over the archetype', () {
    for (final archetype in Archetype.values) {
      expect(lookFor('hagga', archetype), looks['hagga']);
      expect(lookFor('effendi_suit', archetype), looks['effendi_200']);
      expect(lookFor('young_cap', archetype), looks['group_payer']);
    }
  });

  test('an unknown skin falls back by a seen archetype', () {
    for (final (archetype, id) in [
      (Archetype.hajja, 'hagga'),
      (Archetype.student, 'student'),
      (Archetype.headphones, 'headphones'),
      (Archetype.sleeper, 'sleeper'),
      (Archetype.hurry, 'hurried'),
      (Archetype.bigNote, 'effendi_200'),
    ]) {
      final look = lookFor('unknown_skin', archetype);
      expect(look.id, id, reason: archetype.name);
      expect(look.labelKey, passengerLabelKey, reason: archetype.name);
    }
  });

  test('every other archetype, hidden ones included, gets regular', () {
    const seen = {
      Archetype.hajja,
      Archetype.student,
      Archetype.headphones,
      Archetype.sleeper,
      Archetype.hurry,
      Archetype.bigNote,
    };
    for (final archetype in Archetype.values) {
      if (seen.contains(archetype)) continue;
      final look = lookFor('unknown_skin', archetype);
      expect(look.id, 'regular', reason: archetype.name);
      expect(look.labelKey, passengerLabelKey, reason: archetype.name);
    }
    for (final hidden in [
      Archetype.falseClaimer,
      Archetype.honest,
      Archetype.regularCustomer,
      Archetype.groupPayer,
      Archetype.moneyChanger,
      Archetype.dodger,
    ]) {
      expect(lookFor('unknown_skin', hidden), looks['regular']);
    }
  });
}
