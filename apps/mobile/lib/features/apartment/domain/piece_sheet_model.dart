// The piece sheet's model (specs/015-m10-apartment-story, data-model
// "Apartment", contracts/apartment.md "The piece sheet"): the piece, its
// styles, the chosen one, سلمى's line, the price, the balance and the
// family's marks. Pure; the style comes through `variantOf`/the memory.
import 'package:content_models/content_models.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/content/domain/story_characters.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/core/progress/domain/requests.dart';
import 'package:wassal/core/progress/domain/unlocks.dart';

/// The sheet's contents for [itemId], or null when the pack has no such
/// piece or its room's chapter is locked (the router then leaves).
final class PieceSheetModel {
  const PieceSheetModel({
    required this.item,
    required this.room,
    required this.variants,
    required this.selected,
    required this.price,
    required this.jenehat,
    required this.requestMarks,
    required this.owned,
    this.salmaLine,
    this.askerToMiss,
  });

  final Item item;
  final Room room;
  final List<ItemVariant> variants;

  /// The style the sheet shows: the remembered one, else the first.
  final String? selected;

  /// The piece's price in JENEHAT (0 when the pack has none).
  final int price;

  /// The balance it was computed with.
  final int jenehat;

  /// A style an open request names, by `variantId`, with its asker's art
  /// name (`bride_mother`, …).
  final Map<String, String> requestMarks;

  /// Already owned: the sheet doesn't open (the router leaves).
  final bool owned;

  /// سلمى's line: the chosen style's, else the piece's.
  final String? salmaLine;

  /// The asker whose open request another style would miss, while the
  /// chosen style isn't theirs.
  final String? askerToMiss;

  bool get affordable => jenehat >= price;

  int get shortfall => price - jenehat < 0 ? 0 : price - jenehat;

  @override
  bool operator ==(Object other) =>
      other is PieceSheetModel &&
      other.item.itemId == item.itemId &&
      other.selected == selected &&
      other.price == price &&
      other.jenehat == jenehat &&
      other.owned == owned &&
      other.askerToMiss == askerToMiss;

  @override
  int get hashCode =>
      Object.hash(item.itemId, selected, price, jenehat, owned, askerToMiss);
}

/// [itemId]'s sheet at [jenehat], or null when it can't open.
PieceSheetModel? pieceSheetModel(
  ContentSource c,
  PlayerProgress p,
  String itemId, {
  required int jenehat,
  required String? Function(String itemId) variantOf,
  required Set<String> requestsClaimed,
  Map<String, String> styleMemory = const {},
}) {
  final item = c.item(itemId);
  if (item == null) return null;
  final room = c.room(item.roomId);
  if (room == null || !chapterUnlocked(c, p, room.chapterId)) return null;
  final owned = p.owns(SkuKind.item, item.itemId);
  final selected = _styleOf(
    item,
    styleMemory[itemId] ?? variantOf(item.itemId),
  );
  final chosen = item.variants
      .where((v) => v.variantId == selected)
      .firstOrNull;
  final marks = <String, String>{};
  String? askerToMiss;
  for (final (request, state) in requestStates(
    c,
    p,
    variantOf,
    requestsClaimed,
  )) {
    if (request.itemId != item.itemId || state != RequestState.open) continue;
    final wanted = request.variantId;
    if (wanted == null) continue;
    marks[wanted] = storyCharacterArt(request.character);
    if (wanted != selected) askerToMiss = storyCharacterArt(request.character);
  }
  return PieceSheetModel(
    item: item,
    room: room,
    variants: item.variants,
    selected: selected,
    price: switch (c.price(SkuKind.item, item.itemId)) {
      CatalogPrice(currency: Currency.jenehat, :final amount) => amount,
      _ => 0,
    },
    jenehat: jenehat,
    requestMarks: Map.unmodifiable(marks),
    owned: owned,
    salmaLine: chosen?.comment?.arEg ?? item.comment?.arEg,
    askerToMiss: askerToMiss,
  );
}

/// [variantId] when the pack has it, else the first style.
String? _styleOf(Item item, String? variantId) {
  if (variantId != null && item.variants.any((v) => v.variantId == variantId)) {
    return variantId;
  }
  return item.variants.isEmpty ? null : item.variants.first.variantId;
}
