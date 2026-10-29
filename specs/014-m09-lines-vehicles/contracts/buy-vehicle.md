# Contract: Buying a Vehicle (شراء العربية)

Spec US3, US4 #3–#4; FR-030–FR-040. Artboard `BuyVehicle`, and the owner's boards
`BuyVehicleShort`, `BuyVehicleOwned`, `BuyVehicleNotForSale` ([design-briefs.md](./design-briefs.md)).
Research R6, R7, R10.

## Files

```text
lib/features/lines/
├── domain/
│   ├── vehicle_offer.dart      # VehicleOffer, vehicleOffer(c, p, view, id)
│   └── impact.dart             # Impact, impactAfterPurchase(c, p, jenehat, id)
├── application/
│   ├── vehicle_offer_provider.dart
│   └── vehicle_purchase.dart   # VehiclePurchase (held TxnId, busy, outcome)
└── presentation/
    ├── vehicle_sheet.dart
    ├── vehicle_preview.dart    # VehicleSprite on the sky, 358×190
    ├── benefits_row.dart
    ├── price_card.dart
    └── impact_line.dart
```

`router.dart`'s `_page` builds `VehicleSheet(vehicleId)` for `RouteNames.vehiclePurchase`.

## The offer

`VehicleOffer`:

- `vehicle`, `name`, `look`;
- `seats` and `currentSeats`;
- `opensLine` (`LineId?`, the first line by order unlocked by this vehicle);
- `sale` (`VehicleSale`, [progress-rules.md](./progress-rules.md));
- `price` (only when `ForSale`) and `balance`;
- `listPrice` (the catalog's price whatever `sale` says; the price card of a vehicle not for sale
  yet);
- `shortfall` (`int?`, from `price`);
- `impact` (`Impact?`).

`impactAfterPurchase`:

1. `p'` is `p` plus `(SkuKind.vehicle, wire)` in `owned`. `t = savingsTarget(c, p', jenehat − price)`
   (M08).
2. The goal and its price:
   - `ChapterGoalTarget` with `Amount` → `(subjectName, of)`;
   - `ApartmentPieceTarget` → `(itemName, priceJenehat)`;
   - otherwise null.
3. `amount = goalPrice − (jenehat − price)`. Null unless `amount > 0` and the purchase is affordable.

## Layout (`BuyVehicle`)

| Block | `ForSale`, affordable | `ForSale`, short | `Owned` | `NeedsFirst` / `NoPrice` |
| --- | --- | --- | --- | --- |
| Header: name + close | ✓ | ✓ | ✓ | ✓ |
| Preview (`VehicleSprite`, no «بزينتك») | ✓ | ✓ | ✓ | ✓ |
| Benefits: «{n} كرسي بدل {m}» · «بيفتح {line}» (if any) · «قبض أكتر في كل مشوار» | ✓ | ✓ | — | ✓ |
| Price card «السعر» / «معاك» | ✓ | ✓ | — | `NeedsFirst` with `listPrice`; `NoPrice`: — |
| Impact «بعد الشرا، فاضل {amount} ج على {goal}» | when not null | — | — | — |
| «ناقصك {n} ج» (15/700 `danger.ink`) + gold `ProgressBar` 10 high (balance / price), 10 over the buttons | — | ✓ | — | — |
| Status row (`StatusRow`, 44 high, 15/700, radius 18), 12 over the button | — | — | owned: a 24 `primary` tick on `primary.soft`, «دي عربيتك» (starter: «دي عربية المعلم، وانت شغال عليها») | locked look, a 24 lock: «اشتري {vehicle} الأول» / «العربية دي مش للبيع دلوقتي» |
| Buttons (64, radius 22) | «اشتريها» + «لسه» (2:1) | «اشتريها» disabled (§9.1 #5) + «لسه» | «تمام», the primary button, full width | «تمام», the primary button, full width |
| The sheet's height | the full sheet | the full sheet | as tall as its content | the full sheet |

As the owner's boards draw it (`BuyVehicleShort`, `BuyVehicleOwned`, `BuyVehicleNotForSale`,
2026-10-29; [design-briefs.md](./design-briefs.md)).

## Buying

`VehiclePurchase(Economy)`, one per open sheet:

1. «اشتريها» does nothing while busy, or unless `offer.sale is ForSale` and `balance ≥ price`.
2. `_id ??= economy.newRequestId()`, then
   `await economy.buy(_id, kind: SkuKind.vehicle, skuId: vehicleWire[id]!)`. The economy reads the
   price from the catalog.
3. The outcome:

| Outcome | Result | `_id` |
| --- | --- | --- |
| `OpApplied` (incl. `repeated`) | `NavGuard.go('/lines')`; announce `buyVehicleBoughtA11y` | cleared |
| `OpRefused(insufficientFunds)` | stays; the shortfall shows from the view | kept |
| `OpRefused(alreadyOwned)` | stays; the owned state shows from the view | cleared |
| `OpRefused(notForSale \| unknownSku \| catalogMismatch \| unknownVariant)` | `NavGuard.go('/lines')` + `showAppToast(buyVehicleNotForSaleToast)` | cleared |
| `OpWriteFailed` | stays; `tripRetryPurchase` «ما عرفناش نكمّل الشرا.» above the buttons | kept |

- **Offline:** applies at once and syncs later (M06).
- **A later refusal from the server** rolls back through M06's rebase. Lines and any open sheet
  redraw, and M06's `syncBalanceCorrected` toast tells the player.
- **Closing** with «لسه», ✕, swipe, scrim or back spends nothing.

## Accessibility

- The preview is excluded from semantics.
- The price card is one node: «السعر {price} جنيه، معاك {balance} جنيه».
- The benefits are three labelled nodes.
- The status line is a live region when the state changes while the sheet is open (a sync).
- Focus starts on the title.

## Tests

- **Unit:**
  - `vehicle_offer_test.dart`: every sale state, seats, `opensLine`, the shortfall;
  - `impact_test.dart`:
    - the microbus in ch2 → «الشبكة» and its amount;
    - a piece target;
    - a line goal → null;
    - nothing missing → null;
    - not affordable → null;
  - `vehicle_purchase_test.dart`, against a fake `Economy`: every outcome row, a double tap (one
    `buy`), a retry after a write failure (the same id), busy.
- **Widget** (`vehicle_sheet_test.dart`):
  - each column of the layout table;
  - the balance changing while open (a sync) flips short ↔ affordable without closing;
  - a rollback after a purchase;
  - closing four ways with nothing spent;
  - an id the pack lacks → `/lines`.
- **Integration:** `integration_test/lines_loop_test.dart`.
- **Against the dev stack** (`backend` tag): the purchase syncs and is accepted.
- **Design:** `test/design/samples/buy_vehicle.dart` for `BuyVehicle`, `BuyVehicleShort`,
  `BuyVehicleOwned` and `BuyVehicleNotForSale`, with their layout tests and goldens; the plain and
  no-price sheets as goldens only.
- **Sizes:** `test/a11y/buy_vehicle_minimum_sizes_test.dart`.
