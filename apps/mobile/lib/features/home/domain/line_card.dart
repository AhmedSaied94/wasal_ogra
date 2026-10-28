// Home's line card (specs/013-m08-home-result, data-model
// `LineCardFigures`, HANDOFF `C-Home` "Dynamic data"): the next trip's line,
// its place in it, the trips finished and the stars earned.
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/features/home/domain/next_trip.dart';

/// The most stars one trip earns.
const starsPerTrip = 3;

final class LineCardFigures {
  const LineCardFigures({
    required this.lineName,
    required this.tripIndex,
    required this.tripTotal,
    required this.finished,
    required this.starsEarned,
    required this.starsMax,
  });

  final String lineName;

  /// «المشوار {tripIndex} من {tripTotal}».
  final int tripIndex;
  final int tripTotal;

  /// The line's trips with a star or more: the bar is [finished] /
  /// [tripTotal].
  final int finished;

  /// Σ best stars over the line's trips, of 3 × [tripTotal].
  final int starsEarned;
  final int starsMax;

  /// The bar's fill, 0 to 1.
  double get progress => tripTotal == 0 ? 0 : finished / tripTotal;

  @override
  bool operator ==(Object other) =>
      other is LineCardFigures &&
      other.lineName == lineName &&
      other.tripIndex == tripIndex &&
      other.tripTotal == tripTotal &&
      other.finished == finished &&
      other.starsEarned == starsEarned &&
      other.starsMax == starsMax;

  @override
  int get hashCode => Object.hash(
    lineName,
    tripIndex,
    tripTotal,
    finished,
    starsEarned,
    starsMax,
  );
}

/// [next]'s line in figures. Null when the pack lacks the line.
LineCardFigures? lineCardFigures(
  ContentSource c,
  PlayerProgress p,
  NextTrip next,
) {
  final line = c.line(next.lineId);
  if (line == null) return null;
  final trips = c.tripsOf(next.lineId);
  return LineCardFigures(
    lineName: line.name.arEg,
    tripIndex: next.index,
    tripTotal: trips.length,
    finished: trips.where((t) => p.finished(t.tripId)).length,
    starsEarned: trips.fold(0, (sum, t) => sum + p.starsOf(t.tripId)),
    starsMax: starsPerTrip * trips.length,
  );
}
