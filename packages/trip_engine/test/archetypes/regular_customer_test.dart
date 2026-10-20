// The regular customer's tip (rules.md §9.3), the big note and the student
// (§6.1, §7.1).
import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/builders.dart';
import '../support/scripts.dart';

TripEngine _one(
  Archetype archetype, {
  List<int> payment = const [500, 100, 100],
  int fare = 700,
  int studentDiscountPct = 0,
}) => startTrip(
  (TripBuilder()
        ..station('gamaa', 30, fare: fare)
        ..passenger(
          'p1',
          seat: 'A_r',
          dest: 'gamaa',
          payment: payment,
          paysAt: 1,
          archetype: archetype,
        )
        ..rules(studentDiscountPct: studentDiscountPct))
      .build(),
);

void main() {
  test('thanked and not impatient, a regular customer tips', () {
    final engine = _one(Archetype.regularCustomer);
    final events = engine.stepToSeconds(40);
    final tip = eventsOf<PassengerSpeaks>(events)
        .singleWhere((e) => e.slot == SpeechSlot.tip);
    expect(tip.amountPiasters, engine.params.tripTipPiastersRegularCustomer);
    final result = engine.result!;
    expect(result.tipsPiasters, 200);
    expect(result.earningsJenehat, 9, reason: 'fare 700 plus the 200 tip');
  });

  test('an impatient regular customer tips nothing', () {
    final engine = _one(Archetype.regularCustomer, payment: [1000])
      ..stepToSeconds(22);
    expect(engine.passenger('p1').impatient, isTrue);
    for (final piece in [100, 100, 100]) {
      engine.ok(PickFromTray(piece));
    }
    engine
      ..ok(const SendHand('p1'))
      ..stepToSeconds(40);
    expect(engine.passenger('p1').outcome, AlightOutcome.thanked);
    expect(engine.result!.tipsPiasters, 0);
  });

  test('a regular customer who fights tips nothing', () {
    final engine = _one(Archetype.regularCustomer, payment: [1000])
      ..stepToSeconds(40);
    expect(engine.passenger('p1').outcome, AlightOutcome.fight);
    expect(engine.result!.tipsPiasters, 0);
  });

  test('a big note paying 20000 on a 700 fare is owed 19300', () {
    final engine = _one(Archetype.bigNote, payment: [20000])..stepTo(1023);
    expect(engine.passenger('p1').balance, 19300);
  });

  test("a student's discount applies to their fare: 850 at 50% is 450", () {
    final engine = _one(
      Archetype.student,
      payment: [1000],
      fare: 850,
      studentDiscountPct: 50,
    )..stepTo(1023);
    expect(engine.passenger('p1').farePiasters, 450);
    expect(engine.passenger('p1').balance, 550);
  });
}
