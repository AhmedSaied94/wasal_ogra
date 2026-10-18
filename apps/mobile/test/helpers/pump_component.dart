import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import 'surfaces.dart';

/// Pumps a single component under the app theme, Arabic locale and RTL.
Future<void> pumpComponent(
  WidgetTester tester, {
  Widget? body,
  Widget? bottomBar,
  Surface surface = Surface.reference,
}) async {
  applySurface(tester, surface);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      locale: appLocale,
      supportedLocales: const [appLocale],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      home: Scaffold(
        body: Center(child: body ?? const SizedBox.shrink()),
        bottomNavigationBar: bottomBar,
      ),
    ),
  );
}
