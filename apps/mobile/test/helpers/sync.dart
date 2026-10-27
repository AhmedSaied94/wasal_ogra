// Fakes for the sync's tests (specs/011-m06-identity-sync T045, T046): time
// that moves by hand, an account, an economy kept in memory, a recording
// state applier, and the server's JSON.
import 'dart:async';

import 'package:wassal/core/account/authorized_api.dart';
import 'package:wassal/core/account/domain/account.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/economy/economy_sync.dart';
import 'package:wassal/core/network/api_client.dart';
import 'package:wassal/core/sync/domain/wire/state.dart';
import 'package:wassal/core/sync/sync_engine.dart';
import 'package:wassal/core/sync/sync_time.dart';

import 'fake_api.dart';

const syncPlayer = '0192f1c3-7d1e-7a4b-9c11-000000000001';
const otherPlayer = '0192f1c3-7d1e-7a4b-9c11-000000000002';

/// The sync's clock. [wait] moves it at once (so a pass never stalls on
/// spacing or latency), and fires the timers it passes; [elapse] moves it
/// by hand.
final class FakeSyncTime implements SyncTime {
  int now = 0;
  final _timers = <_FakeTimer>[];

  @override
  int nowMs() => now;

  @override
  Future<void> wait(Duration duration) async => elapse(duration);

  @override
  Timer after(Duration duration, void Function() callback) {
    final timer = _FakeTimer(now + duration.inMilliseconds, callback);
    _timers.add(timer);
    return timer;
  }

  /// Moves the clock by [by], firing each timer due on the way, in order.
  void elapse(Duration by) {
    final target = now + by.inMilliseconds;
    while (true) {
      final due = [
        for (final t in _timers)
          if (t.isActive && t.at <= target) t,
      ]..sort((a, b) => a.at.compareTo(b.at));
      if (due.isEmpty) break;
      final next = due.first;
      now = next.at;
      next.fire();
    }
    _timers.removeWhere((t) => !t.isActive);
    now = target;
  }

  /// The timers still waiting.
  int get pendingTimers => _timers.where((t) => t.isActive).length;
}

final class _FakeTimer implements Timer {
  _FakeTimer(this.at, this._callback);

  final int at;
  final void Function() _callback;
  bool _active = true;

  void fire() {
    _active = false;
    _callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}

final class FakeSyncAccount implements SyncAccount {
  FakeSyncAccount({
    this.status = AccountStatus.active,
    this.playerId = syncPlayer,
  });

  @override
  AccountStatus status;

  @override
  String? playerId;

  /// What ensureSession answers.
  bool sessionOk = true;

  @override
  int? signInAfterElapsedMs;

  int sessionChecks = 0;

  @override
  Future<bool> ensureSession() async {
    sessionChecks++;
    return sessionOk;
  }
}

/// The plain client as the authorized one: tokens are the account's tests'
/// business.
final class PlainAuthorizedApi implements AuthorizedApi {
  const PlainAuthorizedApi(this.api);

  final ApiClient api;

  @override
  Future<ApiResult> send(ApiRequest request) => api.send(request);
}

/// One taking of the full state.
typedef StateCall = ({StateSnapshot snapshot, StateWhy why, String playerId});

/// Records what the engine takes, and hands it to [economy] when given.
final class RecordingStates implements StateApplier {
  RecordingStates([this.economy]);

  final EconomySync? economy;
  final calls = <StateCall>[];

  @override
  Future<int> apply(
    StateSnapshot snapshot,
    StateWhy why, {
    required String playerId,
    required int sentAtElapsedMs,
    required int receivedAtElapsedMs,
  }) async {
    calls.add((snapshot: snapshot, why: why, playerId: playerId));
    final economy = this.economy;
    if (economy == null) return 0;
    final state = EconomyState.newPlayer(fuelMax: 5, nowMs: 0);
    if (why == StateWhy.account) {
      return economy.adoptAccount(
        state,
        playerId: playerId,
        stateVersion: snapshot.stateVersion,
      );
    }
    await economy.replaceFromServer(
      state,
      playerId: playerId,
      stateVersion: snapshot.stateVersion,
    );
    return 0;
  }
}

/// The economy's sync side, in memory: rows, their answers and the base.
final class MemoryEconomy implements EconomySync {
  MemoryEconomy(List<LedgerOp> pending, {int? stateVersion, String? playerId})
    : _rows = [
        for (final op in pending)
          (op: op, status: SyncStatus.pending, reason: null),
      ],
      baseInfo = (stateVersion: stateVersion, playerId: playerId);

  List<({LedgerOp op, SyncStatus status, String? reason})> _rows;

  @override
  ({int? stateVersion, String? playerId}) baseInfo;

  /// How many times each id's answer was applied.
  final answersApplied = <String, int>{};

  /// What the next applyAnswer reports as left out by the fold.
  List<TxnId> leftOut = const [];

  final _counts = StreamController<int>.broadcast();

  static final _view = EconomyView(
    EconomyState.newPlayer(fuelMax: 5, nowMs: 0),
    const FuelView(liters: 5, max: 5),
  );

  /// Adds operations, as the player records them.
  void record(List<LedgerOp> ops) {
    _rows = [
      ..._rows,
      for (final op in ops) (op: op, status: SyncStatus.pending, reason: null),
    ];
    _counts.add(pendingCount);
  }

  SyncStatus statusOf(LedgerOp op) =>
      _rows.firstWhere((r) => r.op.op.txnId == op.op.txnId).status;

  String? reasonOf(LedgerOp op) =>
      _rows.firstWhere((r) => r.op.op.txnId == op.op.txnId).reason;

  @override
  int get pendingCount =>
      _rows.where((r) => r.status == SyncStatus.pending).length;

  @override
  Stream<int> get pendingCounts => _counts.stream;

  @override
  Future<List<LedgerOp>> pendingOps({int limit = 100}) async => [
    for (final r in _rows)
      if (r.status == SyncStatus.pending) r.op,
  ].take(limit).toList();

  @override
  Future<int> highestAnsweredSeq() async => _rows
      .where((r) => r.status != SyncStatus.pending)
      .fold<int>(0, (seq, r) => r.op.seq > seq ? r.op.seq : seq);

  @override
  Future<bool> hasPending(OpType type) async =>
      _rows.any((r) => r.status == SyncStatus.pending && r.op.op.type == type);

  @override
  Future<AnswerApplied> applyAnswer(
    SyncAnswer answer, {
    required List<LedgerOp> batch,
    required String playerId,
  }) async {
    final sent = {for (final op in batch) op.op.txnId.value};
    final results = {
      for (final r in answer.results)
        if (sent.contains(r.txnId)) r.txnId: r,
    };
    _rows = [
      for (final row in _rows)
        if (results[row.op.op.txnId.value] case final r?
            when row.status == SyncStatus.pending)
          (
            op: row.op,
            status: r.accepted ? SyncStatus.accepted : SyncStatus.rejected,
            reason: r.reason,
          )
        else
          row,
    ];
    for (final id in results.keys) {
      answersApplied[id] = (answersApplied[id] ?? 0) + 1;
    }
    if (!answer.stateStale) {
      baseInfo = (stateVersion: answer.stateVersion, playerId: playerId);
    }
    _counts.add(pendingCount);
    final left = leftOut;
    leftOut = const [];
    return AnswerApplied(leftOutAccepted: left, before: _view, after: _view);
  }

  @override
  Future<void> replaceFromServer(
    EconomyState snapshot, {
    required String playerId,
    required int stateVersion,
  }) async => baseInfo = (stateVersion: stateVersion, playerId: playerId);

  @override
  Future<int> adoptAccount(
    EconomyState snapshot, {
    required String playerId,
    required int stateVersion,
  }) async {
    final dropped = pendingCount;
    _rows = [
      for (final row in _rows)
        if (row.status == SyncStatus.pending)
          (op: row.op, status: SyncStatus.rejected, reason: 'account_changed')
        else
          row,
    ];
    baseInfo = (stateVersion: stateVersion, playerId: playerId);
    _counts.add(pendingCount);
    return dropped;
  }

  @override
  Future<void> setAside(Map<TxnId, String> reasons) async {
    _rows = [
      for (final row in _rows)
        if (reasons[row.op.op.txnId] case final reason?)
          (op: row.op, status: SyncStatus.rejected, reason: reason)
        else
          row,
    ];
    _counts.add(pendingCount);
  }

  @override
  Future<OpOutcome> grantComebackGift(TxnId id) => throw UnimplementedError();

  /// Each anchor: the server's time and the uptime reading it was for.
  final anchors = <(int, int)>[];

  @override
  Future<void> anchorOnServer(
    int serverTimeMs, {
    required int elapsedAtResponseMs,
  }) async => anchors.add((serverTimeMs, elapsedAtResponseMs));
}

Map<String, Object?> walletJson({int jenehat = 900, int bonat = 77}) => {
  'jenehat': jenehat,
  'bonat': bonat,
  'fuel': 3,
  'fuel_max': 5,
  'fuel_updated_at': '2026-10-17T09:00:00Z',
  'fuel_unlimited_until': null,
};

/// A `GET /v1/bootstrap` answer.
Map<String, Object?> bootstrapJson({
  String serverTime = '2026-10-17T09:00:00Z',
  int stateVersion = 42,
  int? contentVersion = 1,
  bool forceUpdate = false,
  bool comebackClaimable = false,
  String? displayName = 'name',
  int jenehat = 900,
}) => {
  'server_time': serverTime,
  'player': {
    'player_id': syncPlayer,
    'display_name': displayName,
    'driver_level': 4,
    'country': 'EG',
    'providers': ['google'],
  },
  'wallet': walletJson(jenehat: jenehat),
  'entitlements': {
    'remove_ads': true,
    'subscription': null,
    'season_passes': <Object?>[],
    'flags': {'no_interstitials': true, 'fuel_max_bonus': 2},
  },
  'state_version': stateVersion,
  'content': {
    'version': contentVersion,
    'manifest_url': '/v1/content/manifest',
  },
  'client': {
    'min_version': '1.0.0',
    'latest_version': '1.2.0',
    'force_update': forceUpdate,
  },
  'daily': {
    'game_date': '2026-10-17',
    'challenge_available': false,
    'reward_claimable': true,
  },
  'comeback': {'claimable': comebackClaimable},
};

/// A `GET /v1/state` answer, with the sample pack's own ids.
Map<String, Object?> stateJson({int stateVersion = 42}) => {
  'state_version': stateVersion,
  'server_time': '2026-10-17T09:00:00.250Z',
  'player': {
    'display_name': 'name',
    'driver_level': 4,
    'settings': {'digits': 'arabic'},
  },
  'wallet': walletJson(),
  'inventory': {'change_bag': 2, 'wake_all': 0, 'ledger_peek': 1},
  'ownership': [
    {'kind': 'vehicle', 'sku_id': 'micro_old', 'variant': ''},
  ],
  'trips': [
    {
      'trip_id': 'line_hay.01',
      'best_stars': 3,
      'best_time_ms': 91200,
      'plays': 4,
    },
  ],
  'open_trip': null,
  'last_result': null,
  'story': {'chapters': <Object?>[]},
  'grants': {'tutorial': true},
  'stats': {'trips_played': 4},
  'comeback': {'claimable': false},
};

/// The ids a `POST /v1/sync` request carries.
List<String> sentIds(ApiRequest request) => [
  for (final op in (request.body! as Map<String, Object?>)['ops']! as List)
    (op as Map<String, Object?>)['client_txn_id']! as String,
];

/// A `POST /v1/sync` answer for [request]: every operation accepted, but
/// those in [rejected].
ApiOk syncAnswerFor(
  ApiRequest request, {
  Map<String, String> rejected = const {},
  int stateVersion = 5,
  bool stale = false,
}) => apiOk({
  'state_version': stateVersion,
  'state_stale': stale,
  'results': [
    for (final id in sentIds(request))
      if (rejected[id] case final reason?)
        {'client_txn_id': id, 'status': 'rejected', 'reason': reason}
      else
        {'client_txn_id': id, 'status': 'accepted'},
  ],
  'wallet': walletJson(),
});
