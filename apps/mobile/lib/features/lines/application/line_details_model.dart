// What a line's details draw (specs/014-m09-lines-vehicles, contracts/
// line-details.md): the line's standing, its cells and how many show.
import 'package:content_models/content_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/progress/application/player_progress_provider.dart';
import 'package:wassal/features/lines/domain/line_standing.dart';
import 'package:wassal/features/lines/domain/trip_cells.dart';

part 'line_details_model.g.dart';

final class LineDetailsModel {
  const LineDetailsModel({
    required this.standing,
    required this.cells,
    required this.range,
    required this.reason,
  });

  final LineStanding standing;
  final List<TripCell> cells;
  final VisibleRange range;

  /// A locked line's reason, as the pack names what opens it: the
  /// vehicle's name or the line's.
  final ({LockReason reason, String name})? reason;

  @override
  bool operator ==(Object other) =>
      other is LineDetailsModel &&
      other.standing == standing &&
      other.range == range &&
      other.reason == reason &&
      other.cells.length == cells.length &&
      [for (var i = 0; i < cells.length; i++) other.cells[i] == cells[i]]
          .every((same) => same);

  @override
  int get hashCode => Object.hash(standing, range, reason, cells.length);
}

/// Null for a line the active pack lacks.
@riverpod
LineDetailsModel? lineDetailsModel(Ref ref, LineId lineId) {
  final content = ref.watch(contentSourceProvider);
  final progress = ref.watch(playerProgressProvider);
  final line = content.line(lineId);
  if (line == null) return null;
  final standing = lineStanding(content, progress, line);
  final cells = tripCells(content, progress, lineId);
  final state = standing.state;
  final reason = switch (state) {
    LineLocked(reason: final NeedsVehicle reason) => (
      reason: reason as LockReason,
      name: content.vehicle(reason.vehicle)?.name.arEg ?? '',
    ),
    LineLocked(reason: final AfterLine reason) => (
      reason: reason as LockReason,
      name: content.line(reason.line)?.name.arEg ?? '',
    ),
    _ => null,
  };
  return LineDetailsModel(
    standing: standing,
    cells: cells,
    range: visibleRange(cells, locked: state is LineLocked),
    reason: reason,
  );
}
