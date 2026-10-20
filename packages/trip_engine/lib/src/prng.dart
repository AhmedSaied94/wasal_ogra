/// xorshift32 on an unsigned 32-bit state (rules.md §13, research R4). The
/// engine draws from it only for speech variants (§12).
final class Xorshift32 {
  const Xorshift32(this.state);

  /// The current state, in 1..2^32−1 when seeded from a valid seed.
  final int state;

  /// The next value, and the generator that follows it.
  (int, Xorshift32) next() {
    var x = state;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    return (x, Xorshift32(x));
  }
}
