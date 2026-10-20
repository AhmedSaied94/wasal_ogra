// The rule numbers a trip runs with (FR-067, data-model.md "TripParams"). The
// values come from the app's tunables; there are no defaults in code
// (constitution VIII, contracts/tunables.md).
import 'package:content_models/content_models.dart';

import 'clock.dart';
import 'wire.dart';

/// One out-of-bounds param, for the `bad_params` refusal.
typedef ParamProblem = ({String key, String message});

final class TripParams {
  const TripParams({
    required this.tripHopMs,
    required this.tripUndoWindowMs,
    required this.repFight,
    required this.repFalseAccusation,
    required this.repMissedStop,
    required this.repLiarCaught,
    required this.repExactChange,
    required this.repReviveTo,
    required this.tripStationWarningMs,
    required this.tripHopPctHajja,
    required this.tripHopPctChattyRow,
    required this.tripGroupRedirectHopMs,
    required this.tripWakeMs,
    required this.tripSleeperAwakeMs,
    required this.tripHeadphonesAttentiveMs,
    required this.tripPatienceMs,
    required this.tripPatiencePctHurry,
    required this.tripPatienceDrainPctTraffic,
    required this.tripBumpCollectMs,
    required this.tripBreakMinPiasters,
    required this.tripBreakDelayMs,
    required this.tripTipPiastersRegularCustomer,
    required this.boosterLedgerPeekMs,
    required this.boosterTrafficJamMs,
    required this.boosterTrafficJamMaxPerTrip,
    required this.repShortChange,
    required this.repImpatient,
    required this.repChangeRequestDeclined,
  });

  /// The wire form, a flat object keyed by tunable name. Throws
  /// [FormatException] naming a missing, unknown or non-integer key.
  factory TripParams.fromJson(Map<String, Object?> json) {
    for (final key in json.keys) {
      if (!_keys.contains(key)) {
        throw FormatException('unknown TripParams key: $key');
      }
    }
    return _read(json, (key) => key);
  }

  /// Resolves a flat tunables map, such as the app's `tunables.json`, for
  /// [line]: `trip_hop_ms` comes from `trip_hop_ms_<line_id>`.
  factory TripParams.fromTunables(Map<String, Object?> values, LineId line) =>
      _read(
        values,
        (key) => key == 'trip_hop_ms' ? 'trip_hop_ms_${wireName(line)}' : key,
      );

  static TripParams _read(
    Map<String, Object?> json,
    String Function(String key) source,
  ) {
    int read(String key) {
      final name = source(key);
      final value = json[name];
      if (value is! int) {
        throw FormatException(
          json.containsKey(name)
              ? 'TripParams key $name must be an integer'
              : 'TripParams key $name is missing',
        );
      }
      return value;
    }

    return TripParams(
      tripHopMs: read('trip_hop_ms'),
      tripUndoWindowMs: read('trip_undo_window_ms'),
      repFight: read('rep_fight'),
      repFalseAccusation: read('rep_false_accusation'),
      repMissedStop: read('rep_missed_stop'),
      repLiarCaught: read('rep_liar_caught'),
      repExactChange: read('rep_exact_change'),
      repReviveTo: read('rep_revive_to'),
      tripStationWarningMs: read('trip_station_warning_ms'),
      tripHopPctHajja: read('trip_hop_pct_hajja'),
      tripHopPctChattyRow: read('trip_hop_pct_chatty_row'),
      tripGroupRedirectHopMs: read('trip_group_redirect_hop_ms'),
      tripWakeMs: read('trip_wake_ms'),
      tripSleeperAwakeMs: read('trip_sleeper_awake_ms'),
      tripHeadphonesAttentiveMs: read('trip_headphones_attentive_ms'),
      tripPatienceMs: read('trip_patience_ms'),
      tripPatiencePctHurry: read('trip_patience_pct_hurry'),
      tripPatienceDrainPctTraffic: read('trip_patience_drain_pct_traffic'),
      tripBumpCollectMs: read('trip_bump_collect_ms'),
      tripBreakMinPiasters: read('trip_break_min_piasters'),
      tripBreakDelayMs: read('trip_break_delay_ms'),
      tripTipPiastersRegularCustomer: read(
        'trip_tip_piasters_regular_customer',
      ),
      boosterLedgerPeekMs: read('booster_ledger_peek_ms'),
      boosterTrafficJamMs: read('booster_traffic_jam_ms'),
      boosterTrafficJamMaxPerTrip: read('booster_traffic_jam_max_per_trip'),
      repShortChange: read('rep_short_change'),
      repImpatient: read('rep_impatient'),
      repChangeRequestDeclined: read('rep_change_request_declined'),
    );
  }

  final int tripHopMs;
  final int tripUndoWindowMs;
  final int repFight;
  final int repFalseAccusation;
  final int repMissedStop;
  final int repLiarCaught;
  final int repExactChange;
  final int repReviveTo;
  final int tripStationWarningMs;
  final int tripHopPctHajja;
  final int tripHopPctChattyRow;
  final int tripGroupRedirectHopMs;
  final int tripWakeMs;
  final int tripSleeperAwakeMs;
  final int tripHeadphonesAttentiveMs;
  final int tripPatienceMs;
  final int tripPatiencePctHurry;
  final int tripPatienceDrainPctTraffic;
  final int tripBumpCollectMs;
  final int tripBreakMinPiasters;
  final int tripBreakDelayMs;
  final int tripTipPiastersRegularCustomer;
  final int boosterLedgerPeekMs;
  final int boosterTrafficJamMs;
  final int boosterTrafficJamMaxPerTrip;
  final int repShortChange;
  final int repImpatient;
  final int repChangeRequestDeclined;

  Map<String, int> toJson() => {
    'trip_hop_ms': tripHopMs,
    'trip_undo_window_ms': tripUndoWindowMs,
    'rep_fight': repFight,
    'rep_false_accusation': repFalseAccusation,
    'rep_missed_stop': repMissedStop,
    'rep_liar_caught': repLiarCaught,
    'rep_exact_change': repExactChange,
    'rep_revive_to': repReviveTo,
    'trip_station_warning_ms': tripStationWarningMs,
    'trip_hop_pct_hajja': tripHopPctHajja,
    'trip_hop_pct_chatty_row': tripHopPctChattyRow,
    'trip_group_redirect_hop_ms': tripGroupRedirectHopMs,
    'trip_wake_ms': tripWakeMs,
    'trip_sleeper_awake_ms': tripSleeperAwakeMs,
    'trip_headphones_attentive_ms': tripHeadphonesAttentiveMs,
    'trip_patience_ms': tripPatienceMs,
    'trip_patience_pct_hurry': tripPatiencePctHurry,
    'trip_patience_drain_pct_traffic': tripPatienceDrainPctTraffic,
    'trip_bump_collect_ms': tripBumpCollectMs,
    'trip_break_min_piasters': tripBreakMinPiasters,
    'trip_break_delay_ms': tripBreakDelayMs,
    'trip_tip_piasters_regular_customer': tripTipPiastersRegularCustomer,
    'booster_ledger_peek_ms': boosterLedgerPeekMs,
    'booster_traffic_jam_ms': boosterTrafficJamMs,
    'booster_traffic_jam_max_per_trip': boosterTrafficJamMaxPerTrip,
    'rep_short_change': repShortChange,
    'rep_impatient': repImpatient,
    'rep_change_request_declined': repChangeRequestDeclined,
  };

  static final Set<String> _keys = const TripParams(
    tripHopMs: 0,
    tripUndoWindowMs: 0,
    repFight: 0,
    repFalseAccusation: 0,
    repMissedStop: 0,
    repLiarCaught: 0,
    repExactChange: 0,
    repReviveTo: 0,
    tripStationWarningMs: 0,
    tripHopPctHajja: 0,
    tripHopPctChattyRow: 0,
    tripGroupRedirectHopMs: 0,
    tripWakeMs: 0,
    tripSleeperAwakeMs: 0,
    tripHeadphonesAttentiveMs: 0,
    tripPatienceMs: 0,
    tripPatiencePctHurry: 0,
    tripPatienceDrainPctTraffic: 0,
    tripBumpCollectMs: 0,
    tripBreakMinPiasters: 0,
    tripBreakDelayMs: 0,
    tripTipPiastersRegularCustomer: 0,
    boosterLedgerPeekMs: 0,
    boosterTrafficJamMs: 0,
    boosterTrafficJamMaxPerTrip: 0,
    repShortChange: 0,
    repImpatient: 0,
    repChangeRequestDeclined: 0,
  ).toJson().keys.toSet();

  // Rule bounds, not balancing numbers (rules.md §1.4): a duration is at
  // least a step, a percent is 1..1000, reputation is out of 100, and the two
  // traffic-jam bounds keep the longest trip at 1,500 s (data-model.md
  // "TripParams").
  static const _percent = 100;
  static const _bounds = <String, (int, int?)>{
    'trip_hop_ms': (stepMs, null),
    'trip_group_redirect_hop_ms': (stepMs, null),
    'trip_patience_ms': (stepMs, null),
    'trip_hop_pct_hajja': (1, 1000),
    'trip_hop_pct_chatty_row': (1, 1000),
    'trip_patience_pct_hurry': (1, 1000),
    'trip_patience_drain_pct_traffic': (1, 1000),
    'rep_revive_to': (1, 100),
    'booster_traffic_jam_ms': (0, 60000),
    'booster_traffic_jam_max_per_trip': (0, 5),
  };

  /// Every value outside its bounds, and every percent that scales a hop or
  /// a hurried passenger's patience below one step (data-model.md
  /// "TripParams"). A scaled duration is checked only when its own params
  /// are within bounds.
  List<ParamProblem> problems() {
    final own = <ParamProblem>[
      for (final MapEntry(:key, :value) in toJson().entries)
        if (_bounds[key] ?? (0, null) case (final min, final max)
            when value < min || (max != null && value > max))
          (
            key: key,
            message: max == null
                ? '$key is $value, below $min'
                : '$key is $value, outside $min..$max',
          ),
    ];
    final bad = {for (final problem in own) problem.key};
    return [...own, ..._scaledProblems(bad)];
  }

  // `scale` of rules.md §1.3.
  static int _scale(int x, int pct) => x * pct ~/ _percent;

  List<ParamProblem> _scaledProblems(Set<String> bad) {
    final hops = !bad.contains('trip_hop_ms');
    final hajjaOk = hops && !bad.contains('trip_hop_pct_hajja');
    final chattyOk = hops && !bad.contains('trip_hop_pct_chatty_row');
    final hurryOk =
        !bad.contains('trip_patience_ms') &&
        !bad.contains('trip_patience_pct_hurry');
    final hajja = _scale(tripHopMs, tripHopPctHajja);
    final chatty = _scale(tripHopMs, tripHopPctChattyRow);
    final both = _scale(hajja, tripHopPctChattyRow);
    final hurry = _scale(tripPatienceMs, tripPatiencePctHurry);
    return [
      if (hajjaOk && hajja < stepMs)
        (
          key: 'trip_hop_pct_hajja',
          message: "a hajja's hop would be $hajja ms, below $stepMs",
        ),
      if (chattyOk &&
          (chatty < stepMs || (hajjaOk && hajja >= stepMs && both < stepMs)))
        (
          key: 'trip_hop_pct_chatty_row',
          message:
              'a hop in a chatty row would be '
              '${chatty < both ? chatty : both} ms, below $stepMs',
        ),
      if (hurryOk && hurry < stepMs)
        (
          key: 'trip_patience_pct_hurry',
          message:
              "a hurried passenger's patience would be $hurry ms, "
              'below $stepMs',
        ),
    ];
  }
}
