// Rebuilding a killed trip from its replay record (SC-009, research R10,
// replay-and-fixtures.md §4): cut every fixture at 10 points, rebuild, and
// continue.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/builders.dart';
import '../support/default_params.dart';
import '../support/fixture_io.dart';

// Plays [fixture] live, applying each command at its time, up to [cut].
final class _Live {
  _Live(this.fixture)
    : engine = TripEngine.start(
        fixture.definition,
        fixture.params,
        seed: fixture.seed,
      );

  final ParityFixture fixture;
  final TripEngine engine;
  int _next = 0;

  void advanceTo(int cut) {
    final log = fixture.commandLog;
    while (_next < log.length && log[_next].tMs <= cut) {
      engine.stepTo(log[_next].tMs);
      expect(engine.apply(log[_next].command), isA<Accepted>());
      _next++;
    }
    engine.stepTo(cut);
  }

  /// The commands the live run hasn't reached.
  List<LoggedCommand> get rest => fixture.commandLog.sublist(_next);
}

// [state] as JSON, with a running status shown as paused, as a rebuild
// leaves it.
Map<String, Object?> _asRebuilt(TripState state) => {
  ...state.toJson(),
  if (state.status == TripStatus.running) 'status': TripStatus.paused.wire,
};

TripResult _continue(TripEngine engine, List<LoggedCommand> rest) {
  engine.resume();
  for (final entry in rest) {
    engine.stepTo(entry.tMs);
    expect(engine.apply(entry.command), isA<Accepted>());
  }
  while (engine.status == TripStatus.running) {
    engine.step();
  }
  return engine.result!;
}

void main() {
  for (final file in fixtureFiles()) {
    final name = fixtureName(file);
    test('$name rebuilds at 10 cuts, and continues to its result', () {
      final fixture = loadFixture(file);
      final duration = fixture.expectedResult.durationMs;
      final live = _Live(fixture);
      for (var k = 1; k <= 10; k++) {
        final cut = duration * k ~/ 10 ~/ 33 * 33;
        live.advanceTo(cut);
        final record = live.engine.replayRecord;
        expect(record.tMs, live.engine.state.tMs);
        final rebuilt = TripEngine.rebuild(
          ReplayRecord.fromJson(jsonDecode(jsonEncode(record.toJson()))),
        );
        expect(
          rebuilt.state.toJson(),
          _asRebuilt(live.engine.state),
          reason: '$name at $cut',
        );
        expect(rebuilt.step(), isEmpty, reason: 'a rebuilt trip waits');
        final result = _continue(rebuilt, live.rest);
        expect(
          result.toJson(),
          fixture.expectedResult.toJson(),
          reason: '$name continued from $cut',
        );
      }
    });
  }

  group('a rebuilt trip keeps its status', () {
    test('a failed trip comes back failed and still revivable', () {
      final fixture = fixtureNamed('ending__failed.json');
      final live = _Live(fixture)..advanceTo(1 << 30);
      final rebuilt = TripEngine.rebuild(live.engine.replayRecord);
      expect(rebuilt.status, TripStatus.failed);
      expect(rebuilt.state.revivable, isTrue);
      expect(rebuilt.apply(const Revive()), isA<Accepted>());
    });

    test('a finished trip comes back finished', () {
      final live = _Live(fixtureNamed('core__exact_change.json'))
        ..advanceTo(1 << 30);
      final rebuilt = TripEngine.rebuild(live.engine.replayRecord);
      expect(rebuilt.status, TripStatus.finished);
      expect(rebuilt.result!.toJson(), live.engine.result!.toJson());
    });
  });

  group('refused records', () {
    final trip =
        (TripBuilder()
              ..station('gamaa', 30)
              ..passenger(
                'p1',
                seat: 'A_r',
                dest: 'gamaa',
                payment: [1000],
                paysAt: 1,
              ))
            .build();
    ReplayRecord record({
      int seed = 1,
      List<LoggedCommand> log = const [],
      int tMs = 990,
    }) => ReplayRecord(
      definition: trip,
      seed: seed,
      params: defaultParams(),
      commandLog: log,
      tMs: tMs,
    );
    Matcher refused(int? index) =>
        throwsA(isA<RebuildRefused>().having((e) => e.index, 'index', index));

    test('a refused definition', () {
      expect(() => TripEngine.rebuild(record(seed: 0)), refused(null));
    });

    test('t_ms going down along the log', () {
      expect(
        () => TripEngine.rebuild(
          record(
            log: const [
              LoggedCommand(66, PickFromTray(100)),
              LoggedCommand(33, ReturnHand()),
            ],
          ),
        ),
        refused(1),
      );
    });

    test('t_ms before the last command', () {
      expect(
        () => TripEngine.rebuild(
          record(log: const [LoggedCommand(660, PickFromTray(100))], tMs: 330),
        ),
        refused(null),
      );
    });

    test('t_ms that is not a step', () {
      expect(() => TripEngine.rebuild(record(tMs: 100)), refused(null));
    });

    test('an entry rejected on replay', () {
      expect(
        () => TripEngine.rebuild(
          record(log: const [LoggedCommand(33, PickFromTray(1000))]),
        ),
        refused(0),
      );
    });
  });
}
