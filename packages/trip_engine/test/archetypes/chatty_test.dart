// Chatty (rules.md §5.4): while able, a chatty passenger slows every hop out
// of a seat in their row to scale(trip_hop_ms, trip_hop_pct_chatty_row).
import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/builders.dart';
import '../support/edits.dart';
import '../support/scripts.dart';

// p1 in C_r pays; p3 in B_r passes it on; the chatty p2 sits in B_m.
TripBuilder _row({
  Archetype middle = Archetype.regular,
  String chattyDest = 'gamaa',
}) => TripBuilder()
  ..station('kobri', 2)
  ..station('gamaa', 60)
  ..passenger(
    'p1',
    seat: 'C_r',
    dest: 'gamaa',
    payment: [500, 100, 100],
    paysAt: 5,
  )
  ..passenger(
    'p2',
    seat: 'B_m',
    dest: chattyDest,
    payment: [500, 100, 100],
    archetype: Archetype.chatty,
  )
  ..passenger(
    'p3',
    seat: 'B_r',
    dest: 'gamaa',
    payment: [500, 100, 100],
    archetype: middle,
  );

List<(String, int)> _fareHops(TripEngine engine) => [
  for (final hop in eventsOf<TokenHopStarted>(engine.stepToSeconds(15)))
    if (hop.tokenId == 1) ('${hop.from.wire}>${hop.to.wire}', hop.durationMs),
];

void main() {
  test('hops out of a seat in their row are slower, others are not', () {
    final engine = startTrip(_row().build());
    expect(_fareHops(engine), [('p1>p3', 1100), ('p3>DRIVER', 1650)]);
  });

  test('the multiplier stacks after the hajja', () {
    final engine = startTrip(_row(middle: Archetype.hajja).build());
    expect(_fareHops(engine), [('p1>p3', 1100), ('p3>DRIVER', 3300)]);
  });

  test('it does not apply while the chatty passenger is not able', () {
    final engine = startTrip(_row().build());
    setAlertness(engine, 'p2', Alertness.asleep);
    expect(_fareHops(engine), [('p1>p3', 1100), ('p3>DRIVER', 1100)]);
  });

  test('it does not apply after they get off', () {
    final engine = startTrip(_row(chattyDest: 'kobri').build());
    expect(_fareHops(engine), [('p1>p3', 1100), ('p3>DRIVER', 1100)]);
  });
}
