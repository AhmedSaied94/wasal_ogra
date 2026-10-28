import 'package:wassal/core/preferences/settings_store.dart';
import 'package:wassal/core/preferences/shared_prefs_settings_store.dart';

/// An in-memory [SettingsStore] for widget tests. Like the phone's store, it
/// refuses a key missing from [SharedPrefsSettingsStore.keys], so a new
/// preference fails its tests until it is listed there.
final class MemorySettingsStore implements SettingsStore {
  MemorySettingsStore([Map<String, String>? values])
    : values = {...?values}..keys.forEach(_check);

  final Map<String, String> values;

  @override
  String? readString(String key) => values[_check(key)];

  @override
  Future<void> writeString(String key, String value) async =>
      values[_check(key)] = value;

  /// `SharedPreferencesWithCache`'s check, with its message.
  static String _check(String key) {
    if (!SharedPrefsSettingsStore.keys.contains(key)) {
      throw ArgumentError(
        '$key is not included in the PreferencesFilter allowlist',
      );
    }
    return key;
  }
}
