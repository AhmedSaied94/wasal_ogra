// What a trip's definition fixes for its whole run, worked out once at start
// so the rules never search the definition: indexes, seats, groups.
import 'package:content_models/content_models.dart';

import '../wire.dart';

final class Course {
  Course(this.definition)
    : passengerIndex = {
        for (final (i, passenger) in definition.passengers.indexed)
          passenger.passengerId: i,
      },
      stationIndex = {
        for (final (i, station) in definition.stations.indexed)
          station.stationId: i,
      },
      seatRow = {
        for (final seat in definition.seats) seat.seatId: _rowIndex(seat.row),
      },
      seatCol = {for (final seat in definition.seats) seat.seatId: seat.col},
      seatAt = {
        for (final seat in definition.seats)
          (_rowIndex(seat.row), seat.col): seat.seatId,
      },
      payment = [
        for (final passenger in definition.passengers)
          [for (final piece in passenger.payment) denominationValue(piece)],
      ] {
    for (final passenger in definition.passengers) {
      destIndex.add(stationIndex[passenger.destStationId] ?? 0);
      boardIndex.add(switch (passenger.boardStationId) {
        final board? => stationIndex[board],
        null => null,
      });
    }
    for (final event in definition.events) {
      if (event.eventId != EventId.roadsidePickup) continue;
      for (final id in event.passengerIds ?? const <String>[]) {
        if (passengerIndex[id] case final i?) pickedUp.add(i);
      }
    }
    final payers = <String, int>{
      for (final (i, passenger) in definition.passengers.indexed)
        if (passenger.groupId case final group?
            when passenger.archetype == Archetype.groupPayer)
          group: i,
    };
    for (final (i, passenger) in definition.passengers.indexed) {
      final payer = payers[passenger.groupId];
      if (payer != null && payer != i) {
        payerOf.add(payer);
        (membersOf[payer] ??= []).add(i);
      } else {
        payerOf.add(null);
      }
    }
  }

  final TripDefinition definition;

  final Map<String, int> passengerIndex;
  final Map<String, int> stationIndex;

  /// Rows from the driver backwards: front 0, A 1, B 2, C 3, D 4.
  final Map<String, int> seatRow;
  final Map<String, SeatCol> seatCol;

  /// The seat at (row, column), if the vehicle has one.
  final Map<(int, SeatCol), String> seatAt;

  /// Each passenger's authored payment, in piasters.
  final List<List<int>> payment;

  /// Each passenger's destination station index.
  final List<int> destIndex = [];

  /// Each passenger's boarding station index, if any.
  final List<int?> boardIndex = [];

  /// Passengers listed by a `roadside_pickup`.
  final Set<int> pickedUp = {};

  /// For a group member, the index of the group's payer.
  final List<int?> payerOf = [];

  /// For a group payer, the indexes of the members the trip lists.
  final Map<int, List<int>> membersOf = {};

  /// The last row one hop from the driver: rows `front` and `A` are.
  static const int lastNearRow = 1;

  static int _rowIndex(SeatRow row) => switch (row) {
    SeatRow.front => 0,
    SeatRow.a => 1,
    SeatRow.b => 2,
    SeatRow.c => 3,
    SeatRow.d => 4,
  };

  PassengerSpec spec(int passenger) => definition.passengers[passenger];

  /// The index of passenger [passengerId]. Every id the rules hold is one.
  int indexOf(String passengerId) =>
      passengerIndex[passengerId] ??
      (throw StateError('no passenger $passengerId'));

  Archetype archetype(int passenger) =>
      definition.passengers[passenger].archetype;

  bool isMember(int passenger) => payerOf[passenger] != null;

  bool isPayer(int passenger) =>
      definition.passengers[passenger].archetype == Archetype.groupPayer;

  int get stationCount => definition.stations.length;

  TripRules get rules => definition.rules;
}
