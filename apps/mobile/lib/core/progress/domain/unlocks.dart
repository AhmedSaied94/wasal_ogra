// The unlock and completion rules on the phone (specs/013-m08-home-result,
// contracts/progress-rules.md, research R2): a port of
// backend/apps/progress/services/unlocks.py, with its names, argument order
// and edge cases. When that file changes, this one changes in the same PR,
// and so does test/core/progress/unlocks_test.dart, which ports its tests.
//
// Each rule is permissive where a mistake could only let a player do
// something harmless, and strict where it protects value: a room with no
// items, or a line with no regular trips, is never complete. The server
// still decides; the phone checks first so it never offers a start the
// server would refuse as `not_unlocked`.
import 'package:content_models/content_models.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/economy/domain/wire.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';

/// `vehicle_owned`: a starter, or owned.
bool vehicleOwned(ContentSource c, PlayerProgress p, VehicleId vehicleId) {
  final vehicle = c.vehicle(vehicleId);
  if (vehicle == null) return false;
  return vehicle.starter || p.owns(SkuKind.vehicle, vehicleWire[vehicleId]!);
}

/// `line_complete`: every regular trip of the line has a star. A line
/// without one never is.
bool lineComplete(ContentSource c, PlayerProgress p, LineId lineId) {
  if (c.line(lineId) == null) return false;
  final regular = [
    for (final trip in c.tripsOf(lineId))
      if (trip.kind == TripKind.regular) trip.tripId,
  ];
  return regular.isNotEmpty && regular.every(p.finished);
}

/// `line_unlocked`: at start, with its vehicle, or once another line is
/// complete.
bool lineUnlocked(ContentSource c, PlayerProgress p, LineId lineId) {
  final unlock = c.line(lineId)?.unlock;
  if (unlock == null) return false;
  return switch (unlock.kind) {
    UnlockKind.start => true,
    UnlockKind.vehicle => switch (unlock.vehicleId) {
      final vehicle? => vehicleOwned(c, p, vehicle),
      null => false,
    },
    UnlockKind.lineComplete => switch (unlock.lineId) {
      final line? => lineComplete(c, p, line),
      null => false,
    },
  };
}

/// `trip_unlocked`: a story trip a chapter names needs only that chapter
/// unlocked. Any other needs its line unlocked, its vehicle owned, and the
/// regular trip before it in the line at a star or more (the first has
/// none).
bool tripUnlocked(ContentSource c, PlayerProgress p, String tripId) {
  final trip = c.trip(tripId);
  if (trip == null) return false;
  if (trip.kind == TripKind.story) {
    if (_chapterOfStoryTrip(c, tripId) case final chapter?) {
      return chapterUnlocked(c, p, chapter.chapterId);
    }
  }
  if (!lineUnlocked(c, p, trip.lineId)) return false;
  if (!vehicleOwned(c, p, trip.vehicleId)) return false;
  final previous = _previousRegular(c, trip.lineId, tripId);
  return previous == null || p.finished(previous);
}

/// `chapter_unlocked`: the first chapter always; chapter n once chapter n−1
/// is complete.
bool chapterUnlocked(ContentSource c, PlayerProgress p, ChapterId chapterId) {
  final order = chaptersInOrder(c);
  final index = order.indexWhere((ch) => ch.chapterId == chapterId);
  if (index < 0) return false;
  return index == 0 || chapterComplete(c, p, order[index - 1].chapterId);
}

/// `chapter_complete`: its goal and every earlier one met, so chapters
/// complete in order.
bool chapterComplete(ContentSource c, PlayerProgress p, ChapterId chapterId) {
  final order = chaptersInOrder(c);
  final index = order.indexWhere((ch) => ch.chapterId == chapterId);
  if (index < 0) return false;
  return order.take(index + 1).every((ch) => _goalMet(c, p, ch));
}

/// `room_complete`: every item of the room owned. A room without items
/// never is.
bool roomComplete(ContentSource c, PlayerProgress p, RoomId roomId) {
  if (c.room(roomId) == null) return false;
  final items = c.itemsOf(roomId);
  return items.isNotEmpty &&
      items.every((item) => p.owns(SkuKind.item, item.itemId));
}

/// `item_purchasable`: its room's chapter is unlocked.
bool itemPurchasable(ContentSource c, PlayerProgress p, String itemId) {
  final item = c.item(itemId);
  if (item == null) return false;
  final room = c.room(item.roomId);
  return room != null && chapterUnlocked(c, p, room.chapterId);
}

/// `current_chapter` (B03 research R16): the highest unlocked chapter that
/// isn't complete, else the last complete one, else the first. Null for a
/// pack with none.
Chapter? currentChapter(ContentSource c, PlayerProgress p) {
  final order = chaptersInOrder(c);
  if (order.isEmpty) return null;
  Chapter? lastOpen;
  Chapter? lastComplete;
  for (final chapter in order) {
    final complete = chapterComplete(c, p, chapter.chapterId);
    if (complete) {
      lastComplete = chapter;
    } else if (chapterUnlocked(c, p, chapter.chapterId)) {
      lastOpen = chapter;
    }
  }
  return lastOpen ?? lastComplete ?? order.first;
}

/// The chapter the apartment opens in (research R4, HANDOFF §9.3 #2): the
/// first chapter, by order, whose goal is a room. Null when none is. Phone
/// only, and the one place M10 changes to settle it.
Chapter? apartmentOpens(ContentSource c) {
  for (final chapter in chaptersInOrder(c)) {
    if (chapter.goal.kind == GoalKind.completeRoom) return chapter;
  }
  return null;
}

/// Chapters by `(order, chapter_id)`, the server's order.
List<Chapter> chaptersInOrder(ContentSource c) => [...c.chapters]
  ..sort((a, b) {
    final byOrder = a.order.compareTo(b.order);
    return byOrder != 0
        ? byOrder
        : chapterWire[a.chapterId]!.compareTo(chapterWire[b.chapterId]!);
  });

bool _goalMet(ContentSource c, PlayerProgress p, Chapter chapter) {
  final goal = chapter.goal;
  return switch (goal.kind) {
    GoalKind.completeLine => switch (goal.lineId) {
      final line? => lineComplete(c, p, line),
      null => false,
    },
    GoalKind.ownVehicle => switch (goal.vehicleId) {
      final vehicle? => vehicleOwned(c, p, vehicle),
      null => false,
    },
    GoalKind.purchase => p.owns(
      SkuKind.chapter,
      chapterWire[chapter.chapterId]!,
    ),
    GoalKind.completeRoom => switch (goal.roomId) {
      final room? => roomComplete(c, p, room),
      null => false,
    },
  };
}

Chapter? _chapterOfStoryTrip(ContentSource c, String tripId) {
  for (final chapter in chaptersInOrder(c)) {
    if (chapter.storyTripId == tripId) return chapter;
  }
  return null;
}

String? _previousRegular(ContentSource c, LineId lineId, String tripId) {
  final trips = c.tripsOf(lineId);
  final index = trips.indexWhere((t) => t.tripId == tripId);
  if (index < 0) return null;
  for (var i = index - 1; i >= 0; i--) {
    if (trips[i].kind == TripKind.regular) return trips[i].tripId;
  }
  return null;
}
