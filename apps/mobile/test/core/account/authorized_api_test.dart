import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/account/authorized_api.dart';
import 'package:wassal/core/account/domain/account.dart';
import 'package:wassal/core/network/api_client.dart';
import 'package:wassal/core/sync/domain/wire/token_pair.dart';

import '../../helpers/account.dart';
import '../../helpers/economy.dart';
import '../../helpers/fake_api.dart';

// The token rules (specs/011-m06-identity-sync, contracts/api-client.md
// "The token rules", research R4), one test a row, against a scripted
// server and the economy's trusted clock.

const _anonymous = ApiPaths.anonymous;
const _refresh = ApiPaths.refresh;
const _read = ApiPaths.bootstrap;

final _ok = apiOk({'ok': 1});

/// An account with a stored session, valid for [validFor].
Future<TestAccount> _signedIn({
  Duration validFor = const Duration(minutes: 15),
}) async {
  final e = await testEconomy();
  final account = await testAccount(
    economy: e,
    sessions: MemorySessionStore(
      sessionFor(e.clock.nowMs(), validFor: validFor),
    ),
  );
  await account.store.signedIn(playerId: playerIdOf(1), providers: const []);
  return account;
}

void main() {
  test('no session: signs in first, then calls with the new token', () async {
    final a = await testAccount();
    a.api
      ..reply('POST', _anonymous, [apiOk(tokenJson(created: true))])
      ..reply('GET', _read, [_ok]);

    final result = await a.service.authorized.send(testRead);

    expect(result, isA<ApiOk>());
    expect([for (final r in a.api.log) r.path], [_anonymous, _read]);
    expect(a.api.to(_anonymous).single.bearer, isNull);
    expect(bearersTo(a.api, _read), ['access-1']);
    expect(a.sessions.session!.access, 'access-1');
    expect(a.service.status, AccountStatus.active);
  });

  test('under 60 s left: renews first', () async {
    final a = await _signedIn(validFor: const Duration(seconds: 59));
    a.api
      ..reply('POST', _refresh, [
        apiOk(tokenJson(access: 'access-2', refresh: 'refresh-2')),
      ])
      ..reply('GET', _read, [_ok]);

    await a.service.authorized.send(testRead);

    expect(a.api.to(_refresh).single.body, {'refresh': 'refresh-0'});
    expect(bearersTo(a.api, _read), ['access-2']);
  });

  test('with 60 s or more left: no renewal', () async {
    final a = await _signedIn(validFor: const Duration(seconds: 61));
    a.api.reply('GET', _read, [_ok]);
    await a.service.authorized.send(testRead);
    expect(a.api.to(_refresh), isEmpty);
    expect(bearersTo(a.api, _read), ['access-0']);
  });

  test('the renewal pair is stored, in one write, before the call', () async {
    final a = await _signedIn(validFor: Duration.zero);
    final writesBefore = a.sessions.writes;
    a.api
      ..reply('POST', _refresh, [
        apiOk(tokenJson(access: 'access-2', refresh: 'refresh-2')),
      ])
      ..reply('GET', _read, [
        (ApiRequest request) {
          // Stored before the call went out.
          expect(a.sessions.session!.access, 'access-2');
          return _ok;
        },
      ]);

    await a.service.authorized.send(testRead);

    expect(a.sessions.writes, writesBefore + 1);
    final session = a.sessions.session!;
    expect(session.refresh, 'refresh-2');
    expect(session.accessExpiresAtMs, a.economy.clock.nowMs() + 900000);
  });

  group('a lost renewal', () {
    test('is retried with the same refresh token, at most twice', () async {
      final a = await _signedIn(validFor: Duration.zero);
      a.api
        ..reply('POST', _refresh, [
          unreachable,
          FakeReply.dropped(apiOk(tokenJson(access: 'lost'))),
          apiOk(tokenJson(access: 'access-2', refresh: 'refresh-2')),
        ])
        ..reply('GET', _read, [_ok]);

      expect(await a.service.authorized.send(testRead), isA<ApiOk>());
      expect(
        [for (final r in a.api.to(_refresh)) r.body],
        [
          for (var i = 0; i < 3; i++) {'refresh': 'refresh-0'},
        ],
      );
      expect(a.api.to(_anonymous), isEmpty);
      expect(bearersTo(a.api, _read), ['access-2']);
    });

    test('a third loss signs in again', () async {
      final a = await _signedIn(validFor: Duration.zero);
      a.api
        ..reply('POST', _refresh, [unreachable, unreachable, unreachable])
        ..reply('POST', _anonymous, [apiOk(tokenJson(access: 'access-9'))])
        ..reply('GET', _read, [_ok]);

      await a.service.authorized.send(testRead);

      expect(a.api.to(_refresh), hasLength(3));
      expect(a.api.to(_anonymous), hasLength(1));
      expect(bearersTo(a.api, _read), ['access-9']);
    });

    test('past 60 s since the first attempt signs in again', () async {
      final a = await _signedIn(validFor: Duration.zero);
      a.api
        ..reply('POST', _refresh, [
          (ApiRequest _) {
            a.economy.passTime(const Duration(seconds: 61));
            return unreachable;
          },
        ])
        ..reply('POST', _anonymous, [apiOk(tokenJson(access: 'access-9'))])
        ..reply('GET', _read, [_ok]);

      await a.service.authorized.send(testRead);

      expect(a.api.to(_refresh), hasLength(1));
      expect(a.api.to(_anonymous), hasLength(1));
    });

    test('with no network at all, the call answers unreachable', () async {
      final a = await _signedIn(validFor: Duration.zero);
      a.api
        ..always('POST', _refresh, unreachable)
        ..always('POST', _anonymous, unreachable);
      final result = await a.service.authorized.send(testRead);
      expect(result, isA<ApiUnreachable>());
      expect(a.api.to(_read), isEmpty);
    });
  });

  test('token_expired: renews and repeats the call once', () async {
    final a = await _signedIn();
    a.api
      ..reply('GET', _read, [apiFail(401, 'token_expired'), _ok])
      ..reply('POST', _refresh, [apiOk(tokenJson(access: 'access-2'))]);

    expect(await a.service.authorized.send(testRead), isA<ApiOk>());
    expect(bearersTo(a.api, _read), ['access-0', 'access-2']);
  });

  test('token_expired twice: the repeat is the answer', () async {
    final a = await _signedIn();
    a.api
      ..reply('GET', _read, [
        apiFail(401, 'token_expired'),
        apiFail(401, 'token_expired'),
      ])
      ..reply('POST', _refresh, [apiOk(tokenJson(access: 'access-2'))]);
    final result = await a.service.authorized.send(testRead);
    expect((result as ApiFailure).code, 'token_expired');
    expect(a.api.to(_read), hasLength(2));
  });

  test('token_invalid: renews once and repeats once', () async {
    final a = await _signedIn();
    a.api
      ..reply('GET', _read, [apiFail(401, 'token_invalid'), _ok])
      ..reply('POST', _refresh, [apiOk(tokenJson(access: 'access-2'))]);
    expect(await a.service.authorized.send(testRead), isA<ApiOk>());
    expect(a.api.to(_anonymous), isEmpty);
  });

  test('a second token_invalid signs in again', () async {
    final a = await _signedIn();
    a.api
      ..reply('GET', _read, [
        apiFail(401, 'token_invalid'),
        apiFail(401, 'token_invalid'),
        _ok,
      ])
      ..reply('POST', _refresh, [apiOk(tokenJson(access: 'access-2'))])
      ..reply('POST', _anonymous, [apiOk(tokenJson(access: 'access-3'))]);

    expect(await a.service.authorized.send(testRead), isA<ApiOk>());
    expect(bearersTo(a.api, _read), ['access-0', 'access-2', 'access-3']);
    expect(a.api.to(_refresh), hasLength(1));
    expect(a.api.to(_anonymous), hasLength(1));
  });

  for (final code in ['token_expired', 'token_invalid']) {
    test('a renewal answering $code signs in again', () async {
      final a = await _signedIn(validFor: Duration.zero);
      a.api
        ..reply('POST', _refresh, [apiFail(401, code)])
        ..reply('POST', _anonymous, [apiOk(tokenJson(access: 'access-9'))])
        ..reply('GET', _read, [_ok]);
      await a.service.authorized.send(testRead);
      expect(a.api.to(_anonymous), hasLength(1));
      expect(bearersTo(a.api, _read), ['access-9']);
    });
  }

  test('a renewal failure that is not a token error is the answer', () async {
    final a = await _signedIn(validFor: Duration.zero);
    a.api.reply('POST', _refresh, [apiFail(503, 'maintenance')]);
    final result = await a.service.authorized.send(testRead);
    expect((result as ApiFailure).code, 'maintenance');
    expect(a.api.to(_anonymous), isEmpty);
    expect(a.api.to(_read), isEmpty);
  });

  group('403 account_deleted', () {
    test(
      'on a call: deleted, and later calls answer without a request',
      () async {
        final a = await _signedIn();
        a.api.reply('GET', _read, [apiFail(403, 'account_deleted')]);

        final first = await a.service.authorized.send(testRead);
        expect((first as ApiFailure).code, 'account_deleted');
        expect(a.service.status, AccountStatus.deleted);

        final again = await a.service.authorized.send(testRead);
        expect((again as ApiFailure).code, 'account_deleted');
        expect(a.api.log, hasLength(1));

        // On the next launch too.
        final relaunched = await a.relaunch();
        expect(relaunched.service.status, AccountStatus.deleted);
        await relaunched.service.authorized.send(testRead);
        expect(a.api.log, hasLength(1));
        expect(await relaunched.service.ensureSession(), isFalse);
      },
    );

    test('on a renewal', () async {
      final a = await _signedIn(validFor: Duration.zero);
      a.api.reply('POST', _refresh, [apiFail(403, 'account_deleted')]);
      await a.service.authorized.send(testRead);
      expect(a.service.status, AccountStatus.deleted);
    });

    test('on a repeat after token_expired', () async {
      final a = await _signedIn();
      a.api
        ..reply('GET', _read, [
          apiFail(401, 'token_expired'),
          apiFail(403, 'account_deleted'),
        ])
        ..reply('POST', _refresh, [apiOk(tokenJson(access: 'access-2'))]);
      await a.service.authorized.send(testRead);
      expect(a.service.status, AccountStatus.deleted);
    });
  });

  group('tokens for another player: the call is not repeated with them', () {
    final player2 = apiOk(tokenJson(player: 2, access: 'access-2'));

    test('a renewal before the call', () async {
      final a = await _signedIn(validFor: const Duration(seconds: 59));
      a.api.reply('POST', _refresh, [player2]);

      expect(await a.service.authorized.send(testRead), accountChangedAnswer);
      expect(a.api.to(_read), isEmpty);
      expect(a.store.account.playerId, playerIdOf(2));
    });

    test('a renewal after token_expired', () async {
      final a = await _signedIn();
      a.api
        ..reply('GET', _read, [apiFail(401, 'token_expired')])
        ..reply('POST', _refresh, [player2]);

      expect(await a.service.authorized.send(testRead), accountChangedAnswer);
      expect(bearersTo(a.api, _read), ['access-0']);
    });

    test('a renewal after token_invalid', () async {
      final a = await _signedIn();
      a.api
        ..reply('GET', _read, [apiFail(401, 'token_invalid')])
        ..reply('POST', _refresh, [player2]);

      expect(await a.service.authorized.send(testRead), accountChangedAnswer);
      expect(bearersTo(a.api, _read), ['access-0']);
    });

    test('a sign-in after a second token_invalid', () async {
      final a = await _signedIn();
      a.api
        ..reply('GET', _read, [
          apiFail(401, 'token_invalid'),
          apiFail(401, 'token_invalid'),
        ])
        ..reply('POST', _refresh, [apiOk(tokenJson(access: 'access-2'))])
        ..reply('POST', _anonymous, [
          apiOk(tokenJson(player: 3, access: 'access-3')),
        ]);

      expect(await a.service.authorized.send(testRead), accountChangedAnswer);
      expect(bearersTo(a.api, _read), ['access-0', 'access-2']);
    });

    test('a request made for another player is not sent', () async {
      final a = await _signedIn();
      final request = ApiRequest.get(
        _read,
        receiveTimeout: readReceiveTimeout,
        forPlayer: playerIdOf(2),
      );

      expect(await a.service.authorized.send(request), accountChangedAnswer);
      expect(a.api.log, isEmpty);
    });

    test('one made for the session\'s player is', () async {
      final a = await _signedIn();
      a.api.reply('GET', _read, [_ok]);
      final request = ApiRequest.get(
        _read,
        receiveTimeout: readReceiveTimeout,
        forPlayer: playerIdOf(1),
      );

      expect(await a.service.authorized.send(request), isA<ApiOk>());
    });

    test('a renewal answered after another player\'s tokens were stored '
        'keeps them', () async {
      final a = await _signedIn(validFor: const Duration(seconds: 59));
      final gate = Completer<void>();
      a.api.reply('POST', _refresh, [
        FakeReply.held(apiOk(tokenJson(access: 'access-2')), gate),
      ]);

      final sent = a.service.authorized.send(testRead);
      await pumpEventQueue();
      await a.service.authorized.storeTokens(
        TokenPair.fromJson(tokenJson(player: 3, access: 'access-3')),
      );
      gate.complete();

      expect(await sent, accountChangedAnswer);
      expect(a.sessions.session!.access, 'access-3');
      expect(a.store.account.playerId, playerIdOf(3));
      expect(a.api.to(_read), isEmpty);
    });

    test('the next call is the new player\'s', () async {
      final a = await _signedIn(validFor: const Duration(seconds: 59));
      a.api
        ..reply('POST', _refresh, [player2])
        ..reply('GET', _read, [_ok]);
      await a.service.authorized.send(testRead);

      expect(await a.service.authorized.send(testRead), isA<ApiOk>());
      expect(bearersTo(a.api, _read), ['access-2']);
    });
  });

  test('a session that can\'t be saved is kept for this run', () async {
    final a = await _signedIn(validFor: Duration.zero);
    a.sessions.failWrites = true;
    a.api
      ..reply('POST', _refresh, [apiOk(tokenJson(access: 'access-2'))])
      ..reply('GET', _read, [_ok, _ok]);

    expect(await a.service.authorized.send(testRead), isA<ApiOk>());
    expect(await a.service.authorized.send(testRead), isA<ApiOk>());

    expect(bearersTo(a.api, _read), ['access-2', 'access-2']);
    expect(a.api.to(_refresh), hasLength(1));
  });

  test('three concurrent callers share one renewal', () async {
    final a = await _signedIn(validFor: Duration.zero);
    final gate = Completer<void>();
    a.api
      ..reply('POST', _refresh, [
        FakeReply.held(apiOk(tokenJson(access: 'access-2')), gate),
      ])
      ..always('GET', _read, _ok);

    final calls = [
      for (var i = 0; i < 3; i++) a.service.authorized.send(testRead),
    ];
    await pumpEventQueue();
    gate.complete();
    await Future.wait(calls);

    expect(a.api.to(_refresh), hasLength(1));
    expect(bearersTo(a.api, _read), ['access-2', 'access-2', 'access-2']);
  });

  test('two calls that both see token_expired share one renewal', () async {
    final a = await _signedIn();
    final gate = Completer<void>();
    a.api
      ..reply('GET', _read, [
        apiFail(401, 'token_expired'),
        apiFail(401, 'token_expired'),
      ])
      ..always('GET', _read, _ok)
      ..reply('POST', _refresh, [
        FakeReply.held(apiOk(tokenJson(access: 'access-2')), gate),
      ]);
    final calls = [
      a.service.authorized.send(testRead),
      a.service.authorized.send(testRead),
    ];
    await pumpEventQueue();
    gate.complete();
    await Future.wait(calls);
    expect(a.api.to(_refresh), hasLength(1));
  });

  test('a creation 429 waits retry_after_s, and play goes on', () async {
    final a = await testAccount();
    a.api.reply('POST', _anonymous, [
      apiFail(
        429,
        'rate_limited',
        details: {'retry_after_s': 30},
        retryAfter: const Duration(seconds: 10),
      ),
      apiOk(tokenJson()),
    ]);

    final first = await a.service.authorized.send(testRead);
    expect((first as ApiFailure).code, 'rate_limited');

    // Before the wait: no request.
    a.economy.passTime(const Duration(seconds: 29));
    expect(await a.service.ensureSession(), isFalse);
    expect(a.api.to(_anonymous), hasLength(1));

    a.economy.passTime(const Duration(seconds: 1));
    expect(await a.service.ensureSession(), isTrue);
    expect(a.api.to(_anonymous), hasLength(2));
  });

  test('sessionOf counts the expiry on trusted time', () {
    final session = sessionOf(TokenPair.fromJson(tokenJson()), 1000);
    expect(session.accessExpiresAtMs, 901000);
    expect(session.playerId, playerIdOf(1));
  });
}
