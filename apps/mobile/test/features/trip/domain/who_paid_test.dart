import 'dart:convert';

import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/features/trip/domain/talk_log.dart';

import '../../../helpers/trip.dart';

// Who has paid never shows (tasks.md T055, FR-033, contracts/trip-view.md
// "Who has paid").

/// [archetype] as the content writes it.
String _wire(Archetype archetype) => archetype.name.replaceAllMapped(
  RegExp('[A-Z]'),
  (m) => '_${m[0]!.toLowerCase()}',
);

/// The last station warning still standing.
typedef _Warning = ({String stationId, Set<String> owed});

void main() {
  test('nothing tells who has paid, at any moment of any fixture', () {
    var pulses = 0;
    var badges = 0;
    for (final name in allFixtureNames()) {
      _Warning? warning;
      playWithMemory(loadFixture(name), (state, view, events) {
        var reached = false;
        for (final event in events) {
          switch (event) {
            case StationWarning(:final stationId, :final owed):
              warning = (stationId: stationId, owed: owed.toSet());
              reached = false;
            case StationReached(:final stationId)
                when warning?.stationId == stationId:
              warning = null;
              reached = true;
            default:
          }
        }
        for (final p in view.passengers) {
          final at = '$name at ${state.tMs} ms, ${p.passengerId}';
          if (!state.ledgerPeekActive) {
            expect(p.ledgerBadge, isNull, reason: at);
          } else if (p.ledgerBadge != null) {
            badges++;
          }
          if (!p.nearStopPulse) continue;
          pulses++;
          expect(reached, isFalse, reason: '$at: cleared at the station');
          final standing = warning;
          expect(standing, isNotNull, reason: at);
          expect(standing!.stationId, state.nextStation?.stationId, reason: at);
          expect(standing.owed, contains(p.passengerId), reason: at);
          expect(state.passenger(p.passengerId)!.isOwed, isTrue, reason: at);
        }
      });
    }
    // The checks ran on something.
    expect(pulses, greaterThan(0));
    expect(badges, greaterThan(0));
  });

  test('speaker labels follow the skin, never the archetype', () {
    final archetypes = Archetype.values.where((a) => a != Archetype.groupPayer);
    for (final tripId in sampleTripIds) {
      final definition = sampleTrip(tripId);
      final facts = factsFor(definition);
      final state = TripEngine.start(definition, facts.params).state;
      for (var i = 0; i < definition.passengers.length; i++) {
        if (definition.passengers[i].archetype == Archetype.groupPayer) {
          continue;
        }
        for (final archetype in archetypes) {
          final json = jsonDecode(
            jsonEncode(definition.toJson()),
          ) as Map<String, Object?>;
          (json['passengers']! as List<Object?>)[i] = {
            ...(json['passengers']! as List<Object?>)[i]!
                as Map<String, Object?>,
            'archetype': _wire(archetype),
          };
          final swapped = factsFor(TripDefinition.fromJson(json));
          for (final p in state.passengers) {
            expect(
              speakerOf(p.passengerId, state, swapped),
              speakerOf(p.passengerId, state, facts),
              reason:
                  '$tripId: ${definition.passengers[i].passengerId} '
                  'as ${archetype.name}',
            );
          }
        }
      }
    }
  });
}
