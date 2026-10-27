// Account and sync test helpers (specs/011-m06-identity-sync/tasks.md
// T005): memory stores, the route signal, the store launcher, and the
// account store and service on a test economy's real database. Only the
// platform edges are faked.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/account/account_providers.dart';
import 'package:wassal/core/account/account_service.dart';
import 'package:wassal/core/account/domain/account.dart';
import 'package:wassal/core/account/drift_account_store.dart';
import 'package:wassal/core/account/install_id_store.dart';
import 'package:wassal/core/account/session_store.dart';
import 'package:wassal/core/network/api_client.dart';
import 'package:wassal/core/sync/state_applier.dart';
import 'package:wassal/features/trip/data/drift_trip_records.dart';

import 'content.dart' show FakeConnectivitySource;
import 'economy.dart';
import 'fake_api.dart';

export 'package:wassal/core/account/install_id_store.dart'
    show MemoryInstallIdStore;
export 'package:wassal/core/account/session_store.dart' show MemorySessionStore;

/// Whether the trip screen shows, set by hand.
final class FakeRouteSignal {
  final onTripScreen = ValueNotifier<bool>(false);
}

/// The account store on [economy]'s database (schema v3), loaded.
Future<DriftAccountStore> testAccountStore(TestEconomy economy) async {
  final store = DriftAccountStore(economy.db, nowMs: economy.clock.nowMs);
  await store.load();
  return store;
}

/// A UUIDv7 player id; [n] tells them apart.
String playerIdOf(int n) =>
    '0192f1c3-7d1e-7a4b-9c11-${n.toRadixString(16).padLeft(12, '0')}';

/// The install id the tests' account creation sends.
final testInstallId = InstallId.parse('3f2b8c1e-9a4d-4e7f-8b21-5c6d7e8f9a0b');

/// A token answer, as the auth endpoints send it.
Map<String, Object?> tokenJson({
  int player = 1,
  String access = 'access-1',
  String refresh = 'refresh-1',
  int expiresIn = 900,
  List<String> providers = const [],
  bool? created,
}) => {
  'player_id': playerIdOf(player),
  'access': access,
  'refresh': refresh,
  'access_expires_in': expiresIn,
  'providers': providers,
  'created': ?created,
};

/// The account service on a test economy, over [api] and memory stores.
final class TestAccount {
  TestAccount._({
    required this.economy,
    required this.api,
    required this.store,
    required this.sessions,
    required this.installIds,
    required this.connectivity,
    required this.service,
  });

  final TestEconomy economy;
  final FakeApi api;
  final DriftAccountStore store;
  final MemorySessionStore sessions;
  final MemoryInstallIdStore installIds;
  final FakeConnectivitySource connectivity;
  final ServerAccountService service;

  /// The same stores and database, a new service: a relaunch.
  Future<TestAccount> relaunch() => testAccount(
    economy: economy,
    api: api,
    sessions: sessions,
    installIds: installIds,
    connectivity: connectivity,
  );
}

Future<TestAccount> testAccount({
  TestEconomy? economy,
  FakeApi? api,
  MemorySessionStore? sessions,
  MemoryInstallIdStore? installIds,
  FakeConnectivitySource? connectivity,
}) async {
  final e = economy ?? await testEconomy();
  final server = api ?? FakeApi(elapsedMs: () => e.uptime.elapsedRealtimeMs);
  final store = await testAccountStore(e);
  final sessionStore = sessions ?? MemorySessionStore();
  final ids = installIds ?? MemoryInstallIdStore(testInstallId);
  final online = connectivity ?? FakeConnectivitySource();
  late final ServerAccountService service;
  service = ServerAccountService(
    api: server,
    installIds: ids,
    sessions: sessionStore,
    store: store,
    connectivity: online,
    nowMs: e.clock.nowMs,
    elapsedMs: () => e.uptime.elapsedRealtimeMs,
    platform: 'android',
    states: ServerStateApplier(
      economy: e.service,
      trips: DriftTripRecords(e.db),
      content: () => e.content,
      writeProfile: ({displayName, driverLevel}) => service.updateProfile(
        displayName: displayName,
        driverLevel: driverLevel,
      ),
    ),
  );
  addTearDown(service.dispose);
  return TestAccount._(
    economy: e,
    api: server,
    store: store,
    sessions: sessionStore,
    installIds: ids,
    connectivity: online,
    service: service,
  );
}

/// A stored session for player [player], valid for [validFor] of trusted
/// time from [nowMs].
Session sessionFor(
  int nowMs, {
  int player = 1,
  String access = 'access-0',
  String refresh = 'refresh-0',
  Duration validFor = const Duration(minutes: 15),
}) => Session(
  playerId: playerIdOf(player),
  access: access,
  refresh: refresh,
  accessExpiresAtMs: nowMs + validFor.inMilliseconds,
);

/// The bearer each request to [path] carried.
List<String?> bearersTo(FakeApi api, String path) => [
  for (final request in api.to(path)) request.bearer,
];

/// Any authorized call, for the token tests.
const testRead = ApiRequest.get(
  ApiPaths.bootstrap,
  receiveTimeout: readReceiveTimeout,
);

/// The account's platform edges for whole-app tests: memory stores, and a
/// server that is unreachable unless [api] answers.
List<Override> accountTestOverrides({
  FakeApi? api,
  MemorySessionStore? sessions,
  MemoryInstallIdStore? installIds,
}) => [
  installIdStoreProvider.overrideWithValue(
    installIds ?? MemoryInstallIdStore(testInstallId),
  ),
  sessionStoreProvider.overrideWithValue(sessions ?? MemorySessionStore()),
  apiClientProvider.overrideWithValue(api ?? FakeApi(fallback: unreachable)),
];
