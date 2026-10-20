// Fares and payments (rules.md §6.1–§6.4) and fares collected (§11).
import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/builders.dart';
import '../support/scripts.dart';

TripEngine _paying(
  List<int> payment, {
  int fare = 850,
  Archetype archetype = Archetype.regular,
  int discount = 0,
}) {
  final engine = startTrip(
    (TripBuilder()
          ..rules(studentDiscountPct: discount)
          ..station('kobri', 30, fare: fare)
          ..passenger(
            'p1',
            archetype: archetype,
            seat: 'A_r',
            dest: 'kobri',
            payment: payment,
            paysAt: 0,
          ))
        .build(),
  );
  engine.step();
  return engine;
}

void main() {
  test("the fare is the destination's fare", () {
    final p1 = _paying([1000]).passenger('p1');
    expect(p1.fareSent, isTrue);
    expect(p1.farePiasters, 850);
    expect(p1.balance, 150);
  });

  test("a student's fare is discounted and rounded up to 50", () {
    int fare(int stationFare, int discount) => _paying(
      [1000],
      fare: stationFare,
      archetype: Archetype.student,
      discount: discount,
    ).passenger('p1').farePiasters!;
    expect(fare(850, 50), 450);
    expect(fare(700, 50), 350);
    expect(fare(850, 0), 850);
    expect(fare(850, 100), 0);
  });

  test('only students get the discount', () {
    expect(_paying([1000], discount: 50).passenger('p1').farePiasters, 850);
  });

  test('paying sends the authored pieces and fixes the balance', () {
    final owed = _paying([1000]);
    expect(owed.state.tokens.single.pieces, Pieces({1000: 1}));
    expect(owed.state.tokens.single.kind, TokenKind.fare);
    expect(owed.passenger('p1').balance, 150);
    expect(_paying([500, 100, 100, 100, 50]).passenger('p1').balance, 0);
    expect(_paying([500]).passenger('p1').balance, -350);
  });

  test('paying emits FareSent and the pays speech with the amount', () {
    final engine = startTrip(
      (TripBuilder()
            ..station('kobri', 30, fare: 850)
            ..passenger(
              'p1',
              seat: 'A_r',
              dest: 'kobri',
              payment: [1000],
              paysAt: 0,
            ))
          .build(),
    );
    final events = engine.step();
    final sent = eventsOf<FareSent>(events).single;
    expect(
      (sent.passengerId, sent.tokenId, sent.amountPiasters),
      ('p1', 1, 1000),
    );
    final speech = eventsOf<PassengerSpeaks>(events).single;
    expect((speech.slot, speech.amountPiasters), (SpeechSlot.pays, 1000));
  });

  test('a tap on a passenger who owes makes them pay the rest in the fewest pieces', () {
    final engine = _paying([500]);
    final events = engine.ok(const Tap('p1'));
    final rest = eventsOf<FareSent>(events).single;
    expect(rest.amountPiasters, 350);
    expect(engine.state.token(rest.tokenId)!.pieces, Pieces({100: 3, 50: 1}));
    expect(engine.passenger('p1').balance, 0);
    final speech = eventsOf<PassengerSpeaks>(events).single;
    expect((speech.slot, speech.amountPiasters), (SpeechSlot.paysRest, 350));
  });

  test('fares collected is the sum of min(fare, paid in)', () {
    final engine = startTrip(
      (TripBuilder()
            ..station('kobri', 10, fare: 850)
            ..passenger(
              'p1',
              seat: 'A_r',
              dest: 'kobri',
              payment: [500, 100, 100, 100, 50],
              paysAt: 0,
            )
            ..passenger(
              'p2',
              seat: 'A_m',
              dest: 'kobri',
              payment: [500],
              paysAt: 0,
            )
            ..passenger('p3', seat: 'A_l', dest: 'kobri', payment: [1000]))
          .build(),
    )..stepToSeconds(20);
    expect(engine.status, TripStatus.finished);
    expect(engine.result!.faresCollectedPiasters, 850 + 500);
    expect(engine.result!.lostFares, 1);
  });
}
