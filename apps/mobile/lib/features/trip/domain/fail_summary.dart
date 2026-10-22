// What the failure card says (contracts/trip-view.md "Failure summary"):
// the causes that cost the trip its reputation, and the BONAT revive when
// the rules allow one (contracts/trip-controller.md "Revive").
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/features/trip/domain/trip_facts.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';

/// A revive is offered only below the engine's command cap, which refuses
/// the `Revive` itself past it (M01 research R9).
const reviveCommandCap = 1200;

/// The failure card's causes: the top two of [reputationLost] by points,
/// each with its count, since every time costs the same penalty.
FailSummary failSummary(
  Map<RepCause, int> reputationLost,
  TripFacts facts,
  ReviveOffer? revive,
) {
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
  );
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
