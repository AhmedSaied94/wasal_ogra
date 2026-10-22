// The one economy service (research R10, R11, R17): one writer, one
// transaction per operation, and a view that changes only after a commit.
import 'dart:async';

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
import 'package:wassal/core/economy/trusted_clock.dart';
import 'package:wassal/core/economy/txn_ids.dart';

final class EconomyService implements Economy {
  EconomyService._({
    required this._store,
    required this._clock,
    required this._content,
    required this._contentVersion,
    required this._tunables,
    required this._rules,
    required this._state,
  });

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
    ).._rearm();
  }

  final DriftEconomyStore _store;
  final TrustedClock _clock;
  final ContentSource Function() _content;
  final int Function() _contentVersion;
  final ConfigSource Function() _tunables;
  final Rules _rules;
  EconomyState _state;

  final _views = StreamController<EconomyView>.broadcast();
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
  Future<List<LedgerOp>> pendingOps({int limit = 100}) =>
      _serial(() => _store.pendingOps(limit));

  @override
  Future<void> markAccepted(Iterable<TxnId> ids) => _serial(() async {
    final skipped = await _store.markAccepted(ids);
    assert(skipped.isEmpty, 'Not pending, left as they were: $skipped');
  });

  @override
  Future<void> markRejected(Map<TxnId, String> reasons) => _serial(() async {
    final rebuilt = await _store.rebuild(_fold, rejected: reasons);
    _state = rebuilt.fold.state;
    _changed();
    assert(
      rebuilt.skipped.isEmpty,
      'Not pending, left as they were: ${rebuilt.skipped}',
    );
  });

  @override
  Future<void> replaceBase(
    EconomyState snapshot, {
    required int afterSeq,
    int? stateVersion,
  }) => _serial(() async {
    final rebuilt = await _store.rebuild(
      _fold,
      newBase: ProjectionBase(
        state: snapshot,
        afterSeq: afterSeq,
        kind: BaseKind.serverSnapshot,
        stateVersion: stateVersion,
        takenAtMs: _clock.nowMs(),
      ),
    );
    _state = rebuilt.fold.state;
    _changed();
  });

  /// Emits a fresh view, after a tunable change.
  void refresh() => _changed();

  /// Keeps the next-liter timer to the foreground, and the clock fresh
  /// (research R9, R17). No timer runs in the background.
  Future<void> handleLifecycle(AppLifecycleState lifecycle) async {
    switch (lifecycle) {
      case AppLifecycleState.resumed:
        _foreground = true;
        await _saveAnchor(_clock.resync);
        _changed();
      case AppLifecycleState.paused:
        _leaveForeground();
        await _saveAnchor(_clock.saveLatest);
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
        _changed();
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
