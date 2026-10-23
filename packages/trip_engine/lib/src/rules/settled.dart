// Whether anything is left for the player (rules.md §16): a query for the
// screen, which no rule reads.
import 'package:content_models/content_models.dart';

import '../model/passenger.dart';
import '../model/state.dart';
import 'course.dart';

/// With no command, the rest of the trip only reaches its stations, and
/// nothing the player could do would change the result.
bool isSettled(Course course, TripState state) {
  if (state.status != TripStatus.running && state.status != TripStatus.paused) {
    return false;
  }
  if (state.eventsFired.contains(false) ||
      state.tokens.isNotEmpty ||
      state.claims.isNotEmpty ||
      state.disputes.isNotEmpty ||
      state.changeRequests.isNotEmpty ||
      state.pendingBreaks.isNotEmpty) {
    return false;
  }
  for (final (i, passenger) in state.passengers.indexed) {
    if (!_settled(course, i, passenger)) return false;
  }
  return true;
}

// A sleeper who is awake dozes off again (§3, step 2.2), so one aboard
// always needs the player.
bool _settled(Course course, int i, PassengerState passenger) =>
    switch (passenger.presence) {
      Presence.gone => true,
      Presence.waiting => false,
      Presence.aboard =>
        course.archetype(i) != Archetype.sleeper &&
            passenger.balance == 0 &&
            (passenger.fareSent || passenger.neverPays || course.isMember(i)),
    };
