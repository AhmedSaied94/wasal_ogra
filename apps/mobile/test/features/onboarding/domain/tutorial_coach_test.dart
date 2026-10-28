import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/features/onboarding/domain/tutorial_coach.dart';
import 'package:wassal/features/trip/domain/cues.dart';
import 'package:wassal/features/trip/domain/presentation_memory.dart';
import 'package:wassal/features/trip/domain/speech.dart';
import 'package:wassal/features/trip/domain/trip_facts.dart';

import '../../../helpers/trip.dart';
import '../../../helpers/tutorial_content.dart';

// The coach's lessons (specs/012-m07-onboarding/contracts/coach.md
// "Lessons"), one group per row, from states the real engine reaches on
// the tutorial fixture's trips.

const _bubbleMinMs = 4500;

/// One tutorial trip on the engine, its screen memory folded in as the
/// controller folds it, and the coach's memory for [lesson].
final class _Run {
  _Run(String tripId, this.lesson)
    : definition = tutorialTrip(tripId),
      engine = TripEngine.start(
        tutorialTrip(tripId),
        bundledParams(tutorialTrip(tripId).lineId),
        seed: tutorialTrip(tripId).seed,
      ) {
    facts = factsFor(definition, withLine: false, bubbleMinMs: _bubbleMinMs);
  }

  final TripDefinition definition;
  final TripEngine engine;
  final int lesson;
  late final TripFacts facts;
  PresentationMemory presentation = PresentationMemory.empty;
  CoachMemory memory = CoachMemory.empty;

  TripState get state => engine.state;

  late final _speech = SpeechResolver(
    pool: tutorialContent().speechPool,
    piasters: (p) => '$p',
    station: (id) => id,
  );

  void _fold(TripState before, List<DomainEvent> events) {
    final cues = mapCues(
      events,
      before: before,
      after: engine.state,
      facts: facts,
      speech: _speech,
    );
    presentation = presentation.update(
      events,
      cues,
      tMs: engine.state.tMs,
      bubbleMinMs: _bubbleMinMs,
    );
  }

  /// The coach at this moment, its memory kept.
  CoachView? coach() {
    final result = TutorialCoach.step(
      CoachInput(
        lesson: lesson,
        state: state,
        warning: presentation.warning,
        memory: memory,
        bubbleMinMs: _bubbleMinMs,
        destinations: facts.destinations,
      ),
    );
    memory = result.memory;
    return result.view;
  }

  /// Steps the engine, asking the coach each step, until [until] holds.
  CoachView? runUntil(bool Function(CoachView? view) until) {
    for (var i = 0; i < 10000; i++) {
      final view = coach();
      if (until(view)) return view;
      if (state.status != TripStatus.running) break;
      final before = state;
      _fold(before, engine.step());
    }
    fail('never reached: ${state.tMs} ms, ${state.status}');
  }

  void apply(Command command) {
    final before = state;
    final outcome = engine.apply(command);
    expect(outcome, isA<Accepted>(), reason: '$command');
    _fold(before, (outcome as Accepted).events);
  }

  PassengerState passenger(String id) => state.passenger(id)!;
}

void main() {
  group('lesson 0 (trip 1): fareArrived', () {
    test('starts on the first fare that reached the tray', () {
      final run = _Run('line_hay.01', 0);
      final view = run.runUntil((v) => v != null);
      expect(run.state.passengers.any((p) => p.paidIn > 0), isTrue);
      expect(
        view,
        const CoachView(
          lessonStep: CoachStepId.fareArrived,
          targets: [TrayTarget()],
          line: FareArrivedLine(),
          endsOnAnyTap: true,
        ),
      );
    });

    test('a tap anywhere ends it, and it never comes back', () {
      final run = _Run('line_hay.01', 0);
      final view = run.runUntil((v) => v != null);
      run.memory = TutorialCoach.tapped(run.memory, view);
      expect(run.coach(), isNull);
      expect(run.memory.done, {CoachStepId.fareArrived});
      run.runUntil((v) {
        expect(v, isNull);
        return run.state.status != TripStatus.running;
      });
    });

    test('it ends by itself after the bubble time', () {
      final run = _Run('line_hay.01', 0);
      run.runUntil((v) => v != null);
      final shownAt = run.memory.shownAtMs[CoachStepId.fareArrived]!;
      run.runUntil((v) => v == null);
      expect(run.state.tMs - shownAt, greaterThanOrEqualTo(_bubbleMinMs));
      expect(run.memory.done, {CoachStepId.fareArrived});
    });
  });

  group('lesson 1 (trip 2): giveChange', () {
    test('the first owed passenger: the «١» cell, ×3, then the rider', () {
      final run = _Run('line_hay.02', 1);
      var view = run.runUntil((v) => v != null);
      expect(run.passenger('p1').balance, 300);
      expect(
        view,
        const CoachView(
          lessonStep: CoachStepId.giveChange,
          targets: [TrayCellTarget(100), PassengerTarget('p1')],
          line: GiveChangeLine(300, coin: 100, count: 3),
        ),
      );
      run
        ..apply(const PickFromTray(100))
        ..apply(const PickFromTray(100));
      view = run.coach();
      expect(view?.targets.first, const TrayCellTarget(100));
      expect(view?.line, const GiveChangeLine(300, coin: 100, count: 3));
      run.apply(const PickFromTray(100));
      view = run.coach();
      expect(
        view,
        const CoachView(
          lessonStep: CoachStepId.giveChange,
          targets: [PassengerTarget('p1')],
          line: TapRiderLine(),
        ),
      );
    });

    test('ends when a change token targets the rider, and stays done', () {
      final run = _Run('line_hay.02', 1);
      run.runUntil((v) => v != null);
      run
        ..apply(const PickFromTray(100))
        ..apply(const PickFromTray(100))
        ..apply(const PickFromTray(100))
        ..apply(const SendHand('p1'));
      expect(run.coach(), isNull);
      expect(run.memory.done, {CoachStepId.giveChange});
      run.runUntil((v) {
        expect(v, isNull, reason: 'one step per lesson');
        return run.state.status != TripStatus.running;
      });
    });

    test('no single coin pays: the tray and the general line', () {
      // Trip 3's second rider owes 13: no coin pays it alone.
      final run = _Run('line_hay.03', 1);
      run.runUntil((v) => v != null);
      run
        ..apply(const PickFromTray(100))
        ..apply(const PickFromTray(100))
        ..apply(const PickFromTray(100))
        ..apply(const SendHand('p1'));
      run.memory = CoachMemory.empty;
      final view = run.runUntil(
        (v) => v?.targets.contains(const PassengerTarget('p2')) ?? false,
      );
      expect(run.passenger('p2').balance, 1300);
      expect(
        view,
        const CoachView(
          lessonStep: CoachStepId.giveChange,
          targets: [TrayTarget(), PassengerTarget('p2')],
          line: GiveChangeLine(1300),
        ),
      );
    });

    test('a step ends silently when its rider leaves unpaid', () {
      final run = _Run('line_hay.02', 1);
      run.runUntil((v) => v != null);
      run.runUntil((v) => v == null);
      expect(run.passenger('p1').presence, isNot(Presence.aboard));
      expect(run.memory.done, {CoachStepId.giveChange});
    });

    test('a rebuilt state brings the open step back', () {
      final run = _Run('line_hay.02', 1);
      final before = run.runUntil((v) => v != null);
      run.memory = CoachMemory.empty;
      expect(run.coach(), before);
    });
  });

  group('lesson 2 (trip 3): stopNear', () {
    test('the countdown first, then as lesson 1; ends at the stop', () {
      final run = _Run('line_hay.03', 2);
      var view = run.runUntil((v) => v != null);
      expect(view?.lessonStep, CoachStepId.stopNear);
      expect(view?.targets, [const StationCountdownTarget()]);
      expect(view?.line, const StopNearLine('matbaa'));
      final shownAt = run.memory.shownAtMs[CoachStepId.stopNear]!;
      view = run.runUntil((v) => v?.targets.first is! StationCountdownTarget);
      expect(run.state.tMs - shownAt, greaterThanOrEqualTo(_bubbleMinMs));
      expect(view?.targets, [
        const TrayCellTarget(100),
        const PassengerTarget('p1'),
      ]);
      expect(view?.line, const GiveChangeLine(300, coin: 100, count: 3));
      run.runUntil((v) => v == null);
      expect(run.memory.done, {CoachStepId.stopNear});
    });

    test('nothing before a stop is near, though a rider is owed', () {
      final run = _Run('line_hay.03', 2);
      run.runUntil((v) => run.passenger('p1').isOwed);
      expect(run.coach(), isNull);
    });
  });

  group('lesson 3 (trip 4): wakeSleeper', () {
    test('the asleep rider; ends once awake', () {
      final run = _Run('line_hay.04', 3);
      final view = run.runUntil((v) => v != null);
      expect(
        view,
        const CoachView(
          lessonStep: CoachStepId.wakeSleeper,
          targets: [PassengerTarget('p1')],
          line: WakeSleeperLine(),
        ),
      );
      expect(run.passenger('p1').alertness, Alertness.asleep);
      run.apply(const Tap('p1'));
      expect(run.coach(), isNull);
      expect(run.memory.done, {CoachStepId.wakeSleeper});
    });
  });

  group('lesson 4 (trip 5)', () {
    test('no in-trip step', () {
      final run = _Run('line_hay.05', 4);
      run.runUntil((v) {
        expect(v, isNull);
        return run.state.status != TripStatus.running;
      });
    });
  });

  group('outside the tutorial', () {
    test('a lesson out of range coaches nothing', () {
      for (final lesson in [-1, 5]) {
        final run = _Run('line_hay.02', lesson);
        run.runUntil((v) {
          expect(v, isNull);
          return run.state.status != TripStatus.running;
        });
      }
    });
  });
}
