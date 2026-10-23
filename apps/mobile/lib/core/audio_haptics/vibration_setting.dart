// The device's vibration preference and the press feedback that follows it
// (specs/008.5-m21-design-refresh, research R4). Every Pressable ticks
// through pressFeedback, so one switch silences presses and the trip alike.
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wassal/bootstrap/startup.dart';
import 'package:wassal/core/audio_haptics/audio_haptics_providers.dart';

part 'vibration_setting.g.dart';

/// Where vibration is stored. M02 named it for the trip; the string never
/// changes, so a player's choice carries over.
const vibrationKey = 'pref.trip_haptics';

/// Whether vibration is on: anything but `off`, like M02's trip settings.
/// Whoever writes [vibrationKey] invalidates this provider.
@Riverpod(keepAlive: true)
bool vibrationEnabled(Ref ref) =>
    ref.watch(settingsStoreProvider).value?.readString(vibrationKey) != 'off';

/// The tick a control gives when pressed, or nothing with vibration off.
@Riverpod(keepAlive: true)
void Function() pressFeedback(Ref ref) {
  if (!ref.watch(vibrationEnabledProvider)) return _silent;
  final haptics = ref.watch(hapticsProvider);
  return haptics.selection;
}

void _silent() {}
