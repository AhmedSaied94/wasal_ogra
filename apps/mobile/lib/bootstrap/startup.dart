import 'package:flutter_riverpod/flutter_riverpod.dart' show WidgetRef;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wassal/core/config/config_providers.dart';
import 'package:wassal/core/content/content_controller.dart';
import 'package:wassal/core/content/pack_store.dart';
import 'package:wassal/core/platform/app_info.dart';
import 'package:wassal/core/preferences/settings_store.dart';
import 'package:wassal/core/preferences/shared_prefs_settings_store.dart';

part 'startup.g.dart';

/// The device preference store, opened once during startup. After boot it
/// is always loaded, so readers use `requireValue`.
@Riverpod(keepAlive: true)
Future<SettingsStore> settingsStore(Ref ref) =>
    SharedPrefsSettingsStore.create();

/// Everything that must be ready before the boot screen hands over to
/// الموقف, so reads after boot are synchronous. That includes a checked
/// content pack (specs/006-m04-content-loader, FR-008).
@Riverpod(keepAlive: true)
Future<void> appStartup(Ref ref) async {
  await Future.wait([
    ref.watch(settingsStoreProvider.future),
    ref.watch(tunableLayersProvider.future),
    ref.watch(activeContentProvider.future),
  ]);
}

/// Runs startup again after a failure. Each step caches its own result,
/// so the step that failed is reset too, not just [appStartup].
void retryAppStartup(WidgetRef ref) {
  ref
    ..invalidate(settingsStoreProvider)
    ..invalidate(tunableLayersProvider)
    ..invalidate(packStoreProvider)
    ..invalidate(appInfoProvider)
    ..invalidate(activeContentProvider)
    ..invalidate(appStartupProvider);
}
