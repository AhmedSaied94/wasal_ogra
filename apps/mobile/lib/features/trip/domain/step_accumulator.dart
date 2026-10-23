// Frame time to engine steps (research R4): the engine moves in fixed 33 ms
// steps whatever the frame rate, and a long frame never runs away.

/// The engine's step (M01 `clock.dart`).
const engineStepMs = 33;

/// At most this many steps for one frame; the rest of a long frame is
/// dropped, so a hitch slows the trip instead of jumping it.
const maxStepsPerFrame = 10;

final class StepAccumulator {
  int _micros = 0;

  static const _stepMicros = engineStepMs * 1000;

  /// How many steps [frame] makes, keeping the remainder for the next.
  int add(Duration frame) {
    if (frame <= Duration.zero) return 0;
    _micros += frame.inMicroseconds;
    var steps = _micros ~/ _stepMicros;
    if (steps > maxStepsPerFrame) {
      steps = maxStepsPerFrame;
      _micros = 0;
    } else {
      _micros -= steps * _stepMicros;
    }
    return steps;
  }

  /// How far into the next step the clock is, 0–1, for smooth movement.
  double get alpha => _micros / _stepMicros;

  /// Forgets the remainder: a pause starts the next frame fresh.
  void clear() => _micros = 0;
}
