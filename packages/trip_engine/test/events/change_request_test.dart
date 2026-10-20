// change_request (rules.md §4.8, §5.5, §5.7, §14.4): a passenger asks the
// driver to break a note. Default tray: 100×4, 50×4, 500×2.
import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/builders.dart';
import '../support/scripts.dart';

TripEngine _trip({Map<int, int>? tray, int? bumpAt}) {
  final builder = TripBuilder()
    ..station('gamaa', 30)
    ..passenger(
      'p1',
      seat: 'A_r',
      dest: 'gamaa',
      payment: [500, 100, 100],
      paysAt: 1,
    )
    ..event(EventId.changeRequest, 5, passengers: ['p1'], amount: 1000);
  if (tray != null) builder.tray(tray);
  if (bumpAt != null) builder.event(EventId.bump, bumpAt);
  return startTrip(builder.build())..stepToSeconds(6);
}

void main() {
  test('it opens with the note and a speech', () {
    final engine = startTrip(
      (TripBuilder()
            ..station('gamaa', 30)
            ..passenger(
              'p1',
              seat: 'A_r',
              dest: 'gamaa',
              payment: [500, 100, 100],
            )
            ..event(EventId.changeRequest, 5, passengers: ['p1'], amount: 1000))
          .build(),
    );
    final events = engine.stepToSeconds(6);
    final raised = eventsOf<ChangeRequestRaised>(events).single;
    expect((raised.passengerId, raised.amountPiasters), ('p1', 1000));
    final speech = eventsOf<PassengerSpeaks>(events).single;
    expect(
      (speech.slot, speech.amountPiasters),
      (SpeechSlot.changeRequest, 1000),
    );
  });

  test('agreeing sends the chosen pieces, and the note comes back', () {
    final engine = _trip();
    final tray = engine.state.tray;
    final agree = engine.ok(const ResolveChangeRequest('p1', agree: true));
    expect(eventsOf<ChangeRequestResolved>(agree).single.agreed, isTrue);
    final token = engine.state.tokens.single;
    expect(token.kind, TokenKind.breakOut);
    expect(token.pieces.toJson(), {'500': 2});
    expect(engine.state.tray.count(500), tray.count(500) - 2);
    final later = engine.stepToSeconds(12);
    expect(eventsOf<ChangeRequestCompleted>(later).single.passengerId, 'p1');
    expect(engine.state.tray.count(1000), tray.count(1000) + 1);
    expect(engine.state.tray.total, tray.total);
    expect(engine.state.changeRequests, isEmpty);
  });

  test('without the pieces it is cannot_make_change, and stays open', () {
    // With the fare in, the tray holds 500, 100×2 and 50: 750.
    final engine = _trip(tray: {50: 1});
    engine.rejects(
      const ResolveChangeRequest('p1', agree: true),
      RejectionCode.cannotMakeChange,
    );
    expect(engine.state.changeRequests.keys, ['p1']);
  });

  test('declining costs reputation, with a speech', () {
    final engine = _trip();
    final decline = engine.ok(const ResolveChangeRequest('p1', agree: false));
    final drop = eventsOf<ReputationChanged>(decline).single;
    expect(
      (drop.cause, drop.delta),
      (RepCause.changeRequestDeclined, -engine.params.repChangeRequestDeclined),
    );
    expect(spoken(decline, 'p1'), [SpeechSlot.changeRequestDeclined]);
    expect(eventsOf<ChangeRequestResolved>(decline).single.agreed, isFalse);
  });

  test('no answer by their stop counts as declined', () {
    final engine = _trip();
    final events = engine.stepToSeconds(40);
    final drop = eventsOf<ReputationChanged>(events).single;
    expect(drop.cause, RepCause.changeRequestDeclined);
    expect(drop.tMs, 30030);
    expect(eventsOf<ChangeRequestResolved>(events).single.agreed, isFalse);
  });

  test('a lost break_out cancels the exchange with no penalty', () {
    // Agreed at 6006, the break_out hops from 6039 to 7161; the bump at 7 s
    // drops it until 10008.
    final engine = _trip(bumpAt: 7);
    final tray = engine.state.tray.total;
    engine.ok(const ResolveChangeRequest('p1', agree: true));
    final events = engine.stepToSeconds(40);
    expect(eventsOf<DroppedLost>(events), hasLength(1));
    expect(eventsOf<ChangeRequestCompleted>(events), isEmpty);
    expect(eventsOf<ReputationChanged>(events), isEmpty);
    expect(engine.state.tray.total, tray - 1000);
  });

  test('a second request while one is open is skipped', () {
    final engine = startTrip(
      (TripBuilder()
            ..station('gamaa', 30)
            ..passenger(
              'p1',
              seat: 'A_r',
              dest: 'gamaa',
              payment: [500, 100, 100],
              paysAt: 1,
            )
            ..event(EventId.changeRequest, 5, passengers: ['p1'], amount: 1000)
            ..event(EventId.changeRequest, 8, passengers: ['p1'], amount: 1000))
          .build(),
    );
    final events = engine.stepToSeconds(9);
    expect(eventsOf<ChangeRequestRaised>(events), hasLength(1));
    expect(eventsOf<EventSkipped>(events).single.index, 1);
    expect(engine.state.changeRequests.keys, ['p1']);
  });
}
