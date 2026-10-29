# Data Model: Lines Map, Line Details and Vehicle Purchase (M09)

Phase 1 of [plan.md](./plan.md). M09 adds:

- three content fields;
- one device preference;
- derived values computed from the active pack and the economy's projection.

There is **no database change, no new operation and no new tunable.** Everything else is derived on
each view (FR-001).

## Content (new fields)

[contracts/content-fields.md](./contracts/content-fields.md).

| Entity | Field | Type | Rule |
| --- | --- | --- | --- |
| Line | `whats_new` | `LocalizedText` (`ar-EG` required, `ar` optional) | player text, no digits, no edge spaces (V-X1) |
| Line | `display_fare_piasters` | integer | ≥ 50, multiple of 50; display only (FR-043) |
| Vehicle | `short_name` | `LocalizedText` | as `whats_new` |

**Read, unchanged:**

- **Line:** `line_id`, `name`, `order`, `unlock {kind, vehicle_id?, line_id?}`.
- **Vehicle:** `vehicle_id`, `name`, `order`, `starter`, `seats` (count = `seats.length`).
- **Trip:** `trip_id`, `kind`, `line_id`, `vehicle_id`, by trip number.
- **Chapter:** `order`, `title`, `goal`, `story_trip_id`.
- **Catalog:** the `vehicle` prices in JENEHAT.

## Device preference (new)

| Key | Value | Written by | Read by |
| --- | --- | --- | --- |
| `pref.lines_seen` | the news keys the player has seen on Lines: sorted, comma-joined (`line:line_gamaa,story:line_hay.20,vehicle:micro_old`) | `LinesSeenNotifier.markSeen` when Lines is on screen; the first read, when absent | `LinesDotWatcher` |

It is added to `SharedPrefsSettingsStore.keys` and to `MemorySettingsStore`'s list. It is a read
marker, not game state: losing it shows the dot once more, and nothing of value depends on it.

## Derived values (pure, `lib/core/progress/domain/` and `lib/features/lines/domain/`)

### `VehicleSale` (progress domain)

`Owned` | `ForSale(priceJenehat)` | `NeedsFirst(vehicle)` | `NoPrice`
([contracts/progress-rules.md](./contracts/progress-rules.md)).

### `VehicleTile`

| Field | Source |
| --- | --- |
| `vehicle`, `name`, `shortName`, `look` | content |
| `state` | `done` (the player's, before the current one) · `current` (`currentVehicle`) · `forSale(price)` · `notForSale` |

### `LineStanding`

| Field | Source |
| --- | --- |
| `line`, `name`, `whatsNew`, `farePiasters` | content |
| `state` | `locked(reason)` · `current(next)` · `done` (FR-009) |
| `reason` | `NeedsVehicle(vehicle)` for a `vehicle` unlock; `AfterLine(line)` for `line_complete` |
| `next` | `(tripId, number, total)`: the first trip by number that is `tripPlayable` with no star (FR-008) |
| `starsEarned`, `starsMax` | sum of best stars; 3 × the line's trips |
| `allThree` | every trip at 3 stars |
| `doneCount` | trips with ≥ 1 star |

**The focus line:** the line of `homeNextTrip(...)`, else the last `current` line, else the last
unlocked line (FR-010).

### `TripCell`

`(tripId, number, isStory, state, stars, playable)`. The states are `done`, `next`, `playable` and
`locked`, and `isStory` adds the chip ([contracts/line-details.md](./contracts/line-details.md)).
`playable` is whether the rules let the trip start now (`tripPlayable`, FR-026): a `done` cell the
rules refuse keeps its stars but is drawn locked and isn't a link. `startable` is `playable` and not
`locked`.

**`VisibleRange`:** `rows`, `hidden: (from, to)?`. Rows: every row through the furthest cell drawn
done, next or playable, and one more, at least four, capped at the line's (FR-025).

### `VehicleOffer` and `Impact`

| Field | Source |
| --- | --- |
| `seats`, `currentSeats` | `seats.length` of this vehicle and of `currentVehicle` |
| `opensLine` | the first line by order whose `unlock` is this vehicle; null to hide «بيفتح» |
| `sale`, `price`, `balance` | `vehicleSale`, the catalog, `EconomyView.jenehat`; `price` only when `ForSale` |
| `listPrice` | the catalog's JENEHAT price whatever `sale` says, for the price card of a vehicle not for sale yet (`BuyVehicleNotForSale`); null when the catalog has none |
| `shortfall` | `price − balance` when positive |
| `impact` | `Impact(goalName, amount)` or null: M08's `savingsTarget` for the state after the purchase ([contracts/buy-vehicle.md](./contracts/buy-vehicle.md)) |

### `LinesNews`

A set of keys:

- `line:<id>`: unlocked, not a `start` line;
- `story:<tripId>`: `tripPlayable`, no star;
- `vehicle:<id>`: `ForSale` and the balance covers it.

The dot shows when `news − seen ≠ ∅`.

## State diagrams

**A line:**

```text
locked ──(its vehicle owned | its line complete)──▶ current ──(no playable, unstarred trip left)──▶ done
  ▲                                                     ▲                                          │
  └──────────(rollback: the vehicle no longer owned)────┴──────(a newer pack adds trips)───────────┘
```

**A vehicle** (for the player):

```text
notForSale(NeedsFirst) ──(previous owned)──▶ forSale ──(bought)──▶ current ──(a later one bought)──▶ done
                                              ▲                       │
                                              └──(server refuses)─────┘  (M06 rollback)
```

**A story trip** (FR-007):

```text
storyLocked ──(its line unlocked ∧ vehicle owned ∧ chapter complete)──▶ next | playable ──(≥ 1 star)──▶ storyDone
```

**The purchase intent** (`VehiclePurchase`):

```text
idle ──tap──▶ busy(id) ──OpApplied──▶ closed (id cleared)
                 │──insufficientFunds | writeFailed──▶ idle (id kept: a retry is the same intent)
                 │──alreadyOwned──▶ idle, owned state (id cleared)
                 └──notForSale | unknownSku | catalogMismatch──▶ closed + toast (id cleared)
```

## Routes

| Route | Status |
| --- | --- |
| `/lines` | existing (placeholder → `LinesScreen`); its tab always opens at the root |
| `/lines/:lineId` | existing sheet (→ `LineDetailsSheet`) |
| `/lines/vehicle/:vehicleId` | existing sheet (→ `VehicleSheet`) |
| `/lines/:lineId/pre-trip/:tripId` | **new** sheet, child of `/lines/:lineId`; builds M08's `PreTripCard(leaveTo: '/lines/<lineId>')` |
