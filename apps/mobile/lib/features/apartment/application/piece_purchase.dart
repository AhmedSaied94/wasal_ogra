// Buying a piece of the room (specs/015-m10-apartment-story, contracts/
// apartment.md "The piece sheet", T058): rules first, one held request id,
// and whether this purchase completed the room or the chapter (a sync or a
// restore that completed them never counts).
import 'package:content_models/content_models.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/progress/application/player_progress_provider.dart'
    show playerProgressOf;
import 'package:wassal/core/progress/domain/player_progress.dart' as progress;
import 'package:wassal/core/progress/domain/unlocks.dart';

/// What a piece's purchase did.
final class PiecePurchaseResult {
  const PiecePurchaseResult({
    required this.outcome,
    required this.roomCompleted,
    required this.chapterCompleted,
  });

  /// Null when the rules refused it: nothing was sent.
  final OpOutcome? outcome;

  /// This purchase completed the room, and the chapter with it.
  final bool roomCompleted;
  final bool chapterCompleted;
}

final class PiecePurchase {
  PiecePurchase(this._economy, this._content);

  final Economy _economy;
  final ContentSource _content;
  TxnId? _id;
  bool _busy = false;

  bool get busy => _busy;

  /// Buys [item] in [variantId] for [before]. The rules are re-checked, so a
  /// stale tap after a sync spends nothing.
  Future<PiecePurchaseResult> buy(
    Item item,
    String variantId, {
    required progress.PlayerProgress before,
  }) async {
    PiecePurchaseResult refused() => const PiecePurchaseResult(
      outcome: null,
      roomCompleted: false,
      chapterCompleted: false,
    );
    if (_busy ||
        before.owns(SkuKind.item, item.itemId) ||
        !itemPurchasable(_content, before, item.itemId)) {
      return refused();
    }
    _busy = true;
    try {
      final id = _id ??= _economy.newRequestId();
      final outcome = await _economy.buy(
        id,
        kind: SkuKind.item,
        skuId: item.itemId,
        variantId: variantId,
      );
      switch (outcome) {
        case OpApplied(:final view):
          _id = null;
          final after = playerProgressOf(view, _content);
          final roomWas = roomComplete(_content, before, item.roomId);
          final chapterId = _content.room(item.roomId)?.chapterId;
          return PiecePurchaseResult(
            outcome: outcome,
            roomCompleted:
                !roomWas && roomComplete(_content, after, item.roomId),
            chapterCompleted:
                chapterId != null &&
                !chapterComplete(_content, before, chapterId) &&
                chapterComplete(_content, after, chapterId),
          );
        case OpRefused(:final code):
          if (code != EconomyRefusal.insufficientFunds) _id = null;
          return PiecePurchaseResult(
            outcome: outcome,
            roomCompleted: false,
            chapterCompleted: false,
          );
        case OpWriteFailed():
          return PiecePurchaseResult(
            outcome: outcome,
            roomCompleted: false,
            chapterCompleted: false,
          );
      }
    } finally {
      _busy = false;
    }
  }
}
