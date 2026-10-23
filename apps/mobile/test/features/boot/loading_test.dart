import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/theme/components/containers.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/boot/boot_screen.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../../helpers/design_component.dart';
import '../../helpers/economy.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/screens.dart';

// The loading screen in the new look (HANDOFF `Loading`, research R6): the
// sun ground, the wordmark and tagline, the vehicle with its roof sign, the
// road bar following the boot steps, and M03's retry as an InlineAlert.

Finder _inBoot(Finder matching) =>
    find.descendant(of: find.byType(BootScreen), matching: matching);

Future<void> _pumpRoad(WidgetTester tester, double value) =>
    pumpDesignComponent(
      tester,
      SizedBox(width: 300, child: ProgressBar.road(value: value)),
    );

double _markerCentre(WidgetTester tester) =>
    tester.getCenter(find.byKey(ProgressBar.roadMarkerKey)).dx;

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('ar'));
  });

  testWidgets('the sun ground, wordmark, tagline, vehicle, sign, bar, line', (
    tester,
  ) async {
    await pumpWassalApp(tester, overrides: pendingStartup());
    final scaffold = tester.widget<Scaffold>(_inBoot(find.byType(Scaffold)));
    expect(scaffold.backgroundColor, ColorTokens.sun);
    expect(_inBoot(find.text(l10n.appName)), findsOne);
    expect(_inBoot(find.text(l10n.loadingTagline)), findsOne);
    expect(
      find.descendant(
        of: find.byKey(BootScreen.vehicleKey),
        matching: find.byType(SvgPicture),
      ),
      findsOne,
    );
    expect(_inBoot(find.text(l10n.destHome)), findsOne);
    expect(_inBoot(find.byKey(ProgressBar.roadMarkerKey)), findsOne);
    expect(
      _inBoot(find.text(loadingLines(l10n).single)),
      findsOne,
      reason: 'the pool has one line so far',
    );
    expect(find.byType(InlineAlert), findsNothing);
  });

  testWidgets('the wordmark has its sun.lip shadow', (tester) async {
    await pumpWassalApp(tester, overrides: pendingStartup());
    final wordmark = tester.widget<Text>(_inBoot(find.text(l10n.appName)));
    expect(wordmark.style!.shadows, [
      const Shadow(offset: Offset(0, 5), color: ColorTokens.sunLip),
    ]);
  });

  group('the road bar', () {
    testWidgets("at 0.62 the marker's centre is 62% in from the right", (
      tester,
    ) async {
      await _pumpRoad(tester, 0.62);
      final bar = tester.getRect(find.byType(ProgressBar));
      expect(bar.size, const Size(300, ProgressBar.roadHeight));
      expect(_markerCentre(tester), closeTo(bar.right - 0.62 * 300, 0.5));
      final marker = tester.getRect(find.byKey(ProgressBar.roadMarkerKey));
      expect(marker.size, ProgressBar.roadMarker);
      expect(marker.top, closeTo(bar.top - 10, 0.5));
    });

    testWidgets('an update tweens linearly within 150 ms', (tester) async {
      await _pumpRoad(tester, 0);
      final bar = tester.getRect(find.byType(ProgressBar));
      await _pumpRoad(tester, 0.4);
      await tester.pump(const Duration(milliseconds: 75));
      expect(_markerCentre(tester), closeTo(bar.right - 0.2 * 300, 1));
      await tester.pump(const Duration(milliseconds: 75));
      expect(_markerCentre(tester), closeTo(bar.right - 0.4 * 300, 0.5));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        _markerCentre(tester),
        closeTo(bar.right - 0.4 * 300, 0.5),
        reason: 'done by 150 ms',
      );
    });

    testWidgets('jumps under reduced motion', (tester) async {
      await pumpDesignComponent(
        tester,
        const SizedBox(width: 300, child: ProgressBar.road(value: 0)),
        reducedMotion: true,
      );
      final bar = tester.getRect(find.byType(ProgressBar));
      await pumpDesignComponent(
        tester,
        const SizedBox(width: 300, child: ProgressBar.road(value: 0.4)),
        reducedMotion: true,
      );
      expect(_markerCentre(tester), closeTo(bar.right - 0.4 * 300, 0.5));
    });

    testWidgets('a screen reader hears its name and percent', (tester) async {
      await pumpDesignComponent(
        tester,
        const SizedBox(
          width: 300,
          child: ProgressBar.road(value: 0.62, semanticLabel: 'التحميل'),
        ),
      );
      final node = tester.getSemantics(find.byType(ProgressBar));
      expect(node.label, 'التحميل');
      expect(node.value, '62%');
    });
  });

  testWidgets('the bar follows the boot steps, then hands over', (
    tester,
  ) async {
    final database = Completer<void>();
    await pumpWassalApp(
      tester,
      economy: [
        uptimeSourceProvider.overrideWithValue(FakeUptimeSource()),
        databaseOpenerProvider.overrideWithValue(() async {
          await database.future;
          return NativeDatabase.memory();
        }),
      ],
    );
    expect(currentLocation(tester), '/boot');
    final bar = tester.getRect(_inBoot(find.byType(ProgressBar)));
    // Settings, tunables, content and the art are done; the database and
    // the economy wait.
    expect(_markerCentre(tester), closeTo(bar.right - 4 / 6 * bar.width, 1));

    database.complete();
    await tester.pumpAndSettle();
    expect(currentLocation(tester), '/home');
  });

  testWidgets('a failed boot shows the InlineAlert with retry', (tester) async {
    await pumpWassalApp(tester, overrides: failedStartup());
    final alert = tester.widget<InlineAlert>(find.byType(InlineAlert));
    expect(alert.message, l10n.bootErrorMessage);
    expect(alert.action, l10n.bootRetry);
    expect(
      _inBoot(find.text(loadingLines(l10n).single)),
      findsNothing,
      reason: 'the alert takes the line',
    );
  });

  testWidgets('the vehicle drives in from the right over 600 ms', (
    tester,
  ) async {
    await pumpWassalApp(
      tester,
      overrides: pendingStartup(),
      initialLocation: null,
    );
    // pumpWassalApp settles, so the entrance has finished: it ends at x 45.
    expect(tester.getRect(find.byKey(BootScreen.vehicleKey)).left, 45);
    expect(BootScreen.vehicleIn, const Duration(milliseconds: 600));
  });

  test('the native splash is the sun (M03 FR-012)', () {
    final splash = File('flutter_native_splash.yaml').readAsStringSync();
    final colours = RegExp(r'color: "#([0-9A-F]{6})"')
        .allMatches(splash)
        .map((m) => m[1])
        .toSet();
    final sun = ColorTokens.sun.toARGB32() & 0xFFFFFF;
    expect(colours, {sun.toRadixString(16).toUpperCase().padLeft(6, '0')});
  });

  test('the native splash is portrait too, held sideways (M03 FR-004)', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final activity = RegExp(
      '<activity[^>]*android:name=".MainActivity"[^>]*>',
      dotAll: true,
    ).firstMatch(manifest)![0]!;
    expect(activity, contains('android:screenOrientation="portrait"'));
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final orientations = RegExp('<string>(UIInterfaceOrientation\\w+)</string>')
        .allMatches(plist)
        .map((m) => m[1])
        .toSet();
    expect(orientations, {'UIInterfaceOrientationPortrait'});
  });
}
