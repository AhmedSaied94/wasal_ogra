import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/bootstrap/startup.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';

import '../../helpers/content.dart';
import '../../helpers/account.dart';
import '../../helpers/economy.dart';

// The digit preference: device-only, persisted, defaulting to Arabic-Indic
// (FR-025 – FR-027, data-model DigitStyle).

const key = 'pref.digit_style';

Future<ProviderContainer> start() async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await container.read(settingsStoreProvider.future);
  return container;
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('wire values', () {
    expect(DigitStyle.arabicIndic.wire, 'arabic_indic');
    expect(DigitStyle.western.wire, 'western');
    expect(DigitStyle.fromWire('western'), DigitStyle.western);
    expect(DigitStyle.fromWire('arabic_indic'), DigitStyle.arabicIndic);
    for (final junk in <Object?>[null, '', 'garbage', 'Western', 3, true]) {
      expect(
        DigitStyle.fromWire(junk),
        DigitStyle.arabicIndic,
        reason: '$junk',
      );
    }
  });

  test('defaults to Arabic-Indic', () async {
    final container = await start();
    expect(container.read(digitStyleProvider), DigitStyle.arabicIndic);
    expect(
      container.read(numberFormatterProvider).style,
      DigitStyle.arabicIndic,
    );
  });

  test('set(western) applies at once and persists', () async {
    final container = await start();
    await container.read(digitStyleProvider.notifier).set(DigitStyle.western);
    expect(container.read(digitStyleProvider), DigitStyle.western);
    expect(container.read(numberFormatterProvider).style, DigitStyle.western);
    final stored = await SharedPreferencesAsyncPlatform.instance!.getString(
      key,
      const SharedPreferencesOptions(),
    );
    expect(stored, 'western');
  });

  test('a stored "arabic_indic" reads back as Arabic-Indic', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({key: 'arabic_indic'});
    final container = await start();
    expect(container.read(digitStyleProvider), DigitStyle.arabicIndic);
  });

  for (final junk in <Object>['garbage', 7, true]) {
    test(
      'a stored $junk (${junk.runtimeType}) reads back as Arabic-Indic',
      () async {
        SharedPreferencesAsyncPlatform.instance =
            InMemorySharedPreferencesAsync.withData({key: junk});
        final container = await start();
        expect(container.read(digitStyleProvider), DigitStyle.arabicIndic);
      },
    );
  }

  test('the choice survives a restart', () async {
    final first = await start();
    await first.read(digitStyleProvider.notifier).set(DigitStyle.western);
    first.dispose();

    final second = await start();
    expect(second.read(digitStyleProvider), DigitStyle.western);
  });

  test('startup opens the store before the app reads it', () async {
    final container = ProviderContainer(
      overrides: [
        flavorProvider.overrideWithValue(Flavor.dev),
        ...contentTestOverrides(),
        ...economyTestOverrides(),
        ...accountTestOverrides(),
      ],
    );
    addTearDown(container.dispose);
    await container.read(appStartupProvider.future);
    expect(container.read(settingsStoreProvider).hasValue, isTrue);
  });
}
