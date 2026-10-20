// What the US4 fixtures pin: the line_gamaa passenger types, claims and
// groups (rules.md §4.5, §4.6, §5.4, §6.1, §6.5.1, §7, §9.3).
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../../support/fixture_io.dart';
import '../../support/scripts.dart';

final us4Expectations = <String, Expectation>{
  'archetype__big_note_drains_tray.json': (run) {
    // §7.1: a 20000 note on a 700 fare is owed 19300, which takes every
    // large piece in the tray.
    expect(eventsOf<ChangeSent>(run.events).single.amountPiasters, 19300);
    expect(
      eventsOf<ChangeDelivered>(run.events).single.result,
      ChangeResult.exact,
    );
    final tray = run.engine.state.tray;
    for (final note in [2000, 5000, 10000]) {
      expect(tray.counts[note] ?? 0, 0, reason: '$note left in the tray');
    }
    expect(tray.counts[20000], 1);
  },
  'archetype__student_half_fare.json': (run) {
    // §6.1: 850 at 50% is 450, rounded up to the coin.
    expect(run.engine.passenger('p1').farePiasters, 450);
    expect(eventsOf<ChangeSent>(run.events).single.amountPiasters, 50);
    expect(resultOf(run).faresCollectedPiasters, 450);
  },
  'archetype__headphones_called_twice.json': (run) {
    // §4.5 case 3: muted p2 blocks the chain until called twice, pays as
    // soon as attentive, and is muted again 15 s later.
    expect(eventsOf<TokenBlocked>(run.events).single.by, 'p2');
    final called = eventsOf<PassengerCalled>(run.events).single;
    final attentive = eventsOf<PassengerAttentive>(run.events).single;
    expect((called.taps, called.tMs), (1, attentive.tMs));
    expect(
      eventsOf<FareSent>(run.events)
          .singleWhere((e) => e.passengerId == 'p2')
          .tMs,
      attentive.tMs + 33,
    );
    expect(
      eventsOf<PassengerMuted>(run.events).single.tMs - attentive.tMs,
      inInclusiveRange(15000, 15000 + 32),
    );
  },
  'archetype__false_claimer_caught.json': (run) {
    // §4.6: insisting on a false claim catches the liar, who pays.
    final result = resultOf(run);
    expect(result.caughtLiars, 1);
    expect(
      eventsOf<LiarCaught>(run.events).single.tMs,
      eventsOf<FareSent>(run.events).single.tMs,
    );
    expect(result.faresCollectedPiasters, 700);
    expect(result.stars, 3);
  },
  'archetype__false_claimer_believed.json': (run) {
    // §4.6, §6.3: a believed false claimer never pays; a later tap only
    // makes them say so again.
    expect(eventsOf<ClaimAccepted>(run.events).single.passengerId, 'p1');
    expect(eventsOf<FareSent>(run.events).map((e) => e.passengerId), ['p2']);
    expect(
      spoken(run.events, 'p1').where((s) => s == SpeechSlot.claimsPaid),
      hasLength(2),
    );
    expect(run.engine.passenger('p1').outcome, AlightOutcome.leftUnpaid);
    expect(resultOf(run).lostFares, 1);
  },
  'core__false_accusation.json': (run) {
    // §4.5 case 7, §4.6: a tap on a passenger who paid opens a truthful
    // claim, and insisting on it is a false accusation, a fight.
    final result = resultOf(run);
    expect(eventsOf<FalseAccusation>(run.events), hasLength(1));
    expect(result.reputationLost, {
      RepCause.falseAccusation: run.engine.params.repFalseAccusation,
    });
    expect(result.fights, 1);
    expect(result.stars, 1);
  },
  'archetype__group_payer_redirect.json': (run) {
    // §6.1, §6.5.1: the payer pays for three, and change sent to the member
    // goes on to the payer in one 600 ms hop.
    expect(run.engine.passenger('p1').farePiasters, 850 * 3);
    final redirect = eventsOf<TokenHopStarted>(run.events).last;
    expect(
      (redirect.from.wire, redirect.to.wire, redirect.durationMs),
      ('p2', 'p1', run.engine.params.tripGroupRedirectHopMs),
    );
    final delivered = eventsOf<ChangeDelivered>(run.events).single;
    expect((delivered.passengerId, delivered.amountPiasters), ('p1', 2450));
    expect(run.engine.passenger('p2').outcome, AlightOutcome.thanked);
  },
  'archetype__chatty_row.json': (run) {
    // §5.4: hops out of row B, where chatty p2 sits, take 150%.
    final slow = run.engine.params.tripHopMs * 3 ~/ 2;
    final out = {
      for (final hop in eventsOf<TokenHopStarted>(run.events))
        '${hop.from.wire}>${hop.to.wire}': hop.durationMs,
    };
    expect(out['p1>p3'], run.engine.params.tripHopMs);
    expect(out['p3>DRIVER'], slow);
    expect(out['p3>p1'], slow);
    expect(out['p2>DRIVER'], slow);
    expect(out['DRIVER>p3'], run.engine.params.tripHopMs);
  },
  'archetype__regular_customer_tip.json': (run) {
    // §9.3: the patient regular customer tips; the impatient one doesn't.
    final tips = eventsOf<PassengerSpeaks>(run.events)
        .where((e) => e.slot == SpeechSlot.tip);
    expect(tips.map((e) => e.passengerId), ['p1']);
    final result = resultOf(run);
    expect(
      result.tipsPiasters,
      run.engine.params.tripTipPiastersRegularCustomer,
    );
    expect(result.impatient, 1);
    expect(result.earningsJenehat, (1400 + 200) ~/ 100);
  },
  'sample__line_gamaa_02_three_stars.json': (run) {
    // Sample line_gamaa.02 to 3 stars: the sleeper is left asleep, misses
    // his stop and never pays, which costs no star.
    expect(run.engine.definition.tripId, 'line_gamaa.02');
    final result = resultOf(run);
    expect(result.stars, 3);
    expect(result.missedStops, 1);
    expect(result.lostFares, 1);
    expect(eventsOf<ChangeDelivered>(run.events).map((e) => e.result).toSet(), {
      ChangeResult.exact,
    });
  },
};
