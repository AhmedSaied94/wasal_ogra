// What the result screen says of a finished trip (specs/013-m08-home-result,
// data-model `ResultSummary`, research R14, R15). Every figure is the
// result's own; the only rule is the doubled pay.
import 'package:content_models/content_models.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/txn_id.dart';
import 'package:wassal/features/result/domain/result_args.dart';
import 'package:wassal/features/result/domain/speaker.dart';
import 'package:wassal/features/trip/domain/looks.dart';

/// What a star is for (RULES §11), in the stars' order.
enum StarCondition { reached, noFights, noMistakes }

final class StarRow {
  const StarRow(this.condition, {required this.earned});

  final StarCondition condition;
  final bool earned;

  @override
  bool operator ==(Object other) =>
      other is StarRow &&
      other.condition == condition &&
      other.earned == earned;

  @override
  int get hashCode => Object.hash(condition, earned);

  @override
  String toString() => 'StarRow(${condition.name}, $earned)';
}

/// The breakdown card's four rows.
final class Breakdown {
  const Breakdown({
    required this.faresPiasters,
    required this.tipsPiasters,
    required this.overpaidPiasters,
    required this.fights,
  });

  final int faresPiasters;
  final int tipsPiasters;
  final int overpaidPiasters;
  final int fights;

  @override
  bool operator ==(Object other) =>
      other is Breakdown &&
      other.faresPiasters == faresPiasters &&
      other.tipsPiasters == tipsPiasters &&
      other.overpaidPiasters == overpaidPiasters &&
      other.fights == fights;

  @override
  int get hashCode =>
      Object.hash(faresPiasters, tipsPiasters, overpaidPiasters, fights);

  @override
  String toString() =>
      'Breakdown($faresPiasters, +$tipsPiasters, -$overpaidPiasters, '
      '$fights fights)';
}

/// How an amount reads in a mistake's sentence: «نص جنيه», «جنيه», or
/// «{amount} جنيه».
enum AmountSize { half, one, other }

const _half = 50;
const _one = 100;

AmountSize amountSizeOf(int piasters) => switch (piasters) {
  _half => AmountSize.half,
  _one => AmountSize.one,
  _ => AmountSize.other,
};

/// A line of the mistakes card.
sealed class MistakeLine {
  const MistakeLine();
}

/// One of the result's `mistakes`, with its passenger.
final class PassengerMistake extends MistakeLine {
  const PassengerMistake({
    required this.passengerId,
    required this.look,
    required this.labelKey,
    required this.feminine,
    required this.kind,
    required this.amountPiasters,
  });

  final String passengerId;
  final Look look;

  /// The ARB key of who they are («الطالب», «راكب», «الشلة»).
  final String labelKey;
  final bool feminine;
  final MistakeKind kind;
  final int amountPiasters;

  AmountSize get size => amountSizeOf(amountPiasters);

  @override
  bool operator ==(Object other) =>
      other is PassengerMistake &&
      other.passengerId == passengerId &&
      other.look == look &&
      other.labelKey == labelKey &&
      other.feminine == feminine &&
      other.kind == kind &&
      other.amountPiasters == amountPiasters;

  @override
  int get hashCode =>
      Object.hash(passengerId, look, labelKey, feminine, kind, amountPiasters);

  @override
  String toString() =>
      'PassengerMistake($passengerId ${kind.name} $amountPiasters)';
}

/// What a count line counts.
enum CountKind { fights, missedStops, lostFares }

final class CountLine extends MistakeLine {
  const CountLine(this.kind, this.count);

  final CountKind kind;
  final int count;

  @override
  bool operator ==(Object other) =>
      other is CountLine && other.kind == kind && other.count == count;

  @override
  int get hashCode => Object.hash(kind, count);

  @override
  String toString() => 'CountLine(${kind.name}, $count)';
}

/// Which stars what went wrong cost: fights the second and the third,
/// mistakes the third, losses none (RULES §11).
enum SummaryFamily { fights, mistakes, losses }

/// The mistakes card's summary row.
final class MistakesSummary {
  const MistakesSummary({required this.count, required this.family});

  final int count;
  final SummaryFamily family;

  @override
  bool operator ==(Object other) =>
      other is MistakesSummary &&
      other.count == count &&
      other.family == family;

  @override
  int get hashCode => Object.hash(count, family);

  @override
  String toString() => 'MistakesSummary(${family.name}, $count)';
}

/// The result's header and title, from the trip as the content has it.
final class ResultHeading {
  const ResultHeading({
    required this.tripId,
    required this.tripIndex,
    required this.lineName,
    required this.lastStop,
    required this.isStory,
  });

  final String tripId;

  /// «المشوار {tripIndex} · {lineName}».
  final int tripIndex;
  final String lineName;

  /// «وصلنا {lastStop}!».
  final String lastStop;
  final bool isStory;

  @override
  bool operator ==(Object other) =>
      other is ResultHeading &&
      other.tripId == tripId &&
      other.tripIndex == tripIndex &&
      other.lineName == lineName &&
      other.lastStop == lastStop &&
      other.isStory == isStory;

  @override
  int get hashCode =>
      Object.hash(tripId, tripIndex, lineName, lastStop, isStory);
}

/// [trip]'s heading, or null when [content] lacks its line or the trip.
ResultHeading? resultHeading(ContentSource content, TripDefinition trip) {
  final line = content.line(trip.lineId);
  final index = content
      .tripsOf(trip.lineId)
      .indexWhere((t) => t.tripId == trip.tripId);
  if (line == null || index < 0) return null;
  final names = {for (final s in line.stations) s.stationId: s.name.arEg};
  final last = trip.stations.reduce(
    (a, b) => b.atSeconds >= a.atSeconds ? b : a,
  );
  return ResultHeading(
    tripId: trip.tripId,
    tripIndex: index + 1,
    lineName: line.name.arEg,
    lastStop: names[last.stationId] ?? last.stationId,
    isStory: trip.kind == TripKind.story,
  );
}

final class ResultSummary {
  const ResultSummary({
    required this.heading,
    required this.stars,
    required this.starRows,
    required this.breakdown,
    required this.mistakeLines,
    required this.summary,
    required this.payJenehat,
    required this.firstThreeStars,
  });

  final ResultHeading heading;
  final int stars;
  final List<StarRow> starRows;
  final Breakdown breakdown;
  final List<MistakeLine> mistakeLines;

  /// Null when nothing went wrong: the card is hidden.
  final MistakesSummary? summary;
  final int payJenehat;

  /// Three stars on a trip that had fewer: the celebration (FR-045).
  final bool firstThreeStars;

  String get tripId => heading.tripId;
  int get tripIndex => heading.tripIndex;
  String get lineName => heading.lineName;
  String get lastStop => heading.lastStop;
  bool get isStory => heading.isStory;
}

/// [earningsJenehat], doubled when [lastResult] is [startTxn]'s, doubled.
int payOf(
  int earningsJenehat, {
  required LastResult? lastResult,
  required TxnId startTxn,
}) {
  final doubled =
      lastResult != null &&
      lastResult.startTxn == startTxn &&
      lastResult.doubled;
  return doubled ? earningsJenehat * _doubling : earningsJenehat;
}

/// What the ×2 multiplies the pay by.
const _doubling = 2;

/// [args]'s summary, or null when [content] lacks the trip's line or the
/// trip. The pay is doubled when [lastResult] is this start's, doubled.
ResultSummary? resultSummary(
  ContentSource content,
  ResultArgs args, {
  required LastResult? lastResult,
}) {
  final result = args.result;
  final trip = args.replay.definition;
  final heading = resultHeading(content, trip);
  if (heading == null) return null;
  final flags = result.starFlags;
  return ResultSummary(
    heading: heading,
    stars: result.stars,
    starRows: [
      StarRow(StarCondition.reached, earned: flags.reached),
      StarRow(StarCondition.noFights, earned: flags.noFights),
      StarRow(StarCondition.noMistakes, earned: flags.noMistakes),
    ],
    breakdown: Breakdown(
      faresPiasters: result.faresCollectedPiasters,
      tipsPiasters: result.tipsPiasters,
      overpaidPiasters: result.overpaidPiasters,
      fights: result.fights,
    ),
    mistakeLines: _mistakeLines(result, trip),
    summary: _summaryOf(result),
    payJenehat: payOf(
      result.earningsJenehat,
      lastResult: lastResult,
      startTxn: args.startTxn,
    ),
    firstThreeStars: result.stars == 3 && args.bestStarsBefore < 3,
  );
}

List<MistakeLine> _mistakeLines(TripResult result, TripDefinition trip) => [
  for (final mistake in result.mistakes)
    () {
      final speaker = speakerOf(trip, mistake.passengerId);
      return PassengerMistake(
        passengerId: mistake.passengerId,
        look: speaker.look,
        labelKey: speaker.labelKey,
        feminine: speaker.look.feminine,
        kind: mistake.kind,
        amountPiasters: mistake.amountPiasters,
      );
    }(),
  if (result.fights > 0) CountLine(CountKind.fights, result.fights),
  if (result.missedStops > 0)
    CountLine(CountKind.missedStops, result.missedStops),
  if (result.lostFares > 0) CountLine(CountKind.lostFares, result.lostFares),
];

MistakesSummary? _summaryOf(TripResult result) {
  if (result.fights > 0) {
    return MistakesSummary(count: result.fights, family: SummaryFamily.fights);
  }
  if (result.mistakes.isNotEmpty) {
    return MistakesSummary(
      count: result.mistakes.length,
      family: SummaryFamily.mistakes,
    );
  }
  final losses = result.missedStops + result.lostFares;
  if (losses == 0) return null;
  return MistakesSummary(count: losses, family: SummaryFamily.losses);
}
