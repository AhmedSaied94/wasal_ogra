// A line's standing on Lines (specs/014-m09-lines-vehicles, data-model
// `LineStanding`, contracts/lines.md): locked with its reason, current with
// its next trip, or done, with its stars and its content.
import 'package:content_models/content_models.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/progress/domain/playable.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/core/progress/domain/unlocks.dart';

/// What opens a locked line (FR-046).
sealed class LockReason {
  const LockReason();
}

/// «محتاج {vehicle}».
final class NeedsVehicle extends LockReason {
  const NeedsVehicle(this.vehicle);

  final VehicleId vehicle;

  @override
  bool operator ==(Object other) =>
      other is NeedsVehicle && other.vehicle == vehicle;

  @override
  int get hashCode => vehicle.hashCode;

  @override
  String toString() => 'NeedsVehicle(${vehicle.name})';
}

/// «بعد {line}».
final class AfterLine extends LockReason {
  const AfterLine(this.line);

  final LineId line;

  @override
  bool operator ==(Object other) => other is AfterLine && other.line == line;

  @override
  int get hashCode => line.hashCode;

  @override
  String toString() => 'AfterLine(${line.name})';
}

/// A line's next trip: «المشوار {number} من {total}».
final class NextInLine {
  const NextInLine({
    required this.tripId,
    required this.number,
    required this.total,
  });

  final String tripId;

  /// 1-based, by trip number.
  final int number;
  final int total;

  @override
  bool operator ==(Object other) =>
      other is NextInLine &&
      other.tripId == tripId &&
      other.number == number &&
      other.total == total;

  @override
  int get hashCode => Object.hash(tripId, number, total);

  @override
  String toString() => 'NextInLine($tripId, $number/$total)';
}

sealed class LineState {
  const LineState();
}

/// Not open yet. [reason] is null only for a rule the content leaves
/// incomplete.
final class LineLocked extends LineState {
  const LineLocked(this.reason);

  final LockReason? reason;

  @override
  bool operator ==(Object other) =>
      other is LineLocked && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;

  @override
  String toString() => 'LineLocked($reason)';
}

/// Open, with a playable trip without a star.
final class LineCurrent extends LineState {
  const LineCurrent(this.next);

  final NextInLine next;

  @override
  bool operator ==(Object other) => other is LineCurrent && other.next == next;

  @override
  int get hashCode => next.hashCode;

  @override
  String toString() => 'LineCurrent($next)';
}

/// Open, with no playable trip left without a star: every trip a replay.
final class LineDone extends LineState {
  const LineDone();

  @override
  bool operator ==(Object other) => other is LineDone;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'LineDone()';
}

final class LineStanding {
  const LineStanding({
    required this.line,
    required this.name,
    required this.whatsNew,
    required this.farePiasters,
    required this.state,
    required this.starsEarned,
    required this.starsMax,
    required this.allThree,
    required this.doneCount,
  });

  final LineId line;
  final String name;
  final String whatsNew;

  /// The card's fare chip (display only, FR-043).
  final int farePiasters;
  final LineState state;

  /// The sum of the best stars of the line's trips.
  final int starsEarned;

  /// Three a trip.
  final int starsMax;

  /// Every trip at three stars: no «عيد عشان النجوم».
  final bool allThree;

  /// Trips with a star or more.
  final int doneCount;

  @override
  bool operator ==(Object other) =>
      other is LineStanding &&
      other.line == line &&
      other.name == name &&
      other.whatsNew == whatsNew &&
      other.farePiasters == farePiasters &&
      other.state == state &&
      other.starsEarned == starsEarned &&
      other.starsMax == starsMax &&
      other.allThree == allThree &&
      other.doneCount == doneCount;

  @override
  int get hashCode => Object.hash(
    line,
    name,
    whatsNew,
    farePiasters,
    state,
    starsEarned,
    starsMax,
    allThree,
    doneCount,
  );

  @override
  String toString() => 'LineStanding(${line.name}, $state)';
}

/// Every line of [c] in pack order.
List<LineStanding> lineStandings(ContentSource c, PlayerProgress p) => [
  for (final line in c.lines) lineStanding(c, p, line),
];

/// [line]'s standing for [p].
LineStanding lineStanding(ContentSource c, PlayerProgress p, Line line) {
  final trips = c.tripsOf(line.lineId);
  var earned = 0;
  var done = 0;
  for (final trip in trips) {
    final stars = p.starsOf(trip.tripId);
    earned += stars;
    if (stars >= 1) done++;
  }
  return LineStanding(
    line: line.lineId,
    name: line.name.arEg,
    whatsNew: line.whatsNew.arEg,
    farePiasters: line.displayFarePiasters,
    state: _state(c, p, line, trips),
    starsEarned: earned,
    starsMax: 3 * trips.length,
    allThree: trips.isNotEmpty && trips.every((t) => p.starsOf(t.tripId) >= 3),
    doneCount: done,
  );
}

/// [lineId]'s next trip: the first by number that is playable and has no
/// star (FR-008). Null when there is none.
NextInLine? nextInLine(ContentSource c, PlayerProgress p, LineId lineId) {
  final trips = c.tripsOf(lineId);
  for (final (index, trip) in trips.indexed) {
    if (p.starsOf(trip.tripId) == 0 && tripPlayable(c, p, trip.tripId)) {
      return NextInLine(
        tripId: trip.tripId,
        number: index + 1,
        total: trips.length,
      );
    }
  }
  return null;
}

LineState _state(
  ContentSource c,
  PlayerProgress p,
  Line line,
  List<TripDefinition> trips,
) {
  if (!lineUnlocked(c, p, line.lineId)) {
    return LineLocked(lockReason(line));
  }
  return switch (nextInLine(c, p, line.lineId)) {
    final next? => LineCurrent(next),
    null => const LineDone(),
  };
}

/// What opens [line], from its unlock rule; null for a start line or a rule
/// without its id.
LockReason? lockReason(Line line) => switch (line.unlock) {
  LineUnlock(kind: UnlockKind.vehicle, :final vehicleId?) => NeedsVehicle(
    vehicleId,
  ),
  LineUnlock(kind: UnlockKind.lineComplete, lineId: final after?) => AfterLine(
    after,
  ),
  _ => null,
};
