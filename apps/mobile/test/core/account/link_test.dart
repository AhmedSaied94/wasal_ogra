import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/account/domain/link_outcome.dart';
import 'package:wassal/core/network/api_client.dart';
import 'package:wassal/core/sync/sync_engine.dart';

import '../../helpers/account.dart';
import '../../helpers/economy.dart';
import '../../helpers/fake_api.dart';

// Linking Google (specs/011-m06-identity-sync, contracts/account.md "Link
// outcomes", research R8): the flush first, then each answer's outcome.
// M14 builds its screens on them.

const _link = ApiPaths.link;
const _googleToken = 'google-id-token';

/// The sync as the link sees it.
final class _Sync implements SyncEngine {
  _Sync(this._api);

  final FakeApi _api;
  bool flushes = true;

  /// The requests already sent when the flush was asked for.
  int? flushedAfter;
  final requests = <SyncTrigger>[];

  @override
  Future<bool> flush({Duration timeout = const Duration(seconds: 15)}) async {
    flushedAfter = _api.log.length;
    return flushes;
  }

  @override
  void request(SyncTrigger trigger) => requests.add(trigger);

  @override
  Stream<SyncEvent> get events => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Rig {
  _Rig._(this.account, this.sync);

  static Future<_Rig> create() async {
    final e = await testEconomy();
    final account = await testAccount(
      economy: e,
      sessions: MemorySessionStore(sessionFor(e.clock.nowMs())),
    );
    await account.store.signedIn(playerId: playerIdOf(1), providers: const []);
    final sync = _Sync(account.api);
    account.service.attachSync(sync);
    return _Rig._(account, sync);
  }

  final TestAccount account;
  final _Sync sync;

  FakeApi get api => account.api;

  void answer(ApiResult result) => api.reply('POST', _link, [result]);

  Future<LinkOutcome> link({LinkResolve? resolve, String? existingPlayerId}) =>
      account.service.link(
        _googleToken,
        resolve: resolve,
        existingPlayerId: existingPlayerId,
      );
}

Map<String, Object?> _side({
  int level = 3,
  String chapter = 'ch2_tuktuk',
  int bonat = 40,
  String? player,
}) => {
  'driver_level': level,
  'chapter_id': chapter,
  'bonat': bonat,
  'player_id': ?player,
};

final _inUse = apiFail(
  409,
  'provider_in_use',
  details: {
    'current': _side(level: 2, bonat: 5),
    'existing': _side(level: 9, chapter: 'ch5_microbus', player: playerIdOf(7)),
  },
);

void main() {
  group('the flush', () {
    for (final flushes in [true, false]) {
      test('comes first, and is reported: $flushes', () async {
        final rig = await _Rig.create();
        rig.sync.flushes = flushes;
        rig.answer(
          apiOk({
            'player_id': playerIdOf(1),
            'providers': ['google'],
          }),
        );

        final outcome = await rig.link();

        expect(rig.sync.flushedAfter, 0);
        expect(outcome.flushed, flushes);
        expect(rig.api.to(_link), hasLength(1));
      });
    }
  });

  test('the request: Google\'s token with the player\'s bearer', () async {
    final rig = await _Rig.create();
    rig.answer(
      apiOk({
        'player_id': playerIdOf(1),
        'providers': ['google'],
      }),
    );

    await rig.link();

    final request = rig.api.to(_link).single;
    expect(request.body, {'provider': 'google', 'id_token': _googleToken});
    expect(request.bearer, 'access-0');
  });

  group('every answer has its outcome', () {
    test(
      '200 {player_id, providers}: Linked, and the profile has Google',
      () async {
        final rig = await _Rig.create();
        rig.answer(
          apiOk({
            'player_id': playerIdOf(1),
            'providers': ['google'],
          }),
        );

        final outcome = await rig.link();

        expect(
          outcome,
          isA<Linked>().having((l) => l.providers, 'p', {'google'}),
        );
        expect(rig.account.service.profile!.providers, {'google'});
        expect(rig.account.store.account.playerId, playerIdOf(1));
      },
    );

    test('409 provider_in_use: both summaries', () async {
      final rig = await _Rig.create();
      rig.answer(_inUse);

      final outcome = await rig.link() as Conflict;

      expect(outcome.current.driverLevel, 2);
      expect(outcome.current.bonat, 5);
      expect(outcome.current.playerId, isNull);
      expect(outcome.existing.driverLevel, 9);
      expect(outcome.existing.chapterId, 'ch5_microbus');
      expect(outcome.existing.playerId, playerIdOf(7));
    });

    test('409 provider_already_linked', () async {
      final rig = await _Rig.create();
      rig.answer(apiFail(409, 'provider_already_linked'));
      expect(await rig.link(), isA<ProviderAlreadyLinked>());
    });

    test('422 provider_token_invalid: the reason, and our session is never '
        'renewed', () async {
      final rig = await _Rig.create();
      rig.answer(
        apiFail(
          422,
          'provider_token_invalid',
          details: {'provider': 'google', 'reason': 'audience'},
        ),
      );

      final outcome = await rig.link();

      expect(
        outcome,
        isA<GoogleTokenRefused>().having((g) => g.reason, 'reason', 'audience'),
      );
      expect(rig.api.to(ApiPaths.refresh), isEmpty);
      expect(rig.api.to(ApiPaths.anonymous), isEmpty);
      expect(rig.account.sessions.session!.access, 'access-0');
    });

    test('unreachable', () async {
      final rig = await _Rig.create();
      rig.answer(unreachable);
      expect(await rig.link(), isA<LinkUnreachable>());
    });

    test('anything else: its code', () async {
      final rig = await _Rig.create();
      rig.answer(apiFail(500, 'server_error'));
      expect(
        await rig.link(),
        isA<LinkFailed>().having((f) => f.code, 'code', 'server_error'),
      );
    });

    test('a malformed answer is a server_error', () async {
      final rig = await _Rig.create();
      rig.answer(apiFail(409, 'provider_in_use', details: {'current': 1}));
      expect(
        await rig.link(),
        isA<LinkFailed>().having((f) => f.code, 'code', 'server_error'),
      );
    });
  });

  group('the retry after a conflict', () {
    test('sends resolve and existing_player_id', () async {
      final rig = await _Rig.create();
      rig.answer(_inUse);
      final conflict = await rig.link() as Conflict;
      rig.answer(
        apiOk({
          'player_id': playerIdOf(1),
          'providers': ['google'],
        }),
      );

      await rig.link(
        resolve: LinkResolve.keepCurrent,
        existingPlayerId: conflict.existing.playerId,
      );

      expect(rig.api.to(_link).last.body, {
        'provider': 'google',
        'id_token': _googleToken,
        'resolve': 'keep_current',
        'existing_player_id': playerIdOf(7),
      });
    });

    test('switch_to_existing: its tokens are stored, the account moves to '
        'that player, and the sync is asked to take its state', () async {
      final rig = await _Rig.create();
      rig.answer(
        apiOk(tokenJson(player: 7, access: 'access-7', providers: ['google'])),
      );

      final outcome = await rig.link(
        resolve: LinkResolve.switchToExisting,
        existingPlayerId: playerIdOf(7),
      );

      expect(
        outcome,
        isA<Linked>().having((l) => l.providers, 'p', {'google'}),
      );
      expect(rig.account.sessions.session!.playerId, playerIdOf(7));
      expect(rig.account.sessions.session!.access, 'access-7');
      expect(rig.account.store.account.playerId, playerIdOf(7));
      expect(rig.sync.requests, [SyncTrigger.accountActive]);
    });
  });
}
