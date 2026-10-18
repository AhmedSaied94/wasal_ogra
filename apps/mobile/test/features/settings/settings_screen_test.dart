import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/preferences/settings_store.dart';
import 'package:wassal/features/settings/settings_screen.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/routing.dart';

// US3 acceptance 1–3: the digit-style control on /settings.

void main() {
  testWidgets('two options, Arabic-Indic selected by default', (tester) async {
    await pumpWassalApp(tester, initialLocation: '/settings');
    expect(find.byType(SettingsScreen), findsOneWidget);
    final arabic = find.byKey(SettingsScreen.optionKey(DigitStyle.arabicIndic));
    final western = find.byKey(SettingsScreen.optionKey(DigitStyle.western));
    expect(arabic, findsOneWidget);
    expect(western, findsOneWidget);
    expect(find.text('عربية ١٢٣'), findsOneWidget);
    expect(find.text('غربية 123'), findsOneWidget);
    final semantics = tester.ensureSemantics();
    expect(tester.getSemantics(arabic), isSemantics(isSelected: true));
    expect(tester.getSemantics(western), isSemantics(isSelected: false));
    semantics.dispose();
    expect(find.textContaining('١٬٢٥٠'), findsWidgets);
  });

  testWidgets('choosing Western applies everywhere without a restart', (
    tester,
  ) async {
    final container = await pumpWassalApp(tester);
    await tapLink(tester, 'settings');
    await tester.tap(find.byKey(SettingsScreen.optionKey(DigitStyle.western)));
    await tester.pumpAndSettle();

    expect(container.read(digitStyleProvider), DigitStyle.western);
    expect(find.textContaining('1,250'), findsWidgets);
    expect(find.textContaining('١٬٢٥٠'), findsNothing);

    await tapLink(tester, 'account');
    expect(currentLocation(tester), '/settings/account');
    expect(find.textContaining('1,250'), findsWidgets);
    expect(find.textContaining('12:30'), findsWidgets);

    // Back on الموقف too.
    await pressBack(tester);
    await pressBack(tester);
    expect(currentLocation(tester), '/home');
    expect(find.textContaining('8.5'), findsWidgets);
  });

  testWidgets('each option is at least 44×44', (tester) async {
    await pumpWassalApp(tester, initialLocation: '/settings');
    for (final style in DigitStyle.values) {
      final size = tester.getSize(find.byKey(SettingsScreen.optionKey(style)));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }
  });

  testWidgets('a pumped Western preference shows Western from the start', (
    tester,
  ) async {
    await pumpWassalApp(tester, digits: DigitStyle.western);
    expect(find.textContaining('1,250'), findsWidgets);
  });

  testWidgets('a failed save is reported, and the choice still applies', (
    tester,
  ) async {
    final container = await pumpWassalApp(
      tester,
      initialLocation: '/settings',
      settingsStore: _FailingWrites(),
    );
    await tester.tap(find.byKey(SettingsScreen.optionKey(DigitStyle.western)));
    await tester.pumpAndSettle();
    expect(container.read(digitStyleProvider), DigitStyle.western);
    expect(tester.takeException(), isA<FileSystemException>());
  });
}

class _FailingWrites implements SettingsStore {
  @override
  String? readString(String key) => null;

  @override
  Future<void> writeString(String key, String value) async =>
      throw const FileSystemException('disk full');
}
