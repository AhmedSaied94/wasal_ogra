// What the failure card says (contracts/trip-view.md "Failure summary"):
// the causes that cost the trip its reputation, and the BONAT revive when
// the rules allow one (contracts/trip-controller.md "Revive"). From 008.5
// it also says whether a story trip's rule was broken, and whose angry
// faces the card draws (data-model.md "FailSummary").
import 'package:content_models/content_models.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/features/trip/domain/trip_facts.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';

/// A revive is offered only below the engine's command cap, which refuses
/// the `Revive` itself past it (M01 research R9).
const reviveCommandCap = 1200;

/// The faces the failure card draws, at most.
const maxAngryFaces = 3;

/// The failure card's causes: the top two of [reputationLost] by points,
/// each with its count, since every time costs the same penalty. With the
/// failed [state], also the broken story rule and the angry faces.
FailSummary failSummary(
  Map<RepCause, int> reputationLost,
  TripFacts facts,
  ReviveOffer? revive, {
  TripState? state,
}) {
  final lost =
      reputationLost.entries.where((e) => e.key.loss && e.value > 0).toList()
        ..sort((a, b) {
          final byPoints = b.value.compareTo(a.value);
          return byPoints != 0 ? byPoints : a.key.index.compareTo(b.key.index);
        });
  return FailSummary(
    causes: [
      for (final MapEntry(key: cause, value: points) in lost.take(2))
        FailCause(
          cause: cause,
          count: switch (facts.penaltyOf(cause)) {
            final penalty? when penalty > 0 => points ~/ penalty,
            _ => null,
          },
        ),
    ],
    revive: revive,
    brokeStoryRule:
        state != null &&
        facts.storyNoFights &&
        state.status == TripStatus.failed &&
        state.counters.fights > 0,
    angryFaces: state == null ? const [] : _angryFaces(state, facts),
  );
}

/// Those who fought, then those who missed their stop, then those still
/// seated; each group in seat order, the near row first, right to left,
/// the front seat last.
List<String> _angryFaces(TripState state, TripFacts facts) {
  final seats = {for (final s in facts.definition.seats) s.seatId: s};
  int seatRank(String seatId) => switch (seats[seatId]) {
    final seat? =>
      (seat.row == SeatRow.front ? SeatRow.values.length : seat.row.index) *
              SeatCol.values.length +
          seat.col.index,
    null => 0,
  };
  int? groupOf(PassengerState p) => switch (p.outcome) {
    AlightOutcome.fight => 0,
    AlightOutcome.missedStop => 1,
    _ when p.presence == Presence.aboard => 2,
    _ => null,
  };
  final ranked =
      [
        for (final p in state.passengers)
          if (groupOf(p) case final group?)
            (p.passengerId, group, seatRank(p.seatId)),
      ]..sort((a, b) {
        final byGroup = a.$2.compareTo(b.$2);
        return byGroup != 0 ? byGroup : a.$3.compareTo(b.$3);
      });
  return [for (final (id, _, _) in ranked.take(maxAngryFaces)) id];
}

/// The revive the card offers, or null: the engine allows one, the trip is
/// below the command cap, this trip's revive isn't [paid] already, and the
/// catalog prices it. Unaffordable below [priceBonat].
ReviveOffer? reviveOffer(
  TripState state, {
  required int? priceBonat,
  required int bonat,
  required bool paid,
}) {
  if (!state.revivable ||
      state.commandsAccepted >= reviveCommandCap ||
      paid ||
      priceBonat == null) {
    return null;
  }
  return ReviveOffer(priceBonat: priceBonat, affordable: bonat >= priceBonat);
}
