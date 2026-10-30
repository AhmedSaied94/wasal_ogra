# Contract: The Apartment Tab, the Piece Sheet, RoomDone and Family Requests

The screens of the «الشقة» tab: what each one shows, what each tap does, and the purchases behind
them. Research R1, R6–R11, R14, R17; spec FR-001–FR-027, FR-040–FR-045, FR-050. The artboards'
values are in HANDOFF §11 (`AptGoal`, `AptGoalReady`, `AptRooms`, `Piece`, `RoomDone`, `Requests`);
this file names only what M10 decides beyond them.

## Folders

```text
lib/features/apartment/
├── domain/        apartment_view.dart, goal_view_model.dart, room_model.dart, piece_sheet_model.dart (pure)
├── application/   apartment_providers.dart, piece_purchase.dart, goal_purchase.dart, request_claim.dart
└── presentation/  apartment_screen.dart, goal_view.dart, rooms_view.dart, room_scene.dart, piece_sheet.dart,
                   room_done_dialog.dart, requests_sheet.dart, pending_chip.dart,
                   chapters_page.dart (scene-viewer.md)
lib/core/progress/domain/   requests.dart, rewards.dart (pure; economy-ops.md)
lib/core/art/apartment_art.dart
```

The domain folders import the models, the content source, the wire, the progress domain and Home's
`savings_target.dart` only (research R20).

`PlayerProgress` holds what is owned but not its style. So every domain function that shows or checks
a style takes `variantOf` (`String? Function(String itemId)`, the caller passing
`EconomyView.variantOf`): `RoomModel`, `PieceSheetModel` and `requestStates`.

## The tab (`/apartment`, `ApartmentScreen`)

```dart
sealed class ApartmentView { }
final class GoalView extends ApartmentView { final GoalViewModel model; }
final class RoomsView extends ApartmentView { final RoomModel model; final bool storyEnd; }

ApartmentView apartmentView(ContentSource c, PlayerProgress p, Set<String> pendingClaims, …);
```

| Current chapter | View |
| --- | --- |
| `order` below `apartmentOpens(c).order`, or no room chapter in the pack | `GoalView` |
| from `apartmentOpens` on | `RoomsView`, the current chapter's room selected |
| complete (the end of the story) | `RoomsView` on the last room, `storyEnd: true` |

Both views share the header (title, the JENEHAT `CurrencyPill`, the pending chip) and the chapter
bar, which opens `/apartment/chapters`.

### The pending chip (`PendingChip`, research R6)

- Shown while `pendingRewardsProvider` is not empty: a `sun.soft` pill with the BONAT icon and
  «+{n} بون في الطريق», where `n` is the sum.
- Label «{n} بون في الطريق، توصل مع المزامنة».
- It disappears when the base catches up. There is no animation: the BONAT pill on Home rises
  through M06's state replacement.

## The goal view (`GoalView`, research R8)

```dart
final class GoalViewModel {
  final Chapter chapter;            // number, title for the bar
  final SavingsTarget target;       // M08: ChapterGoalTarget (amount or trips, progress, affordable)
  final GoalArt art;                // goal_art slug, or the vehicle/tuktuk/ring fallback
  final CharacterLine? line;        // goal_line; ready_line replaces its text when ready
  final GoalAction action;          // none | buyChapter(price) | openVehicleSheet(vehicleId)
  final bool ready;                 // target.affordable && !owned
}
```

| Goal kind | Goal row | Bar | Ready action |
| --- | --- | --- | --- |
| `complete_line` | «{done} / {total} مشوار», counting the line's regular trips (M08's `Count`; a story trip doesn't count) | regular trips finished / regular trips | never ready |
| `own_vehicle` | «{saved} / {price} ج» | `min(jenehat, price) / price` | «اشتري {goal}» + «−{price} ج» → push `/lines/vehicle/:vehicleId` |
| `purchase` | «{saved} / {price} ج» | as above | «اشتري {goal}» + «−{price} ج» → `GoalPurchase` |

- **Ready** (`AptGoalReady`): the «جاهزة!» chip before the amount, the bar full, the `ready_line`,
  the CTA under the card, and the teaser shrinks. The view announces «{goal} جاهزة» politely on
  entry in this state.
- **The bar** animates from `goalBarSeenProvider[chapter]` to the current value (`sheetIn`), then
  stores it.
- **The teaser** is static: `paper` with the `outline` ring, the `AptGoal_03` drawing, «شقة العُمر»
  and `aptGoalLockedBody`. It is not tappable.

### `GoalPurchase` (`application/goal_purchase.dart`)

```dart
final class GoalPurchase {
  Future<GoalPurchaseResult> buy(ChapterId chapterId);   // held TxnId; M09's VehiclePurchase shape
}
```

1. **Rules first:** `chapterUnlocked`, the goal's kind is `purchase`, and the chapter is not owned.
   Otherwise the result is `notAllowed`, and nothing is sent.
2. `economy.buy(id, kind: SkuKind.chapter, skuId: chapterId)`. On `OpApplied` the held id clears. On
   `insufficient_funds` or `OpWriteFailed` it is kept; on another refusal it clears.
3. **On `OpApplied`:**
   - a coin burst from the CTA (`ui/coins_burst` in Rive when drawn, else a short scale);
   - then, if the chapter has a `story_trip_id` the player hasn't finished,
     `startNextTrip(context, ref, tripId: storyTripId, from: StartFrom.apartment)`;
   - otherwise the view simply rebuilds.

**`StartFrom.apartment`** (M08's `start_next_trip.dart`, one new value) opens the pre-trip card at
`/apartment/pre-trip/:tripId`, a root page whose back leads to `/apartment` (M09's `linePreTrip`
pattern). Every other rule of `startNextTrip` holds: the fuel sheet on an empty tank, and the due
scene before the trip.

## The rooms view (`RoomsView`, research R9)

```dart
final class RoomModel {
  final Chapter chapter; final Room room;
  final List<RoomTab> tabs;                 // salon, kitchen, bedroom: selectable | locked(name)
  final List<PieceCell> pieces;             // by order: owned(variant) | nextTarget(shortfall, progress, affordable) | missing(price)
  final int owned, total;
  final Scene? goalScene;                   // the chapter's goal scene
  final SceneState? goalSceneState;
  final int requestCount;                   // open + done (requests.dart)
}
```

| Block | Rule |
| --- | --- |
| Chapter bar | «الفصل {n} · {title}» over `tagline`; «جهّزت {owned} من {total}» over the bar. While `goalSceneState == waiting` and the room is complete, its trailing side is a «شوف المشهد» chip (its own button, `/story/scene/:id?then=/apartment`); the rest opens the timeline |
| Tabs | `Segmented`: a room whose chapter is unlocked is selectable; others are locked with a lock 12, read «مقفولة», and inert. Names from the pack, or ARB `roomTeaserName` for rooms the pack lacks. The hit area spans the 44 row |
| Requests button | «الطلبات», with the `CountBadge` (`primary`/white) hidden at 0; label «طلبات أهل العروسة، {n} مفتوحين»; opens `/apartment/requests` |
| Room scene | `RoomScene` (below) |
| Grid | `role=list` «قطع {room}»; owned «اتركّبت» (inert); next target «ناقصك {n}» + bar, or «تقدر تشتريها» in `primary` when affordable; other missing «{price} ج». Tapping a missing piece opens `/apartment/item/:itemId` |
| Strip | `InfoStrip` «خلّص {room} وافتح مشهد «{scene title}»» while the room isn't complete and it has a goal scene; at the end of the story «باقي الحكاية جاية في تحديث قريب» |

- The next target is M08's `_nextPiece`, exported as `nextPiece(c, p, room)`, so Home and the grid
  agree.
- The column is a scroll view (rooms of 5–6 pieces).

### `RoomScene` (`presentation/room_scene.dart`)

- A 358×300 design space, `FittedBox`-scaled to the card's width, with the room's card colour from
  `AppPalette` (the drawn `#F6E7D4` becomes a token, `scene.roomCard`, if none fits).
- Layers in order:
  1. `room.art` through `ApartmentArt`, else `RoomFallback`;
  2. each owned piece's variant `art` in its `slot` rect, else `PieceFallback`;
  3. each missing piece's dashed outline in its rect (a `CustomPaint`, 3 px dashes in
     `scene.outline`);
  4. its chip, «+» in a `primary` circle and «{item} · {price}». The chip is centred on the rect,
     clamped 8 pt inside the card, one line with an ellipsis at 160, 44 high. Label
     «{item}، {price} جنيه».
- A tab switch crossfades the scene in ≤ 150 ms.

### After a piece is bought

1. The sheet closes with `OpApplied` (below).
2. The piece drops into its rect: about 300 ms, `MotionTokens.dialogIn`. Its chip leaves and its cell
   turns to «اتركّبت».
3. سلمى's `SpeechBubble` (`bubblePop`) shows the variant's `comment` (else the item's) over the room,
   with her avatar. It stays until the next tap or scroll on the view.
4. The view announces «اشتريت {piece}».
5. If the room became complete with this purchase, `RoomDone` opens once the drop-in ends.

Under reduced motion, the drop-in and the bubble only fade.

## The piece sheet (`/apartment/item/:itemId`, `PieceSheet`, research R10)

An `AppSheetPage` with its own header (`ownHeader`), over the apartment.

```dart
final class PieceSheetModel {
  final Item item; final List<ItemVariant> variants; final String selected;
  final String? salmaLine;                     // selected variant's comment ?? item.comment
  final int price, balance;
  final Map<String, StoryCharacter> requestMarks;   // variantId → asker, for open requests on this item
  final StoryCharacter? missesRequest;         // set when the selected variant misses an open request
}
```

| Part | Rule |
| --- | --- |
| Styles | one card per variant (1–3), its drawing via `ApartmentArt`; the selected one ringed; `pieceStyleMemoryProvider[itemId]` else the first |
| Request mark | under a marked style's name, a `StatusChip` «طلب {asker}» (`sceneSpeaker` names) |
| سلمى's line | `CharacterAvatar` salma + the line, hidden when there is none |
| Missed line | above the button, «لو اخترت ده، طلب {asker} هيفوتك» in `danger.ink` 13/700, while `missesRequest` is set; it wraps |
| Button, affordable | `AppButton.primary` «اشتري» + the price chip «−{n} ج»; label «اشتري {item} بـ{n} جنيه» |
| Button, short | «ناقصك {n} ج» over `AppButton.primary` «اطلع مشوار» with the fuel chip «−١» (icon). It calls `startNextTrip(from: StartFrom.apartment)` with Home's next trip |
| Owned | the sheet doesn't open: owned cells are inert, and a stale link redirects to `/apartment` |
| Locked (the item's room not unlocked) | the same redirect |

- Changing the style updates the line, the missed line and the drawing at once. Each change stores
  `pieceStyleMemoryProvider[itemId]`.
- An unknown `itemId` redirects to `/apartment`, as other unknown ids do (the router's rule).

### `PiecePurchase` (`application/piece_purchase.dart`)

```dart
final class PiecePurchase {
  Future<PiecePurchaseResult> buy(String itemId, String variantId);   // held TxnId per (item, variant)
}
```

- **Rules first:** `itemPurchasable(c, p, itemId)` and not owned.
- Then `economy.buy(id, kind: SkuKind.item, skuId: itemId, variantId: variantId)`, with M09's id
  holding.
- Refusals show M09's messages: «الفلوس مش كفاية» and «عندك دي خلاص». Nothing is spent.
- The result carries two flags, both on the projection and computed from this outcome only, so a sync
  or a restore never opens `RoomDone` (spec edge case):
  - `roomCompleted`: `roomComplete(after)` and not `roomComplete(before)`;
  - `chapterCompleted`: the same for the room's chapter.

## RoomDone (`RoomDoneDialog`, research R6, R7)

A dialog over the apartment (`showAppDialog`, M08's), pushed by the rooms view after a purchase with
`roomCompleted`. It has no route of its own.

| Part | Rule |
| --- | --- |
| Room art | `room.art` through `ApartmentArt` with every piece composed (the same `RoomScene`, 260×130), and confetti once behind |
| Chip | «الفصل {n} · {done} من {total} قطع» |
| Title | «{room} خلصت!» |
| Reward pill | «+{n} بون مكافأة», where `n` is `room.completion_bonat`, plus `chapter.completion_bonat` when this purchase also completed the room's chapter (spec FR-023; `PiecePurchaseResult.chapterCompleted`). «في الطريق» shows under it while either reward is pending (R6). When received before the dialog closes, «في الطريق» goes |
| Quote | `room.done_line` with سلمى's avatar and name; hidden without one |
| «شوف المشهد» | `/story/scene/:goalSceneId?then=/apartment`, closing the dialog. Hidden when the chapter has no goal scene |
| «بعدين», scrim, back | close; the scene stays waiting (chapter bar chip, album, Home's card) |

- Focus starts on the CTA.
- The dialog announces «{room} خلصت، المكافأة {n} بون في الطريق».
- `ui/bonat_burst` isn't played: the reward hasn't arrived (R6).

## Family requests (`/apartment/requests`, `RequestsSheet`, research R11)

An `AppSheetPage` over the apartment, listing `requestStates(c, p, variantOf, requestsClaimed)`'s open
and done requests: done
first, then by room and item `order`.

| Row | Content |
| --- | --- |
| Done | the asker's `CharacterAvatar` happy; the request `text` (content); the condition; the reward chip «+{n} بون»; `AppButton.primary` «خد» |
| Open | avatar neutral; the text; the condition; the reward chip; no button |
| Empty list | the `States` empty pattern with «مفيش طلبات دلوقتي. أهل العروسة هيطلبوا لما تبدأ تجهّز.» |

- **Condition:** «{item} بشكل «{variant}»» when the request names a variant, else «اشتري {item}».
- **The asker's name:** ARB `sceneSpeaker(character)`.
- **«خد»** calls `RequestClaim.claim(requestId)`:
  - one held `TxnId` per request;
  - rules first: the state is `done`;
  - then `economy.claimRequest`.
  - On `OpApplied`, the row collapses (200 ms) and a toast shows «+{n} بون في الطريق»; offline,
    «+{n} بون في الطريق، توصل مع النت».
  - A refusal leaves the row as it was.
  - After the server's answer, the pending chip carries the sum until the base has it.
- Row label: «{asker}: {text}، {condition}، المكافأة {n} بون».

## The end of the story (research R14)

- `savingsTarget` (`features/home/domain/savings_target.dart`) gains a fourth case:
  `StoryEndTarget`. It is returned when the pack has chapters and `chapterComplete(currentChapter)`.
- `HomeSavingsCard` draws it as the goal card: «شقة العُمر», the end line «باقي الحكاية جاية في
  تحديث قريب», no bar, tap → `/apartment`. Board `HomeStoryEnd`.
- The result's apartment card treats it as `NoTarget` (hidden).
- Every `switch` over `SavingsTarget` stays exhaustive: the compiler finds the call sites.

## Tests

- **Domain:** `apartment_view_test` (both views, the boundary chapter, the end), `goal_view_model_test`
  (three goal kinds, ready, fallbacks), `room_model_test` (cell states, next target equal to Home's,
  requests count), `piece_sheet_model_test` (remembered style, line fallbacks, marks, missed line),
  `requests_test` (each state, ordering, count), `rewards_test` (economy-ops.md).
- **Application:** `piece_purchase_test` (rules first, held id, `roomCompleted` only from this
  outcome), `goal_purchase_test` (rules, held id, the story trip's card opened at
  `/apartment/pre-trip/...`), `request_claim_test` (rules, held id, refusal leaves the row),
  `start_next_trip_test` (`StartFrom.apartment`).
- **Widget:** each view and state, the chip clamp, the 44 row, tab switch, the drop-in and bubble, the
  dialog's two exits, the sheet's style change and missed line, requests rows and the empty state,
  the pending chip.
- **Design:** samples, goldens and layout tests for `AptGoal`, `AptGoalReady`, `AptRooms`, `Piece`,
  `RoomDone` and `Requests` (research R18, with their expected differences).
