// Groups (rules.md §4.5, §6.1, §6.5.1, §7.2): the payer pays for everyone
// and receives the group's change.
import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/builders.dart';
import '../support/edits.dart';
import '../support/scripts.dart';

// The payer p1 and a listed member p2 on an 850 stop. [size] counts the
// payer, so a size of 3 leaves one member unlisted.
TripBuilder _group({
  int size = 2,
  List<int> payment = const [2000],
  int? paysAt = 1,
  String memberDest = 'gamaa',
}) => TripBuilder()
  ..station('kobri', 20)
  ..station('gamaa', 50, fare: 850)
  ..passenger(
    'p1',
    seat: 'A_r',
    dest: 'gamaa',
    payment: payment,
    paysAt: paysAt,
    archetype: Archetype.groupPayer,
    group: 'g1',
    groupSize: size,
  )
  ..passenger(
    'p2',
    seat: 'A_m',
    dest: memberDest,
    payment: const [1000],
    group: 'g1',
    groupSize: size,
  );

void _give(TripEngine engine, String passengerId, List<int> pieces) {
  for (final piece in pieces) {
    engine.ok(PickFromTray(piece));
  }
  engine.ok(SendHand(passengerId));
}

void main() {
  test('the group fare counts unlisted members at the base fare', () {
    final engine = startTrip(_group(size: 3, payment: [5000]).build())
      ..stepTo(1023);
    final payer = engine.passenger('p1');
    expect(payer.farePiasters, 850 * 3);
    expect(payer.balance, 2450);
  });

  test('a tap on a member acts on the payer', () {
    final engine = startTrip(_group(paysAt: null).build());
    final events = engine.ok(const Tap('p2'));
    expect(eventsOf<FareSent>(events).single.passengerId, 'p1');
    expect(spoken(events, 'p1'), [SpeechSlot.paysGroup]);
  });

  test('members never pay or claim', () {
    final engine = startTrip(_group().build());
    final events = engine.stepToSeconds(60);
    expect(eventsOf<FareSent>(events).map((e) => e.passengerId), ['p1']);
    expect(eventsOf<ClaimRaised>(events), isEmpty);
    expect(engine.passenger('p2').fareSent, isFalse);
  });

  test("a member's change goes on to the payer in one 600 ms hop", () {
    final engine = startTrip(_group().build())..stepToSeconds(3);
    _give(engine, 'p2', [100, 100, 100]);
    final events = engine.stepToSeconds(6);
    final redirect = eventsOf<TokenHopStarted>(events).last;
    expect(
      (redirect.from.wire, redirect.to.wire, redirect.durationMs),
      ('p2', 'p1', 600),
    );
    final delivered = eventsOf<ChangeDelivered>(events).single;
    expect(
      (delivered.passengerId, delivered.result),
      ('p1', ChangeResult.exact),
    );
    expect(engine.passenger('p1').balance, 0);
  });

  test("with the payer gone, a member's change is not owed", () {
    final engine = startTrip(
      (TripBuilder()
            ..station('kobri', 20)
            ..station('gamaa', 50)
            ..passenger(
              'p1',
              seat: 'A_r',
              dest: 'kobri',
              payment: [500, 100, 100, 500, 100, 100],
              paysAt: 1,
              archetype: Archetype.groupPayer,
              group: 'g1',
              groupSize: 2,
            )
            ..passenger(
              'p2',
              seat: 'A_m',
              dest: 'gamaa',
              payment: [1000],
              group: 'g1',
              groupSize: 2,
            ))
          .build(),
    )..stepToSeconds(25);
    _give(engine, 'p2', [100]);
    final events = engine.stepToSeconds(30);
    expect(
      eventsOf<ChangeDelivered>(events).single.result,
      ChangeResult.notOwed,
    );
  });

  test('members get off thanked, or with a missed stop if asleep', () {
    final thanked = startTrip(_group(memberDest: 'kobri').build())
      ..stepToSeconds(25);
    expect(thanked.passenger('p2').outcome, AlightOutcome.thanked);
    final asleep = startTrip(_group(memberDest: 'kobri').build());
    setAlertness(asleep, 'p2', Alertness.asleep);
    asleep.stepToSeconds(25);
    expect(asleep.passenger('p2').outcome, AlightOutcome.missedStop);
    expect(asleep.state.counters.lostFares, 0);
  });

  test('change to a member whose payer has left is judged not owed', () {
    // The payer p1 gets off at kobri; change sent to p2 after that stays
    // with p2, who is owed nothing.
    final engine = startTrip(
      (TripBuilder()
            ..station('kobri', 20)
            ..station('gamaa', 50, fare: 850)
            ..passenger(
              'p1',
              seat: 'A_r',
              dest: 'kobri',
              payment: const [2000],
              paysAt: 1,
              archetype: Archetype.groupPayer,
              group: 'g1',
              groupSize: 2,
            )
            ..passenger(
              'p2',
              seat: 'A_m',
              dest: 'gamaa',
              payment: const [1000],
              group: 'g1',
              groupSize: 2,
            ))
          .build(),
    )..stepToSeconds(21);
    expect(engine.passenger('p1').presence, Presence.gone);
    _give(engine, 'p2', [100]);
    final events = engine.stepToSeconds(25);
    final delivered = eventsOf<ChangeDelivered>(events).single;
    expect(
      (delivered.passengerId, delivered.result),
      ('p2', ChangeResult.notOwed),
    );
    expect(engine.state.tokens, isEmpty);
    expect(engine.state.mistakes.last.kind, MistakeKind.notOwed);
  });
}
