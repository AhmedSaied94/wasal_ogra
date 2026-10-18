import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/config/tunable.dart';
import 'package:wassal/core/glossary/ids.dart';

// The bundled defaults are the single source of balancing values
// (contracts/tunables.md, constitution VIII, FR-031 – FR-033, SC-007).

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
  'trip_hints_enabled_line_hay': true,
  'trip_hints_enabled_line_gamaa': false,
  'trip_hints_enabled_line_souq': false,
  'trip_hints_enabled_line_masyaf': false,
  'trip_hints_enabled_line_safar': false,
  'trip_undo_window_ms': 1000,
  'rep_fight': 30,
  'rep_false_accusation': 20,
  'rep_missed_stop': 15,
  'rep_liar_caught': 10,
  'rep_exact_change': 3,
  'rep_revive_to': 40,
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

  test('tunables.json holds exactly the 30 contract keys and values', () {
    expect(expected, hasLength(30));
    expect(bundled.keys.toSet(), expected.keys.toSet());
    for (final MapEntry(:key, :value) in expected.entries) {
      expect(bundled[key], value, reason: key);
      expect(bundled[key].runtimeType, value.runtimeType, reason: key);
    }
  });

  test('per-line keys cover every line', () {
    const hop = [1300, 1100, 900, 900, 900];
    const bubble = [4500, 4000, 3500, 3500, 3500];
    for (final (i, line) in LineId.values.indexed) {
      expect(
        bundled[Tunable.tripHopMs(line).key],
        hop[i],
        reason: line.wireName,
      );
      expect(bundled[Tunable.tripBubbleMinMs(line).key], bubble[i]);
      expect(
        bundled[Tunable.tripHintsEnabled(line).key],
        line == LineId.lineHay,
        reason: 'hints are on only for line_hay (mobile §14.3)',
      );
    }
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
    expect(Tunable.tripHintsEnabled(LineId.lineHay).parse(1), isNull);
    expect(Tunable.tripHintsEnabled(LineId.lineHay).parse(false), isFalse);
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
