import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderContainer;
import 'package:wassal/core/account/account_providers.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';

import '../../../helpers/content.dart';
import '../../../helpers/economy.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/trip.dart';
import '../../../helpers/tutorial_content.dart';

// A late restore (contracts/first-session.md "A late restore"): a returning
// player's state, taken by the sync after boot handed over, moves a player
// still in the opening or on the Name card to Home. On a trip, nothing
// happens, and a name confirmed on this phone before it wins (FR-005).

const _restoredName = 'سيد';
const _localName = 'حمادة';

final class _Launch {
  _Launch(this.container, this.economy, this.restorations);

  final ProviderContainer container;
  final TestEconomy economy;
  final StreamController<void> restorations;

  /// The sync takes [state] as the server's, then reports it as M06 does.
  Future<void> restore(WidgetTester tester, EconomyState state) async {
    await economy.service.replaceFromServer(
      state,
      playerId: 'player-1',
      stateVersion: 7,
    );
    restorations.add(null);
    await pumpFrames(tester);
  }
}

Future<_Launch> _launch(WidgetTester tester, String location) async {
  final economy = await testEconomy(content: tutorialContent());
  final restorations = StreamController<void>.broadcast();
  addTearDown(restorations.close);
  await preloadTripArt(tester);
  final container = await pumpWassalApp(
    tester,
    newPlayer: true,
    initialLocation: location,
    settle: false,
    content: contentTestOverrides(assets: tutorialBundledAssets()),
    economy: economyOverridesOf(economy),
    trip: tripTestOverrides(),
    overrides: [
      progressRestoredProvider.overrideWith((ref) => restorations.stream),
    ],
  );
  return _Launch(container, economy, restorations);
}

EconomyState _server({String? name, bool progress = false}) =>
    EconomyState.newPlayer(fuelMax: 5, nowMs: 0).copyWith(
      displayName: () => name,
      progress: {
        if (progress)
          for (final trip in tutorialTripIds)
            trip: const TripProgress(bestStars: 3, plays: 1, bestTimeMs: 1),
      },
    );

void main() {
  testWidgets('in the opening, a restored name: Home, and the opening done', (
    tester,
  ) async {
    final s = await _launch(tester, '/onboarding/intro');
    expect(currentLocation(tester), '/onboarding/intro');
    await s.restore(tester, _server(name: _restoredName));
    expect(currentLocation(tester), '/home');
    final flags = s.container.read(firstSessionFlagsProvider.notifier).current;
    expect(flags.openingDoneAtMs, isNotNull);
  });

  testWidgets('on the Name card, a restored progress: Home', (tester) async {
    final s = await _launch(tester, '/onboarding/name');
    expect(currentLocation(tester), '/onboarding/name');
    await s.restore(tester, _server(progress: true));
    expect(currentLocation(tester), '/home');
    final flags = s.container.read(firstSessionFlagsProvider.notifier).current;
    expect(flags.openingDoneAtMs, isNotNull);
  });

  testWidgets('a restore with no name and no progress: the opening goes on', (
    tester,
  ) async {
    final s = await _launch(tester, '/onboarding/intro');
    await s.restore(tester, _server());
    expect(currentLocation(tester), '/onboarding/intro');
    final flags = s.container.read(firstSessionFlagsProvider.notifier).current;
    expect(flags.openingDoneAtMs, isNull);
  });

  testWidgets('on a trip: nothing', (tester) async {
    final s = await _launch(tester, '/trip/line_hay.01');
    expect(currentLocation(tester), '/trip/line_hay.01');
    await s.restore(tester, _server(name: _restoredName, progress: true));
    expect(currentLocation(tester), '/trip/line_hay.01');
  });

  testWidgets('a name confirmed before the restore wins (FR-005)', (
    tester,
  ) async {
    final s = await _launch(tester, '/trip/line_hay.01');
    final service = s.economy.service;
    await service.setDisplayName(service.newRequestId(), _localName);
    await s.restore(tester, _server(name: _restoredName, progress: true));
    expect(s.container.read(economyViewProvider).displayName, _localName);
    expect(s.container.read(driverNameProvider), _localName);
    expect(currentLocation(tester), '/trip/line_hay.01');
  });
}
