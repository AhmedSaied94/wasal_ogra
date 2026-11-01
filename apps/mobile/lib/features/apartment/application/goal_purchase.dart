// Buying the chapter goal from the apartment (specs/015-m10-apartment-story,
// contracts/apartment.md "GoalPurchase", research R8): rules first, then one
// request id held per intent, as M09's `VehiclePurchase`. Offline, it applies
// at once and M06 syncs it later.
import 'package:content_models/content_models.dart';
import 'package:wassal/core/economy/domain/wire.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/core/progress/domain/unlocks.dart';
import 'package:wassal/core/content/domain/content_source.dart';

/// What a goal purchase did.
sealed class GoalPurchaseResult {
  const GoalPurchaseResult();
}

/// The rules refused it: nothing was sent.
final class GoalNotAllowed extends GoalPurchaseResult {
  const GoalNotAllowed();
}

final class GoalBought extends GoalPurchaseResult {
  const GoalBought();
}

/// The server refused it (`insufficient_funds`, `already_owned`, …).
final class GoalRefused extends GoalPurchaseResult {
  const GoalRefused(this.code);

  final EconomyRefusal code;
}

/// The write failed: the held id stays for the next tap.
final class GoalWriteFailed extends GoalPurchaseResult {
  const GoalWriteFailed();
}

final class GoalPurchase {
  GoalPurchase(this._economy);

  final Economy _economy;
  TxnId? _id;
  bool _busy = false;

  /// A call is in flight.
  bool get busy => _busy;

  /// Buys [chapter]'s goal. The caller passes what the screen shows, so a
  /// stale tap after a sync is judged on the rules, never on the old view.
  Future<GoalPurchaseResult> buy(
    ContentSource content,
    PlayerProgress progress,
    Chapter chapter,
  ) async {
    if (_busy) return const GoalNotAllowed();
    final purchase = chapter.goal.kind == GoalKind.purchase;
    final owned = progress.owns(
      SkuKind.chapter,
      chapterWire[chapter.chapterId]!,
    );
    if (!purchase ||
        owned ||
        !chapterUnlocked(content, progress, chapter.chapterId)) {
      return const GoalNotAllowed();
    }
    _busy = true;
    try {
      final id = _id ??= _economy.newRequestId();
      final outcome = await _economy.buy(
        id,
        kind: SkuKind.chapter,
        skuId: chapterWire[chapter.chapterId]!,
      );
      switch (outcome) {
        case OpApplied():
          _id = null;
          return const GoalBought();
        case OpRefused(:final code):
          // Short of money is the same intent, a retry after saving; any
          // other refusal is final.
          if (code != EconomyRefusal.insufficientFunds) _id = null;
          return GoalRefused(code);
        case OpWriteFailed():
          return const GoalWriteFailed();
      }
    } finally {
      _busy = false;
    }
  }
}
