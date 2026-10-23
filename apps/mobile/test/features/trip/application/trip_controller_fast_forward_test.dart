import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/domain/step_accumulator.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/trip.dart';

// Fast-forward (trip_engine RULES.md §16): once nothing is left for the
// player, the trip clock runs `settledSpeedUp` times faster to the end of
// the line. The engine and the result don't change, and a bubble stays as
// long on screen.

const _frame = Duration(milliseconds: engineStepMs);

/// `event__open_road_clamped`: p1 and p2 pay exact fares, nothing is left
/// after the open road at 15 s, p1 gets off at kobri (23 s) and p2 at the
/// end of the line (33 s).
const _fixture = 'event__open_road_clamped';

Future<TripController> _open() async {
  final f = loadFixture(_fixture);
  final c = testController(
    await testEconomy(),
    fixed: FixedTrip(definition: f.definition, params: f.params, seed: f.seed),
  );
  await c.open('line_gamaa.01');
  return c;
}

void _frames(TripController c, int count) {
  for (var i = 0; i < count; i++) {
    c.advance(_frame);
  }
}

/// Advances [c] a frame at a time until the clock runs faster.
void _untilFastForward(TripController c) {
  for (var t = 0; t < 60000 && !c.view!.fastForward; t += engineStepMs) {
    c.advance(_frame);
  }
  expect(c.view!.fastForward, isTrue);
}

void main() {
  test('real time while something is left, then four times faster', () async {
    final c = await _open();
    final start = c.engine!.state.tMs;
    _frames(c, 10);
    expect(c.engine!.state.tMs, start + 330);
    expect(c.view!.fastForward, isFalse);

    _untilFastForward(c);
    expect(c.engine!.isSettled, isTrue);
    final at = c.engine!.state.tMs;
    _frames(c, 10);
    expect(settledSpeedUp, 4);
    expect(c.engine!.state.tMs, at + 330 * settledSpeedUp);
  });

  test('the trip ends at its last station with the same result', () async {
    final c = await _open();
    _untilFastForward(c);
    runOut(c);
    expect(
      c.engine!.result!.toJson(),
      loadFixture(_fixture).expectedResult.toJson(),
    );
  });

  test('a pause stops it, and resuming brings it back', () async {
    final c = await _open();
    _untilFastForward(c);
    c.pause(PauseReason.button);
    expect(c.view!.fastForward, isFalse);
    final at = c.engine!.state.tMs;
    _frames(c, 10);
    expect(c.engine!.state.tMs, at);
    c.resume();
    expect(c.view!.fastForward, isTrue);
  });

  test('a tap that opens a claim brings back real time', () async {
    final c = await _open();
    _untilFastForward(c);
    c.tap('p2');
    expect(c.engine!.state.claims.keys, ['p2']);
    expect(c.view!.fastForward, isFalse);
    c.answerClaim('p2', insist: false);
    expect(c.view!.fastForward, isTrue);
  });

  test('a bubble keeps its time on screen', () async {
    final c = await _open();
    _untilFastForward(c);
    final from = c.engine!.state.tMs;
    final minMs = c.session!.facts.bubbleMinMs;
    while (c.phase == TripPhase.running &&
        !c.view!.bubbles.any((b) => b.shownAtMs >= from)) {
      c.advance(_frame);
    }
    final bubble = c.view!.bubbles.firstWhere((b) => b.shownAtMs >= from);
    // Past its usual time on the trip clock, it is still up.
    while (c.phase == TripPhase.running &&
        c.engine!.state.tMs < bubble.shownAtMs + minMs + 330) {
      c.advance(_frame);
    }
    expect(c.phase, TripPhase.running);
    expect(c.view!.bubbles, contains(bubble));
  });
}
