// «آخر كلام»: the last two things said or sent (contracts/trip-view.md).
import 'package:content_models/content_models.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/features/trip/domain/skin_looks.dart';
import 'package:wassal/features/trip/domain/trip_facts.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/domain/view_value.dart';

/// Lines «آخر كلام» keeps.
const talkLogLength = 2;

final class TalkLog extends ViewValue {
  const TalkLog([this.lines = const []]);

  static const empty = TalkLog();

  /// Oldest first.
  final List<LogLine> lines;

  TalkLog push(LogLine line) {
    final all = [...lines, line];
    return TalkLog(
      all.length > talkLogLength
          ? all.sublist(all.length - talkLogLength)
          : all,
    );
  }

  @override
  Map<String, Object?> get fields => {'lines': lines};
}

/// Who [passengerId] is in «آخر كلام»: their look's label, «الشلة» for a
/// group payer, and their station's letter when another passenger aboard
/// shares the label. Never the archetype's name (research R10).
SpeakerLabel speakerOf(String passengerId, TripState state, TripFacts facts) {
  String labelOf(String id) =>
      facts.specs[id]?.archetype == Archetype.groupPayer
      ? groupLabelKey
      : facts.looks[id]?.labelKey ?? passengerLabelKey;
  final label = labelOf(passengerId);
  final shared = state.passengers.any(
    (p) =>
        p.passengerId != passengerId &&
        p.presence == Presence.aboard &&
        labelOf(p.passengerId) == label,
  );
  return SpeakerLabel(
    labelKey: label,
    slot: shared ? facts.slotOf(passengerId) : null,
  );
}
