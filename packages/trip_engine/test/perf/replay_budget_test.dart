// The replay budget (SC-004, SC-005): the longest trip replays and rebuilds
// in under a second, and its command log fits backend §16's 64 KB.
import 'dart:convert';

import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/fixture_io.dart';

const _longestTripMs = 1500000;
const _budgetMs = 1000;
const _logLimitBytes = 65536;
const _timedRuns = 3;

int _canonicalBytes(List<Object?> log) =>
    utf8.encode(canonicalJson(log)).length;

void main() {
  final fixture = fixtureNamed('stress__longest_trip.json');

  // The best of a few runs after one warm-up, as a device would have warmed
  // up, so a busy CI runner's noise doesn't fail the budget. On the dev
  // machine a replay takes about 55 ms warm and 190 ms cold.
  int timeMs(void Function() run) {
    run();
    var best = -1;
    for (var i = 0; i < _timedRuns; i++) {
      final watch = Stopwatch()..start();
      run();
      final ms = watch.elapsedMilliseconds;
      if (best < 0 || ms < best) best = ms;
    }
    return best;
  }

  test('it really is the longest trip, with 1,200 commands', () {
    expect(
      fixture.expectedResult.durationMs,
      greaterThanOrEqualTo(_longestTripMs),
    );
    expect(fixture.commandLog, hasLength(1200));
  });

  test('replaying it takes under 1 s', () {
    final ms = timeMs(
      () => replay(
        fixture.definition,
        fixture.params,
        fixture.seed,
        fixture.commandLog,
      ),
    );
    expect(ms, lessThan(_budgetMs));
  });

  test('rebuilding it at its last step takes under 1 s', () {
    final record = ReplayRecord(
      definition: fixture.definition,
      seed: fixture.seed,
      params: fixture.params,
      commandLog: fixture.commandLog,
      tMs: fixture.expectedResult.durationMs,
    );
    expect(timeMs(() => TripEngine.rebuild(record)), lessThan(_budgetMs));
  });

  test('its canonical command log fits in 64 KB', () {
    expect(
      _canonicalBytes([for (final entry in fixture.commandLog) entry.toJson()]),
      lessThanOrEqualTo(_logLimitBytes),
    );
  });

  test('so do 1,200 copies of the longest entry and a final Abandon', () {
    // Abandon is accepted past the cap (rules.md §4), so the longest log has
    // 1,201 entries.
    const longest = LoggedCommand(
      1500000,
      ResolveChangeRequest('p999', agree: false),
    );
    expect(utf8.encode(canonicalJson(longest.toJson())), hasLength(45));
    expect(
      _canonicalBytes([
        ...List.filled(1200, longest.toJson()),
        const LoggedCommand(1500000, Abandon()).toJson(),
      ]),
      lessThanOrEqualTo(_logLimitBytes),
    );
  });
}
