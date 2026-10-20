// Writes fixtures/parity/stress__longest_trip.json (SC-004, SC-005): a full
// micro_old carrying 30 passengers, the longest trip the bounds allow
// (1,500 s) and exactly 1,200 accepted commands. Deterministic, so running it
// again gives the same file. Run in packages/trip_engine:
//
//   fvm dart run tool/stress_fixture.dart
//   fvm dart run tool/fixtures.dart update ../../fixtures/parity/stress__longest_trip.json
import 'dart:convert';
import 'dart:io';

import 'package:content_models/content_models.dart';
import 'package:trip_engine/trip_engine.dart';

const _path = '../../fixtures/parity/stress__longest_trip.json';
const _tunables = '../../apps/mobile/assets/config/tunables.json';

// Schema and params maxima (trip.schema.json, data-model.md "TripParams").
const _lastStationSeconds = 600;
const _trafficEvents = 10;
const _eventSeconds = 60;
const _jamMs = 60000;
const _jamsPerTrip = 5;
const _commands = 1200;

// One step of the clock, and the filler commands' spacing: a pick and a
// return every 76 steps fit 597 pairs before the last station.
const _stepMs = 33;
const _fillerEveryMs = 76 * _stepMs;

const _seats = [
  ('front_r', SeatRow.front, SeatCol.r),
  ('A_r', SeatRow.a, SeatCol.r),
  ('A_m', SeatRow.a, SeatCol.m),
  ('A_l', SeatRow.a, SeatCol.l),
  ('B_r', SeatRow.b, SeatCol.r),
  ('B_m', SeatRow.b, SeatCol.m),
  ('B_l', SeatRow.b, SeatCol.l),
  ('C_r', SeatRow.c, SeatCol.r),
  ('C_m', SeatRow.c, SeatCol.m),
  ('C_l', SeatRow.c, SeatCol.l),
];

// Types that need no help from the driver when paying exactly.
const _archetypes = [
  Archetype.regular,
  Archetype.hajja,
  Archetype.chatty,
  Archetype.regularCustomer,
  Archetype.honest,
];

const _stations = ['kobri', 'mostashfa', 'madrasa', 'gamaa'];

TripDefinition _definition() {
  final exact = [Denomination.v500, Denomination.v100, Denomination.v100];
  // Each seat carries three passengers in turn: aboard to kobri, then from
  // kobri to mostashfa, then from mostashfa to gamaa.
  final legs = [
    (null, 'kobri'),
    ('kobri', 'mostashfa'),
    ('mostashfa', 'gamaa'),
  ];
  final passengers = [
    for (final (leg, (board, dest)) in legs.indexed)
      for (final (i, (seat, _, _)) in _seats.indexed)
        PassengerSpec(
          passengerId: 'p${leg * _seats.length + i + 1}',
          archetype: _archetypes[(leg + i) % _archetypes.length],
          skin: 'worker_blue',
          seatId: seat,
          boardStationId: board,
          destStationId: dest,
          paysAtSeconds: board == null ? i + 1 : 0,
          payment: exact,
        ),
  ];
  return TripDefinition(
    tripId: 'line_gamaa.99',
    rev: 1,
    kind: TripKind.regular,
    lineId: LineId.lineGamaa,
    vehicleId: VehicleId.microOld,
    seed: 2026102001,
    seats: [
      for (final (id, row, col) in _seats)
        Seat(
          seatId: id,
          row: row,
          col: col,
          reachableByDriver: row == SeatRow.front || row == SeatRow.a,
        ),
    ],
    stations: [
      for (final (i, id) in _stations.indexed)
        TripStation(
          stationId: id,
          atSeconds: _lastStationSeconds * (i + 1) ~/ _stations.length,
          farePiasters: 700,
        ),
    ],
    initialTray: const {'50': 4, '100': 4, '500': 2},
    rules: const TripRules(
      studentDiscountPct: 0,
      bagFarePiasters: 0,
      childFreeAge: 6,
      maxBreakRequests: 2,
      noFightsRequired: false,
    ),
    passengers: passengers,
    events: [
      for (var i = 1; i <= _trafficEvents; i++)
        TripEvent(
          eventId: EventId.traffic,
          atSeconds: i * 10,
          seconds: _eventSeconds,
        ),
    ],
    starRules: const StarRules(
      two: StarRuleTwo.noFights,
      three: StarRuleThree.noFightsNoMistakes,
    ),
    maxEarningsJenehat: 250,
  );
}

TripParams _params() {
  final tunables =
      jsonDecode(File(_tunables).readAsStringSync()) as Map<String, Object?>;
  final defaults = TripParams.fromTunables(tunables, LineId.lineGamaa);
  return TripParams.fromJson({
    ...defaults.toJson(),
    'booster_traffic_jam_ms': _jamMs,
    'booster_traffic_jam_max_per_trip': _jamsPerTrip,
  });
}

void _apply(TripEngine engine, Command command) {
  if (engine.apply(command) case Rejected(:final rejection)) {
    throw StateError(
      '$command was rejected at ${engine.state.tMs}: ${rejection.code.wire}',
    );
  }
}

void main() {
  final definition = _definition();
  final params = _params();
  final engine = TripEngine.start(definition, params);
  for (var i = 0; i < _jamsPerTrip; i++) {
    _apply(engine, const UseBooster(BoosterId.trafficJam));
  }
  var at = 0;
  while (engine.commandLog.length + 2 <= _commands) {
    at += _fillerEveryMs;
    engine.stepTo(at);
    _apply(engine, const PickFromTray(100));
    _apply(engine, const ReturnHand());
  }
  if (engine.commandLog.length < _commands) {
    _apply(engine, const UseBooster(BoosterId.ledgerPeek));
  }
  final fixture = ParityFixture(
    definition: definition,
    seed: engine.seed,
    params: params,
    commandLog: engine.commandLog,
    expectedResult: replay(definition, params, engine.seed, engine.commandLog),
  );
  File(_path).writeAsStringSync(fixture.encode());
  stdout.writeln(
    'wrote $_path: ${fixture.commandLog.length} commands, '
    '${fixture.expectedResult.durationMs} ms',
  );
}
