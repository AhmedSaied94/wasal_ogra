import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderContainer;
import 'package:wassal/core/content/content_controller.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/features/onboarding/domain/first_session.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';

import '../../helpers/coached_player.dart';
import '../../helpers/content.dart';
import '../../helpers/economy.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/trip.dart';
import '../../helpers/tutorial_content.dart';

// A kill at each step of the first session (FR-051, contracts/ci-checks.md):
// the session runs on a file database through its real writers, the app is
// killed (nothing closes, nothing more is written), and the next launch's
// target is checked. Never the opening or the name again once done, and
// never a second tutorial gift.

const _name = 'حمادة';
const _sceneAfterTrip3 = 'the_stand';

/// One phone's first session, as far as the kill.
final class _Phone {
  _Phone(this.economy);

  TestEconomy economy;
  late ProviderContainer _container;

  FirstSessionFlagsNotifier get _flags =>
      _container.read(firstSessionFlagsProvider.notifier);

  /// The app's providers over the economy, the first session's service
  /// listening as the app's does.
  Future<void> open() async {
    _container = contentContainer(
      assets: tutorialBundledAssets(),
      overrides: economyOverridesOf(economy),
    );
    await _container.read(activeContentProvider.future);
    await _container.read(firstSessionFlagsProvider.future);
    _container.listen(firstSessionServiceProvider, (_, _) {});
  }

  /// The opening's page opened (it writes step 1).
  Future<void> openingShown() => _flags.reachStep(1);

  Future<void> openingDone() async {
    await openingShown();
    await _flags.markOpeningDone();
  }

  Future<void> named() async {
    await openingDone();
    final service = economy.service;
    await service.setDisplayName(service.newRequestId(), _name);
  }

  /// Tutorial trips 1 to [count], played to their ends by the coached
  /// player, with what the app does between them.
  Future<void> played(int count) async {
    await named();
    for (final (i, trip) in tutorialTripIds.take(count).indexed) {
      if (i == 3) await sceneSeen();
      if (i == 4) await fuelLesson();
      final c = testController(economy);
      await c.open(trip);
      await playCoached(c, onItsOwn: true);
      await settle();
    }
  }

  /// Tutorial trip [index] (0-based) started and under way, after the
  /// ones before it.
  Future<void> inTrip(int index) async {
    await played(index);
    if (index == 3) await sceneSeen();
    if (index == 4) await fuelLesson();
    final c = testController(economy, disposeAtTearDown: false);
    await c.open(tutorialTripIds[index]);
    advanceMs(c, 2000);
    await settle();
  }

  /// The سلمى scene seen, and the ask's place passed (the scene page).
  Future<void> sceneSeen() async {
    final service = _container.read(firstSessionServiceProvider);
    await service.sceneSeen(_sceneAfterTrip3);
    await service.afterScene();
  }

  /// The fuel lesson's button: the gift, then the mark.
  Future<void> fuelLesson({bool marked = true}) async {
    final service = economy.service;
    await service.grantTutorialGift(service.newRequestId());
    if (marked) await _flags.markFuelLessonDone();
  }

  /// The app is killed: nothing more is written.
  Future<void> kill() async {
    _container.dispose();
    await economy.close();
  }

  /// The next launch reads the file again. Outside `runAsync`: an economy
  /// opened in its zone would hold the app's frames up.
  Future<void> relaunch() async => economy = await reopen(economy);
}

/// A new phone's first session up to [steps], then a kill and a launch;
/// the launched app's container.
Future<(ProviderContainer, _Phone)> _killAndLaunch(
  WidgetTester tester,
  Future<void> Function(_Phone phone) steps,
) async {
  late _Phone phone;
  await tester.runAsync(() async {
    phone = _Phone(
      await testEconomy(content: tutorialContent(), dbFile: tempDbFile()),
    );
    await phone.open();
    await steps(phone);
    await phone.kill();
  });
  await phone.relaunch();
  await preloadTripArt(tester);
  final container = await pumpWassalApp(
    tester,
    newPlayer: true,
    settleBoot: false,
    content: contentTestOverrides(assets: tutorialBundledAssets()),
    economy: economyOverridesOf(phone.economy),
    trip: tripTestOverrides(),
  );
  return (container, phone);
}

Future<int> _gifts(_Phone phone) => opCount(phone.economy, 'tutorial_gift');

Uri _scene(String then) => Uri(
  path: '/onboarding/scene/$_sceneAfterTrip3',
  queryParameters: {'then': then},
);

void main() {
  testWidgets('in the opening: the opening again', (tester) async {
    await _killAndLaunch(tester, (p) => p.openingShown());
    expect(currentLocation(tester), '/onboarding/intro');
  });

  testWidgets('on the Name card: the Name card, not the opening', (
    tester,
  ) async {
    await _killAndLaunch(tester, (p) => p.openingDone());
    expect(currentLocation(tester), '/onboarding/name');
  });

  testWidgets('between the name and trip 1: trip 1', (tester) async {
    final (container, _) = await _killAndLaunch(tester, (p) => p.named());
    expect(currentLocation(tester), '/trip/${tutorialTripIds[0]}');
    expect(container.read(tutorialCoachProvider(tutorialTripIds[0])), 0);
  });

  for (final (index, trip) in tutorialTripIds.indexed) {
    testWidgets('in trip ${index + 1}: the trip, paused, coached again', (
      tester,
    ) async {
      final (container, phone) = await _killAndLaunch(
        tester,
        (p) => p.inTrip(index),
      );
      expect(currentLocation(tester), '/trip/$trip');
      expect(controllerOf(tester).phase, TripPhase.paused);
      expect(container.read(tutorialCoachProvider(trip)), index);
      expect(await _gifts(phone), index == 4 ? 1 : 0);
    });
  }

  testWidgets("on trip 3's result: the scene, then Home", (tester) async {
    final (container, _) = await _killAndLaunch(tester, (p) => p.played(3));
    expect(Uri.parse(currentLocation(tester)), _scene('/home'));
    final flags = container.read(firstSessionFlagsProvider.notifier).current;
    expect(flags.scenesDue, {_sceneAfterTrip3});
    expect(flags.scenesSeen, isEmpty);
  });

  testWidgets('after the scene: Home, and the scene never again', (
    tester,
  ) async {
    final (container, _) = await _killAndLaunch(tester, (p) async {
      await p.played(3);
      await p.sceneSeen();
    });
    expect(currentLocation(tester), '/home');
    expect(
      container.read(firstSessionProvider).beforeStart(tutorialTripIds[3]),
      isNull,
    );
  });

  testWidgets('on the fuel lesson, before the button: no gift, no mark, '
      'and the lesson again before trip 5', (tester) async {
    final (container, phone) = await _killAndLaunch(tester, (p) async {
      await p.played(4);
      await p.sceneSeen();
    });
    expect(currentLocation(tester), '/home');
    expect(await _gifts(phone), 0);
    final flags = container.read(firstSessionFlagsProvider.notifier).current;
    expect(flags.fuelLessonDoneAtMs, isNull);
    expect(
      container.read(firstSessionProvider).beforeStart(tutorialTripIds[4]),
      const FuelLessonDue(),
    );
  });

  testWidgets('between the gift and the mark: one gift, no lesson again', (
    tester,
  ) async {
    final (container, phone) = await _killAndLaunch(tester, (p) async {
      await p.played(4);
      await p.sceneSeen();
      await p.fuelLesson(marked: false);
    });
    expect(await _gifts(phone), 1);
    expect(
      container.read(firstSessionProvider).beforeStart(tutorialTripIds[4]),
      isNull,
    );
  });

  testWidgets('right after the button: one gift, a full tank, trip 5 next', (
    tester,
  ) async {
    final (container, phone) = await _killAndLaunch(tester, (p) async {
      await p.played(4);
      await p.sceneSeen();
      await p.fuelLesson();
    });
    expect(currentLocation(tester), '/home');
    expect(await _gifts(phone), 1);
    final fuel = container.read(economyViewProvider).fuel;
    expect(fuel.liters, fuel.max);
    expect(
      container.read(firstSessionProvider).beforeStart(tutorialTripIds[4]),
      isNull,
    );
  });
}
