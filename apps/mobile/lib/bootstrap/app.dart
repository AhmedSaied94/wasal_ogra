import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/bootstrap/startup.dart';
import 'package:wassal/core/content/content_controller.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/content/home_arrival.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/platform/connectivity.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/core/theme/app_theme.dart';
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
  AppLifecycleListener? _lifecycle;

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
    // A fresh clock reading on every return to the foreground, and no fuel
    // timer in the background (specs/007-m05-local-economy, research R9, R17).
    _lifecycle ??= AppLifecycleListener(
      onStateChange: (state) {
        final economy = ref.read(economyProvider).value;
        if (economy != null) unawaited(economy.handleLifecycle(state));
      },
    );
  }

  @override
  void dispose() {
    _content?.dispose();
    _lifecycle?.dispose();
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
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
