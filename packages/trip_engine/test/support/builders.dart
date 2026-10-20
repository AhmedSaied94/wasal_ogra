// Small trip definitions built in code (research R16). Every builder output
// is a valid TripDefinition unless a test breaks it on purpose.
import 'package:content_models/content_models.dart';

/// Seats of the two layouts the tests use: `tuktuk` (one row A) and
/// `micro_old` (front_r, then rows A to C).
List<Seat> seatsOf(VehicleId vehicle) => switch (vehicle) {
  VehicleId.tuktuk => [for (final col in SeatCol.values) _seat(SeatRow.a, col)],
  _ => [
    _seat(SeatRow.front, SeatCol.r),
    for (final row in [SeatRow.a, SeatRow.b, SeatRow.c])
      for (final col in SeatCol.values) _seat(row, col),
  ],
};

Seat _seat(SeatRow row, SeatCol col) {
  final rowName = switch (row) {
    SeatRow.front => 'front',
    SeatRow.a => 'A',
    SeatRow.b => 'B',
    SeatRow.c => 'C',
    SeatRow.d => 'D',
  };
  return Seat(
    seatId: '${rowName}_${col.name}',
    row: row,
    col: col,
    reachableByDriver: row == SeatRow.front || row == SeatRow.a,
  );
}

Denomination denomination(int piasters) =>
    Denomination.values.byName('v$piasters');

/// A fluent builder of trip definitions. Defaults: `micro_old` on
/// `line_gamaa`, seed 1, no events, rules with no discount and two breaks.
final class TripBuilder {
  TripBuilder({
    this.vehicle = VehicleId.microOld,
    this.line = LineId.lineGamaa,
  });

  final VehicleId vehicle;
  final LineId line;
  int _seed = 1;
  int _maxEarnings = 100;
  TripKind _kind = TripKind.regular;
  List<Seat>? _seats;
  final _stations = <TripStation>[];
  final _passengers = <PassengerSpec>[];
  final _events = <TripEvent>[];
  Map<String, int> _tray = {'100': 4, '50': 4, '500': 2};
  TripRules _rules = const TripRules(
    studentDiscountPct: 0,
    bagFarePiasters: 0,
    childFreeAge: 6,
    maxBreakRequests: 2,
    noFightsRequired: false,
  );

  TripBuilder seed(int value) => this.._seed = value;

  TripBuilder maxEarnings(int jenehat) => this.._maxEarnings = jenehat;

  TripBuilder story() => this.._kind = TripKind.story;

  TripBuilder seats(List<Seat> seats) => this.._seats = seats;

  TripBuilder station(String id, int atSeconds, {int fare = 700}) => this
    .._stations.add(
      TripStation(stationId: id, atSeconds: atSeconds, farePiasters: fare),
    );

  TripBuilder passenger(
    String id, {
    required String seat,
    required String dest,
    required List<int> payment,
    Archetype archetype = Archetype.regular,
    String? board,
    int? paysAt,
    String? group,
    int? groupSize,
    Map<String, String>? speechKeys,
    String skin = 'worker_blue',
  }) => this
    .._passengers.add(
      PassengerSpec(
        passengerId: id,
        archetype: archetype,
        skin: skin,
        seatId: seat,
        boardStationId: board,
        destStationId: dest,
        paysAtSeconds: paysAt,
        payment: [for (final piece in payment) denomination(piece)],
        groupId: group,
        groupSize: groupSize,
        speechKeys: speechKeys,
      ),
    );

  TripBuilder event(
    EventId id,
    int atSeconds, {
    List<String>? passengers,
    int? amount,
    int? seconds,
    String? station,
  }) => this
    .._events.add(
      TripEvent(
        eventId: id,
        atSeconds: atSeconds,
        passengerIds: passengers,
        amountPiasters: amount,
        seconds: seconds,
        stationId: station,
      ),
    );

  TripBuilder tray(Map<int, int> counts) => this
    .._tray = {
      for (final MapEntry(:key, :value) in counts.entries) '$key': value,
    };

  TripBuilder rules({
    int studentDiscountPct = 0,
    int maxBreakRequests = 2,
    bool noFightsRequired = false,
  }) => this
    .._rules = TripRules(
      studentDiscountPct: studentDiscountPct,
      bagFarePiasters: 0,
      childFreeAge: 6,
      maxBreakRequests: maxBreakRequests,
      noFightsRequired: noFightsRequired,
    );

  TripDefinition build() => TripDefinition(
    tripId: '${_lineWire(line)}.01',
    rev: 1,
    kind: _kind,
    lineId: line,
    vehicleId: vehicle,
    seed: _seed,
    seats: _seats ?? seatsOf(vehicle),
    stations: List.of(_stations),
    initialTray: Map.of(_tray),
    rules: _rules,
    passengers: List.of(_passengers),
    events: List.of(_events),
    starRules: const StarRules(
      two: StarRuleTwo.noFights,
      three: StarRuleThree.noFightsNoMistakes,
    ),
    maxEarningsJenehat: _maxEarnings,
  );
}

String _lineWire(LineId line) => switch (line) {
  LineId.lineHay => 'line_hay',
  LineId.lineGamaa => 'line_gamaa',
  LineId.lineSouq => 'line_souq',
  LineId.lineMasyaf => 'line_masyaf',
  LineId.lineSafar => 'line_safar',
};
