import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/boot_progress.dart';
import 'package:wassal/bootstrap/startup.dart';
import 'package:wassal/core/account/account_providers.dart';
import 'package:wassal/core/account/account_service.dart';
import 'package:wassal/core/account/domain/account.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/network/api_client.dart';
import 'package:wassal/core/routing/router.dart';

import '../../helpers/account.dart';
import '../../helpers/content.dart';
import '../../helpers/economy.dart';
import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/sync.dart';
import '../../helpers/trip.dart';

// The first open's wait (specs/011-m06-identity-sync, research R6): boot
// waits for the account's work up to 3 s after startup completes, on a
// first open only, and hands over to the account just before it leaves.

final class _Launch {
  _Launch(this.container, this.startup);

  final ProviderContainer container;
  final Completer<void> startup;

  String get path => container.read(routerProvider).state.uri.path;

  BootProgress get progress => container.read(bootProgressProvider);

  ServerAccountService get account =>
      container.read(accountServiceProvider).requireValue;
}

/// Pumps the app with startup held until the test completes it.
Future<_Launch> _launch(
  WidgetTester tester,
  TestEconomy economy, {
  required FakeApi api,
  MemorySessionStore? sessions,
  bool online = true,
}) async {
  final startup = Completer<void>();
  final connectivity = FakeConnectivitySource()..current = online;
  final container = await pumpWassalApp(
    tester,
    content: contentTestOverrides(connectivity: connectivity),
    economy: economyOverridesOf(economy),
    account: accountTestOverrides(api: api, sessions: sessions),
    overrides: [
      appStartupProvider.overrideWith((ref) async {
        await appStartup(ref);
        await startup.future;
      }),
    ],
  );
  return _Launch(container, startup);
}

void main() {
  testWidgets('a later launch hands over at once', (tester) async {
    final economy = await testEconomy();
    final store = await testAccountStore(economy);
    await store.signedIn(playerId: playerIdOf(1), providers: const []);
    final api = FakeApi(fallback: unreachable);

    // Its session too: with nothing pending, the sync has no batch to send.
    final launch = await _launch(
      tester,
      economy,
      api: api,
      sessions: MemorySessionStore(sessionFor(economy.clock.nowMs())),
    );
    launch.startup.complete();
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(launch.path, '/home');
    // Nothing of the account's: the sync's bootstrap is all that goes out.
    expect(api.log.map((r) => r.path), everyElement(ApiPaths.bootstrap));
    expect(
      await launch.container.read(firstOpenOutcomeProvider.future),
      FirstOpenOutcome.notFirstOpen,
    );
  });

  testWidgets('a first open waits for the account, and goes when it lands', (
    tester,
  ) async {
    final economy = await testEconomy();
    final gate = Completer<void>();
    final api = FakeApi(fallback: unreachable)
      ..reply('POST', ApiPaths.anonymous, [
        FakeReply.held(apiOk(tokenJson(created: true)), gate),
      ]);

    final launch = await _launch(tester, economy, api: api);
    launch.startup.complete();
    await tester.pump(const Duration(seconds: 2));
    expect(launch.path, '/boot');
    expect(launch.progress.done, isNot(contains(BootStep.account)));
    expect(launch.account.handedOver, isFalse);

    gate.complete();
    await tester.pumpAndSettle();
    expect(launch.path, '/home');
    expect(launch.progress.done, contains(BootStep.account));
    expect(launch.progress.value, 1);
    expect(launch.account.status, AccountStatus.active);
    expect(
      await launch.container.read(firstOpenOutcomeProvider.future),
      FirstOpenOutcome.newPlayer,
    );
  });

  testWidgets('a returning player within 3 s: Home with the state in place', (
    tester,
  ) async {
    final economy = await testEconomy();
    final api = FakeApi(fallback: unreachable)
      ..reply('POST', ApiPaths.anonymous, [apiOk(tokenJson(created: false))])
      ..reply('GET', ApiPaths.state, [apiOk(stateJson(stateVersion: 6))]);

    final launch = await _launch(tester, economy, api: api);
    launch.startup.complete();
    await tester.pumpAndSettle();

    expect(launch.path, '/home');
    expect(
      await launch.container.read(firstOpenOutcomeProvider.future),
      FirstOpenOutcome.restored,
    );
    final view = launch.container.read(economyViewProvider);
    expect(view.jenehat, 900);
    expect(view.progress['line_hay.01']?.bestStars, 3);
    expect(launch.account.profile!.displayName, 'name');
  });

  testWidgets('past 3 s it hands over, and the work goes on', (tester) async {
    final economy = await testEconomy();
    final gate = Completer<void>();
    final api = FakeApi(fallback: unreachable)
      ..reply('POST', ApiPaths.anonymous, [
        FakeReply.held(apiOk(tokenJson(created: true)), gate),
      ]);

    final launch = await _launch(tester, economy, api: api);
    launch.startup.complete();
    await tester.pump(firstOpenWait - const Duration(milliseconds: 100));
    expect(launch.path, '/boot');

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(launch.path, '/home');
    expect(launch.progress.done, contains(BootStep.account));
    expect(launch.account.handedOver, isTrue);

    // The account still arrives, in the background.
    gate.complete();
    await tester.pumpAndSettle();
    expect(launch.account.status, AccountStatus.active);
  });

  testWidgets('with no network there is no wait', (tester) async {
    final economy = await testEconomy();
    // No network: the sync's own attempt fails at once (the first open's
    // offline answer sends nothing, account_service_test).
    final api = FakeApi(fallback: unreachable);

    final launch = await _launch(tester, economy, api: api, online: false);
    launch.startup.complete();
    await tester.pump();
    await tester.pump();
    expect(launch.path, '/home');
    await tester.pumpAndSettle();

    expect(launch.account.handedOver, isTrue);
    expect(
      await launch.container.read(firstOpenOutcomeProvider.future),
      FirstOpenOutcome.offline,
    );
  });

  testWidgets('boot hands over to the account just before it navigates', (
    tester,
  ) async {
    final economy = await testEconomy();
    final api = FakeApi(fallback: unreachable);
    final launch = await _launch(tester, economy, api: api);
    final router = launch.container.read(routerProvider);
    final handedOverAtNavigation = <bool>[];
    void changed() => handedOverAtNavigation.add(launch.account.handedOver);
    router.routerDelegate.addListener(changed);
    addTearDown(() => router.routerDelegate.removeListener(changed));

    expect(launch.account.handedOver, isFalse);
    launch.startup.complete();
    await tester.pumpAndSettle();

    expect(launch.path, '/home');
    expect(handedOverAtNavigation, isNotEmpty);
    expect(handedOverAtNavigation, everyElement(isTrue));
  });
}
