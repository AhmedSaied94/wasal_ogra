// The base of the tests against the dev stack (specs/011-m06-identity-sync,
// research R23, contracts/ci-checks.md "The `sync-e2e` job"): the app's own
// account and sync services on an in-memory database, calling
// `WASSAL_E2E_API` (default http://localhost:8000) over real HTTP. Each
// device gets a fresh install id, so the tests' players never meet.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/core/account/account_service.dart';
import 'package:wassal/core/account/install_id_store.dart';
import 'package:wassal/core/network/api_client.dart';
import 'package:wassal/core/network/http_client.dart';
import 'package:wassal/core/sync/state_applier.dart';
import 'package:wassal/core/sync/sync_engine.dart';
import 'package:wassal/features/trip/data/drift_trip_records.dart';

import '../helpers/account.dart';
import '../helpers/content.dart';
import '../helpers/economy.dart';
import '../helpers/sync.dart';

/// The dev stack's API.
final e2eApiBase =
    Platform.environment['WASSAL_E2E_API'] ?? 'http://localhost:8000';

/// The version the tests' requests carry: the oldest the server supports.
const e2eAppVersion = '1.0.0+1';

/// The pack version the phones' operations declare: 1 on the stack CI seeds
/// (`seed_backend.py`); on a local stack that has published since, any
/// version of the sample pack it still supports.
final e2eContentVersion = int.parse(
  Platform.environment['WASSAL_E2E_CONTENT_VERSION'] ?? '1',
);

/// flutter_test's binding answers every HTTP request with a 400; these
/// tests talk to the real stack. Call from `setUpAll`.
void useRealHttp() => HttpOverrides.global = null;

/// One phone: its economy, its stores and its services.
final class E2eDevice {
  E2eDevice._({
    required this.economy,
    required this.api,
    required this.sessions,
    required this.installIds,
    required this.account,
  });

  final TestEconomy economy;
  final ApiClient api;
  final MemorySessionStore sessions;
  final MemoryInstallIdStore installIds;
  final ServerAccountService account;
}

/// A phone on a fresh install id, or [installIds]'s, calling the stack
/// through [wrap] (a dropping wrapper, for one).
Future<E2eDevice> e2eDevice({
  MemoryInstallIdStore? installIds,
  ApiClient Function(ApiClient api)? wrap,
}) async {
  final economy = await testEconomy(contentVersion: e2eContentVersion);
  final dio = createHttpClient(Flavor.dev, FakeAppInfo(e2eAppVersion));
  final ApiClient real = DioApiClient(
    dio: dio,
    flavor: Flavor.dev,
    apiBase: e2eApiBase,
    elapsedMs: () => economy.uptime.elapsedRealtimeMs,
  );
  final api = wrap?.call(real) ?? real;
  final sessions = MemorySessionStore();
  final ids = installIds ?? MemoryInstallIdStore(newInstallId());
  final account = ServerAccountService(
    api: api,
    installIds: ids,
    sessions: sessions,
    store: await testAccountStore(economy),
    connectivity: FakeConnectivitySource(),
    nowMs: economy.clock.nowMs,
    elapsedMs: () => economy.uptime.elapsedRealtimeMs,
    platform: 'android',
  );
  return E2eDevice._(
    economy: economy,
    api: api,
    sessions: sessions,
    installIds: ids,
    account: account,
  );
}

/// [device]'s sync engine, on fake time: tests run passes with `syncNow`.
SyncRunner e2eEngine(
  E2eDevice device, {
  int? Function()? serverStateVersion,
  int seed = 1,
}) {
  final economy = device.economy.service;
  final engine = SyncRunner(
    account: device.account,
    api: device.account.authorized,
    economy: economy,
    states: ServerStateApplier(
      economy: economy,
      trips: DriftTripRecords(device.economy.db),
      content: () => device.economy.content,
      writeProfile: device.account.updateProfile,
    ),
    time: FakeSyncTime(),
    serverStateVersion: serverStateVersion ?? () => null,
    random: Random(seed),
  );
  addTearDown(engine.dispose);
  return engine;
}
