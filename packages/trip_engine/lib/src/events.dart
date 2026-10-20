// What happened, in order, from every step and accepted command
// (contracts/engine-api.md "Domain events"). The engine reports everything,
// including who has paid; M02 decides what to show.
import 'package:content_models/content_models.dart';

import 'capabilities.dart';
import 'model/counters.dart';
import 'model/passenger.dart';
import 'model/result.dart';
import 'model/token.dart';
import 'money.dart';
import 'wire.dart';

part 'events/choice_events.dart';
part 'events/money_events.dart';
part 'events/passenger_events.dart';
part 'events/trip_events.dart';

sealed class DomainEvent {
  const DomainEvent(this.tMs);

  /// The clock when it happened.
  final int tMs;

  /// The wire name.
  String get name;

  Map<String, Object> get payload;

  /// `{"name": …, "t_ms": …, …payload}`.
  Map<String, Object> toJson() => {'name': name, 't_ms': tMs, ...payload};

  @override
  String toString() => '$name@$tMs$payload';
}

/// Events whose payload is one passenger.
mixin _OnePassenger on DomainEvent {
  String get passengerId;

  @override
  Map<String, Object> get payload => {'passenger_id': passengerId};
}

/// Events whose payload is one token.
mixin _OneToken on DomainEvent {
  int get tokenId;

  @override
  Map<String, Object> get payload => {'token_id': tokenId};
}
