import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/bootstrap/startup.dart';
import 'package:wassal/core/content/content_controller.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/content/home_arrival.dart';
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

  @override
  void initState() {
    super.initState();
    // Content updates start only after startup, so the boot screen never
    // waits on the network (specs/006-m04-content-loader, FR-015).
    ref.listenManual(appStartupProvider, (_, next) {
      if (next is AsyncData<void>) _startContent();
    }, fireImmediately: true);
  }

  void _startContent() {
    _content ??= ContentLifecycle(
      router: ref.read(routerProvider),
      controller: ref.read(activeContentProvider.notifier),
      updater: ref.read(contentUpdaterProvider),
      connectivity: ref.read(connectivitySourceProvider),
    );
  }

  @override
  void dispose() {
    _content?.dispose();
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
