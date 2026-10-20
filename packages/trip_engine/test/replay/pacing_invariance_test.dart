// Pacing never changes a trip (SC-001, FR-054, rules.md §10.2): stepping one
// at a time, seven per call or straight to each command, and pausing around
// the commands allowed while paused, all give the same result, events and
// fingerprint as replay().
import 'dart:math';

import 'package:test/test.dart';
import 'package:trip_engine/src/rules/command_handlers.dart'
    show allowedStatuses;
import 'package:trip_engine/src/rules/transition.dart' show stepMs;
import 'package:trip_engine/trip_engine.dart';

import '../support/fixture_io.dart';

/// Advances [engine] toward [tMs], handing every event to [out].
typedef Advance = void Function(
  TripEngine engine,
  int tMs,
  void Function(List<DomainEvent>) out,
);

void _oneAtATime(
  TripEngine engine,
  int tMs,
  void Function(List<DomainEvent>) out,
) {
  while (engine.status == TripStatus.running && engine.state.tMs < tMs) {
    out(engine.step());
  }
}

void _sevenPerCall(
  TripEngine engine,
  int tMs,
  void Function(List<DomainEvent>) out,
) {
  while (engine.status == TripStatus.running && engine.state.tMs < tMs) {
    out(engine.stepTo(min(engine.state.tMs + 7 * stepMs, tMs)));
  }
}

void _straightTo(
  TripEngine engine,
  int tMs,
  void Function(List<DomainEvent>) out,
) => out(engine.stepTo(tMs));

// Past the longest trip the bounds allow (1,500 s).
const int _end = 1 << 30;

typedef _Run = ({Object? result, List<Object> events, String fingerprint});

_Run _run(ParityFixture fixture, Advance advance, {bool pauseAround = false}) {
  final engine = TripEngine.start(
    fixture.definition,
    fixture.params,
    seed: fixture.seed,
  );
  final events = <DomainEvent>[];
  for (final entry in fixture.commandLog) {
    advance(engine, entry.tMs, events.addAll);
    final pause =
        pauseAround &&
        engine.status == TripStatus.running &&
        allowedStatuses(entry.command).contains(TripStatus.paused);
    if (pause) engine.pause();
    final outcome = engine.apply(entry.command);
    expect(outcome, isA<Accepted>(), reason: '${entry.toJson()}');
    events.addAll((outcome as Accepted).events);
    if (pause) engine.resume();
  }
  advance(engine, _end, events.addAll);
  return (
    result: engine.result?.toJson(),
    events: [for (final event in events) event.toJson()],
    fingerprint: commandLogHash(engine.commandLog),
  );
}

void main() {
  final files = fixtureFiles();

  test('there are fixtures', () => expect(files, isNotEmpty));

  for (final file in files) {
    group(fixtureName(file), () {
      late final fixture = loadFixture(file);
      late final reference = _run(fixture, _straightTo);

      test('matches replay()', () {
        final result = replay(
          fixture.definition,
          fixture.params,
          fixture.seed,
          fixture.commandLog,
        );
        expect(reference.result, result.toJson());
        expect(reference.fingerprint, result.commandLogHash);
      });

      for (final (name, advance) in [
        ('one step at a time', _oneAtATime),
        ('seven steps per call', _sevenPerCall),
      ]) {
        test(name, () {
          final run = _run(fixture, advance);
          expect(run.result, reference.result);
          expect(run.events, reference.events);
          expect(run.fingerprint, reference.fingerprint);
        });
      }

      test('pausing around every command allowed while paused', () {
        final run = _run(fixture, _oneAtATime, pauseAround: true);
        expect(run.result, reference.result);
        expect(run.events, reference.events);
        expect(run.fingerprint, reference.fingerprint);
      });
    });
  }

  test('1,000 replays of one fixture give one result', () {
    final fixture = loadFixture(files.first);
    final first = replay(
      fixture.definition,
      fixture.params,
      fixture.seed,
      fixture.commandLog,
    ).toJson();
    for (var i = 1; i < 1000; i++) {
      final again = replay(
        fixture.definition,
        fixture.params,
        fixture.seed,
        fixture.commandLog,
      ).toJson();
      if (again.toString() != first.toString()) {
        fail('replay $i differs: $again');
      }
    }
  });
}
