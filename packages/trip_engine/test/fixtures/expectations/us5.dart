// What the US5 fixtures pin: the eight authored events, skipping, and two
// sample trips (rules.md §5.7, §8, §9).
import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../../support/fixture_io.dart';
import '../../support/scripts.dart';

List<int> _stationTimes(Replayed run) => [
  for (final e in eventsOf<StationReached>(run.events)) e.tMs,
];

final us5Expectations = <String, Expectation>{
  'event__bump_collect_and_lose.json': (run) {
    // §5.7: both fares drop; the collected one arrives, the lost one never
    // counts while its passenger is still owed and paid back.
    expect(eventsOf<MoneyDropped>(run.events).map((e) => e.tokenId), [1, 2]);
    expect(eventsOf<DroppedCollected>(run.events).single.tokenId, 1);
    expect(eventsOf<DroppedLost>(run.events).single.tokenId, 2);
    expect(eventsOf<ChangeDelivered>(run.events).map((e) => e.passengerId), [
      'p1',
      'p2',
    ]);
    expect(resultOf(run).faresCollectedPiasters, 700);
    expect(run.engine.passenger('p2').paidIn, 0);
  },
  'event__traffic.json': (run) {
    // §9.1: +10 s from the next station on; traffic speeds up patience
    // until kobri.
    expect(eventsOf<ScheduleShifted>(run.events).single.deltaMs, 10000);
    expect(_stationTimes(run), [30030, 50028]);
    final ranOut = eventsOf<PatienceRanOut>(run.events).single.tMs;
    expect(ranOut, lessThan(1023 + 20000));
    expect(run.engine.state.trafficActive, isFalse);
  },
  'event__open_road_clamped.json': (run) {
    // §9.1: −10 s would bring kobri within the warning, so it is clamped.
    final shift = eventsOf<ScheduleShifted>(run.events).single;
    expect(shift.deltaMs, (15015 + 8000) - 30000);
    expect(_stationTimes(run), [23034, 33033]);
  },
  'event__fare_increase.json': (run) {
    // §6.1, §6.2: p1 tops up to the new fare, p2 (listed) pays the old one
    // and the rest when tapped, p3's earlier fare stands.
    final fares = {
      for (final e in eventsOf<FareSent>(run.events))
        '${e.passengerId}:${e.tokenId}': e.amountPiasters,
    };
    expect(fares, {'p3:1': 1000, 'p1:3': 800, 'p2:4': 700, 'p2:5': 100});
    expect(spoken(run.events, 'p2'), contains(SpeechSlot.paysOldFare));
    expect(spoken(run.events, 'p2'), contains(SpeechSlot.paysRest));
    expect(resultOf(run).faresCollectedPiasters, 800 + 800 + 700);
  },
  'event__drop_me_here.json': (run) {
    // §8, §9.3: p1 gets off at the deadline, and p2, waiting since kobri,
    // takes the seat then.
    final deadline = eventsOf<StopChanged>(run.events).single.deadlineMs;
    final off = eventsOf<PassengerAlighted>(run.events).first;
    expect(off.passengerId, 'p1');
    expect(off.tMs, inInclusiveRange(deadline, deadline + 32));
    expect(eventsOf<PassengerBoarded>(run.events).single.tMs, off.tMs);
  },
  'event__payment_dispute.json': (run) {
    // §4.7: naming p1, who paid, is right: p2 is caught and pays.
    expect(eventsOf<DisputeResolved>(run.events).single.right, isTrue);
    expect(eventsOf<LiarCaught>(run.events).single.passengerId, 'p2');
    expect(resultOf(run).caughtLiars, 1);
    expect(resultOf(run).faresCollectedPiasters, 1400);
  },
  'event__change_request.json': (run) {
    // §4.8, §5.5: the tray's two 500s go out and the 1000 note comes back.
    final hops = eventsOf<TokenHopStarted>(run.events);
    final breakOut = hops.firstWhere((e) => e.from == Holder.driver);
    expect(breakOut.to.wire, 'p1');
    expect(eventsOf<ChangeRequestCompleted>(run.events), hasLength(1));
    final tray = run.engine.state.tray;
    expect((tray.count(1000), tray.count(500)), (1, 1));
  },
  'event__roadside_pickup.json': (run) {
    // §9.5: p2 boards at the event; p3 waits for p1's seat.
    expect(
      eventsOf<PassengerBoarded>(run.events).map((e) => (e.passengerId, e.tMs)),
      [('p2', 5016), ('p3', eventsOf<StationReached>(run.events).first.tMs)],
    );
  },
  'event__skipped.json': (run) {
    // §8: an event naming someone not aboard is skipped and never fires.
    expect(
      eventsOf<EventSkipped>(run.events).map((e) => (e.index, e.eventId)),
      [(0, EventId.dropMeHere), (2, EventId.changeRequest)],
    );
    expect(eventsOf<EventStarted>(run.events).single.index, 1);
    expect(run.engine.passenger('p2').deadlineMs, isNull);
  },
  'sample__line_hay_02_three_stars.json': (run) {
    // Sample line_hay.02 to 3 stars: traffic, then the dispute answered
    // right.
    expect(run.engine.definition.tripId, 'line_hay.02');
    expect(eventsOf<DisputeResolved>(run.events).single.right, isTrue);
    expect(resultOf(run).stars, 3);
  },
  'sample__line_gamaa_01_three_stars.json': (run) {
    // Sample line_gamaa.01 to 3 stars: the sleeper is woken in time for
    // kobri, and the change the bump drops is collected and sent again.
    expect(run.engine.definition.tripId, 'line_gamaa.01');
    expect(eventsOf<DroppedCollected>(run.events), hasLength(1));
    expect(run.engine.passenger('p2').outcome, AlightOutcome.thanked);
    expect(resultOf(run).stars, 3);
  },
};
