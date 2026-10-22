// The top bar's station strip (trip-view.md "The projection", research R16).
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/features/trip/domain/trip_facts.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';

StationStripView stationStrip(TripState state, TripFacts facts) {
  final schedule = state.schedule;
  final next = state.nextStationIndex;
  final student = facts.definition.rules.studentDiscountPct > 0;
  final countdown = switch (state.nextStation) {
    final station? => station.atMs - state.tMs,
    null => null,
  };
  return StationStripView(
    chips: [
      for (final (i, station) in schedule.indexed)
        StationChip(
          stationId: station.stationId,
          slot: i,
          name: facts.stationName(station.stationId),
          farePiasters: station.farePiasters + state.fareIncreasePiasters,
          studentIcon: student,
          reached: i < next,
          next: i == next,
        ),
    ],
    vehiclePermille: _vehiclePermille(state),
    countdownMs: countdown,
    warning:
        countdown != null && countdown <= facts.params.tripStationWarningMs,
  );
}

/// Station i sits at (i + 1) ÷ n of the strip; the vehicle moves between
/// the previous station's time (or the start) and the next one's.
int _vehiclePermille(TripState state) {
  final schedule = state.schedule;
  if (schedule.isEmpty) return 0;
  final next = state.nextStationIndex;
  if (next >= schedule.length) return 1000;
  final from = next == 0 ? 0 : schedule[next - 1].atMs;
  final to = schedule[next].atMs;
  final span = to - from;
  final done = span <= 0 ? 1000 : ((state.tMs - from) * 1000 ~/ span);
  final fraction = done.clamp(0, 1000);
  return (next * 1000 + fraction) ~/ schedule.length;
}
