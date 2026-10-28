import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/onboarding/domain/tutorial_coach.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/domain/bubble_queue.dart';
import 'package:wassal/features/trip/domain/presentation_memory.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/trip.dart';
import '../../../helpers/tutorial_content.dart';

// The coach in the trip (specs/012-m07-onboarding/contracts/coach.md):
// `TripModel.coach` from the trip's lesson, hints held back while a step
// shows, the memory per run, and بلية's bubble under the two-bubble limit.

const _frame = Duration(milliseconds: 33);

/// Runs [controller]'s clock until [until] holds on its model.
TripModel _runUntil(TripController controller, bool Function(TripModel) until) {
  for (var i = 0; i < 6000; i++) {
    final model = controller.model;
    if (until(model)) return model;
    if (controller.phase != TripPhase.running) break;
    controller.advance(_frame);
  }
  fail('never reached at ${controller.view?.tMs} ms, ${controller.phase}');
}

Future<TripController> _open(
  TestEconomy economy,
  String tripId, {
  int? lesson,
  bool disposeAtTearDown = true,
}) async {
  final controller = testController(
    economy,
    coachLesson: () => lesson,
    disposeAtTearDown: disposeAtTearDown,
  );
  await controller.open(tripId);
  expect(controller.phase, TripPhase.running);
  return controller;
}

void main() {
  group('TripModel.coach', () {
    test('only when the trip has a lesson', () async {
      final economy = await testEconomy(content: tutorialContent());
      final plain = await _open(economy, 'line_hay.02');
      _runUntil(plain, (m) {
        expect(m.coach, isNull);
        return plain.engine!.state.passenger('p1')!.isOwed;
      });
      plain.pause(PauseReason.button);
      await plain.leave();

      final economy2 = await testEconomy(content: tutorialContent());
      final coached = await _open(economy2, 'line_hay.02', lesson: 1);
      final model = _runUntil(coached, (m) => m.coach != null);
      expect(model.coach?.lessonStep, CoachStepId.giveChange);
    });

    test('no hint while a step shows', () async {
      final economy = await testEconomy(content: tutorialContent());
      final controller = await _open(economy, 'line_hay.03', lesson: 2);
      var steps = 0;
      _runUntil(controller, (m) {
        if (m.coach != null) {
          steps++;
          expect(m.view?.hint, isNull);
        }
        return controller.phase != TripPhase.running;
      });
      expect(steps, greaterThan(0));
    });

    test('the clock runs during a step', () async {
      final economy = await testEconomy(content: tutorialContent());
      final controller = await _open(economy, 'line_hay.02', lesson: 1);
      final at = _runUntil(controller, (m) => m.coach != null).view!.tMs;
      controller.advance(_frame * 10);
      expect(controller.model.coach, isNotNull);
      expect(controller.view!.tMs, greaterThan(at));
    });

    test('lesson 0: a tap the scrim takes ends the step', () async {
      final economy = await testEconomy(content: tutorialContent());
      final controller = await _open(economy, 'line_hay.01', lesson: 0);
      final model = _runUntil(controller, (m) => m.coach != null);
      expect(model.coach?.endsOnAnyTap, isTrue);
      controller.coachTapped();
      expect(controller.model.coach, isNull);
      _runUntil(controller, (m) {
        expect(m.coach, isNull);
        return controller.phase != TripPhase.running;
      });
    });

    test('the memory is per run: a new open coaches again', () async {
      final economy = await testEconomy(content: tutorialContent());
      final first = await _open(economy, 'line_hay.02', lesson: 1);
      _runUntil(first, (m) => m.coach != null);
      first
        ..pick(100)
        ..pick(100)
        ..pick(100)
        ..send('p1');
      expect(first.model.coach, isNull);
      first.pause(PauseReason.button);
      await first.leave();
      await settle();

      final again = await _open(economy, 'line_hay.02', lesson: 1);
      expect(
        _runUntil(again, (m) => m.coach != null).coach?.lessonStep,
        CoachStepId.giveChange,
      );
    });

    test('after a kill and resume, the open step comes back', () async {
      final economy = await testEconomy(content: tutorialContent());
      final killed = await _open(
        economy,
        'line_hay.02',
        lesson: 1,
        disposeAtTearDown: false,
      );
      final before = _runUntil(killed, (m) => m.coach != null).coach;
      killed.pause(PauseReason.lifecycle);
      await settle();

      final resumed = testController(economy, coachLesson: () => 1);
      await resumed.open('line_hay.02');
      resumed.resume();
      expect(_runUntil(resumed, (m) => m.coach != null).coach, before);
    });
  });

  group("بلية's bubble and the two-bubble limit", () {
    const minMs = 4000;
    const step = (source: CoachStepId.giveChange, line: TapRiderLine());

    PresentationMemory talking(List<String> riders, {int at = 0}) =>
        PresentationMemory(
          bubbles: BubbleQueue(
            visible: [
              for (final r in riders)
                BubbleView(
                  passengerId: r,
                  text: r,
                  style: BubbleStyle.plain,
                  shownAtMs: at,
                ),
            ],
          ),
        );

    test('with two riders talking, the step waits for its bubble', () {
      var memory = talking(['a', 'b'])
          .belyaAt(step, tMs: 0, bubbleMinMs: minMs);
      expect(memory.belya, isNull);
      memory = memory
          .at(minMs, bubbleMinMs: minMs)
          .belyaAt(step, tMs: minMs, bubbleMinMs: minMs);
      expect(memory.belya?.line, const TapRiderLine());
      expect(memory.belya?.shownAtMs, minMs);
    });

    test('while it shows, a second rider line waits', () {
      var memory = talking(['a']).belyaAt(step, tMs: 0, bubbleMinMs: minMs);
      expect(memory.belya, isNotNull);
      memory = memory.update(const [], const [], tMs: 33, bubbleMinMs: minMs);
      memory = PresentationMemory(
        bubbles: memory.bubbles.push(
          const WaitingLine(
            passengerId: 'b',
            text: 'b',
            style: BubbleStyle.plain,
            emittedAtMs: 33,
          ),
        ),
        belya: memory.belya,
      ).at(66, bubbleMinMs: minMs);
      expect(memory.bubbles.visible.map((b) => b.passengerId), ['a']);
      expect(memory.bubbles.waiting.map((w) => w.passengerId), ['b']);
    });

    test('a step that ends early keeps the bubble its minimum time', () {
      var memory = PresentationMemory.empty.belyaAt(
        step,
        tMs: 0,
        bubbleMinMs: minMs,
      );
      memory = memory.belyaAt(null, tMs: 1000, bubbleMinMs: minMs);
      expect(memory.belya?.line, const TapRiderLine());
      memory = memory.belyaAt(null, tMs: minMs, bubbleMinMs: minMs);
      expect(memory.belya, isNull);
    });

    test('the next bubble waits for the one showing', () {
      const next = (source: CoachStepId.stopNear, line: StopNearLine('x'));
      var memory = PresentationMemory.empty.belyaAt(
        step,
        tMs: 0,
        bubbleMinMs: minMs,
      );
      memory = memory.belyaAt(next, tMs: 1000, bubbleMinMs: minMs);
      expect(memory.belya?.line, const TapRiderLine());
      memory = memory.belyaAt(next, tMs: minMs, bubbleMinMs: minMs);
      expect(memory.belya?.line, const StopNearLine('x'));
    });

    test('a hint follows the same rules', () {
      const hint = HintView(key: 'tripHintOwed', targetPassengerId: 'a');
      final wish = (source: hint.key, line: hint);
      var memory = talking(['a', 'b'])
          .belyaAt(wish, tMs: 0, bubbleMinMs: minMs);
      expect(memory.belya, isNull);
      memory = memory
          .at(minMs, bubbleMinMs: minMs)
          .belyaAt(wish, tMs: minMs, bubbleMinMs: minMs);
      expect(memory.belya?.line, hint);
    });
  });
}
