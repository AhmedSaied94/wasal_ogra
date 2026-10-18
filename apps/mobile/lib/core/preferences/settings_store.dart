/// Device-only UI preferences, such as the digit style.
///
/// Scope rule: never tokens, secrets or game state. Tokens belong in
/// flutter_secure_storage and game state in the local database.
abstract interface class SettingsStore {
  /// The stored string, or null when missing or not a string.
  String? readString(String key);

  Future<void> writeString(String key, String value);
}
