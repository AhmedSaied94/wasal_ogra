import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/startup.dart';
import 'package:wassal/core/preferences/shared_prefs_settings_store.dart';
import 'package:wassal/features/trip/application/trip_settings.dart';
import 'package:wassal/features/trip/trip_providers.dart';

import '../../../helpers/memory_settings_store.dart';

void main() {
  test('defaults: sound and vibration on, no hints seen', () {
    final settings = TripSettings.read(MemorySettingsStore());
    expect(settings.soundOn, isTrue);
    expect(settings.hapticsOn, isTrue);
    expect(settings.hintsSeen, isEmpty);
  });

  test('reads stored values, and unknown ones as defaults', () {
    final settings = TripSettings.read(
      MemorySettingsStore({
        tripSoundKey: 'off',
        tripHapticsKey: 'maybe',
        tripHintsSeenKey: 'sleeper,,hajja',
      }),
    );
    expect(settings.soundOn, isFalse);
    expect(settings.hapticsOn, isTrue);
    expect(settings.hintsSeen, {'sleeper', 'hajja'});
  });

  test('the notifier saves each change under its key', () async {
    final store = MemorySettingsStore();
    final container = ProviderContainer(
      overrides: [settingsStoreProvider.overrideWith((ref) async => store)],
    );
    addTearDown(container.dispose);
    await container.read(settingsStoreProvider.future);
    final notifier = container.read(tripSettingsProvider.notifier);

    await notifier.setSound(on: false);
    await notifier.setHaptics(on: false);
    await notifier.markHintSeen('sleeper');
    await notifier.markHintSeen('hajja');
    await notifier.markHintSeen('sleeper');

    expect(store.values, {
      tripSoundKey: 'off',
      tripHapticsKey: 'off',
      tripHintsSeenKey: 'hajja,sleeper',
    });
    expect(container.read(tripSettingsProvider).hintsSeen, {
      'sleeper',
      'hajja',
    });
  });

  test('the shared preferences store allows the three keys', () {
    expect(
      SharedPrefsSettingsStore.keys,
      containsAll([tripSoundKey, tripHapticsKey, tripHintsSeenKey]),
    );
  });
}
