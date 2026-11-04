import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/fold.dart';
import 'package:wassal/core/economy/domain/rules.dart';
import 'package:wassal/core/economy/economy.dart';

import '../../helpers/economy.dart';

// `ad_reward_seen` (specs/018-m11-ads, contracts/economy-ops.md, research
// R13, T010): one row per shown piggy reward, no deltas, no projection
// change, and a repeat of the same nonce refused.

const _nonce = '0192f3a1-7b2c-4d4e-8f00-000000000001';

void main() {
  test(
    'stores one row with the nonce, no deltas, and changes nothing',
    () async {
      final e = await testEconomy();
      final before = e.service.state;
      final outcome = await e.service.markAdRewardSeen(
        e.service.newRequestId(),
        nonce: _nonce,
      );
      final applied = outcome as OpApplied;
      expect(applied.repeated, isFalse);
      final op = applied.op.op;
      expect(op.type, OpType.adRewardSeen);
      expect(op.payload, {'nonce': _nonce});
      expect(op.jenehatDelta, 0);
      expect(op.bonatDelta, 0);
      expect(op.fuelDelta, 0);
      expect(op.reason, isNull);
      expect(op.ref, isNull);
      expect(e.service.state.jenehat, before.jenehat);
      expect(e.service.state.bonat, before.bonat);
      expect(e.service.state.fuel, before.fuel);
      expect(e.service.pendingCount, 1);
    },
  );

  test('a new request id with the same nonce is refused', () async {
    final e = await testEconomy();
    await e.service.markAdRewardSeen(e.service.newRequestId(), nonce: _nonce);
    final again = await e.service.markAdRewardSeen(
      e.service.newRequestId(),
      nonce: _nonce,
    );
    expect((again as OpRefused).code, EconomyRefusal.alreadyRecorded);
    expect(e.service.pendingCount, 1);
  });

  test('the same request id again is a repeat', () async {
    final e = await testEconomy();
    final id = e.service.newRequestId();
    await e.service.markAdRewardSeen(id, nonce: _nonce);
    final again = await e.service.markAdRewardSeen(id, nonce: _nonce);
    expect((again as OpApplied).repeated, isTrue);
    expect(e.service.pendingCount, 1);
  });

  test('adRewardSeen is true whatever the sync status', () async {
    final e = await testEconomy();
    expect(await e.service.adRewardSeen(_nonce), isFalse);
    await e.service.markAdRewardSeen(e.service.newRequestId(), nonce: _nonce);
    expect(await e.service.adRewardSeen(_nonce), isTrue);
    for (final status in ['accepted', 'rejected']) {
      await e.db.customStatement(
        "UPDATE ledger_ops SET sync_status = '$status' "
        "WHERE op_type = 'ad_reward_seen'",
      );
      expect(await e.service.adRewardSeen(_nonce), isTrue, reason: status);
    }
    expect(await e.service.adRewardSeen('another'), isFalse);
  });

  test('the fold after a rebuild skips it', () async {
    final e = await testEconomy(dbFile: tempDbFile());
    await e.service.markAdRewardSeen(e.service.newRequestId(), nonce: _nonce);
    final state = e.service.state;
    final ops = [for (final op in await e.service.pendingOps()) op.op];
    final folded = fold(state, ops, const ProductionRules());
    expect(folded.state.jenehat, state.jenehat);
    expect(folded.state.bonat, state.bonat);
    expect(const ProductionRules().stillValid(state, ops.single), isTrue);
    final reopened = await reopen(e);
    expect(reopened.service.state.jenehat, state.jenehat);
  });
}
