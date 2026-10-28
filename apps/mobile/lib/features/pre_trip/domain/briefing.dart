// What the pre-trip card says of one trip (specs/013-m08-home-result,
// data-model `TripBriefing`, research R5, R7). The card describes what the
// engine does: the rule lines and the new subject only for what it plays.
import 'package:content_models/content_models.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/economy/domain/wire.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/features/pre_trip/domain/met_set.dart';
import 'package:wassal/features/pre_trip/domain/new_subjects.dart';
import 'package:wassal/features/trip/domain/looks.dart';

/// The in-trip boosters in the artboard's order: كيس فكة، الدفتر، صحّي
/// النايم، زحمة.
const boosterTileOrder = [
  BoosterId.changeBag,
  BoosterId.ledgerPeek,
  BoosterId.wakeAll,
  BoosterId.trafficJam,
];

/// A stop's cell: its [slot] in drop-off order (1–4, the colour and the
/// letter أ ب ج د), its name and its fare.
final class StopPrice {
  const StopPrice({
    required this.slot,
    required this.stationName,
    required this.farePiasters,
  });

  final int slot;
  final String stationName;
  final int farePiasters;

  @override
  bool operator ==(Object other) =>
      other is StopPrice &&
      other.slot == slot &&
      other.stationName == stationName &&
      other.farePiasters == farePiasters;

  @override
  int get hashCode => Object.hash(slot, stationName, farePiasters);

  @override
  String toString() => 'StopPrice($slot, $stationName, $farePiasters)';
}

/// A fare rule the trip applies (FR-028).
sealed class RuleLine {
  const RuleLine();
}

/// Students pay [percent] less with their card.
final class StudentLine extends RuleLine {
  const StudentLine(this.percent);

  final int percent;

  @override
  bool operator ==(Object other) =>
      other is StudentLine && other.percent == percent;

  @override
  int get hashCode => percent.hashCode;

  @override
  String toString() => 'StudentLine($percent)';
}

/// A bag pays [farePiasters].
final class BagLine extends RuleLine {
  const BagLine(this.farePiasters);

  final int farePiasters;

  @override
  bool operator ==(Object other) =>
      other is BagLine && other.farePiasters == farePiasters;

  @override
  int get hashCode => farePiasters.hashCode;
}

/// Children under [age] ride free.
final class ChildFreeLine extends RuleLine {
  const ChildFreeLine(this.age);

  final int age;

  @override
  bool operator ==(Object other) => other is ChildFreeLine && other.age == age;

  @override
  int get hashCode => age.hashCode;
}

/// What the «جديد» card introduces.
sealed class NewSubject {
  const NewSubject();

  /// Its wire id, which keys its name and sentence.
  String get wire;
}

/// A passenger type, drawn with the [look] of the trip's first passenger
/// of that type.
final class NewArchetype extends NewSubject {
  const NewArchetype(this.archetype, this.look);

  final Archetype archetype;
  final Look look;

  @override
  String get wire => newCardArchetypes[archetype]!;
}

/// An event, drawn with its [icon].
final class NewEvent extends NewSubject {
  const NewEvent(this.eventId, this.icon);

  final EventId eventId;
  final String icon;

  @override
  String get wire => newCardEvents[eventId]!;
}

/// A booster's tile and how many the player holds.
final class BoosterTile {
  const BoosterTile({required this.booster, required this.count});

  final BoosterId booster;
  final int count;

  @override
  bool operator ==(Object other) =>
      other is BoosterTile && other.booster == booster && other.count == count;

  @override
  int get hashCode => Object.hash(booster, count);

  @override
  String toString() => 'BoosterTile($booster, $count)';
}

/// The buy chip: the first booster at 0, at its catalog price.
final class BuyOffer {
  const BuyOffer({required this.booster, required this.priceBonat});

  final BoosterId booster;
  final int priceBonat;

  @override
  bool operator ==(Object other) =>
      other is BuyOffer &&
      other.booster == booster &&
      other.priceBonat == priceBonat;

  @override
  int get hashCode => Object.hash(booster, priceBonat);

  @override
  String toString() => 'BuyOffer($booster, $priceBonat)';
}

final class TripBriefing {
  const TripBriefing({
    required this.tripId,
    required this.lineName,
    required this.tripIndex,
    required this.isStory,
    required this.storyRuleNoFights,
    required this.stops,
    required this.ruleLines,
    required this.newSubject,
    required this.starsEarned,
    required this.boosters,
    required this.buyOffer,
    required this.boostersHidden,
  });

  final String tripId;
  final String lineName;

  /// 1-based, on its line.
  final int tripIndex;
  final bool isStory;
  final bool storyRuleNoFights;
  final List<StopPrice> stops;
  final List<RuleLine> ruleLines;
  final NewSubject? newSubject;
  final int starsEarned;
  final List<BoosterTile> boosters;
  final BuyOffer? buyOffer;

  /// M07's lock (FR-032): the whole block is hidden.
  final bool boostersHidden;
}

/// [tripId]'s briefing, or null when [content] lacks the trip.
TripBriefing? tripBriefing(
  ContentSource content, {
  required String tripId,
  required PlayerProgress progress,
  required Map<BoosterId, int> inventory,
  required MetSet met,
  required bool boostersLocked,
}) {
  final trip = content.trip(tripId);
  final line = trip == null ? null : content.line(trip.lineId);
  if (trip == null || line == null) return null;
  final names = {for (final s in line.stations) s.stationId: s.name.arEg};
  final stops = [...trip.stations]
    ..sort((a, b) => a.atSeconds.compareTo(b.atSeconds));
  final boosters = [
    for (final booster in boosterTileOrder)
      BoosterTile(booster: booster, count: inventory[booster] ?? 0),
  ];
  return TripBriefing(
    tripId: tripId,
    lineName: line.name.arEg,
    tripIndex: content.tripsOf(trip.lineId).indexOf(trip) + 1,
    isStory: trip.kind == TripKind.story,
    storyRuleNoFights: trip.rules.noFightsRequired,
    stops: [
      for (final (i, stop) in stops.indexed)
        StopPrice(
          slot: i + 1,
          stationName: names[stop.stationId] ?? stop.stationId,
          farePiasters: stop.farePiasters,
        ),
    ],
    ruleLines: _ruleLines(trip),
    newSubject: newSubjectOf(trip, met),
    starsEarned: progress.starsOf(tripId),
    boosters: boosters,
    buyOffer: boostersLocked ? null : _offer(content, boosters),
    boostersHidden: boostersLocked,
  );
}

/// The first of [trip]'s passenger types, then its events, that [met]
/// lacks and the card can introduce.
NewSubject? newSubjectOf(TripDefinition trip, MetSet met) {
  for (final passenger in trip.passengers) {
    final type = passenger.archetype;
    if (met.archetypes.contains(type)) continue;
    if (!newCardArchetypes.containsKey(type)) continue;
    return NewArchetype(type, lookFor(passenger.skin, type));
  }
  for (final event in trip.events) {
    if (met.events.contains(event.eventId)) continue;
    if (eventIcons[event.eventId] case final icon?) {
      return NewEvent(event.eventId, icon);
    }
  }
  return null;
}

List<RuleLine> _ruleLines(TripDefinition trip) {
  final types = {for (final p in trip.passengers) p.archetype};
  final rules = trip.rules;
  return [
    if (rules.studentDiscountPct > 0 && types.contains(Archetype.student))
      StudentLine(rules.studentDiscountPct),
    if (rules.bagFarePiasters > 0 && types.any(bagArchetypes.contains))
      BagLine(rules.bagFarePiasters),
    if (rules.childFreeAge > 0 && types.any(childArchetypes.contains))
      ChildFreeLine(rules.childFreeAge),
  ];
}

BuyOffer? _offer(ContentSource content, List<BoosterTile> tiles) {
  for (final tile in tiles) {
    if (tile.count > 0) continue;
    final price = content.price(SkuKind.booster, boosterWire[tile.booster]!);
    if (price == null || price.currency != Currency.bonat) continue;
    return BuyOffer(booster: tile.booster, priceBonat: price.amount);
  }
  return null;
}
