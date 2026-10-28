// The whole first session (specs/012-m07-onboarding SC-002, contracts/
// ci-checks.md "Integration"): a fresh database and the tutorial fixture,
// offline from the opening through the five tutorial trips, the scene after
// trip 3 and the fuel lesson before trip 5, to Home; then online, where the
// name and the gift reach the server once each. Headless:
//
//   fvm flutter test integration_test/first_session_test.dart -d flutter-tester
//
// or on a device with `--flavor dev`.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/network/api_client.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/core/sync/sync_providers.dart';
import 'package:wassal/core/theme/components/story.dart';
import 'package:wassal/features/onboarding/domain/tutorial_coach.dart';
import 'package:wassal/features/onboarding/presentation/first_session_continue.dart';
import 'package:wassal/features/onboarding/presentation/fuel_lesson_screen.dart';
import 'package:wassal/features/onboarding/presentation/name_screen.dart';
import 'package:wassal/features/onboarding/presentation/scene_player.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/presentation/dashboard/boosters_locked_bar.dart';
import 'package:wassal/features/trip/presentation/dashboard/boosters_row.dart';
import 'package:wassal/features/trip/presentation/dashboard/dashboard.dart';

import '../test/helpers/account.dart';
import '../test/helpers/coached_player.dart';
import '../test/helpers/content.dart';
import '../test/helpers/economy.dart';
import '../test/helpers/fake_api.dart';
import '../test/helpers/pump_app.dart';
import '../test/helpers/sync.dart';
import '../test/helpers/trip.dart';
import '../test/helpers/tutorial_content.dart';
import 'trip_helpers.dart';

const _openingPanels = 3;

/// The operation types [api]'s syncs carried, in order.
List<String> _sentTypes(FakeApi api) => [
  for (final request in api.to(ApiPaths.sync))
    for (final op in (request.body! as Map<String, Object?>)['ops']! as List)
      (op as Map<String, Object?>)['op_type']! as String,
];

/// Taps [finder] once it can be hit: pages come in with a transition.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await pumpUntil(tester, () => finder.hitTestable().evaluate().isNotEmpty);
  await tester.tap(finder);
}

/// Real time for a transition to run.
Future<void> _frames(WidgetTester tester, {int count = 10}) async {
  for (var i = 0; i < count; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
}

/// «يلا» on the scene's panel, and its turn.
Future<void> _next(WidgetTester tester) async {
  await _tap(tester, find.byKey(ScenePlayer.nextKey));
  await _frames(tester);
}

/// The page dots' panel, or null once the scene has left.
int? _panel(WidgetTester tester) {
  final dots = find.byType(PageDots).evaluate();
  return dots.isEmpty ? null : (dots.first.widget as PageDots).index;
}

/// «يلا» until the panel on screen moves on: once, or twice when its turns
/// are still playing and the first only shows the rest of its bubbles
/// (specs/012.5-m22-animated-scenes), whether or not Rive plays here.
Future<void> _nextPanel(WidgetTester tester) async {
  final scene = currentLocation(tester);
  final shown = _panel(tester);
  for (var taps = 0; taps < 2; taps++) {
    await _next(tester);
    if (currentLocation(tester) != scene || _panel(tester) != shown) return;
  }
  fail('panel $shown of $scene stayed after two taps of «يلا»');
}

/// Plays the scene until its page has left; how many panels it had.
Future<int> _playScene(WidgetTester tester) async {
  final scene = currentLocation(tester);
  var panels = 0;
  while (panels < 10 && currentLocation(tester) == scene) {
    await _nextPanel(tester);
    panels++;
  }
  return panels;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('first open to Home offline, then one name and one gift '
      'online', (tester) async {
    final api = FakeApi(fallback: unreachable);
    final economy = await testEconomy(content: tutorialContent());
    await preloadTripArt(tester);
    final container = await pumpWassalApp(
      tester,
      newPlayer: true,
      settleBoot: false,
      content: contentTestOverrides(assets: tutorialBundledAssets()),
      economy: economyOverridesOf(economy),
      account: accountTestOverrides(api: api),
      trip: tripTestOverrides(),
    );
    final router = container.read(routerProvider);
    final visited = <String>[];
    void changed() => visited.add(router.state.uri.toString());
    router.routerDelegate.addListener(changed);
    addTearDown(() => router.routerDelegate.removeListener(changed));

    // 1–2. The opening, three panels, and the Name card.
    await pumpUntil(
      tester,
      () => currentLocation(tester) == '/onboarding/intro',
    );
    expect(await _playScene(tester), _openingPanels);
    await pumpUntil(
      tester,
      () => currentLocation(tester) == '/onboarding/name',
    );
    await _tap(tester, find.byKey(NameScreen.ctaKey));

    // 3–4. The five trips, coached; the scene after trip 3, the fuel lesson
    // before trip 5.
    for (final (index, tripId) in tutorialTripIds.indexed) {
      // The last trip's screen leaves with the page transition.
      await pumpUntil(
        tester,
        () =>
            currentLocation(tester) == '/trip/$tripId' &&
            find.byType(TripDashboard).evaluate().length == 1 &&
            controllerOf(tester).session?.tripId == tripId &&
            controllerOf(tester).phase == TripPhase.running,
      );
      expect(find.byType(BoostersLockedBar), findsOneWidget, reason: tripId);
      expect(find.byType(BoostersRow), findsNothing, reason: tripId);
      if (index == 4) {
        // Full from the gift, less the liter this start took.
        final fuel = container.read(economyViewProvider).fuel;
        expect(fuel.liters, fuel.max - 1);
      }

      final ownStep = index >= CoachStepId.values.length;
      final run = await tester.runAsync(
        () => playCoached(controllerOf(tester), onItsOwn: ownStep),
      );
      expect(run!.steps, [
        if (!ownStep) CoachStepId.values[index],
      ], reason: tripId);
      expect(run.result.stars, greaterThanOrEqualTo(1), reason: tripId);

      await pumpUntil(
        tester,
        () => currentLocation(tester) == '/trip/$tripId/result',
      );
      await _tap(tester, find.byKey(FirstSessionContinue.buttonKey));
      if (index == 2) {
        await pumpUntil(
          tester,
          () => currentLocation(tester).startsWith('/onboarding/scene/'),
        );
        await _playScene(tester);
      }
      if (index == 3) {
        await pumpUntil(
          tester,
          () => currentLocation(tester).startsWith('/onboarding/fuel'),
        );
        await _tap(tester, find.byKey(FuelLessonScreen.ctaKey));
      }
    }
    await pumpUntil(tester, () => currentLocation(tester) == '/home');

    bool shown(String prefix) => visited.any((l) => l.startsWith(prefix));
    expect(
      visited.where((l) => l.startsWith('/onboarding/scene/')).toSet(),
      hasLength(1),
      reason: 'the scene, once',
    );
    expect(
      visited.where((l) => l.startsWith('/onboarding/fuel')).toSet(),
      hasLength(1),
      reason: 'the fuel lesson, once',
    );
    expect(shown('/onboarding/intro'), isFalse, reason: 'never again');

    // 5. Online: the name and the gift, once each.
    api
      ..reply('POST', ApiPaths.anonymous, [apiOk(tokenJson(created: true))])
      ..always(
        'POST',
        ApiPaths.sync,
        (ApiRequest r) => syncAnswerFor(r, stateVersion: 9),
      );
    final engine = await tester.runAsync(
      () => container.read(syncEngineProvider.future),
    );
    final flushed = await tester.runAsync(
      () => engine!.flush(timeout: const Duration(seconds: 10)),
    );
    expect(flushed, isTrue);
    final types = _sentTypes(api);
    expect(types.where((t) => t == 'settings_update'), hasLength(1));
    expect(types.where((t) => t == 'tutorial_gift'), hasLength(1));
  });
}
