// The public `Xorshift32` (specs/015-m10-apartment-story, research R15): the
// rider comments seed a fresh generator from the trip seed, so the engine's
// own PRNG state is never touched. The vectors are `src/prng.dart`'s own
// test's, so the export is the same algorithm.
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

void main() {
  test('seed 1 draws src/prng.dart\'s first value', () {
    expect(const Xorshift32(1).next().$1, 270369);
  });

  test('seed 521288629 draws src/prng.dart\'s first value', () {
    expect(const Xorshift32(521288629).next().$1, 1425164135);
  });

  test('seed 0xDEADBEEF draws a value in 1..2^32-1', () {
    expect(
      const Xorshift32(0xDEADBEEF).next().$1,
      inInclusiveRange(1, 0xFFFFFFFF),
    );
  });
}
