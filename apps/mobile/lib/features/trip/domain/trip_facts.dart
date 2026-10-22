// What the projection knows about the trip besides the engine's state: the
// definition it started with, the line for names, the params, and the
// line's presentation tunables (data-model.md "TripSession").
import 'package:content_models/content_models.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/features/trip/domain/skin_looks.dart';

/// When a line shows بلية's hints (`trip_hints_mode_<line_id>`).
enum HintMode { off, firstTime, always }

/// The glossary's denominations, ascending: the drawer's eight slots.
const trayDenominations = [50, 100, 500, 1000, 2000, 5000, 10000, 20000];

/// The four boosters a trip offers, in the dashboard's order.
const tripBoosters = [
  BoosterId.changeBag,
  BoosterId.ledgerPeek,
  BoosterId.wakeAll,
  BoosterId.trafficJam,
];

final class TripFacts {
  TripFacts({
    required this.definition,
    required this.line,
    required this.params,
    required this.bubbleMinMs,
    required this.hintMode,
  });

  final TripDefinition definition;

  /// Null when the active pack no longer has the trip's line.
  final Line? line;
  final TripParams params;
  final int bubbleMinMs;
  final HintMode hintMode;

  late final Map<String, PassengerSpec> specs = {
    for (final p in definition.passengers) p.passengerId: p,
  };

  late final Map<String, SkinLook> looks = {
    for (final p in definition.passengers)
      p.passengerId: lookFor(p.skin, p.archetype),
  };

  /// Each drop-off station's slot (color and letter), by stop order.
  late final Map<String, int> slots = {
    for (final (i, s) in definition.stations.indexed) s.stationId: i,
  };

  late final Map<String, String> _stationNames = {
    for (final s in line?.stations ?? const <LineStation>[])
      s.stationId: s.name.arEg,
  };

  /// The number after the dot in the trip id: `line_hay.01` → 1.
  late final int tripNumber =
      int.tryParse(definition.tripId.split('.').last) ?? 0;

  bool get storyNoFights =>
      definition.kind == TripKind.story && definition.rules.noFightsRequired;

  /// The station's name in the trip's line, or null without the line.
  String? stationName(String stationId) => _stationNames[stationId];

  /// The destination slot of [passengerId], or null.
  int? slotOf(String passengerId) => switch (specs[passengerId]) {
    final spec? => slots[spec.destStationId],
    null => null,
  };

  /// The passengers of [passengerId]'s group, itself included.
  Iterable<String> groupOf(String passengerId) {
    final group = specs[passengerId]?.groupId;
    if (group == null) return [passengerId];
    return [
      for (final p in definition.passengers)
        if (p.groupId == group) p.passengerId,
    ];
  }

  /// The reputation a cause costs each time, or null for a gain.
  int? penaltyOf(RepCause cause) => switch (cause) {
    RepCause.fight => params.repFight,
    RepCause.falseAccusation => params.repFalseAccusation,
    RepCause.missedStop => params.repMissedStop,
    RepCause.shortChange => params.repShortChange,
    RepCause.impatient => params.repImpatient,
    RepCause.changeRequestDeclined => params.repChangeRequestDeclined,
    RepCause.exactChange || RepCause.liarCaught || RepCause.revive => null,
  };
}
