import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/game_day.dart';

// The game days the server and the app share (fixtures/economy/game_day.json,
// specs/018-m11-ads research R9). The backend's
// apps/economy/tests/test_game_day_fixture.py checks the file against its
// `game_date` (Python's `Africa/Cairo`); here every case replays through
// `gameDayOf`. If one fails, the zone's rule changed: fix `gameDayOf`, never
// the case.

const _fixture = '../../fixtures/economy/game_day.json';

int _utc(int y, int m, int d, [int h = 0, int min = 0, int s = 0]) =>
    DateTime.utc(y, m, d, h, min, s).millisecondsSinceEpoch;

void main() {
  final cases = (jsonDecode(File(_fixture).readAsStringSync()) as List)
      .cast<Map<String, Object?>>();

  test('the fixture is there and covers ten years', () {
    expect(cases.length, greaterThan(300));
  });

  test('every shared case gives the server\'s date', () {
    final wrong = [
      for (final kase in cases)
        if (gameDayOf(kase['ms']! as int) != kase['date'])
          '${kase['ms']}: ${gameDayOf(kase['ms']! as int)} != ${kase['date']}',
    ];
    expect(wrong, isEmpty, reason: wrong.join('\n'));
  });

  test('Cairo midnight in winter (UTC+2) and in summer (UTC+3)', () {
    expect(gameDayOf(_utc(2026, 1, 14, 21, 59, 59)), '2026-01-14');
    expect(gameDayOf(_utc(2026, 1, 14, 22)), '2026-01-15');
    expect(gameDayOf(_utc(2026, 7, 14, 20, 59, 59)), '2026-07-14');
    expect(gameDayOf(_utc(2026, 7, 14, 21)), '2026-07-15');
  });

  test('the switches of 2026: the last Friday of April, the last Thursday of '
      'October', () {
    // 2026-04-24 00:00 local standard time is 2026-04-23 22:00 UTC.
    expect(gameDayOf(_utc(2026, 4, 23, 21, 59, 59)), '2026-04-23');
    expect(gameDayOf(_utc(2026, 4, 23, 22)), '2026-04-24');
    // 2026-10-29 24:00 local summer time is 2026-10-29 21:00 UTC.
    expect(gameDayOf(_utc(2026, 10, 29, 20, 59, 59)), '2026-10-29');
    expect(gameDayOf(_utc(2026, 10, 29, 22)), '2026-10-30');
  });

  test(
    'before 2023 Egypt kept no daylight saving',
    () {
      expect(gameDayOf(_utc(2022, 7, 14, 21, 30)), '2022-07-14');
    },
    skip:
        'gameDayOf codes the rule Egypt has kept since 2023 only; the game '
        'has no trusted time before 2026.',
  );
}
