import 'dart:async';

import 'package:content_models/content_models.dart';
import 'package:drift/drift.dart' show ApplyInterceptor;
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/account/domain/account_record.dart';
import 'package:wassal/core/account/drift_account_store.dart';
import 'package:wassal/core/economy/domain/rules.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/economy/economy_sync.dart';
import 'package:wassal/core/sync/comeback_gift.dart';
import 'package:wassal/core/sync/domain/wire/server_wallet.dart';

import '../../helpers/account.dart';
import '../../helpers/economy.dart';
import '../../helpers/sync.dart';

// The comeback gift and its guard (specs/011-m06-identity-sync, contracts/
// sync.md "The comeback gift", research R16), on a real database.

final class _Rig {
  _Rig._(this.economy, this.store, this.gift, this._infos);

  static Future<_Rig> create({
    EconomyState Function(int)? firstState,
    FailingInterceptor? interceptor,
  }) async {
    final economy = await testEconomy(
      firstState: firstState,
      executor: interceptor == null
          ? null
          : (inner) => inner.interceptWith(interceptor),
    );
    final store = await testAccountStore(economy);
    final infos = StreamController<ServerInfo>.broadcast();
    addTearDown(infos.close);
    final gift = await LocalComebackGift.open(
      store: store,
      economy: economy.service,
      infos: infos.stream,
      nowMs: economy.clock.nowMs,
    );
    addTearDown(gift.dispose);
    return _Rig._(economy, store, gift, infos);
  }

  final TestEconomy economy;
  final DriftAccountStore store;
  final LocalComebackGift gift;
  final StreamController<ServerInfo> _infos;

  /// A bootstrap arrives, a minute later.
  Future<void> bootstrap({required bool claimable}) async {
    economy.passTime(minute);
    await store.saveBootstrap(
      receivedAtMs: economy.clock.nowMs(),
      serverTimeMs: economy.clock.nowMs(),
      stateVersion: 1,
      contentVersion: 1,
      client: null,
      entitlements: null,
      daily: null,
      comebackClaimable: claimable,
    );
    _infos.add(store.serverInfo);
    await pumpEventQueue();
  }

  Future<OpOutcome> claim() {
    economy.passTime(minute);
    return gift.claim(economy.service.newRequestId());
  }

  /// The server answers every pending operation.
  Future<void> answerAll() async {
    final batch = await economy.service.pendingOps();
    await economy.service.applyAnswer(
      SyncAnswer(
        stateVersion: 2,
        stateStale: false,
        results: [for (final op in batch) OpResult.accepted(op.op.txnId.value)],
        wallet: ServerWallet(
          jenehat: economy.service.view.jenehat,
          bonat: economy.service.view.bonat,
          fuel: economy.service.state.fuel.liters,
          fuelMax: 5,
          fuelUpdatedAtMs: economy.service.state.fuel.countedFromMs,
        ),
      ),
      batch: batch,
      playerId: syncPlayer,
    );
    await pumpEventQueue();
  }
}

EconomyState _lowTank(int nowMs) => EconomyState.newPlayer(
  fuelMax: 5,
  nowMs: nowMs,
).copyWith(fuel: FuelState(liters: 1, countedFromMs: nowMs), bonat: 40);

void main() {
  group('the operation', () {
    test('fills the tank and adds one change_bag, with no BONAT', () async {
      final rig = await _Rig.create(firstState: _lowTank);
      await rig.bootstrap(claimable: true);

      final outcome = await rig.claim() as OpApplied;

      final op = outcome.op.op;
      expect(op.type, OpType.comebackGift);
      expect(op.payload, isEmpty);
      expect(op.fuelDelta, 4);
      expect(op.bonatDelta, 0);
      expect(op.jenehatDelta, 0);
      expect(op.reason, isNull);
      expect(op.ref, isNull);
      final view = rig.economy.service.view;
      expect(view.fuel.liters, 5);
      expect(view.inventory, {BoosterId.changeBag: 1});
      expect(view.bonat, 40);
      await rig.economy.store.checkProjection(const ProductionRules());
    });

    test('a full tank stays full, and the gift still applies', () async {
      final rig = await _Rig.create();
      await rig.bootstrap(claimable: true);

      final outcome = await rig.claim() as OpApplied;

      expect(outcome.op.op.fuelDelta, 0);
      expect(rig.economy.service.view.fuel.liters, 5);
      expect(rig.economy.service.view.inventory, {BoosterId.changeBag: 1});
    });
  });

  group('the guard', () {
    test('a claim whose write failed is not left held', () async {
      final interceptor = FailingInterceptor();
      final rig = await _Rig.create(interceptor: interceptor);
      await rig.bootstrap(claimable: true);

      interceptor
        ..failInserts = true
        ..failUpdates = true;
      await expectLater(rig.claim(), throwsA(isA<Exception>()));
      expect(rig.gift.claimable, isTrue, reason: 'nothing was written');

      interceptor
        ..failInserts = false
        ..failUpdates = false;
      expect(await rig.claim(), isA<OpApplied>());
    });

    test('only with the cached flag', () async {
      final rig = await _Rig.create();
      expect(rig.gift.claimable, isFalse, reason: 'no bootstrap yet');
      expect(
        await rig.claim(),
        isA<OpRefused>().having(
          (r) => r.code,
          'code',
          EconomyRefusal.notEligible,
        ),
      );

      await rig.bootstrap(claimable: false);
      expect(rig.gift.claimable, isFalse);

      await rig.bootstrap(claimable: true);
      expect(rig.gift.claimable, isTrue);
    });

    test('a second claim while one is pending is refused', () async {
      final rig = await _Rig.create();
      await rig.bootstrap(claimable: true);

      expect(await rig.claim(), isA<OpApplied>());
      expect(rig.gift.claimable, isFalse);
      expect(
        await rig.claim(),
        isA<OpRefused>().having(
          (r) => r.code,
          'code',
          EconomyRefusal.notEligible,
        ),
      );
      expect(rig.economy.service.pendingCount, 1);
    });

    test(
      'a claimable bootstrap while the claim waits doesn\'t re-arm it',
      () async {
        final rig = await _Rig.create();
        await rig.bootstrap(claimable: true);
        await rig.claim();

        await rig.bootstrap(claimable: true);
        expect(rig.gift.claimable, isFalse, reason: 'still pending');

        await rig.answerAll();
        expect(rig.gift.claimable, isFalse, reason: 'that flag came before');

        await rig.bootstrap(claimable: true);
        expect(rig.gift.claimable, isTrue, reason: 'a newer flag');
      },
    );

    test('the answer sets comeback_answered_at_ms', () async {
      final rig = await _Rig.create();
      await rig.bootstrap(claimable: true);
      await rig.claim();
      final claimedAt = rig.store.serverInfo.comebackClaimedAtMs;
      expect(claimedAt, isNotNull);
      expect(rig.store.serverInfo.comebackAnsweredAtMs, isNull);

      rig.economy.passTime(minute);
      await rig.answerAll();

      expect(
        rig.store.serverInfo.comebackAnsweredAtMs,
        greaterThan(claimedAt!),
      );
    });

    test('offline, from the cache, after a relaunch too', () async {
      final rig = await _Rig.create();
      await rig.bootstrap(claimable: true);

      // A new store and gift over the same database: the cache is all
      // there is, and no request goes anywhere.
      final store = await testAccountStore(rig.economy);
      final gift = await LocalComebackGift.open(
        store: store,
        economy: rig.economy.service,
        infos: const Stream.empty(),
        nowMs: rig.economy.clock.nowMs,
      );
      addTearDown(gift.dispose);
      expect(gift.claimable, isTrue);
      expect(
        await gift.claim(rig.economy.service.newRequestId()),
        isA<OpApplied>(),
      );

      // And a relaunch with the claim still pending keeps it refused.
      final again = await LocalComebackGift.open(
        store: await testAccountStore(rig.economy),
        economy: rig.economy.service,
        infos: const Stream.empty(),
        nowMs: rig.economy.clock.nowMs,
      );
      addTearDown(again.dispose);
      expect(again.claimable, isFalse);
    });

    test('claimables follows the guard', () async {
      final rig = await _Rig.create();
      final seen = <bool>[];
      rig.gift.claimables.listen(seen.add);

      await rig.bootstrap(claimable: true);
      await rig.claim();
      await pumpEventQueue();
      await rig.answerAll();
      await pumpEventQueue();

      expect(seen, [true, false]);
    });
  });
}
