// The confirmed base beside the projection (specs/015-m10-apartment-story,
// contracts/economy-ops.md "economy.dart", research R6): what tells a reward
// "on its way" from one received.
import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/economy/economy_sync.dart';
import 'package:wassal/core/sync/domain/wire/server_wallet.dart';

import '../../helpers/economy.dart';

const _player = '0192f1c3-7d1e-7a4b-9c11-000000000001';

EconomyState _withNish(int nowMs) =>
    EconomyState.newPlayer(fuelMax: 5, nowMs: nowMs).copyWith(
      jenehat: 1000,
      bonat: 7,
      ownership: {
        (SkuKind.item, 'salon.nish'): Owned(
          kind: SkuKind.item,
          variantId: 'crystal',
          acquiredAtMs: nowMs,
        ),
      },
    );

SyncAnswer _accepted(List<LedgerOp> batch) => SyncAnswer(
  stateVersion: 9,
  stateStale: false,
  results: [for (final op in batch) OpResult.accepted(op.op.txnId.value)],
  wallet: const ServerWallet(
    jenehat: 1000,
    bonat: 7,
    fuel: 8,
    fuelMax: 8,
    fuelUpdatedAtMs: testEpochMs,
  ),
);

void main() {
  test('a scene recorded and a claim made show in the view at once', () async {
    final e = await testEconomy(firstState: _withNish);

    await e.service.recordScene(
      e.service.newRequestId(),
      chapterId: ChapterId.ch1FirstJob,
      sceneId: 'the_stand',
    );
    await e.service.claimRequest(
      e.service.newRequestId(),
      requestId: 'req_nish_crystal',
    );

    expect(e.service.view.scenesSeen['ch1_first_job'], {'the_stand'});
    expect(e.service.view.requestsClaimed, {'req_nish_crystal'});
    expect(e.service.view.bonat, 7);
  });

  test('a pending scene or claim is in the projection, not the confirmed '
      'base', () async {
    final e = await testEconomy(firstState: _withNish);

    await e.service.recordScene(
      e.service.newRequestId(),
      chapterId: ChapterId.ch1FirstJob,
      sceneId: 'the_stand',
    );
    await e.service.claimRequest(
      e.service.newRequestId(),
      requestId: 'req_nish_crystal',
    );

    final view = e.service.view;
    expect(view.confirmed.scenesSeen, isEmpty);
    expect(view.confirmed.requestsClaimed, isEmpty);
    expect(view.confirmed.owns(SkuKind.item, 'salon.nish'), isTrue);
    expect(view.confirmed.variantOf('salon.nish'), 'crystal');
  });

  test(
    'a pending purchase is in the projection, not the confirmed base',
    () async {
      final e = await testEconomy(
        firstState: (nowMs) {
          return EconomyState.newPlayer(
            fuelMax: 5,
            nowMs: nowMs,
          ).copyWith(jenehat: 1000);
        },
      );

      await e.service.buy(
        e.service.newRequestId(),
        kind: SkuKind.item,
        skuId: 'salon.nish',
        variantId: 'classic',
      );

      final view = e.service.view;
      expect(view.owns(SkuKind.item, 'salon.nish'), isTrue);
      expect(view.variantOf('salon.nish'), 'classic');
      expect(view.confirmed.owns(SkuKind.item, 'salon.nish'), isFalse);
      expect(view.confirmed.variantOf('salon.nish'), isNull);
    },
  );

  test('after an accepted answer both have it', () async {
    final e = await testEconomy(firstState: _withNish);
    final applied = await e.service.recordScene(
      e.service.newRequestId(),
      chapterId: ChapterId.ch1FirstJob,
      sceneId: 'the_stand',
    ) as OpApplied;
    final claim = await e.service.claimRequest(
      e.service.newRequestId(),
      requestId: 'req_nish_crystal',
    ) as OpApplied;

    await e.service.applyAnswer(
      _accepted([applied.op, claim.op]),
      batch: [applied.op, claim.op],
      playerId: _player,
    );

    final view = e.service.view;
    expect(view.scenesSeen['ch1_first_job'], {'the_stand'});
    expect(view.confirmed.scenesSeen['ch1_first_job'], {'the_stand'});
    expect(view.requestsClaimed, {'req_nish_crystal'});
    expect(view.confirmed.requestsClaimed, {'req_nish_crystal'});
  });

  test('a state replacement sets both', () async {
    final e = await testEconomy();

    await e.service.replaceFromServer(
      EconomyState.newPlayer(fuelMax: 5, nowMs: testEpochMs).copyWith(
        jenehat: 40,
        bonat: 12,
        ownership: {
          (SkuKind.item, 'salon.nish'): Owned(
            kind: SkuKind.item,
            variantId: 'crystal',
            acquiredAtMs: testEpochMs,
          ),
        },
        scenesSeen: {
          'ch4_salon': {'family_visit'},
        },
        requestsClaimed: {'req_nish_crystal'},
      ),
      playerId: _player,
      stateVersion: 12,
    );

    final view = e.service.view;
    expect(view.scenesSeen['ch4_salon'], {'family_visit'});
    expect(view.confirmed.scenesSeen['ch4_salon'], {'family_visit'});
    expect(view.requestsClaimed, {'req_nish_crystal'});
    expect(view.confirmed.requestsClaimed, {'req_nish_crystal'});
    expect(view.confirmed.owns(SkuKind.item, 'salon.nish'), isTrue);
  });
}
