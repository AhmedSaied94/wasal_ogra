# Contract: The Pre-trip Card (كارت ما قبل المشوار)

Spec US2; FR-023–FR-033. Artboard `PreTrip`. Research R5–R7.

## Files

```text
lib/features/pre_trip/
├── domain/
│   ├── met_set.dart            # metSet(content, progress)
│   ├── new_subjects.dart       # newCardSubjects (closed table), eventIcons, bagArchetypes, childArchetypes
│   ├── briefing.dart           # tripBriefing(content, view, metSet, boostersLocked)
│   └── card_mode.dart          # shouldShowCard(...)
├── application/
│   ├── card_mode_provider.dart # PreTripCardModeNotifier (pref.pre_trip_card)
│   ├── briefing_provider.dart  # tripBriefingProvider(tripId)
│   └── booster_purchase.dart   # BoosterPurchase (held TxnId, buy, outcome)
└── presentation/
    ├── pre_trip_card.dart      # the sheet's body
    ├── stop_prices.dart        # up to 4 cells in one row
    ├── new_card.dart
    ├── star_goals.dart
    ├── booster_tiles.dart      # tiles + buy chip
    └── buy_dialog.dart         # AppDialog spend confirmation
```

`router.dart`'s `/home/pre-trip/:tripId` builds `PreTripCard(tripId)` inside its existing
`AppSheetPage`. The route's parameter validator already refuses malformed ids.

## Opening

- **A trip the active pack lacks, or one not `tripUnlocked`** (a stale link, or a pack switch):
  the card doesn't render. It pops back to `/home` after the frame, and nothing is charged.
- **Any startable trip** opens. Today that is from Home and from the result; later from M09.

## Layout (`PreTrip`, top to bottom)

| Block | Content | Rule |
| --- | --- | --- |
| Grabber + header | `briefing.lineName` over `preTripTitle(index)`; `StatusChip.story` «مشوار قصة» when `isStory`; close `IconCircleButton` 44 «اقفل» | FR-023, FR-033 |
| Prices | «أسعار المحطات»; one `StationTag(slot)` cell per stop, right to left, in drop-off order; `piasters(fare)` + «ج»; up to 4 in one row (cells share the width; long names wrap to 2 lines) | FR-027 |
| Rule lines | the `student_card` icon + the line, per `ruleLines` | FR-028 |
| New card | `PassengerAvatar(look, 60)` or the event icon; `StatusChip.new_` «جديد»; the name; the sentence (2 lines) | FR-029 |
| Stars | «النجوم» + 3 rows: `preTripStar1..3`; filled when `starsEarned ≥ i`, else the empty star + «لسه» | FR-030 |
| Boosters | «المساعدات» + 4 tiles (not tappable) with «×{n}»; the buy chip «{booster} بـ{price} بونات» when `buyOffer != null`. The whole block is hidden while `boostersHidden` | FR-031, FR-032 |
| Story condition | the `danger` bar «أي خناقة والمشوار يتعاد» (M02's ARB line) above the button, when `isStory && storyRuleNoFights` | FR-033 |
| Button | `AppButton.primary(xl)` «اطلع» + `CostChip` «−١» (hidden in an unlimited window); label `preTripA11yGo` «اطلع، هيصرف لتر بنزين». Pinned at the bottom; the body above scrolls | FR-023, FR-026 |

## Actions

| Element | Result |
| --- | --- |
| ✕, swipe down past 25% or a fling, the scrim, system back | pop to `/home`; nothing is spent (FR-025) |
| «اطلع» | with fuel, a window or M07's `firstSession.fuelLessonDue(tripId)`: `NavGuard.go(context, '/trip/$tripId')`, which replaces the sheet; the trip charges the liter (M02). With an empty tank: the fuel sheet (FR-026) |
| Buy chip | `buy_dialog.dart` (below) |

## Buying a booster

`BoosterPurchase` (one per open card):

1. A chip tap opens `BuyDialog(booster, priceBonat, balance)`:
   - the booster's icon and name, «بـ{price} بون», «معاك {balance}», or «ناقصك {n}» when short;
   - «اشتري» (primary) and «مش دلوقتي» (tertiary);
   - no dismissal by tapping outside (HANDOFF `AppDialog`).
2. «اشتري» takes the held id (`_id ??= economy.newRequestId()`), then
   `await economy.buy(_id, kind: SkuKind.booster, skuId: boosterWire[booster])`:
   - `OpApplied`: `_id = null`, close; the tile's count updates from `economyViewProvider`, and the
     chip moves to the next empty booster or hides;
   - `OpRefused(insufficientFunds)`: the dialog stays and shows «ناقصك …»; `_id` is kept, and any
     other refusal shows M02's `tripRefusal*` line;
   - `OpWriteFailed`: the neutral retry line (`retryMessage`), and `_id` is kept.
3. A second tap while a call is in flight does nothing.

This works offline.

## Tests

- **Unit:**
  - `met_set_test.dart`;
  - `briefing_test.dart`: drop-off order, slots and letters, 4 stops, the rule-line tables, the
    new subject's order, stars, boosters and the buy offer, the locked state;
  - `card_mode_test.dart`;
  - `new_subjects_test.dart`: against `capabilities.json` and `app_ar.arb`.
- **Widget** (`pre_trip_card_test.dart`):
  - closing four ways with nothing spent;
  - «اطلع» going to `/trip/<id>`;
  - an empty tank;
  - an unknown trip;
  - the story chip and bar;
  - a scrolling body with a pinned button;
  - the buy flow: applied, refused, a double tap, offline, a write failure.
- **Settings** (`settings_pre_trip_card_test.dart`): the row, the saved value, the default from the
  tunable.
- **Design:** `test/design/samples/pre_trip.dart`, `pre_trip_layout_test.dart`,
  `test/goldens/design/pre_trip_goldens_test.dart`.
