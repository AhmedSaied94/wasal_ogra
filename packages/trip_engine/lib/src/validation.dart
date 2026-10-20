// Refusals at start (rules.md §2.1, data-model.md "Validation", FR-003). The
// definition is assumed to pass trip.schema.json; these are the engine's own
// checks, with the same codes B05 uses.
import 'package:content_models/content_models.dart';

import 'capabilities.dart';
import 'params.dart';
import 'wire.dart';

enum RefusalCode {
  badSeed,
  badParams,
  duplicateId,
  unknownSeat,
  unknownStation,
  stationsOutOfOrder,
  boardAfterDest,
  seatTakenAtStart,
  unknownPassenger,
  groupMismatch,
  unsupportedArchetype,
  unsupportedEvent,
  eventParam,
  pickupConflict;

  String get wire => wireName(this);
}

/// One problem: its code, the path of the offending field (`seed`,
/// `params.<key>`, or a JSON path into the definition) and an English
/// message for developers.
final class Refusal {
  const Refusal(this.code, this.path, this.message);

  final RefusalCode code;
  final String path;
  final String message;

  @override
  String toString() => '${code.wire} at $path: $message';
}

/// Thrown by `TripEngine.start` with every problem found.
final class TripRefused implements Exception {
  TripRefused(List<Refusal> refusals) : refusals = List.unmodifiable(refusals);

  final List<Refusal> refusals;

  @override
  String toString() => 'TripRefused(${refusals.join('; ')})';
}

/// Every problem of [definition] with [params] and [seed].
List<Refusal> validate(
  TripDefinition definition,
  TripParams params,
  int seed,
) => validateWith(definition, params, seed);

/// [validate] against chosen capabilities, so tests can narrow them.
List<Refusal> validateWith(
  TripDefinition definition,
  TripParams params,
  int seed, {
  Set<Archetype> archetypes = EngineCapabilities.archetypes,
  Set<EventId> events = EngineCapabilities.events,
}) {
  final out = <Refusal>[];
  void refuse(RefusalCode code, String path, String message) =>
      out.add(Refusal(code, path, message));

  if (seed < 1 || seed > 0xFFFFFFFF) {
    refuse(RefusalCode.badSeed, 'seed', 'the seed $seed is outside 1..2^32-1');
  }
  for (final problem in params.problems()) {
    refuse(RefusalCode.badParams, 'params.${problem.key}', problem.message);
  }

  final seats = _unique(
    [for (final seat in definition.seats) seat.seatId],
    r'$.seats',
    'seat_id',
    refuse,
  );
  final stations = _unique(
    [for (final station in definition.stations) station.stationId],
    r'$.stations',
    'station_id',
    refuse,
  );
  final passengers = _unique(
    [for (final passenger in definition.passengers) passenger.passengerId],
    r'$.passengers',
    'passenger_id',
    refuse,
  );

  for (final (i, station) in definition.stations.indexed) {
    if (i > 0 && station.atSeconds <= definition.stations[i - 1].atSeconds) {
      refuse(
        RefusalCode.stationsOutOfOrder,
        '\$.stations[$i].at_seconds',
        'station times must strictly increase',
      );
    }
  }

  final pickedUp = _pickups(definition, refuse);
  final seatedAtStart = <String>{};
  for (final (i, passenger) in definition.passengers.indexed) {
    final path = '\$.passengers[$i]';
    if (!archetypes.contains(passenger.archetype)) {
      refuse(
        RefusalCode.unsupportedArchetype,
        '$path.archetype',
        'the engine does not support ${wireName(passenger.archetype)}',
      );
    }
    if (!seats.contains(passenger.seatId)) {
      refuse(
        RefusalCode.unknownSeat,
        '$path.seat_id',
        'no seat ${passenger.seatId}',
      );
    }
    final dest = stations.indexOf(passenger.destStationId);
    if (dest < 0) {
      refuse(
        RefusalCode.unknownStation,
        '$path.dest_station_id',
        'no station ${passenger.destStationId}',
      );
    }
    if (passenger.boardStationId case final board?) {
      final boardIndex = stations.indexOf(board);
      if (boardIndex < 0) {
        refuse(
          RefusalCode.unknownStation,
          '$path.board_station_id',
          'no station $board',
        );
      } else if (dest >= 0 && boardIndex >= dest) {
        refuse(
          RefusalCode.boardAfterDest,
          '$path.board_station_id',
          'boards at $board, not before ${passenger.destStationId}',
        );
      }
    }
    final aboardAtStart =
        passenger.boardStationId == null &&
        !pickedUp.contains(passenger.passengerId);
    if (aboardAtStart && !seatedAtStart.add(passenger.seatId)) {
      refuse(
        RefusalCode.seatTakenAtStart,
        '$path.seat_id',
        'two passengers start in ${passenger.seatId}',
      );
    }
  }

  _groups(definition, refuse);
  _events(definition, passengers, events, refuse);
  return out;
}

typedef _Refuse = void Function(RefusalCode code, String path, String message);

List<String> _unique(
  List<String> ids,
  String list,
  String field,
  _Refuse refuse,
) {
  final seen = <String>{};
  for (final (i, id) in ids.indexed) {
    if (!seen.add(id)) {
      refuse(RefusalCode.duplicateId, '$list[$i].$field', 'duplicate id $id');
    }
  }
  return ids;
}

// Passengers listed by a roadside_pickup, with pickup conflicts refused.
Set<String> _pickups(TripDefinition definition, _Refuse refuse) {
  final boards = {
    for (final passenger in definition.passengers)
      if (passenger.boardStationId != null) passenger.passengerId,
  };
  final picked = <String>{};
  for (final (i, event) in definition.events.indexed) {
    if (event.eventId != EventId.roadsidePickup) continue;
    for (final (j, id) in (event.passengerIds ?? const <String>[]).indexed) {
      if (!picked.add(id) || boards.contains(id)) {
        refuse(
          RefusalCode.pickupConflict,
          '\$.events[$i].passenger_ids[$j]',
          '$id is boarded by more than one pickup or station',
        );
      }
    }
  }
  return picked;
}

void _groups(TripDefinition definition, _Refuse refuse) {
  final firstSize = <String, int>{};
  final members = <String, int>{};
  final payers = <String, int>{};
  final firstIndex = <String, int>{};
  for (final (i, passenger) in definition.passengers.indexed) {
    final path = '\$.passengers[$i]';
    final group = passenger.groupId;
    final isPayer = passenger.archetype == Archetype.groupPayer;
    if (group == null) {
      if (isPayer) {
        refuse(
          RefusalCode.groupMismatch,
          '$path.group_id',
          'a group_payer needs a group',
        );
      } else if (passenger.groupSize != null) {
        refuse(
          RefusalCode.groupMismatch,
          '$path.group_size',
          'a group_size needs a group',
        );
      }
      continue;
    }
    firstIndex.putIfAbsent(group, () => i);
    final size = passenger.groupSize;
    if (size == null) {
      refuse(
        RefusalCode.groupMismatch,
        '$path.group_size',
        '$group needs a group_size',
      );
    } else if (firstSize.putIfAbsent(group, () => size) != size) {
      refuse(
        RefusalCode.groupMismatch,
        '$path.group_size',
        '$group has group_size ${firstSize[group]} elsewhere',
      );
    }
    final count = members[group] = (members[group] ?? 0) + 1;
    if (firstSize[group] case final limit? when count > limit) {
      refuse(
        RefusalCode.groupMismatch,
        '$path.group_id',
        '$group has more than $limit',
      );
    }
    if (isPayer) {
      final payerCount = payers[group] = (payers[group] ?? 0) + 1;
      if (payerCount > 1) {
        refuse(
          RefusalCode.groupMismatch,
          '$path.archetype',
          '$group has two group_payers',
        );
      }
    }
  }
  for (final MapEntry(key: group, value: i) in firstIndex.entries) {
    if (!payers.containsKey(group)) {
      refuse(
        RefusalCode.groupMismatch,
        '\$.passengers[$i].group_id',
        '$group has no group_payer',
      );
    }
  }
}

void _events(
  TripDefinition definition,
  List<String> passengers,
  Set<EventId> supported,
  _Refuse refuse,
) {
  final grouped = {
    for (final passenger in definition.passengers)
      if (passenger.groupId != null) passenger.passengerId,
  };
  final stations = {
    for (final station in definition.stations) station.stationId,
  };
  for (final (i, event) in definition.events.indexed) {
    final path = '\$.events[$i]';
    if (!supported.contains(event.eventId)) {
      refuse(
        RefusalCode.unsupportedEvent,
        '$path.event_id',
        'the engine does not support ${wireName(event.eventId)}',
      );
      continue;
    }
    final ids = event.passengerIds ?? const <String>[];
    for (final (j, id) in ids.indexed) {
      if (!passengers.contains(id)) {
        refuse(
          RefusalCode.unknownPassenger,
          '$path.passenger_ids[$j]',
          'no passenger $id',
        );
      }
    }
    if (event.stationId case final station? when !stations.contains(station)) {
      refuse(
        RefusalCode.unknownStation,
        '$path.station_id',
        'no station $station',
      );
    }
    final rules = EngineCapabilities.eventParams[event.eventId] ?? const {};
    final values = <String, Object?>{
      'passenger_ids': event.passengerIds,
      'station_id': event.stationId,
      'amount_piasters': event.amountPiasters,
      'seconds': event.seconds,
    };
    for (final MapEntry(key: name, :value) in values.entries) {
      final problem = _paramProblem(rules[name], value, grouped);
      if (problem case (final suffix, final message)) {
        refuse(RefusalCode.eventParam, '$path.$name$suffix', message);
      }
    }
  }
}

// The problem with one event parameter, as (path suffix, message), or null.
(String, String)? _paramProblem(
  EventParamRule? rule,
  Object? value,
  Set<String> grouped,
) {
  if (rule == null) {
    return value == null ? null : ('', 'not allowed for this event');
  }
  if (value == null) {
    return rule.use == ParamUse.required ? ('', 'required') : null;
  }
  switch (value) {
    case final int number:
      if (rule.min case final min? when number < min) return ('', 'below $min');
      if (rule.max case final max? when number > max) {
        return ('', 'above ${rule.max}');
      }
      if (rule.oneOf case final oneOf? when !oneOf.contains(number)) {
        return ('', 'must be one of $oneOf');
      }
    case final List<String> ids:
      if (rule.minItems case final min? when ids.length < min) {
        return ('', 'fewer than $min');
      }
      if (rule.maxItems case final max? when ids.length > max) {
        return ('', 'more than $max');
      }
      if (rule.noGroupMembers) {
        for (final (j, id) in ids.indexed) {
          if (grouped.contains(id)) return ('[$j]', '$id is in a group');
        }
      }
  }
  return null;
}
