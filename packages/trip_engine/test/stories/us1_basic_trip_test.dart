// US1's Independent Test and acceptance scenarios on sample line_hay.01
// (tuktuk, hop 1300 ms): p1 pays 1000 at 3 s for a 700 fare and gets off at
// madrasa (30 s); p2, a student at 50%, pays 1000 at 8 s for 350 and gets off
// at forn (55 s).
import 'dart:convert';
import 'dart:io';

import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/builders.dart';
import '../support/scripts.dart';

final _lineHay01 = TripDefinition.fromJson(
  jsonDecode(
    File('../../content/examples/sample/trips/line_hay/line_hay.01.json')
        .readAsStringSync(),
  ) as Map<String, dynamic>,
);

/// Steps to [tMs], picks [pieces] and sends them to [passengerId].
List<DomainEvent> _give(
  TripEngine engine,
  int tMs,
  String passengerId,
  List<int> pieces,
) => [
  ...engine.stepTo(tMs),
  for (final piece in pieces) ...engine.ok(PickFromTray(piece)),
  ...engine.ok(SendHand(passengerId)),
];

/// The 3-star script, with p1's change replaced by [p1Change].
List<DomainEvent> _play(
  TripEngine engine, {
  List<int>? p1Change = const [100, 100, 100],
}) => [
  // p1's fare reaches the tray at 3003 + 40 × 33 = 4323.
  if (p1Change != null) ..._give(engine, 4323, 'p1', p1Change),
  // p2's at 8019 + 1320 = 9339.
  ..._give(engine, 9339, 'p2', [500, 100, 50]),
  ...engine.stepToSeconds(60),
];

void main() {
  test('the 3-star run, with its exact earnings', () {
    final engine = startTrip(_lineHay01);
    final events = _play(engine);
    final result = engine.result!;
    expect(engine.status, TripStatus.finished);
    expect(result.stars, 3);
    expect(result.faresCollectedPiasters, 700 + 350);
    expect(result.earningsJenehat, 10);
    expect(result.durationMs, 55011);
    expect(result.mistakes, isEmpty);
    expect(result.fights, 0);
    expect(
      eventsOf<ChangeDelivered>(events).map((e) => (e.passengerId, e.result)),
      [('p1', ChangeResult.exact), ('p2', ChangeResult.exact)],
    );
    expect(
      eventsOf<PassengerAlighted>(events)
          .map((e) => (e.passengerId, e.outcome)),
      [('p1', AlightOutcome.thanked), ('p2', AlightOutcome.thanked)],
    );
    expect(
      engine.state.tray.total,
      Pieces({100: 4, 50: 4, 500: 2}).total + 1050,
    );
  });

  test('scenario 1: exact change settles, the reward never goes above 100', () {
    final engine = startTrip(_lineHay01);
    final events = _play(engine);
    final rewards = eventsOf<ReputationChanged>(events)
        .where((e) => e.cause == RepCause.exactChange);
    expect(rewards.map((e) => e.value), [100, 100]);
    expect(engine.passenger('p1').balance, 0);
  });

  test('scenario 2: a fare from row C hops seat by seat, and change goes back the same way', () {
    final engine = startTrip(
      (TripBuilder()
            ..station('gamaa', 60)
            ..passenger(
              'p1',
              seat: 'C_r',
              dest: 'gamaa',
              payment: [1000],
              paysAt: 0,
            )
            ..passenger('p2', seat: 'B_r', dest: 'gamaa', payment: [1000])
            ..passenger('p3', seat: 'A_r', dest: 'gamaa', payment: [1000]))
          .build(),
    );
    final fare = engine.stepToSeconds(5);
    expect(
      eventsOf<TokenHopStarted>(fare).map((e) => '${e.from.wire}>${e.to.wire}'),
      ['p1>p2', 'p2>p3', 'p3>DRIVER'],
    );
    for (final piece in [100, 100, 100]) {
      engine.ok(PickFromTray(piece));
    }
    engine.ok(const SendHand('p1'));
    final change = engine.stepToSeconds(10);
    expect(
      eventsOf<TokenHopStarted>(change)
          .map((e) => '${e.from.wire}>${e.to.wire}'),
      ['DRIVER>p3', 'p3>p2', 'p2>p1'],
    );
    expect(eventsOf<ChangeDelivered>(change).single.result, ChangeResult.exact);
  });

  test('over-change gives 2 stars and one over mistake', () {
    final engine = startTrip(_lineHay01);
    _play(engine, p1Change: [100, 100, 100, 50, 50]);
    final result = engine.result!;
    expect(result.stars, 2);
    expect(result.mistakes.single.toJson(), {
      'passenger_id': 'p1',
      'kind': 'over',
      'amount_piasters': 100,
    });
    expect(result.earningsJenehat, 9);
  });

  test('scenario 3: withheld change gives a fight at the stop and 1 star', () {
    final engine = startTrip(_lineHay01);
    final events = _play(engine, p1Change: null);
    final fight = eventsOf<ReputationChanged>(events)
        .singleWhere((e) => e.cause == RepCause.fight);
    expect(fight.delta, -30);
    expect(fight.tMs, 30030);
    expect(engine.result!.fights, 1);
    expect(engine.result!.stars, 1);
    expect(engine.result!.mistakes.single.kind, MistakeKind.unreturned);
  });

  test(
    'scenario 4: an unpaid passenger is a lost fare, not in the earnings',
    () {
      final engine = startTrip(
        (TripBuilder(vehicle: VehicleId.tuktuk, line: LineId.lineHay)
              ..station('madrasa', 10)
              ..passenger('p1', seat: 'A_r', dest: 'madrasa', payment: [1000]))
            .build(),
      )..stepToSeconds(20);
      expect(engine.result!.lostFares, 1);
      expect(engine.result!.faresCollectedPiasters, 0);
      expect(engine.result!.earningsJenehat, 0);
      expect(engine.passenger('p1').outcome, AlightOutcome.leftUnpaid);
    },
  );

  test('scenario 5: bad sends and picks are rejected and change nothing', () {
    final engine = startTrip(_lineHay01);
    engine.rejects(const SendHand('p1'), RejectionCode.handEmpty);
    engine.rejects(const PickFromTray(1000), RejectionCode.trayEmpty);
    _play(engine, p1Change: [100, 100, 100]);
    expect(engine.status, TripStatus.finished);
    engine.rejects(const PickFromTray(100), RejectionCode.wrongStatus);
  });

  test(
    'scenario 6: stars count fights and mistakes, earnings are whole pounds',
    () {
      final perfect = startTrip(_lineHay01);
      _play(perfect);
      final over = startTrip(_lineHay01);
      _play(over, p1Change: [100, 100, 100, 50, 50]);
      final withheld = startTrip(_lineHay01);
      _play(withheld, p1Change: null);
      expect([perfect, over, withheld].map((e) => e.result!.stars), [3, 2, 1]);
      expect(
        withheld.result!.earningsJenehat,
        10,
        reason: 'fares 1050, nothing given away',
      );
    },
  );
}
