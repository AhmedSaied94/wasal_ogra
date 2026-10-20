// What the US3 fixtures pin: the hajja, the sleeper, the hurried passenger
// and patience (rules.md §3 step 2, §5.4, §7.3, §9.3).
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../../support/fixture_io.dart';
import '../../support/scripts.dart';

List<int> _durations(Replayed run, int tokenId) => [
  for (final hop in run.events.whereType<TokenHopStarted>())
    if (hop.tokenId == tokenId) hop.durationMs,
];

final us3Expectations = <String, Expectation>{
  'archetype__hajja_slow_hop.json': (run) {
    // §5.4: hops out of the hajja's seat take 200%, hops into it don't.
    final hop = run.engine.params.tripHopMs;
    expect(hopsOf(run, fareToken(run, 'p1')), ['p1>p2', 'p2>DRIVER']);
    expect(_durations(run, fareToken(run, 'p1')), [hop, hop * 2]);
    expect(_durations(run, changeToken(run, 'p1')), [hop, hop * 2]);
    expect(_durations(run, fareToken(run, 'p2')), [hop * 2]);
  },
  'archetype__sleeper_blocks_chain.json': (run) {
    // §5.3: the asleep p2 blocks p1's fare until a tap wakes him.
    final fare = fareToken(run, 'p1');
    final blocked = eventsOf<TokenBlocked>(run.events).single;
    expect((blocked.tokenId, blocked.by), (fare, 'p2'));
    final woke = eventsOf<PassengerWoke>(run.events).single.tMs;
    expect(eventsOf<TokenUnblocked>(run.events).single.tMs, woke);
    expect(
      woke - eventsOf<PassengerWaking>(run.events).single.tMs,
      greaterThanOrEqualTo(run.engine.params.tripWakeMs),
    );
    expect(resultOf(run).stars, 3);
  },
  'archetype__sleeper_missed_stop.json': (run) {
    // §9.3: asleep at his stop while owed: a missed stop, not a fight.
    final result = resultOf(run);
    expect(result.missedStops, 1);
    expect(result.fights, 0);
    expect(result.mistakes.single.kind, MistakeKind.unreturned);
    expect(run.engine.passenger('p1').outcome, AlightOutcome.missedStop);
    expect(result.reputation, 100 - run.engine.params.repMissedStop);
    expect(result.stars, 2);
  },
  'archetype__sleeper_redoze.json': (run) {
    // Clarification 5: awake for trip_sleeper_awake_ms after waking, then
    // asleep again; the change waits for the second tap.
    final woke = eventsOf<PassengerWoke>(run.events).map((e) => e.tMs).toList();
    final asleep = eventsOf<PassengerFellAsleep>(run.events).single.tMs;
    expect(woke, hasLength(2));
    expect(asleep - woke.first, inInclusiveRange(15000, 15000 + 32));
    expect(eventsOf<TokenBlocked>(run.events).single.by, 'p1');
    expect(
      eventsOf<ChangeDelivered>(run.events).single.tMs,
      greaterThan(woke.last),
    );
    expect(resultOf(run).stars, 3);
  },
  'archetype__hurry_impatient.json': (run) {
    // §7.1, §7.3: a hurried passenger runs out at half the patience, once.
    final ranOut = eventsOf<PatienceRanOut>(run.events).single;
    final paid = eventsOf<FareSent>(run.events).single.tMs;
    expect(ranOut.tMs - paid, inInclusiveRange(9900, 10000));
    final result = resultOf(run);
    expect(result.impatient, 1);
    expect(result.reputationLost, {RepCause.impatient: 5});
    expect(result.reputation, 98);
    expect(result.stars, 3);
  },
  'core__patience_runs_out.json': (run) {
    // §7.3: patience runs out after 20 s owed, once; it never refills, and
    // p2, who paid exactly, never starts it.
    final ranOut = eventsOf<PatienceRanOut>(run.events).single;
    expect(ranOut.passengerId, 'p1');
    expect(
      ranOut.tMs - eventsOf<FareSent>(run.events).first.tMs,
      inInclusiveRange(19900, 20000),
    );
    expect(
      eventsOf<PassengerSpeaks>(run.events)
          .where((e) => e.slot == SpeechSlot.wantsChange)
          .map((e) => e.passengerId),
      ['p1'],
    );
    expect(run.engine.passenger('p2').patienceMs, isNull);
    expect(run.engine.passenger('p1').patienceMs, 0);
    expect(resultOf(run).impatient, 1);
  },
};
