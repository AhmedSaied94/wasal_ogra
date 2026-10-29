# Contract: The Phone-only Progression Rules

Spec FR-001–FR-013, Clarifications Q1. Research R1, R2. It extends M08's
[progress-rules.md](../../013-m08-home-result/contracts/progress-rules.md). `unlocks.dart`, the port
of the server's `unlocks.py`, is not edited.

## File and imports

`apps/mobile/lib/core/progress/domain/playable.dart`, under the existing `lib/core/progress/domain`
entry of `test/repo/domain_imports_test.dart`. It imports only `package:content_models/`,
`content_source.dart`, `economy/domain/wire.dart` and its own folder (`unlocks.dart`,
`player_progress.dart`).

## Functions

| Dart | Rule | Spec |
| --- | --- | --- |
| `tripPlayable(c, p, tripId)` | A trip a chapter names as its `storyTripId`: `lineUnlocked(line) && vehicleOwned(vehicle) && chapterComplete(chapter)`. Any other trip: `tripUnlocked(c, p, tripId)`. Unknown id: false. | FR-006, FR-007 |
| `currentVehicle(c, p)` | The last vehicle by `order` with `vehicleOwned`; null for a pack without vehicles | FR-002 |
| `vehicleSale(c, p, vehicleId)` | `Owned` if `vehicleOwned`. Else `NeedsFirst(v)` if an earlier vehicle `v` (first by `order`) isn't owned. Else `NoPrice` if `c.price(SkuKind.vehicle, wire)` is null or not JENEHAT. Else `ForSale(price)`. Unknown id: `NoPrice`. | FR-003, FR-035 |

```dart
sealed class VehicleSale { const VehicleSale(); }
final class Owned extends VehicleSale { const Owned(); }
final class ForSale extends VehicleSale { const ForSale(this.priceJenehat); final int priceJenehat; }
final class NeedsFirst extends VehicleSale { const NeedsFirst(this.vehicle); final VehicleId vehicle; }
final class NoPrice extends VehicleSale { const NoPrice(); }
```

## Callers switched (M08's merged code)

| File | From | To |
| --- | --- | --- |
| `features/home/domain/next_trip.dart` (`startable`) | `tripUnlocked` | `tripPlayable` |
| `features/pre_trip/presentation/pre_trip_card.dart` (opening check) | `tripUnlocked` | `tripPlayable` |
| `features/home/application/start_next_trip.dart` | no check | step 0: not `tripPlayable` → return false |

Every new caller in `features/lines/` uses `tripPlayable` and `vehicleSale`, never `tripUnlocked`.

## Guarantees (tests)

`test/core/progress/playable_test.dart`:

- **Never more permissive.** Over every state reachable at depth 8 in the sample pack and in
  `synthetic_packs.dart`'s new `draftShaped` pack:
  - `tripPlayable ⇒ tripUnlocked` for every trip;
  - `vehicleSale is ForSale ⇒` M05's `validateBuy` accepts the vehicle when the balance covers the
    price.

  `draftShaped` has `line_hay` with 19 regular trips and story `.20` (ch1, `complete_line`), and
  `line_gamaa` with story `.01` (ch2, `own_vehicle micro_old`) and story `.18` (ch3, `purchase`).
- **The story cases by name** (US5):
  - `line_gamaa.01` is locked without the microbus in every chapter;
  - `line_hay.20` becomes playable exactly when `.01`–`.19` have a star;
  - `.18` is locked after `.17` until ch3 is owned, while `.19` is playable;
  - after the shabka, `.18` is playable even with `.19`–`.22` done.
- **Vehicles:** `NeedsFirst` for a third vehicle while the second isn't owned; `NoPrice` for the
  starter and for a price in BONAT; `Owned` for the starter.
- **Unknown ids** answer false, `NoPrice` or null.

M08's `unlocks_test.dart` (the server's cases) stays as it is. `next_trip_test.dart` and
`sample_sweep_test.dart` gain the story-trip cases above.
