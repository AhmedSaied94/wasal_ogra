// The sync's providers (specs/011-m06-identity-sync, contracts/sync.md).
// Screens never read them: the engine runs from the app's lifecycle, and
// internal builds' debug card reads its snapshot.
import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wassal/core/account/account_providers.dart';
import 'package:wassal/core/account/domain/account_record.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/platform/connectivity.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/core/sync/bootstrap_service.dart';
import 'package:wassal/core/sync/comeback_gift.dart';
import 'package:wassal/core/sync/server_status.dart';
import 'package:wassal/core/sync/domain/wire/bootstrap.dart';
import 'package:wassal/core/sync/state_applier.dart';
import 'package:wassal/core/sync/sync_engine.dart';
import 'package:wassal/core/sync/sync_lifecycle.dart';
import 'package:wassal/core/sync/sync_time.dart';
import 'package:wassal/features/trip/trip_providers.dart';

part 'sync_providers.g.dart';

/// The bootstrap (research R15). The sync's lifecycle runs it before its
/// passes; «sync now» forces it.
@Riverpod(keepAlive: true)
Future<BootstrapService> bootstrapService(Ref ref) async {
  final account = await ref.watch(accountServiceProvider.future);
  final store = await ref.watch(accountStoreProvider.future);
  final clock = await ref.watch(trustedClockProvider.future);
  await ref.watch(economyProvider.future);
  final service = BootstrapService(
    api: account.authorized,
    store: store,
    economy: ref.watch(economySyncProvider),
    writeProfile: account.updateProfile,
    checkContent: () => ref.read(contentUpdaterProvider).check(force: true),
    activeContentVersion: () => ref.read(contentVersionProvider),
    nowMs: clock.nowMs,
    elapsedMs: clock.elapsedMs,
    clients: ref.read(serverStatusProvider.notifier),
  );
  ref.onDispose(service.dispose);
  return service;
}

/// The last bootstrap, cached: synchronous and offline (FR-015). Empty
/// until the account's store is open.
@Riverpod(keepAlive: true)
ServerInfo serverInfo(Ref ref) {
  final bootstrap = ref.watch(bootstrapServiceProvider).value;
  if (bootstrap != null) {
    final changes = bootstrap.infos.listen((_) => ref.invalidateSelf());
    ref.onDispose(() => unawaited(changes.cancel()));
  }
  return ref.watch(accountStoreProvider).value?.serverInfo ?? ServerInfo.empty;
}

/// Neutral before the first bootstrap: M11, M12, M14.
@Riverpod(keepAlive: true)
Entitlements entitlements(Ref ref) =>
    ref.watch(serverInfoProvider).entitlements;

/// M13's daily challenge and reward.
@Riverpod(keepAlive: true)
DailyBlock? dailyBlock(Ref ref) => ref.watch(serverInfoProvider).daily;

/// The comeback gift's guard (research R16): M10's comeback card.
@Riverpod(keepAlive: true)
Future<ComebackGift> comebackGift(Ref ref) async {
  final store = await ref.watch(accountStoreProvider.future);
  final bootstrap = await ref.watch(bootstrapServiceProvider.future);
  final clock = await ref.watch(trustedClockProvider.future);
  await ref.watch(economyProvider.future);
  final gift = await LocalComebackGift.open(
    store: store,
    economy: ref.watch(economySyncProvider),
    infos: bootstrap.infos,
    nowMs: clock.nowMs,
  );
  ref.onDispose(gift.dispose);
  return gift;
}

@Riverpod(keepAlive: true)
Future<SyncRunner> syncEngine(Ref ref) async {
  final account = await ref.watch(accountServiceProvider.future);
  final clock = await ref.watch(trustedClockProvider.future);
  final bootstrap = await ref.watch(bootstrapServiceProvider.future);
  await ref.watch(economyProvider.future);
  final economy = ref.watch(economySyncProvider);
  final engine = SyncRunner(
    account: account,
    api: account.authorized,
    economy: economy,
    states: ServerStateApplier(
      economy: economy,
      trips: ref.watch(tripRecordsProvider),
      content: () => loadedContentSource(ref),
      writeProfile: account.updateProfile,
    ),
    time: RealSyncTime(clock.elapsedMs),
    serverStateVersion: () => bootstrap.stateVersion,
    status: ref.read(serverStatusProvider.notifier),
    bootstrap: () => bootstrap.refresh(force: true),
  );
  account.attachSync(engine);
  ref.onDispose(engine.dispose);
  return engine;
}

/// The engine's gates and triggers. `WassalApp` listens from startup's end
/// to its dispose, which disposes this.
@riverpod
Future<SyncLifecycle> syncLifecycle(Ref ref) async {
  final engine = await ref.watch(syncEngineProvider.future);
  final account = await ref.watch(accountServiceProvider.future);
  final bootstrap = await ref.watch(bootstrapServiceProvider.future);
  final economy = ref.watch(economySyncProvider);
  final lifecycle = SyncLifecycle(
    router: ref.watch(routerProvider),
    engine: engine,
    bootstrap: bootstrap,
    status: () => account.status,
    connectivity: ref.watch(connectivitySourceProvider),
    pendingCounts: economy.pendingCounts,
    pendingCount: economy.pendingCount,
    statuses: account.statuses,
  );
  ref.onDispose(lifecycle.dispose);
  return lifecycle;
}
