// A line's trip grid (specs/014-m09-lines-vehicles, contracts/line-details.md
// "The cells", research R4): one cell a trip by number, and how many rows
// show before «والمشاوير من … لـ … بتظهر لما تقرّب».
import 'package:content_models/content_models.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/progress/domain/playable.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/core/progress/domain/unlocks.dart';

enum CellState {
  /// A star or more: a replay for stars.
  done,

  /// The line's next trip, with «كمّل».
  next,

  /// Another playable trip without a star (after the shabka, FR-024).
  playable,

  /// Not playable, with no star: not a link.
  locked,
}

final class TripCell {
  const TripCell({
    required this.tripId,
    required this.number,
    required this.isStory,
    required this.state,
    this.stars = 0,
  });

  final String tripId;

  /// 1-based, by trip number.
  final int number;

  /// The «قصة» chip, whatever the state.
  final bool isStory;
  final CellState state;

  /// The best stars of a done cell.
  final int stars;

  /// Whether a tap starts it.
  bool get startable => state != CellState.locked;

  @override
  bool operator ==(Object other) =>
      other is TripCell &&
      other.tripId == tripId &&
      other.number == number &&
      other.isStory == isStory &&
      other.state == state &&
      other.stars == stars;

  @override
  int get hashCode => Object.hash(tripId, number, isStory, state, stars);

  @override
  String toString() =>
      'TripCell($number, ${state.name}${isStory ? ', story' : ''}, $stars)';
}

/// [line]'s cells for [p]. A locked line's are all locked (FR-028).
List<TripCell> tripCells(ContentSource c, PlayerProgress p, LineId line) {
  final open = lineUnlocked(c, p, line);
  var nextTaken = false;
  return [
    for (final (index, trip) in c.tripsOf(line).indexed)
      () {
        final stars = p.starsOf(trip.tripId);
        final CellState state;
        if (!open) {
          state = CellState.locked;
        } else if (stars >= 1) {
          state = CellState.done;
        } else if (tripPlayable(c, p, trip.tripId)) {
          state = nextTaken ? CellState.playable : CellState.next;
          nextTaken = true;
        } else {
          state = CellState.locked;
        }
        return TripCell(
          tripId: trip.tripId,
          number: index + 1,
          isStory: trip.kind == TripKind.story,
          state: state,
          stars: open ? stars.clamp(0, 3) : 0,
        );
      }(),
  ];
}

/// Five cells a row (`LineDetails` block 2c).
const cellsPerRow = 5;

/// The rows a locked line shows, and the least any line shows.
const minVisibleRows = 4;

/// Rows shown past the next trip's.
const rowsAhead = 2;

final class VisibleRange {
  const VisibleRange({required this.rows, this.hidden});

  /// Rows shown, from the first.
  final int rows;

  /// The first and last trip numbers not shown; null when all are.
  final (int, int)? hidden;

  @override
  bool operator ==(Object other) =>
      other is VisibleRange && other.rows == rows && other.hidden == hidden;

  @override
  int get hashCode => Object.hash(rows, hidden);

  @override
  String toString() => 'VisibleRange($rows, $hidden)';
}

/// FR-025: `max(4, next row + 2)` rows, capped at the line's; every row for
/// a done line (no next trip); four for a locked one.
VisibleRange visibleRange(List<TripCell> cells, {bool locked = false}) {
  final total = (cells.length + cellsPerRow - 1) ~/ cellsPerRow;
  final next = cells.where((c) => c.state == CellState.next).firstOrNull;
  final int rows;
  if (locked) {
    rows = minVisibleRows < total ? minVisibleRows : total;
  } else if (next == null) {
    rows = total;
  } else {
    final nextRow = (next.number - 1) ~/ cellsPerRow;
    final wanted = nextRow + rowsAhead > minVisibleRows
        ? nextRow + rowsAhead
        : minVisibleRows;
    rows = wanted < total ? wanted : total;
  }
  final shown = rows * cellsPerRow;
  return VisibleRange(
    rows: rows,
    hidden: shown < cells.length ? (shown + 1, cells.length) : null,
  );
}
