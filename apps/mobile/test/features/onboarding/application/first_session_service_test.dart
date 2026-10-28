import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/content/content_controller.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/features/onboarding/application/first_session_service.dart';
import 'package:wassal/features/onboarding/domain/first_session.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';

import '../../../helpers/coached_player.dart';
import '../../../helpers/content.dart';
import '../../../helpers/economy.dart';
import '../../../helpers/trip.dart';
import '../../../helpers/tutorial_content.dart';

// What the first session writes as it goes (contracts/first-session.md
// "Events that write the flags"): starts raise the step, a first finish seen
// on this phone makes its after-trip scene due, the scene and the ask raise
// it further, and the tutorial's end is recorded once.

final class _Session {
  _Session(this.container, this.economy);

  final ProviderContainer container;
  final TestEconomy economy;

  FirstSessionService get service =>
      container.read(firstSessionServiceProvider);

  FirstSessionFlags get flags =>
      container.read(firstSessionFlagsProvider.notifier).current;

  /// The economy's view with [state], its fuel as it is.
  EconomyView view(EconomyState state) =>
      EconomyView(state, economy.service.view.fuel);

  EconomyState get state => economy.service.state;
}

Future<_Session> _open({EconomyState Function(int nowMs)? firstState}) async {
  final economy = await testEconomy(
    content: tutorialContent(),
    firstState: firstState,
  );
  final container = contentContainer(
    assets: tutorialBundledAssets(),
    overrides: economyOverridesOf(economy),
  );
  await container.read(activeContentProvider.future);
  await container.read(firstSessionFlagsProvider.future);
  // Listened to, as the app does: a provider no one listens to is paused.
  container.listen(firstSessionServiceProvider, (_, _) {});
  return _Session(container, economy);
}

/// Plays [tripId] to its end through the economy, as the trip screen does.
Future<void> _play(_Session s, String tripId) async {
  final c = testController(s.economy);
  await c.open(tripId);
  await playCoached(c, onItsOwn: true);
  await settle();
}

UnfinishedTrip _started(String tripId, String txn) => UnfinishedTrip(
  startTxn: TxnId.parse(txn),
  tripId: tripId,
  contentVersion: 1,
  maxEarningsJenehat: 10,
  startedAtMs: 0,
);

const _txn1 = '0190f3a0-0000-7000-8000-000000000001';
const _txn2 = '0190f3a0-0000-7000-8000-000000000002';

void main() {
  test("a first finish of trip 3 makes the_stand due", () async {
    final s = await _open();
    for (final trip in tutorialTripIds.take(3)) {
      await _play(s, trip);
    }
    expect(s.state.progress['line_hay.03']?.firstCompletedAtMs, isNotNull);
    expect(s.flags.scenesDue, {'the_stand'});
  });

  test('a finish after the first does not', () async {
    final s = await _open(
      firstState: (nowMs) =>
          EconomyState.newPlayer(fuelMax: 5, nowMs: nowMs).copyWith(
            progress: const {
              'line_hay.03': TripProgress(
                bestStars: 1,
                plays: 1,
                firstCompletedAtMs: 1,
              ),
            },
          ),
    );
    await _play(s, 'line_hay.03');
    expect(s.flags.scenesDue, isEmpty);
  });

  test('a restored progress does not', () async {
    final s = await _open();
    final before = s.view(s.state);
    // The server sends best times, never a first-finish time.
    final restored = s.view(
      s.state.copyWith(
        progress: const {
          'line_hay.03': TripProgress(
            bestStars: 3,
            plays: 2,
            bestTimeMs: 50000,
          ),
        },
      ),
    );
    await s.service.onView(before, restored);
    expect(s.flags.scenesDue, isEmpty);
  });

  test("a replay of a restored trip 3 doesn't either", () async {
    // A best time from the server, and no first finish on this phone.
    final s = await _open(
      firstState: (nowMs) =>
          EconomyState.newPlayer(fuelMax: 5, nowMs: nowMs).copyWith(
            progress: const {
              'line_hay.03': TripProgress(
                bestStars: 3,
                plays: 2,
                bestTimeMs: 50000,
              ),
            },
          ),
    );
    await _play(s, 'line_hay.03');
    expect(s.state.progress['line_hay.03']?.firstCompletedAtMs, isNotNull);
    expect(s.flags.scenesDue, isEmpty);
  });

  test('starts write steps 2, 3, 4, 7 and 8', () async {
    final s = await _open();
    final steps = <int>[];
    var previous = s.view(s.state);
    for (final (i, trip) in tutorialTripIds.indexed) {
      final next = s.view(
        s.state.copyWith(
          unfinished: () => _started(trip, i.isEven ? _txn1 : _txn2),
        ),
      );
      await s.service.onView(previous, next);
      steps.add(s.flags.stepReached);
      previous = next;
    }
    expect(steps, [2, 3, 4, 7, 8]);
  });

  test('a restart of the same trip writes nothing new', () async {
    final s = await _open();
    final first = s.view(
      s.state.copyWith(unfinished: () => _started('line_hay.02', _txn1)),
    );
    await s.service.onView(s.view(s.state), first);
    expect(s.flags.stepReached, 3);
    final again = s.view(
      s.state.copyWith(unfinished: () => _started('line_hay.02', _txn2)),
    );
    await s.service.onView(first, again);
    expect(s.flags.stepReached, 3);
  });

  test('a trip outside the tutorial writes no step', () async {
    final s = await _open();
    await s.service.onView(
      s.view(s.state),
      s.view(
        s.state.copyWith(unfinished: () => _started('line_gamaa.01', _txn1)),
      ),
    );
    expect(s.flags.stepReached, 0);
  });

  test('the scene writes 5, the ask after it 6', () async {
    final s = await _open();
    await s.service.sceneSeen('the_stand');
    expect(s.flags.scenesSeen, {'the_stand'});
    expect(s.flags.stepReached, sceneSeenStep);
    await s.service.afterScene();
    expect(s.flags.stepReached, askStep);
  });

  test('the ask waits for the hooks', () async {
    final hooks = _CountingHooks();
    final economy = await testEconomy(content: tutorialContent());
    final container = contentContainer(
      assets: tutorialBundledAssets(),
      overrides: [
        ...economyOverridesOf(economy),
        firstSessionHooksProvider.overrideWithValue(hooks),
      ],
    );
    await container.read(activeContentProvider.future);
    await container.read(firstSessionFlagsProvider.future);
    await container.read(firstSessionServiceProvider).afterScene();
    expect(hooks.calls, 1);
  });

  test('done_at_ms once the tutorial is done', () async {
    final s = await _open();
    for (final trip in tutorialTripIds.take(4)) {
      await _play(s, trip);
    }
    expect(s.flags.doneAtMs, isNull);
    await _play(s, 'line_hay.05');
    expect(s.container.read(firstSessionProvider).tutorialDone, isTrue);
    final done = s.flags.doneAtMs;
    expect(done, isNotNull);
    // Never written again.
    await s.service.onView(s.view(s.state), s.view(s.state));
    expect(s.flags.doneAtMs, done);
  });

  test('the trip whose first finish ends the tutorial is kept', () async {
    final s = await _open();
    for (final trip in tutorialTripIds.take(4)) {
      await _play(s, trip);
    }
    expect(s.container.read(tutorialEndedOnProvider), isNull);
    await _play(s, 'line_hay.05');
    expect(s.container.read(tutorialEndedOnProvider), 'line_hay.05');
  });

  test('a tutorial done by a restore ends on no trip', () async {
    final s = await _open();
    final restored = s.view(
      s.state.copyWith(
        progress: {
          for (final trip in tutorialTripIds)
            trip: const TripProgress(bestStars: 3, plays: 1, bestTimeMs: 1),
        },
      ),
    );
    await s.service.onView(s.view(s.state), restored);
    expect(s.flags.doneAtMs, isNotNull);
    expect(s.container.read(tutorialEndedOnProvider), isNull);
  });
}

final class _CountingHooks implements FirstSessionHooks {
  int calls = 0;

  @override
  Future<void> afterScene() async => calls++;
}
