// Home's next trip (specs/013-m08-home-result, research R3, data-model
// `NextTrip`): each rule step, where "the line played last" comes from, a
// sweep over every state a new player reaches, and M07's tutorial trip in
// the first session.
import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/progress/domain/playable.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/core/progress/domain/unlocks.dart';
import 'package:wassal/features/home/application/home_model.dart';
import 'package:wassal/features/home/domain/next_trip.dart';
import 'package:wassal/features/onboarding/domain/first_session.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/progress.dart';
import '../../../helpers/tutorial_content.dart';

/// Short names: `h1` is line_hay.01, `g2` line_gamaa.02, `s1` line_souq.01.
String _long(String short) {
  final line = switch (short[0]) {
    'h' => 'line_hay',
    'g' => 'line_gamaa',
    _ => 'line_souq',
  };
  return '$line.0${short.substring(1)}';
}

String _short(String id) =>
    '${id.startsWith('line_hay')
        ? 'h'
        : id.startsWith('line_gamaa')
        ? 'g'
        : 's'}'
    '${int.parse(id.split('.').last)}';

/// A player who finished [shorts], each at one star.
PlayerProgress _played(String shorts) => player({
  for (final s in shorts.split(' ').where((s) => s.isNotEmpty)) _long(s): 1,
});

String? _next(ContentSource c, PlayerProgress p, {String? last}) =>
    switch (nextTrip(
      c,
      p,
      lastFinishedTripId: last == null ? null : _long(last),
    )) {
      final next? => '${_short(next.tripId)}${next.isReplay ? ' replay' : ''}',
      null => null,
    };

String _key(Set<String> state) =>
    ([for (final id in state) _short(id)]..sort()).join(' ');

/// Each reachable state of the progression pack, by the trip finished last
/// (`-` for none, as at a launch with no first-finish times), with the next
/// trip written out by hand.
const _progressionNext = <String, Map<String, String>>{
  '': {'-': 'h1'},
  'h1': {'h1': 'h3', '-': 'h3'},
  'h1 h3': {'h3': 'h4', '-': 'h4'},
  // Line hay's regular trips done: ch2 names the story trip h2 mid-line,
  // which waits for ch2's goal, line gamaa (specs/014-m09-lines-vehicles,
  // FR-007), so Home goes on to gamaa.
  'h1 h3 h4': {'h4': 'g1', '-': 'g1'},
  'h1 h2 h3 h4': {'h2': 'g1', '-': 'g1'},
  'g1 h1 h3 h4': {'g1': 'g2', 'h4': 'g2', '-': 'g2'},
  'g1 h1 h2 h3 h4': {'g1': 'g2', 'h2': 'g2', '-': 'g2'},
  'g1 g2 h1 h3 h4': {'g2': 'h2', 'g1': 'h2', '-': 'h2'},
  // Every open line finished (souq needs the micro_old): a replay, on the
  // line played last.
  'g1 g2 h1 h2 h3 h4': {
    'g2': 'g1 replay',
    'g1': 'g1 replay',
    'h2': 'h1 replay',
    '-': 'h1 replay',
  },
};

/// The sample: line_hay's 01, 02 and the ch1 story trip 03; line_gamaa
/// needs the micro_old.
const _sampleNext = <String, Map<String, String>>{
  '': {'-': 'h1'},
  'h1': {'h1': 'h2'},
  'h3': {'h3': 'h1'},
  'h1 h3': {'h3': 'h2', 'h1': 'h2'},
  'h1 h2': {'h2': 'h3'},
  'h1 h2 h3': {'h3': 'h1 replay', 'h2': 'h1 replay'},
};

void _sweep(ContentSource c, Map<String, Map<String, String>> table) {
  final states = reachableStates(
    c,
    startable: (p, id) => tripUnlocked(c, p, id),
  );
  expect({for (final s in states) _key(s)}, table.keys.toSet());
  for (final state in states) {
    final key = _key(state);
    final p = player({for (final id in state) id: 1});
    for (final last in [null, ...state]) {
      final next = nextTrip(c, p, lastFinishedTripId: last);
      expect(next, isNotNull, reason: 'after "$key"');
      expect(
        tripPlayable(c, p, next!.tripId),
        isTrue,
        reason: '${next.tripId} after "$key" must be playable',
      );
      final want = table[key]![last == null ? '-' : _short(last)];
      if (want == null) continue;
      expect(
        _next(c, p, last: last == null ? null : _short(last)),
        want,
        reason: 'after "$key", last ${last ?? '-'}',
      );
    }
  }
}

void main() {
  final c = progressionContent();

  group('the rule steps', () {
    test('only startable trips: the locked story trip h2 waits', () {
      expect(_next(c, _played('h1')), 'h3');
    });

    test('unfinished means no star: a failed trip is played again', () {
      final p = player({_long('h1'): 1, _long('h3'): 0});
      expect(_next(c, p, last: 'h1'), 'h3');
    });

    test('the line played last first', () {
      expect(_next(c, _played('g1 h1 h3 h4'), last: 'g1'), 'g2');
      expect(_next(c, _played('g1 g2 h1 h3 h4'), last: 'h4'), 'h2');
    });

    test('then the earliest open line by order', () {
      expect(_next(c, _played('g1 g2 h1 h3 h4'), last: 'g2'), 'h2');
    });

    test('then the fewest best stars on the line played last', () {
      final p = player({
        for (final s in ['h1', 'h2', 'h3', 'h4']) _long(s): 3,
        _long('g1'): 3,
        _long('g2'): 1,
      });
      expect(_next(c, p, last: 'g1'), 'g2 replay');
    });

    test('the earliest by trip number on a tie', () {
      final p = player({
        _long('h1'): 2,
        _long('h2'): 1,
        _long('h3'): 1,
        _long('h4'): 2,
        _long('g1'): 3,
        _long('g2'): 3,
      });
      expect(_next(c, p, last: 'h4'), 'h2 replay');
    });

    test('index is 1-based in the line', () {
      final next = nextTrip(c, _played('g1 g2 h1 h3 h4'))!;
      expect(next.tripId, 'line_hay.02');
      expect(next.lineId, LineId.lineHay);
      expect(next.index, 2);
      expect(next.isReplay, isFalse);
    });

    test('null for a pack with no startable trip', () {
      final locked = sampleWith((json) {
        for (final line in entries(json, 'lines')) {
          line['unlock'] = {'kind': 'vehicle', 'vehicle_id': 'micro_new'};
        }
        for (final chapter in entries(json, 'chapters')) {
          chapter.remove('story_trip_id');
        }
      });
      expect(nextTrip(locked, PlayerProgress.empty), isNull);
    });
  });

  group('the line played last', () {
    test('a trip unknown to the pack counts as none', () {
      expect(
        nextTrip(
          c,
          _played('g1 g2 h1 h3 h4'),
          lastFinishedTripId: 'gone.01',
        )?.tripId,
        'line_hay.02',
      );
    });

    test('at launch: the trip with the latest first finish', () {
      const finish = TripProgress(bestStars: 1, plays: 1);
      expect(
        lastFirstCompleted({
          'line_hay.01': const TripProgress(
            bestStars: 1,
            plays: 1,
            firstCompletedAtMs: 10,
          ),
          'line_gamaa.01': const TripProgress(
            bestStars: 1,
            plays: 2,
            firstCompletedAtMs: 30,
          ),
          'line_hay.03': const TripProgress(
            bestStars: 1,
            plays: 1,
            firstCompletedAtMs: 20,
          ),
          // Restored from the server: no first-finish time.
          'line_hay.04': finish,
        }),
        'line_gamaa.01',
      );
    });

    test('none finished: none, so the first line by order', () {
      expect(lastFirstCompleted(const {}), isNull);
      expect(
        lastFirstCompleted(const {
          'line_hay.01': TripProgress(bestStars: 0, plays: 1),
        }),
        isNull,
      );
      expect(_next(c, PlayerProgress.empty), 'h1');
    });
  });

  group(
    'story trips wait for their chapter (specs/014-m09-lines-vehicles)',
    () {
      final draft = draftContent();
      String t(String line, int n) => '$line.${n.toString().padLeft(2, '0')}';
      final hay = {for (var n = 1; n <= 19; n++) t('line_hay', n): 1};

      test('line_gamaa.18 waits for the shabka; .19 comes first', () {
        final upTo17 = {for (var n = 1; n <= 17; n++) t('line_gamaa', n): 1};
        final p = player({...hay, ...upTo17}, {microOld});
        expect(
          nextTrip(draft, p, lastFinishedTripId: 'line_gamaa.17')?.tripId,
          'line_gamaa.19',
        );
        final bought = player({...hay, ...upTo17}, {microOld, shabka});
        expect(
          nextTrip(draft, bought, lastFinishedTripId: 'line_gamaa.17')?.tripId,
          'line_gamaa.18',
        );
      });

      test('line_hay.20 comes only after .01–.19', () {
        for (var n = 1; n <= 19; n++) {
          final p = player({for (var i = 1; i < n; i++) t('line_hay', i): 1});
          expect(
            nextTrip(draft, p)?.tripId,
            t('line_hay', n),
            reason: 'after ${n - 1}',
          );
        }
        expect(nextTrip(draft, player(hay))?.tripId, 'line_hay.20');
      });

      test('the sample\'s story trip line_hay.03 waits for ch1\'s goal', () {
        final sample = sampleContent();
        expect(
          nextTrip(sample, player({'line_hay.01': 1}))?.tripId,
          'line_hay.02',
        );
        expect(nextTrip(sample, player(hayDone))?.tripId, 'line_hay.03');
      });
    },
  );

  group('every reachable state', () {
    test('the sample pack', () => _sweep(sampleContent(), _sampleNext));
    test('the progression pack', () => _sweep(c, _progressionNext));
  });

  group('the first session', () {
    final tutorial = tutorialContent();

    FirstSession session(int finished) => FirstSession(
      FirstSessionFacts(
        flags: const FirstSessionFlags(),
        tutorialTrips: tutorialTripIds,
        progress: {
          for (final id in tutorialTripIds.take(finished))
            id: const TripProgress(
              bestStars: 1,
              plays: 1,
              firstCompletedAtMs: 1,
            ),
        },
        fuelLiters: 5,
        fuelUnlimited: false,
        tutorialGranted: false,
      ),
    );

    PlayerProgress progress(int finished) =>
        player({for (final id in tutorialTripIds.take(finished)) id: 1});

    for (var finished = 0; finished < tutorialTripIds.length; finished++) {
      test('$finished finished: tutorial trip ${finished + 1}', () {
        final next = homeNextTrip(
          tutorial,
          progress(finished),
          session(finished),
          lastFinishedTripId: null,
        );
        expect(next?.tripId, tutorialTripIds[finished]);
      });
    }

    test("after trip 5, FR-010's rule takes over", () {
      final done = tutorialTripIds.length;
      final p = progress(done);
      expect(session(done).nextTutorialTrip, isNull);
      expect(
        homeNextTrip(
          tutorial,
          p,
          session(done),
          lastFinishedTripId: tutorialTripIds.last,
        ),
        nextTrip(tutorial, p, lastFinishedTripId: tutorialTripIds.last),
      );
    });
  });
}
