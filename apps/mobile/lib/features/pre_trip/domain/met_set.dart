// The passenger types and events a player has met (specs/013-m08-home-result,
// data-model `MetSet`, research R5). Derived from progress, so it follows a
// restore.
import 'package:content_models/content_models.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';

typedef MetSet = ({Set<Archetype> archetypes, Set<EventId> events});

/// The archetypes and events of every trip in [content] that [progress]
/// finished (at least one star). Trips the pack lacks are skipped.
MetSet metSet(ContentSource content, PlayerProgress progress) {
  final archetypes = <Archetype>{};
  final events = <EventId>{};
  for (final tripId in progress.bestStars.keys) {
    if (!progress.finished(tripId)) continue;
    final trip = content.trip(tripId);
    if (trip == null) continue;
    archetypes.addAll([for (final p in trip.passengers) p.archetype]);
    events.addAll([for (final e in trip.events) e.eventId]);
  }
  return (archetypes: archetypes, events: events);
}
