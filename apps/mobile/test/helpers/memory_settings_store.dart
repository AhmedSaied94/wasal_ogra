import 'package:wassal/core/preferences/settings_store.dart';

/// An in-memory [SettingsStore] for widget tests.
final class MemorySettingsStore implements SettingsStore {
  MemorySettingsStore([Map<String, String>? values]) : values = {...?values};

  final Map<String, String> values;

  @override
  String? readString(String key) => values[key];

  @override
  Future<void> writeString(String key, String value) async =>
      values[key] = value;
}
