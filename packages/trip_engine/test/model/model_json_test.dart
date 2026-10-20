// The state and result types: canonical snake_case JSON, integers only,
// absent optionals left out, and unmodifiable collections (data-model.md).
import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/src/model/token.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/builders.dart';
import '../support/scripts.dart';

const _stateKeys = {
  't_ms',
  'status',
  'reputation',
  'tray',
  'hand',
  'passengers',
  'tokens',
  'next_token_id',
  'schedule',
  'next_station',
  'events_fired',
  'fare_increase_piasters',
  'old_fare_payers',
  'traffic_active',
  'claims',
  'disputes',
  'change_requests',
  'pending_breaks',
  'breaks_used',
  'counters',
  'mistakes',
  'reputation_lost',
  'boosters_used',
  'revived',
  'revivable',
  'commands_accepted',
  'prng',
};

const _passengerKeys = {
  'passenger_id',
  'presence',
  'seat_id',
  'alertness',
  'taps',
  'fare_sent',
  'balance',
  'paid_in',
  'half_patience_spoken',
  'impatient',
  'claim_resolved',
  'never_pays',
  'pickup_due',
};

final _result = <String, Object>{
  'trip_id': 'line_hay.01',
  'rev': 1,
  'outcome': 'finished',
  'stars': 2,
  'star_flags': {'reached': true, 'no_fights': true, 'no_mistakes': false},
  'fares_collected_piasters': 1400,
  'overpaid_piasters': 50,
  'tips_piasters': 200,
  'earnings_jenehat': 15,
  'fights': 0,
  'lost_fares': 0,
  'missed_stops': 0,
  'impatient': 1,
  'caught_liars': 0,
  'mistakes': [
    {'passenger_id': 'p1', 'kind': 'over', 'amount_piasters': 50},
  ],
  'reputation': 92,
  'reputation_lost': {'impatient': 5},
  'duration_ms': 55011,
  'boosters_used': ['change_bag', 'wake_all'],
  'revived': false,
  'command_log_hash':
      '4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',
};

void _expectIntegersOnly(Object? json, String path) {
  switch (json) {
    case double():
      fail('$path is a double');
    case Map<Object?, Object?>():
      for (final MapEntry(:key, :value) in json.entries) {
        expect(key, isA<String>(), reason: path);
        _expectIntegersOnly(value, '$path.$key');
      }
    case List<Object?>():
      for (final (index, item) in json.indexed) {
        _expectIntegersOnly(item, '$path[$index]');
      }
    case null:
      fail('$path is null: absent optionals are left out');
    default:
  }
}

void main() {
  final definition =
      (TripBuilder()
            ..station('kobri', 30, fare: 850)
            ..station('gamaa', 60, fare: 900)
            ..passenger(
              'p1',
              seat: 'A_r',
              dest: 'kobri',
              payment: [1000],
              paysAt: 2,
            )
            ..passenger(
              'p2',
              seat: 'B_m',
              dest: 'gamaa',
              payment: [1000],
              board: 'kobri',
            ))
          .build();

  test('a starting state has the data-model keys, and no absent optionals', () {
    final state = startTrip(definition).state;
    final json = state.toJson();
    expect(json.keys.toSet(), _stateKeys);
    _expectIntegersOnly(json, r'$');
    final passengers = json['passengers']! as List<Object?>;
    expect(
      (passengers.first! as Map<String, Object?>).keys.toSet(),
      _passengerKeys,
    );
    expect(json['schedule'], [
      {
        'station_id': 'kobri',
        'at_ms': 30000,
        'fare_piasters': 850,
        'warned': false,
      },
      {
        'station_id': 'gamaa',
        'at_ms': 60000,
        'fare_piasters': 900,
        'warned': false,
      },
    ]);
    expect(json['counters'], {
      'fights': 0,
      'lost_fares': 0,
      'missed_stops': 0,
      'impatient': 0,
      'caught_liars': 0,
      'tips_piasters': 0,
      'overpaid_piasters': 0,
    });
    expect(json['tray'], {'100': 4, '50': 4, '500': 2});
    expect(json['status'], 'running');
    expect(json['prng'], 1);
  });

  test('state collections are unmodifiable', () {
    final state = startTrip(definition).state;
    expect(
      () => state.passengers.add(state.passengers.first),
      throwsUnsupportedError,
    );
    expect(() => state.tokens.clear(), throwsUnsupportedError);
    expect(() => state.schedule.clear(), throwsUnsupportedError);
    expect(() => state.eventsFired.clear(), throwsUnsupportedError);
    expect(() => state.oldFarePayers.add('p1'), throwsUnsupportedError);
    expect(() => state.claims.clear(), throwsUnsupportedError);
    expect(() => state.disputes.clear(), throwsUnsupportedError);
    expect(() => state.changeRequests.clear(), throwsUnsupportedError);
    expect(() => state.pendingBreaks.clear(), throwsUnsupportedError);
    expect(() => state.mistakes.clear(), throwsUnsupportedError);
    expect(() => state.reputationLost.clear(), throwsUnsupportedError);
    expect(() => state.boostersUsed.clear(), throwsUnsupportedError);
    expect(() => state.tray.counts[50] = 9, throwsUnsupportedError);
  });

  test('the getters M02 reads', () {
    final state = startTrip(definition).state;
    expect(state.ledgerPeekActive, isFalse);
    expect(state.undoAvailableUntilMs, isNull);
    expect(state.nextStation!.stationId, 'kobri');
    expect(state.breaksLeft, 2);
    expect(state.passenger('p1')!.isAble, isTrue);
    expect(state.passenger('p1')!.isOwed, isFalse);
    expect(state.passenger('p1')!.patiencePermille, isNull);
    expect(state.passenger('p2')!.presence, Presence.waiting);
    expect(state.passenger('p9'), isNull);
  });

  test('a token has its keys, with the hop and drop fields only when set', () {
    final held = makeMoneyToken(
      tokenId: 3,
      kind: TokenKind.breakOut,
      pieces: Pieces({500: 1}),
      owner: 'p1',
      target: Holder.passenger('p1'),
      holder: Holder.driver,
    );
    expect(held.toJson(), {
      'token_id': 3,
      'kind': 'break_out',
      'pieces': {'500': 1},
      'owner': 'p1',
      'target': 'p1',
      'holder': 'DRIVER',
      'hops_done': 0,
    });
    expect(held.progressPermille, isNull);
    final hopping = held.copyWith(
      hop: const Hop(to: Holder.driver, elapsedMs: 330, durationMs: 1100),
    );
    expect(hopping.toJson()['hop'], {
      'to': 'DRIVER',
      'elapsed_ms': 330,
      'duration_ms': 1100,
    });
    expect(hopping.progressPermille, 300);
    expect(Holder.driver.isDriver, isTrue);
    expect(Holder.passenger('p4').passengerId, 'p4');
  });

  test('the choice and record types', () {
    expect(const Claim(truthful: true).toJson(), {'truthful': true});
    expect(const Dispute(a: 'p1', b: 'p2').toJson(), {'a': 'p1', 'b': 'p2'});
    expect(const ChangeRequest(notePiasters: 5000).toJson(), {
      'note_piasters': 5000,
    });
    expect(
      const PendingBreak(denomination: 1000, completesAtMs: 1533).toJson(),
      {'denomination': 1000, 'completes_at_ms': 1533},
    );
    expect(const LastSend(tokenId: 2, untilMs: 1330).toJson(), {
      'token_id': 2,
      'until_ms': 1330,
    });
    expect(
      const Mistake(
        passengerId: 'p1',
        kind: MistakeKind.notOwed,
        amountPiasters: 100,
      ).toJson(),
      {'passenger_id': 'p1', 'kind': 'not_owed', 'amount_piasters': 100},
    );
  });

  test('TripResult round-trips through JSON', () {
    final result = TripResult.fromJson(_result);
    expect(result.toJson(), _result);
    expect(result.outcome, TripOutcome.finished);
    expect(result.boostersUsed, [BoosterId.changeBag, BoosterId.wakeAll]);
    expect(result.reputationLost, {RepCause.impatient: 5});
    expect(() => result.mistakes.clear(), throwsUnsupportedError);
    expect(() => result.boostersUsed.clear(), throwsUnsupportedError);
    expect(() => result.reputationLost.clear(), throwsUnsupportedError);
  });

  test('TripResult.fromJson refuses malformed input', () {
    for (final change in <void Function(Map<String, Object?>)>[
      (json) => json.remove('stars'),
      (json) => json['outcome'] = 'won',
      (json) => json['stars'] = '3',
      (json) => json['boosters_used'] = ['rocket'],
      (json) => json['reputation_lost'] = {'luck': 1},
      (json) => json['mistakes'] = [
        {'passenger_id': 'p1'},
      ],
      (json) => json['extra'] = 1,
    ]) {
      final json = Map<String, Object?>.of(_result);
      change(json);
      expect(() => TripResult.fromJson(json), throwsFormatException);
    }
  });
}
