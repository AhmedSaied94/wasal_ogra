# Contract: Fuel on the Server

The server's fuel rules. They are M05's (`specs/007-m05-local-economy/contracts/fuel-and-time.md`)
in the same integer arithmetic, with the server's timeline on top. Where this file and M05's
disagree on a rule that does not involve the server's clock, M05's wins and this file is wrong.

All times are UTC milliseconds since the Unix epoch in the functions, and datetimes in the database.
`max` is the tank's size, `regen = fuel_regen_minutes × 60_000`.

## State

The wallet's `fuel` (liters), `fuel_updated_at` (`countedFrom`), `fuel_unlimited_until` and
`timeline_at`. `countedFrom` is always set: below the maximum it is when the current countdown
started; at or above it is when the tank last became full.

## Functions (`economy/services/fuel.py`)

The same as M05, restated so the fixtures can be read without it:

```text
regenerate(s, t):
  if s.liters >= max: return s
  n = max(0, (t - s.countedFrom) // regen)
  if s.liters + n >= max:
    return (liters: max, countedFrom: s.countedFrom + (max - s.liters) * regen)
  return (liters: s.liters + n, countedFrom: s.countedFrom + n * regen)

spend_one(s, t):        requires s.liters >= 1
  liters = s.liters - 1
  countedFrom = t if (s.liters >= max and liters < max) else s.countedFrom

fill_to_max(s, t):      refused as tank_full when s.liters >= max
  liters = max; countedFrom = t

extend_unlimited(s, t):
  unlimitedUntil = max(s.unlimitedUntil or t, t) + 3_600_000

is_unlimited(s, t) = s.unlimitedUntil is not None and t < s.unlimitedUntil
```

Integer floor division and no floats. `max` and `regen` are read at the operation's time `t`.

## The effective time of an operation

```text
t_i = clamp(occurred_at_i, timeline_at, server_now)      timeline_at := t_i after each operation
```

`timeline_at` starts at the wallet's creation and persists across batches. `server_now` is read
once per batch. So within and across batches time never goes backward, and never goes past the
server's clock. A move of more than `SYNC_CLOCK_CLAMP_FLAG_MINUTES` raises `clock_clamped`.

## Per operation

| Operation | Rule at `t` |
| --- | --- |
| `trip_start`, `fuel` mode | `regenerate`, then: liters ≥ 1 → `spend_one`; else overdraft (below) |
| `trip_start`, `unlimited` | `regenerate` only; needs `is_unlimited`, else `not_eligible` |
| `trip_start`, `challenge` | `not_eligible` until B08 |
| overdraft | game day of `t` has fewer than `ECONOMY_FUEL_OVERDRAFT_PER_DAY` (2) overdrafts: accept, liters stay 0, flag `fuel_overdraft`, counter + 1. Otherwise `cap_reached`. |
| `ad_reward` `fuel_refill`, `spend_bonat` `fuel` | `regenerate`, `fill_to_max` (`tank_full` when full) |
| `ad_reward` `fuel_refill` cap | the day counter `fuel_refill_ad` for the game day of `t` is below `ECONOMY_FUEL_REFILL_DAILY_CAP` (3), else `cap_reached` |
| `spend_bonat` `fuel_unlimited_1h` | `regenerate`, `extend_unlimited` |
| `tutorial_gift`, `comeback_gift` | `regenerate`, then liters = `max`, `countedFrom` = `t` (no refusal on a full tank) |
| revive, resume, boosters | nothing |

`max` is `ECONOMY_FUEL_MAX` (5), or `ECONOMY_FUEL_MAX_SUBSCRIBER` (7) when the entitlements carry
`fuel_max_bonus` at `t`. A lowered maximum keeps the liters above it; nothing regenerates until the
tank is below the maximum (M05 FR-024).

A read (bootstrap, state, the sync answer) shows `regenerate(s, server_now)` without writing it.

## Shared fixtures

`fixtures/economy/fuel.json`:

```json
{
  "cases": [
    {
      "name": "start from a full tank counts from the start",
      "scope": "both",
      "settings": { "max": 5, "regen_minutes": 20 },
      "initial": { "liters": 5, "counted_from": "2026-10-17T09:00:00Z", "unlimited_until": null },
      "steps": [
        { "op": "trip_start", "t": "2026-10-17T09:00:00Z", "mode": "fuel" },
        { "op": "trip_start", "t": "2026-10-17T09:07:00Z", "mode": "fuel" },
        { "op": "read", "t": "2026-10-17T09:45:00Z" }
      ],
      "expected": [
        { "liters": 4, "counted_from": "2026-10-17T09:00:00Z", "accepted": true },
        { "liters": 3, "counted_from": "2026-10-17T09:00:00Z", "accepted": true },
        { "liters": 5, "counted_from": "2026-10-17T09:40:00Z", "accepted": true }
      ]
    }
  ]
}
```

- A step is `trip_start`, `refill`, `unlimited_1h`, `set_max` or `read`, with `t` and, for starts,
  `mode`. `expected[i]` is the state after step *i* plus whether it was accepted and, when refused,
  the `reason`.
- `scope`: `both` for M05's rules (Dart and Python replay them), `server` for the clamp, overdraft and
  cap cases (Python only; they use `server_now` and `timeline_at` given in the case).
- The cases start with every worked example in M05's contract and then add: a start after a long
  gap; a backward `occurred_at`; a future `occurred_at`; three overdrafts in a day; a refill on a
  full tank; a window extended while running; a lowered maximum.
