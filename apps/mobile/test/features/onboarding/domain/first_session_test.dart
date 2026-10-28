import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/account/domain/account.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/features/onboarding/domain/first_session.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/tutorial_content.dart';

// The first session's answers (specs/012-m07-onboarding/contracts/
// first-session.md "Answers", research R1–R4, R10–R12): pure, from stored
// facts.

const _trips = tutorialTripIds;

const _finished = TripProgress(
  bestStars: 2,
  plays: 1,
  bestTimeMs: 60000,
  firstCompletedAtMs: 1000,
);
const _failed = TripProgress(bestStars: 0, plays: 1);

/// A restored trip: the server's state sends no first-finish time.
const _restoredFinish = TripProgress(bestStars: 3, plays: 2, bestTimeMs: 5);

FirstSession _session({
  FirstSessionFlags flags = const FirstSessionFlags(),
  List<String> tutorialTrips = _trips,
  Map<String, TripProgress> progress = const {},
  String? unfinishedTripId,
  int liters = 5,
  bool unlimited = false,
  bool granted = false,
  String? name,
  bool nameRefused = false,
  String? opening = 'opening',
  Map<String, String> afterTrip = const {'line_hay.03': 'the_stand'},
  bool coachEverywhere = false,
}) => FirstSession(
  FirstSessionFacts(
    flags: flags,
    tutorialTrips: tutorialTrips,
    progress: progress,
    unfinishedTripId: unfinishedTripId,
    fuelLiters: liters,
    fuelUnlimited: unlimited,
    tutorialGranted: granted,
    displayName: name,
    nameRefused: nameRefused,
    openingSceneId: opening,
    afterTripScenes: afterTrip,
    coachEverywhere: coachEverywhere,
  ),
);

Map<String, TripProgress> _done(int n) => {
  for (final id in _trips.take(n)) id: _finished,
};

void main() {
  group('launchTarget', () {
    for (final outcome in [
      FirstOpenOutcome.newPlayer,
      FirstOpenOutcome.offline,
      FirstOpenOutcome.timedOut,
      FirstOpenOutcome.notFirstOpen,
    ]) {
      test('${outcome.name}: the opening scene first', () {
        expect(_session().launchTarget(outcome), '/onboarding/intro');
      });
    }

    test('restored: Home, whatever the flags say', () {
      expect(_session().launchTarget(FirstOpenOutcome.restored), '/home');
    });

    test('the Name card once the opening is done', () {
      const flags = FirstSessionFlags(openingDoneAtMs: 5);
      expect(
        _session(flags: flags).launchTarget(FirstOpenOutcome.notFirstOpen),
        '/onboarding/name',
      );
    });

    test('trip 1 once a name is saved (FR-002)', () {
      const flags = FirstSessionFlags(openingDoneAtMs: 5);
      expect(
        _session(
          flags: flags,
          name: 'Hamada',
        ).launchTarget(FirstOpenOutcome.notFirstOpen),
        '/trip/line_hay.01',
      );
    });

    test('a pack without an opening scene starts at the Name card', () {
      expect(
        _session(opening: null).launchTarget(FirstOpenOutcome.newPlayer),
        '/onboarding/name',
      );
    });

    test('once a trip has started: Home (FR-003)', () {
      expect(
        _session(progress: {'line_hay.01': _failed})
            .launchTarget(FirstOpenOutcome.notFirstOpen),
        '/home',
      );
      expect(
        _session(unfinishedTripId: 'line_hay.01')
            .launchTarget(FirstOpenOutcome.notFirstOpen),
        '/home',
      );
    });

    test('a tutorial start the step recorded: Home, with no progress', () {
      // A refused or replaced trip_start leaves no progress row, but the
      // player has driven (contracts/first-session.md "hasStartedATrip").
      expect(
        _session(flags: const FirstSessionFlags(stepReached: 2))
            .launchTarget(FirstOpenOutcome.notFirstOpen),
        '/home',
      );
      expect(
        _session(
          flags: const FirstSessionFlags(openingDoneAtMs: 5, stepReached: 1),
          name: 'Hamada',
        ).launchTarget(FirstOpenOutcome.notFirstOpen),
        '/trip/line_hay.01',
        reason: 'step 1 is the opening, not a trip',
      );
    });

    test('a pack with no tutorial line: Home after the name', () {
      expect(
        _session(
          tutorialTrips: const [],
          name: 'Hamada',
          flags: const FirstSessionFlags(openingDoneAtMs: 5),
        ).launchTarget(FirstOpenOutcome.newPlayer),
        '/home',
      );
    });
  });

  group('beforeStart', () {
    test('nothing on a plain start', () {
      expect(_session().beforeStart('line_hay.02'), isNull);
    });

    test('a due scene comes first, until it is seen', () {
      const flags = FirstSessionFlags(scenesDue: ['the_stand']);
      expect(
        _session(flags: flags).beforeStart('line_hay.04'),
        const DueScene('the_stand'),
      );
      const seen = FirstSessionFlags(
        scenesDue: ['the_stand'],
        scenesSeen: ['the_stand'],
      );
      expect(_session(flags: seen).beforeStart('line_hay.04'), isNull);
    });

    test('a due scene wins over the fuel lesson', () {
      const flags = FirstSessionFlags(scenesDue: ['the_stand']);
      expect(
        _session(flags: flags, progress: _done(4)).beforeStart('line_hay.05'),
        const DueScene('the_stand'),
      );
    });

    test('the fuel lesson before trip 5 is first played', () {
      expect(
        _session(progress: _done(4)).beforeStart('line_hay.05'),
        const FuelLessonDue(),
      );
      expect(
        _session(progress: {..._done(4), 'line_hay.05': _failed})
            .beforeStart('line_hay.05'),
        isNull,
        reason: 'played once already',
      );
    });

    test('the fuel lesson for any tutorial trip on an empty tank', () {
      expect(
        _session(liters: 0).beforeStart('line_hay.02'),
        const FuelLessonDue(),
      );
      expect(
        _session(liters: 0, unlimited: true).beforeStart('line_hay.02'),
        isNull,
        reason: 'an unlimited window needs no fuel',
      );
    });

    test('never once granted, or once done, or for another trip', () {
      expect(
        _session(progress: _done(4), granted: true).beforeStart('line_hay.05'),
        isNull,
      );
      const done = FirstSessionFlags(fuelLessonDoneAtMs: 9);
      expect(
        _session(flags: done, liters: 0).beforeStart('line_hay.02'),
        isNull,
      );
      expect(_session(liters: 0).beforeStart('line_gamaa.01'), isNull);
    });

    test('a three-trip tutorial has no fuel lesson but on an empty tank', () {
      final three = _trips.take(3).toList();
      expect(
        _session(
          tutorialTrips: three,
          progress: _done(2),
        ).beforeStart('line_hay.03'),
        isNull,
      );
      expect(
        _session(tutorialTrips: three, liters: 0).beforeStart('line_hay.03'),
        const FuelLessonDue(),
      );
    });
  });

  group('onArrivalAtHome', () {
    test('a due scene, or nothing', () {
      expect(_session().onArrivalAtHome(), isNull);
      const flags = FirstSessionFlags(scenesDue: ['the_stand']);
      expect(
        _session(flags: flags).onArrivalAtHome(),
        const DueScene('the_stand'),
      );
    });
  });

  // contracts/name.md "The re-ask".
  group('askName', () {
    test('a refused name', () {
      expect(
        _session(name: null, nameRefused: true, progress: _done(1)).askName,
        isTrue,
      );
    });

    test('no name after a trip has started', () {
      expect(_session(progress: {_trips[0]: _failed}).askName, isTrue);
      expect(_session(unfinishedTripId: _trips[0]).askName, isTrue);
    });

    test('not before a trip: the Name card asks', () {
      expect(_session().askName, isFalse);
    });

    test('not with a name', () {
      expect(_session(name: 'حمادة', progress: _done(5)).askName, isFalse);
    });
  });

  group('nextAfterResult', () {
    test('along the five trips, then Home', () {
      for (var i = 0; i < 4; i++) {
        expect(
          _session(progress: _done(i + 1)).nextAfterResult(_trips[i]),
          '/trip/${_trips[i + 1]}',
        );
      }
      expect(_session(progress: _done(5)).nextAfterResult(_trips[4]), '/home');
    });

    test('a failed trip is next again', () {
      expect(
        _session(progress: {..._done(1), 'line_hay.02': _failed})
            .nextAfterResult('line_hay.02'),
        '/trip/line_hay.02',
      );
    });

    test('the first unfinished trip, even after a later one', () {
      expect(
        _session(progress: {'line_hay.01': _finished, 'line_hay.03': _finished})
            .nextAfterResult('line_hay.03'),
        '/trip/line_hay.02',
      );
    });

    test('Home after a trip outside the tutorial', () {
      expect(_session().nextAfterResult('line_gamaa.01'), '/home');
    });
  });

  group('the state', () {
    test('inFirstSession: a trip started and the tutorial not done', () {
      expect(_session().inFirstSession, isFalse);
      expect(_session(progress: _done(1)).inFirstSession, isTrue);
      expect(_session(unfinishedTripId: 'line_hay.01').inFirstSession, isTrue);
      expect(_session(progress: _done(5)).inFirstSession, isFalse);
    });

    test('tutorialDone with five tutorial trips, and with three', () {
      expect(_session(progress: _done(4)).tutorialDone, isFalse);
      expect(_session(progress: _done(5)).tutorialDone, isTrue);
      final three = _trips.take(3).toList();
      expect(
        _session(tutorialTrips: three, progress: _done(3)).tutorialDone,
        isTrue,
      );
    });

    test('a finish from the server\'s state counts (FR-039)', () {
      expect(
        _session(progress: {for (final id in _trips) id: _restoredFinish})
            .tutorialDone,
        isTrue,
      );
    });

    test('boostersLocked until the tutorial is done', () {
      expect(_session().boostersLocked, isTrue);
      expect(_session(progress: _done(4)).boostersLocked, isTrue);
      expect(_session(progress: _done(5)).boostersLocked, isFalse);
    });

    test('stepReached is the stored value', () {
      expect(_session().stepReached, 0);
      expect(
        _session(flags: const FirstSessionFlags(stepReached: 6)).stepReached,
        6,
      );
    });
  });

  group('coachFor', () {
    test('each tutorial trip by its lesson, until its first finish', () {
      for (final (i, id) in _trips.indexed) {
        expect(_session().coachFor(id), i, reason: id);
      }
      expect(_session(progress: _done(2)).coachFor('line_hay.02'), isNull);
      expect(
        _session(progress: {'line_hay.02': _failed}).coachFor('line_hay.02'),
        1,
        reason: 'a failed run is coached again',
      );
      expect(
        _session(progress: {'line_hay.01': _restoredFinish})
            .coachFor('line_hay.01'),
        isNull,
      );
    });

    test('never outside the tutorial', () {
      expect(_session().coachFor('line_gamaa.01'), isNull);
    });

    test('the debug switch coaches a finished tutorial trip (R21)', () {
      expect(
        _session(
          progress: _done(5),
          coachEverywhere: true,
        ).coachFor('line_hay.03'),
        2,
      );
      expect(_session(coachEverywhere: true).coachFor('line_gamaa.01'), isNull);
    });
  });

  group('the steps a start writes (R12)', () {
    test('trips 1–3: 2–4; trip 4: 7; trip 5: 8; others none', () {
      expect(
        [for (final id in _trips) stepOnStart(_trips, id)],
        [2, 3, 4, 7, 8],
      );
      expect(stepOnStart(_trips, 'line_gamaa.01'), isNull);
    });
  });

  group('scenesDueAfter', () {
    test('a first finish of a trip a scene plays after', () {
      expect(_session().afterTripScene('line_hay.03'), 'the_stand');
      expect(_session().afterTripScene('line_hay.02'), isNull);
    });
  });

  group('from the pack (R3, R5)', () {
    test("the tutorial: the start line's first five trips by number", () {
      expect(tutorialTripsOf(tutorialContent()), _trips);
    });

    test('the sample has three', () {
      expect(tutorialTripsOf(sampleContent()), _trips.take(3));
    });

    test("the scenes that play by themselves, from chapter 1", () {
      final scenes = sessionScenesOf(sampleContent());
      expect(scenes.opening, 'opening');
      expect(scenes.afterTrip, {'line_hay.03': 'the_stand'});
    });

    test('a pack with no tutorial line has no tutorial', () {
      expect(tutorialTripsOf(_NoStartLine(sampleContent())), isEmpty);
    });
  });
}

/// [inner] with every line unlocked by a vehicle instead of at the start.
final class _NoStartLine implements ContentSource {
  _NoStartLine(this.inner);

  final ContentSource inner;

  @override
  List<Line> get lines => [
    for (final line in inner.lines)
      Line.fromJson({
        ...line.toJson(),
        'unlock': {'kind': 'vehicle', 'vehicle_id': 'micro_old'},
      }),
  ];

  @override
  List<TripDefinition> tripsOf(LineId line) => inner.tripsOf(line);

  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
