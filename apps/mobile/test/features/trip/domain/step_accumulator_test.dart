import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/trip/domain/step_accumulator.dart';

void main() {
  test('16 ms frames step every second or third frame', () {
    final acc = StepAccumulator();
    final steps = [
      for (var i = 0; i < 60; i++) acc.add(const Duration(milliseconds: 16)),
    ];
    expect(steps.every((s) => s <= 1), isTrue);
    expect(steps.where((s) => s == 1).length, 960 ~/ engineStepMs);
    // Between two steps, one or two frames without.
    int? gap;
    for (final s in steps) {
      if (s == 1) {
        if (gap != null) expect(gap, inInclusiveRange(1, 2));
        gap = 0;
      } else if (gap != null) {
        gap++;
      }
    }
  });

  test('a 1 s frame runs at most 10 steps and drops the rest', () {
    final acc = StepAccumulator();
    expect(acc.add(const Duration(seconds: 1)), maxStepsPerFrame);
    expect(acc.alpha, 0);
    expect(acc.add(const Duration(milliseconds: 16)), 0);
  });

  test('alpha is the remainder over one step', () {
    final acc = StepAccumulator()..add(const Duration(milliseconds: 50));
    expect(acc.alpha, closeTo(17 / 33, 1e-9));
    acc.clear();
    expect(acc.alpha, 0);
    expect(acc.add(const Duration(milliseconds: 32)), 0);
  });

  test('a 0 ms first frame does nothing', () {
    final acc = StepAccumulator();
    expect(acc.add(Duration.zero), 0);
    expect(acc.alpha, 0);
  });
}
