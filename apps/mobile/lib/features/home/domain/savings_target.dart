// What the player is saving for (specs/013-m08-home-result, research R4,
// data-model `SavingsTarget`): the current chapter's goal before the
// apartment opens, then the next piece of the apartment. Home's savings
// card and the result's apartment card both show it.
import 'package:content_models/content_models.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/economy/domain/wire.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/core/progress/domain/unlocks.dart';

/// How far the player is towards a target.
sealed class SavingsProgress {
  const SavingsProgress();

  /// The bar's fill, 0 to 1.
  double get fraction;
}

/// JENEHAT saved of a price.
final class Amount extends SavingsProgress {
  const Amount({required this.have, required this.of});

  final int have;
  final int of;

  @override
  double get fraction => of <= 0 ? 1 : (have / of).clamp(0, 1).toDouble();

  @override
  bool operator ==(Object other) =>
      other is Amount && other.have == have && other.of == of;

  @override
  int get hashCode => Object.hash(have, of);

  @override
  String toString() => 'Amount($have/$of)';
}

/// Trips finished of a line's regular trips.
final class Count extends SavingsProgress {
  const Count({required this.done, required this.of});

  final int done;
  final int of;

  @override
  double get fraction => of <= 0 ? 0 : (done / of).clamp(0, 1).toDouble();

  @override
  bool operator ==(Object other) =>
      other is Count && other.done == done && other.of == of;

  @override
  int get hashCode => Object.hash(done, of);

  @override
  String toString() => 'Count($done/$of)';
}

sealed class SavingsTarget {
  const SavingsTarget();

  /// JENEHAT covers the price: «جاهزة للشرا!», the apartment tab's dot.
  /// A line goal never is.
  bool get affordable;
}

/// Before the apartment opens: the current chapter's goal.
final class ChapterGoalTarget extends SavingsTarget {
  const ChapterGoalTarget({
    required this.chapter,
    required this.goalKind,
    required this.subjectName,
    required this.progress,
    this.opensInChapter,
  });

  final Chapter chapter;
  final GoalKind goalKind;

  /// The line, vehicle, chapter or room the goal names, as the content
  /// names it.
  final String subjectName;

  /// The chapter the apartment opens in, by order; null when none does.
  final int? opensInChapter;
  final SavingsProgress progress;

  @override
  bool get affordable => switch (progress) {
    Amount(:final have, of: final price) => have >= price,
    Count() => false,
  };

  @override
  bool operator ==(Object other) =>
      other is ChapterGoalTarget &&
      other.chapter.chapterId == chapter.chapterId &&
      other.goalKind == goalKind &&
      other.subjectName == subjectName &&
      other.opensInChapter == opensInChapter &&
      other.progress == progress;

  @override
  int get hashCode => Object.hash(
    chapter.chapterId,
    goalKind,
    subjectName,
    opensInChapter,
    progress,
  );

  @override
  String toString() =>
      'ChapterGoalTarget(${chapter.chapterId.name}, ${goalKind.name}, '
      '$subjectName, $progress)';
}

/// From the apartment's chapter on: the next piece to buy.
final class ApartmentPieceTarget extends SavingsTarget {
  const ApartmentPieceTarget({
    required this.chapter,
    required this.itemId,
    required this.itemName,
    required this.priceJenehat,
    required this.jenehat,
  });

  final Chapter chapter;
  final String itemId;
  final String itemName;
  final int priceJenehat;

  /// The balance it was computed with.
  final int jenehat;

  Amount get progress => Amount(have: jenehat, of: priceJenehat);

  @override
  bool get affordable => jenehat >= priceJenehat;

  @override
  bool operator ==(Object other) =>
      other is ApartmentPieceTarget &&
      other.chapter.chapterId == chapter.chapterId &&
      other.itemId == itemId &&
      other.itemName == itemName &&
      other.priceJenehat == priceJenehat &&
      other.jenehat == jenehat;

  @override
  int get hashCode =>
      Object.hash(chapter.chapterId, itemId, itemName, priceJenehat, jenehat);

  @override
  String toString() =>
      'ApartmentPieceTarget(${chapter.chapterId.name}, $itemId, '
      '$jenehat/$priceJenehat)';
}

/// The end of the available story: the last chapter is complete.
final class StoryEndTarget extends SavingsTarget {
  const StoryEndTarget(this.chapter);

  final Chapter chapter;

  @override
  bool get affordable => false;

  @override
  bool operator ==(Object other) =>
      other is StoryEndTarget && other.chapter.chapterId == chapter.chapterId;

  @override
  int get hashCode => Object.hash(StoryEndTarget, chapter.chapterId);

  @override
  String toString() => 'StoryEndTarget(${chapter.chapterId.name})';
}

/// A pack without chapters, or nothing left to save for.
final class NoTarget extends SavingsTarget {
  const NoTarget();

  @override
  bool get affordable => false;

  @override
  bool operator ==(Object other) => other is NoTarget;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'NoTarget()';
}

/// The target for a player with [jenehat] (research R4).
SavingsTarget savingsTarget(ContentSource c, PlayerProgress p, int jenehat) {
  final chapter = currentChapter(c, p);
  if (chapter == null) return const NoTarget();
  final order = chaptersInOrder(c);
  // The story's last chapter complete: there is nothing left to save for.
  if (order.last.chapterId == chapter.chapterId &&
      chapterComplete(c, p, chapter.chapterId)) {
    return StoryEndTarget(chapter);
  }
  final opens = apartmentOpens(c);
  final open = opens != null && chapter.order >= opens.order;
  if (open && chapter.goal.kind == GoalKind.completeRoom) {
    final room = chapter.goal.roomId;
    final piece = room == null ? null : nextPiece(c, p, room);
    if (piece == null) return const NoTarget();
    final (item, price) = piece;
    return ApartmentPieceTarget(
      chapter: chapter,
      itemId: item.itemId,
      itemName: item.name.arEg,
      priceJenehat: price,
      jenehat: jenehat,
    );
  }
  return _goalTarget(c, p, chapter, jenehat, opensIn: opens?.order) ??
      const NoTarget();
}

ChapterGoalTarget? _goalTarget(
  ContentSource c,
  PlayerProgress p,
  Chapter chapter,
  int jenehat, {
  required int? opensIn,
}) {
  final goal = chapter.goal;
  ChapterGoalTarget target(String name, SavingsProgress progress) =>
      ChapterGoalTarget(
        chapter: chapter,
        goalKind: goal.kind,
        subjectName: name,
        opensInChapter: opensIn,
        progress: progress,
      );
  Amount amount(int? price) => Amount(have: jenehat, of: price ?? 0);

  switch (goal.kind) {
    case GoalKind.completeLine:
      final line = goal.lineId == null ? null : c.line(goal.lineId!);
      if (line == null) return null;
      final regular = [
        for (final trip in c.tripsOf(line.lineId))
          if (trip.kind == TripKind.regular) trip.tripId,
      ];
      return target(
        line.name.arEg,
        Count(done: regular.where(p.finished).length, of: regular.length),
      );
    case GoalKind.ownVehicle:
      final vehicle = goal.vehicleId == null
          ? null
          : c.vehicle(goal.vehicleId!);
      if (vehicle == null) return null;
      final price = c.price(SkuKind.vehicle, vehicleWire[vehicle.vehicleId]!);
      return target(vehicle.name.arEg, amount(_jenehat(price)));
    case GoalKind.purchase:
      final price = c.price(SkuKind.chapter, chapterWire[chapter.chapterId]!);
      return target(chapter.title.arEg, amount(_jenehat(price)));
    case GoalKind.completeRoom:
      final room = goal.roomId == null ? null : c.room(goal.roomId!);
      if (room == null) return null;
      final piece = nextPiece(c, p, room.roomId);
      return target(room.name.arEg, amount(piece?.$2));
  }
}

/// The first unowned item of [room] by `order`, with its JENEHAT price
/// (M10's rooms view reuses it, so Home and the grid agree).
(Item, int)? nextPiece(ContentSource c, PlayerProgress p, RoomId room) {
  final items = [...c.itemsOf(room)]
    ..sort((a, b) => a.order.compareTo(b.order));
  for (final item in items) {
    if (p.owns(SkuKind.item, item.itemId)) continue;
    final price = _jenehat(c.price(SkuKind.item, item.itemId));
    if (price == null) continue;
    return (item, price);
  }
  return null;
}

/// [price] in JENEHAT; null for a missing price or another currency.
int? _jenehat(CatalogPrice? price) => switch (price) {
  CatalogPrice(currency: Currency.jenehat, :final amount) => amount,
  _ => null,
};
