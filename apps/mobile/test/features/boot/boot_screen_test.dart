import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/bootstrap/startup.dart';
import 'package:wassal/core/config/config_providers.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/core/platform/launch_metrics.dart';
import 'package:wassal/core/theme/tokens/colors.dart';
import 'package:wassal/features/boot/boot_screen.dart';

import '../../helpers/pump_app.dart';

const launchChannel = MethodChannel('wassal/launch');

void main() {
  late List<String> launchCalls;

  setUp(() {
    LaunchMetrics.resetForTest();
    launchCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launchChannel, (call) async {
          launchCalls.add(call.method);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launchChannel, null);
  });

  testWidgets('first frame is shams with the app name (FR-012)', (
    tester,
  ) async {
    final startup = Completer<void>();
    await pumpWassalApp(
      tester,
      overrides: [appStartupProvider.overrideWith((ref) => startup.future)],
    );

    expect(currentLocation(tester), '/boot');
    final scaffold = tester.widget<Scaffold>(
      find.descendant(
        of: find.byType(BootScreen),
        matching: find.byType(Scaffold),
      ),
    );
    expect(scaffold.backgroundColor, ColorTokens.shams);
    expect(find.text('وصّل الأجرة'), findsOneWidget);
    expect(launchCalls, isEmpty, reason: 'الموقف has not drawn yet');
  });

  testWidgets('hands over to الموقف once startup completes', (tester) async {
    final startup = Completer<void>();
    await pumpWassalApp(
      tester,
      overrides: [appStartupProvider.overrideWith((ref) => startup.future)],
    );
    startup.complete();
    await tester.pumpAndSettle();
    expect(currentLocation(tester), '/home');
    expect(find.byType(BootScreen), findsNothing);
  });

  testWidgets('a failed startup shows a retry that recovers', (tester) async {
    var attempts = 0;
    await pumpWassalApp(
      tester,
      overrides: [
        appStartupProvider.overrideWith((ref) async {
          attempts++;
          if (attempts == 1) throw StateError('disk unavailable');
        }),
      ],
    );
    expect(currentLocation(tester), '/boot');
    expect(find.text('حاول تاني'), findsOneWidget);

    await tester.tap(find.text('حاول تاني'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(currentLocation(tester), '/home');
  });

  testWidgets('retry also re-runs the startup step that failed', (
    tester,
  ) async {
    var attempts = 0;
    await pumpWassalApp(
      tester,
      overrides: [
        tunableLayersProvider.overrideWith((ref) async {
          attempts++;
          if (attempts == 1) throw StateError('asset unreadable');
          return const TunableLayers(defaults: {}, overrides: {});
        }),
      ],
    );
    expect(currentLocation(tester), '/boot');
    expect(find.text('حاول تاني'), findsOneWidget);

    await tester.tap(find.text('حاول تاني'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(currentLocation(tester), '/home');
  });

  testWidgets('no screen but boot opens before startup completes', (
    tester,
  ) async {
    final startup = Completer<void>();
    final container = await pumpWassalApp(
      tester,
      overrides: [appStartupProvider.overrideWith((ref) => startup.future)],
    );
    container.read(routerProvider).go('/settings');
    await tester.pumpAndSettle();
    expect(currentLocation(tester), '/boot');
    expect(find.byType(BootScreen), findsOneWidget);

    startup.complete();
    await tester.pumpAndSettle();
    expect(currentLocation(tester), '/home');
  });

  testWidgets('reports fully drawn once, after الموقف first draws (FR-012a)', (
    tester,
  ) async {
    await pumpWassalApp(tester);
    expect(currentLocation(tester), '/home');
    expect(launchCalls, ['reportFullyDrawn']);

    await tester.tap(find.text('الخطوط'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الموقف').last);
    await tester.pumpAndSettle();
    expect(launchCalls, ['reportFullyDrawn']);
  });

  testWidgets('a missing platform handler is not an error', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launchChannel, null);
    await pumpWassalApp(tester);
    expect(currentLocation(tester), '/home');
    expect(tester.takeException(), isNull);
  });
}
