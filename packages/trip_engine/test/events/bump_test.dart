// The bump (rules.md §8, §5.7, §3 step 2.5): every mid-hop token falls to
// the floor for trip_bump_collect_ms (3 s). line_gamaa: p1 in A_r pays 1000
// at 1 s; the fare hops from 1023 to 2145.
import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/builders.dart';
import '../support/scripts.dart';

TripEngine _trip(
  int bumpAt, {
  Archetype archetype = Archetype.regular,
  int station = 30,
}) => startTrip(
  (TripBuilder()
        ..station('gamaa', station)
        ..passenger(
          'p1',
          seat: 'A_r',
          dest: 'gamaa',
          payment: [1000],
          paysAt: 1,
          archetype: archetype,
        )
        ..event(EventId.bump, bumpAt))
      .build(),
);

// Sends [pieces] to p1 once the fare is in, at 2145; the change hops from
// 2178 to 3300.
void _sendChange(TripEngine engine, List<int> pieces) {
  engine.stepTo(2145);
  for (final piece in pieces) {
    engine.ok(PickFromTray(piece));
  }
  engine.ok(const SendHand('p1'));
}

void main() {
  test('only mid-hop tokens drop', () {
    final engine = _trip(2);
    final bump = engine.stepTo(2013);
    expect(eventsOf<EventStarted>(bump).single.eventId, EventId.bump);
    expect(eventsOf<MoneyDropped>(bump).single.tokenId, 1);
    final token = engine.state.token(1)!;
    expect(
      (token.isDropped, token.hop, token.droppedUntilMs),
      (true, null, 5013),
    );
  });

  test('a held token stays where it is', () {
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
              seat: 'B_r',
              dest: 'gamaa',
              payment: [500, 100, 100],
              archetype: Archetype.sleeper,
            )
            ..event(EventId.bump, 2))
          .build(),
    );
    expect(eventsOf<MoneyDropped>(engine.stepToSeconds(3)), isEmpty);
    expect(engine.state.token(1)!.blockedBy, 'p2');
  });

  group('collected in time', () {
    test('a fare arrives at the driver', () {
      final engine = _trip(2)..stepToSeconds(3);
      final collect = engine.ok(const CollectDropped(1));
      expect(eventsOf<DroppedCollected>(collect).single.tokenId, 1);
      expect(
        eventsOf<MoneyArrivedAtDriver>(collect).single.kind,
        TokenKind.fare,
      );
      expect(engine.passenger('p1').paidIn, 1000);
      expect(engine.state.token(1), isNull);
    });

    test('change goes to the tray, and the passenger is still owed', () {
      final engine = _trip(3);
      _sendChange(engine, [100, 100, 100]);
      final tray = engine.stepToSeconds(4).isEmpty
          ? 0
          : engine.state.tray.total;
      engine.ok(const CollectDropped(2));
      expect(engine.state.tray.total, tray + 300);
      expect(engine.passenger('p1').balance, 300);
    });

    test("an honest passenger's return goes to the tray", () {
      final engine = _trip(4, archetype: Archetype.honest);
      _sendChange(engine, [500]);
      engine.stepToSeconds(5);
      expect(engine.state.token(3)!.kind, TokenKind.returned);
      final tray = engine.state.tray.total;
      engine.ok(const CollectDropped(3));
      expect(engine.state.tray.total, tray + 200);
      engine.stepToSeconds(40);
      expect(engine.result!.overpaidPiasters, 0);
    });
  });

  group('lost after the deadline', () {
    test('a lost fare never counts, but its balance stands', () {
      final engine = _trip(2);
      final events = engine.stepTo(5016);
      expect(eventsOf<DroppedLost>(events).single.tMs, 5016);
      final p1 = engine.passenger('p1');
      expect((p1.fareSent, p1.balance, p1.paidIn), (true, 300, 0));
      engine.stepToSeconds(40);
      expect(engine.result!.faresCollectedPiasters, 0);
    });

    test('a lost return is overpaid', () {
      final engine = _trip(4, archetype: Archetype.honest);
      _sendChange(engine, [500]);
      expect(eventsOf<DroppedLost>(engine.stepTo(7029)), hasLength(1));
      engine.stepToSeconds(40);
      expect(engine.result!.overpaidPiasters, 200);
    });

    test('lost change is gone, and the passenger is still owed', () {
      final engine = _trip(3);
      _sendChange(engine, [100, 100, 100]);
      final tray = engine.state.tray.total;
      expect(eventsOf<DroppedLost>(engine.stepTo(6006)), hasLength(1));
      expect(engine.state.tray.total, tray);
      expect(engine.passenger('p1').balance, 300);
    });
  });

  test('CollectDropped on a token that is not dropped has no effect', () {
    final engine = _trip(20)..stepTo(1023);
    engine
      ..rejects(const CollectDropped(1), RejectionCode.noEffect)
      ..rejects(const CollectDropped(9), RejectionCode.noEffect);
  });

  test('a dropped token at the end of the trip is lost', () {
    final engine = _trip(2, station: 4);
    final events = engine.stepToSeconds(10);
    expect(engine.status, TripStatus.finished);
    expect(eventsOf<DroppedLost>(events).single.tMs, engine.result!.durationMs);
    expect(engine.state.tokens, isEmpty);
  });
}
