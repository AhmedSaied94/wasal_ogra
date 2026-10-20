// The hajja (rules.md §5.4): a hop she passes on lasts
// scale(trip_hop_ms, trip_hop_pct_hajja); a hop to her takes the usual time.
import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/builders.dart';
import '../support/scripts.dart';

List<(String, int)> _hops(Iterable<DomainEvent> events) => [
  for (final hop in eventsOf<TokenHopStarted>(events))
    ('${hop.from.wire}>${hop.to.wire}', hop.durationMs),
];

void main() {
  test(
    'her own fare hops at 2600 ms on line_hay, and her coins reach the tray',
    () {
      final engine = startTrip(
        (TripBuilder(vehicle: VehicleId.tuktuk, line: LineId.lineHay)
              ..station('madrasa', 30)
              ..passenger(
                'p1',
                seat: 'A_r',
                dest: 'madrasa',
                payment: [500, 100, 100],
                paysAt: 1,
                archetype: Archetype.hajja,
              ))
            .build(),
      );
      final trayBefore = engine.state.tray.total;
      // 2600 ms is 79 steps from 1023.
      final events = engine.stepTo(3597);
      expect(_hops(events), [('p1>DRIVER', 2600)]);
      expect(eventsOf<MoneyArrivedAtDriver>(events), isEmpty);
      final arrived = engine.step();
      expect(engine.state.tMs, 3630);
      expect(
        eventsOf<MoneyArrivedAtDriver>(arrived).single.amountPiasters,
        700,
      );
      expect(engine.state.tray.total, trayBefore + 700);
    },
  );

  test('as a middle holder only the hop out of her seat is slow', () {
    final engine = startTrip(
      (TripBuilder()
            ..station('gamaa', 40)
            ..passenger(
              'p1',
              seat: 'C_r',
              dest: 'gamaa',
              payment: [1000],
              paysAt: 1,
            )
            ..passenger(
              'p2',
              seat: 'B_r',
              dest: 'gamaa',
              payment: [500, 100, 100],
              archetype: Archetype.hajja,
            ))
          .build(),
    );
    final fare = engine.stepToSeconds(6);
    expect(_hops(fare), [('p1>p2', 1100), ('p2>DRIVER', 2200)]);
    for (final piece in [100, 100, 100]) {
      engine.ok(PickFromTray(piece));
    }
    engine.ok(const SendHand('p1'));
    final change = engine.stepToSeconds(12);
    expect(_hops(change), [('DRIVER>p2', 1100), ('p2>p1', 2200)]);
    expect(eventsOf<ChangeDelivered>(change).single.result, ChangeResult.exact);
  });
}
