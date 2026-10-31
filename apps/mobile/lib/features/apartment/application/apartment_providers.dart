// The apartment tab's providers (specs/015-m10-apartment-story, contracts/
// apartment.md "The tab"): the view over the projection, the bar's remembered
// value and the goal purchase.
import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/progress/application/player_progress_provider.dart';
import 'package:wassal/core/progress/application/pending_rewards_provider.dart';
import 'package:wassal/features/apartment/application/goal_purchase.dart';
import 'package:wassal/features/apartment/application/piece_purchase.dart';
import 'package:wassal/features/apartment/application/request_claim.dart';
import 'package:wassal/features/apartment/domain/apartment_view.dart';
import 'package:wassal/features/apartment/domain/piece_sheet_model.dart'
    as sheet;
import 'package:wassal/features/apartment/domain/room_model.dart';

part 'apartment_providers.g.dart';

/// The BONAT the server hasn't paid yet, for the rooms header's chip.
int _pendingTotal(Ref ref) =>
    [for (final reward in ref.watch(pendingRewardsProvider)) reward.bonat]
        .fold(0, (sum, bonat) => sum + bonat);

/// What the tab draws now, rebuilt when the pack, the progress or the view
/// changes.
@Riverpod(keepAlive: true)
ApartmentView apartmentView(Ref ref) {
  final view = ref.watch(economyViewProvider);
  return apartmentViewOf(
    ref.watch(contentSourceProvider),
    ref.watch(playerProgressProvider),
    jenehat: view.jenehat,
    variantOf: view.variantOf,
    requestsClaimed: view.requestsClaimed,
    scenesSeen: view.scenesSeen,
    pendingTotal: _pendingTotal(ref),
  );
}

/// The bar's last value per chapter, so it animates from where it was
/// (research R8). In memory: a relaunch draws the bar full.
@Riverpod(keepAlive: true)
class GoalBarSeen extends _$GoalBarSeen {
  @override
  Map<ChapterId, double> build() => const {};

  /// The value [chapter] was last drawn at, then stores [value].
  double take(ChapterId chapter, double value) {
    final seen = state[chapter] ?? 0;
    if (seen != value) state = {...state, chapter: value};
    return seen;
  }
}

/// The row the timeline's rail was last drawn to (the current chapter's, or
/// the last at the story's end), so it animates once per chapter change.
/// In memory: a relaunch animates it once.
@Riverpod(keepAlive: true)
class ChaptersRailSeen extends _$ChaptersRailSeen {
  @override
  int? build() => null;

  void take(int reach) => state = reach;
}

/// The one purchase object of the tab, so a double tap holds one request id.
@Riverpod(keepAlive: true)
GoalPurchase goalPurchase(Ref ref) =>
    GoalPurchase(ref.watch(economyProvider).requireValue);

/// The chosen style per piece, so the sheet and the room remember it
/// (research R10). In memory: a relaunch starts on the pack's first style.
@Riverpod(keepAlive: true)
class PieceStyleMemory extends _$PieceStyleMemory {
  @override
  Map<String, String> build() => const {};

  void choose(String itemId, String variantId) =>
      state = {...state, itemId: variantId};
}

/// The selected room tab. In memory.
@Riverpod(keepAlive: true)
class RoomTabId extends _$RoomTabId {
  @override
  RoomId? build() => null;

  set tab(RoomId? value) => state = value;
}

/// [roomId]'s own model (RoomDone's), not the current chapter's room: the one
/// that completes a room can move the story on to a room of its own.
final roomModelOfProvider = Provider.family<RoomModel?, RoomId>((
  Ref ref,
  RoomId roomId,
) {
  final view = ref.watch(economyViewProvider);
  return roomModelOfRoom(
    ref.watch(contentSourceProvider),
    ref.watch(playerProgressProvider),
    roomId,
    jenehat: view.jenehat,
    variantOf: view.variantOf,
    requestsClaimed: view.requestsClaimed,
    scenesSeen: view.scenesSeen,
    pendingTotal: _pendingTotal(ref),
  );
});

/// [itemId]'s sheet at the current balance, or null when it can't open.
final pieceSheetModelProvider = Provider.family<sheet.PieceSheetModel?, String>(
  (Ref ref, String itemId) {
    final view = ref.watch(economyViewProvider);
    return sheet.pieceSheetModel(
      ref.watch(contentSourceProvider),
      ref.watch(playerProgressProvider),
      itemId,
      jenehat: view.jenehat,
      variantOf: view.variantOf,
      requestsClaimed: view.requestsClaimed,
      styleMemory: ref.watch(pieceStyleMemoryProvider),
    );
  },
);

/// The one purchase object of the rooms view.
@Riverpod(keepAlive: true)
PiecePurchase piecePurchase(Ref ref) => PiecePurchase(
  ref.watch(economyProvider).requireValue,
  ref.watch(contentSourceProvider),
);

/// The one claim object of the requests sheet, so a double tap holds one
/// request id per request.
@Riverpod(keepAlive: true)
RequestClaim requestClaim(Ref ref) => RequestClaim(
  ref.watch(economyProvider).requireValue,
  ref.watch(contentSourceProvider),
);

/// The piece just bought, for the rooms view's drop-in and سلمى's bubble
/// (contracts/apartment.md "After a piece is bought", research R9).
typedef BoughtRecord = ({String itemId, String variantId});

/// Set by the piece sheet on `OpApplied`; cleared by the next tap or scroll on
/// the rooms view. In memory.
class BoughtPiece extends Notifier<BoughtRecord?> {
  @override
  BoughtRecord? build() => null;

  void bought(String itemId, String variantId) =>
      state = (itemId: itemId, variantId: variantId);

  void clear() => state = null;
}

final boughtPieceProvider = NotifierProvider<BoughtPiece, BoughtRecord?>(
  BoughtPiece.new,
);
