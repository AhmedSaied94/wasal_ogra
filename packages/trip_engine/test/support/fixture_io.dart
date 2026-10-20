// Loading the parity fixtures of fixtures/parity and replaying them with
// their events (replay-and-fixtures.md §5).
import 'dart:convert';
import 'dart:io';

import 'package:trip_engine/src/replay.dart' show replayEngine;
import 'package:trip_engine/trip_engine.dart';

const fixturesDir = '../../fixtures/parity';

/// Every fixture file, sorted by name.
List<File> fixtureFiles() =>
    Directory(fixturesDir)
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

String fixtureName(File file) => file.uri.pathSegments.last;

ParityFixture loadFixture(File file) =>
    ParityFixture.fromJson(jsonDecode(file.readAsStringSync()));

/// The fixture named [name] in [fixturesDir].
ParityFixture fixtureNamed(String name) =>
    loadFixture(File('$fixturesDir/$name'));

/// A fixture's replay: the engine at the end, and every event on the way.
typedef Replayed = ({TripEngine engine, List<DomainEvent> events});

Replayed replayWithEvents(ParityFixture fixture) {
  final events = <DomainEvent>[];
  final engine = replayEngine(
    fixture.definition,
    fixture.params,
    fixture.seed,
    fixture.commandLog,
    onEvents: events.addAll,
  );
  return (engine: engine, events: events);
}

/// The rule a fixture pins, asserted on its replay.
typedef Expectation = void Function(Replayed run);

/// The hops of token [tokenId], each as `from>to`.
List<String> hopsOf(Replayed run, int tokenId) => [
  for (final hop in run.events.whereType<TokenHopStarted>())
    if (hop.tokenId == tokenId) '${hop.from.wire}>${hop.to.wire}',
];

/// The id of [passengerId]'s fare token (the first, unless [nth] says).
int fareToken(Replayed run, String passengerId, [int nth = 0]) => run.events
    .whereType<FareSent>()
    .where((e) => e.passengerId == passengerId)
    .elementAt(nth)
    .tokenId;

/// The id of the change token sent to [passengerId] (the first, unless [nth]).
int changeToken(Replayed run, String passengerId, [int nth = 0]) => run.events
    .whereType<ChangeSent>()
    .where((e) => e.passengerId == passengerId)
    .elementAt(nth)
    .tokenId;

/// The trip's result, which every replay ends with.
TripResult resultOf(Replayed run) =>
    run.engine.result ?? (throw StateError('the replay has no result'));
