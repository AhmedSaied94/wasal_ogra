import 'package:flutter_riverpod/flutter_riverpod.dart' show WidgetRef;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wassal/bootstrap/boot_progress.dart';
import 'package:wassal/core/config/config_providers.dart';
import 'package:wassal/core/content/content_controller.dart';
import 'package:wassal/core/content/pack_store.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/platform/app_info.dart';
import 'package:wassal/core/preferences/settings_store.dart';
import 'package:wassal/core/preferences/shared_prefs_settings_store.dart';
import 'package:wassal/core/art/rive_art.dart';

part 'startup.g.dart';

/// The device preference store, opened once during startup. After boot it
/// is always loaded, so readers use `requireValue`.
@Riverpod(keepAlive: true)
Future<SettingsStore> settingsStore(Ref ref) =>
    SharedPrefsSettingsStore.create();

/// How far startup is, for the loading screen's road bar
/// (specs/008.5-m21-design-refresh, research R6).
@Riverpod(keepAlive: true)
class BootProgressNotifier extends _$BootProgressNotifier {
  @override
  BootProgress build() => const BootProgress();

  void markDone(BootStep step) => state = state.withDone(step);

  /// Keeps the first failure, so a step that fails because an earlier one
  /// did doesn't hide it.
  void markFailed(BootStep step) {
    if (state.failed == null) state = state.withFailure(step);
  }
}

/// Everything that must be ready before the boot screen hands over to
/// الموقف, so reads after boot are synchronous. That includes a checked
/// content pack (specs/006-m04-content-loader, FR-008) and the opened economy
/// (specs/007-m05-local-economy, FR-005). Each step reports to
/// [bootProgressProvider] as it finishes.
@Riverpod(keepAlive: true)
Future<void> appStartup(Ref ref) {
  final progress = ref.read(bootProgressProvider.notifier);
  return trackBootSteps(
    {
      BootStep.settings: ref.watch(settingsStoreProvider.future),
      BootStep.tunables: ref.watch(tunableLayersProvider.future),
      BootStep.content: ref.watch(activeContentProvider.future),
      BootStep.database: ref.watch(appDatabaseProvider.future),
      BootStep.economy: ref.watch(economyProvider.future),
      BootStep.art: ref.watch(riveArtProvider.future),
    },
    onDone: progress.markDone,
    onFailed: progress.markFailed,
  );
}

/// Runs startup again after a failure. Each step caches its own result,
/// so the step that failed is reset too, not just [appStartup]. The art
/// keeps its file: its step never fails (`loadRiveArt`).
void retryAppStartup(WidgetRef ref) {
  ref
    ..invalidate(settingsStoreProvider)
    ..invalidate(tunableLayersProvider)
    ..invalidate(packStoreProvider)
    ..invalidate(appInfoProvider)
    ..invalidate(activeContentProvider)
    ..invalidate(uptimeSnapshotProvider)
    ..invalidate(appDatabaseProvider)
    ..invalidate(economyStoreProvider)
    ..invalidate(trustedClockProvider)
    ..invalidate(economyProvider)
    ..invalidate(bootProgressProvider)
    ..invalidate(appStartupProvider);
}
