import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/bootstrap/startup.dart';
import 'package:wassal/core/config/bundled_config_source.dart';
import 'package:wassal/core/config/config_providers.dart';
import 'package:wassal/core/config/config_source.dart';
import 'package:wassal/core/config/override_config_source.dart';
import 'package:wassal/core/config/tunable.dart';
import 'package:wassal/core/glossary/ids.dart';

import '../../helpers/content.dart';
import '../../helpers/economy.dart';
import '../../helpers/memory_settings_store.dart';

// Reading tunables: overrides first, then the bundled defaults (FR-034,
// FR-035).

final Map<String, Object?> defaults = jsonDecode(
  File('assets/config/tunables.json').readAsStringSync(),
) as Map<String, Object?>;

ProviderContainer containerWith({
  required Map<String, String> assets,
  Flavor flavor = Flavor.dev,
}) {
  final container = ProviderContainer(
    overrides: [
      flavorProvider.overrideWithValue(flavor),
      settingsStoreProvider.overrideWith((ref) => MemorySettingsStore()),
      assetReaderProvider.overrideWithValue((path) async => assets[path]),
      // Startup also loads content; flutter test doesn't bundle its
      // flavor-scoped assets. And it opens the economy's database.
      ...contentTestOverrides(),
      ...economyTestOverrides(),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  final bundled = BundledConfigSource(defaults);

  test('bundled reads return the defaults', () {
    expect(bundled.read(Tunable.fuelMax), 5);
    expect(bundled.read(Tunable.tripHopMs(LineId.lineGamaa)), 1100);
    expect(
      bundled.read(Tunable.tripHintsMode(LineId.lineHay)),
      TripHintsMode.always,
    );
    expect(bundled.read(Tunable.tripPatienceMs), 20000);
    expect(bundled.read(Tunable.preTripCardMode), PreTripCardMode.always);
  });

  test('a hints-mode override applies only with a known wire value', () {
    final hints = Tunable.tripHintsMode(LineId.lineHay);
    final valid = OverrideConfigSource({hints.key: 'off'}, fallback: bundled);
    expect(valid.read(hints), TripHintsMode.off);
    final bad = OverrideConfigSource({
      hints.key: 'sometimes',
    }, fallback: bundled);
    expect(bad.read(hints), TripHintsMode.always);
  });

  test('a valid override changes only its key', () {
    final source = OverrideConfigSource({'fuel_max': 9}, fallback: bundled);
    expect(source.read(Tunable.fuelMax), 9);
    for (final tunable in Tunable.all.where((t) => t != Tunable.fuelMax)) {
      expect(source.read(tunable), bundled.read(tunable), reason: tunable.key);
    }
  });

  for (final bad in <Object?>['nine', true, 9.5, null]) {
    test('an override of $bad falls back to the default', () {
      final source = OverrideConfigSource({'fuel_max': bad}, fallback: bundled);
      expect(source.read(Tunable.fuelMax), 5);
    });
  }

  // The fuel rules divide by the regeneration time and count up to the max
  // (specs/007-m05-local-economy research R8): neither may be below 1.
  for (final fuel in [
    Tunable.fuelMax,
    Tunable.fuelMaxSubscriber,
    Tunable.fuelRegenMinutes,
  ]) {
    for (final bad in [0, -1]) {
      test('an override of $bad for ${fuel.key} falls back to the default', () {
        final source = OverrideConfigSource({fuel.key: bad}, fallback: bundled);
        expect(source.read(fuel), bundled.read(fuel));
        expect(source.read(fuel), greaterThan(0));
      });
    }
  }

  test('a key missing from the bundled defaults is a StateError', () {
    expect(
      () => BundledConfigSource(const {}).read(Tunable.fuelMax),
      throwsStateError,
    );
  });

  final tunablesJson = File('assets/config/tunables.json').readAsStringSync();

  test('dev applies tunables.dev.json over the defaults', () async {
    final container = containerWith(
      assets: {
        bundledTunablesAsset: tunablesJson,
        devTunablesAsset: '{"fuel_max": 9, "rep_fight": "x"}',
      },
    );
    await container.read(appStartupProvider.future);
    final config = container.read(configSourceProvider);
    expect(config.read(Tunable.fuelMax), 9);
    expect(config.read(Tunable.repFight), 30);
  });

  test('a missing dev asset counts as no overrides', () async {
    final container = containerWith(
      assets: {bundledTunablesAsset: tunablesJson},
    );
    await container.read(appStartupProvider.future);
    expect(container.read(configSourceProvider).read(Tunable.fuelMax), 5);
  });

  test('staging and prod ignore dev overrides', () async {
    for (final flavor in [Flavor.staging, Flavor.prod]) {
      final container = containerWith(
        flavor: flavor,
        assets: {
          bundledTunablesAsset: tunablesJson,
          devTunablesAsset: '{"fuel_max": 9}',
        },
      );
      await container.read(appStartupProvider.future);
      expect(container.read(configSourceProvider).read(Tunable.fuelMax), 5);
    }
  });

  test('after startup, reads are synchronous', () async {
    final container = containerWith(
      assets: {bundledTunablesAsset: tunablesJson},
    );
    await container.read(appStartupProvider.future);
    final ConfigSource config = container.read(configSourceProvider);
    final int fuelMax = config.read(Tunable.fuelMax);
    expect(fuelMax, 5);
  });

  testWidgets('the real asset bundle loads at app startup', (tester) async {
    final container = ProviderContainer(
      overrides: [
        flavorProvider.overrideWithValue(Flavor.dev),
        settingsStoreProvider.overrideWith((ref) => MemorySettingsStore()),
        ...contentTestOverrides(),
        ...economyTestOverrides(),
      ],
    );
    addTearDown(container.dispose);
    await tester.runAsync(() => container.read(appStartupProvider.future));
    expect(container.read(configSourceProvider).read(Tunable.fuelMax), 5);
  });
}
