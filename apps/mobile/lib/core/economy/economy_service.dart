// The one economy service (research R10, R11, R17): one writer, one
// transaction per operation, and a view that changes only after a commit.
// It is also the sync's way in (`EconomySync`, specs/011-m06-identity-sync
// research R20), on the same serial queue.
import 'dart:async';
import 'dart:math' show max;

import 'package:content_models/content_models.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:trip_engine/trip_engine.dart' show TripResult;
import 'package:wassal/core/config/config_source.dart';
import 'package:wassal/core/config/tunable.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/economy/domain/fold.dart';
import 'package:wassal/core/economy/domain/fuel.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/rules.dart';
import 'package:wassal/core/economy/drift_economy_store.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/economy/economy_sync.dart';
import 'package:wassal/core/economy/trusted_clock.dart';
import 'package:wassal/core/economy/txn_ids.dart';

final class EconomyService implements Economy, EconomySync {
  EconomyService._({
    required this._store,
    required this._clock,
    required this._content,
    required this._contentVersion,
    required this._tunables,
    required this._rules,
    required this._state,
    required ProjectionBase base,
    required this._pending,
    required this._nameRefused,
  }) : _base = (stateVersion: base.stateVersion, playerId: base.playerId);

  /// Reads the materialized tables (never the log, research R18) and arms
  /// the next-liter timer.
  static Future<EconomyService> open({
    required DriftEconomyStore store,
    required TrustedClock clock,
    required ContentSource Function() content,
    required int Function() contentVersion,
    required ConfigSource Function() tunables,
    Rules rules = const ProductionRules(),
  }) async {
    final stored = await store.load();
    return EconomyService._(
      store: store,
      clock: clock,
      content: content,
      contentVersion: contentVersion,
      tunables: tunables,
      rules: rules,
      state: stored.state,
      base: stored.base,
      pending: await store.pendingCount(),
      nameRefused: await store.nameRefused(),
    ).._rearm();
  }

  final DriftEconomyStore _store;
  final TrustedClock _clock;
  final ContentSource Function() _content;
  final int Function() _contentVersion;
  final ConfigSource Function() _tunables;
  final Rules _rules;
  EconomyState _state;
  ({int? stateVersion, String? playerId}) _base;
  int _pending;

  /// The view's `nameRefused`, read from the log after each change that can
  /// answer a name (M07 research R8).
  bool _nameRefused;

  final _views = StreamController<EconomyView>.broadcast();
  final _pendingCounts = StreamController<int>.broadcast();
  Future<void> _tail = Future.value();
  Timer? _timer;
  bool _foreground = true;
  bool _disposed = false;

  /// The state the view shows, for tests and the debug fold check.
  EconomyState get state => _state;

  @override
  EconomyView get view {
    final tunables = _tunables();
    return EconomyView(
      _state,
      fuelView(
        _state.fuel,
        _clock.nowMs(),
        max: tunables.read(Tunable.fuelMax),
        regenMs: regenMsOf(tunables.read(Tunable.fuelRegenMinutes)),
      ),
      nameRefused: _nameRefused,
    );
  }

  @override
  Stream<EconomyView> get views => _views.stream;

  @override
  TxnId newRequestId() => newTxnId(_clock.nowMs());

  @override
  Future<OpOutcome> startTrip(TxnId id, {required String tripId}) =>
      _submit(id, StartTripRequest(tripId));

  @override
  Future<OpOutcome> recordResult(
    TxnId id, {
    required TxnId start,
    required TripResult result,
  }) => _submit(id, RecordResultRequest(start: start, result: result));

  @override
  Future<OpOutcome> useBooster(TxnId id, {required BoosterId booster}) =>
      _submit(id, UseBoosterRequest(booster));

  @override
  Future<OpOutcome> buy(
    TxnId id, {
    required SkuKind kind,
    required String skuId,
    String? variantId,
  }) => _submit(id, BuyRequest(kind: kind, skuId: skuId, variantId: variantId));

  @override
  Future<OpOutcome> applyAdReward(TxnId id, {required AdPlacement placement}) =>
      _submit(id, AdRewardRequest(placement));

  @override
  Future<OpOutcome> setDisplayName(TxnId id, String name) =>
      _submit(id, SettingsUpdateRequest(name));

  @override
  Future<OpOutcome> grantTutorialGift(TxnId id) =>
      _submit(id, const TutorialGiftRequest());

  // The sync (EconomySync).

  @override
  ({int? stateVersion, String? playerId}) get baseInfo => _base;

  @override
  int get pendingCount => _pending;

  @override
  Stream<int> get pendingCounts => _pendingCounts.stream;

  @override
  Future<List<LedgerOp>> pendingOps({int limit = 100}) =>
      _serial(() => _store.pendingOps(limit));

  @override
  Future<int> highestAnsweredSeq() => _serial(_store.highestAnsweredSeq);

  @override
  Future<bool> hasPending(OpType type) =>
      _serial(() => _store.hasPending(type));

  @override
  Future<AnswerApplied> applyAnswer(
    SyncAnswer answer, {
    required List<LedgerOp> batch,
    required String playerId,
  }) => _serial(() async {
    final before = view;
    final inBatch = {for (final op in batch) op.op.txnId.value: op.op.txnId};
    final wallet = answer.wallet;
    final applied = await _store.applyAnswer(
      _fold,
      results: {
        // A result for an id this batch didn't send is ignored.
        for (final result in answer.results)
          ?inBatch[result.txnId]: result.reason,
      },
      batchMaxSeq: batch.fold(0, (seq, op) => max(seq, op.seq)),
      balances: answer.stateStale
          ? null
          : (
              jenehat: wallet.jenehat,
              bonat: wallet.bonat,
              fuel: wallet.fuelState,
            ),
      stateVersion: answer.stateVersion,
      playerId: playerId,
      takenAtMs: _clock.nowMs(),
    );
    _state = applied.fold.state;
    _base = (
      stateVersion: applied.base.stateVersion,
      playerId: applied.base.playerId,
    );
    await _recount();
    _changed();
    return AnswerApplied(
      leftOutAccepted: List.unmodifiable(applied.leftOutAccepted),
      before: before,
      after: view,
    );
  });

  @override
  Future<void> replaceFromServer(
    EconomyState snapshot, {
    required String playerId,
    required int stateVersion,
  }) => _takeServerState(
    snapshot,
    playerId: playerId,
    stateVersion: stateVersion,
    dropPending: false,
  );

  @override
  Future<int> adoptAccount(
    EconomyState snapshot, {
    required String playerId,
    required int stateVersion,
  }) => _takeServerState(
    snapshot,
    playerId: playerId,
    stateVersion: stateVersion,
    dropPending: true,
  );

  Future<int> _takeServerState(
    EconomyState snapshot, {
    required String playerId,
    required int stateVersion,
    required bool dropPending,
  }) => _serial(() async {
    final taken = await _store.takeServerState(
      _fold,
      snapshot: snapshot,
      stateVersion: stateVersion,
      playerId: playerId,
      takenAtMs: _clock.nowMs(),
      dropPending: dropPending,
    );
    _state = taken.fold.state;
    _base = (stateVersion: taken.base.stateVersion, playerId: playerId);
    await _recount();
    _changed();
    return taken.dropped;
  });

  @override
  Future<void> setAside(Map<TxnId, String> reasons) => _serial(() async {
    final rebuilt = await _store.rebuild(_fold, rejected: reasons);
    _state = rebuilt.fold.state;
    await _recount();
    _changed();
  });

  @override
  Future<OpOutcome> grantComebackGift(TxnId id) =>
      _submit(id, const ComebackGiftRequest());

  @override
  Future<void> anchorOnServer(
    int serverTimeMs, {
    required int elapsedAtResponseMs,
  }) => _serial(
    () => _saveAnchor(
      () => _clock.anchorOnServer(
        serverTimeMs,
        elapsedAtResponseMs: elapsedAtResponseMs,
      ),
    ),
  );

  /// Reads the pending count and the name's refusal again, after a change
  /// that answered some.
  Future<void> _recount() async {
    _pending = await _store.pendingCount();
    _nameRefused = await _store.nameRefused();
    _pendingChanged();
  }

  void _pendingChanged() {
    if (!_disposed) _pendingCounts.add(_pending);
  }

  /// Emits a fresh view, after a tunable change.
  void refresh() => _changed();

  /// Keeps the next-liter timer to the foreground, and the clock fresh
  /// (research R9, R17). No timer runs in the background. The clock's work
  /// waits behind the requests already queued, so a resync never lands
  /// between a request's validation and its commit (M06 research R20).
  Future<void> handleLifecycle(AppLifecycleState lifecycle) async {
    switch (lifecycle) {
      case AppLifecycleState.resumed:
        _foreground = true;
        await _serial(() => _saveAnchor(_clock.resync));
        _changed();
      case AppLifecycleState.paused:
        _leaveForeground();
        await _serial(() => _saveAnchor(_clock.saveLatest));
      case AppLifecycleState.hidden:
        _leaveForeground();
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        break;
    }
  }

  /// A lifecycle write of the clock's anchor. A full disk keeps the anchor in
  /// memory, and the next op or pause saves it (research R11).
  Future<void> _saveAnchor(Future<void> Function() write) async {
    try {
      await write();
    } on EconomyWriteError {
      return;
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_views.close());
    unawaited(_pendingCounts.close());
  }

  FoldResult _fold(EconomyState base, List<Op> ops) => fold(base, ops, _rules);

  Future<OpOutcome> _submit(TxnId id, OpRequest request) => _serial(() async {
    final stored = await _store.findOp(id);
    if (stored != null) {
      assert(
        requestMatches(stored.op, request),
        'The id $id was already used for ${stored.op}.',
      );
      return OpApplied(op: stored, view: view, repeated: true);
    }
    switch (_rules.validate(_state, request, _context(id))) {
      case Declined(:final code):
        return OpRefused(code);
      case Validated(:final op):
        final after = _rules.apply(_state, op);
        final LedgerOp ledgerOp;
        try {
          ledgerOp = await _store.commit(op, before: _state, after: after);
        } on EconomyWriteError {
          return const OpWriteFailed();
        }
        _state = after;
        _pending++;
        if (op.type == OpType.settingsUpdate) _nameRefused = false;
        _changed();
        _pendingChanged();
        return OpApplied(op: ledgerOp, view: view, repeated: false);
    }
  });

  RuleContext _context(TxnId id) {
    final tunables = _tunables();
    return RuleContext(
      nowMs: _clock.nowMs(),
      content: _content(),
      contentVersion: _contentVersion(),
      fuelMax: tunables.read(Tunable.fuelMax),
      fuelRegenMinutes: tunables.read(Tunable.fuelRegenMinutes),
      txnId: id,
    );
  }

  /// Runs [task] after every task before it, so two requests never validate
  /// against the same state (FR-017).
  Future<T> _serial<T>(Future<T> Function() task) {
    final result = _tail.then((_) => task());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  void _changed() {
    if (_disposed) return;
    _views.add(view);
    _rearm();
  }

  void _leaveForeground() {
    _foreground = false;
    _timer?.cancel();
    _timer = null;
  }

  /// One timer, for the next liter or the end of an unlimited window.
  void _rearm() {
    _timer?.cancel();
    _timer = null;
    if (!_foreground || _disposed) return;
    final fuel = view.fuel;
    final next = switch ((fuel.nextLiterAtMs, fuel.unlimitedUntilMs)) {
      (final a?, final b?) => a < b ? a : b,
      (final a?, null) => a,
      (null, final b?) => b,
      (null, null) => null,
    };
    if (next == null) return;
    final wait = next - _clock.nowMs();
    _timer = Timer(Duration(milliseconds: wait < 1 ? 1 : wait), _changed);
  }
}
