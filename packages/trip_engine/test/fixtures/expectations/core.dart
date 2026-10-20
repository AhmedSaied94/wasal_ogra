// What each `core__` fixture pins: the chain, change and getting off
// (rules.md §5, §6.5, §9).
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../../support/fixture_io.dart';
import '../../support/scripts.dart';

final coreExpectations = <String, Expectation>{
  'core__chain_rows.json': (run) {
    // §5.2: hop by hop through the occupied seats of the column, both ways.
    expect(hopsOf(run, fareToken(run, 'p1')), ['p1>p2', 'p2>p3', 'p3>DRIVER']);
    expect(hopsOf(run, changeToken(run, 'p1')), [
      'DRIVER>p3',
      'p3>p2',
      'p2>p1',
    ]);
    expect(resultOf(run).stars, 3);
  },
  'core__empty_seat_skip.json': (run) {
    // §5.2: the empty B_r is skipped, and p2 in B_m is in another column.
    expect(hopsOf(run, fareToken(run, 'p1')), ['p1>p3', 'p3>DRIVER']);
    expect(hopsOf(run, changeToken(run, 'p1')), ['DRIVER>p3', 'p3>p1']);
  },
  'core__exact_change.json': (run) {
    // §6.5: exact change settles the balance and earns the reward.
    final delivered = eventsOf<ChangeDelivered>(run.events).single;
    expect(
      (delivered.result, delivered.amountPiasters),
      (ChangeResult.exact, 300),
    );
    expect(
      eventsOf<ReputationChanged>(run.events).single.cause,
      RepCause.exactChange,
    );
    expect(spoken(run.events, 'p1'), contains(SpeechSlot.thanks));
    expect(run.engine.passenger('p1').balance, 0);
    expect(resultOf(run).stars, 3);
  },
  'core__short_then_topup.json': (run) {
    // §6.5: short change costs reputation and leaves the rest owed; topping
    // it up is exact.
    expect(
      eventsOf<ChangeDelivered>(run.events)
          .map((e) => (e.result, e.amountPiasters)),
      [(ChangeResult.short, 200), (ChangeResult.exact, 100)],
    );
    expect(eventsOf<ReputationChanged>(run.events).map((e) => e.cause), [
      RepCause.shortChange,
      RepCause.exactChange,
    ]);
    expect(
      eventsOf<ReputationChanged>(run.events).first.delta,
      -run.engine.params.repShortChange,
    );
    expect(resultOf(run).mistakes, isEmpty);
    expect(run.engine.passenger('p1').outcome, AlightOutcome.thanked);
  },
  'core__over_change_kept.json': (run) {
    // §6.5: a regular keeps the excess; it is a mistake and is overpaid.
    expect(
      eventsOf<ChangeDelivered>(run.events).single.result,
      ChangeResult.over,
    );
    final result = resultOf(run);
    expect(result.mistakes.single.toJson(), {
      'passenger_id': 'p1',
      'kind': 'over',
      'amount_piasters': 200,
    });
    expect(result.overpaidPiasters, 200);
    expect(result.earningsJenehat, 5);
    expect(result.stars, 2);
    expect(eventsOf<ExcessReturned>(run.events), isEmpty);
  },
  'core__not_owed_kept.json': (run) {
    // §6.5: change to a passenger owed nothing is a not_owed mistake.
    expect(
      eventsOf<ChangeDelivered>(run.events).single.result,
      ChangeResult.notOwed,
    );
    final result = resultOf(run);
    expect(result.mistakes.single.kind, MistakeKind.notOwed);
    expect(result.overpaidPiasters, 100);
    expect(result.earningsJenehat, 6);
    expect(result.stars, 2);
  },
  'core__fight_at_stop.json': (run) {
    // §9.3: a passenger still owed at their stop fights.
    final fight = eventsOf<ReputationChanged>(run.events).single;
    expect(
      (fight.cause, fight.delta, fight.tMs),
      (RepCause.fight, -run.engine.params.repFight, 20031),
    );
    final result = resultOf(run);
    expect(result.fights, 1);
    expect(result.mistakes.single.kind, MistakeKind.unreturned);
    expect(result.stars, 1);
    expect(run.engine.passenger('p1').outcome, AlightOutcome.fight);
  },
  'core__left_unpaid.json': (run) {
    // §9.3: a passenger who never paid leaves unpaid, a lost fare.
    expect(eventsOf<FareSent>(run.events).map((e) => e.passengerId), ['p2']);
    expect(run.engine.passenger('p1').outcome, AlightOutcome.leftUnpaid);
    expect(resultOf(run).lostFares, 1);
    expect(resultOf(run).faresCollectedPiasters, 700);
  },
  'core__boarding_at_station.json': (run) {
    // §9.4, §9.5: at kobri p1 gets off first, then p2 takes the freed seat
    // and p3 a free one, in the same step.
    final kobri = eventsOf<StationReached>(run.events).first.tMs;
    final atKobri = [
      for (final e in run.events)
        if (e.tMs == kobri && (e is PassengerAlighted || e is PassengerBoarded))
          e.toJson(),
    ];
    expect(atKobri.map((e) => (e['name'], e['passenger_id'])), [
      ('PassengerAlighted', 'p1'),
      ('PassengerBoarded', 'p2'),
      ('PassengerBoarded', 'p3'),
    ]);
    expect(eventsOf<PassengerBoarded>(run.events).first.seatId, 'A_r');
    expect(resultOf(run).stars, 3);
  },
};
