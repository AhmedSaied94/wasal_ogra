import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/account/drift_account_store.dart';
import 'package:wassal/core/sync/domain/wire/bootstrap.dart';
import 'package:wassal/core/sync/domain/wire/reader.dart';

import '../../helpers/account.dart';
import '../../helpers/economy.dart';

// The bootstrap's `ads` block (specs/018-m11-ads, research R11, T018): B07's
// shape, the empty block from an older server, and its cache in
// `server_info.ads`.

const _nonce = '0192f3a1-7b2c-4d4e-8f00-000000000001';

Map<String, Object?> _grant(int n) => {
  'nonce': '0192f3a1-7b2c-4d4e-8f00-${n.toString().padLeft(12, '0')}',
  'jenehat': 30,
  'bonat': 2,
  'granted_at': '2026-11-02T21:59:58.000Z',
};

Map<String, Object?> _block({bool available = true, List<Object?>? unseen}) => {
  'morning_piggy': {
    'available': available,
    'unseen': unseen ?? [_grant(1)],
  },
};

void main() {
  test("B07's example block parses", () {
    final ads = AdsBlock.fromJson(_block());
    expect(ads.piggyAvailable, isTrue);
    final grant = ads.unseen.single;
    expect(grant.nonce, _nonce);
    expect(grant.jenehat, 30);
    expect(grant.bonat, 2);
    expect(
      grant.grantedAtMs,
      DateTime.utc(2026, 11, 2, 21, 59, 58).millisecondsSinceEpoch,
    );
  });

  test('no block, or no piggy in it, is the empty block', () {
    for (final json in [null, <String, Object?>{}]) {
      final ads = AdsBlock.fromJson(json);
      expect(ads.piggyAvailable, isFalse);
      expect(ads.unseen, isEmpty);
    }
  });

  test('more than five entries keep all that came', () {
    final ads = AdsBlock.fromJson(
      _block(unseen: [for (var i = 1; i <= 7; i++) _grant(i)]),
    );
    expect(ads.unseen, hasLength(7));
  });

  test("a malformed entry fails with the entry's path", () {
    expect(
      () => AdsBlock.fromJson(
        _block(
          unseen: [
            _grant(1),
            {..._grant(2), 'bonat': '2'},
          ],
        ),
      ),
      throwsA(
        isA<WireFormatException>().having(
          (e) => e.message,
          'message',
          contains('ads.morning_piggy.unseen.1.bonat'),
        ),
      ),
    );
  });

  test('the store keeps the block and reads it back offline', () async {
    final e = await testEconomy();
    final store = await testAccountStore(e);
    expect(store.serverInfo.ads, isNull);
    await store.saveBootstrap(
      receivedAtMs: testEpochMs + 10,
      serverTimeMs: testEpochMs + 20,
      stateVersion: 3,
      contentVersion: null,
      client: {
        'min_version': '1.0.0',
        'latest_version': '1.0.0',
        'force_update': false,
      },
      entitlements: {
        'remove_ads': false,
        'subscription': null,
        'season_passes': <Object?>[],
      },
      daily: {
        'game_date': '2026-11-03',
        'challenge_available': false,
        'reward_claimable': false,
      },
      ads: _block(),
      comebackClaimable: false,
    );

    final again = DriftAccountStore(e.db, nowMs: e.clock.nowMs);
    await again.load();
    final ads = again.serverInfo.ads!;
    expect(ads.piggyAvailable, isTrue);
    expect(ads.unseen.single.nonce, _nonce);
  });
}
