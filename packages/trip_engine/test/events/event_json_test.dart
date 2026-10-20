// Every domain event's name and JSON keys match the contracts/engine-api.md
// table exactly.
import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

final _result = TripResult.fromJson({
  'trip_id': 'line_hay.01',
  'rev': 1,
  'outcome': 'abandoned',
  'stars': 0,
  'star_flags': {'reached': false, 'no_fights': true, 'no_mistakes': true},
  'fares_collected_piasters': 0,
  'overpaid_piasters': 0,
  'tips_piasters': 0,
  'earnings_jenehat': 0,
  'fights': 0,
  'lost_fares': 0,
  'missed_stops': 0,
  'impatient': 0,
  'caught_liars': 0,
  'mistakes': <Object>[],
  'reputation': 100,
  'reputation_lost': <String, Object>{},
  'duration_ms': 33,
  'boosters_used': <Object>[],
  'revived': false,
  'command_log_hash': 'ab',
});

// The table, as (event, name, payload keys).
final _table = <(DomainEvent, String, Set<String>)>[
  (
    const PassengerBoarded(33, passengerId: 'p1', seatId: 'A_r'),
    'PassengerBoarded',
    {'passenger_id', 'seat_id'},
  ),
  (
    const PassengerSpeaks(
      33,
      passengerId: 'p1',
      slot: SpeechSlot.pays,
      speechKey: 'passenger.pays',
      variant: 9,
      amountPiasters: 1000,
    ),
    'PassengerSpeaks',
    {'passenger_id', 'slot', 'speech_key', 'variant', 'amount_piasters'},
  ),
  (
    const PassengerWaking(33, passengerId: 'p1'),
    'PassengerWaking',
    {'passenger_id'},
  ),
  (
    const PassengerWoke(33, passengerId: 'p1'),
    'PassengerWoke',
    {'passenger_id'},
  ),
  (
    const PassengerFellAsleep(33, passengerId: 'p1'),
    'PassengerFellAsleep',
    {'passenger_id'},
  ),
  (
    const PassengerCalled(33, passengerId: 'p1', taps: 1),
    'PassengerCalled',
    {'passenger_id', 'taps'},
  ),
  (
    const PassengerAttentive(33, passengerId: 'p1'),
    'PassengerAttentive',
    {'passenger_id'},
  ),
  (
    const PassengerMuted(33, passengerId: 'p1'),
    'PassengerMuted',
    {'passenger_id'},
  ),
  (
    const PatienceRanOut(33, passengerId: 'p1'),
    'PatienceRanOut',
    {'passenger_id'},
  ),
  (
    const StopChanged(33, passengerId: 'p1', deadlineMs: 9000),
    'StopChanged',
    {'passenger_id', 'deadline_ms'},
  ),
  (
    const PassengerAlighted(
      33,
      passengerId: 'p1',
      outcome: AlightOutcome.leftUnpaid,
    ),
    'PassengerAlighted',
    {'passenger_id', 'outcome'},
  ),
  (
    const FareSent(33, passengerId: 'p1', tokenId: 1, amountPiasters: 1000),
    'FareSent',
    {'passenger_id', 'token_id', 'amount_piasters'},
  ),
  (
    const ChangeSent(33, passengerId: 'p1', tokenId: 2, amountPiasters: 300),
    'ChangeSent',
    {'passenger_id', 'token_id', 'amount_piasters'},
  ),
  (const SendUndone(33, tokenId: 2), 'SendUndone', {'token_id'}),
  (
    const TokenHopStarted(
      33,
      tokenId: 1,
      from: Holder.driver,
      to: Holder.passenger('p1'),
      durationMs: 1100,
    ),
    'TokenHopStarted',
    {'token_id', 'from', 'to', 'duration_ms'},
  ),
  (
    const TokenBlocked(33, tokenId: 1, by: 'p2'),
    'TokenBlocked',
    {'token_id', 'by'},
  ),
  (const TokenUnblocked(33, tokenId: 1), 'TokenUnblocked', {'token_id'}),
  (
    const MoneyArrivedAtDriver(
      33,
      tokenId: 1,
      kind: TokenKind.fare,
      amountPiasters: 1000,
    ),
    'MoneyArrivedAtDriver',
    {'token_id', 'kind', 'amount_piasters'},
  ),
  (
    const ChangeDelivered(
      33,
      tokenId: 2,
      passengerId: 'p1',
      result: ChangeResult.notOwed,
      amountPiasters: 300,
    ),
    'ChangeDelivered',
    {'token_id', 'passenger_id', 'result', 'amount_piasters'},
  ),
  (
    const ExcessReturned(33, passengerId: 'p1', amountPiasters: 50),
    'ExcessReturned',
    {'passenger_id', 'amount_piasters'},
  ),
  (const MoneyDropped(33, tokenId: 1), 'MoneyDropped', {'token_id'}),
  (const DroppedCollected(33, tokenId: 1), 'DroppedCollected', {'token_id'}),
  (const DroppedLost(33, tokenId: 1), 'DroppedLost', {'token_id'}),
  (
    const BreakRequested(33, denomination: 1000, completesAtMs: 1533),
    'BreakRequested',
    {'denomination', 'completes_at_ms'},
  ),
  (
    BreakCompleted(
      33,
      denomination: 1000,
      pieces: Pieces({500: 1, 100: 4, 50: 2}),
    ),
    'BreakCompleted',
    {'denomination', 'pieces'},
  ),
  (const ClaimRaised(33, passengerId: 'p1'), 'ClaimRaised', {'passenger_id'}),
  (
    const ClaimAccepted(33, passengerId: 'p1'),
    'ClaimAccepted',
    {'passenger_id'},
  ),
  (const LiarCaught(33, passengerId: 'p1'), 'LiarCaught', {'passenger_id'}),
  (
    const FalseAccusation(33, passengerId: 'p1'),
    'FalseAccusation',
    {'passenger_id'},
  ),
  (
    const DisputeRaised(33, disputeId: 2, passengerIds: ['p1', 'p2']),
    'DisputeRaised',
    {'dispute_id', 'passenger_ids'},
  ),
  (
    const DisputeResolved(33, disputeId: 2, right: true),
    'DisputeResolved',
    {'dispute_id', 'right'},
  ),
  (
    const ChangeRequestRaised(33, passengerId: 'p1', amountPiasters: 5000),
    'ChangeRequestRaised',
    {'passenger_id', 'amount_piasters'},
  ),
  (
    const ChangeRequestResolved(33, passengerId: 'p1', agreed: false),
    'ChangeRequestResolved',
    {'passenger_id', 'agreed'},
  ),
  (
    const ChangeRequestCompleted(33, passengerId: 'p1'),
    'ChangeRequestCompleted',
    {'passenger_id'},
  ),
  (
    const EventStarted(33, index: 0, eventId: EventId.bump),
    'EventStarted',
    {'index', 'event_id'},
  ),
  (
    const EventSkipped(33, index: 1, eventId: EventId.dropMeHere),
    'EventSkipped',
    {'index', 'event_id'},
  ),
  (
    const FareIncreased(33, amountPiasters: 100, totalIncreasePiasters: 200),
    'FareIncreased',
    {'amount_piasters', 'total_increase_piasters'},
  ),
  (const ScheduleShifted(33, deltaMs: 10000), 'ScheduleShifted', {'delta_ms'}),
  (
    const StationWarning(
      33,
      stationId: 'kobri',
      atMs: 30000,
      alighting: ['p1'],
      owed: <String>[],
    ),
    'StationWarning',
    {'station_id', 'at_ms', 'alighting', 'owed'},
  ),
  (
    const StationReached(33, stationId: 'kobri'),
    'StationReached',
    {'station_id'},
  ),
  (
    const ReputationChanged(33, delta: -30, cause: RepCause.fight, value: 70),
    'ReputationChanged',
    {'delta', 'cause', 'value'},
  ),
  (
    const MistakeMade(
      33,
      passengerId: 'p1',
      kind: MistakeKind.unreturned,
      amountPiasters: 300,
    ),
    'MistakeMade',
    {'passenger_id', 'kind', 'amount_piasters'},
  ),
  (
    const BoosterUsed(33, boosterId: BoosterId.ledgerPeek),
    'BoosterUsed',
    {'booster_id'},
  ),
  (
    const LedgerPeekStarted(33, untilMs: 10033),
    'LedgerPeekStarted',
    {'until_ms'},
  ),
  (const LedgerPeekEnded(33), 'LedgerPeekEnded', <String>{}),
  (
    const TripFailed(
      33,
      reputationLost: {RepCause.fight: 60, RepCause.missedStop: 45},
      revivable: true,
    ),
    'TripFailed',
    {'reputation_lost', 'revivable'},
  ),
  (const TripRevived(33, reputation: 40), 'TripRevived', {'reputation'}),
  (TripFinished(33, result: _result), 'TripFinished', {'result'}),
  (TripAbandoned(33, result: _result), 'TripAbandoned', {'result'}),
];

void main() {
  test('the table has all 49 events', () {
    expect({for (final (_, name, _) in _table) name}, hasLength(49));
  });

  for (final (event, name, keys) in _table) {
    test(name, () {
      expect(event.name, name);
      expect(event.tMs, 33);
      final json = event.toJson();
      expect(json.keys.toSet(), {'name', 't_ms', ...keys});
      expect(json['name'], name);
      expect(json['t_ms'], 33);
    });
  }

  test('optional speech placeholders are left out when absent', () {
    const speech = PassengerSpeaks(
      66,
      passengerId: 'p2',
      slot: SpeechSlot.stopNear,
      speechKey: 'passenger.stop_near',
      variant: 1,
      stationId: 'kobri',
    );
    expect(speech.toJson(), {
      'name': 'PassengerSpeaks',
      't_ms': 66,
      'passenger_id': 'p2',
      'slot': 'stop_near',
      'speech_key': 'passenger.stop_near',
      'variant': 1,
      'station_id': 'kobri',
    });
  });

  test('payload values use wire forms', () {
    expect(
      const TokenHopStarted(
        33,
        tokenId: 1,
        from: Holder.driver,
        to: Holder.passenger('p1'),
        durationMs: 1100,
      ).toJson(),
      {
        'name': 'TokenHopStarted',
        't_ms': 33,
        'token_id': 1,
        'from': 'DRIVER',
        'to': 'p1',
        'duration_ms': 1100,
      },
    );
    expect(
      const TripFailed(
        99,
        reputationLost: {RepCause.fight: 60},
        revivable: false,
      ).toJson()['reputation_lost'],
      {'fight': 60},
    );
    expect(
      BreakCompleted(
        33,
        denomination: 1000,
        pieces: Pieces({500: 1, 100: 4, 50: 2}),
      ).toJson()['pieces'],
      {'50': 2, '100': 4, '500': 1},
    );
    expect(
      const ChangeDelivered(
        33,
        tokenId: 2,
        passengerId: 'p1',
        result: ChangeResult.notOwed,
        amountPiasters: 300,
      ).toJson()['result'],
      'not_owed',
    );
    expect(
      TripFinished(33, result: _result).toJson()['result'],
      _result.toJson(),
    );
  });
}
