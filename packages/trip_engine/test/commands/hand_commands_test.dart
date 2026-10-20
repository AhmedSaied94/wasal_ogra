// PickFromTray, ReturnHand and SendHand (rules.md §4.1–§4.3).
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/builders.dart';
import '../support/scripts.dart';

TripEngine _trip() => startTrip(
  (TripBuilder()
        ..tray({100: 2, 50: 1})
        ..station('kobri', 1)
        ..station('gamaa', 60)
        ..passenger('p1', seat: 'A_r', dest: 'gamaa', payment: [1000])
        ..passenger(
          'p2',
          seat: 'A_m',
          dest: 'gamaa',
          board: 'kobri',
          payment: [1000],
        )
        ..passenger('p3', seat: 'A_l', dest: 'kobri', payment: [1000]))
      .build(),
);

void main() {
  group('PickFromTray', () {
    test('moves one piece from the tray to the hand', () {
      final engine = _trip();
      expect(engine.ok(const PickFromTray(100)), isEmpty);
      expect(engine.state.tray.toJson(), {'50': 1, '100': 1});
      expect(engine.state.hand.toJson(), {'100': 1});
    });

    test(
      'is rejected for a denomination the tray lacks, or that does not exist',
      () {
        final engine = _trip();
        engine.rejects(const PickFromTray(500), RejectionCode.trayEmpty);
        engine.rejects(const PickFromTray(300), RejectionCode.badArgument);
        engine
          ..ok(const PickFromTray(50))
          ..rejects(const PickFromTray(50), RejectionCode.trayEmpty);
      },
    );
  });

  group('ReturnHand', () {
    test('puts the whole hand back', () {
      final engine = _trip()
        ..ok(const PickFromTray(100))
        ..ok(const PickFromTray(50))
        ..ok(const ReturnHand());
      expect(engine.state.hand.isEmpty, isTrue);
      expect(engine.state.tray.toJson(), {'50': 1, '100': 2});
    });

    test('is rejected with an empty hand', () {
      _trip().rejects(const ReturnHand(), RejectionCode.handEmpty);
    });
  });

  group('SendHand', () {
    test('creates a change token from the driver and clears the hand', () {
      final engine = _trip()
        ..stepTo(330)
        ..ok(const PickFromTray(100))
        ..ok(const PickFromTray(50));
      final events = engine.ok(const SendHand('p1'));
      final token = engine.state.tokens.single;
      expect(token.toJson(), {
        'token_id': 1,
        'kind': 'change',
        'pieces': {'50': 1, '100': 1},
        'owner': 'p1',
        'target': 'p1',
        'holder': 'DRIVER',
        'hops_done': 0,
      });
      expect(engine.state.hand.isEmpty, isTrue);
      final sent = eventsOf<ChangeSent>(events).single;
      expect(
        (sent.passengerId, sent.tokenId, sent.amountPiasters),
        ('p1', 1, 150),
      );
      expect(engine.state.lastSend!.toJson(), {
        'token_id': 1,
        'until_ms': 1330,
      });
    });

    test('is rejected with an empty hand', () {
      _trip().rejects(const SendHand('p1'), RejectionCode.handEmpty);
    });

    test('is rejected for a passenger who is not aboard', () {
      final engine = _trip()..ok(const PickFromTray(100));
      engine.rejects(const SendHand('p2'), RejectionCode.notAboard);
      engine.rejects(const SendHand('p9'), RejectionCode.notAboard);
      engine.stepToSeconds(2);
      expect(engine.passenger('p3').presence, Presence.gone);
      engine.rejects(const SendHand('p3'), RejectionCode.notAboard);
    });
  });

  test('rejected commands are not logged, accepted ones are', () {
    final engine = _trip();
    engine.rejects(const ReturnHand(), RejectionCode.handEmpty);
    engine.rejects(const PickFromTray(500), RejectionCode.trayEmpty);
    engine
      ..ok(const PickFromTray(100))
      ..ok(const SendHand('p1'));
    expect(engine.commandLog.map((entry) => entry.toJson()), [
      [0, 'PickFromTray', 100],
      [0, 'SendHand', 'p1'],
    ]);
  });
}
