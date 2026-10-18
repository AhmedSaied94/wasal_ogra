import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// The only locale: Egyptian Arabic, right to left, whatever the device
/// language is (FR-001).
const appLocale = Locale('ar');

/// System text scaling is honored between these bounds (FR-030).
const minTextScale = 1.0;
const maxTextScale = 1.3;

class WassalApp extends ConsumerWidget {
  const WassalApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
