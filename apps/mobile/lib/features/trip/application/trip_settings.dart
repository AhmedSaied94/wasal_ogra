// The trip's device preferences (data-model.md "Preferences"): sound,
// vibration, and the passenger types بلية has already explained.
import 'package:wassal/core/audio_haptics/vibration_setting.dart';
import 'package:wassal/core/preferences/settings_store.dart';

const tripSoundKey = 'pref.trip_sound';

/// Vibration is the app's, not only the trip's: buttons tick with it too.
const tripHapticsKey = vibrationKey;
const tripHintsSeenKey = 'pref.trip_hints_seen';

const _on = 'on';
const _off = 'off';

final class TripSettings {
  const TripSettings({
    this.soundOn = true,
    this.hapticsOn = true,
    this.hintsSeen = const {},
  });

  /// What [store] holds; missing or unknown values are the defaults.
  factory TripSettings.read(SettingsStore store) => TripSettings(
    soundOn: store.readString(tripSoundKey) != _off,
    hapticsOn: store.readString(tripHapticsKey) != _off,
    hintsSeen: {
      for (final wire in (store.readString(tripHintsSeenKey) ?? '').split(','))
        if (wire.isNotEmpty) wire,
    },
  );

  final bool soundOn;
  final bool hapticsOn;

  /// Archetype wire names.
  final Set<String> hintsSeen;

  TripSettings copyWith({
    bool? soundOn,
    bool? hapticsOn,
    Set<String>? hintsSeen,
  }) => TripSettings(
    soundOn: soundOn ?? this.soundOn,
    hapticsOn: hapticsOn ?? this.hapticsOn,
    hintsSeen: hintsSeen ?? this.hintsSeen,
  );

  /// Writes every value to [store].
  Future<void> write(SettingsStore store) async {
    await store.writeString(tripSoundKey, soundOn ? _on : _off);
    await store.writeString(tripHapticsKey, hapticsOn ? _on : _off);
    await store.writeString(
      tripHintsSeenKey,
      (hintsSeen.toList()..sort()).join(','),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TripSettings &&
      other.soundOn == soundOn &&
      other.hapticsOn == hapticsOn &&
      other.hintsSeen.length == hintsSeen.length &&
      other.hintsSeen.containsAll(hintsSeen);

  @override
  int get hashCode =>
      Object.hash(soundOn, hapticsOn, Object.hashAllUnordered(hintsSeen));
}
