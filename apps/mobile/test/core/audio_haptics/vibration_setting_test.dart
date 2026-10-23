import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/startup.dart';
import 'package:wassal/core/audio_haptics/audio_haptics_providers.dart';
import 'package:wassal/core/audio_haptics/vibration_setting.dart';
import 'package:wassal/features/trip/trip_providers.dart';

import '../../helpers/memory_settings_store.dart';
import '../../helpers/trip.dart';

// The press feedback and its switch (specs/008.5-m21-design-refresh,
// research R4).

Future<ProviderContainer> _container(
  MemorySettingsStore store,
  FakeHaptics haptics,
) async {
  final container = ProviderContainer(
    overrides: [
      settingsStoreProvider.overrideWith((ref) async => store),
      hapticsProvider.overrideWithValue(haptics),
    ],
  );
  addTearDown(container.dispose);
  await container.read(settingsStoreProvider.future);
  return container;
}

void main() {
  test("the key is M02's, so a stored choice carries over", () {
    expect(vibrationKey, 'pref.trip_haptics');
  });

  test('a press ticks once when vibration is on', () async {
    final haptics = FakeHaptics();
    final container = await _container(
      MemorySettingsStore({vibrationKey: 'on'}),
      haptics,
    );
    container.read(pressFeedbackProvider)();
    expect(haptics.felt, ['selection']);
  });

  test('vibration is on when nothing is stored', () async {
    final haptics = FakeHaptics();
    final container = await _container(MemorySettingsStore(), haptics);
    expect(container.read(vibrationEnabledProvider), isTrue);
    container.read(pressFeedbackProvider)();
    expect(haptics.felt, ['selection']);
  });

  test('a press is silent when vibration is off', () async {
    final haptics = FakeHaptics();
    final container = await _container(
      MemorySettingsStore({vibrationKey: 'off'}),
      haptics,
    );
    container.read(pressFeedbackProvider)();
    expect(haptics.felt, isEmpty);
  });

  test("turning the trip's vibration off silences presses at once", () async {
    final haptics = FakeHaptics();
    final container = await _container(
      MemorySettingsStore({vibrationKey: 'on'}),
      haptics,
    );
    expect(container.read(vibrationEnabledProvider), isTrue);
    await container.read(tripSettingsProvider.notifier).setHaptics(on: false);
    container.read(pressFeedbackProvider)();
    expect(haptics.felt, isEmpty);
    expect(container.read(vibrationEnabledProvider), isFalse);
  });
}
