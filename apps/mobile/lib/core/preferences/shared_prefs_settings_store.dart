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
