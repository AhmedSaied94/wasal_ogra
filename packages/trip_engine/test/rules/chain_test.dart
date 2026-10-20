// The passing chain (rules.md §5.1–§5.5, §5.8): routing, hop length,
// blocking, and tokens of a passenger who gets off.
import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/builders.dart';
import '../support/edits.dart';
import '../support/scripts.dart';

/// One column, rows front to D: front_r, A_r, B_r, C_r, D_r.
List<Seat> _column() => [
  for (final (row, name) in [
    (SeatRow.front, 'front'),
    (SeatRow.a, 'A'),
    (SeatRow.b, 'B'),
    (SeatRow.c, 'C'),
    (SeatRow.d, 'D'),
  ])
    Seat(
      seatId: '${name}_r',
      row: row,
      col: SeatCol.r,
      reachableByDriver: row == SeatRow.front || row == SeatRow.a,
    ),
];

/// The hops of token [tokenId] in [events], as `from>to`.
List<String> _hops(List<DomainEvent> events, int tokenId) => [
  for (final hop in eventsOf<TokenHopStarted>(events))
    if (hop.tokenId == tokenId) '${hop.from.wire}>${hop.to.wire}',
];

void main() {
  group('routing toward the driver', () {
    test('from row D, through each occupied seat ahead, skipping empty C', () {
      final engine = startTrip(
        (TripBuilder()
              ..seats(_column())
              ..station('gamaa', 60)
              ..passenger(
                'pD',
                seat: 'D_r',
                dest: 'gamaa',
                payment: [1000],
                paysAt: 0,
              )
              ..passenger('pB', seat: 'B_r', dest: 'gamaa', payment: [1000])
              ..passenger('pA', seat: 'A_r', dest: 'gamaa', payment: [1000])
              ..passenger(
                'pF',
                seat: 'front_r',
                dest: 'gamaa',
                payment: [1000],
              ))
            .build(),
      );
      final events = engine.stepToSeconds(10);
      expect(_hops(events, 1), ['pD>pB', 'pB>pA', 'pA>DRIVER']);
      expect(eventsOf<MoneyArrivedAtDriver>(events).single.tokenId, 1);
      expect(engine.state.tray.count(1000), 1);
    });

    test('rows front and A hand straight to the driver', () {
      final engine = startTrip(
        (TripBuilder()
              ..seats(_column())
              ..station('gamaa', 60)
              ..passenger(
                'pF',
                seat: 'front_r',
                dest: 'gamaa',
                payment: [1000],
                paysAt: 0,
              )
              ..passenger(
                'pA',
                seat: 'A_r',
                dest: 'gamaa',
                payment: [1000],
                paysAt: 0,
              ))
            .build(),
      );
      final events = engine.stepToSeconds(5);
      expect(_hops(events, 1), ['pF>DRIVER']);
      expect(_hops(events, 2), ['pA>DRIVER']);
    });

    test('with every seat ahead empty, row C hands to the driver', () {
      final engine = startTrip(
        (TripBuilder()
              ..station('gamaa', 60)
              ..passenger(
                'p1',
                seat: 'C_m',
                dest: 'gamaa',
                payment: [1000],
                paysAt: 0,
              )
              ..passenger('p2', seat: 'B_r', dest: 'gamaa', payment: [1000]))
            .build(),
      );
      expect(_hops(engine.stepToSeconds(5), 1), ['p1>DRIVER']);
    });
  });

  group('routing toward a passenger', () {
    test('from the driver, through each occupied seat of their column', () {
      final engine = startTrip(
        (TripBuilder()
              ..seats(_column())
              ..station('gamaa', 60)
              ..passenger('pD', seat: 'D_r', dest: 'gamaa', payment: [1000])
              ..passenger('pB', seat: 'B_r', dest: 'gamaa', payment: [1000])
              ..passenger('pA', seat: 'A_r', dest: 'gamaa', payment: [1000]))
            .build(),
      );
      engine
        ..ok(const PickFromTray(100))
        ..ok(const SendHand('pD'));
      expect(_hops(engine.stepToSeconds(10), 1), [
        'DRIVER>pA',
        'pA>pB',
        'pB>pD',
      ]);
    });

    test('rows front and A are one hop from the driver', () {
      final engine = startTrip(
        (TripBuilder()
              ..station('gamaa', 60)
              ..passenger('p1', seat: 'front_r', dest: 'gamaa', payment: [1000])
              ..passenger('p2', seat: 'A_m', dest: 'gamaa', payment: [1000]))
            .build(),
      );
      engine
        ..ok(const PickFromTray(100))
        ..ok(const SendHand('p1'))
        ..ok(const PickFromTray(100))
        ..ok(const SendHand('p2'));
      final events = engine.stepToSeconds(5);
      expect(_hops(events, 1), ['DRIVER>p1']);
      expect(_hops(events, 2), ['DRIVER>p2']);
    });
  });

  group('the next holder is worked out at each hop', () {
    TripBuilder trip({required String middle}) => TripBuilder()
      ..station('kobri', 3)
      ..station('gamaa', 60)
      ..passenger('p1', seat: 'C_r', dest: 'gamaa', payment: [1000])
      ..passenger('p2', seat: 'A_r', dest: 'gamaa', payment: [1000])
      ..passenger(
        'p3',
        seat: 'B_r',
        dest: middle == 'boards' ? 'gamaa' : 'kobri',
        board: middle == 'boards' ? 'kobri' : null,
        payment: [1000],
      );

    List<String> sendAt1980(TripBuilder builder) {
      final engine = startTrip(builder.build())..stepTo(1980);
      engine
        ..ok(const PickFromTray(100))
        ..ok(const SendHand('p1'));
      return _hops(engine.stepToSeconds(8), 1);
    }

    test('a seat that fills mid-transit joins the chain', () {
      expect(sendAt1980(trip(middle: 'boards')), [
        'DRIVER>p2',
        'p2>p3',
        'p3>p1',
      ]);
    });

    test('a seat that empties mid-transit leaves it', () {
      expect(sendAt1980(trip(middle: 'leaves')), ['DRIVER>p2', 'p2>p1']);
    });
  });

  test('a 1300 ms hop takes 40 steps', () {
    final engine = startTrip(
      (TripBuilder(vehicle: VehicleId.tuktuk, line: LineId.lineHay)
            ..station('madrasa', 30)
            ..passenger(
              'p1',
              seat: 'A_r',
              dest: 'madrasa',
              payment: [1000],
              paysAt: 0,
            ))
          .build(),
    );
    final started = eventsOf<TokenHopStarted>(engine.step()).single;
    expect((started.tMs, started.durationMs), (33, 1300));
    expect(
      eventsOf<MoneyArrivedAtDriver>(engine.stepTo(33 + 39 * 33)),
      isEmpty,
    );
    final arrived = eventsOf<MoneyArrivedAtDriver>(engine.step()).single;
    expect(arrived.tMs, 33 + 40 * 33);
  });

  test('progress is reported in permille while hopping', () {
    final engine = startTrip(
      (TripBuilder()
            ..station('gamaa', 60)
            ..passenger(
              'p1',
              seat: 'A_r',
              dest: 'gamaa',
              payment: [1000],
              paysAt: 0,
            ))
          .build(),
    )..stepTo(33 + 10 * 33);
    expect(engine.state.tokens.single.progressPermille, 330 * 1000 ~/ 1100);
  });

  group('blocking', () {
    TripEngine start() => startTrip(
      (TripBuilder()
            ..station('gamaa', 60)
            ..passenger(
              'p1',
              seat: 'B_r',
              dest: 'gamaa',
              payment: [1000],
              paysAt: 0,
            )
            ..passenger('p2', seat: 'A_r', dest: 'gamaa', payment: [1000]))
          .build(),
    );

    test(
      'an unable next holder blocks, and the hop starts once they are able',
      () {
        final engine = start();
        setAlertness(engine, 'p2', Alertness.asleep);
        final blocked = engine.stepToSeconds(2);
        expect(eventsOf<TokenBlocked>(blocked).map((e) => (e.tokenId, e.by)), [
          (1, 'p2'),
        ]);
        expect(engine.state.tokens.single.blockedBy, 'p2');
        expect(_hops(blocked, 1), isEmpty);
        setAlertness(engine, 'p2', Alertness.awake);
        final moved = engine.step();
        expect(eventsOf<TokenUnblocked>(moved).single.tokenId, 1);
        expect(_hops(moved, 1), ['p1>p2']);
        expect(engine.state.tokens.single.blockedBy, isNull);
      },
    );

    test('an unable holder blocks the token it holds', () {
      // One step before the fare reaches p2; a hop in progress always ends.
      final engine = start()..stepTo(33 + 33 * 33);
      setAlertness(engine, 'p2', Alertness.asleep);
      engine.stepToSeconds(5);
      expect(engine.state.tokens.single.holder, const Holder.passenger('p2'));
      expect(engine.state.tokens.single.blockedBy, 'p2');
      expect(engine.state.tokens.single.hop, isNull);
    });

    test('an unable target blocks its change', () {
      final engine = start();
      setAlertness(engine, 'p2', Alertness.asleep);
      engine
        ..ok(const PickFromTray(100))
        ..ok(const SendHand('p2'));
      final events = engine.stepToSeconds(1);
      expect(
        eventsOf<TokenBlocked>(events).where((e) => e.tokenId == 2).single.by,
        'p2',
      );
    });
  });

  group('a passenger who gets off', () {
    TripBuilder trip() => TripBuilder()
      ..station('kobri', 1)
      ..station('gamaa', 60)
      ..passenger('p1', seat: 'C_r', dest: 'gamaa', payment: [1000], paysAt: 0)
      ..passenger(
        'p2',
        seat: 'B_r',
        dest: 'kobri',
        payment: [500, 100, 100, 100, 50],
        paysAt: 30,
      );

    test('hands the driver what they hold or are about to receive', () {
      final engine = startTrip(trip().build());
      final events = engine.stepTo(1023);
      expect(_hops(events, 1), ['p1>p2']);
      final arrived = eventsOf<MoneyArrivedAtDriver>(events).single;
      expect(
        (arrived.tMs, arrived.tokenId, arrived.amountPiasters),
        (1023, 1, 1000),
      );
      expect(engine.passenger('p1').paidIn, 1000);
      expect(engine.state.tokens, isEmpty);
      expect(engine.state.tray.count(1000), 1);
    });

    test('sends the tokens addressed to them back to the tray', () {
      final engine = startTrip(
        (trip()..passenger('p3', seat: 'A_l', dest: 'gamaa', payment: [1000]))
            .build(),
      );
      final tray = engine.state.tray;
      engine
        ..ok(const PickFromTray(100))
        ..ok(const SendHand('p2'))
        ..stepTo(1023);
      expect(
        engine.state.tokens.where((t) => t.kind == TokenKind.change),
        isEmpty,
      );
      expect(
        engine.state.tray.plus(engine.state.hand).count(100),
        tray.count(100),
      );
    });
  });
}
