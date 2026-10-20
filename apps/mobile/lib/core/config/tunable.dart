import 'package:wassal/core/glossary/ids.dart';

/// How the pre-trip card is shown (`pre_trip_card_mode`).
enum PreTripCardMode {
  always('always'),
  newOnly('new_only');

  const PreTripCardMode(this.wire);

  final String wire;
}

/// When a line shows hints (`trip_hints_mode_<line_id>`, ux-spec «الصعوبة
/// والمساعدة حسب الخط»). `firstTime` shows a passenger type's hint only the
/// first time the player meets that type.
enum TripHintsMode {
  off('off'),
  firstTime('first_time'),
  always('always');

  const TripHintsMode(this.wire);

  final String wire;
}

/// A typed balancing key (constitution VIII, mobile §14.3).
///
/// The registry holds keys and types only. Every value lives in
/// `assets/config/tunables.json`; there are no defaults in code.
final class Tunable<T extends Object> {
  const Tunable._(this.key, this._parse);

  final String key;
  final T? Function(Object? raw) _parse;

  /// The value as [T], or null when [raw] has the wrong type.
  T? parse(Object? raw) => _parse(raw);

  @override
  String toString() => 'Tunable($key)';

  static int? _int(Object? raw) => raw is int ? raw : null;

  static PreTripCardMode? _preTripCardMode(Object? raw) {
    for (final mode in PreTripCardMode.values) {
      if (mode.wire == raw) return mode;
    }
    return null;
  }

  static TripHintsMode? _tripHintsMode(Object? raw) {
    for (final mode in TripHintsMode.values) {
      if (mode.wire == raw) return mode;
    }
    return null;
  }

  // Per line: `<prefix>_<line_id>`.
  static Tunable<int> tripHopMs(LineId line) =>
      Tunable._('trip_hop_ms_${line.wireName}', _int);
  static Tunable<int> tripBubbleMinMs(LineId line) =>
      Tunable._('trip_bubble_min_ms_${line.wireName}', _int);
  static Tunable<TripHintsMode> tripHintsMode(LineId line) =>
      Tunable._('trip_hints_mode_${line.wireName}', _tripHintsMode);

  static const tripUndoWindowMs = Tunable<int>._('trip_undo_window_ms', _int);

  // The trip engine's rule numbers (M01, specs/004-m01-trip-engine/contracts/
  // tunables.md). They reach the engine as `TripParams`.
  static const tripStationWarningMs = Tunable<int>._(
    'trip_station_warning_ms',
    _int,
  );
  static const tripHopPctHajja = Tunable<int>._('trip_hop_pct_hajja', _int);
  static const tripHopPctChattyRow = Tunable<int>._(
    'trip_hop_pct_chatty_row',
    _int,
  );
  static const tripGroupRedirectHopMs = Tunable<int>._(
    'trip_group_redirect_hop_ms',
    _int,
  );
  static const tripWakeMs = Tunable<int>._('trip_wake_ms', _int);
  static const tripSleeperAwakeMs = Tunable<int>._(
    'trip_sleeper_awake_ms',
    _int,
  );
  static const tripHeadphonesAttentiveMs = Tunable<int>._(
    'trip_headphones_attentive_ms',
    _int,
  );
  static const tripPatienceMs = Tunable<int>._('trip_patience_ms', _int);
  static const tripPatiencePctHurry = Tunable<int>._(
    'trip_patience_pct_hurry',
    _int,
  );
  static const tripPatienceDrainPctTraffic = Tunable<int>._(
    'trip_patience_drain_pct_traffic',
    _int,
  );
  static const tripBumpCollectMs = Tunable<int>._('trip_bump_collect_ms', _int);
  static const tripBreakMinPiasters = Tunable<int>._(
    'trip_break_min_piasters',
    _int,
  );
  static const tripBreakDelayMs = Tunable<int>._('trip_break_delay_ms', _int);
  static const tripTipPiastersRegularCustomer = Tunable<int>._(
    'trip_tip_piasters_regular_customer',
    _int,
  );
  static const boosterLedgerPeekMs = Tunable<int>._(
    'booster_ledger_peek_ms',
    _int,
  );
  static const boosterTrafficJamMs = Tunable<int>._(
    'booster_traffic_jam_ms',
    _int,
  );
  static const boosterTrafficJamMaxPerTrip = Tunable<int>._(
    'booster_traffic_jam_max_per_trip',
    _int,
  );

  static const repFight = Tunable<int>._('rep_fight', _int);
  static const repFalseAccusation = Tunable<int>._(
    'rep_false_accusation',
    _int,
  );
  static const repMissedStop = Tunable<int>._('rep_missed_stop', _int);
  static const repLiarCaught = Tunable<int>._('rep_liar_caught', _int);
  static const repExactChange = Tunable<int>._('rep_exact_change', _int);
  static const repReviveTo = Tunable<int>._('rep_revive_to', _int);
  static const repShortChange = Tunable<int>._('rep_short_change', _int);
  static const repImpatient = Tunable<int>._('rep_impatient', _int);
  static const repChangeRequestDeclined = Tunable<int>._(
    'rep_change_request_declined',
    _int,
  );
  static const fuelMax = Tunable<int>._('fuel_max', _int);
  static const fuelMaxSubscriber = Tunable<int>._('fuel_max_subscriber', _int);
  static const fuelRegenMinutes = Tunable<int>._('fuel_regen_minutes', _int);
  static const adsInterstitialEveryNTrips = Tunable<int>._(
    'ads_interstitial_every_n_trips',
    _int,
  );
  static const adsInterstitialGraceTrips = Tunable<int>._(
    'ads_interstitial_grace_trips',
    _int,
  );
  static const adsFuelRefillDailyCap = Tunable<int>._(
    'ads_fuel_refill_daily_cap',
    _int,
  );
  static const preTripCardMode = Tunable<PreTripCardMode>._(
    'pre_trip_card_mode',
    _preTripCardMode,
  );
  static const notifDailyMax = Tunable<int>._('notif_daily_max', _int);

  /// Every registered key: 30 in M03, 50 after M01.
  static final List<Tunable<Object>> all = List.unmodifiable([
    for (final line in LineId.values) tripHopMs(line),
    for (final line in LineId.values) tripBubbleMinMs(line),
    for (final line in LineId.values) tripHintsMode(line),
    tripUndoWindowMs,
    tripStationWarningMs,
    tripHopPctHajja,
    tripHopPctChattyRow,
    tripGroupRedirectHopMs,
    tripWakeMs,
    tripSleeperAwakeMs,
    tripHeadphonesAttentiveMs,
    tripPatienceMs,
    tripPatiencePctHurry,
    tripPatienceDrainPctTraffic,
    tripBumpCollectMs,
    tripBreakMinPiasters,
    tripBreakDelayMs,
    tripTipPiastersRegularCustomer,
    repFight,
    repFalseAccusation,
    repMissedStop,
    repLiarCaught,
    repExactChange,
    repReviveTo,
    repShortChange,
    repImpatient,
    repChangeRequestDeclined,
    boosterLedgerPeekMs,
    boosterTrafficJamMs,
    boosterTrafficJamMaxPerTrip,
    fuelMax,
    fuelMaxSubscriber,
    fuelRegenMinutes,
    adsInterstitialEveryNTrips,
    adsInterstitialGraceTrips,
    adsFuelRefillDailyCap,
    preTripCardMode,
    notifDailyMax,
  ]);
}
