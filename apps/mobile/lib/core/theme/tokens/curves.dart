import 'package:flutter/animation.dart';

/// The design's `easeOutBack(k)` (docs/design/tokens.json `motion`): it
/// overshoots by an amount set by [k], then settles at 1.
///
/// `f(t) = 1 + (k + 1)(t − 1)³ + k(t − 1)²`, so `f(0) = 0` and `f(1) = 1`.
final class EaseOutBack extends Curve {
  const EaseOutBack(this.k);

  /// The overshoot; Flutter's [Curves.easeOutBack] is about 1.7.
  final double k;

  @override
  double transformInternal(double t) {
    final u = t - 1;
    return 1 + (k + 1) * u * u * u + k * u * u;
  }

  @override
  String toString() => 'EaseOutBack($k)';
}
