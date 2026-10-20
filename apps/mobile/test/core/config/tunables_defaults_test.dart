import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/config/tunable.dart';
import 'package:wassal/core/glossary/ids.dart';

// The bundled defaults are the single source of balancing values
// (contracts/tunables.md, constitution VIII, FR-031 – FR-033, SC-007).
// M01 adds the trip engine's 20 keys and turns the hints switch into a mode
// (specs/004-m01-trip-engine/contracts/tunables.md).

const expected = <String, Object>{
  'trip_hop_ms_line_hay': 1300,
  'trip_hop_ms_line_gamaa': 1100,
  'trip_hop_ms_line_souq': 900,
  'trip_hop_ms_line_masyaf': 900,
  'trip_hop_ms_line_safar': 900,
  'trip_bubble_min_ms_line_hay': 4500,
  'trip_bubble_min_ms_line_gamaa': 4000,
  'trip_bubble_min_ms_line_souq': 3500,
  'trip_bubble_min_ms_line_masyaf': 3500,
  'trip_bubble_min_ms_line_safar': 3500,
  'trip_hints_mode_line_hay': 'always',
  'trip_hints_mode_line_gamaa': 'first_time',
  'trip_hints_mode_line_souq': 'off',
  'trip_hints_mode_line_masyaf': 'off',
  'trip_hints_mode_line_safar': 'off',
  'trip_undo_window_ms': 1000,
  'trip_station_warning_ms': 8000,
  'trip_hop_pct_hajja': 200,
  'trip_hop_pct_chatty_row': 150,
  'trip_group_redirect_hop_ms': 600,
  'trip_wake_ms': 1000,
  'trip_sleeper_awake_ms': 15000,
  'trip_headphones_attentive_ms': 15000,
  'trip_patience_ms': 20000,
  'trip_patience_pct_hurry': 50,
  'trip_patience_drain_pct_traffic': 150,
  'trip_bump_collect_ms': 3000,
  'trip_break_min_piasters': 1000,
  'trip_break_delay_ms': 1500,
  'trip_tip_piasters_regular_customer': 200,
  'rep_fight': 30,
  'rep_false_accusation': 20,
  'rep_missed_stop': 15,
  'rep_liar_caught': 10,
  'rep_exact_change': 3,
  'rep_revive_to': 40,
  'rep_short_change': 5,
  'rep_impatient': 5,
  'rep_change_request_declined': 5,
  'booster_ledger_peek_ms': 10000,
  'booster_traffic_jam_ms': 10000,
  'booster_traffic_jam_max_per_trip': 3,
  'fuel_max': 5,
  'fuel_max_subscriber': 7,
  'fuel_regen_minutes': 20,
  'ads_interstitial_every_n_trips': 3,
  'ads_interstitial_grace_trips': 10,
  'ads_fuel_refill_daily_cap': 3,
  'pre_trip_card_mode': 'always',
  'notif_daily_max': 2,
};

late Map<String, dynamic> bundled;

void main() {
  setUpAll(() async {
    bundled = jsonDecode(
      await rootBundle.loadString('assets/config/tunables.json'),
    ) as Map<String, dynamic>;
  });

  test('tunables.json holds exactly the 50 contract keys and values', () {
    expect(expected, hasLength(50));
    expect(bundled.keys.toSet(), expected.keys.toSet());
    for (final MapEntry(:key, :value) in expected.entries) {
      expect(bundled[key], value, reason: key);
      expect(bundled[key].runtimeType, value.runtimeType, reason: key);
    }
  });

  test('per-line keys cover every line', () {
    const hop = [1300, 1100, 900, 900, 900];
    const bubble = [4500, 4000, 3500, 3500, 3500];
    const hints = [
      TripHintsMode.always,
      TripHintsMode.firstTime,
      TripHintsMode.off,
      TripHintsMode.off,
      TripHintsMode.off,
    ];
    for (final (i, line) in LineId.values.indexed) {
      expect(
        bundled[Tunable.tripHopMs(line).key],
        hop[i],
        reason: line.wireName,
      );
      expect(bundled[Tunable.tripBubbleMinMs(line).key], bubble[i]);
      final hintsKey = Tunable.tripHintsMode(line).key;
      expect(
        Tunable.tripHintsMode(line).parse(bundled[hintsKey]),
        hints[i],
        reason: 'ux-spec «الصعوبة والمساعدة حسب الخط»: $hintsKey',
      );
    }
  });

  test('trip_hints_mode is one of off/first_time/always', () {
    final hints = Tunable.tripHintsMode(LineId.lineGamaa);
    expect(hints.key, 'trip_hints_mode_line_gamaa');
    expect(hints.parse('off'), TripHintsMode.off);
    expect(hints.parse('first_time'), TripHintsMode.firstTime);
    expect(hints.parse('always'), TripHintsMode.always);
    expect(hints.parse('on'), isNull);
    expect(hints.parse(true), isNull);
    expect(hints.parse(null), isNull);
  });

  test('pre_trip_card_mode is "always", one of always/new_only', () {
    expect(bundled['pre_trip_card_mode'], 'always');
    expect(
      Tunable.preTripCardMode.parse(bundled['pre_trip_card_mode']),
      PreTripCardMode.always,
    );
    expect(Tunable.preTripCardMode.parse('new_only'), PreTripCardMode.newOnly);
    expect(Tunable.preTripCardMode.parse('sometimes'), isNull);
  });

  test('the registry and the file agree on keys and types', () {
    final registered = Tunable.all.map((t) => t.key).toList();
    expect(registered.toSet(), hasLength(registered.length), reason: 'unique');
    expect(registered.toSet(), bundled.keys.toSet());
    for (final tunable in Tunable.all) {
      expect(
        tunable.parse(bundled[tunable.key]),
        isNotNull,
        reason: '${tunable.key} does not parse as its declared type',
      );
    }
  });

  test('parse rejects the wrong JSON type', () {
    expect(Tunable.fuelMax.parse(9), 9);
    expect(Tunable.fuelMax.parse('nine'), isNull);
    expect(Tunable.fuelMax.parse(true), isNull);
    expect(Tunable.fuelMax.parse(9.5), isNull);
    expect(Tunable.fuelMax.parse(null), isNull);
    expect(Tunable.tripHintsMode(LineId.lineHay).parse(1), isNull);
    expect(Tunable.tripStationWarningMs.parse(8000), 8000);
    expect(Tunable.tripStationWarningMs.parse('8000'), isNull);
  });

  test('the dev overrides file ships empty', () {
    // Read from disk: `flutter test` runs without a flavor, so this
    // dev-only asset is not in the test bundle.
    final dev = jsonDecode(
      File('assets/config/tunables.dev.json').readAsStringSync(),
    );
    expect(dev, isEmpty);
  });
}
