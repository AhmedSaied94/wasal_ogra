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
import 'package:wassal/core/sync/server_status.dart';
import 'package:wassal/features/story/story_overrides.dart';

import 'account.dart';
import 'content.dart';
import 'economy.dart';
import 'first_session.dart';
import 'memory_settings_store.dart';
import 'server_status.dart';
import 'surfaces.dart';
import 'trip.dart';

/// Pumps the whole app the way `bootstrap()` does, with test overrides.
///
/// [content] replaces the content loader's seams, which default to the
/// sample pack's bundled assets ([contentTestOverrides]). [economy] replaces
/// the economy's, which default to a database in memory
/// ([economyTestOverrides]). [account] replaces the account's edges, which
/// default to memory stores and an unreachable server
/// ([accountTestOverrides]). [trip] replaces the trip screen's platform
/// edges, which are always fakes ([tripTestOverrides]). [serverStatus] pins
/// what the player is told of the server, online with nothing due unless
/// a test says otherwise; null keeps the real one, which follows the
/// (unreachable) server. Unless [newPlayer], the player is past the first
/// session's screens ([returningPlayerOverrides]), so boot hands over to
/// الموقف. [overrides] come last. [size] replaces
/// [surface]'s frame (the trip's surfaces). Without [settle], the initial
/// location gets a fixed number of frames ([pumpFrames]); without
/// [settleBoot], so does boot.
Future<ProviderContainer> pumpWassalApp(
  WidgetTester tester, {
  List<Override> overrides = const [],
  List<Override>? content,
  List<Override>? economy,
  List<Override>? account,
  List<Override>? trip,
  ServerStatusState? serverStatus = const ServerStatusState(),
  Flavor flavor = Flavor.dev,
  String? initialLocation,
  double textScale = 1.0,
  Surface surface = Surface.reference,
  Size? size,
  DigitStyle digits = DigitStyle.arabicIndic,
  SettingsStore? settingsStore,
  bool settle = true,
  bool settleBoot = true,
  bool newPlayer = false,
}) async {
  applySurfaceSize(tester, size ?? surface.size);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  // A second call is a relaunch: the last app's scope goes first, as a
  // process exit takes it, rather than taking the new overrides.
  await tester.pumpWidget(const SizedBox.shrink());
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
        ...account ?? accountTestOverrides(),
        ...trip ?? tripTestOverrides(),
        // M10's slots, before the test's own (specs/015-m10-apartment-story).
        ...storyOverrides(),
        if (serverStatus != null)
          serverStatusProvider.overrideWith(
            () => PinnedServerStatus(serverStatus),
          ),
        if (!newPlayer) ...returningPlayerOverrides(),
        ...overrides,
      ],
      child: const WassalApp(),
    ),
  );
  await (settleBoot ? tester.pumpAndSettle() : pumpFrames(tester, count: 60));

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

/// The app's router, to go somewhere as a link would.
GoRouter appRouter(WidgetTester tester) => _router(tester);

/// A context below MaterialApp's localizations, theme and text-scale clamp.
BuildContext appContext(WidgetTester tester) =>
    _router(tester).routerDelegate.navigatorKey.currentContext!;

/// The top route's location, for example `/home`, including pushed pages
/// and sheets (the router's own URI leaves those out).
String currentLocation(WidgetTester tester) =>
    _router(tester).state.uri.toString();
