// UndoLastSend (rules.md §4.4): the last send comes back to the hand while
// the undo window lasts and before its first hop ends. p1 pays 1000 at 1 s;
// the fare is in at 2145.
import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/builders.dart';
import '../support/default_params.dart';
import '../support/scripts.dart';

TripEngine _trip({int? undoWindow, List<(EventId, int)> events = const []}) {
  final builder = TripBuilder()
    ..station('gamaa', 30)
    ..passenger('p1', seat: 'A_r', dest: 'gamaa', payment: [1000], paysAt: 1);
  for (final (id, at) in events) {
    builder.event(id, at);
  }
  return startTrip(
    builder.build(),
    params: undoWindow == null
        ? null
        : paramsWith({'trip_undo_window_ms': undoWindow}),
  )..stepTo(2145);
}

void _send(TripEngine engine, List<int> pieces) {
  for (final piece in pieces) {
    engine.ok(PickFromTray(piece));
  }
  engine.ok(const SendHand('p1'));
}

void main() {
  test('within the window it puts the pieces back in the hand', () {
    final engine = _trip();
    _send(engine, [100, 100, 100]);
    final send = engine.state.lastSend!;
    expect(send.untilMs, 2145 + 1000);
    engine.stepTo(2178);
    final undo = engine.ok(const UndoLastSend());
    expect(eventsOf<SendUndone>(undo).single.tokenId, send.tokenId);
    expect(engine.state.hand.total, 300);
    expect(engine.state.token(send.tokenId), isNull);
    expect(engine.state.lastSend, isNull);
    expect(engine.state.undoAvailableUntilMs, isNull);
  });

  test('after the window it is undo_unavailable', () {
    final engine = _trip();
    _send(engine, [100]);
    engine.stepTo(3168);
    engine.rejects(const UndoLastSend(), RejectionCode.undoUnavailable);
  });

  test('after the first hop ends it is undo_unavailable', () {
    // p2 in A_r passes p1's change on, so the send takes two hops.
    final engine = startTrip(
      (TripBuilder()
            ..station('gamaa', 30)
            ..passenger(
              'p1',
              seat: 'C_r',
              dest: 'gamaa',
              payment: [1000],
              paysAt: 1,
            )
            ..passenger(
              'p2',
              seat: 'A_r',
              dest: 'gamaa',
              payment: [500, 100, 100],
            ))
          .build(),
      params: paramsWith({'trip_undo_window_ms': 60000}),
    )..stepToSeconds(5);
    _send(engine, [100]);
    engine.stepTo(engine.state.tMs + 35 * 33);
    expect(engine.state.tokens.single.hopsDone, 1);
    engine.rejects(const UndoLastSend(), RejectionCode.undoUnavailable);
  });

  test('a dropped token cannot be undone', () {
    final engine = _trip(undoWindow: 60000, events: [(EventId.bump, 3)]);
    _send(engine, [100]);
    engine.stepToSeconds(3);
    expect(engine.state.tokens.single.isDropped, isTrue);
    engine.rejects(const UndoLastSend(), RejectionCode.undoUnavailable);
  });

  test('a second undo is undo_unavailable', () {
    final engine = _trip();
    _send(engine, [100]);
    engine.ok(const UndoLastSend());
    engine.rejects(const UndoLastSend(), RejectionCode.undoUnavailable);
  });

  test('only the last send can be undone', () {
    final engine = _trip();
    _send(engine, [100]);
    _send(engine, [100, 100]);
    engine.ok(const UndoLastSend());
    expect(engine.state.hand.total, 200);
    expect(engine.state.tokens.single.pieces.total, 100);
    engine.rejects(const UndoLastSend(), RejectionCode.undoUnavailable);
  });

  test('with nothing sent it is undo_unavailable', () {
    _trip().rejects(const UndoLastSend(), RejectionCode.undoUnavailable);
  });
}
