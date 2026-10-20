// Abandoning and pausing (rules.md §4, §4.13, FR-054).
import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/builders.dart';
import '../support/edits.dart';
import '../support/scripts.dart';

TripEngine _trip() => startTrip(
  (TripBuilder()
        ..station('gamaa', 30)
        ..passenger(
          'p1',
          seat: 'A_r',
          dest: 'gamaa',
          payment: [1000],
          paysAt: 1,
        ))
      .build(),
)..stepToSeconds(3);

void _expectAbandoned(TripEngine engine, List<DomainEvent> events) {
  final result = eventsOf<TripAbandoned>(events).single.result;
  expect(result.toJson(), engine.result!.toJson());
  expect(engine.status, TripStatus.abandoned);
  expect(result.outcome, TripOutcome.abandoned);
  expect((result.stars, result.earningsJenehat), (0, 0));
}

void main() {
  test('abandoning a running trip', () {
    final engine = _trip();
    _expectAbandoned(engine, engine.ok(const Abandon()));
  });

  test('abandoning a paused trip', () {
    final engine = _trip()..pause();
    _expectAbandoned(engine, engine.ok(const Abandon()));
  });

  test('abandoning a failed trip', () {
    final engine = _trip();
    setReputation(engine, 0);
    engine.step();
    expect(engine.status, TripStatus.failed);
    _expectAbandoned(engine, engine.ok(const Abandon()));
  });

  test('commands after the end are wrong_status', () {
    final abandoned = _trip()..ok(const Abandon());
    abandoned
      ..rejects(const Abandon(), RejectionCode.wrongStatus)
      ..rejects(const PickFromTray(100), RejectionCode.wrongStatus);
    final finished = _trip()..stepToSeconds(40);
    expect(finished.status, TripStatus.finished);
    finished
      ..rejects(const Abandon(), RejectionCode.wrongStatus)
      ..rejects(
        const UseBooster(BoosterId.changeBag),
        RejectionCode.wrongStatus,
      );
  });

  test('while paused only choices, boosters and Abandon are accepted', () {
    final engine = _trip()
      ..ok(const PickFromTray(100))
      ..pause();
    for (final command in const <Command>[
      PickFromTray(100),
      ReturnHand(),
      SendHand('p1'),
      UndoLastSend(),
      Tap('p1'),
      RequestBreak(1000),
      CollectDropped(1),
      Revive(),
    ]) {
      engine.rejects(command, RejectionCode.wrongStatus);
    }
    engine
      ..rejects(const ResolveClaim('p1', insist: true), RejectionCode.noChoice)
      ..rejects(const ResolveDispute(0, 'p1'), RejectionCode.noChoice)
      ..rejects(
        const ResolveChangeRequest('p1', agree: true),
        RejectionCode.noChoice,
      )
      ..ok(const UseBooster(BoosterId.changeBag))
      ..ok(const Abandon());
  });

  test('pause and resume are never logged and change only the status', () {
    final engine = _trip();
    final before = engine.state.toJson();
    engine
      ..pause()
      ..resume();
    expect(engine.state.toJson(), before);
    expect(engine.commandLog, isEmpty);
  });
}
