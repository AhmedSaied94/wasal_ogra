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
    this.playable = true,
  });

  final String tripId;

  /// 1-based, by trip number.
  final int number;

  /// The «قصة» chip, whatever the state.
  final bool isStory;
  final CellState state;

  /// The best stars of a done cell.
  final int stars;

  /// Whether the rules let the trip start (FR-012, FR-026). A done cell
  /// keeps its stars but isn't a link when they don't.
  final bool playable;

  /// Whether a tap starts it.
  bool get startable => playable && state != CellState.locked;

  @override
  bool operator ==(Object other) =>
      other is TripCell &&
      other.tripId == tripId &&
      other.number == number &&
      other.isStory == isStory &&
      other.state == state &&
      other.stars == stars &&
      other.playable == playable;

  @override
  int get hashCode =>
      Object.hash(tripId, number, isStory, state, stars, playable);

  @override
  String toString() =>
      'TripCell($number, ${state.name}${isStory ? ', story' : ''}, $stars'
      '${playable ? '' : ', locked'})';
}

/// [line]'s cells for [p]. A locked line's are all locked (FR-028).
List<TripCell> tripCells(ContentSource c, PlayerProgress p, LineId line) {
  final open = lineUnlocked(c, p, line);
  var nextTaken = false;
  return [
    for (final (index, trip) in c.tripsOf(line).indexed)
      () {
        final stars = p.starsOf(trip.tripId);
        // The rules decide a tap, whatever the stars say (FR-026): a done
        // trip that is no longer playable (a newer pack, a rolled-back
        // purchase) keeps its stars but isn't a link.
        final playable = open && tripPlayable(c, p, trip.tripId);
        final CellState state;
        if (!open) {
          state = CellState.locked;
        } else if (stars >= 1) {
          state = CellState.done;
        } else if (playable) {
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
          playable: open && playable,
        );
      }(),
  ];
}

/// Five cells a row (`LineDetails` block 2c).
const cellsPerRow = 5;

/// The rows a locked line shows, and the least any line shows.
const minVisibleRows = 4;

/// Rows shown past the furthest trip played or playable.
const rowsAhead = 1;

/// The row a 1-based trip number is in.
int _rowOf(int number) => (number - 1) ~/ cellsPerRow + 1;

/// The last cell drawn as done or playable, if any.
TripCell? _lastUsed(List<TripCell> cells) {
  for (final cell in cells.reversed) {
    if (cell.state != CellState.locked) return cell;
  }
  return null;
}

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

/// FR-025 (as `LineDetailsStory` draws it, 2026-10-29): every row through
/// the furthest trip played or playable, and one more, at least four; so
/// every row for a done line, and four for a locked one. A story trip can
/// open behind trips the player already finished (the shabka, a newer
/// pack), so the rows count from the furthest, and nothing played becomes
/// unreachable.
VisibleRange visibleRange(List<TripCell> cells, {bool locked = false}) {
  final total = (cells.length + cellsPerRow - 1) ~/ cellsPerRow;
  var wanted = minVisibleRows;
  final lastUsed = locked ? null : _lastUsed(cells);
  if (lastUsed != null && _rowOf(lastUsed.number) + rowsAhead > wanted) {
    wanted = _rowOf(lastUsed.number) + rowsAhead;
  }
  final rows = wanted < total ? wanted : total;
  final shown = rows * cellsPerRow;
  return VisibleRange(
    rows: rows,
    hidden: shown < cells.length ? (shown + 1, cells.length) : null,
  );
}
