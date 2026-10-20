// Judging change (rules.md §6.5): exact, short, over and not owed, and the
// honest passenger's returns.
import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/builders.dart';
import '../support/edits.dart';
import '../support/scripts.dart';

/// p1 (A_r) owes nothing yet and pays 1000 for an 850 fare at 0 s; the fare
/// reaches the tray at 1155 ms. p2 (A_m) never pays.
TripEngine _trip({
  Archetype archetype = Archetype.regular,
  List<int> payment = const [1000],
}) {
  final engine = startTrip(
    (TripBuilder()
          ..station('gamaa', 60, fare: 850)
          ..passenger(
            'p1',
            archetype: archetype,
            seat: 'A_r',
            dest: 'gamaa',
            payment: payment,
            paysAt: 0,
          )
          ..passenger(
            'p2',
            archetype: archetype,
            seat: 'A_m',
            dest: 'gamaa',
            payment: [1000],
          ))
        .build(),
  );
  engine.stepTo(1155);
  return engine;
}

/// Picks [pieces], sends them to [passengerId], and steps until the change
/// is judged. Returns the events from the send on.
List<DomainEvent> _give(
  TripEngine engine,
  String passengerId,
  List<int> pieces,
) {
  final events = <DomainEvent>[];
  for (final piece in pieces) {
    events.addAll(engine.ok(PickFromTray(piece)));
  }
  events.addAll(engine.ok(SendHand(passengerId)));
  for (var i = 0; i < 100 && eventsOf<ChangeDelivered>(events).isEmpty; i++) {
    events.addAll(engine.step());
  }
  return events;
}

ChangeDelivered _judged(List<DomainEvent> events) =>
    eventsOf<ChangeDelivered>(events).single;

void main() {
  group('exact', () {
    test('settles the passenger and rewards rep_exact_change', () {
      final engine = _trip();
      setReputation(engine, 90);
      final events = _give(engine, 'p1', [100, 50]);
      expect(_judged(events).result, ChangeResult.exact);
      expect(_judged(events).amountPiasters, 150);
      expect(engine.passenger('p1').balance, 0);
      expect(engine.state.reputation, 93);
      final rep = eventsOf<ReputationChanged>(events).single;
      expect((rep.delta, rep.cause, rep.value), (3, RepCause.exactChange, 93));
      expect(spoken(events, 'p1'), [SpeechSlot.thanks]);
      expect(engine.state.mistakes, isEmpty);
    });

    test('the reward is capped at 100', () {
      final engine = _trip();
      setReputation(engine, 99);
      final events = _give(engine, 'p1', [100, 50]);
      expect(engine.state.reputation, 100);
      expect(eventsOf<ReputationChanged>(events).single.delta, 1);
    });
  });

  test('short change lowers the balance and costs rep_short_change; a top-up that settles is exact', () {
    final engine = _trip();
    final short = _give(engine, 'p1', [100]);
    expect(_judged(short).result, ChangeResult.short);
    expect(engine.passenger('p1').balance, 50);
    expect(engine.state.reputation, 95);
    expect(engine.state.reputationLost, {RepCause.shortChange: 5});
    final speech = eventsOf<PassengerSpeaks>(short).single;
    expect((speech.slot, speech.amountPiasters), (SpeechSlot.shortChange, 50));
    final topUp = _give(engine, 'p1', [50]);
    expect(_judged(topUp).result, ChangeResult.exact);
    expect(engine.passenger('p1').balance, 0);
    expect(engine.state.reputation, 98);
  });

  group('over', () {
    test('records the excess as a mistake, kept by a regular passenger', () {
      final engine = _trip();
      final events = _give(engine, 'p1', [100, 100]);
      expect(_judged(events).result, ChangeResult.over);
      expect(_judged(events).amountPiasters, 200);
      expect(engine.passenger('p1').balance, 0);
      expect(engine.state.mistakes.single.toJson(), {
        'passenger_id': 'p1',
        'kind': 'over',
        'amount_piasters': 50,
      });
      expect(eventsOf<MistakeMade>(events).single.amountPiasters, 50);
      expect(engine.state.counters.overpaidPiasters, 50);
      expect(engine.state.reputation, 100);
    });

    test('an honest passenger returns the excess in the fewest pieces, to the tray', () {
      final engine = _trip(archetype: Archetype.honest);
      final events = _give(engine, 'p1', [100, 100]);
      expect(spoken(events, 'p1'), [SpeechSlot.returnsExcess]);
      expect(eventsOf<PassengerSpeaks>(events).single.amountPiasters, 50);
      final back = engine.state.tokens.single;
      expect(
        (back.kind, back.pieces, back.target),
        (TokenKind.returned, Pieces({50: 1}), Holder.driver),
      );
      final tray = engine.state.tray;
      final returned = engine.stepToSeconds(5);
      expect(eventsOf<ExcessReturned>(returned).single.amountPiasters, 50);
      expect(engine.state.tray, tray.plusOne(50));
      expect(engine.state.counters.overpaidPiasters, 0);
      expect(engine.state.mistakes.single.kind, MistakeKind.over);
    });
  });

  group('not owed', () {
    test(
      'change to a passenger who has not paid is a mistake of the whole token',
      () {
        final engine = _trip();
        final events = _give(engine, 'p2', [100]);
        expect(_judged(events).result, ChangeResult.notOwed);
        expect(engine.state.mistakes.single.toJson(), {
          'passenger_id': 'p2',
          'kind': 'not_owed',
          'amount_piasters': 100,
        });
        expect(engine.state.counters.overpaidPiasters, 100);
      },
    );

    test('change to a passenger owed nothing is not owed', () {
      final engine = _trip(payment: [500, 100, 100, 100, 50]);
      final events = _give(engine, 'p1', [50]);
      expect(_judged(events).result, ChangeResult.notOwed);
      expect(engine.state.counters.overpaidPiasters, 50);
    });

    test('an honest passenger sends the same pieces back', () {
      final engine = _trip(archetype: Archetype.honest);
      final events = _give(engine, 'p2', [100]);
      expect(spoken(events, 'p2'), [SpeechSlot.returnsExcess]);
      expect(engine.state.tokens.single.pieces, Pieces({100: 1}));
      engine.stepToSeconds(5);
      expect(engine.state.counters.overpaidPiasters, 0);
    });
  });

  test('two tokens to the same passenger are judged in arrival order', () {
    final engine = _trip();
    engine
      ..ok(const PickFromTray(100))
      ..ok(const SendHand('p1'))
      ..ok(const PickFromTray(50))
      ..ok(const SendHand('p1'));
    final events = engine.stepToSeconds(5);
    expect(
      eventsOf<ChangeDelivered>(events).map((e) => (e.tokenId, e.result)),
      [(2, ChangeResult.short), (3, ChangeResult.exact)],
    );
    expect(engine.passenger('p1').balance, 0);
  });
}
