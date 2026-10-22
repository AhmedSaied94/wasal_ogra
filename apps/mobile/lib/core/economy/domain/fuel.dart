// The fuel rules (research R8, contracts/fuel-and-time.md "Fuel"), exact to
// the millisecond. B03 must agree with them. `max` is `fuel_max`, and
// `regenMs` is `fuel_regen_minutes` in milliseconds.
import 'package:wassal/core/economy/domain/economy_state.dart';

/// How long one `fuel_unlimited_1h` lasts. It defines that product
/// (glossary §3.3); a different duration would be another product, so it
/// isn't a tunable (constitution VIII).
const unlimitedWindowMs = 3600000;

const msPerMinute = 60000;

/// `fuel_regen_minutes` in milliseconds.
int regenMsOf(int fuelRegenMinutes) => fuelRegenMinutes * msPerMinute;

/// [s] with every liter that came back by [t]. At or above [max] nothing
/// regenerates (FR-024).
FuelState regenerate(
  FuelState s,
  int t, {
  required int max,
  required int regenMs,
}) {
  if (s.liters >= max) return s;
  final n = _max(0, (t - s.countedFromMs) ~/ regenMs);
  if (s.liters + n >= max) {
    return FuelState(
      liters: max,
      // The moment it filled.
      countedFromMs: s.countedFromMs + (max - s.liters) * regenMs,
      unlimitedUntilMs: s.unlimitedUntilMs,
    );
  }
  return FuelState(
    liters: s.liters + n,
    countedFromMs: s.countedFromMs + n * regenMs,
    unlimitedUntilMs: s.unlimitedUntilMs,
  );
}

/// One liter fewer at [t]. Leaving the maximum starts the countdown at [t];
/// below it, the time already counted is kept (FR-021). An empty tank holds
/// at 0, as the fold's leniency needs (research R6).
FuelState spendOne(FuelState s, int t, {required int max}) {
  if (s.liters < 1) return s;
  final liters = s.liters - 1;
  return FuelState(
    liters: liters,
    countedFromMs: s.liters >= max && liters < max ? t : s.countedFromMs,
    unlimitedUntilMs: s.unlimitedUntilMs,
  );
}

/// A full tank at [t], or null when it is already full (`tank_full`).
FuelState? fillToMax(FuelState s, int t, {required int max}) {
  if (s.liters >= max) return null;
  return FuelState(
    liters: max,
    countedFromMs: t,
    unlimitedUntilMs: s.unlimitedUntilMs,
  );
}

/// One more [unlimitedWindowMs], from [t] or from the end of a window still
/// running.
FuelState extendUnlimited(FuelState s, int t) => FuelState(
  liters: s.liters,
  countedFromMs: s.countedFromMs,
  unlimitedUntilMs: _max(s.unlimitedUntilMs ?? t, t) + unlimitedWindowMs,
);

bool isUnlimited(FuelState s, int t) {
  final until = s.unlimitedUntilMs;
  return until != null && t < until;
}

/// What screens show of the tank (FR-023).
final class FuelView {
  const FuelView({
    required this.liters,
    required this.max,
    this.nextLiterAtMs,
    this.fullAtMs,
    this.unlimitedUntilMs,
  });

  final int liters;
  final int max;

  /// When the next liter arrives; null at or above [max].
  final int? nextLiterAtMs;

  /// When the tank will be full; null at or above [max].
  final int? fullAtMs;

  /// The end of an unlimited-fuel window still running at the read.
  final int? unlimitedUntilMs;

  @override
  bool operator ==(Object other) =>
      other is FuelView &&
      other.liters == liters &&
      other.max == max &&
      other.nextLiterAtMs == nextLiterAtMs &&
      other.fullAtMs == fullAtMs &&
      other.unlimitedUntilMs == unlimitedUntilMs;

  @override
  int get hashCode =>
      Object.hash(liters, max, nextLiterAtMs, fullAtMs, unlimitedUntilMs);

  @override
  String toString() =>
      'FuelView($liters/$max, next $nextLiterAtMs, full $fullAtMs, '
      'unlimited until $unlimitedUntilMs)';
}

/// The tank at [t], regenerated with the current tunables.
FuelView fuelView(
  FuelState s,
  int t, {
  required int max,
  required int regenMs,
}) {
  final r = regenerate(s, t, max: max, regenMs: regenMs);
  final full = r.liters >= max;
  return FuelView(
    liters: r.liters,
    max: max,
    nextLiterAtMs: full ? null : r.countedFromMs + regenMs,
    fullAtMs: full ? null : r.countedFromMs + (max - r.liters) * regenMs,
    unlimitedUntilMs: isUnlimited(r, t) ? r.unlimitedUntilMs : null,
  );
}

int _max(int a, int b) => a > b ? a : b;
