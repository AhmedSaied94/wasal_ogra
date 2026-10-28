// The passenger types and events a player has met (specs/013-m08-home-result,
// research R5): those of every trip in the active pack with at least one
// star.
import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/pre_trip/domain/met_set.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/progress.dart';

void main() {
  final c = sampleContent();

  test('a new player has met nothing', () {
    final met = metSet(c, player());
    expect(met.archetypes, isEmpty);
    expect(met.events, isEmpty);
  });

  test("a finished trip's passengers and events", () {
    final met = metSet(c, player({'line_hay.02': 1}));
    expect(met.archetypes, {
      Archetype.groupPayer,
      Archetype.regular,
      Archetype.hajja,
    });
    expect(met.events, {EventId.traffic, EventId.paymentDispute});
  });

  test('a trip at no star, a failed one, is not met', () {
    final met = metSet(c, player({'line_gamaa.01': 0, 'line_hay.01': 2}));
    expect(met.archetypes, {Archetype.regular, Archetype.student});
    expect(met.events, isEmpty);
  });

  test('a trip the pack lacks is skipped', () {
    final met = metSet(c, player({'line_old.09': 3, 'line_hay.01': 1}));
    expect(met.archetypes, {Archetype.regular, Archetype.student});
  });

  test('it follows the progress it is given, as after a restore', () {
    expect(metSet(c, player()).archetypes, isEmpty);
    final restored = player({'line_gamaa.01': 3, 'line_gamaa.02': 3});
    expect(metSet(c, restored).archetypes, {
      Archetype.bigNote,
      Archetype.sleeper,
      Archetype.student,
      Archetype.honest,
      Archetype.hurry,
      Archetype.groupPayer,
    });
    expect(metSet(c, restored).events, {EventId.bump});
  });
}
