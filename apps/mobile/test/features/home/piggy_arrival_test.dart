import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/sync/domain/wire/bootstrap.dart';
import 'package:wassal/core/sync/sync_providers.dart';
import 'package:wassal/features/home/application/arrival_queue.dart';
import 'package:wassal/features/home/application/piggy_arrival.dart';

import '../../helpers/economy.dart';
import '../../helpers/trip.dart' show opCount;

// The late piggy reward on arrival at Home (specs/018-m11-ads, research
// R14, T047): due for an unseen grant with no local `ad_reward_seen`, the
// newest first, rank 40. The dialog itself is `piggy_banner_test.dart`'s.

PiggyGrant _grant(String nonce, int at) =>
    PiggyGrant(nonce: nonce, jenehat: 30, bonat: 2, grantedAtMs: at);

Future<(ProviderContainer, TestEconomy)> _container(
  List<PiggyGrant> unseen,
) async {
  final economy = await testEconomy();
  final container = ProviderContainer(
    overrides: [
      economyProvider.overrideWith((ref) async => economy.service),
      adsBlockProvider.overrideWithValue(
        AdsBlock(piggyAvailable: false, unseen: unseen),
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(economyProvider.future);
  return (container, economy);
}

void main() {
  test('due with an unseen grant the phone hasn\'t recorded', () async {
    final (container, _) = await _container([_grant('n-1', 1)]);
    const item = PiggyArrival();
    // The first arrival starts reading the log.
    expect(item.isDue(container), isFalse);
    await container.read(unseenPiggiesProvider.future);
    expect(item.isDue(container), isTrue);
  });

  test(
    'not due once seen, even unsynced, while bootstrap still lists it',
    () async {
      final (container, economy) = await _container([_grant('n-1', 1)]);
      await economy.service.markAdRewardSeen(
        economy.service.newRequestId(),
        nonce: 'n-1',
      );
      expect(await opCount(economy, 'ad_reward_seen'), 1);
      expect(economy.service.pendingCount, greaterThan(0));
      expect(await container.read(unseenPiggiesProvider.future), isEmpty);
      expect(const PiggyArrival().isDue(container), isFalse);
    },
  );

  test('the newest first, one per arrival', () async {
    final (container, economy) = await _container([
      _grant('older', 1000),
      _grant('newer', 2000),
    ]);
    final left = await container.read(unseenPiggiesProvider.future);
    expect([for (final g in left) g.nonce], ['newer', 'older']);

    await economy.service.markAdRewardSeen(
      economy.service.newRequestId(),
      nonce: 'newer',
    );
    container.invalidate(unseenPiggiesProvider);
    final after = await container.read(unseenPiggiesProvider.future);
    expect([for (final g in after) g.nonce], ['older']);
  });

  test('rank 40, after the due scene and the name sheet', () async {
    final (container, _) = await _container(const []);
    final ranks = [
      for (final item in container.read(arrivalItemsProvider)) item.rank,
    ];
    expect(ranks, [10, 20, 40]);
    expect(container.read(arrivalItemsProvider).last, isA<PiggyArrival>());
  });

  test('no block: nothing to read', () async {
    final (container, _) = await _container(const []);
    expect(await container.read(unseenPiggiesProvider.future), isEmpty);
  });
}
