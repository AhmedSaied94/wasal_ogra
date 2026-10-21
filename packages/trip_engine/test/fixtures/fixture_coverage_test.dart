// The fixtures cover the whole engine (SC-002): every supported archetype,
// event, command and booster, every ending, and each sample trip at 3 stars.
import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/fixture_io.dart';

void main() {
  final fixtures = {
    for (final file in fixtureFiles()) fixtureName(file): loadFixture(file),
  };
  final definitions = [for (final f in fixtures.values) f.definition];
  final results = [for (final f in fixtures.values) f.expectedResult];

  test('every supported archetype appears', () {
    final seen = {
      for (final d in definitions)
        for (final p in d.passengers) p.archetype,
    };
    expect(
      seen.containsAll(EngineCapabilities.archetypes),
      isTrue,
      reason: 'missing ${EngineCapabilities.archetypes.difference(seen)}',
    );
  });

  test('every event appears', () {
    final seen = {
      for (final d in definitions)
        for (final e in d.events) e.eventId,
    };
    expect(seen, EngineCapabilities.events);
  });

  test('all 13 commands appear in some log', () {
    final seen = {
      for (final f in fixtures.values)
        for (final entry in f.commandLog) entry.command.name,
    };
    expect(seen, {
      'PickFromTray',
      'ReturnHand',
      'SendHand',
      'UndoLastSend',
      'Tap',
      'ResolveClaim',
      'ResolveDispute',
      'ResolveChangeRequest',
      'RequestBreak',
      'CollectDropped',
      'UseBooster',
      'Revive',
      'Abandon',
    });
  });

  test('all four in-trip boosters are used', () {
    final seen = {for (final r in results) ...r.boostersUsed};
    expect(
      seen.containsAll(const {
        BoosterId.changeBag,
        BoosterId.wakeAll,
        BoosterId.ledgerPeek,
        BoosterId.trafficJam,
      }),
      isTrue,
    );
  });

  test('every ending appears', () {
    final finished = {
      for (final r in results)
        if (r.outcome == TripOutcome.finished) r.stars,
    };
    expect(finished.containsAll({1, 2, 3}), isTrue);
    final outcomes = {for (final r in results) r.outcome};
    expect(outcomes, containsAll([TripOutcome.failed, TripOutcome.abandoned]));
    expect(results.any((r) => r.revived), isTrue);
  });

  test('each of the 5 sample trips has a sample fixture with 3 stars', () {
    final samples = {
      for (final MapEntry(:key, :value) in fixtures.entries)
        if (key.startsWith('sample__') && value.expectedResult.stars == 3)
          value.definition.tripId,
    };
    expect(samples, {
      'line_hay.01',
      'line_hay.02',
      'line_hay.03',
      'line_gamaa.01',
      'line_gamaa.02',
    });
  });

  test('each of the 5 sample trips has a solver fixture with 3 stars', () {
    final solved = {
      for (final MapEntry(:key, :value) in fixtures.entries)
        if (key.startsWith('solver__') && value.expectedResult.stars == 3)
          value.definition.tripId,
    };
    expect(solved, {
      'line_hay.01',
      'line_hay.02',
      'line_hay.03',
      'line_gamaa.01',
      'line_gamaa.02',
    });
  });
}
