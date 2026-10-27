import 'dart:async';
import 'dart:math';

import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/account/domain/account.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/network/api_client.dart';
import 'package:wassal/core/sync/domain/wire/token_pair.dart';
import 'package:wassal/core/sync/state_applier.dart';
import 'package:wassal/core/sync/sync_engine.dart';
import 'package:wassal/features/trip/data/drift_trip_records.dart';

import '../../helpers/account.dart';
import '../../helpers/economy.dart';
import '../../helpers/fake_api.dart';
import '../../helpers/sync.dart';

// The account in the background (specs/011-m06-identity-sync, contracts/
// account.md, research R5, R6; US1): creation with the install id, a
// session kept across launches, and the first open.

const _anonymous = ApiPaths.anonymous;

/// The sync as the account sees it: restores asked for, events sent.
final class _Sync implements SyncEngine {
  final _events = StreamController<SyncEvent>.broadcast();
  int restores = 0;

  void emit(SyncEvent event) => _events.add(event);

  @override
  void requestRestore() => restores++;

  @override
  Stream<SyncEvent> get events => _events.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A returning player's answers: the creation, and the state.
void _returning(TestAccount a, {Object? state}) => a.api
  ..reply('POST', _anonymous, [apiOk(tokenJson(created: false))])
  ..reply('GET', ApiPaths.state, [state ?? apiOk(stateJson(stateVersion: 8))]);

/// The real sync over [a]'s account, tokens and economy.
SyncRunner _engine(TestAccount a, List<SyncEvent> events) {
  final economy = a.economy.service;
  final engine = SyncRunner(
    account: a.service,
    api: a.service.authorized,
    economy: economy,
    states: ServerStateApplier(
      economy: economy,
      trips: DriftTripRecords(a.economy.db),
      content: () => a.economy.content,
      writeProfile: a.service.updateProfile,
    ),
    time: FakeSyncTime(),
    serverStateVersion: () => null,
    random: Random(1),
  );
  engine.events.listen(events.add);
  addTearDown(engine.dispose);
  return engine;
}

/// An account whose economy can buy boosters with BONAT.
Future<TestAccount> _spender() async => testAccount(
  economy: await testEconomy(
    firstState: (nowMs) => EconomyState.newPlayer(
      fuelMax: 5,
      nowMs: nowMs,
    ).copyWith(jenehat: 1000, bonat: 100),
  ),
);

/// One operation for the server.
Future<void> _spend(TestAccount a) async {
  final economy = a.economy.service;
  expect(
    await economy.buy(
      economy.newRequestId(),
      kind: SkuKind.booster,
      skuId: 'change_bag',
    ),
    isA<OpApplied>(),
  );
}

Matcher get _heldDeleted =>
    isA<PassHeld>().having((p) => p.reason, 'reason', HoldReason.deleted);

void main() {
  group('ensureSession', () {
    test('creates the account with the install id', () async {
      final a = await testAccount();
      a.api.reply('POST', _anonymous, [
        apiOk(tokenJson(created: true, providers: ['google'])),
      ]);

      expect(await a.service.ensureSession(), isTrue);

      final request = a.api.to(_anonymous).single;
      expect(request.body, {
        'install_id': testInstallId.value,
        'platform': 'android',
        'locale': 'ar-EG',
      });
      expect(request.bearer, isNull);
      expect(a.service.status, AccountStatus.active);
      expect(a.service.profile!.playerId, playerIdOf(1));
      expect(a.service.profile!.providers, {'google'});
      expect(a.store.account.playerId, playerIdOf(1));
    });

    test('a second call makes no request', () async {
      final a = await testAccount();
      a.api.reply('POST', _anonymous, [apiOk(tokenJson())]);
      await a.service.ensureSession();
      expect(await a.service.ensureSession(), isTrue);
      expect(a.api.log, hasLength(1));
    });

    test('concurrent calls send one creation', () async {
      final a = await testAccount();
      a.api.reply('POST', _anonymous, [apiOk(tokenJson())]);
      final results = await Future.wait([
        a.service.ensureSession(),
        a.service.ensureSession(),
      ]);
      expect(results, [true, true]);
      expect(a.api.log, hasLength(1));
    });

    for (final (name, answer) in [
      ('a 5xx', apiFail(503, 'dependency_unavailable')),
      ('no connection', unreachable),
      ('a malformed answer', apiOk({'player_id': 1})),
    ]) {
      test('$name leaves it none, and the next call tries again', () async {
        final a = await testAccount();
        a.api.reply('POST', _anonymous, [answer, apiOk(tokenJson())]);

        expect(await a.service.ensureSession(), isFalse);
        expect(a.service.status, AccountStatus.none);
        expect(a.sessions.session, isNull);
        // Play goes on: the economy still takes requests.
        expect(a.economy.service.view.jenehat, 0);

        expect(await a.service.ensureSession(), isTrue);
        expect(a.service.status, AccountStatus.active);
      });
    }

    test('a relaunch reuses the session', () async {
      final a = await testAccount();
      a.api.reply('POST', _anonymous, [apiOk(tokenJson())]);
      await a.service.ensureSession();

      final again = await a.relaunch();
      expect(again.service.status, AccountStatus.active);
      expect(await again.service.ensureSession(), isTrue);
      expect(a.api.to(_anonymous), hasLength(1));
    });

    test('the install id goes only to account creation', () async {
      final a = await testAccount();
      a.api
        ..reply('POST', _anonymous, [apiOk(tokenJson(expiresIn: 30))])
        ..reply('POST', ApiPaths.refresh, [apiOk(tokenJson(access: 'a2'))])
        ..always('GET', ApiPaths.bootstrap, apiOk({'ok': 1}))
        ..always('POST', ApiPaths.sync, apiOk({'ok': 1}));
      await a.service.ensureSession();
      await a.service.authorized.send(testRead);
      await a.service.authorized.send(
        const ApiRequest.post(
          ApiPaths.sync,
          receiveTimeout: syncReceiveTimeout,
          body: {'base_state_version': 0, 'ops': <Object?>[]},
        ),
      );

      for (final request in a.api.log) {
        final text = '${request.body} ${request.bearer}';
        final carries = text.contains(testInstallId.value);
        expect(carries, request.path == _anonymous, reason: request.path);
      }
      expect(a.api.log.map((r) => r.path), contains(ApiPaths.refresh));
    });

    test('a token answer for another player moves the account to it', () async {
      final a = await testAccount();
      a.api.reply('POST', _anonymous, [apiOk(tokenJson())]);
      await a.service.ensureSession();
      await a.service.authorized.storeTokens(
        TokenPair.fromJson(tokenJson(player: 2, providers: ['google'])),
      );
      expect(a.store.account.playerId, playerIdOf(2));
      expect(a.sessions.session!.playerId, playerIdOf(2));
      expect(a.service.profile!.providers, {'google'});
    });
  });

  group('firstOpen', () {
    test('a new player: clears an old session first, then creates', () async {
      final e = await testEconomy();
      final a = await testAccount(
        economy: e,
        sessions: MemorySessionStore(sessionFor(e.clock.nowMs(), player: 9)),
      );
      a.api.reply('POST', _anonymous, [apiOk(tokenJson(created: true))]);

      expect(await a.service.firstOpen(), FirstOpenOutcome.newPlayer);

      // The keychain's session from a previous install was not used.
      expect(a.api.log.single.path, _anonymous);
      expect(a.sessions.session!.playerId, playerIdOf(1));
      expect(a.store.account.firstOpenAtMs, testEpochMs);
      expect(a.service.status, AccountStatus.active);
    });

    test('offline: answers at once, with no request', () async {
      final a = await testAccount();
      a.connectivity.current = false;
      expect(await a.service.firstOpen(), FirstOpenOutcome.offline);
      expect(a.api.log, isEmpty);
      expect(a.service.status, AccountStatus.none);
      expect(a.store.account.firstOpenAtMs, isNotNull);
    });

    test('a failed creation answers offline', () async {
      final a = await testAccount();
      a.api.reply('POST', _anonymous, [unreachable]);
      expect(await a.service.firstOpen(), FirstOpenOutcome.offline);
    });

    test('runs once a launch', () async {
      final a = await testAccount();
      a.api.reply('POST', _anonymous, [apiOk(tokenJson(created: true))]);
      final first = a.service.firstOpen();
      expect(a.service.firstOpen(), same(first));
      await first;
      expect(a.api.log, hasLength(1));
    });

    test('a later launch answers notFirstOpen with no request', () async {
      final a = await testAccount();
      a.api.reply('POST', _anonymous, [apiOk(tokenJson(created: true))]);
      await a.service.firstOpen();
      final firstOpenAt = a.store.account.firstOpenAtMs;

      final again = await a.relaunch();
      expect(await again.service.firstOpen(), FirstOpenOutcome.notFirstOpen);
      expect(a.api.log, hasLength(1));
      expect(again.store.account.firstOpenAtMs, firstOpenAt);
      expect(again.sessions.session, isNotNull);
    });

    test('a returning player: the state is taken, and restored', () async {
      final a = await testAccount();
      _returning(a);

      expect(await a.service.firstOpen(), FirstOpenOutcome.restored);

      expect(a.api.log.map((r) => r.path), [_anonymous, ApiPaths.state]);
      expect(a.store.account.restoredAtMs, isNotNull);
      expect(a.economy.service.view.jenehat, 900);
      expect(a.economy.service.view.progress['line_hay.01']?.bestStars, 3);
      expect(a.economy.service.baseInfo, (
        stateVersion: 8,
        playerId: playerIdOf(1),
      ));
      expect(a.service.profile!.displayName, 'name');
    });

    test('past the hand-over, the state is left to the sync', () async {
      final a = await testAccount();
      final sync = _Sync();
      a.service.attachSync(sync);
      a.api.reply('POST', _anonymous, [apiOk(tokenJson(created: false))]);
      a.service.handOver();

      expect(await a.service.firstOpen(), FirstOpenOutcome.timedOut);

      expect(a.api.to(ApiPaths.state), isEmpty);
      expect(sync.restores, 1);
      expect(a.store.account.restoredAtMs, isNull);
      expect(a.economy.service.view.jenehat, 0);

      final restored = a.service.restorations.first;
      sync.emit(const StateTaken(8, StateWhy.firstOpen));
      await restored;
      expect(a.store.account.restoredAtMs, isNotNull);
    });

    test(
      'a state answer that lands after the hand-over isn\'t applied',
      () async {
        final a = await testAccount();
        final sync = _Sync();
        a.service.attachSync(sync);
        final gate = Completer<void>();
        _returning(a, state: FakeReply.held(apiOk(stateJson()), gate));

        final outcome = a.service.firstOpen();
        while (a.api.to(ApiPaths.state).isEmpty) {
          await pumpEventQueue();
        }
        a.service.handOver();
        gate.complete();

        expect(await outcome, FirstOpenOutcome.timedOut);
        expect(a.economy.service.view.jenehat, 0);
        expect(a.economy.service.baseInfo.stateVersion, isNull);
        expect(sync.restores, 1);
      },
    );

    test(
      'a failed state fetch leaves it to the sync, once it attaches',
      () async {
        final a = await testAccount();
        _returning(a, state: unreachable);

        expect(await a.service.firstOpen(), FirstOpenOutcome.offline);
        expect(a.economy.service.view.jenehat, 0);

        final sync = _Sync();
        a.service.attachSync(sync);
        expect(sync.restores, 1);
      },
    );

    test('another reason\'s state taken is no restore', () async {
      final a = await testAccount();
      final sync = _Sync();
      a.service.attachSync(sync);
      var restorations = 0;
      a.service.restorations.listen((_) => restorations++);

      sync
        ..emit(const StateTaken(3, StateWhy.stale))
        ..emit(const StateTaken(4, StateWhy.account));
      await pumpEventQueue();

      expect(restorations, 0);
      expect(a.store.account.restoredAtMs, isNull);
    });

    test('an offline first open counts again on the next launch', () async {
      final a = await testAccount();
      a.connectivity.current = false;
      await a.service.firstOpen();
      final firstOpenAt = a.store.account.firstOpenAtMs;

      a.economy.passTime(minute);
      a.connectivity.current = true;
      a.api.reply('POST', _anonymous, [apiOk(tokenJson(created: true))]);
      final again = await a.relaunch();
      expect(await again.service.firstOpen(), FirstOpenOutcome.newPlayer);
      expect(again.store.account.firstOpenAtMs, firstOpenAt);
    });
  });

  group('account changes, with the sync (contracts/account.md)', () {
    test(
      'operations recorded before any account go out for the first player',
      () async {
        final a = await _spender();
        await _spend(a);
        await _spend(a);
        a.api
          ..reply('POST', _anonymous, [apiOk(tokenJson())])
          ..always('POST', ApiPaths.sync, (ApiRequest r) => syncAnswerFor(r));

        await _engine(a, []).syncNow();

        final sync = a.api.to(ApiPaths.sync).single;
        expect(sentIds(sync), hasLength(2));
        expect(sync.bearer, 'access-1');
        expect(a.api.to(ApiPaths.state), isEmpty);
        expect(a.economy.service.baseInfo.playerId, playerIdOf(1));
        expect(a.economy.service.pendingCount, 0);
      },
    );

    /// Player 1 synced once, two of its operations pending, then a token
    /// answer for player 2.
    Future<TestAccount> changed() async {
      final a = await _spender();
      a.api
        ..reply('POST', _anonymous, [apiOk(tokenJson())])
        ..always('POST', ApiPaths.sync, (ApiRequest r) => syncAnswerFor(r))
        ..always('GET', ApiPaths.state, apiOk(stateJson(stateVersion: 9)));
      await _spend(a);
      await _engine(a, []).syncNow();
      await _spend(a);
      await _spend(a);

      await a.service.authorized.storeTokens(
        TokenPair.fromJson(tokenJson(player: 2, access: 'access-2')),
      );
      return a;
    }

    test('another player\'s tokens: stored, and the sync takes its state '
        'before sending anything', () async {
      final a = await changed();
      expect(a.store.account.playerId, playerIdOf(2));
      expect(a.sessions.session!.playerId, playerIdOf(2));
      expect(a.economy.service.pendingCount, 2, reason: 'until the next pass');
      expect(a.economy.service.baseInfo.playerId, playerIdOf(1));

      final events = <SyncEvent>[];
      await _engine(a, events).syncNow();

      expect(a.api.to(ApiPaths.sync), hasLength(1), reason: 'player 1\'s');
      expect(bearersTo(a.api, ApiPaths.state), ['access-2']);
      expect(events.whereType<OpsDropped>().single.count, 2);
      expect(events.whereType<StateTaken>().single.why, StateWhy.account);
      expect(a.economy.service.pendingCount, 0);
      expect(a.economy.service.baseInfo, (
        stateVersion: 9,
        playerId: playerIdOf(2),
      ));
    });

    test('a kill between the two: the next launch completes it', () async {
      final a = await changed();

      final again = await a.relaunch();
      final events = <SyncEvent>[];
      await _engine(again, events).syncNow();

      expect(events.whereType<OpsDropped>().single.count, 2);
      expect(again.economy.service.baseInfo.playerId, playerIdOf(2));
      expect(a.api.to(ApiPaths.sync), hasLength(1));
    });

    test('a renewal that answers another player never repeats the old '
        'player\'s batch with its tokens', () async {
      final a = await _spender();
      a.api
        ..reply('POST', _anonymous, [apiOk(tokenJson())])
        ..reply('POST', ApiPaths.sync, [
          (ApiRequest r) => syncAnswerFor(r),
          apiFail(401, 'token_expired'),
        ])
        ..always('POST', ApiPaths.sync, (ApiRequest r) => syncAnswerFor(r))
        ..reply('POST', ApiPaths.refresh, [
          apiOk(tokenJson(player: 2, access: 'access-2', refresh: 'r-2')),
        ])
        ..always('GET', ApiPaths.state, apiOk(stateJson(stateVersion: 9)));
      final events = <SyncEvent>[];
      final engine = _engine(a, events);
      // Player 1's base, then two of its operations.
      await _spend(a);
      await engine.syncNow();
      await _spend(a);
      await _spend(a);

      await engine.syncNow();

      expect(bearersTo(a.api, ApiPaths.sync), ['access-1', 'access-1']);
      expect(bearersTo(a.api, ApiPaths.state), ['access-2']);
      expect(events.whereType<OpsDropped>().single.count, 2);
      expect(a.economy.service.baseInfo.playerId, playerIdOf(2));
    });

    test('403 account_deleted: deleted, the sync stops, and stays stopped '
        'after a relaunch', () async {
      final a = await _spender();
      a.api
        ..reply('POST', _anonymous, [apiOk(tokenJson())])
        ..always('POST', ApiPaths.sync, apiFail(403, 'account_deleted'));
      await _spend(a);

      expect(await _engine(a, []).syncNow(), _heldDeleted);
      expect(a.service.status, AccountStatus.deleted);

      final again = await a.relaunch();
      expect(again.service.status, AccountStatus.deleted);
      final sent = a.api.log.length;
      expect(await _engine(again, []).syncNow(), _heldDeleted);
      expect(a.api.log, hasLength(sent));
      expect(a.economy.service.pendingCount, 1, reason: 'play goes on');
    });
  });
}
