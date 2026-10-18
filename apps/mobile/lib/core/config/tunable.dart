import 'package:wassal/core/glossary/ids.dart';

/// How the pre-trip card is shown (`pre_trip_card_mode`).
enum PreTripCardMode {
  always('always'),
  newOnly('new_only');

  const PreTripCardMode(this.wire);

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

  static bool? _bool(Object? raw) => raw is bool ? raw : null;

  static PreTripCardMode? _preTripCardMode(Object? raw) {
    for (final mode in PreTripCardMode.values) {
      if (mode.wire == raw) return mode;
    }
    return null;
  }

  // Per line: `<prefix>_<line_id>`.
  static Tunable<int> tripHopMs(LineId line) =>
      Tunable._('trip_hop_ms_${line.wireName}', _int);
  static Tunable<int> tripBubbleMinMs(LineId line) =>
      Tunable._('trip_bubble_min_ms_${line.wireName}', _int);
  static Tunable<bool> tripHintsEnabled(LineId line) =>
      Tunable._('trip_hints_enabled_${line.wireName}', _bool);

  static const tripUndoWindowMs = Tunable<int>._('trip_undo_window_ms', _int);
  static const repFight = Tunable<int>._('rep_fight', _int);
  static const repFalseAccusation = Tunable<int>._(
    'rep_false_accusation',
    _int,
  );
  static const repMissedStop = Tunable<int>._('rep_missed_stop', _int);
  static const repLiarCaught = Tunable<int>._('rep_liar_caught', _int);
  static const repExactChange = Tunable<int>._('rep_exact_change', _int);
  static const repReviveTo = Tunable<int>._('rep_revive_to', _int);
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

  /// Every registered key: 30 in M03.
  static final List<Tunable<Object>> all = List.unmodifiable([
    for (final line in LineId.values) tripHopMs(line),
    for (final line in LineId.values) tripBubbleMinMs(line),
    for (final line in LineId.values) tripHintsEnabled(line),
    tripUndoWindowMs,
    repFight,
    repFalseAccusation,
    repMissedStop,
    repLiarCaught,
    repExactChange,
    repReviveTo,
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
