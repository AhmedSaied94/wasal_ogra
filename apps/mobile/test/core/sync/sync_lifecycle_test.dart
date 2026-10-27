import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/account/domain/account.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/txn_id.dart';
import 'package:wassal/core/network/api_client.dart';
import 'package:wassal/core/sync/bootstrap_service.dart';
import 'package:wassal/core/sync/sync_engine.dart';
import 'package:wassal/core/sync/sync_lifecycle.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../../helpers/account.dart';
import '../../helpers/content.dart';
import '../../helpers/economy.dart';
import '../../helpers/fake_api.dart';
import '../../helpers/sync.dart';

// The sync's gates and triggers from the app's life (specs/011-m06-
// identity-sync, contracts/sync.md "Gates", research R9, R14).

LedgerOp _op(int seq) => LedgerOp(
  seq: seq,
  op: Op(
    txnId: TxnId.parse(
      '0192f3a1-7b2c-7d4e-8f00-${seq.toRadixString(16).padLeft(12, '0')}',
    ),
    type: OpType.spendBonat,
    payload: const {'sku_kind': 'booster', 'sku_id': 'change_bag'},
    occurredAtMs: 1792627200000 + seq,
    contentVersion: 1,
    fuelMax: 5,
    fuelRegenMinutes: 20,
  ),
  syncStatus: SyncStatus.pending,
);

final class _Rig {
  _Rig() {
    api.always('POST', ApiPaths.sync, (ApiRequest r) => syncAnswerFor(r));
    engine = SyncRunner(
      account: FakeSyncAccount(),
      api: PlainAuthorizedApi(api),
      economy: economy,
      states: RecordingStates(economy),
      time: time,
      serverStateVersion: () => null,
      random: Random(1),
    );
    router = GoRouter(
      initialLocation: '/home',
      routes: [
        for (final path in ['/home', '/trip/:tripId', '/trip/:tripId/result'])
          GoRoute(path: path, builder: (_, _) => const SizedBox.expand()),
      ],
    );
  }

  final time = FakeSyncTime();
  final api = FakeApi();
  final economy = MemoryEconomy(const []);
  final connectivity = FakeConnectivitySource();
  final statuses = StreamController<AccountStatus>.broadcast();
  late final SyncRunner engine;
  late final GoRouter router;
  late final SyncLifecycle lifecycle;

  BootstrapService? bootstrap;
  AccountStatus status = AccountStatus.active;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
      ),
    );
    lifecycle = SyncLifecycle(
      router: router,
      engine: engine,
      connectivity: connectivity,
      pendingCounts: economy.pendingCounts,
      pendingCount: economy.pendingCount,
      statuses: statuses.stream,
      status: () => status,
      bootstrap: bootstrap,
    );
    addTearDown(() {
      lifecycle.dispose();
      engine.dispose();
      unawaited(statuses.close());
    });
    await settle(tester);
  }

  /// Lets the passes started end.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() async {
      await pumpEventQueue();
      await engine.idle;
      await pumpEventQueue();
    });
    await tester.pump();
  }

  int get syncs => api.to(ApiPaths.sync).length;
}

void main() {
  test('isTripRoute: the trip screen only', () {
    expect(isTripRoute('/trip/line_hay.01'), isTrue);
    expect(isTripRoute('/trip/line_hay.01/result'), isFalse);
    expect(isTripRoute('/home/pre-trip/line_hay.01'), isFalse);
    expect(isTripRoute('/home'), isFalse);
  });

  testWidgets('a pass at the start', (tester) async {
    final rig = _Rig();
    rig.economy.record([_op(1)]);
    await rig.pump(tester);

    expect(rig.syncs, 1);
    expect(rig.economy.pendingCount, 0);
  });

  testWidgets('the trip route holds the sync; leaving it sends', (
    tester,
  ) async {
    final rig = _Rig();
    await rig.pump(tester);
    rig.router.go('/trip/line_hay.01');
    await tester.pumpAndSettle();

    rig.economy.record([_op(1)]);
    rig.engine.request(SyncTrigger.manual);
    await rig.settle(tester);
    expect(rig.syncs, 0);

    rig.router.go('/trip/line_hay.01/result');
    await tester.pumpAndSettle();
    await rig.settle(tester);
    expect(rig.syncs, 1, reason: 'the result route is no gate');
  });

  testWidgets('a new operation asks for a pass, debounced', (tester) async {
    final rig = _Rig();
    await rig.pump(tester);

    rig.economy.record([_op(1)]);
    await rig.settle(tester);
    expect(rig.syncs, 0);

    rig.time.elapse(opsDebounce);
    await rig.settle(tester);
    expect(rig.syncs, 1);

    // The answer lowered the count: no pass for that.
    rig.time.elapse(opsDebounce);
    await rig.settle(tester);
    expect(rig.syncs, 1);
  });

  testWidgets('a connection and an active account ask for a pass', (
    tester,
  ) async {
    final rig = _Rig();
    await rig.pump(tester);

    rig.economy.record([_op(1)]);
    rig.connectivity.set(true);
    await rig.settle(tester);
    expect(rig.syncs, 1);

    rig.economy.record([_op(2)]);
    rig.statuses.add(AccountStatus.active);
    await rig.settle(tester);
    expect(rig.syncs, 2);

    rig.connectivity.set(false);
    rig.statuses.add(AccountStatus.deleted);
    rig.economy.record([_op(3)]);
    rig.engine.request(SyncTrigger.resume);
    await rig.settle(tester);
    expect(rig.syncs, 3, reason: 'resume');
  });

  testWidgets('the background holds it; a resume sends', (tester) async {
    final rig = _Rig();
    await rig.pump(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);

    rig.economy.record([_op(1)]);
    rig.engine.request(SyncTrigger.manual);
    await rig.settle(tester);
    expect(rig.syncs, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await rig.settle(tester);
    expect(rig.syncs, 1);
  });

  testWidgets('a bootstrap runs before the start\'s pass, not for an absent '
      'account', (tester) async {
    for (final status in [AccountStatus.active, AccountStatus.none]) {
      final rig = _Rig()..status = status;
      await tester.runAsync(() async {
        final economy = await testEconomy();
        rig.bootstrap = BootstrapService(
          api: PlainAuthorizedApi(rig.api),
          store: await testAccountStore(economy),
          economy: rig.economy,
          writeProfile: ({displayName, driverLevel, providers}) async {},
          checkContent: () async {},
          activeContentVersion: () => 1,
          nowMs: economy.clock.nowMs,
          elapsedMs: () => economy.uptime.elapsedRealtimeMs,
        );
      });
      rig.api.always('GET', ApiPaths.bootstrap, apiOk(bootstrapJson()));
      rig.economy.record([_op(1)]);
      await rig.pump(tester);
      await rig.settle(tester);

      expect(rig.api.log.map((r) => r.path), [
        if (status == AccountStatus.active) ApiPaths.bootstrap,
        ApiPaths.sync,
      ], reason: '$status');
    }
  });

  testWidgets('a visible rejection shows the toast', (tester) async {
    final rig = _Rig();
    final op = _op(1);
    rig.api.reply('POST', ApiPaths.sync, [
      (ApiRequest r) =>
          syncAnswerFor(r, rejected: {op.op.txnId.value: 'insufficient_funds'}),
    ]);
    rig.economy.record([op]);
    await rig.pump(tester);

    expect(find.text('رصيدك اتظبط على آخر حساب'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 10));
  });
}
