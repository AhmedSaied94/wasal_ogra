// One station of the trip's schedule (data-model.md "StationState").

final class StationState {
  const StationState._({
    required this.stationId,
    required this.atMs,
    required this.farePiasters,
    required this.warned,
  });

  final String stationId;

  /// Current arrival time: the authored time plus every shift so far.
  final int atMs;

  /// Authored fare. The current fare adds `TripState.fareIncreasePiasters`.
  final int farePiasters;

  /// Whether `StationWarning` has fired.
  final bool warned;

  Map<String, Object> toJson() => {
    'station_id': stationId,
    'at_ms': atMs,
    'fare_piasters': farePiasters,
    'warned': warned,
  };
}

StationState makeStationState({
  required String stationId,
  required int atMs,
  required int farePiasters,
}) => StationState._(
  stationId: stationId,
  atMs: atMs,
  farePiasters: farePiasters,
  warned: false,
);

extension StationStateUpdate on StationState {
  StationState copyWith({int? atMs, bool? warned}) => StationState._(
    stationId: stationId,
    atMs: atMs ?? this.atMs,
    farePiasters: farePiasters,
    warned: warned ?? this.warned,
  );
}
