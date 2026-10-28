import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/bootstrap/startup.dart';
import 'package:wassal/core/art/rive_art.dart';
import 'package:wassal/core/art/rive_scenes.dart';
import 'package:wassal/core/audio_haptics/audio_haptics_providers.dart';
import 'package:wassal/core/audio_haptics/vibration_setting.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import 'memory_settings_store.dart';
import 'trip.dart';

/// Pumps a «كرتون ناعم» component (specs/008.5-m21-design-refresh) under
/// the app theme, the Arabic locale and RTL, on [background], in a
/// ProviderScope whose haptics are [haptics].
///
/// [vibration] is the stored vibration preference; [reducedMotion] turns
/// on the platform's reduce-motion setting; [size] is the surface at device
/// pixel ratio 1; [overrides] come last, for a screen's providers. No scene
/// panel animates (specs/012.5-m22-animated-scenes, T011): a test that wants
/// turns overrides `scenePanelsProvider`.
Future<void> pumpDesignComponent(
  WidgetTester tester,
  Widget child, {
  FakeHaptics? haptics,
  bool vibration = true,
  bool reducedMotion = false,
  Size size = const Size(390, 844),
  Color? background,
  double textScale = 1,
  bool center = true,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (reducedMotion) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
  if (textScale != 1) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      hapticsProvider.overrideWithValue(haptics ?? FakeHaptics()),
      riveScenesProvider.overrideWith((ref) async => const RiveArt.none()),
      settingsStoreProvider.overrideWith(
        (ref) async =>
            MemorySettingsStore({vibrationKey: vibration ? 'on' : 'off'}),
      ),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  // Startup has loaded the store before any screen shows.
  await container.read(settingsStoreProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAppTheme(),
        locale: appLocale,
        supportedLocales: const [appLocale],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        // A screen's Scaffold gives its text a root style; so does this.
        home: DefaultTextStyle(
          style: TypeTokens.body.copyWith(color: ColorTokens.ink),
          child: ColoredBox(
            color: background ?? ColorTokens.ground,
            child: center
                ? Center(child: child)
                : Align(alignment: Alignment.topCenter, child: child),
          ),
        ),
      ),
    ),
  );
}
