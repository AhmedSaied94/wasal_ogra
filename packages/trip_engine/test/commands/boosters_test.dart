// The four in-trip boosters (rules.md §3 step 2.4, §4.11).
import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/builders.dart';
import '../support/default_params.dart';
import '../support/scripts.dart';

TripBuilder _trip() => TripBuilder()
  ..station('kobri', 30)
  ..station('gamaa', 50)
  ..passenger(
    'p1',
    seat: 'A_r',
    dest: 'gamaa',
    payment: [500, 100, 100],
    paysAt: 1,
  );

void main() {
  test('change_bag adds 50×2, 100×3 and 500×2', () {
    final engine = startTrip(_trip().build());
    final before = engine.state.tray;
    final events = engine.ok(const UseBooster(BoosterId.changeBag));
    expect(eventsOf<BoosterUsed>(events).single.boosterId, BoosterId.changeBag);
    final after = engine.state.tray;
    expect(
      [
        for (final d in [50, 100, 500]) after.count(d) - before.count(d),
      ],
      [2, 3, 2],
    );
    expect(engine.state.boostersUsed, [BoosterId.changeBag]);
  });

  test('wake_all wakes every asleep or waking sleeper at once', () {
    final engine = startTrip(
      (_trip()
            ..passenger(
              'p2',
              seat: 'A_m',
              dest: 'gamaa',
              payment: [1000],
              archetype: Archetype.sleeper,
            )
            ..passenger(
              'p3',
              seat: 'A_l',
              dest: 'gamaa',
              payment: [1000],
              archetype: Archetype.sleeper,
            ))
          .build(),
    )..ok(const Tap('p3'));
    expect(engine.passenger('p3').alertness, Alertness.waking);
    final events = engine.ok(const UseBooster(BoosterId.wakeAll));
    expect(eventsOf<PassengerWoke>(events).map((e) => e.passengerId), [
      'p2',
      'p3',
    ]);
    expect(spoken(events, 'p2'), [SpeechSlot.woke]);
    for (final id in ['p2', 'p3']) {
      final state = engine.passenger(id);
      expect((state.alertness, state.alertUntilMs), (Alertness.awake, 15000));
    }
  });

  test('ledger_peek lasts booster_ledger_peek_ms', () {
    final engine = startTrip(_trip().build())..stepTo(990);
    final events = engine.ok(const UseBooster(BoosterId.ledgerPeek));
    expect(eventsOf<LedgerPeekStarted>(events).single.untilMs, 10990);
    expect(engine.state.ledgerPeekActive, isTrue);
    expect(eventsOf<LedgerPeekEnded>(engine.stepTo(10989)), isEmpty);
    expect(engine.state.ledgerPeekActive, isTrue);
    final ended = engine.step();
    expect(eventsOf<LedgerPeekEnded>(ended).single.tMs, 11022);
    expect(engine.state.ledgerPeekUntilMs, isNull);
    expect(engine.state.ledgerPeekActive, isFalse);
  });

  test('traffic_jam shifts the schedule by booster_traffic_jam_ms', () {
    final engine = startTrip(_trip().build())..stepToSeconds(5);
    final events = engine.ok(const UseBooster(BoosterId.trafficJam));
    expect(eventsOf<ScheduleShifted>(events).single.deltaMs, 10000);
    expect([for (final s in engine.state.schedule) s.atMs], [40000, 60000]);
  });

  test('a fourth traffic_jam is booster_limit at the default of 3', () {
    final engine = startTrip(_trip().build());
    for (var i = 0; i < 3; i++) {
      engine.ok(const UseBooster(BoosterId.trafficJam));
    }
    engine.rejects(
      const UseBooster(BoosterId.trafficJam),
      RejectionCode.boosterLimit,
    );
    expect(engine.state.boostersUsed, hasLength(3));
  });

  test('a limit of 0 rejects the first traffic_jam', () {
    startTrip(
      _trip().build(),
      params: paramsWith({'booster_traffic_jam_max_per_trip': 0}),
    ).rejects(
      const UseBooster(BoosterId.trafficJam),
      RejectionCode.boosterLimit,
    );
  });

  for (final booster in [
    BoosterId.revive,
    BoosterId.refuelFull,
    BoosterId.fuelUnlimited1h,
  ]) {
    test('${booster.name} is not an in-trip booster', () {
      startTrip(_trip().build())
          .rejects(UseBooster(booster), RejectionCode.badArgument);
    });
  }

  test('every use is recorded, and boosters work while paused', () {
    final engine = startTrip(_trip().build())
      ..ok(const UseBooster(BoosterId.changeBag))
      ..pause()
      ..ok(const UseBooster(BoosterId.ledgerPeek))
      ..ok(const UseBooster(BoosterId.changeBag));
    expect(engine.status, TripStatus.paused);
    expect(engine.state.boostersUsed, [
      BoosterId.changeBag,
      BoosterId.ledgerPeek,
      BoosterId.changeBag,
    ]);
    engine
      ..resume()
      ..stepToSeconds(60);
    expect(engine.result!.boostersUsed, hasLength(3));
  });
}
