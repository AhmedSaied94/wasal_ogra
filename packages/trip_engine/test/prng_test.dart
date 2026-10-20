// xorshift32 (rules.md §13): the vectors are shared with B05's mirror.
import 'package:test/test.dart';
import 'package:trip_engine/src/prng.dart';

List<int> _draw(int seed, int count) {
  var prng = Xorshift32(seed);
  return [
    for (var i = 0; i < count; i++)
      () {
        final (value, next) = prng.next();
        prng = next;
        return value;
      }(),
  ];
}

void main() {
  test('seed 1', () {
    expect(_draw(1, 5), [270369, 67634689, 2647435461, 307599695, 2398689233]);
  });

  test('seed 521288629', () {
    expect(_draw(521288629, 3), [1425164135, 2680915048, 127437483]);
  });

  test('seed 4294967295', () {
    expect(_draw(4294967295, 3), [253983, 4228382207, 1958451267]);
  });

  test('the generator is immutable: drawing twice from one state agrees', () {
    const prng = Xorshift32(7);
    expect(prng.next().$1, prng.next().$1);
    expect(prng.state, 7);
  });

  test('every value stays in 0..2^32-1', () {
    for (final seed in [1, 2, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF, 123456789]) {
      for (final value in _draw(seed, 2000)) {
        expect(value, inInclusiveRange(1, 0xFFFFFFFF));
      }
    }
  });
}
