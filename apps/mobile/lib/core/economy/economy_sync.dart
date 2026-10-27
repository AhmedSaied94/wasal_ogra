// The economy's sync-only calls (specs/011-m06-identity-sync,
// contracts/sync.md "`EconomySync`", research R20). `EconomyService`
// implements it beside `Economy`, and every call runs on the service's
// serial queue, so it never interleaves with a player's request (FR-022).
// Only `lib/core/sync/` and `lib/core/account/` read `economySyncProvider`:
// `economy_sync_access_test.dart` keeps screens out.
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/sync/domain/wire/sync_answer.dart';

export 'package:wassal/core/sync/domain/wire/sync_answer.dart';

abstract interface class EconomySync {
  /// The base: its server state version (null before any), and its player
  /// (null before any). Synchronous after startup.
  ({int? stateVersion, String? playerId}) get baseInfo;

  int get pendingCount;

  /// A value after every change.
  Stream<int> get pendingCounts;

  /// The oldest pending operations, in `seq` order.
  Future<List<LedgerOp>> pendingOps({int limit = 100});

  /// The highest `seq` with an answer (accepted or rejected); 0 when none.
  Future<int> highestAnsweredSeq();

  /// Whether an operation of [type] is pending: the comeback gift's guard
  /// (research R16).
  Future<bool> hasPending(OpType type);

  /// One answer, in one transaction (research R11): marks the results,
  /// rebases on the answer's wallet unless [SyncAnswer.stateStale], folds
  /// what is still pending. Returns what the fold left out among the
  /// accepted operations (the divergence check) and the view before and
  /// after.
  Future<AnswerApplied> applyAnswer(
    SyncAnswer answer, {
    required List<LedgerOp> batch,
    required String playerId,
  });

  /// The full state, for the same player or for operations recorded before
  /// any account (research R12).
  Future<void> replaceFromServer(
    EconomyState snapshot, {
    required String playerId,
    required int stateVersion,
  });

  /// Another player's state (research R7): pending operations become
  /// `rejected(account_changed)`. Returns how many.
  Future<int> adoptAccount(
    EconomyState snapshot, {
    required String playerId,
    required int stateVersion,
  });

  /// A local rejection (research R13): `validation_error`,
  /// `payload_too_large`.
  Future<void> setAside(Map<TxnId, String> reasons);

  /// The comeback gift (research R16): fuel to the maximum and one
  /// `change_bag`. Guarded by `ComebackGift`.
  Future<OpOutcome> grantComebackGift(TxnId id);

  /// Anchors trusted time on the server's, behind every request already
  /// queued, so a new anchor never lands between a request's validation and
  /// its commit (research R20).
  Future<void> anchorOnServer(
    int serverTimeMs, {
    required int elapsedAtResponseMs,
  });
}

/// What applying one answer did.
final class AnswerApplied {
  const AnswerApplied({
    required this.leftOutAccepted,
    required this.before,
    required this.after,
  });

  /// Operations the server accepted that the rebase's fold left out: the
  /// base can't match the server, so the full state follows.
  final List<TxnId> leftOutAccepted;
  final EconomyView before;
  final EconomyView after;
}
