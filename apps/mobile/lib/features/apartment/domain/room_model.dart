// The rooms view's model (specs/015-m10-apartment-story, data-model
// "Apartment", contracts/apartment.md "The rooms view"): the current room,
// its pieces by order, its tabs and what the strip says. Pure; the styles
// come from `variantOf`, as `PlayerProgress` holds none.
import 'package:content_models/content_models.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/core/progress/domain/requests.dart';
import 'package:wassal/core/progress/domain/story.dart';
import 'package:wassal/core/progress/domain/unlocks.dart';
import 'package:wassal/features/home/domain/savings_target.dart'
    show Amount, nextPiece;

/// A room's tab: selectable when its chapter is unlocked, locked otherwise.
sealed class RoomTab {
  const RoomTab();

  /// The room it names.
  RoomId get roomId;
}

final class SelectableTab extends RoomTab {
  const SelectableTab(this.room);

  final Room room;

  @override
  RoomId get roomId => room.roomId;
}

/// A room the pack may lack, named by ARB (`roomTeaserName`).
final class LockedTab extends RoomTab {
  const LockedTab(this.roomId);

  @override
  final RoomId roomId;
}

/// A piece in the grid, by `order`.
sealed class PieceCell {
  const PieceCell(this.item);

  final Item item;

  /// The style an owned piece shows: its own, else the first (research R10).
  String? get variantId => null;
}

final class OwnedCell extends PieceCell {
  const OwnedCell(super.item, this.variantId);

  @override
  final String? variantId;
}

/// The first unowned piece: Home's `nextPiece`, with what the grid says.
final class NextTargetCell extends PieceCell {
  const NextTargetCell(
    super.item, {
    required this.price,
    required this.shortfall,
    required this.jenehat,
  });

  final int price;
  final int shortfall;
  final int jenehat;

  Amount get progress => Amount(have: jenehat, of: price);

  bool get affordable => shortfall == 0;
}

final class MissingCell extends PieceCell {
  const MissingCell(super.item, this.price);

  final int price;
}

/// What the rooms view draws (data-model "Apartment").
final class RoomModel {
  const RoomModel({
    required this.chapter,
    required this.room,
    required this.tabs,
    required this.pieces,
    required this.owned,
    required this.total,
    required this.requestCount,
    required this.pendingTotal,
    this.goalScene,
    this.goalSceneState,
  });

  final Chapter chapter;
  final Room room;
  final List<RoomTab> tabs;
  final List<PieceCell> pieces;
  final int owned;
  final int total;
  final int requestCount;
  final int pendingTotal;

  /// The scene the room's completion plays, and whether it waits.
  final Scene? goalScene;
  final SceneState? goalSceneState;

  bool get complete => total > 0 && owned == total;

  @override
  bool operator ==(Object other) =>
      other is RoomModel &&
      other.chapter.chapterId == chapter.chapterId &&
      other.room.roomId == room.roomId &&
      other.owned == owned &&
      other.total == total &&
      other.requestCount == requestCount &&
      other.pendingTotal == pendingTotal &&
      other.goalScene?.sceneId == goalScene?.sceneId &&
      other.goalSceneState == goalSceneState;

  @override
  int get hashCode => Object.hash(
    chapter.chapterId,
    room.roomId,
    owned,
    total,
    requestCount,
    pendingTotal,
    goalScene?.sceneId,
    goalSceneState,
  );
}

/// The room the tab shows while [chapter] is current: the room of the last
/// chapter up to it that names one. Completing a room moves the story on to
/// the next chapter, and the room stays on screen with its goal scene.
///
/// Null when no chapter up to [chapter] names a room, or the pack has none.
RoomModel? roomModel(
  ContentSource c,
  PlayerProgress p,
  Chapter chapter, {
  required int jenehat,
  required String? Function(String itemId) variantOf,
  required Set<String> requestsClaimed,
  required Map<String, Set<String>> scenesSeen,
  required int pendingTotal,
}) {
  final current = _roomOf(c, chapter);
  if (current == null) return null;
  final (roomChapter, room) = current;

  final tabs = [
    // By the glossary's order (salon, kitchen, bedroom), including the
    // rooms the pack lacks: they lock, with their ARB names.
    for (final id in RoomId.values)
      if (c.room(id) case final each?)
        if (chapterUnlocked(c, p, each.chapterId))
          SelectableTab(each)
        else
          LockedTab(id)
      else
        LockedTab(id),
  ];
  final items = [...c.itemsOf(room.roomId)]
    ..sort((a, b) => a.order.compareTo(b.order));
  final next = nextPiece(c, p, room.roomId);
  final pieces = <PieceCell>[
    for (final item in items)
      if (p.owns(SkuKind.item, item.itemId))
        OwnedCell(item, _styleOf(item, variantOf(item.itemId)))
      else if (next != null && next.$1.itemId == item.itemId)
        NextTargetCell(
          item,
          price: next.$2,
          shortfall: next.$2 - jenehat < 0 ? 0 : next.$2 - jenehat,
          jenehat: jenehat,
        )
      else
        MissingCell(item, _price(c, item)),
  ];
  final goalScene = goalSceneOf(roomChapter);
  return RoomModel(
    chapter: roomChapter,
    room: room,
    tabs: tabs,
    pieces: pieces,
    owned: pieces.whereType<OwnedCell>().length,
    total: pieces.length,
    requestCount: _requestCount(c, p, variantOf, requestsClaimed),
    pendingTotal: pendingTotal,
    goalScene: goalScene,
    goalSceneState: goalScene == null
        ? null
        : sceneState(c, p, scenesSeen, roomChapter, goalScene),
  );
}

/// [roomId]'s own model, whichever chapter is current: the room of the
/// chapter that names it. RoomDone draws the room just completed even when
/// that purchase moved the story on to a chapter with a room of its own, which
/// [roomModel] would then show instead. Null when the pack lacks the room or
/// its chapter.
RoomModel? roomModelOfRoom(
  ContentSource c,
  PlayerProgress p,
  RoomId roomId, {
  required int jenehat,
  required String? Function(String itemId) variantOf,
  required Set<String> requestsClaimed,
  required Map<String, Set<String>> scenesSeen,
  required int pendingTotal,
}) {
  final room = c.room(roomId);
  final chapter = room == null ? null : c.chapter(room.chapterId);
  if (chapter == null) return null;
  return roomModel(
    c,
    p,
    chapter,
    jenehat: jenehat,
    variantOf: variantOf,
    requestsClaimed: requestsClaimed,
    scenesSeen: scenesSeen,
    pendingTotal: pendingTotal,
  );
}

/// The last chapter at or before [chapter] that names a room, with it.
(Chapter, Room)? _roomOf(ContentSource c, Chapter chapter) {
  (Chapter, Room)? found;
  for (final each in chaptersInOrder(c)) {
    if (each.order > chapter.order) break;
    final id = each.goal.roomId;
    if (id == null) continue;
    final room = c.room(id);
    if (room != null) found = (each, room);
  }
  return found;
}

/// [item]'s stored style, or its first: a style the pack dropped still
/// draws (research R10).
String? _styleOf(Item item, String? variantId) {
  if (variantId == null) {
    return item.variants.isEmpty ? null : item.variants.first.variantId;
  }
  for (final variant in item.variants) {
    if (variant.variantId == variantId) return variantId;
  }
  return item.variants.isEmpty ? null : item.variants.first.variantId;
}

int _requestCount(
  ContentSource c,
  PlayerProgress p,
  String? Function(String itemId) variantOf,
  Set<String> requestsClaimed,
) => [
  for (final (_, state) in requestStates(c, p, variantOf, requestsClaimed))
    if (state == RequestState.open || state == RequestState.done) state,
].length;

int _price(ContentSource c, Item item) =>
    switch (c.price(SkuKind.item, item.itemId)) {
      CatalogPrice(currency: Currency.jenehat, :final amount) => amount,
      _ => 0,
    };
