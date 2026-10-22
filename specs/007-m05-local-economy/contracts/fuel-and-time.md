# Contract: Fuel and Trusted Time

The fuel rules ([research R8](../research.md#r8-fuel)) and the trusted clock
([research R9](../research.md#r9-trusted-time)), which B03 must agree with (spec Assumptions).
Every value is an integer, and every time is in UTC milliseconds.

## Fuel

`max = fuel_max`, `regen = fuel_regen_minutes × 60_000`. Both are read from `ConfigSource`
(`Tunable.fuelMax`, `Tunable.fuelRegenMinutes`) for reads, and recorded on each operation for the
fold. Both must be at least 1: an override below 1 falls back to the bundled default.

`countedFrom` is always set. Below the maximum it is when the current countdown started. At or
above the maximum it is the moment the tank last became full, and nothing counts.

```text
regenerate(s, t):
  if s.liters >= max: return s
  n = max(0, (t - s.countedFrom) ~/ regen)
  if s.liters + n >= max:
    return (liters: max, countedFrom: s.countedFrom + (max - s.liters) * regen)   (the moment it filled)
  return (liters: s.liters + n, countedFrom: s.countedFrom + n * regen)

spendOne(s, t):          requires s.liters >= 1
  liters = s.liters - 1
  countedFrom = (s.liters >= max and liters < max) ? t : s.countedFrom

fillToMax(s, t):         refused (tank_full) when s.liters >= max
  liters = max; countedFrom = t

extendUnlimited(s, t):   (fuel_unlimited_1h)
  unlimitedUntil = max(s.unlimitedUntil ?? t, t) + 3_600_000

isUnlimited(s, t) = s.unlimitedUntil != null and t < s.unlimitedUntil

view(s, t): r = regenerate(s, t)
  nextLiterAt = r.liters >= max ? null : r.countedFrom + regen
  fullAt      = r.liters >= max ? null : r.countedFrom + (max - r.liters) * regen
```

**Which tunables apply.** An operation regenerates to its own time with the `fuel_max` and
`fuel_regen_minutes` it records, so the time up to each operation keeps its values. A read
regenerates from the last operation with the current values (FR-027).

| Event | Rule |
| --- | --- |
| Trip start, `fuel` mode | `regenerate` to `t`, then `spendOne`; refused `no_fuel` if `liters == 0` |
| Trip start, `unlimited` mode | `regenerate` only; liters untouched |
| `refuel_full`, `fuel_refill` | `regenerate`, then `fillToMax` |
| `fuel_unlimited_1h` | `regenerate`, then `extendUnlimited` |
| Revive, resume | nothing (FR-030) |
| `fuel_max` lowered below `liters` | liters kept; `regenerate` does nothing until `liters < max` (FR-024) |
| `fuel_max` raised above `liters` | counting resumes from `countedFrom`, the moment the tank last filled, for the time since the last operation (FR-027) |
| `fuel_regen_minutes` changed | applies to the time since the last operation; what each operation recorded is kept (FR-027) |

**Examples** (max 5, regen 20 min):

1. Full at 09:00, start at 09:00 → 4 liters, counting from 09:00. Next liter 09:20, full 09:20.
2. Then a start at 09:07 → 3 liters, still counting from 09:00. Next 09:20, full 09:40.
3. At 09:45, the view regenerates: 5 liters, full since 09:40 (`countedFrom = 09:40`). The 5
   minutes past 09:40 count for nothing, because the tank was full.
4. A tunable lowers `fuel_max` to 4 while the tank holds 5 → 5 kept, not counting. A start → 4,
   still not counting (4 is the max). Another start → 3, counting from that moment.

## Trusted time

```dart
abstract interface class UptimeSource {
  /// null where the platform has no channel (iOS before phase 3, tests without a fake).
  Future<BootSnapshot?> snapshot();
}
final class BootSnapshot { final int elapsedRealtimeMs; final int? bootCount; }

abstract interface class TrustedClock {
  int nowMs();                       // synchronous
  Future<void> resync();             // at startup and on every return to the foreground
  Future<void> anchorOnServer(int serverTimeMs, {required int elapsedAtResponseMs}); // M06
  int get latestMs;
}
```

### Android channel `wassal/clock`

Method `bootSnapshot`, no arguments. Returns
`{"elapsed_realtime_ms": SystemClock.elapsedRealtime(), "boot_count": Settings.Global.getInt(cr, BOOT_COUNT)}`,
with `boot_count` null when the setting is missing. It needs no permission. It lives in
`MainActivity` next to `wassal/launch`.

### Rules

```text
on resync:
  snap = uptime.snapshot()
  if snap == null:                              (no channel)
     base = max(deviceNow, latestTrusted); use the device clock from base, never below latestTrusted
  else if restarted(anchor, snap):
     anchor = (ms: max(deviceNow, latestTrusted), elapsed: snap.elapsed, boot: snap.bootCount, source: device)
  stopwatch.reset(); snapElapsed = snap.elapsed
  then save the new anchor; a failed save keeps it in memory, and the next op or pause saves it

restarted(a, s) = (a.bootCount != null and s.bootCount != null) ? a.bootCount != s.bootCount
                                                                 : s.elapsed < a.elapsed

nowMs = max(latestTrusted, anchor.ms + (snapElapsed + stopwatch.elapsedMs - anchor.elapsed))
```

- `latestTrusted` is stored with every operation, in the same transaction, and on
  `AppLifecycleState.paused`. It never decreases.
- The anchor is read and written only through `DriftEconomyStore` (`loadAnchor`, `saveAnchor`).
  `TrustedClock` never touches the database itself (contracts/storage.md "Guards").
- **First open:** anchor = (device now, snapshot elapsed, boot count, `device`).
- **`anchorOnServer`** (M06): anchor = (server time, the elapsed at the response, the boot count,
  `server`), never below `latestTrusted`.
- **Same boot** (the app closed and reopened): the stored anchor still holds. The device clock isn't
  read, so a clock change while the phone stayed on has no effect (spec Clarifications).

### Cases the tests cover

| Case | Expected |
| --- | --- |
| Clock +3 h, phone on, app open | nothing changes |
| Clock +3 h, phone on, app closed and reopened | nothing changes |
| Clock −3 h, phone on | nothing changes |
| Restart, clock right, 2 h off | +2 h counted |
| Restart, clock +3 h | +3 h counted on the device (the server reconciles) |
| Restart, clock −3 h | re-anchored at `latestTrusted`; the time off isn't counted; nothing taken away |
| No boot count, restart with longer uptime than the anchor | treated as the same boot: the time off isn't counted (conservative) |
| No channel | the device clock, never below `latestTrusted` |
| Time zone or DST change | nothing changes |
