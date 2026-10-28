// The pre-trip card's setting (specs/013-m08-home-result FR-024, research
// R6): its row on Settings, the saved `pref.pre_trip_card`, and the
// `pre_trip_card_mode` tunable when nothing valid is saved.
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/startup.dart';
import 'package:wassal/core/config/bundled_config_source.dart';
import 'package:wassal/core/config/config_providers.dart';
import 'package:wassal/core/config/config_source.dart';
import 'package:wassal/core/config/tunable.dart';
import 'package:wassal/features/pre_trip/application/card_mode_provider.dart';
import 'package:wassal/features/settings/settings_screen.dart';

import '../../helpers/economy.dart';
import '../../helpers/memory_settings_store.dart';
import '../../helpers/pump_app.dart';

const _key = PreTripCardModeNotifier.key;

/// The bundled tunables with `pre_trip_card_mode` set to [mode].
final class _Tunables implements ConfigSource {
  _Tunables(this.mode);

  final PreTripCardMode mode;
  final _bundled = BundledConfigSource(bundledTunables());

  @override
  T read<T extends Object>(Tunable<T> key) =>
      identical(key, Tunable.preTripCardMode) ? mode as T : _bundled.read(key);
}

void _expectChosen(WidgetTester tester, PreTripCardMode mode) {
  for (final option in PreTripCardMode.values) {
    expect(
      tester.getSemantics(find.byKey(SettingsScreen.cardOptionKey(option))),
      isSemantics(isSelected: option == mode),
      reason: option.wire,
    );
  }
}

void main() {
  testWidgets('the row, «يظهر دايمًا» by default (the bundled tunable)', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final container = await pumpWassalApp(tester, initialLocation: '/settings');
    expect(find.text('كارت ما قبل المشوار'), findsOneWidget);
    expect(find.text('يظهر دايمًا'), findsOneWidget);
    expect(find.text('في الجديد بس'), findsOneWidget);
    _expectChosen(tester, PreTripCardMode.always);
    expect(container.read(preTripCardModeProvider), PreTripCardMode.always);
    semantics.dispose();
  });

  testWidgets('choosing «في الجديد بس» applies at once and is saved', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final store = MemorySettingsStore();
    final container = await pumpWassalApp(
      tester,
      initialLocation: '/settings',
      settingsStore: store,
    );
    await tester.tap(
      find.byKey(SettingsScreen.cardOptionKey(PreTripCardMode.newOnly)),
    );
    await tester.pumpAndSettle();
    _expectChosen(tester, PreTripCardMode.newOnly);
    expect(container.read(preTripCardModeProvider), PreTripCardMode.newOnly);
    expect(store.values[_key], 'new_only');
    semantics.dispose();
  });

  testWidgets('a saved choice shows from the start', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpWassalApp(
      tester,
      initialLocation: '/settings',
      settingsStore: MemorySettingsStore({_key: 'new_only'}),
    );
    _expectChosen(tester, PreTripCardMode.newOnly);
    semantics.dispose();
  });

  for (final (what, saved) in [('missing', null), ('invalid', 'sometimes')]) {
    testWidgets('$what: the tunable', (tester) async {
      final container = await pumpWassalApp(
        tester,
        initialLocation: '/settings',
        settingsStore: MemorySettingsStore({_key: ?saved}),
        overrides: [
          configSourceProvider.overrideWithValue(
            _Tunables(PreTripCardMode.newOnly),
          ),
        ],
      );
      expect(container.read(preTripCardModeProvider), PreTripCardMode.newOnly);
      expect(
        container.read(settingsStoreProvider).requireValue.readString(_key),
        saved,
      );
    });
  }
}
