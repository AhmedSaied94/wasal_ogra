import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/account/domain/account.dart';
import 'package:wassal/core/account/drift_account_store.dart';

import '../../helpers/account.dart';
import '../../helpers/economy.dart';

// The account store (specs/011-m06-identity-sync, data-model.md "`account`",
// "`server_info`"): the only writer of its two rows, one transaction a
// write, read synchronously after `load()`.

/// Every write, and whether it ran inside a transaction.
final class _Writes extends QueryInterceptor {
  var transactions = 0;
  final outside = <String>[];

  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    transactions++;
    return super.beginTransaction(parent);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (executor is! TransactionExecutor) outside.add(statement);
    return super.runUpdate(executor, statement, args);
  }
}

void main() {
  test('starts with no account and an empty server row', () async {
    final store = await testAccountStore(await testEconomy());
    expect(store.account.status, AccountStatus.none);
    expect(store.account.playerId, isNull);
    expect(store.account.providers, isEmpty);
    expect(store.account.profile, isNull);
    expect(store.serverInfo.stateVersion, isNull);
    expect(store.serverInfo.comebackClaimable, isFalse);
    expect(store.serverInfo.client, isNull);
    expect(store.serverInfo.daily, isNull);
    expect(store.serverInfo.entitlements.removeAds, isFalse);
  });

  test('signs in, sets the profile and stamps updated_at_ms', () async {
    final e = await testEconomy();
    final store = await testAccountStore(e);
    e.passTime(minute);

    await store.signedIn(playerId: playerIdOf(1), providers: const []);
    expect(store.account.status, AccountStatus.active);
    expect(store.account.playerId, playerIdOf(1));
    expect(store.account.updatedAtMs, testEpochMs + 60000);

    e.passTime(minute);
    await store.setProfile(
      providers: const ['google'],
      displayName: 'driver',
      driverLevel: 3,
    );
    // Null keeps what is stored.
    await store.setProfile(driverLevel: 4);
    final profile = store.account.profile!;
    expect(profile.playerId, playerIdOf(1));
    expect(profile.providers, {'google'});
    expect(profile.displayName, 'driver');
    expect(profile.driverLevel, 4);
    expect(store.account.updatedAtMs, testEpochMs + 120000);

    await store.markDeleted();
    expect(store.account.status, AccountStatus.deleted);

    // The rows hold it, for the next launch.
    final again = await testAccountStore(e);
    expect(again.account.status, AccountStatus.deleted);
    expect(again.account.providers, ['google']);
    expect(again.account.displayName, 'driver');
  });

  test('first_open_at_ms is set once and never changed', () async {
    final e = await testEconomy();
    final store = await testAccountStore(e);
    await store.markFirstOpen(testEpochMs + 5);
    final stamped = store.account.updatedAtMs;
    e.passTime(minute);
    await store.markFirstOpen(testEpochMs + 99999);
    expect(store.account.firstOpenAtMs, testEpochMs + 5);
    expect(store.account.updatedAtMs, stamped, reason: 'nothing written');

    await store.markRestored(testEpochMs + 7);
    expect(store.account.restoredAtMs, testEpochMs + 7);
  });

  test('keeps the bootstrap, and reads it back after load()', () async {
    final e = await testEconomy();
    final store = await testAccountStore(e);
    await store.saveBootstrap(
      receivedAtMs: testEpochMs + 10,
      serverTimeMs: testEpochMs + 20,
      stateVersion: 42,
      contentVersion: null,
      client: {
        'min_version': '1.0.0',
        'latest_version': '1.2.0',
        'force_update': false,
      },
      entitlements: {
        'remove_ads': true,
        'subscription': null,
        'season_passes': <Object?>[],
        'flags': {'no_interstitials': true, 'fuel_max_bonus': 2},
      },
      daily: {
        'game_date': '2026-10-17',
        'challenge_available': true,
        'reward_claimable': false,
      },
      comebackClaimable: true,
    );

    final again = DriftAccountStore(e.db, nowMs: e.clock.nowMs);
    await again.load();
    final info = again.serverInfo;
    expect(info.receivedAtMs, testEpochMs + 10);
    expect(info.serverTimeMs, testEpochMs + 20);
    expect(info.stateVersion, 42);
    expect(info.contentVersion, isNull);
    expect(info.comebackClaimable, isTrue);
    expect(info.client!.latestVersion, '1.2.0');
    expect(info.client!.forceUpdate, isFalse);
    expect(info.entitlements.removeAds, isTrue);
    expect(info.entitlements.noInterstitials, isTrue);
    expect(info.entitlements.fuelMaxBonus, 2);
    expect(info.daily!.challengeAvailable, isTrue);
    // Canonical JSON: sorted keys, no spaces.
    expect(
      info.clientJson,
      '{"force_update":false,"latest_version":"1.2.0","min_version":"1.0.0"}',
    );
  });

  test('marks the comeback claim and its answer', () async {
    final store = await testAccountStore(await testEconomy());
    await store.markComebackClaimed(testEpochMs + 1);
    await store.markComebackAnswered(testEpochMs + 2);
    expect(store.serverInfo.comebackClaimedAtMs, testEpochMs + 1);
    expect(store.serverInfo.comebackAnsweredAtMs, testEpochMs + 2);
  });

  test('every write is one transaction', () async {
    final writes = _Writes();
    final e = await testEconomy(
      executor: (inner) => inner.interceptWith(writes),
    );
    final store = await testAccountStore(e);
    writes
      ..transactions = 0
      ..outside.clear();

    await store.markFirstOpen(1);
    await store.signedIn(playerId: playerIdOf(2), providers: const []);
    await store.setProfile(displayName: 'x');
    await store.markDeleted();
    await store.markRestored(2);
    await store.saveBootstrap(
      receivedAtMs: 1,
      serverTimeMs: 1,
      stateVersion: 0,
      contentVersion: 1,
      client: const {},
      entitlements: const {},
      daily: const {},
      comebackClaimable: false,
    );
    await store.markComebackClaimed(3);
    await store.markComebackAnswered(4);

    expect(writes.transactions, 8);
    expect(writes.outside, isEmpty);
  });
}
