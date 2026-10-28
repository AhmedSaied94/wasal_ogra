import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/account/domain/account.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/txn_id.dart';
import 'package:wassal/core/network/api_client.dart';
import 'package:wassal/core/sync/domain/batching.dart';
import 'package:wassal/core/sync/sync_engine.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/sync.dart';

// The sync's passes (specs/011-m06-identity-sync, contracts/sync.md "Gates"
// and "A pass", research R9–R14), against a scripted server, fake time and
// an economy in memory. The economy's own side of an answer is
// apply_answer_test's; the two together are sync_property_test's.

const _thirdPlayer = '0192f1c3-7d1e-7a4b-9c11-000000000003';

LedgerOp _op(
  int seq, {
  OpType type = OpType.spendBonat,
  Map<String, Object>? payload,
}) => LedgerOp(
  seq: seq,
  op: Op(
    txnId: TxnId.parse(
      '0192f3a1-7b2c-7d4e-8f00-${seq.toRadixString(16).padLeft(12, '0')}',
    ),
    type: type,
    payload: payload ?? const {'kind': 'booster', 'sku_id': 'change_bag'},
    occurredAtMs: 1792627200000 + seq * 1000,
    contentVersion: 1,
    fuelMax: 5,
    fuelRegenMinutes: 20,
  ),
  syncStatus: SyncStatus.pending,
);

List<LedgerOp> _ops(int count, {int from = 1}) => [
  for (var seq = from; seq < from + count; seq++) _op(seq),
];

/// Real play's mix (SC-005): each trip a start and a result of
/// [resultBytes], and a spend every fifth trip.
List<LedgerOp> _playMix(int count, {required int resultBytes}) {
  final ops = <LedgerOp>[];
  var seq = 0;
  for (var trip = 1; ops.length < count; trip++) {
    final start = _op(
      ++seq,
      type: OpType.tripStart,
      payload: {'trip_id': 'line_hay.01'},
    );
    ops
      ..add(start)
      ..add(
        _op(
          ++seq,
          type: OpType.tripResult,
          payload: {
            'start_txn': start.op.txnId.value,
            'result': {'log': 'x' * resultBytes},
          },
        ),
      );
    if (trip % 5 == 0) ops.add(_op(++seq));
  }
  return ops.take(count).toList();
}

final class _Status implements SyncStatusSink {
  final calls = <String>[];
  Map<String, Object?>? maintenanceDetails;

  @override
  void reached() => calls.add('reached');

  @override
  void unreachable() => calls.add('unreachable');

  @override
  void maintenance(Map<String, Object?> details) {
    calls.add('maintenance');
    maintenanceDetails = details;
  }

  @override
  void clientOutdated() => calls.add('clientOutdated');

  @override
  void passEnded(PassOutcome outcome) {}
}

final class _Rig {
  _Rig(
    List<LedgerOp> pending, {
    int? baseVersion = 3,
    String? basePlayer = syncPlayer,
    Duration? latency,
    Future<void> Function()? bootstrap,
  }) {
    api = FakeApi(elapsedMs: () => time.now, latency: latency, wait: time.wait);
    economy = MemoryEconomy(
      pending,
      stateVersion: baseVersion,
      playerId: basePlayer,
    );
    states = RecordingStates(economy);
    engine = SyncRunner(
      account: account,
      api: PlainAuthorizedApi(api),
      economy: economy,
      states: states,
      time: time,
      serverStateVersion: () => serverVersion,
      status: status,
      bootstrap: bootstrap,
      random: Random(7),
    );
    engine.events.listen(events.add);
    addTearDown(engine.dispose);
  }

  final time = FakeSyncTime();
  final account = FakeSyncAccount();
  final status = _Status();
  late final FakeApi api;
  late final MemoryEconomy economy;
  late final RecordingStates states;
  late final SyncRunner engine;
  int? serverVersion;
  final events = <SyncEvent>[];

  /// Every sync request, answered: all accepted.
  void acceptAll({int stateVersion = 5}) => api.always(
    'POST',
    ApiPaths.sync,
    (ApiRequest r) => syncAnswerFor(r, stateVersion: stateVersion),
  );

  List<ApiRequest> get syncs => api.to(ApiPaths.sync);

  List<int> get batchSizes => [for (final r in syncs) sentIds(r).length];

  /// Asks for a pass with [trigger], and waits for every pass to end.
  Future<PassOutcome?> run([SyncTrigger trigger = SyncTrigger.startup]) async {
    engine.request(trigger);
    await engine.idle;
    await pumpEventQueue();
    return engine.snapshot.lastOutcome;
  }

  /// Moves time by [by], and waits for the passes it started.
  Future<void> elapse(Duration by) async {
    time.elapse(by);
    await pumpEventQueue();
    await engine.idle;
    await pumpEventQueue();
  }

  List<PassOutcome> get outcomes => [
    for (final e in events)
      if (e case PassEnded(:final outcome)) outcome,
  ];

  int get toasts => events.whereType<BalanceCorrected>().length;
}

Matcher _held(HoldReason reason) =>
    isA<PassHeld>().having((p) => p.reason, 'reason', reason);

Matcher _failed(String code) =>
    isA<PassFailed>().having((p) => p.code, 'code', code);

void main() {
  group('gates', () {
    test('no pass while the session fails: backoff, nothing sent', () async {
      final rig = _Rig(_ops(2));
      rig.account
        ..status = AccountStatus.none
        ..sessionOk = false;

      expect(await rig.run(), _failed('account'));
      expect(rig.api.log, isEmpty);
      expect(rig.engine.snapshot.backoffUntilMs, isNotNull);
    });

    test('deleted: held, without even a session check', () async {
      final rig = _Rig(_ops(2))..acceptAll();
      rig.account.status = AccountStatus.deleted;

      expect(await rig.run(), _held(HoldReason.deleted));
      expect(rig.account.sessionChecks, 0);
      expect(rig.api.log, isEmpty);
    });

    test('the trip route holds it; leaving asks for one', () async {
      final rig = _Rig(_ops(2))..acceptAll();
      rig.engine.setTripScreen(true);

      expect(await rig.run(), _held(HoldReason.trip));
      expect(rig.api.log, isEmpty);

      rig.engine.setTripScreen(false);
      await rig.engine.idle;
      expect(rig.engine.snapshot.lastOutcome, isA<PassDone>());
      expect(rig.batchSizes, [2]);
      expect(rig.economy.pendingCount, 0);
    });

    test('background holds it; a resume asks for one', () async {
      final rig = _Rig(_ops(1))..acceptAll();
      rig.engine.setForeground(false);

      expect(await rig.run(), _held(HoldReason.background));
      expect(rig.api.log, isEmpty);

      rig.engine.setForeground(true);
      await rig.engine.idle;
      expect(rig.batchSizes, [1]);
    });

    test('maintenance holds it until the next resume', () async {
      final rig = _Rig(_ops(1));
      rig.api
        ..reply('POST', ApiPaths.sync, [
          apiFail(503, 'maintenance', details: {'until': null}),
        ])
        ..always('POST', ApiPaths.sync, (ApiRequest r) => syncAnswerFor(r));

      expect(await rig.run(), _held(HoldReason.maintenance));
      expect(rig.status.calls, contains('maintenance'));
      expect(await rig.run(SyncTrigger.online), _held(HoldReason.maintenance));
      expect(rig.syncs, hasLength(1));

      rig.engine
        ..setForeground(false)
        ..setForeground(true);
      await rig.engine.idle;
      expect(rig.syncs, hasLength(2));
      expect(rig.economy.pendingCount, 0);
    });

    test('the backoff holds every trigger but online and manual', () async {
      final rig = _Rig(_ops(1));
      rig.api.reply('POST', ApiPaths.sync, [unreachable, unreachable]);
      rig.acceptAll();

      expect(await rig.run(), _failed('noConnection'));
      for (final trigger in [
        SyncTrigger.startup,
        SyncTrigger.resume,
        SyncTrigger.accountActive,
        SyncTrigger.leftTrip,
      ]) {
        rig.engine.request(trigger);
      }
      await rig.engine.idle;
      expect(rig.syncs, hasLength(1), reason: 'held by the backoff');

      expect(await rig.engine.syncNow(), _failed('noConnection'));
      expect(rig.syncs, hasLength(2), reason: 'manual skips it');

      expect(await rig.run(SyncTrigger.online), isA<PassDone>());
      expect(rig.syncs, hasLength(3), reason: 'online resets it');
    });

    test('a pass stops before its next request when a trip opens, and the '
        'answer that lands then waits', () async {
      final rig = _Rig(_ops(150));
      final gate = Completer<void>();
      rig.api.reply('POST', ApiPaths.sync, [
        FakeReply.held((ApiRequest r) => syncAnswerFor(r), gate),
      ]);
      rig.acceptAll();

      rig.engine.request(SyncTrigger.startup);
      await pumpEventQueue();
      expect(rig.syncs, hasLength(1));
      rig.engine.setTripScreen(true);
      gate.complete();
      await rig.engine.idle;

      expect(rig.engine.snapshot.lastOutcome, _held(HoldReason.trip));
      expect(rig.syncs, hasLength(1));
      expect(rig.economy.pendingCount, 150, reason: 'nothing applied');

      rig.engine.setTripScreen(false);
      await rig.engine.idle;
      expect(rig.batchSizes, [100, 100, 50]);
      expect(sentIds(rig.syncs[1]), sentIds(rig.syncs[0]));
      expect(rig.economy.pendingCount, 0);
      expect(rig.economy.answersApplied.values, everyElement(1));
    });
  });

  group('triggers', () {
    test('each trigger starts a pass', () async {
      final rig = _Rig(const [])..acceptAll();
      var seq = 0;
      for (final trigger in [
        SyncTrigger.startup,
        SyncTrigger.accountActive,
        SyncTrigger.resume,
        SyncTrigger.online,
        SyncTrigger.leftTrip,
        SyncTrigger.manual,
        SyncTrigger.retry,
      ]) {
        rig.economy.record([_op(++seq)]);
        expect(await rig.run(trigger), isA<PassDone>(), reason: '$trigger');
        expect(rig.syncs, hasLength(seq), reason: '$trigger');
      }
    });

    test('opsRecorded waits 2 s, and each new one restarts the wait', () async {
      final rig = _Rig(_ops(1))..acceptAll();

      rig.engine.request(SyncTrigger.opsRecorded);
      await rig.elapse(const Duration(milliseconds: 1000));
      rig.engine.request(SyncTrigger.opsRecorded);
      await rig.elapse(const Duration(milliseconds: 1999));
      expect(rig.api.log, isEmpty);

      await rig.elapse(const Duration(milliseconds: 1));
      expect(rig.syncs, hasLength(1));
    });

    test('triggers during a pass give exactly one more pass', () async {
      final rig = _Rig(_ops(1));
      final gate = Completer<void>();
      rig.api.reply('POST', ApiPaths.sync, [
        FakeReply.held((ApiRequest r) => syncAnswerFor(r), gate),
      ]);
      rig.acceptAll();

      rig.engine.request(SyncTrigger.startup);
      await pumpEventQueue();
      rig.economy.record([_op(2)]);
      rig.engine
        ..request(SyncTrigger.resume)
        ..request(SyncTrigger.online)
        ..request(SyncTrigger.accountActive);
      gate.complete();
      await rig.engine.idle;
      await pumpEventQueue();

      expect(rig.outcomes, hasLength(2));
      expect(rig.batchSizes, [1, 1]);
      expect(rig.economy.pendingCount, 0);
    });
  });

  group('spacing and backoff', () {
    test('at least 1 s between an answer and the next batch', () async {
      final rig = _Rig(_ops(250), latency: const Duration(milliseconds: 300));
      final answeredAt = <int>[];
      rig.api.always('POST', ApiPaths.sync, (ApiRequest r) {
        answeredAt.add(rig.time.now);
        return syncAnswerFor(r);
      });

      await rig.run();

      expect(answeredAt, hasLength(3));
      for (var i = 1; i < answeredAt.length; i++) {
        // The answer, 1 s, then the next request's 300 ms.
        expect(answeredAt[i] - answeredAt[i - 1], greaterThanOrEqualTo(1300));
      }
    });

    test('2, 4, 8 … up to 300 s, each ±20%', () async {
      final rig = _Rig(_ops(1));
      rig.api.always('POST', ApiPaths.sync, unreachable);

      var expected = 2000;
      for (var n = 1; n <= 12; n++) {
        if (n == 1) await rig.run();
        final failed = rig.engine.snapshot.lastOutcome! as PassFailed;
        final wait = failed.retryAtMs - rig.time.now;
        expect(wait, inInclusiveRange(expected * 0.8, expected * 1.2));
        await rig.elapse(Duration(milliseconds: wait));
        expected = min(expected * 2, 300000);
      }
      expect(rig.syncs, hasLength(13));
    });

    test('a long run of failures never overflows the wait', () async {
      final rig = _Rig(_ops(1));
      rig.api.always('POST', ApiPaths.sync, unreachable);

      for (var n = 1; n <= 80; n++) {
        if (n == 1) await rig.run();
        final failed = rig.engine.snapshot.lastOutcome! as PassFailed;
        final wait = failed.retryAtMs - rig.time.now;
        expect(wait, inInclusiveRange(2000 * 0.8, 300000 * 1.2), reason: '$n');
        await rig.elapse(Duration(milliseconds: wait));
      }
      expect(rig.syncs, hasLength(81));
    });

    test('the retry is never held by the backoff it ends', () async {
      final rig = _Rig(_ops(1));
      rig.api.reply('POST', ApiPaths.sync, [unreachable]);
      rig.acceptAll();

      expect(await rig.run(), _failed('noConnection'));
      // A timer that fires a tick before the backoff's clock says so.
      expect(await rig.run(SyncTrigger.retry), isA<PassDone>());
      expect(rig.syncs, hasLength(2));
    });

    test('a pass that throws is reported and backs off, and the retry '
        'runs', () async {
      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previous);
      final rig = _Rig(_ops(1));
      rig.api.reply('POST', ApiPaths.sync, [
        (ApiRequest r) => throw const FileSystemException('disk I/O error'),
      ]);
      rig.acceptAll();

      final failed = (await rig.run())! as PassFailed;

      expect(failed.code, 'internal');
      expect(reported.single.library, 'sync');
      expect(reported.single.exception, isA<FileSystemException>());
      await rig.elapse(Duration(milliseconds: failed.retryAtMs - rig.time.now));
      expect(rig.economy.pendingCount, 0);
    });

    test('Retry-After is a floor', () async {
      final rig = _Rig(_ops(1));
      rig.api.reply('POST', ApiPaths.sync, [
        apiFail(429, 'rate_limited', retryAfter: const Duration(seconds: 30)),
      ]);

      final failed = (await rig.run())! as PassFailed;
      expect(failed.code, 'rate_limited');
      expect(failed.retryAtMs - rig.time.now, greaterThanOrEqualTo(30000));
    });

    test('a success resets it', () async {
      final rig = _Rig(_ops(1));
      rig.api.reply('POST', ApiPaths.sync, [
        unreachable,
        unreachable,
        (ApiRequest r) => syncAnswerFor(r),
        unreachable,
      ]);

      await rig.engine.syncNow();
      await rig.engine.syncNow();
      expect(await rig.engine.syncNow(), isA<PassDone>());
      expect(rig.engine.snapshot.backoffUntilMs, isNull);

      rig.economy.record([_op(2)]);
      final failed = (await rig.engine.syncNow()) as PassFailed;
      expect(failed.retryAtMs - rig.time.now, inInclusiveRange(1600, 2400));
    });

    test('a failed account creation backs off; its 429 waits at least '
        'retry_after_s', () async {
      final rig = _Rig(_ops(1));
      rig.account.sessionOk = false;

      final first = (await rig.run())! as PassFailed;
      expect(first.code, 'account');
      expect(first.retryAtMs - rig.time.now, inInclusiveRange(1600, 2400));

      rig.account.signInAfterElapsedMs = rig.time.now + 45000;
      final second = (await rig.engine.syncNow()) as PassFailed;
      expect(second.retryAtMs - rig.time.now, greaterThanOrEqualTo(45000));
      expect(rig.api.log, isEmpty);
    });
  });

  group('a backlog (SC-005)', () {
    /// B03's limits: 60 syncs per player in any 60 s, a 256 KB body.
    /// Returns when each accepted sync came.
    List<int> b03(_Rig rig) {
      final at = <int>[];
      rig.api.always('POST', ApiPaths.sync, (ApiRequest r) {
        final now = rig.time.now;
        if (utf8.encode(jsonEncode(r.body)).length > 256 * 1024) {
          return apiFail(413, 'payload_too_large');
        }
        if (at.where((t) => t > now - 60000).length >= 60) {
          return apiFail(
            429,
            'rate_limited',
            retryAfter: const Duration(seconds: 10),
          );
        }
        at.add(now);
        return syncAnswerFor(r);
      });
      return at;
    }

    test('5,000 operations: no 429 or 413, ≤ 50 batches, ≤ 120 s', () async {
      final rig = _Rig(
        _playMix(5000, resultBytes: 600),
        latency: const Duration(milliseconds: 300),
      );
      final accepted = b03(rig);

      await rig.engine.syncNow();

      expect(rig.economy.pendingCount, 0);
      expect(rig.syncs.length, lessThanOrEqualTo(50));
      expect(accepted, hasLength(rig.syncs.length), reason: 'none refused');
      expect(rig.time.now, lessThanOrEqualTo(120000));
    });

    test('with every result at 8 KB: still no 429 or 413', () async {
      final rig = _Rig(
        _playMix(5000, resultBytes: 8000),
        latency: const Duration(milliseconds: 300),
      );
      final accepted = b03(rig);

      await rig.engine.syncNow();

      expect(rig.economy.pendingCount, 0);
      expect(accepted, hasLength(rig.syncs.length), reason: 'none refused');
    });
  });

  group('refusals (R13)', () {
    for (final (status, code) in [
      (400, 'batch_too_large'),
      (413, 'payload_too_large'),
    ]) {
      test('$status $code halves the batch', () async {
        final rig = _Rig(_ops(4));
        rig.api.reply('POST', ApiPaths.sync, [apiFail(status, code)]);
        rig.acceptAll();

        expect(await rig.run(), isA<PassDone>());
        expect(rig.batchSizes, [4, 2, 2]);
        expect(rig.economy.pendingCount, 0);
      });

      test('$status $code on one operation sets it aside', () async {
        final ops = _ops(2);
        final rig = _Rig(ops);
        rig.api.reply('POST', ApiPaths.sync, [
          apiFail(status, code),
          apiFail(status, code),
        ]);
        rig.acceptAll();

        await rig.run();

        expect(rig.batchSizes, [2, 1, 1]);
        expect(rig.economy.reasonOf(ops[0]), 'payload_too_large');
        expect(rig.economy.statusOf(ops[1]), SyncStatus.accepted);
        expect(
          rig.events.whereType<OpSetAside>().single.txnId,
          ops[0].op.txnId.value,
        );
      });
    }

    test('validation_error naming ops.N sets N aside', () async {
      final ops = _ops(3);
      final rig = _Rig(ops);
      rig.api.reply('POST', ApiPaths.sync, [
        apiFail(
          400,
          'validation_error',
          details: {
            'fields': {
              'ops.1.payload.sku_id': ['unknown'],
            },
          },
        ),
      ]);
      rig.acceptAll();

      expect(await rig.run(), isA<PassDone>());
      expect(rig.economy.reasonOf(ops[1]), 'validation_error');
      expect(sentIds(rig.syncs[1]), [
        ops[0].op.txnId.value,
        ops[2].op.txnId.value,
      ]);
      expect(rig.economy.pendingCount, 0);
    });

    for (final (status, code) in [
      (400, 'validation_error'),
      (415, 'unsupported_media_type'),
      (406, 'not_acceptable'),
    ]) {
      test(
        '$status $code naming no operation holds until the next launch',
        () async {
          final rig = _Rig(_ops(1));
          rig.api.reply('POST', ApiPaths.sync, [apiFail(status, code)]);
          rig.acceptAll();

          expect(await rig.run(), _held(HoldReason.refused));
          expect(await rig.run(SyncTrigger.online), _held(HoldReason.refused));
          expect(await rig.engine.syncNow(), _held(HoldReason.refused));
          expect(rig.syncs, hasLength(1));
          expect(rig.engine.snapshot.heldUntilLaunch, isTrue);
          expect(rig.economy.pendingCount, 1);
        },
      );
    }

    test('426 holds until the next launch and reports the update', () async {
      final rig = _Rig(_ops(1));
      rig.api.reply('POST', ApiPaths.sync, [apiFail(426, 'client_outdated')]);

      expect(await rig.run(), _held(HoldReason.refused));
      expect(rig.status.calls, contains('clientOutdated'));
      expect(rig.engine.snapshot.lastError, 'client_outdated');
    });

    test('503 maintenance reports its details', () async {
      final rig = _Rig(_ops(1));
      rig.api.reply('POST', ApiPaths.sync, [
        apiFail(503, 'maintenance', details: {'until': '2026-10-27T10:00:00Z'}),
      ]);

      expect(await rig.run(), _held(HoldReason.maintenance));
      expect(rig.status.maintenanceDetails, {'until': '2026-10-27T10:00:00Z'});
    });

    for (final (result, code) in <(ApiResult, String)>[
      (apiFail(503, 'dependency_unavailable'), 'dependency_unavailable'),
      (apiFail(500, 'server_error'), 'server_error'),
      (apiFail(502, 'bad_gateway'), 'bad_gateway'),
      (unreachable, 'noConnection'),
      (const ApiUnreachable(UnreachableKind.timeout), 'timeout'),
      (apiOk({'state_version': 'x'}), 'server_error'),
    ]) {
      test('$code backs off, and the operations stay pending', () async {
        final rig = _Rig(_ops(2));
        rig.api.reply('POST', ApiPaths.sync, [result]);

        expect(await rig.run(), _failed(code));
        expect(rig.economy.pendingCount, 2);
        expect(rig.engine.snapshot.backoffUntilMs, isNotNull);
        expect(
          rig.status.calls.last,
          result is ApiUnreachable ? 'unreachable' : 'reached',
        );
      });
    }

    test('403 account_deleted holds', () async {
      final rig = _Rig(_ops(1));
      rig.api.reply('POST', ApiPaths.sync, [apiFail(403, 'account_deleted')]);

      expect(await rig.run(), _held(HoldReason.deleted));
    });
  });

  test('a lost answer: the same ids again, each answer applied once', () async {
    final ops = _ops(3);
    final rig = _Rig(ops);
    final seen = <String>[];
    ApiOk answer(ApiRequest r) {
      seen.addAll(sentIds(r));
      return syncAnswerFor(r, rejected: {ops[1].op.txnId.value: 'not_owned'});
    }

    rig.api
      ..reply('POST', ApiPaths.sync, [FakeReply.dropped(answer)])
      ..always('POST', ApiPaths.sync, answer);

    expect(await rig.run(), _failed('timeout'));
    expect(rig.economy.pendingCount, 3);
    expect(await rig.run(SyncTrigger.online), isA<PassDone>());

    final ids = [for (final op in ops) op.op.txnId.value];
    expect(seen, [...ids, ...ids]);
    expect(rig.economy.answersApplied, {for (final id in ids) id: 1});
    expect(rig.economy.reasonOf(ops[1]), 'not_owned');
  });

  group('the toast (R14)', () {
    test('once after a pass with visible rejections', () async {
      final ops = _ops(150);
      final rig = _Rig(ops);
      rig.api.always(
        'POST',
        ApiPaths.sync,
        (ApiRequest r) => syncAnswerFor(
          r,
          rejected: {
            ops[3].op.txnId.value: 'insufficient_funds',
            ops[120].op.txnId.value: 'insufficient_funds',
          },
        ),
      );

      await rig.run();

      expect(rig.events.whereType<OpRejected>(), hasLength(2));
      expect(rig.toasts, 1);
    });

    test('not for trip_revive or traffic_jam rewards alone', () async {
      final ops = [
        _op(1, type: OpType.adReward, payload: {'ad_placement': 'trip_revive'}),
        _op(2, type: OpType.adReward, payload: {'ad_placement': 'traffic_jam'}),
      ];
      final rig = _Rig(ops);
      rig.api.always(
        'POST',
        ApiPaths.sync,
        (ApiRequest r) => syncAnswerFor(
          r,
          rejected: {for (final op in ops) op.op.txnId.value: 'ad_cap'},
        ),
      );

      await rig.run();

      expect(rig.events.whereType<OpRejected>(), hasLength(2));
      expect(rig.toasts, 0);
    });

    // M07 research R7: a refused name is asked again on Home instead.
    test('not for a refused name; its reason is kept', () async {
      final name = _op(
        1,
        type: OpType.settingsUpdate,
        payload: {'display_name': 'x'},
      );
      final rig = _Rig([name]);
      rig.api.always(
        'POST',
        ApiPaths.sync,
        (ApiRequest r) => syncAnswerFor(
          r,
          rejected: {name.op.txnId.value: 'validation_error'},
        ),
      );

      await rig.run();

      expect(rig.events.whereType<OpRejected>(), hasLength(1));
      expect(rig.toasts, 0);
      expect(rig.economy.statusOf(name), SyncStatus.rejected);
      expect(rig.economy.reasonOf(name), 'validation_error');
    });

    test('but for a refused tutorial gift', () async {
      final gift = _op(1, type: OpType.tutorialGift, payload: const {});
      final rig = _Rig([gift]);
      rig.api.always(
        'POST',
        ApiPaths.sync,
        (ApiRequest r) => syncAnswerFor(
          r,
          rejected: {gift.op.txnId.value: 'already_granted'},
        ),
      );

      await rig.run();

      expect(rig.toasts, 1);
    });

    test('not for account_changed', () async {
      final rig = _Rig(_ops(2), basePlayer: otherPlayer)..acceptAll();
      rig.api.always('GET', ApiPaths.state, apiOk(stateJson()));

      await rig.run();

      expect(rig.events.whereType<OpsDropped>().single.count, 2);
      expect(rig.toasts, 0);
    });

    test('never on the trip route: it waits for the route to close', () async {
      final ops = _ops(150);
      final rig = _Rig(ops);
      final gate = Completer<void>();
      rig.api.reply('POST', ApiPaths.sync, [
        (ApiRequest r) => syncAnswerFor(
          r,
          rejected: {ops[0].op.txnId.value: 'insufficient_funds'},
        ),
        FakeReply.held((ApiRequest r) => syncAnswerFor(r), gate),
      ]);
      rig.acceptAll();

      rig.engine.request(SyncTrigger.startup);
      for (var i = 0; i < 50 && rig.syncs.length < 2; i++) {
        await pumpEventQueue();
      }
      rig.engine.setTripScreen(true);
      gate.complete();
      await rig.engine.idle;
      await pumpEventQueue();
      expect(rig.engine.snapshot.lastOutcome, _held(HoldReason.trip));
      expect(rig.toasts, 0);

      rig.engine.setTripScreen(false);
      await rig.engine.idle;
      await pumpEventQueue();
      expect(rig.toasts, 1);
    });
  });

  group('the full state', () {
    test('another player in the base: taken before anything is sent', () async {
      final rig = _Rig(_ops(2), basePlayer: otherPlayer)..acceptAll();
      rig.api.always('GET', ApiPaths.state, apiOk(stateJson(stateVersion: 9)));

      expect(await rig.run(), isA<PassIdle>());
      expect(rig.api.log.first.path, ApiPaths.state);
      expect(rig.states.calls.single.why, StateWhy.account);
      expect(rig.economy.baseInfo, (stateVersion: 9, playerId: syncPlayer));
      expect(rig.syncs, isEmpty, reason: 'both dropped');
      expect(rig.events.whereType<StateTaken>().single.why, StateWhy.account);
    });

    test('a stale answer takes it', () async {
      final rig = _Rig(_ops(1));
      rig.api
        ..always(
          'POST',
          ApiPaths.sync,
          (ApiRequest r) => syncAnswerFor(r, stale: true),
        )
        ..always('GET', ApiPaths.state, apiOk(stateJson(stateVersion: 12)));

      await rig.run();

      expect(rig.states.calls.single.why, StateWhy.stale);
      expect(rig.economy.baseInfo.stateVersion, 12);
    });

    test('an accepted operation the fold left out takes it', () async {
      final ops = _ops(1);
      final rig = _Rig(ops)..acceptAll();
      rig.economy.leftOut = [ops.single.op.txnId];
      rig.api.always('GET', ApiPaths.state, apiOk(stateJson()));

      await rig.run();

      expect(rig.states.calls.single.why, StateWhy.diverged);
    });

    test('the server ahead with nothing pending takes it', () async {
      final rig = _Rig(const [], baseVersion: 3)..serverVersion = 10;
      rig.api.always('GET', ApiPaths.state, apiOk(stateJson(stateVersion: 10)));

      await rig.run();
      expect(rig.states.calls.single.why, StateWhy.ahead);

      await rig.run();
      expect(rig.states.calls, hasLength(1), reason: 'in step now');
    });

    test('a pending restore takes it first, once', () async {
      final rig = _Rig(_ops(1), baseVersion: null, basePlayer: null)
        ..acceptAll();
      rig.api.always('GET', ApiPaths.state, apiOk(stateJson()));

      rig.engine.requestRestore();
      await rig.engine.idle;
      await rig.run();

      expect(rig.api.log.first.path, ApiPaths.state);
      expect(rig.states.calls.map((c) => c.why), [StateWhy.firstOpen]);
      expect(rig.syncs, hasLength(1));
    });

    test('a restore waits for the trip route to close', () async {
      final rig = _Rig(_ops(1), baseVersion: null, basePlayer: null)
        ..acceptAll();
      rig.api.always('GET', ApiPaths.state, apiOk(stateJson(stateVersion: 7)));
      rig.engine.setTripScreen(true);

      rig.engine.requestRestore();
      await rig.engine.idle;
      expect(rig.api.log, isEmpty);
      expect(rig.states.calls, isEmpty);

      rig.engine.setTripScreen(false);
      await rig.engine.idle;
      await pumpEventQueue();
      expect(rig.api.log.map((r) => r.path), [ApiPaths.state, ApiPaths.sync]);
      expect(rig.events.whereType<StateTaken>().single.why, StateWhy.firstOpen);
    });

    test('a refused state fetch backs off', () async {
      final rig = _Rig(const [])..serverVersion = 10;
      rig.api.reply('GET', ApiPaths.state, [unreachable]);

      expect(await rig.run(), _failed('noConnection'));
      expect(rig.states.calls, isEmpty);
    });
  });

  group('account changes', () {
    test(
      'operations recorded before any account go out for the first player',
      () async {
        final rig = _Rig(_ops(2), baseVersion: null, basePlayer: null)
          ..acceptAll();

        await rig.run();

        expect(rig.states.calls, isEmpty);
        expect(rig.batchSizes, [2]);
        expect(rig.economy.baseInfo.playerId, syncPlayer);
      },
    );

    test('another player between two batches: the rest waits for its '
        'state, and is dropped', () async {
      final rig = _Rig(_ops(150));
      rig.api
        ..always('POST', ApiPaths.sync, (ApiRequest r) {
          // A token answer for another player lands while this one is out.
          rig.account.playerId = otherPlayer;
          return syncAnswerFor(r);
        })
        ..always('GET', ApiPaths.state, apiOk(stateJson(stateVersion: 9)));

      await rig.run();

      expect(rig.batchSizes, [maxBatchOps]);
      expect(rig.states.calls.single.why, StateWhy.account);
      expect(rig.states.calls.single.playerId, otherPlayer);
      expect(rig.events.whereType<OpsDropped>().single.count, 50);
      expect(rig.economy.baseInfo, (stateVersion: 9, playerId: otherPlayer));
    });

    test('a state fetched with another player\'s tokens is taken as '
        'theirs', () async {
      final rig = _Rig(_ops(1));
      var fetches = 0;
      rig.api
        ..always(
          'POST',
          ApiPaths.sync,
          (ApiRequest r) => syncAnswerFor(r, stale: true),
        )
        ..always('GET', ApiPaths.state, (ApiRequest r) {
          if (fetches++ == 0) rig.account.playerId = otherPlayer;
          return apiOk(stateJson(stateVersion: 12));
        });

      await rig.run();

      expect(rig.states.calls.map((c) => (c.why, c.playerId)), [
        (StateWhy.account, otherPlayer),
      ]);
      expect(rig.economy.baseInfo.playerId, otherPlayer);
    });

    test('a session with no player backs off, and sends nothing', () async {
      final rig = _Rig(_ops(1))..acceptAll();
      rig.account.playerId = null;

      expect(await rig.run(), _failed('account'));
      expect(rig.api.log, isEmpty);
    });

    test('a state fetch refused as account_changed: no backoff, and the '
        'next pass takes the new player\'s state', () async {
      final rig = _Rig(_ops(1), basePlayer: otherPlayer);
      rig.api.reply('GET', ApiPaths.state, [
        (ApiRequest r) {
          rig.account.playerId = _thirdPlayer;
          return const ApiFailure(409, 'account_changed');
        },
        apiOk(stateJson(stateVersion: 9)),
      ]);
      rig.acceptAll();

      await rig.run();

      expect(rig.engine.snapshot.backoffUntilMs, isNull);
      expect(rig.states.calls.map((c) => (c.why, c.playerId)), [
        (StateWhy.account, _thirdPlayer),
      ]);
      expect(rig.economy.baseInfo.playerId, _thirdPlayer);
    });

    test('a batch refused as account_changed: no backoff, and the next '
        'pass takes the new player\'s state', () async {
      final rig = _Rig(_ops(1));
      rig.api
        ..reply('POST', ApiPaths.sync, [
          (ApiRequest r) {
            // The renewal that refused it stored another player's tokens.
            rig.account.playerId = otherPlayer;
            return const ApiFailure(409, 'account_changed');
          },
        ])
        ..always('GET', ApiPaths.state, apiOk(stateJson(stateVersion: 9)));

      await rig.run();

      expect(rig.syncs, hasLength(1));
      expect(rig.states.calls.single.why, StateWhy.account);
      expect(rig.outcomes, everyElement(isA<PassIdle>()));
      expect(rig.events.whereType<OpsDropped>().single.count, 1);
    });
  });

  test('every request names the player it is for', () async {
    final rig = _Rig(_ops(1))
      ..acceptAll()
      ..serverVersion = 10;
    rig.api.always('GET', ApiPaths.state, apiOk(stateJson(stateVersion: 10)));

    await rig.run();

    expect(rig.api.log.map((r) => r.path), [ApiPaths.sync, ApiPaths.state]);
    expect(
      [for (final r in rig.api.log) r.forPlayer],
      [syncPlayer, syncPlayer],
    );
  });

  group('flush', () {
    test('sends until nothing is pending', () async {
      final rig = _Rig(_ops(250))..acceptAll();

      expect(await rig.engine.flush(), isTrue);
      expect(rig.economy.pendingCount, 0);
    });

    test('false when the server stays out of reach', () async {
      final rig = _Rig(_ops(1));
      rig.api.always('POST', ApiPaths.sync, unreachable);

      expect(await rig.engine.flush(), isFalse);
      expect(rig.economy.pendingCount, 1);
    });
  });

  test('syncNow runs the forced bootstrap first', () async {
    final order = <String>[];
    late _Rig rig;
    rig = _Rig(_ops(1), bootstrap: () async => order.add('bootstrap'));
    rig.api.always('POST', ApiPaths.sync, (ApiRequest r) {
      order.add('sync');
      return syncAnswerFor(r);
    });

    await rig.engine.syncNow();

    expect(order, ['bootstrap', 'sync']);
  });
}
