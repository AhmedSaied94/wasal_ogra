/// Durations (contracts/design-tokens.md «Motion»). All stay under ⅓ s
/// (FR-022).
abstract final class MotionTokens {
  /// Press feedback and fades.
  static const fast = Duration(milliseconds: 150);

  /// Page transitions.
  static const screen = Duration(milliseconds: 250);

  /// Sheet open and close.
  static const sheet = Duration(milliseconds: 250);

  static const all = [fast, screen, sheet];
}
