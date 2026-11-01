// The bride's family's requests, as the sheet lists them
// (specs/015-m10-apartment-story, contracts/apartment.md "Family requests",
// data-model.md "Family request"). Pure.
//
// The states follow the server's rule exactly (B03 R9): a claim the phone
// offers is never refused as not eligible. `variantOf` is
// `EconomyView.variantOf`, because `PlayerProgress` holds what is owned but
// not its style.
import 'package:content_models/content_models.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/core/progress/domain/unlocks.dart';

enum RequestState { locked, open, done, missed, claimed }

/// [request]'s state: locked until its room's chapter unlocks; claimed once
/// taken; done when the piece is owned in the style it names; missed when
/// it's owned in another; open otherwise.
RequestState requestState(
  ContentSource c,
  PlayerProgress p,
  FamilyRequest request,
  String? Function(String itemId) variantOf,
  Set<String> requestsClaimed,
) {
  if (requestsClaimed.contains(request.requestId)) return RequestState.claimed;
  final room = c.room(request.roomId);
  if (room == null || !chapterUnlocked(c, p, room.chapterId)) {
    return RequestState.locked;
  }
  if (!p.owns(SkuKind.item, request.itemId)) return RequestState.open;
  final wanted = request.variantId;
  if (wanted == null || variantOf(request.itemId) == wanted) {
    return RequestState.done;
  }
  return RequestState.missed;
}

/// Every request with its state, the done ones first, then the rooms' and
/// the items' order.
List<(FamilyRequest, RequestState)> requestStates(
  ContentSource c,
  PlayerProgress p,
  String? Function(String itemId) variantOf,
  Set<String> requestsClaimed,
) {
  final rows = [
    for (final request in c.familyRequests)
      (request, requestState(c, p, request, variantOf, requestsClaimed)),
  ];
  int roomOrder(FamilyRequest r) => c.room(r.roomId)?.order ?? 1 << 30;
  int itemOrder(FamilyRequest r) => c.item(r.itemId)?.order ?? 1 << 30;
  rows.sort((a, b) {
    final byState = _rank(a.$2).compareTo(_rank(b.$2));
    if (byState != 0) return byState;
    final byRoom = roomOrder(a.$1).compareTo(roomOrder(b.$1));
    if (byRoom != 0) return byRoom;
    final byItem = itemOrder(a.$1).compareTo(itemOrder(b.$1));
    return byItem != 0 ? byItem : a.$1.requestId.compareTo(b.$1.requestId);
  });
  return rows;
}

/// The «الطلبات» badge's count: open plus done (HANDOFF §9.1 #8).
int openRequestCount(
  ContentSource c,
  PlayerProgress p,
  String? Function(String itemId) variantOf,
  Set<String> requestsClaimed,
) {
  var count = 0;
  for (final (_, state) in requestStates(c, p, variantOf, requestsClaimed)) {
    if (state == RequestState.open || state == RequestState.done) count++;
  }
  return count;
}

int _rank(RequestState state) => switch (state) {
  RequestState.done => 0,
  RequestState.claimed => 1,
  RequestState.open => 2,
  RequestState.locked => 3,
  RequestState.missed => 4,
};
