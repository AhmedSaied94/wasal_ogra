import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/bootstrap/startup.dart';
import 'package:wassal/bootstrap/status_overlay_host.dart';
import 'package:wassal/core/account/account_providers.dart';
import 'package:wassal/core/art/rive_art.dart';
import 'package:wassal/core/art/rive_scenes.dart';
import 'package:wassal/core/content/content_controller.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/content/home_arrival.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/platform/connectivity.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/features/story/application/story_due_watcher.dart';
import 'package:wassal/features/story/application/story_service.dart';
import 'package:wassal/core/sync/sync_lifecycle.dart';
import 'package:wassal/core/sync/sync_providers.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/components/system_bars.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/home/application/arrival_queue.dart';
import 'package:wassal/features/lines/application/lines_dot_watcher.dart';
import 'package:wassal/features/onboarding/application/first_session_lifecycle.dart';
import 'package:wassal/features/onboarding/application/first_session_service.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// The only locale: Egyptian Arabic, right to left, whatever the device
/// language is (FR-001).
const appLocale = Locale('ar');

/// System text scaling is honored between these bounds (FR-030).
const minTextScale = 1.0;
const maxTextScale = 1.3;

class WassalApp extends ConsumerStatefulWidget {
  const WassalApp({super.key});

  @override
  ConsumerState<WassalApp> createState() => _WassalAppState();
}

class _WassalAppState extends ConsumerState<WassalApp> {
  ContentLifecycle? _content;
  HomeArrivalQueue? _arrivals;
  ProviderSubscription<StoryDueWatcher>? _storyDue;
  LinesDotWatcher? _linesDot;
  AppLifecycleListener? _lifecycle;
  ProviderSubscription<AsyncValue<SyncLifecycle>>? _sync;
  ProviderSubscription<FirstSessionService>? _firstSession;
  ProviderSubscription<AsyncValue<void>>? _restored;

  @override
  void initState() {
    super.initState();
    // Content updates start only after startup, so the boot screen never
    // waits on the network (specs/006-m04-content-loader, FR-015).
    ref.listenManual(appStartupProvider, (_, next) {
      if (next is AsyncData<void>) _afterStartup();
    }, fireImmediately: true);
  }

  void _afterStartup() {
    _content ??= ContentLifecycle(
      router: ref.read(routerProvider),
      controller: ref.read(activeContentProvider.notifier),
      updater: ref.read(contentUpdaterProvider),
      connectivity: ref.read(connectivitySourceProvider),
    );
    // After the content's, so an arrival switches the pack first
    // (specs/013-m08-home-result, research R9).
    _arrivals ??= HomeArrivalQueue(
      ref.read(routerProvider),
      ProviderScope.containerOf(context, listen: false),
    );
    // The lines tab's «new» dot, from any tab (specs/014-m09-lines-vehicles,
    // research R8).
    _linesDot ??= LinesDotWatcher(
      ProviderScope.containerOf(context, listen: false),
    );
    // A fresh clock reading on every return to the foreground, and no fuel
    // timer in the background (specs/007-m05-local-economy, research R9, R17).
    _lifecycle ??= AppLifecycleListener(
      onStateChange: (state) {
        final economy = ref.read(economyProvider).value;
        if (economy != null) unawaited(economy.handleLifecycle(state));
      },
    );
    // The first session's flags follow the economy from here on
    // (specs/012-m07-onboarding/contracts/first-session.md).
    _firstSession ??= ref.listenManual(firstSessionServiceProvider, (_, _) {});
    // M10's due scenes (specs/015-m10-apartment-story, research R3).
    _storyDue ??= ref.listenManual(storyDueWatcherProvider, (_, _) {});
    _backfillStory();
    _restored ??= _listenForRestore();
    // The sync, from here to dispose (specs/011-m06-identity-sync). It never
    // blocks play: one that can't start is reported, and the app stays
    // offline.
    _sync ??= ref.listenManual(syncLifecycleProvider, (_, next) {
      if (next case AsyncError(:final error, :final stackTrace)) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'sync',
          ),
        );
      }
    });
  }

  bool _storyBackfilled = false;

  /// Once a launch, every scene M07 saw that the economy lacks reaches it
  /// (specs/015-m10-apartment-story, contracts/story-flow.md "Recording a
  /// scene", FR-052). It waits for the economy and M07's flags, which it
  /// reads; a failure is reported and play goes on.
  void _backfillStory() {
    if (_storyBackfilled) return;
    _storyBackfilled = true;
    Future<void> run() async {
      await ref.read(economyProvider.future);
      await ref.read(firstSessionFlagsProvider.future);
      await ref.read(storyServiceProvider).backfill();
    }

    unawaited(
      run().catchError((Object error, StackTrace stack) {
        FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stack, library: 'story'),
        );
      }),
    );
  }

  /// A returning player found after the hand-over leaves the opening
  /// (specs/012-m07-onboarding/contracts/first-session.md "A late restore").
  ProviderSubscription<AsyncValue<void>> _listenForRestore() {
    final lifecycle = FirstSessionLifecycle(
      router: ref.read(routerProvider),
      flags: ref.read(firstSessionFlagsProvider.notifier),
      view: () => ref.read(economyViewProvider),
    );
    return ref.listenManual(progressRestoredProvider, (_, next) {
      if (next is! AsyncData<void>) return;
      unawaited(
        lifecycle.restored().catchError((Object error, StackTrace stack) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'onboarding',
            ),
          );
        }),
      );
    });
  }

  @override
  void dispose() {
    _content?.dispose();
    _arrivals?.dispose();
    _linesDot?.dispose();
    _storyDue?.close();
    _lifecycle?.dispose();
    _sync?.close();
    _firstSession?.close();
    _restored?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      debugShowCheckedModeBanner: false,
      routerConfig: ref.watch(routerProvider),
      locale: appLocale,
      supportedLocales: const [appLocale],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      // Same look in light and dark mode (FR-009): no dark theme.
      theme: buildAppTheme(),
      themeMode: ThemeMode.light,
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: minTextScale,
        maxScaleFactor: maxTextScale,
        // Screens are on the ground unless they say otherwise.
        child: SystemBars(
          bottom: ColorTokens.ground,
          // The Rive files once boot has decoded them; static art until
          // then.
          child: RiveArtScope(
            art: ref.watch(riveArtProvider).value,
            scenes: ref.watch(riveScenesProvider).value,
            child: StatusOverlayHost(child: child ?? const SizedBox.shrink()),
          ),
        ),
      ),
    );
  }
}
