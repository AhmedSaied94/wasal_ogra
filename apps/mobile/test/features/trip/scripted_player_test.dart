import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../../helpers/trip.dart';

// Every reproducible parity fixture plays through the screen's controls
// and ends with the fixture's result, command log hash included (tasks.md
// T034, T062, T071, T079, T087 and T092; SC-002).

/// The fixtures the screen can't reproduce, and why (research R11): a
/// screen that stops the clock for a payment dispute answers it in the
/// step that raises it.
const unreproducible = {
  'event__payment_dispute':
      'answers its dispute a second after it opens (5016 → 6006 ms); '
      'dispute_screen_way_test.dart plays it the screen\'s way',
  'solver__line_hay_02': 'never answers its dispute',
};

/// What SC-002 counts: every fixture but those two.
const reproducibleCount = 58;

void main() {
  final names = allFixtureNames();
  final reproducible = [
    for (final name in names)
      if (!unreproducible.containsKey(name)) name,
  ];

  test('$reproducibleCount fixtures, all but the two the screen can\'t', () {
    expect(names, containsAll(unreproducible.keys));
    expect(reproducible, hasLength(reproducibleCount));
  });

  for (final name in reproducible) {
    testWidgets('$name plays through the controls', (tester) async {
      final fixture = loadFixture(name);
      final run = await ScriptedPlayer(tester, fixture).play();
      expect(run.inexact, isFalse);
      expect(run.result, isNotNull, reason: '${run.exit}');
      expect(run.result!.toJson(), fixture.expectedResult.toJson());
    });
  }

  // Each use through the row is charged once (tasks.md T079's checkpoint).
  for (final name in reproducible.where((n) => n.startsWith('booster__'))) {
    testWidgets('$name charges each use once', (tester) async {
      final fixture = loadFixture(name);
      final economy = await economyFor(fixture);
      final uses = fixture.commandLog
          .where((e) => e.command is UseBooster)
          .length;
      await ScriptedPlayer(tester, fixture).play(economy: economy);
      expect(await opCount(economy, 'use_booster'), uses);
      expect(economy.service.view.inventory, isEmpty);
    });
  }
}
