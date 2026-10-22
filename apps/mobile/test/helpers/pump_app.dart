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
import 'economy.dart';
import 'memory_settings_store.dart';
import 'surfaces.dart';
import 'trip.dart';

/// Pumps the whole app the way `bootstrap()` does, with test overrides.
///
/// [content] replaces the content loader's seams, which default to the
/// sample pack's bundled assets ([contentTestOverrides]). [economy] replaces
/// the economy's, which default to a database in memory
/// ([economyTestOverrides]). [trip] replaces the trip screen's platform
/// edges, which are always fakes ([tripTestOverrides]). [overrides] come
/// last. [size]
/// replaces [surface]'s frame (the trip's surfaces). Without [settle], the
/// initial location gets a fixed number of frames ([pumpFrames]).
Future<ProviderContainer> pumpWassalApp(
  WidgetTester tester, {
  List<Override> overrides = const [],
  List<Override>? content,
  List<Override>? economy,
  List<Override>? trip,
  Flavor flavor = Flavor.dev,
  String? initialLocation,
  double textScale = 1.0,
  Surface surface = Surface.reference,
  Size? size,
  DigitStyle digits = DigitStyle.arabicIndic,
  SettingsStore? settingsStore,
  bool settle = true,
}) async {
  applySurfaceSize(tester, size ?? surface.size);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        flavorProvider.overrideWithValue(flavor),
        // The saved digit style, as the device's preference store holds it.
        settingsStoreProvider.overrideWith(
          (ref) =>
              settingsStore ??
              MemorySettingsStore({DigitStyleNotifier.key: digits.wire}),
        ),
        ...content ?? contentTestOverrides(),
        ...economy ?? economyTestOverrides(),
        ...trip ?? tripTestOverrides(),
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
    await (settle ? tester.pumpAndSettle() : pumpFrames(tester));
  }
  return container;
}

/// Pumps [count] frames of [step] each: for screens with a clock on them
/// (a countdown that ticks every second), where nothing ever settles.
Future<void> pumpFrames(
  WidgetTester tester, {
  int count = 20,
  Duration step = const Duration(milliseconds: 50),
}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(step);
  }
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
