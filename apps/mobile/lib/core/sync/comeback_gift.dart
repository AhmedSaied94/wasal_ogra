// The comeback gift's guard (specs/011-m06-identity-sync, contracts/
// sync.md "The comeback gift", research R16): a claim from the cached
// bootstrap's flag, once, and not again until a newer flag than the last
// claim and its answer. It works offline: the gift is a local operation,
// and the server decides it when the operation syncs.
import 'dart:async';

import 'package:wassal/core/account/domain/account_record.dart';
import 'package:wassal/core/account/drift_account_store.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/economy/economy_sync.dart';

abstract interface class ComebackGift {
  /// The cached flag, no claim pending, and the flag newer than the last
  /// claim and its answer.
  bool get claimable;

  /// A value when [claimable] changes.
  Stream<bool> get claimables;

  /// `OpRefused(notEligible)` when not [claimable].
  Future<OpOutcome> claim(TxnId id);
}

final class LocalComebackGift implements ComebackGift {
  LocalComebackGift._(
    this._store,
    this._economy,
    this._nowMs, {
    required this._pending,
  }) : _last = false;

  /// Reads whether a claim is pending, then follows [infos] (each
  /// bootstrap written) and the economy's pending count.
  static Future<LocalComebackGift> open({
    required DriftAccountStore store,
    required EconomySync economy,
    required Stream<ServerInfo> infos,
    required int Function() nowMs,
  }) async {
    final gift = LocalComebackGift._(
      store,
      economy,
      nowMs,
      pending: await economy.hasPending(OpType.comebackGift),
    );
    gift
      .._last = gift.claimable
      .._subscriptions = [
        infos.listen((_) => gift._emit()),
        economy.pendingCounts.listen((_) => unawaited(gift._checkAnswered())),
      ];
    return gift;
  }

  final DriftAccountStore _store;
  final EconomySync _economy;
  final int Function() _nowMs;
  final _claimables = StreamController<bool>.broadcast();
  List<StreamSubscription<Object?>> _subscriptions = const [];

  /// A claim's operation is pending.
  bool _pending;
  bool _last;

  @override
  bool get claimable {
    final info = _store.serverInfo;
    final received = info.receivedAtMs;
    if (!info.comebackClaimable || _pending || received == null) return false;
    for (final at in [info.comebackClaimedAtMs, info.comebackAnsweredAtMs]) {
      if (at != null && received <= at) return false;
    }
    return true;
  }

  @override
  Stream<bool> get claimables => _claimables.stream;

  @override
  Future<OpOutcome> claim(TxnId id) async {
    if (!claimable) return const OpRefused(EconomyRefusal.notEligible);
    // Held before the first await, so a second tap is refused.
    _pending = true;
    final OpOutcome outcome;
    try {
      await _store.markComebackClaimed(_nowMs());
      outcome = await _economy.grantComebackGift(id);
    } on Exception {
      // Not left held by a write that failed: the pending op decides.
      _pending = await _economy.hasPending(OpType.comebackGift);
      _emit();
      rethrow;
    }
    if (outcome is! OpApplied) {
      _pending = await _economy.hasPending(OpType.comebackGift);
    }
    _emit();
    return outcome;
  }

  /// The claim's operation was answered (accepted, rejected or dropped).
  Future<void> _checkAnswered() async {
    if (!_pending || await _economy.hasPending(OpType.comebackGift)) return;
    _pending = false;
    await _store.markComebackAnswered(_nowMs());
    _emit();
  }

  void _emit() {
    final now = claimable;
    if (now == _last || _claimables.isClosed) return;
    _last = now;
    _claimables.add(now);
  }

  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_claimables.close());
  }
}
