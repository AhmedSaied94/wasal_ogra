# Contract: Home (الموقف)

Spec US1, US4, US6; FR-001–FR-022a, FR-049–FR-054. Artboards `C-Home`, `HomeStates`. Research R3,
R4, R9–R13, R21.

## Files

```text
lib/features/home/
├── domain/
│   ├── next_trip.dart          # nextTrip(content, progress, lastFinishedTripId)
│   ├── savings_target.dart     # savingsTarget(content, progress, jenehat)
│   └── line_card.dart          # lineCardFigures(...)
├── application/
│   ├── home_model.dart         # homeModelProvider
│   ├── arrival_queue.dart      # HomeArrivalQueue, ArrivalItem, arrivalItemsProvider
│   ├── home_slots.dart         # HomeDailyRow, MorningPiggySlot, storySceneWaiting
│   ├── checkpoint.dart         # BetweenTripsCheckpoint (+ provider)
│   ├── last_finished_trip.dart # lastFinishedTripProvider (memory)
│   └── start_next_trip.dart    # the one function every "start" button calls
└── presentation/
    ├── home_screen.dart
    ├── home_header.dart        # profile, pills (TrustedCountdown)
    ├── street_scene.dart       # StreetPainter, vehicle, sign, caller, riders
    ├── line_card.dart
    ├── start_button.dart       # «يلا نطلع!» / «البنزين خلص»
    ├── savings_card.dart       # piece / chapter goal / waiting scene
    ├── trusted_countdown.dart
    └── debug_sheet.dart        # internal builds only
```

The router's `/home` builds `ReportFullyDrawn(child: HomeStatusArea(child: HomeScreen()))` for every
flavor.

## `startNextTrip(context, ref, {required String tripId, required StartFrom from})`

Every way into a trip from Home, the card's launcher and «مشوار تاني» goes through this:

1. **An empty tank** (no window, and not M07's `firstSession.fuelLessonDue(tripId)`): open the fuel sheet's route
   (`/shop/fuel`, a placeholder until M12) and stop.
2. **The checkpoint:** `await checkpoint.pass()` (no-op until M11). If the context is no longer
   mounted, stop.
3. **Card or trip:**
   - a tutorial trip while `inFirstSession` (M07, contracts/seams.md), or `!shouldShowCard(...)`: `NavGuard.go(context, '/trip/$tripId')`;
   - otherwise `context.go('/home/pre-trip/$tripId')`.

`StartFrom` is `home` or `result`, for M15 later. The debug list bypasses this and opens
`/trip/<id>` directly.

## The screen

Columns follow `C-Home`'s order and gaps (R12). Each block:

| Block | Shows | Tap |
| --- | --- | --- |
| Profile | `CharacterAvatar('usta')` in the 48 `sun` circle; M07's `driverNameProvider` («الأسطى» by default; one line, max 84, ellipsis); `homeLevelChip(n)` | `/settings` |
| JENEHAT pill | `CurrencyPill.coin` | none; label `homeA11yCoins` |
| BONAT pill | `CurrencyPill.bonat` | `/shop`; offline: disabled with `homeA11yBonatOffline` |
| Fuel pill | `ratio(liters, max)`, `TrustedCountdown` under it; `empty` style when `fuelState == empty`; unlimited: the window's time left | the fuel sheet |
| Debug button | internal builds only, the `tasks` icon at the scene's top-start | `debug_sheet.dart` |
| Daily row | `HomeDailyRow` slot (null: nothing) | the slot's own |
| Scene | `street_scene.dart` (R13); flexible height | none (garage: phase 2) |
| Line card | `lineCardFigures`; `homeLineTripOf`, `ProgressBar.primary`, stars `ratio` | `/lines` |
| Start button | normal / empty / unlimited (R11); `CostChip` «−١» except unlimited; label includes the liter | `startNextTrip` (normal) or the fuel sheet (empty) |
| Savings card | `ApartmentPieceTarget`: «تحويش الجواز», «الفصل {n}», «الجاية: {item}», `{have} / {price} ج`, gold bar, «جاهزة للشرا!» when affordable. `ChapterGoalTarget`: goal title, «الفصل {n}», lock + «الشقة بتتفتح في الفصل {n}», progress. `storySceneWaiting`: «مشهد جديد مستنيك» instead of the bar | `/apartment` |
| Piggy | `MorningPiggySlot` (null: nothing, no space) | the slot's own |
| Bottom bar | `BottomNav`; the shop tab disabled offline; the apartment dot while `apartmentDot` | tabs |

**The apartment dot** (FR-009). A listener on `homeModelProvider.select((m) => m.apartmentDot)`
calls `newDotProvider(Section.apartment).show()` when it turns true. Opening the tab clears it
(M03).

## States

| State | Condition | Changes |
| --- | --- | --- |
| Out of fuel | `fuelState == empty` | `AppButton.danger` «البنزين خلص» + chip «اللتر الجاي {mm:ss}»; the fuel pill's empty style; both open the fuel sheet. Crossfade 150 ms (none under reduced motion) |
| Back to normal | a new view with `liters ≥ 1` | the reverse, without leaving Home |
| Offline | `reach == offline` | `HomeStatusArea`'s banner; the scene shrinks (200 ms); the shop tab and BONAT pill disabled; trips work |
| Maintenance | `maintenance != null` and online | M06's maintenance card in the banner's place; trips work |
| Early chapter | `savings is ChapterGoalTarget` | the goal card; the scene's vehicle is the next trip's (the tuktuk) with بلية |
| Fuel lesson due | M07's `firstSession.fuelLessonDue(next.tripId)` | the normal button on an empty tank; its tap goes to `/trip/<id>`, where M07's redirect shows the lesson |
| Unlimited | `fuelState == unlimited` | the pill shows the window's time left; no «−١» |
| No next trip | `next == null` | the start button disabled (never in a validated pack) |

## Arrival at Home

`HomeArrivalQueue(router, ref)` is created in `bootstrap/app.dart`'s `_afterStartup`, after
`ContentLifecycle`, and disposed with it. Its behaviour is in research R9; its items are in
[seams.md](./seams.md). From the start it holds M07's two: the due scene (rank 10) and the name
sheet (rank 20). They replace the router's `/home` scene redirect and `NameReaskHost`, which this
feature removes.

## Tests

- `test/features/home/domain/*_test.dart` (unit).
- `test/features/home/home_screen_test.dart`: every state above, its transitions, the links and the
  `startNextTrip` branches with fakes.
- `test/features/home/street_scene_test.dart`: the sign and the caller per vehicle, the re-pop, reduced
  motion.
- `test/features/home/trusted_countdown_test.dart`: a fake trusted clock, a device clock change, the
  a11y label once a minute.
- `test/features/home/arrival_queue_test.dart`.
- `test/features/onboarding/arrival_items_test.dart`: the scene before the name sheet, the name
  sheet once per launch, and the first notification ask inside the scene's item.
- `test/features/home/debug_entry_test.dart`: the entry by flavor.
- Design checks: `test/design/samples/c_home.dart`, `home_states.dart`; `*_layout_test.dart`;
  `test/goldens/design/c_home_goldens_test.dart`, `home_states_goldens_test.dart`.
