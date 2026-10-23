import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/data/drift_trip_records.dart';
import 'package:wassal/features/trip/domain/step_accumulator.dart';

import '../../helpers/economy.dart';
import '../../helpers/trip.dart';

// A kill at any moment of a trip loses nothing (tasks.md T048, SC-006): on
// a database file, the five sample trips are killed at 50 seeded moments,
// each after a write, and reopened.

const _samples = [
  'sample__line_hay_01_three_stars',
  'sample__line_hay_02_three_stars',
  'sample__line_hay_03_three_stars',
  'sample__line_gamaa_01_three_stars',
  'sample__line_gamaa_02_three_stars',
];

/// Where one kill happens: after [lastCommand] of the log and [extraMs] more
/// of the trip clock, with a lifecycle pause first when [pausedFirst].
final class _KillPoint {
  const _KillPoint(
    this.fixture,
    this.lastCommand,
    this.extraMs,
    this.pausedFirst,
  );

  final String fixture;
  final int lastCommand;
  final int extraMs;
  final bool pausedFirst;

  @override
  String toString() =>
      '$fixture after command $lastCommand +${extraMs}ms'
      '${pausedFirst ? ', paused' : ''}';
}

List<_KillPoint> _killPoints() {
  final random = Random(806);
  return [
    for (var n = 0; n < 50; n++)
      () {
        final fixture = _samples[n % _samples.length];
        final log = loadFixture(fixture).commandLog;
        return _KillPoint(
          fixture,
          random.nextInt(log.length),
          random.nextInt(3000),
          n.isEven,
        );
      }(),
  ];
}

/// The state's JSON without its status: a rebuilt trip comes back paused.
Map<String, Object> _withoutStatus(TripState state) =>
    state.toJson()..remove('status');

void main() {
  for (final point in _killPoints()) {
    test('$point', () async {
      final fixture = loadFixture(point.fixture);
      final tripId = fixture.definition.tripId;
      final before = await testEconomy(dbFile: tempDbFile());
      final live = testController(
        before,
        fixed: FixedTrip(
          definition: fixture.definition,
          params: fixture.params,
          seed: fixture.seed,
        ),
        disposeAtTearDown: false,
      );
      await live.open(tripId);
      final fuel = before.service.view.fuel.liters;
      final start = live.session!.startTxn;

      await playCommands(live, fixture.commandLog.take(point.lastCommand + 1));
      final atCommand = live.engine!.state;
      // On, with no write, short of the trip's end.
      final endMs = fixture.expectedResult.durationMs;
      for (
        var t = 0;
        t < point.extraMs &&
            live.phase == TripPhase.running &&
            live.engine!.state.tMs + 100 < endMs;
        t += engineStepMs
      ) {
        live.advance(const Duration(milliseconds: engineStepMs));
      }
      if (point.pausedFirst) live.pause(PauseReason.lifecycle);
      await settle();
      final atKill = live.engine!.state;
      final saved = (await DriftTripRecords(before.db).load(start))!.tMs;

      // The kill: the process dies; the file opens again at the next launch.
      final after = await reopen(before);
      final rebuilt = testController(after);
      await rebuilt.open(tripId);
      expect(rebuilt.phase, TripPhase.paused);
      expect(rebuilt.session!.startTxn, start);
      final state = rebuilt.engine!.state;
      expect(state.tMs, saved);
      if (point.pausedFirst || saved == atKill.tMs) {
        // Paused first (or stopped by the trip itself): exactly the kill's
        // moment.
        expect(saved, atKill.tMs);
        expect(_withoutStatus(state), _withoutStatus(atKill));
      } else {
        // The last write was the last command.
        expect(saved, atCommand.tMs);
        expect(_withoutStatus(state), _withoutStatus(atCommand));
      }
      expect(after.service.view.fuel.liters, fuel);
      expect(await opCount(after, 'trip_start'), 1);
    });
  }
}
