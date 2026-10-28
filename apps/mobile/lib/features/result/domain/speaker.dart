// Who a passenger is in the result's lines (specs/013-m08-home-result,
// research R14, R15): their look, and its label, with «الشلة» for a group
// payer, as «آخر كلام» names them (the trip's talk_log.dart).
import 'package:content_models/content_models.dart';
import 'package:wassal/features/trip/domain/looks.dart';

typedef Speaker = ({Look look, String labelKey});

/// [passengerId] of [trip]; a passenger the trip lacks has the neutral
/// look.
Speaker speakerOf(TripDefinition trip, String passengerId) {
  for (final spec in trip.passengers) {
    if (spec.passengerId != passengerId) continue;
    final look = lookFor(spec.skin, spec.archetype);
    return (
      look: look,
      labelKey: spec.archetype == Archetype.groupPayer
          ? groupLabelKey
          : look.labelKey,
    );
  }
  final look = lookFor(_neutral, Archetype.regular);
  return (look: look, labelKey: look.labelKey);
}

const _neutral = 'regular';
