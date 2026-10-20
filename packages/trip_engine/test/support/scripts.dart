// Helpers for driving a trip in tests: start, step to a time, and apply a
// command expecting it to be accepted or rejected.
import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import 'default_params.dart';

TripEngine startTrip(
  TripDefinition definition, {
  TripParams? params,
  int? seed,
}) => TripEngine.start(
  definition,
  params ?? defaultParams(definition.lineId),
  seed: seed,
);

extension TripScript on TripEngine {
  /// Steps to [seconds] of trip time (rounded up to the next 33 ms step).
  List<DomainEvent> stepToSeconds(int seconds) => stepTo(seconds * 1000);

  /// Applies [command] and expects it to be accepted. Returns its events.
  List<DomainEvent> ok(Command command) {
    final outcome = apply(command);
    if (outcome is Rejected) {
      fail(
        '$command was rejected: ${outcome.rejection.code} '
        '(${outcome.rejection.message})',
      );
    }
    return (outcome as Accepted).events;
  }

  /// Applies [command] and expects it to be rejected with [code], leaving
  /// the state and the log unchanged.
  void rejects(Command command, RejectionCode code) {
    final before = state.toJson();
    final logLength = commandLog.length;
    final outcome = apply(command);
    expect(outcome, isA<Rejected>(), reason: '$command');
    expect((outcome as Rejected).rejection.code, code, reason: '$command');
    expect(state.toJson(), before, reason: 'a rejected $command changed state');
    expect(commandLog, hasLength(logLength));
  }

  PassengerState passenger(String id) => state.passenger(id)!;
}

/// The events of type [T] in [events].
List<T> eventsOf<T extends DomainEvent>(Iterable<DomainEvent> events) =>
    events.whereType<T>().toList();

/// The speech slots spoken by [passengerId] in [events], in order.
List<SpeechSlot> spoken(Iterable<DomainEvent> events, String passengerId) => [
  for (final speech in events.whereType<PassengerSpeaks>())
    if (speech.passengerId == passengerId) speech.slot,
];
