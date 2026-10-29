// Home's next trip (specs/013-m08-home-result, research R3, data-model
// `NextTrip`): a startable unfinished trip on the line played last, else on
// the earliest open line, else a replay with the fewest stars on the line
// played last. M07's tutorial trip replaces it during the first session,
// in the application layer.
import 'package:content_models/content_models.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/progress/domain/playable.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/core/progress/domain/unlocks.dart';

final class NextTrip {
  const NextTrip({
    required this.tripId,
    required this.lineId,
    required this.index,
    this.isReplay = false,
  });

  /// [tripId] of [c] as a next trip, or null when the pack lacks it.
  static NextTrip? of(ContentSource c, String tripId, {bool isReplay = false}) {
    final trip = c.trip(tripId);
    if (trip == null) return null;
    final index = c.tripsOf(trip.lineId).indexWhere((t) => t.tripId == tripId);
    return NextTrip(
      tripId: tripId,
      lineId: trip.lineId,
      index: index + 1,
      isReplay: isReplay,
    );
  }

  final String tripId;

  /// The line Home's card and scene show.
  final LineId lineId;

  /// 1-based, in `tripsOf(lineId)`: «المشوار {n}».
  final int index;

  /// Every open line is finished: this is a trip to play again.
  final bool isReplay;

  @override
  bool operator ==(Object other) =>
      other is NextTrip &&
      other.tripId == tripId &&
      other.lineId == lineId &&
      other.index == index &&
      other.isReplay == isReplay;

  @override
  int get hashCode => Object.hash(tripId, lineId, index, isReplay);

  @override
  String toString() =>
      'NextTrip($tripId, #$index${isReplay ? ', replay' : ''})';
}

/// The next trip by FR-010's rule, with [lastFinishedTripId] naming the line
/// played last. Null only for a pack with no startable trip.
NextTrip? nextTrip(
  ContentSource c,
  PlayerProgress p, {
  String? lastFinishedTripId,
}) {
  // A story trip comes at its moment in the story
  // (specs/014-m09-lines-vehicles, FR-012).
  bool startable(TripDefinition t) => tripPlayable(c, p, t.tripId);
  bool unfinished(TripDefinition t) => p.starsOf(t.tripId) == 0;

  // 3. The line played last; with no finished trip, the first by order.
  final lines = c.lines;
  if (lines.isEmpty) return null;
  final last = switch (lastFinishedTripId) {
    final id? => c.trip(id)?.lineId,
    null => null,
  };
  final followed = last ?? lines.first.lineId;

  // 4. Its first startable unfinished trip, by trip number.
  if (_first(c.tripsOf(followed), (t) => startable(t) && unfinished(t))
      case final trip?) {
    return NextTrip.of(c, trip.tripId);
  }
  // 5. Else the earliest open line, by order, with one.
  for (final line in lines) {
    if (!lineUnlocked(c, p, line.lineId)) continue;
    if (_first(c.tripsOf(line.lineId), (t) => startable(t) && unfinished(t))
        case final trip?) {
      return NextTrip.of(c, trip.tripId);
    }
  }
  // 6. Else a replay: the fewest best stars on the line played last, the
  // earliest on a tie; on the first open line with a startable trip when
  // that line has none.
  for (final lineId in [followed, for (final l in lines) l.lineId]) {
    final startables = c.tripsOf(lineId).where(startable).toList();
    if (startables.isEmpty) continue;
    var best = startables.first;
    for (final trip in startables.skip(1)) {
      if (p.starsOf(trip.tripId) < p.starsOf(best.tripId)) best = trip;
    }
    return NextTrip.of(c, best.tripId, isReplay: true);
  }
  // 7. Nothing startable at all, which a validated pack never is.
  return null;
}

/// The trip finished first most recently: the line played last at launch,
/// before a trip of this run names it (research R3). Null with none.
String? lastFirstCompleted(Map<String, TripProgress> progress) {
  String? latest;
  var at = -1;
  for (final MapEntry(key: id, value: trip) in progress.entries) {
    final completed = trip.firstCompletedAtMs;
    if (completed != null && completed > at) {
      latest = id;
      at = completed;
    }
  }
  return latest;
}

TripDefinition? _first(
  List<TripDefinition> trips,
  bool Function(TripDefinition trip) test,
) {
  for (final trip in trips) {
    if (test(trip)) return trip;
  }
  return null;
}
