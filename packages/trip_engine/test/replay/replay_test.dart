// replay() and the replay record (engine-api.md "Entry points",
// replay-and-fixtures.md §4): a live run's log replays to the same result,
// and a log the engine can't follow is refused with the entry's index.
import 'dart:convert';

import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/builders.dart';
import '../support/default_params.dart';
import '../support/scripts.dart';

// p1 (A_r) pays 1000 at 1 s for a 700 fare; the fare reaches the tray at
// 1023 + 34 × 33 = 2145. The trip finishes at gamaa, 30 s.
TripDefinition _trip({bool noFights = false}) =>
    (TripBuilder()
          ..station('gamaa', 30)
          ..passenger(
            'p1',
            seat: 'A_r',
            dest: 'gamaa',
            payment: [1000],
            paysAt: 1,
          )
          ..rules(noFightsRequired: noFights))
        .build();

TripEngine _live() {
  final engine = startTrip(_trip())..stepTo(2145);
  for (final piece in [100, 100, 100]) {
    engine.ok(PickFromTray(piece));
  }
  engine
    ..ok(const SendHand('p1'))
    ..stepToSeconds(40);
  return engine;
}

TypeMatcher<RebuildRefused> _refusedAt(int? index) =>
    isA<RebuildRefused>().having((e) => e.index, 'index', index);

void main() {
  final params = defaultParams();

  test("a live run's log replays to the live result", () {
    final live = _live();
    expect(live.status, TripStatus.finished);
    final replayed = replay(_trip(), params, 1, live.commandLog);
    expect(replayed.toJson(), live.result!.toJson());
    expect(replayed.commandLogHash, commandLogHash(live.commandLog));
  });

  test('the log replays the same from its wire form', () {
    final live = _live();
    final wire = jsonDecode(
      jsonEncode([for (final entry in live.commandLog) entry.toJson()]),
    );
    expect(
      replay(_trip(), params, 1, decodeCommandLog(wire)).toJson(),
      live.result!.toJson(),
    );
  });

  test('a log entry the engine rejects is refused with its index', () {
    expect(
      () => replay(_trip(), params, 1, const [
        LoggedCommand(0, PickFromTray(100)),
        LoggedCommand(33, SendHand('p9')),
      ]),
      throwsA(_refusedAt(1)),
    );
  });

  test('a log whose t_ms goes down is refused', () {
    expect(
      () => replay(_trip(), params, 1, const [
        LoggedCommand(66, PickFromTray(100)),
        LoggedCommand(33, ReturnHand()),
      ]),
      throwsA(_refusedAt(1)),
    );
  });

  test('an entry after the trip has ended is refused', () {
    expect(
      () => replay(_trip(), params, 1, const [
        LoggedCommand(39996, PickFromTray(100)),
      ]),
      throwsA(_refusedAt(0)),
    );
  });

  test('a refused trip is refused with its problems and no index', () {
    expect(
      () => replay(_trip(), params, 0, const []),
      throwsA(
        _refusedAt(null).having(
          (e) => e.refusals.map((r) => r.code),
          'refusals',
          contains(RefusalCode.badSeed),
        ),
      ),
    );
  });

  test('a log that ends with the trip failed returns the failed result', () {
    // No change is sent: one fight at gamaa fails a no-fights trip.
    final result = replay(_trip(noFights: true), params, 1, const [
      LoggedCommand(0, PickFromTray(100)),
    ]);
    expect(result.outcome, TripOutcome.failed);
    expect(result.stars, 0);
    expect(result.durationMs, 30030);
    expect(
      result.commandLogHash,
      commandLogHash(const [LoggedCommand(0, PickFromTray(100))]),
    );
  });

  group('ReplayRecord', () {
    ReplayRecord record() {
      final live = _live();
      return ReplayRecord(
        definition: _trip(),
        seed: 1,
        params: params,
        commandLog: live.commandLog,
        tMs: live.state.tMs,
      );
    }

    test('round-trips through JSON', () {
      final json = jsonDecode(jsonEncode(record().toJson()));
      final back = ReplayRecord.fromJson(json);
      expect(back.toJson(), record().toJson());
      expect(back.commandLog, hasLength(4));
      expect((json as Map<String, Object?>).keys.toSet(), {
        'command_log',
        'definition',
        'params',
        'seed',
        't_ms',
      });
    });

    Map<String, Object?> wire() =>
        jsonDecode(jsonEncode(record().toJson())) as Map<String, Object?>;

    test('refuses an unknown or missing key', () {
      expect(
        () => ReplayRecord.fromJson({...wire(), 'notes': 'x'}),
        throwsFormatException,
      );
      expect(
        () => ReplayRecord.fromJson(wire()..remove('t_ms')),
        throwsFormatException,
      );
    });

    test('refuses a malformed definition, seed or log', () {
      expect(
        () => ReplayRecord.fromJson({
          ...wire(),
          'definition': {'seed': 'x'},
        }),
        throwsFormatException,
      );
      expect(
        () => ReplayRecord.fromJson({...wire(), 'seed': '1'}),
        throwsFormatException,
      );
      expect(
        () => ReplayRecord.fromJson({
          ...wire(),
          'command_log': [
            [33, 'Fly'],
          ],
        }),
        throwsFormatException,
      );
      expect(() => ReplayRecord.fromJson([]), throwsFormatException);
    });
  });
}
