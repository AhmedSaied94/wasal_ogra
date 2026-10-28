import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/bootstrap/startup.dart';
import 'package:wassal/core/account/account_providers.dart';
import 'package:wassal/core/account/account_service.dart' show firstOpenWait;
import 'package:wassal/core/account/domain/account.dart';
import 'package:wassal/core/config/config_providers.dart';
import 'package:wassal/core/config/tunable_snapshot.dart';
import 'package:wassal/core/network/api_client.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/core/platform/launch_metrics.dart';
import 'package:wassal/features/boot/boot_screen.dart';
import 'package:wassal/features/onboarding/data/drift_first_session_store.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/features/trip/data/drift_trip_records.dart';
import 'package:wassal/features/trip/data/trip_records.dart';

import '../../helpers/account.dart';
import '../../helpers/content.dart';
import '../../helpers/economy.dart';
import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/sync.dart';
import '../../helpers/trip.dart';

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
    expect(scaffold.backgroundColor, ColorTokens.sun);
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
          // The economy reads fuel_max at startup.
          return TunableLayers(
            defaults: bundledTunables(),
            overrides: const {},
          );
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

  group('a new player (specs/012-m07-onboarding, first-session.md "Boot")', () {
    /// Launches a new player over [economy] and returns every path the
    /// router went to, and the container.
    Future<(List<String>, ProviderContainer)> launch(
      WidgetTester tester,
      TestEconomy economy, {
      FakeApi? api,
      MemorySessionStore? sessions,
      bool online = true,
      Duration wait = Duration.zero,
    }) async {
      final startup = Completer<void>();
      final connectivity = FakeConnectivitySource()..current = online;
      final container = await pumpWassalApp(
        tester,
        newPlayer: true,
        content: contentTestOverrides(connectivity: connectivity),
        economy: economyOverridesOf(economy),
        account: accountTestOverrides(
          api: api ?? FakeApi(fallback: unreachable),
          sessions: sessions,
        ),
        overrides: [
          appStartupProvider.overrideWith((ref) async {
            await appStartup(ref);
            await startup.future;
          }),
        ],
      );
      final router = container.read(routerProvider);
      final paths = [router.state.uri.path];
      void changed() => paths.add(router.state.uri.path);
      router.routerDelegate.addListener(changed);
      addTearDown(() => router.routerDelegate.removeListener(changed));
      startup.complete();
      if (wait > Duration.zero) await tester.pump(wait);
      await tester.pumpAndSettle();
      return (paths, container);
    }

    Future<int?> openingDone(TestEconomy economy) async =>
        (await DriftFirstSessionStore(economy.db).read()).openingDoneAtMs;

    testWidgets('newPlayer: the opening scene', (tester) async {
      final economy = await testEconomy();
      final api = FakeApi(fallback: unreachable)
        ..reply('POST', ApiPaths.anonymous, [apiOk(tokenJson(created: true))]);
      final (paths, container) = await launch(tester, economy, api: api);
      expect(
        await container.read(firstOpenOutcomeProvider.future),
        FirstOpenOutcome.newPlayer,
      );
      expect(paths, ['/boot', '/onboarding/intro']);
    });

    testWidgets('offline: the opening scene', (tester) async {
      final economy = await testEconomy();
      final (paths, container) = await launch(tester, economy, online: false);
      expect(
        await container.read(firstOpenOutcomeProvider.future),
        FirstOpenOutcome.offline,
      );
      expect(paths.last, '/onboarding/intro');
    });

    testWidgets('timedOut: the opening scene', (tester) async {
      final economy = await testEconomy();
      final gate = Completer<void>();
      final api = FakeApi(fallback: unreachable)
        ..reply('POST', ApiPaths.anonymous, [
          FakeReply.held(apiOk(tokenJson(created: true)), gate),
        ]);
      final (paths, _) = await launch(
        tester,
        economy,
        api: api,
        wait: firstOpenWait + const Duration(milliseconds: 100),
      );
      expect(paths.last, '/onboarding/intro');
      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('notFirstOpen: the opening scene while it is not done', (
      tester,
    ) async {
      final economy = await testEconomy();
      final store = await testAccountStore(economy);
      await store.signedIn(playerId: playerIdOf(1), providers: const []);
      final (paths, container) = await launch(
        tester,
        economy,
        sessions: MemorySessionStore(sessionFor(economy.clock.nowMs())),
      );
      expect(
        await container.read(firstOpenOutcomeProvider.future),
        FirstOpenOutcome.notFirstOpen,
      );
      expect(paths.last, '/onboarding/intro');
    });

    testWidgets('restored: Home, and the opening counts as done', (
      tester,
    ) async {
      final economy = await testEconomy();
      final api = FakeApi(fallback: unreachable)
        ..reply('POST', ApiPaths.anonymous, [apiOk(tokenJson(created: false))])
        ..reply('GET', ApiPaths.state, [apiOk(stateJson(stateVersion: 6))]);
      final (paths, container) = await launch(tester, economy, api: api);
      expect(
        await container.read(firstOpenOutcomeProvider.future),
        FirstOpenOutcome.restored,
      );
      expect(paths, ['/boot', '/home']);
      expect(await openingDone(economy), isNotNull);
      expect(
        container.read(firstSessionFlagsProvider).value?.openingDoneAtMs,
        isNotNull,
        reason: 'through the notifier, so the redirects read it',
      );
    });

    testWidgets('an unfinished trip still wins', (tester) async {
      final economy = await testEconomy();
      final id = economy.service.newRequestId();
      final definition = economy.content.trip('line_hay.01')!;
      await DriftTripRecords(economy.db).create(
        TripRecordHeader(
          startTxn: id,
          tripId: 'line_hay.01',
          contentVersion: 1,
          definition: definition,
          seed: definition.seed,
          params: TripParams.fromTunables(
            tunableSnapshot(bundledConfig()),
            definition.lineId,
          ),
          createdAtMs: economy.clock.nowMs(),
        ),
      );
      await economy.service.startTrip(id, tripId: 'line_hay.01');
      final (paths, _) = await launch(tester, economy, online: false);
      expect(paths.take(2), ['/boot', '/trip/line_hay.01']);
      expect(paths, isNot(contains('/onboarding/intro')));
    });

    testWidgets('a relaunch after the opening, before the name: the Name '
        'card', (tester) async {
      final economy = await testEconomy();
      await DriftFirstSessionStore(economy.db).markOpeningDone(5);
      final (paths, _) = await launch(tester, economy, online: false);
      expect(paths.last, '/onboarding/name');
    });

    testWidgets('a relaunch after the name, before trip 1 starts: trip 1 '
        '(FR-002)', (tester) async {
      final economy = await testEconomy();
      await DriftFirstSessionStore(economy.db).markOpeningDone(5);
      await economy.service.setDisplayName(
        economy.service.newRequestId(),
        'Hamada',
      );
      final (paths, _) = await launch(tester, economy, online: false);
      expect(paths.take(2), ['/boot', '/trip/line_hay.01']);
    });
  });
}
