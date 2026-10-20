// TripParams: the wire form and its validation (data-model.md "TripParams").
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/default_params.dart';

const _keys = [
  'trip_hop_ms',
  'trip_undo_window_ms',
  'rep_fight',
  'rep_false_accusation',
  'rep_missed_stop',
  'rep_liar_caught',
  'rep_exact_change',
  'rep_revive_to',
  'trip_station_warning_ms',
  'trip_hop_pct_hajja',
  'trip_hop_pct_chatty_row',
  'trip_group_redirect_hop_ms',
  'trip_wake_ms',
  'trip_sleeper_awake_ms',
  'trip_headphones_attentive_ms',
  'trip_patience_ms',
  'trip_patience_pct_hurry',
  'trip_patience_drain_pct_traffic',
  'trip_bump_collect_ms',
  'trip_break_min_piasters',
  'trip_break_delay_ms',
  'trip_tip_piasters_regular_customer',
  'booster_ledger_peek_ms',
  'booster_traffic_jam_ms',
  'booster_traffic_jam_max_per_trip',
  'rep_short_change',
  'rep_impatient',
  'rep_change_request_declined',
];

Map<String, Object?> _wire() => Map.of(defaultParams().toJson());

List<String> _problemKeys(Map<String, Object?> wire) =>
    TripParams.fromJson(wire).problems().map((problem) => problem.key).toList();

void main() {
  test('the wire form has exactly the 28 keys', () {
    expect(_wire().keys.toSet(), _keys.toSet());
    expect(_keys, hasLength(28));
  });

  test('fromJson and toJson round-trip', () {
    final wire = _wire();
    expect(TripParams.fromJson(wire).toJson(), wire);
    expect(TripParams.fromJson(wire).tripHopMs, 1100);
  });

  test('a missing key is a FormatException naming it', () {
    for (final key in _keys) {
      final wire = _wire()..remove(key);
      expect(
        () => TripParams.fromJson(wire),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains(key),
          ),
        ),
      );
    }
  });

  test('a non-integer value is a FormatException naming the key', () {
    for (final bad in <Object?>['1000', 1000.5, true, null]) {
      final wire = _wire()..['rep_fight'] = bad;
      expect(
        () => TripParams.fromJson(wire),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('rep_fight'),
          ),
        ),
        reason: '$bad',
      );
    }
  });

  test('an unknown key is a FormatException naming it', () {
    final wire = _wire()..['trip_hop_ms_line_hay'] = 1300;
    expect(
      () => TripParams.fromJson(wire),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('trip_hop_ms_line_hay'),
        ),
      ),
    );
  });

  group('problems()', () {
    test('the defaults have none', () {
      expect(defaultParams().problems(), isEmpty);
    });

    test('the step-sized durations are at least 33', () {
      for (final key in [
        'trip_hop_ms',
        'trip_group_redirect_hop_ms',
        'trip_patience_ms',
      ]) {
        // At 33 ms, a percent below 100 would scale it below a step.
        final atStep = _wire()
          ..[key] = 33
          ..['trip_patience_pct_hurry'] = 100;
        expect(_problemKeys(_wire()..[key] = 32), [key]);
        expect(_problemKeys(atStep), isEmpty);
      }
    });

    test('every percent is 1..1000', () {
      // Long enough durations that 1% of them is still a step.
      Map<String, Object?> long() => _wire()
        ..['trip_hop_ms'] = 3300
        ..['trip_patience_ms'] = 3300;
      for (final key in [
        'trip_hop_pct_hajja',
        'trip_hop_pct_chatty_row',
        'trip_patience_pct_hurry',
        'trip_patience_drain_pct_traffic',
      ]) {
        expect(_problemKeys(long()..[key] = 0), [key]);
        expect(_problemKeys(long()..[key] = 1001), [key]);
        expect(_problemKeys(long()..[key] = 1), isEmpty);
        expect(_problemKeys(long()..[key] = 1000), isEmpty);
      }
    });

    test('a percent never scales a hop or patience below one step', () {
      // trip_hop_ms 100: 32% of it is 32 ms, 33% is 33 ms.
      Map<String, Object?> short() => _wire()
        ..['trip_hop_ms'] = 100
        ..['trip_patience_ms'] = 100;
      expect(_problemKeys(short()..['trip_hop_pct_hajja'] = 32), [
        'trip_hop_pct_hajja',
      ]);
      expect(_problemKeys(short()..['trip_hop_pct_hajja'] = 33), isEmpty);
      expect(_problemKeys(short()..['trip_hop_pct_chatty_row'] = 32), [
        'trip_hop_pct_chatty_row',
      ]);
      expect(_problemKeys(short()..['trip_patience_pct_hurry'] = 32), [
        'trip_patience_pct_hurry',
      ]);
      expect(_problemKeys(short()..['trip_patience_pct_hurry'] = 33), isEmpty);
      // A hajja in a chatty row: 60% of 60% of 100 ms is 36 ms, 50% of 60%
      // is 30 ms.
      final both = short()..['trip_hop_pct_hajja'] = 60;
      expect(_problemKeys(both..['trip_hop_pct_chatty_row'] = 60), isEmpty);
      expect(_problemKeys(both..['trip_hop_pct_chatty_row'] = 50), [
        'trip_hop_pct_chatty_row',
      ]);
    });

    test('rep_revive_to is 1..100', () {
      expect(_problemKeys(_wire()..['rep_revive_to'] = 0), ['rep_revive_to']);
      expect(_problemKeys(_wire()..['rep_revive_to'] = 101), ['rep_revive_to']);
      expect(_problemKeys(_wire()..['rep_revive_to'] = 100), isEmpty);
    });

    test('the traffic jam is bounded, keeping the longest trip at 1,500 s', () {
      expect(_problemKeys(_wire()..['booster_traffic_jam_ms'] = 60001), [
        'booster_traffic_jam_ms',
      ]);
      expect(
        _problemKeys(_wire()..['booster_traffic_jam_ms'] = 60000),
        isEmpty,
      );
      expect(_problemKeys(_wire()..['booster_traffic_jam_max_per_trip'] = 6), [
        'booster_traffic_jam_max_per_trip',
      ]);
      expect(
        _problemKeys(_wire()..['booster_traffic_jam_max_per_trip'] = 5),
        isEmpty,
      );
    });

    test('every other field is at least 0', () {
      const bounded = {
        'trip_hop_ms',
        'trip_group_redirect_hop_ms',
        'trip_patience_ms',
        'trip_hop_pct_hajja',
        'trip_hop_pct_chatty_row',
        'trip_patience_pct_hurry',
        'trip_patience_drain_pct_traffic',
        'rep_revive_to',
      };
      for (final key in _keys.where((key) => !bounded.contains(key))) {
        expect(_problemKeys(_wire()..[key] = -1), [key], reason: key);
        expect(_problemKeys(_wire()..[key] = 0), isEmpty, reason: key);
      }
    });

    test('every problem is reported', () {
      final wire = _wire()
        ..['rep_fight'] = -1
        ..['trip_hop_ms'] = 0;
      expect(_problemKeys(wire), unorderedEquals(['rep_fight', 'trip_hop_ms']));
    });
  });
}
