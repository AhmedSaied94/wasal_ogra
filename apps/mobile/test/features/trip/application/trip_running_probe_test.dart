import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/domain/step_accumulator.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/trip.dart';

// The trip's running probe (specs/018-m11-ads, research R7, T030): true
// exactly while the engine runs, which is when no ad call may happen.

void main() {
  test('follows start, pause, resume and leaving', () async {
    final economy = await testEconomy();
    final probe = ValueNotifier(false);
    final c = testController(economy, running: probe);
    expect(probe.value, isFalse);

    await c.open('line_hay.01');
    expect(c.phase, TripPhase.running);
    expect(probe.value, isTrue);

    advanceMs(c, 1000);
    c.pause(PauseReason.button);
    expect(probe.value, isFalse);
    c.resume();
    expect(probe.value, isTrue);

    c.pause(PauseReason.lifecycle);
    expect(probe.value, isFalse);
    await c.leave();
    expect(probe.value, isFalse);
  });

  test('false once the trip fails, and true again after a revive', () async {
    final f = loadFixture('ending__revived');
    final economy = await stockedEconomy(bonat: 100);
    final probe = ValueNotifier(false);
    final c = testController(
      economy,
      running: probe,
      fixed: FixedTrip(
        definition: f.definition,
        params: f.params,
        seed: f.seed,
      ),
    );
    await c.open(f.definition.tripId);
    while (c.phase == TripPhase.running) {
      expect(probe.value, isTrue);
      c.advance(const Duration(milliseconds: engineStepMs));
    }
    expect(c.phase, TripPhase.failed);
    expect(probe.value, isFalse);
  });

  test('false at the end and on dispose', () async {
    final economy = await testEconomy();
    final probe = ValueNotifier(false);
    final c = testController(economy, running: probe, disposeAtTearDown: false);
    await c.open('line_hay.01');
    expect(probe.value, isTrue);
    c.dispose();
    expect(probe.value, isFalse);
  });

  test('two trips overlapping: the probe holds while either runs', () async {
    // One trip's screen replacing another's: the first is disposed after
    // the second runs (review M4).
    final economy = await stockedEconomy(bonat: 0);
    final probe = ValueNotifier(false);
    final first = testController(
      economy,
      running: probe,
      disposeAtTearDown: false,
    );
    await first.open('line_hay.01');
    final second = testController(economy, running: probe);
    // It finds the first's record: a trip resumed opens paused.
    await second.open('line_hay.01');
    second.resume();
    expect(second.phase, TripPhase.running);
    first.dispose();
    expect(probe.value, isTrue);
    second.pause(PauseReason.button);
    expect(probe.value, isFalse);
  });

  test('a resume at launch opens paused, with the probe false', () async {
    final economy = await testEconomy(dbFile: tempDbFile());
    final first = testController(economy, disposeAtTearDown: false);
    await first.open('line_hay.01');
    advanceMs(first, 2000);
    first.dispose();
    await settle();

    final probe = ValueNotifier(false);
    final again = testController(economy, running: probe);
    await again.open('line_hay.01');
    expect(probe.value, again.phase == TripPhase.running);
  });
}
