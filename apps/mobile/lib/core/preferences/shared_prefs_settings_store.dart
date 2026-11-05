import 'package:shared_preferences/shared_preferences.dart';
import 'package:wassal/core/preferences/settings_store.dart';

/// [SettingsStore] on shared_preferences (research R11). Reads are
/// synchronous from a cache loaded once at startup.
///
/// Device UI preferences only: never tokens, secrets or game state.
final class SharedPrefsSettingsStore implements SettingsStore {
  SharedPrefsSettingsStore._(this._prefs);

  /// Every key this store may hold.
  static const keys = {
    'pref.digit_style',
    // The trip's (specs/008-m02-trip-screen, data-model.md "Preferences").
    'pref.trip_sound',
    'pref.trip_haptics',
    'pref.trip_hints_seen',
    // The optional update the player closed (M06, `dismissedUpdateKey`).
    'update.dismissedVersion',
    // The pre-trip card's setting (specs/013-m08-home-result, research R6).
    'pref.pre_trip_card',
    // The news Lines has shown (specs/014-m09-lines-vehicles, research R8):
    // a read marker, not game state. Losing it shows the «new» dot once more.
    'pref.lines_seen',
    // The interstitial's pacing (specs/018-m11-ads, data-model.md "Device
    // preferences"): the trip counts when an interstitial last showed and
    // when a rewarded ad last paid. Pacing, not game state.
    'pref.ads_last_interstitial_trip',
    'pref.ads_last_rewarded_trip',
    // The game day the morning piggy's ad last paid: a marker, not game
    // state. Losing it offers an ad the server refuses.
    'pref.ads_piggy_attempted_day',
  };

  final SharedPreferencesWithCache _prefs;

  static Future<SharedPrefsSettingsStore> create() async =>
      SharedPrefsSettingsStore._(
        await SharedPreferencesWithCache.create(
          cacheOptions: const SharedPreferencesWithCacheOptions(
            allowList: keys,
          ),
        ),
      );

  @override
  String? readString(String key) {
    final value = _prefs.get(key);
    return value is String ? value : null;
  }

  @override
  Future<void> writeString(String key, String value) =>
      _prefs.setString(key, value);
}
