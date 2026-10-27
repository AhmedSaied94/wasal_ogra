// The account's providers (specs/011-m06-identity-sync, contracts/
// account.md "Providers"). This file only constructs the stores and the
// service; every write of `account` and `server_info` goes through the
// store.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wassal/core/account/account_service.dart';
import 'package:wassal/core/account/authorized_api.dart';
import 'package:wassal/core/account/domain/account.dart';
import 'package:wassal/core/account/drift_account_store.dart';
import 'package:wassal/core/account/install_id_store.dart';
import 'package:wassal/core/account/session_store.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/network/api_client.dart';
import 'package:wassal/core/platform/app_info.dart';
import 'package:wassal/core/platform/connectivity.dart';
import 'package:wassal/core/sync/server_status.dart';
import 'package:wassal/core/sync/state_applier.dart';
import 'package:wassal/features/trip/trip_providers.dart';

part 'account_providers.g.dart';

/// The only writer of `account` and `server_info`, loaded during startup so
/// its rows read synchronously and offline (FR-015).
@Riverpod(keepAlive: true)
Future<DriftAccountStore> accountStore(Ref ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final clock = await ref.watch(trustedClockProvider.future);
  final store = DriftAccountStore(db, nowMs: clock.nowMs);
  await store.load();
  return store;
}

/// Block Store and its file on Android, the keychain on iOS (R1).
@Riverpod(keepAlive: true)
InstallIdStore installIdStore(Ref ref) => switch (defaultTargetPlatform) {
  TargetPlatform.android => AndroidInstallIdStore(),
  TargetPlatform.iOS => KeychainInstallIdStore(),
  _ => MemoryInstallIdStore(),
};

@Riverpod(keepAlive: true)
SessionStore sessionStore(Ref ref) => switch (defaultTargetPlatform) {
  TargetPlatform.android || TargetPlatform.iOS => SecureSessionStore(),
  _ => MemorySessionStore(),
};

/// Read after the database, the clock and the economy are open: a
/// returning player's first open takes its state (R6).
@Riverpod(keepAlive: true)
Future<ServerAccountService> accountService(Ref ref) async {
  final store = await ref.watch(accountStoreProvider.future);
  final clock = await ref.watch(trustedClockProvider.future);
  final info = await ref.watch(appInfoProvider.future);
  final economy = await ref.watch(economyProvider.future);
  late final ServerAccountService service;
  service = ServerAccountService(
    // Every answer tells what the player is shown of the server (R17–R19).
    api: ObservedApiClient(
      ref.watch(apiClientProvider),
      ref.read(serverStatusProvider.notifier).observe,
    ),
    installIds: ref.watch(installIdStoreProvider),
    sessions: ref.watch(sessionStoreProvider),
    store: store,
    connectivity: ref.watch(connectivitySourceProvider),
    nowMs: clock.nowMs,
    elapsedMs: clock.elapsedMs,
    platform: info.platform,
    states: ServerStateApplier(
      economy: economy,
      trips: ref.watch(tripRecordsProvider),
      content: () => loadedContentSource(ref),
      writeProfile: ({displayName, driverLevel}) => service.updateProfile(
        displayName: displayName,
        driverLevel: driverLevel,
      ),
    ),
  );
  ref.onDispose(service.dispose);
  return service;
}

/// Every player endpoint goes through it (contracts/api-client.md).
@Riverpod(keepAlive: true)
AuthorizedApi authorizedApi(Ref ref) =>
    ref.watch(accountServiceProvider).requireValue.authorized;

/// M14, B09's screens and the debug card.
@Riverpod(keepAlive: true)
Stream<AccountStatus> accountStatus(Ref ref) async* {
  final service = await ref.watch(accountServiceProvider.future);
  yield service.status;
  yield* service.statuses;
}

/// What the server last said of the player: M07, M08, M14.
@Riverpod(keepAlive: true)
Profile? profile(Ref ref) {
  final service = ref.watch(accountServiceProvider).requireValue;
  final changes = service.changes.listen((_) => ref.invalidateSelf());
  ref.onDispose(() => unawaited(changes.cancel()));
  return service.profile;
}

/// The first open's outcome: boot waits for it (R6); M07 routes by it.
@Riverpod(keepAlive: true)
Future<FirstOpenOutcome> firstOpenOutcome(Ref ref) async =>
    (await ref.watch(accountServiceProvider.future)).firstOpen();

/// A returning player's state, found past the first open's 3 s, was taken
/// (R6): M07 moves the player from the intro to Home.
@Riverpod(keepAlive: true)
Stream<void> progressRestored(Ref ref) async* {
  final service = await ref.watch(accountServiceProvider.future);
  yield* service.restorations;
}
