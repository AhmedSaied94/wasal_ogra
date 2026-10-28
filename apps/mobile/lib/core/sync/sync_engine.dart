// The sync (specs/011-m06-identity-sync, contracts/sync.md "`SyncEngine`",
// research R9–R14): one pass at a time sends the pending operations in
// order, applies each answer in one step, takes the full state when the
// phone and the server disagree, and stops at every closed gate. Nothing
// here runs in the background, and nothing changes the economy while the
// trip screen shows.
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:wassal/core/account/authorized_api.dart';
import 'package:wassal/core/account/domain/account.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/economy_sync.dart';
import 'package:wassal/core/network/api_client.dart';
import 'package:wassal/core/sync/domain/batching.dart';
import 'package:wassal/core/sync/domain/pass.dart';
import 'package:wassal/core/sync/domain/sync_batch.dart';
import 'package:wassal/core/sync/domain/wire/reader.dart';
import 'package:wassal/core/sync/domain/wire/state.dart';
import 'package:wassal/core/sync/sync_events.dart';
import 'package:wassal/core/sync/sync_time.dart';

export 'package:wassal/core/sync/domain/pass.dart';
export 'package:wassal/core/sync/sync_events.dart';

abstract interface class SyncEngine {
  /// Asks for a pass. Joins the running one (which then runs once more),
  /// or starts one if no gate is closed.
  void request(SyncTrigger trigger);

  /// Internal builds' «sync now»: a forced bootstrap, then a pass.
  Future<PassOutcome> syncNow();

  /// Sends until nothing is pending or [timeout] passes; for the link (R8).
  Future<bool> flush({Duration timeout = const Duration(seconds: 15)});

  /// A returning player was found after the first open's hand-over (R6).
  /// The next pass takes the full state first and emits
  /// `StateTaken(firstOpen)`. Held in memory.
  void requestRestore();

  Stream<SyncEvent> get events;
  SyncSnapshot get snapshot;
}

/// What the sync needs from the account (contracts/account.md).
abstract interface class SyncAccount {
  AccountStatus get status;

  /// The account's player, or null before any.
  String? get playerId;

  Future<bool> ensureSession();

  /// The uptime reading before which no creation is sent: a creation
  /// `429` (FR-004).
  int? get signInAfterElapsedMs;
}

/// Takes the server's full state into the phone (R7, R12): the economy, the
/// profile and the time anchor. Returns how many pending operations another
/// player's state dropped. The elapsed times are the request's, on the
/// uptime counter, for the anchor's round-trip midpoint (R15).
abstract interface class StateApplier {
  Future<int> apply(
    StateSnapshot snapshot,
    StateWhy why, {
    required String playerId,
    required int sentAtElapsedMs,
    required int receivedAtElapsedMs,
  });
}

/// Where the sync reports what it learned of the server (US4's
/// `ServerStatus`, research R17–R19).
abstract interface class SyncStatusSink {
  /// The server answered.
  void reached();

  /// No answer: no connection, a timeout or DNS.
  void unreachable();

  /// `503 maintenance`, with its details.
  void maintenance(Map<String, Object?> details);

  /// `426 client_outdated`.
  void clientOutdated();

  /// A pass ended (R17, R19).
  void passEnded(PassOutcome outcome);
}

/// [SyncStatusSink] that drops everything.
final class NoSyncStatus implements SyncStatusSink {
  const NoSyncStatus();

  @override
  void reached() {}

  @override
  void unreachable() {}

  @override
  void maintenance(Map<String, Object?> details) {}

  @override
  void clientOutdated() {}

  @override
  void passEnded(PassOutcome outcome) {}
}

/// At least this long between an answer and the next batch: under B03's
/// 60 syncs a minute (SC-005).
const batchSpacing = Duration(seconds: 1);

/// A new pending operation waits this long, so a trip's start and result
/// often travel together.
const opsDebounce = Duration(seconds: 2);

/// The backoff: from 2 s, doubling to 5 min, ±20%.
const backoffFirst = Duration(seconds: 2);
const backoffMax = Duration(minutes: 5);
const backoffJitter = 0.2;

/// The ad rewards whose effects are counters, not anything the player sees
/// as a balance (research R14).
final _counterPlacements = {
  AdPlacement.tripRevive.wire,
  AdPlacement.trafficJam.wire,
};

final _opIndex = RegExp(r'^ops\.(\d+)(?:\.|$)');

final class SyncRunner implements SyncEngine {
  SyncRunner({
    required this._account,
    required this._api,
    required this._economy,
    required this._states,
    required this._time,
    required this._serverStateVersion,
    this._status = const NoSyncStatus(),
    this._bootstrap,
    Random? random,
  }) : _random = random ?? Random();

  final SyncAccount _account;
  final AuthorizedApi _api;
  final EconomySync _economy;
  final StateApplier _states;
  final SyncTime _time;

  /// The last bootstrap's `state_version`, or null before any (R15).
  final int? Function() _serverStateVersion;
  final SyncStatusSink _status;

  /// The forced bootstrap of «sync now» (R15).
  final Future<void> Function()? _bootstrap;
  final Random _random;

  final _events = StreamController<SyncEvent>.broadcast();

  Future<PassOutcome>? _running;
  bool _again = false;
  bool _restorePending = false;

  // The gates.
  bool _onTripScreen = false;
  bool _foreground = true;
  bool _maintenanceHold = false;
  bool _heldUntilLaunch = false;

  // The backoff.
  int _failures = 0;
  int? _retryAtMs;
  Timer? _retryTimer;
  Timer? _debounce;

  int? _lastAnswerAtMs;
  bool _toastDue = false;
  PassOutcome? _lastOutcome;
  int? _lastEndedAtMs;
  int? _lastDurationMs;
  int _setAsideSinceLaunch = 0;
  String? _lastError;
  bool _disposed = false;

  @override
  Stream<SyncEvent> get events => _events.stream;

  @override
  SyncSnapshot get snapshot => SyncSnapshot(
    running: _running != null,
    lastOutcome: _lastOutcome,
    lastEndedAtMs: _lastEndedAtMs,
    lastError: _lastError,
    backoffUntilMs: _backingOff ? _retryAtMs : null,
    heldUntilLaunch: _heldUntilLaunch,
    lastDurationMs: _lastDurationMs,
    setAsideSinceLaunch: _setAsideSinceLaunch,
  );

  /// The trip route shows, or stopped showing (R9). Leaving it asks for a
  /// pass and delivers a waiting toast.
  void setTripScreen(bool shown) {
    if (shown == _onTripScreen) return;
    _onTripScreen = shown;
    if (shown) return;
    _deliverToast();
    request(SyncTrigger.leftTrip);
  }

  /// The app came to the foreground, or left it. A return lifts the
  /// maintenance hold (R19) and asks for a pass.
  void setForeground(bool foreground) {
    if (foreground == _foreground) return;
    _foreground = foreground;
    if (!foreground) return;
    _maintenanceHold = false;
    request(SyncTrigger.resume);
  }

  @override
  void request(SyncTrigger trigger) {
    if (_disposed) return;
    if (trigger == SyncTrigger.opsRecorded) {
      _debounce?.cancel();
      _debounce = _time.after(opsDebounce, () => _start(trigger));
      return;
    }
    _start(trigger);
  }

  @override
  Future<PassOutcome> syncNow() async {
    await _bootstrap?.call();
    return _start(SyncTrigger.manual) ?? const PassIdle();
  }

  @override
  Future<bool> flush({Duration timeout = const Duration(seconds: 15)}) async {
    if (_economy.pendingCount == 0) return true;
    final deadline = Completer<PassOutcome?>();
    final timer = _time.after(timeout, () => deadline.complete(null));
    try {
      while (_economy.pendingCount > 0) {
        final pass = _start(SyncTrigger.manual);
        if (pass == null) return false;
        final outcome = await Future.any([pass, deadline.future]);
        if (outcome is! PassDone && outcome is! PassIdle) break;
      }
    } finally {
      timer.cancel();
    }
    return _economy.pendingCount == 0;
  }

  @override
  void requestRestore() {
    _restorePending = true;
    request(SyncTrigger.accountActive);
  }

  /// Completes when no pass is running.
  Future<void> get idle async {
    for (var running = _running; running != null; running = _running) {
      await running;
    }
  }

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _debounce?.cancel();
    unawaited(_events.close());
  }

  bool get _backingOff {
    final at = _retryAtMs;
    return at != null && _time.nowMs() < at;
  }

  /// Starts a pass, or marks the running one to run again. Returns the
  /// running passes' outcome, or null when the backoff holds [trigger].
  Future<PassOutcome>? _start(SyncTrigger trigger) {
    if (_disposed) return null;
    if (trigger == SyncTrigger.online) _resetBackoff();
    if (_running case final running?) {
      _again = true;
      return running;
    }
    // The retry's timer and the backoff's clock can disagree by a tick,
    // and a dropped retry would wait for the next trigger.
    final skipsBackoff =
        trigger == SyncTrigger.online ||
        trigger == SyncTrigger.manual ||
        trigger == SyncTrigger.retry;
    if (_backingOff && !skipsBackoff) return null;
    return _running = _runPasses();
  }

  Future<PassOutcome> _runPasses() async {
    PassOutcome outcome;
    try {
      do {
        _again = false;
        final startedAt = _time.nowMs();
        outcome = await _guardedPass();
        _lastOutcome = outcome;
        final endedAt = _lastEndedAtMs = _time.nowMs();
        _lastDurationMs = endedAt - startedAt;
        _status.passEnded(outcome);
        _emit(PassEnded(outcome, durationMs: endedAt - startedAt));
      } while (_again && (outcome is PassDone || outcome is PassIdle));
    } finally {
      _running = null;
    }
    _deliverToast();
    return outcome;
  }

  /// A pass that threw (a database error, say) backs off like a failed
  /// request: the retry still comes, and the error is reported.
  Future<PassOutcome> _guardedPass() async {
    try {
      return await _pass();
    } on Exception catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack, library: 'sync'),
      );
      return _backOff('internal');
    }
  }

  HoldReason? _closedGate() {
    if (_account.status == AccountStatus.deleted) return HoldReason.deleted;
    if (!_foreground) return HoldReason.background;
    if (_onTripScreen) return HoldReason.trip;
    if (_maintenanceHold) return HoldReason.maintenance;
    if (_heldUntilLaunch) return HoldReason.refused;
    return null;
  }

  Future<PassOutcome> _pass() async {
    if (_closedGate() case final reason?) return PassHeld(reason);
    // 1. The account.
    if (!await _account.ensureSession()) {
      if (_account.status == AccountStatus.deleted) {
        return const PassHeld(HoldReason.deleted);
      }
      final after = _account.signInAfterElapsedMs;
      return _backOff(
        'account',
        atLeast: after == null
            ? null
            : Duration(milliseconds: after - _time.nowMs()),
      );
    }
    final player = _account.playerId;
    if (player == null) return _backOff('account');
    // 2. Another player's state, before anything is sent with its tokens.
    final basePlayer = _economy.baseInfo.playerId;
    if (basePlayer != null && basePlayer != player) {
      if (await _takeState(StateWhy.account, player) case final stop?) {
        return stop;
      }
    }
    // 2b. A returning player found after the first open's hand-over.
    if (_restorePending) {
      if (await _takeState(StateWhy.firstOpen, player) case final stop?) {
        return stop;
      }
      _restorePending = false;
    }
    // 3. The batches.
    final counts = _Counts();
    var cap = maxBatchOps;
    while (true) {
      if (_closedGate() case final reason?) return PassHeld(reason);
      // Another player's tokens since the pass began: the next pass takes
      // its state before anything more is sent (R7).
      if (_account.playerId != player) {
        _again = true;
        return _ended(counts);
      }
      final pending = await _economy.pendingOps(limit: cap);
      final plan = planBatch(
        pending,
        baseStateVersion: _economy.baseInfo.stateVersion ?? 0,
        maxOps: cap,
      );
      switch (plan) {
        case NothingPending():
          break;
        case OversizedOp(:final op):
          await _setAside({op: 'payload_too_large'}, counts);
          continue;
        case NextBatch(:final batch):
          final step = await _send(batch, player, counts);
          switch (step) {
            case _Continue():
              cap = maxBatchOps;
              continue;
            case _Shrink(:final ops):
              cap = ops;
              continue;
            case _Stop(:final outcome):
              return outcome;
          }
      }
      break;
    }
    // 4. The server is ahead, and nothing is pending.
    final serverVersion = _serverStateVersion();
    final baseVersion = _economy.baseInfo.stateVersion;
    if (_economy.pendingCount == 0 &&
        serverVersion != null &&
        (baseVersion == null || serverVersion > baseVersion)) {
      if (await _takeState(StateWhy.ahead, player) case final stop?) {
        return stop;
      }
    }
    return _ended(counts);
  }

  PassOutcome _ended(_Counts counts) {
    _resetBackoff();
    if (counts.batches == 0 && counts.setAside == 0) return const PassIdle();
    return PassDone(
      batches: counts.batches,
      accepted: counts.accepted,
      rejected: counts.rejected,
      setAside: counts.setAside,
    );
  }

  /// One batch: spacing, the request, and its answer or refusal.
  Future<_Step> _send(SyncBatch batch, String player, _Counts counts) async {
    final last = _lastAnswerAtMs;
    if (last != null) {
      final wait = last + batchSpacing.inMilliseconds - _time.nowMs();
      if (wait > 0) await _time.wait(Duration(milliseconds: wait));
    }
    if (_closedGate() case final reason?) return _Stop(PassHeld(reason));
    final result = await _api.send(
      ApiRequest.post(
        ApiPaths.sync,
        receiveTimeout: syncReceiveTimeout,
        body: batch.body,
        forPlayer: player,
      ),
    );
    if (result is! ApiUnreachable) _lastAnswerAtMs = _time.nowMs();
    switch (result) {
      case ApiOk(:final json):
        _status.reached();
        final SyncAnswer answer;
        try {
          answer = SyncAnswer.fromJson(json);
        } on WireFormatException {
          return _Stop(_backOff('server_error'));
        }
        // An answer that lands as a trip opens waits: its operations are
        // sent again later, and the server answers the same (FR-018).
        if (_closedGate() case final reason?) return _Stop(PassHeld(reason));
        final applied = await _economy.applyAnswer(
          answer,
          batch: batch.ops,
          playerId: player,
        );
        _answered(answer, batch, counts);
        if (answer.stateStale || applied.leftOutAccepted.isNotEmpty) {
          final why = answer.stateStale ? StateWhy.stale : StateWhy.diverged;
          if (await _takeState(why, player) case final stop?) {
            return _Stop(stop);
          }
        }
        _resetBackoff();
        return const _Continue();
      case ApiFailure(status: 400, code: 'batch_too_large') ||
          ApiFailure(status: 413):
        _status.reached();
        if (batch.ops.length == 1) {
          await _setAside({batch.ops.single: 'payload_too_large'}, counts);
          return const _Continue();
        }
        return _Shrink(halved(batch.ops.length));
      case ApiFailure(status: 400, code: 'validation_error', :final details):
        _status.reached();
        final named = _namedOps(details, batch);
        if (named.isEmpty) return _Stop(_holdUntilLaunch('validation_error'));
        await _setAside({
          for (final op in named) op: 'validation_error',
        }, counts);
        return const _Continue();
      case ApiFailure(status: 415 || 406, :final code):
        _status.reached();
        return _Stop(_holdUntilLaunch(code));
      case ApiFailure(code: 'account_changed'):
        // Not sent: the loop's player check ends the pass.
        return const _Continue();
      default:
        return _Stop(_refused(result));
    }
  }

  void _answered(SyncAnswer answer, SyncBatch batch, _Counts counts) {
    counts.batches++;
    final byId = {for (final op in batch.ops) op.op.txnId.value: op.op};
    for (final result in answer.results) {
      final op = byId[result.txnId];
      if (op == null) continue;
      final reason = result.reason;
      if (reason == null) {
        counts.accepted++;
        continue;
      }
      counts.rejected++;
      _emit(OpRejected(result.txnId, op.type.wire, reason));
      if (_isVisible(op)) _toastDue = true;
    }
  }

  Future<void> _setAside(Map<LedgerOp, String> reasons, _Counts counts) async {
    await _economy.setAside({
      for (final MapEntry(:key, :value) in reasons.entries) key.op.txnId: value,
    });
    for (final MapEntry(key: op, value: reason) in reasons.entries) {
      counts.setAside++;
      _setAsideSinceLaunch++;
      _emit(OpSetAside(op.op.txnId.value, op.op.type.wire, reason));
      if (_isVisible(op.op)) _toastDue = true;
    }
  }

  /// `GET /v1/state` and its taking. Null when taken; else why the pass
  /// stops.
  Future<PassOutcome?> _takeState(StateWhy why, String player) async {
    if (_closedGate() case final reason?) return PassHeld(reason);
    final result = await _api.send(
      ApiRequest.get(
        ApiPaths.state,
        receiveTimeout: readReceiveTimeout,
        forPlayer: player,
      ),
    );
    switch (result) {
      case ApiOk(
        :final json,
        :final sentAtElapsedMs,
        :final receivedAtElapsedMs,
      ):
        _status.reached();
        final StateSnapshot snapshot;
        try {
          snapshot = StateSnapshot.fromJson(json);
        } on WireFormatException {
          return _backOff('server_error');
        }
        if (_closedGate() case final reason?) return PassHeld(reason);
        // Another player's tokens fetched it: the next pass takes it as
        // theirs.
        if (_account.playerId != player) {
          _again = true;
          return const PassIdle();
        }
        final dropped = await _states.apply(
          snapshot,
          why,
          playerId: player,
          sentAtElapsedMs: sentAtElapsedMs,
          receivedAtElapsedMs: receivedAtElapsedMs,
        );
        if (dropped > 0) _emit(OpsDropped(dropped));
        _emit(StateTaken(snapshot.stateVersion, why));
        return null;
      // The session is another player's now: the next pass takes theirs.
      case ApiFailure(code: 'account_changed'):
        _again = true;
        return const PassIdle();
      default:
        return _refused(result);
    }
  }

  /// A whole request refused (R13), for every call.
  PassOutcome _refused(ApiResult result) {
    switch (result) {
      case ApiUnreachable(:final kind):
        _status.unreachable();
        return _backOff(kind.name);
      case ApiFailure(status: 403, code: 'account_deleted'):
        _status.reached();
        return const PassHeld(HoldReason.deleted);
      case ApiFailure(status: 426):
        _status
          ..reached()
          ..clientOutdated();
        return _holdUntilLaunch('client_outdated');
      case ApiFailure(status: 503, code: 'maintenance', :final details):
        _status
          ..reached()
          ..maintenance(details);
        _maintenanceHold = true;
        _lastError = 'maintenance';
        return const PassHeld(HoldReason.maintenance);
      case ApiFailure(status: 429, :final code, :final retryAfter):
        _status.reached();
        return _backOff(code, atLeast: retryAfter);
      case ApiFailure(:final code):
        _status.reached();
        return _backOff(code);
      case ApiOk():
        return _backOff('server_error');
    }
  }

  PassOutcome _holdUntilLaunch(String code) {
    _heldUntilLaunch = true;
    _lastError = code;
    return const PassHeld(HoldReason.refused);
  }

  /// Backs off (R9): 2 s doubling to 5 min, ±20%, and never under
  /// [atLeast]. The retry asks for a pass when it ends.
  PassFailed _backOff(String code, {Duration? atLeast}) {
    _failures++;
    // Clamped so pow never overflows: the cap is reached long before.
    final base = min(
      backoffFirst.inMilliseconds * pow(2, min(_failures - 1, 30)),
      backoffMax.inMilliseconds,
    ).toInt();
    final jitter = 1 + backoffJitter * (2 * _random.nextDouble() - 1);
    final wait = max((base * jitter).round(), atLeast?.inMilliseconds ?? 0);
    final at = _time.nowMs() + wait;
    _retryAtMs = at;
    _lastError = code;
    _retryTimer?.cancel();
    _retryTimer = _time.after(
      Duration(milliseconds: wait),
      () => request(SyncTrigger.retry),
    );
    return PassFailed(code, retryAtMs: at);
  }

  void _resetBackoff() {
    _failures = 0;
    _retryAtMs = null;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _deliverToast() {
    if (!_toastDue || _onTripScreen) return;
    _toastDue = false;
    _emit(const BalanceCorrected());
  }

  void _emit(SyncEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  /// The operations `details.fields` names by `ops.N…`.
  static List<LedgerOp> _namedOps(
    Map<String, Object?> details,
    SyncBatch batch,
  ) {
    final fields = details['fields'];
    if (fields is! Map<String, Object?>) return const [];
    final indexes = {
      for (final key in fields.keys)
        if (_opIndex.firstMatch(key) case final match?) int.parse(match[1]!),
    };
    return [
      for (final i in indexes.toList()..sort())
        if (i < batch.ops.length) batch.ops[i],
    ];
  }

  /// A rejection the player could see (R14): every type but the ad
  /// rewards whose effects are counters, and the name, which Home asks for
  /// again instead (specs/012-m07-onboarding research R7).
  static bool _isVisible(Op op) => switch (op.type) {
    OpType.adReward => !_counterPlacements.contains(op.payload['ad_placement']),
    OpType.settingsUpdate => false,
    _ => true,
  };
}

/// What a pass counted.
final class _Counts {
  int batches = 0;
  int accepted = 0;
  int rejected = 0;
  int setAside = 0;
}

sealed class _Step {
  const _Step();
}

final class _Continue extends _Step {
  const _Continue();
}

/// Resend with at most [ops] operations (R13).
final class _Shrink extends _Step {
  const _Shrink(this.ops);

  final int ops;
}

final class _Stop extends _Step {
  const _Stop(this.outcome);

  final PassOutcome outcome;
}
