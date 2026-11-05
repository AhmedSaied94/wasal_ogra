import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/ads/domain/piggy_plan.dart';

// The piggy's asks after the reward (specs/018-m11-ads, research R12, T022).

void main() {
  test('waits of 1, 2 and 4 s ask at 1, 3 and 7 s', () {
    expect(piggyWaitsMs, [1000, 2000, 4000]);
    var at = 0;
    final asks = [for (final wait in piggyWaitsMs) at += wait];
    expect(asks, [1000, 3000, 7000]);
  });

  test('three NotYet give up', () {
    var outcome = PiggyStep.asking;
    for (var i = 0; i < piggyWaitsMs.length; i++) {
      outcome = piggyStep(PiggyAnswer.notYet, ask: i + 1);
    }
    expect(outcome, PiggyStep.gaveUp);
  });

  test('NotYet before the last ask keeps asking', () {
    expect(piggyStep(PiggyAnswer.notYet, ask: 1), PiggyStep.asking);
    expect(piggyStep(PiggyAnswer.notYet, ask: 2), PiggyStep.asking);
  });

  test('granted at any ask is granted; refused is refused', () {
    for (var ask = 1; ask <= 3; ask++) {
      expect(piggyStep(PiggyAnswer.granted, ask: ask), PiggyStep.granted);
      expect(piggyStep(PiggyAnswer.refused, ask: ask), PiggyStep.refused);
    }
  });
}
