import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/bootstrap/startup.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/preferences/settings_store.dart';
import 'package:wassal/core/routing/router.dart';

import 'content.dart';
import 'memory_settings_store.dart';
import 'surfaces.dart';

/// Pumps the whole app the way `bootstrap()` does, with test overrides.
///
/// [content] replaces the content loader's seams, which default to the
/// sample pack's bundled assets ([contentTestOverrides]).
Future<ProviderContainer> pumpWassalApp(
  WidgetTester tester, {
  List<Override> overrides = const [],
  List<Override>? content,
  String? initialLocation,
  double textScale = 1.0,
  Surface surface = Surface.reference,
  DigitStyle digits = DigitStyle.arabicIndic,
  SettingsStore? settingsStore,
}) async {
  applySurface(tester, surface);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        flavorProvider.overrideWithValue(Flavor.dev),
        // The saved digit style, as the device's preference store holds it.
        settingsStoreProvider.overrideWith(
          (ref) =>
              settingsStore ??
              MemorySettingsStore({DigitStyleNotifier.key: digits.wire}),
        ),
        ...content ?? contentTestOverrides(),
        ...overrides,
      ],
      child: const WassalApp(),
    ),
  );
  await tester.pumpAndSettle();

  final container = ProviderScope.containerOf(
    tester.element(find.byType(WassalApp)),
  );
  if (initialLocation != null) {
    container.read(routerProvider).go(initialLocation);
    await tester.pumpAndSettle();
  }
  return container;
}

GoRouter _router(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(WassalApp)))
        .read(routerProvider);

/// A context below MaterialApp's localizations, theme and text-scale clamp.
BuildContext appContext(WidgetTester tester) =>
    _router(tester).routerDelegate.navigatorKey.currentContext!;

/// The top route's location, for example `/home`, including pushed pages
/// and sheets (the router's own URI leaves those out).
String currentLocation(WidgetTester tester) =>
    _router(tester).state.uri.toString();
