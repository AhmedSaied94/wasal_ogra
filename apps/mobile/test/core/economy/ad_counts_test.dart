import 'package:drift/drift.dart' show DatabaseConnectionUser;
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/economy.dart';

import '../../helpers/economy.dart';

// The economy's two counts for M11 (specs/018-m11-ads, contracts/
// economy-ops.md, research R9, R10, T011): refill ads on a game day, and
// trip starts.

var _n = 0x100;

/// A log row of [type] at [atMs], as stored by the economy.
Future<void> _row(
  DatabaseConnectionUser db,
  String type, {
  required int atMs,
  String payload = '{}',
  String status = 'pending',
}) => db.customStatement(
  'INSERT INTO ledger_ops (txn_id, op_type, payload, occurred_at_ms, '
  'content_version, fuel_max, fuel_regen_minutes, sync_status) VALUES '
  "('0192f3a1-7b2c-7d4e-8f00-${(_n++).toRadixString(16).padLeft(12, '0')}', "
  "'$type', '$payload', $atMs, 1, 5, 20, '$status')",
);

const _refill = '{"ad_placement":"fuel_refill"}';
const _double = '{"ad_placement":"result_double","ref":"x"}';

/// [h]:[m]:[s] in Cairo on 2026-11-03 (winter, UTC+2).
int _cairo(int h, int m, int s) =>
    DateTime.utc(2026, 11, 3, h - 2, m, s).millisecondsSinceEpoch;

void main() {
  test('refills count on their own Cairo day only', () async {
    final e = await testEconomy();
    // The day before, at its last second; the day itself at its first and
    // its last; the next day at its first.
    await _row(
      e.db,
      'ad_reward',
      atMs: _cairo(0, 0, 0) - 1000,
      payload: _refill,
    );
    await _row(e.db, 'ad_reward', atMs: _cairo(0, 0, 0), payload: _refill);
    await _row(e.db, 'ad_reward', atMs: _cairo(23, 59, 59), payload: _refill);
    await _row(e.db, 'ad_reward', atMs: _cairo(24, 0, 0), payload: _refill);

    expect(
      await e.service.adRewardsOn(AdPlacement.fuelRefill, '2026-11-02'),
      1,
    );
    expect(
      await e.service.adRewardsOn(AdPlacement.fuelRefill, '2026-11-03'),
      2,
    );
    expect(
      await e.service.adRewardsOn(AdPlacement.fuelRefill, '2026-11-04'),
      1,
    );
  });

  test(
    'other placements, other types and rejected rows do not count',
    () async {
      final e = await testEconomy();
      final noon = _cairo(12, 0, 0);
      await _row(e.db, 'ad_reward', atMs: noon, payload: _refill);
      await _row(e.db, 'ad_reward', atMs: noon, payload: _double);
      await _row(e.db, 'trip_start', atMs: noon, payload: _refill);
      await _row(
        e.db,
        'ad_reward',
        atMs: noon,
        payload: _refill,
        status: 'rejected',
      );
      await _row(
        e.db,
        'ad_reward',
        atMs: noon,
        payload: _refill,
        status: 'accepted',
      );

      expect(
        await e.service.adRewardsOn(AdPlacement.fuelRefill, '2026-11-03'),
        2,
      );
      expect(
        await e.service.adRewardsOn(AdPlacement.resultDouble, '2026-11-03'),
        1,
      );
    },
  );

  test("a refill the economy applies counts on today's game day", () async {
    final e = await testEconomy(
      firstState: (nowMs) => EconomyState.newPlayer(
        fuelMax: 5,
        nowMs: nowMs,
      ).copyWith(fuel: FuelState(liters: 0, countedFromMs: nowMs)),
    );
    final applied = await e.service.applyAdReward(
      e.service.newRequestId(),
      placement: AdPlacement.fuelRefill,
    );
    final at = (applied as OpApplied).op.op.occurredAtMs;
    final day = DateTime.fromMillisecondsSinceEpoch(at, isUtc: true);
    // testEpochMs is 2026-10-22 00:00 UTC: 03:00 in Cairo's summer time.
    expect(day.toIso8601String(), startsWith('2026-10-22'));
    expect(
      await e.service.adRewardsOn(AdPlacement.fuelRefill, '2026-10-22'),
      1,
    );
  });

  test('tripStarts counts every trip_start row', () async {
    final e = await testEconomy();
    expect(await e.service.tripStarts(), 0);
    await _row(e.db, 'trip_start', atMs: testEpochMs);
    await _row(e.db, 'trip_start', atMs: testEpochMs, status: 'rejected');
    await _row(e.db, 'ad_reward', atMs: testEpochMs, payload: _refill);
    expect(await e.service.tripStarts(), 2);
  });
}
