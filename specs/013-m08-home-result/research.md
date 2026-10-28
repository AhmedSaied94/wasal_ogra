# Research: Home, Pre-trip Card and Result Screen (M08)

Decisions behind [plan.md](./plan.md). Each one is grounded in the code on `master`: first at
8052a72 (M02, M05, M06 and 008.5 merged, M07 in progress), then updated on 2026-10-28 at 1b92f58,
after M07 (`012-m07-onboarding`) and M22 (`012.5-m22-animated-scenes`) merged. The update rewrote R8,
R9, R19, R22, R25 and R26; every other decision held against the merged code. M22 changes nothing
here: it animates the scenes M07 plays, and M08 only opens them through M07.

**Open questions.** The delivery plan says step 7 has nothing open in the architecture docs, and that
holds: mobile §24 has one open item, #3 (AdMob mediation networks), which is M11's. M08 owns none of
HANDOFF §9.3's questions. #4 (routing money around أبو سمّاعة) was due before M08's card mentions it
(012's spec) and was closed as "no" in this spec's Clarifications. No item in this file is left
open.

## R1. Where the screens live, and what they replace

**Decision.**

- **Folders** (mobile §5): `lib/features/home/`, `lib/features/pre_trip/`, `lib/features/result/`,
  each with `domain/` (pure), `application/` (Riverpod) and `presentation/`. The progression rules
  every later feature needs go in a new core domain, `lib/core/progress/domain/` (R2).
- **Routes.** No new route. The table already declares all three (M03's `routes.dart`):
  - `/home` (tab): `HomeScreen` replaces the placeholder in every flavor. `router.dart`'s
    `RouteNames.home when playtest` branch goes. Home keeps `ReportFullyDrawn` and
    `HomeStatusArea`, which now wraps the real screen.
  - `/home/pre-trip/:tripId` (sheet, root navigator, above the bar): `PreTripCard` in an
    `AppSheetPage`.
  - `/trip/:tripId/result` (page): `ResultScreen` replaces the placeholder and `ResultSummary`.
- **The internal tools** (US6) open from a debug button on Home as a modal sheet, not a route, so the
  route table and its tests don't change (R21).

**Rejected.** A `/home/debug` route: it adds a destination the prod table would have to hide.

## R2. The unlock rules on the phone

**Finding.** The phone checks no unlock today. M05's `validateTripStart` checks the trip exists, no
trip is unfinished and the tank. The server refuses a start as `not_unlocked`
(`backend/apps/economy/services/ops/trips.py`) by B03 research R6, implemented in
`backend/apps/progress/services/unlocks.py`. M05 handed "check unlock order before asking the
economy" to M08–M10.

**Decision.** A pure Dart mirror of `unlocks.py` in `lib/core/progress/domain/unlocks.dart`
([contracts/progress-rules.md](./contracts/progress-rules.md)):

- `vehicleOwned`, `lineComplete`, `lineUnlocked`, `tripUnlocked`, `chapterUnlocked`,
  `chapterComplete`, `roomComplete`, `currentChapter`. Each has the server's name, argument order and
  edge cases: a line without regular trips is never complete; a story trip needs only its chapter
  unlocked; the trip before a regular trip is the previous *regular* trip in the line.
- They read a `PlayerProgress` value (best stars by trip id, owned `(kind, sku)` pairs). The
  application layer builds it from `EconomyView` (`progress`, `owns`). The rules never see the
  view, so the domain imports only `content_models` (guard entry added).
- **"Finished"** means `bestStars ≥ 1`, the server's rule. A finished run always earns at least one
  star (RULES §11: `stars` is 1 once `reached`).
- **Kept the same as the server's** by porting `backend/apps/progress/tests/test_unlocks.py`'s 19
  cases one to one into `test/core/progress/unlocks_test.dart`, with the Python test's name in each
  Dart test's name. A sweep over the sample pack also checks every reachable state (R3).
- M09 (line details, vehicle purchase) and M10 (chapters, rooms) use the same file.

**Rejected.**

- A shared JSON fixture read by both pytest and Dart: it would mean changing B03's tests in a
  mobile feature. The port is cheap, and the comment in `unlocks.py` already says the two must
  move together. The plan lists it for M10, which owns the chapter rules (R26).
- Asking the economy (`startTrip`) to refuse locked trips: unlock order is a progression rule, not
  an economy one (M05 spec), and a refusal there would come too late to keep Home honest.

## R3. The next trip (FR-010, Clarifications Q1)

**Decision.** A pure `nextTrip(...)` in `lib/features/home/domain/next_trip.dart`:

1. **Startable.** A trip is a candidate only if `tripUnlocked` (R2) is true.
2. **Unfinished.** A trip with `bestStars == 0`.
3. **The line Home follows** is the line *played last*: the line of the last trip the player
   finished. With no finished trip, it is the first line by `order`.
4. If that line has a startable unfinished trip, the next trip is the first one by trip number.
5. Otherwise, the open line (unlocked, by `order`) earliest in the pack with a startable unfinished
   trip.
6. Otherwise, every open line is finished. The next trip is the startable trip with the fewest best
   stars on the line played last, the earliest by trip number on a tie.
7. A pack with no startable trip at all (impossible in a validated pack: the `start` line's first
   trip is always unlocked) gives null. Home then shows its button disabled, and a test pins this.

**Where "the line played last" comes from.** No stored record names the last trip:

- `LastResult` has the start id and the pay but no trip id;
- `TripProgress.firstCompletedAtMs` only records the first finish;
- the server's state carries the same shapes.

So it is derived:

- **In memory:** `lastFinishedTripProvider` (keepAlive), set by the result screen when a finished
  trip's result opens (R14).
- **At launch,** before any trip this run: the trip with the latest `firstCompletedAtMs`, which is
  the line the player is progressing on.

The only divergence from a stored record: a replay of an older trip in a previous run doesn't move
Home after a restart. Rule A then still lands on a line with unfinished trips, or on the newest
finished line.

**During the first session** M07's `nextTutorialTrip` overrides this (FR-011, R8).

**Tests.** A sweep over the sample pack: from a new player, finish each startable trip in every
order up to depth 6. In every state, `nextTrip` must be unlocked by the server's rules, and must
match the expected line and trip. The same sweep runs over `synthetic_packs.dart` packs with
several lines, a story trip mid-line, and a locked story chapter.

**Rejected.**

- **A stored "last line" in the preference store:** it is a piece of play history, and the
  preference store is for device preferences only (M07's constraint).
- **Adding `tripId` to `LastResult`:** it changes M05's base format, M06's wire mapping and B03's
  `state.py` for one Home hint.

## R4. The savings card, the chapter and the apartment's chapter (FR-007, FR-017–FR-020, FR-043)

**Decision.** A pure `savingsTarget(...)` in `lib/features/home/domain/savings_target.dart`, used by
Home's savings card and the result's apartment card:

- **The current chapter** is `currentChapter` (R2). Since chapters complete in order, it is the first
  chapter whose goal isn't met, which is the server's B03 R16 reading.
- **When the apartment opens** (FR-019) is read from one function, `apartmentOpens(chapters)`. It
  returns the first chapter, by `order`, whose goal is `complete_room`. In the sample and the
  release draft that is chapter 4, as the artboards draw it. M10 settles HANDOFF §9.3 #2 by changing
  only this function. There is no constant and no tunable: it is the pack's structure, not a
  balancing number.
- **Before the apartment opens,** the target is the chapter's goal:

  | `goal.kind` | Title (ARB, owner approval R18) | Progress |
  | --- | --- | --- |
  | `complete_line` | «خلّص {line}» | the line's finished regular trips / its regular trips |
  | `own_vehicle` | «اشتري {vehicle}» | JENEHAT / the vehicle's catalog price |
  | `purchase` | «اشتري {chapter}» | JENEHAT / the chapter's catalog price |
  | `complete_room` | «جهّز {room}» | JENEHAT / the room's first unowned item's price |

  `{line}`, `{vehicle}`, `{chapter}` and `{room}` are the content's names (`ar-EG`). The design's
  short «اشتري الميكروباص» is sample text. The vehicle's content name is «الميكروباص القديم», which
  the a11y label in HomeStates already uses, so the title shows the content name and ellipsizes on
  one line.
- **From the apartment's chapter on,** the target is the next piece: the first unowned item, by
  `order`, of the current chapter's goal room, with its catalog price. A current chapter whose goal
  isn't a room shows its goal as above.
- **Affordable** (FR-007 «جاهزة للشرا!», FR-009, FR-043 «تقدر تشتري …!») means JENEHAT ≥ price,
  for a target with a price. A line goal is never "affordable".
- **The waiting scene** (FR-020) is a seam, `storySceneWaiting`, false until M10 (R10).
- **The result's bar** runs from `jenehatBefore` to the balance after the pay. `jenehatBefore` is
  captured by the trip (R14), not computed by subtracting.

**Rejected.** A `apartment_opens_chapter` tunable: it isn't balancing, and M10 owns the decision.

## R5. Met passenger types and events, and the new card (FR-029)

**Decision.**

- **The met set** is derived from the active pack and `progress` (pure,
  `lib/features/pre_trip/domain/met_set.dart`): the archetypes of the passengers and the `event_id`s
  of every trip with `bestStars ≥ 1`. Because it comes from progress, it follows a restore. Trips the
  pack lacks are skipped (M05 FR-034).
- **What can be new.** Every archetype the engine supports (`content/engine/capabilities.json`)
  except `regular`, which is the baseline, and all eight in-trip events. The list is a closed table
  in the domain (`newCardSubjects`). A test checks it against `capabilities.json` and the ARB keys,
  so a new archetype can't ship without its sentence.
- **Which one shows.** The trip's passengers in definition order, then its events in definition
  order. The first subject not in the met set wins.
- **The picture.**
  - For an archetype: the look (`skin`) of the trip's first passenger of that type, through
    `looks.dart`, drawn by the new `PassengerAvatar` (R25).
  - 008.5 noted that the `claimer` and `honest` looks aren't tied to those archetypes, so the
    picture shows only that this type is aboard, never which passenger it is.
  - For an event: the design has no event glyphs. A closed table maps each event to the nearest
    existing icon:

    | Event | Icon |
    | --- | --- |
    | `bump` | `warning` |
    | `traffic` | `booster_traffic` |
    | `open_road` | `route_bold` |
    | `fare_increase` | `coin_up` |
    | `drop_me_here` | `hand` |
    | `payment_dispute` | `speech` |
    | `change_request` | `call_change` |
    | `roadside_pickup` | `hand` |

    Each sits on the card's 60 pt circle. Proper event art is a design request listed for the
    owner (plan "Owner actions").
- **The sentence describes the engine** (RULES §7, §8). The drafts (R18) were written from those
  sections. The أبو سمّاعة sentence says to call him twice and nothing about routing money
  (Clarifications Q3).
- **The name and sentence are app strings** keyed by the archetype or event id (spec Assumptions).
  HANDOFF suggested content, but the pack has no such field, and these sentences describe rules
  that live in code.
- **The rule lines (FR-028)** follow the same principle. RULES §6.1 applies only the student
  discount, so the student line («الطلبة بنص أجرة لو ورّوا الكارنيه», with the trip's percentage
  when it isn't 50) shows when the discount is above 0 and a student rides. `bag_fare_piasters` and
  `child_free_age` are authored, but no engine archetype carries a bag or a child. Their lines are
  wired to two empty archetype tables, pinned by a test against `capabilities.json`, so they
  appear only once the engine supports them (data-model.md `TripBriefing`).

## R6. The card setting (FR-024)

**Decision.**

- `preTripCardModeProvider` (Notifier) reads `pref.pre_trip_card` from the settings store, with the
  value `always` or `new_only` (`PreTripCardMode.wire`). When the key is missing or invalid, it
  falls back to the `pre_trip_card_mode` tunable, which exists with the default `always`. A device
  preference, like `pref.digit_style`.
- `shouldShowCard(trip, metSet, mode)` (pure): always for a story trip; always when the trip has
  something new (R5); otherwise only when the mode is `always`.
- **Settings** gains a `Segmented` row «كارت ما قبل المشوار» with «يظهر دايمًا» and «في الجديد بس»,
  built like the digit-style row on the current placeholder Settings screen. M14 moves it into the
  `Settings` artboard.

## R7. Buying a booster from the card (FR-031)

**Decision.**

- **The chip** offers the first booster, in the artboard's order (كيس فكة، الدفتر، صحّي النايم،
  زحمة), whose count is 0, at its catalog price. When the player has some of each, it hides.
- **A tap** opens the 008.5 spend-confirmation dialog (`AppDialog`, `States` box 4), over the sheet,
  with M02's booster-card content: the icon, name, price and balance, or «ناقصك …» when short. The
  buttons are «اشتري» and «مش دلوقتي». Its texts reuse M02's `tripBooster*` strings where they fit,
  plus a dialog-only «اشتري».
- **The purchase** calls `economy.buy(id, kind: booster, skuId)` with one `TxnId` held from the tap
  until the result arrives, so a double tap buys once (M05 R10). The results:
  - `OpApplied`: the tile's count updates in place, from `economyViewProvider`;
  - `OpRefused(insufficientFunds)`: the dialog shows «ناقصك …» and nothing changes;
  - `OpWriteFailed`: the neutral retry line, and a retry reuses the id.
- **Offline works,** since BONAT spends are optimistic up to the local balance (constitution IV,
  mobile §11). M06 rolls back a server refusal with its toast.

**Why not the undo toast** that ux-spec «الشرا» and HANDOFF give purchases under 50 BONAT. Applying
a purchase only after a 3-second undo window is M12's mechanism, by M05's hand-over. Building it
here, for one chip, would build it twice. 008.5 already chose the confirmation card for boosters in
the trip, and the card follows that. M12 may switch both to its undo flow. This conflict is listed
for the PR description (README override 3).

## R8. The first session (FR-011, FR-032): M08 reads M07 directly

**Finding** (M07 as merged, `lib/features/onboarding/`). `firstSessionProvider` gives a
`FirstSession` (`domain/first_session.dart`) with:

- `inFirstSession`, `tutorialDone`, `boostersLocked`, `askName`;
- `nextAfterResult(tripId)`: a location, the next unfinished tutorial trip's `/trip/<id>` or `/home`;
- `beforeStart(tripId)`: null, `DueScene` or `FuelLessonDue`. A due scene wins over the fuel lesson,
  and the fuel-lesson test itself is the private `_fuelLessonDue(tripId)`;
- `onArrivalAtHome()`: the due scene, if any;
- `facts.tutorialTrips` and `facts.progress`.

M07 also has:

- two router redirects on `/trip/:tripId`, for a due scene and the fuel lesson, so every start goes
  through `/trip/<id>`;
- the `/home` redirect to a due scene, and `NameReaskHost` around Home (`core/routing/router.dart`);
- `FirstSessionContinue` (`presentation/first_session_continue.dart`): the result's «كمّل», key
  `first-session-continue`. It shows while `inFirstSession`, and once on the result of the trip that
  ended the tutorial (`tutorialEndedOnProvider`). M07's `integration_test/first_session_test.dart`
  taps it by that key and expects `/home` after trip 5;
- `driverNameProvider`: a `String`, never null, with `driverNameDefault` «الأسطى» when there's no
  name.

Cross-feature imports are already the rule: `features/trip` imports `features/onboarding` for the
coach.

**Decision.** M08 uses M07 as merged. There is no seam interface, no adapter, and no
`homeDriverNameProvider`.

- **Two small additions to M07's domain,** with tests in `first_session_test.dart`:
  - `String? get nextTutorialTrip`: the first tutorial trip not finished, while `inFirstSession`,
    else null. `nextAfterResult` is rewritten on top of it, with the same results.
  - `bool fuelLessonDue(String tripId)`: the private test made public, so Home asks it directly. Read
    through `beforeStart`, a due scene would hide it.
- **Home's next trip** (FR-011) is `nextTutorialTrip` when non-null, otherwise FR-010's rule (R3).
- **No card for tutorial trips** (FR-011): a trip in `facts.tutorialTrips` while `inFirstSession`
  goes straight to `/trip/<id>`, from Home and the result.
- **The fuel lesson in place of the out-of-fuel state** (FR-011, FR-012): Home keeps «يلا نطلع!» while
  `fuelLessonDue(next)`. Its tap goes to `/trip/<id>`, where M07's redirect shows the lesson.
- **The result's main action** (FR-011): the result screen places M07's `FirstSessionContinue`
  where «مشوار تاني» goes, whenever it shows, so its key, label and `tutorialEndedOnProvider`
  handling stay M07's. Otherwise it shows «مشوار تاني» (FR-044).
- **The boosters** (FR-032): the card hides the boosters and the buy chip while `boostersLocked`.
- **The name:** Home shows `driverNameProvider`. M08 adds no default key.
- **Every start goes through `/trip/<id>`,** from Home, the card, the result and the debug sheet, so
  M07's redirects apply to all of them.

**Rejected.**

- Keeping the `FirstSessionSeam` interface with an adapter. It only existed so that M08 could merge
  before M07. With M07 merged, it would be a second layer with one implementation.
- Reading the fuel lesson through `beforeStart`: on an empty tank with a scene due, Home would show
  «البنزين خلص» although the lesson fills the tank right after the scene.

## R9. Arrival at Home (FR-022a, Clarifications Q4 and 2026-10-28)

**Finding.** M04's `HomeArrival` (`core/content/home_arrival.dart`) calls back when the location
becomes exactly `/home` from anywhere else. `ContentLifecycle` uses it for `switchIfReady()`, which
sets the new pack synchronously, before its first `await`. M07, as merged, opens two things at
arrival:

- a `/home` router redirect to a due scene (`router.dart`, through `onArrivalAtHome()`), whose
  `ScenePage` awaits `FirstSessionService.afterScene()` (M14's notification hook) before going on to
  `/home`;
- `NameReaskHost`, wrapped around Home in the router's shell. On each arrival, and on its first
  build, it opens `showNameSheet` when `askName` is true, once per launch (`nameAskedProvider`).

So a scene and then the name sheet can open on one arrival.

**Decision.** A `HomeArrivalQueue` (`lib/features/home/application/arrival_queue.dart`):

- It is created with the app's other lifecycles (`bootstrap/app.dart`, after startup), after
  `ContentLifecycle`, so its `HomeArrival` listener runs after the pack switch on the same router
  notification.
- **On each arrival** it waits for the end of the frame, then asks the registered `ArrivalItem`s,
  in order, whether each is due. It opens only the first due item, and awaits it.
- **While an item is open,** and on the arrival that returns from it, nothing else opens. An item
  that leaves for a route and comes back to `/home` doesn't trigger the next one. That waits for
  a real later arrival.
- **Nothing opens** unless the location is still `/home` when the frame ends. A trip, a sheet over
  Home, or the pause card never counts, which is M04's rule.
- **The order** is fixed by each item's `rank`:
  1. a due story scene (M07's after-trip scene, later M10's);
  2. the name sheet (M07);
  3. a later notification ask (M14);
  4. the morning piggy (M11).
- **M07's two become items, in this feature** (Clarifications 2026-10-28, Q1), in
  `lib/features/onboarding/presentation/arrival_items.dart`:
  - `DueSceneArrival` (rank 10): due when `onArrivalAtHome()` returns a scene. `open` pushes
    `/onboarding/scene/<id>?then=/home` and completes on the return.
  - `NameSheetArrival` (rank 20): due when `askName` is true and `nameAskedProvider` isn't done.
    `open` marks it done and awaits `showNameSheet(root, refused: facts.nameRefused)` on the root
    navigator, as `NameReaskHost` does.

  `arrivalItemsProvider` returns these two. M10, M11 and M14 add theirs to the same list.
- **Removed from M07's code:**
  - the `/home` row of the router's redirect;
  - the `NameReaskHost` wrapper in the shell, and the widget itself.

  M07's spec still holds: the scene plays at the next arrival at Home, before the next trip (M07
  FR-031), and the name sheet opens on arrival at most once per launch (FR-018). They just never
  share an arrival. This departs from M07's hand-over, which kept `NameReaskHost`; the PR
  description says why.
- **The first notification ask** (Clarifications 2026-10-28, Q2) stays M07's `afterScene` step.
  `ScenePage` awaits it before returning to `/home`, so the scene item's `open` completes only after
  the ask: the two count as one item. Rank 30 is only for M14's later asks.
- **FR-011's "before the next trip"** is kept by M07's `/trip/<id>` redirect, not by the queue.

**Rejected.**

- Keeping M07's `/home` redirect and `NameReaskHost` beside the queue: a scene and the name sheet
  could open back to back, which Q4 and its 2026-10-28 follow-up ruled out.
- Only changing `NameReaskHost` to skip the arrival after a scene: it leaves two mechanisms, and
  M10's and M11's items would still need the queue.

## R10. The between-trips checkpoint and the other slots (FR-021, FR-022, FR-041, FR-042, FR-046, FR-047)

**Decision.** Each later feature fills one interface, behind a Riverpod provider whose default
does nothing ([contracts/seams.md](./contracts/seams.md)):

| Seam | Default | Filled by |
| --- | --- | --- |
| `BetweenTripsCheckpoint.pass()` before the card (or a direct trip) from Home and «مشوار تاني» | returns at once | M11 (interstitial, constitution IX, glossary §3.4; not before the tutorial is done) |
| `HomeDailyRow` (the gift, the tasks, the challenge, the event) | null: no row | M13; the event circle at public launch |
| `MorningPiggySlot` | null | M11 with B07 |
| `ResultDoubleSlot` (the ×2 offer and its decline link) | null | M11 |
| `ResultTaskSlot` (the banner and the payout's BONAT chip) | null | M13 |
| `StoryAfterResult.after(tripId)` | does nothing | M10 (the chapter's scene after a story trip) |
| `storySceneWaiting` | false | M10 (FR-020) |
| `NavDestinations` (apartment, its goal view, Lines, the shop, the fuel sheet, Settings) | the current placeholders | M09, M10, M12, M14 |

- **Interfaces only, no SDK code.** The checkpoint is never called after «اطلع». Nothing
  under `lib/features/trip/` changes for ads.
- **The design samples** override each slot with a fake that draws the artboard's sample (FR-021),
  so goldens and layout tests cover the slots.
- **The ×2 state** uses the economy's `lastResult.doubled` for this trip's start (R14). Once
  doubled, the slot hides and the pay shows twice the earnings (FR-042).

## R11. The fuel countdown and trusted time (FR-003, FR-012, FR-013)

**Decision.**

- **The figures** come from `EconomyView.fuel` (`FuelView`):
  - `liters` and `max`, the real maximum (7 for subscribers once M17 lands);
  - `nextLiterAtMs`, null when full, so the countdown hides;
  - `unlimitedUntilMs`.
- **"Now"** is `TrustedClock.nowMs()`. The countdown is `nextLiterAtMs − now`, formatted with
  `NumberFormatter.countdown`.
- **Ticking.** A small `TrustedCountdown` widget runs its own 1 s `Timer` and rebuilds only itself
  (the pill's timer line, the out-of-fuel chip, the unlimited window's time left). It cancels the
  timer in `dispose`.
- **When a liter arrives,** the economy publishes a new view (M05 R17). `economyViewProvider` then
  rebuilds the pill and turns the danger button back into «يلا نطلع!» on its own (FR-012). The
  countdown never decides the state; the view does.
- **A device clock change** has no effect: trusted time ignores it (constitution VI). The test sets
  a fake clock forward and back, and checks the shown countdown against the fake trusted clock
  (SC-003).
- **Screen readers.** The pill's label is set at minute granularity, «البنزين ٤ من ٥، اللتر الجاي بعد
  ١٣ دقيقة», rounded up, so it changes at most once a minute. The ticking text is excluded from
  semantics, and there is no live region (FR-003, HANDOFF). This departs from HANDOFF's
  minutes-and-seconds label on purpose.
- **The unlimited window** (M12 sells it):
  - the pill shows the window's time left;
  - the button never turns to the danger state, and its «−١» chip hides;
  - the result's «−١ لتر» chip hides too.

## R12. Home's layout and height (FR-001, FR-014, FR-016, edge cases)

**Decision.**

- **One column** in C-Home's order, with a 16 pt gutter and 10 pt gaps. The scene card is the
  only flexible block: it takes the height left over, with no maximum, so on tall phones the
  street grows. It has a minimum of 180 pt: the vehicle's 150 plus the road. Below that, the column
  scrolls above the fixed bottom bar (edge case "Short screens").
- **Without the morning piggy** (no M11 yet), its slot takes no space and the scene card absorbs the
  52 + 10 pt.
- **The offline banner and the maintenance card** stay in `HomeStatusArea` (M06), which already sits
  above Home's content and keeps its state when a card comes or goes:
  - the scene card shrinks as the banner takes height, 332 → 282 at 844 pt;
  - the change animates over 200 ms `easeOut` (`HomeStates`), with no animation under reduced
    motion;
  - the banner keeps its single announcement (M06).
- **«محتاج نت»** (FR-014):
  - `BottomNav` gains `disabled` (a `List<bool>`): the cell draws at 0.45 opacity, does nothing on
    tap, and exposes `enabled: false` with the label «المحل، محتاج نت». The shell passes the shop
    tab as disabled while offline, on every tab.
  - The BONAT pill takes `onTap: null` with a disabled semantics flag and the same label.
  - The daily challenge and the piggy are disabled inside their slots by their own features, which
    read `serverStatusProvider`.
- **Large balances** use the pills' own growth, with `NumberFormatter.integer` grouping and no
  abbreviation.
- **A long name** shows on one line, max-width 84, with an ellipsis (C-Home).

## R13. The street scene (FR-004)

**Finding.** The design exports the scene as one flat SVG (`illustrations/screens/C-Home_02.svg`,
358×332). It holds the street, the microbus and a sample sign text. `HomeStates_02.svg` holds the
tuktuk variant. The Rive file has a `Vehicle` artboard with the four looks and a `Person` artboard
with 24 looks. It has no barker; the barker is drawn in the HTML. The loading screen already draws
`Vehicle` with a roof-sign overlay (008.5 R6).

**Decision.** The scene is built from parts so its dynamic data stays in Flutter (constitution: no
text in a canvas, and the sign and call come from content):

- **The street.** A `StreetPainter` draws it with the scene tokens, at the SVG's geometry: the sky,
  the sun disc, the cloud, five buildings, the kerb, and the road with its lane dashes. It anchors
  to the card's bottom, so a taller card shows more sky.
- **The vehicle** is a `VehicleSprite` of the next trip's vehicle (`micro_old`, or the master's
  `tuktuk` before the microbus), idle, with its static SVG as the fallback (008.5 R17).
- **The roof sign** (microbus only) is a Flutter pill with the line's last station name, as on the
  loading screen. The tuktuk has none (HomeStates).
- **The caller.**
  - On the microbus, the barker is a `Person` of look `regular` at the door, with
    `passengers/regular.svg` as the fallback.
  - On the tuktuk, بلية is `Person` look 23 / `characters/belya.svg`.
  - Their bubble is a `SpeechBubble` (character variant, no name) with «{station}.. {station}!»: an
    ARB template filled with the line's last station's name. The spec assumes no new content field.
- **The riders** are two `PassengerAvatar` heads in the windows, of looks `regular` and `hagga`,
  fixed decoration.
- **Motion** (FR-004, FR-049):
  - the bubble pops on entering and re-pops every `DesignExtras.barkerRepop` (6 s, a new motion
    constant in `design_extras.dart`, since HANDOFF gives no interval);
  - the vehicle and caller idle.
  - Under reduced motion there is no pop, and the idle loops pause on frame 0.
- **Not tappable** in the MVP: the garage is phase 2 (FR-008). The layout test skips the garage box,
  with that reason.
- **Expected golden differences** (design-checks): the barker and riders are Rive or SVG people
  rather than the HTML's drawing, and the street is painted.

**Rejected.** Copying `C-Home_02.svg` whole: its sign text is baked in, and its microbus isn't the
Rive vehicle the rest of the app uses.

## R14. From the trip to the result (FR-035, FR-036, FR-038, FR-043, FR-045)

**Finding.** `TripController._exitFor` gives `ExitToResult(tripId, result)`. `TripScreen` then
pushes `/trip/<id>/result` with `extra: result`. By then the economy has the result: the pay is in
JENEHAT, progress is updated, and `lastResult` is this trip's. The trip's record (its replay record)
is deleted before the exit (M02 R6, R7).

**Decision.**

- **What the trip hands over.** `ExitToResult` carries a `ResultArgs`:
  - `result`: the engine's `TripResult`;
  - `startTxn`: to match `lastResult` for the ×2 state;
  - `replay`: the engine's `ReplayRecord` at the end, for the quote;
  - `bestStarsBefore` and `jenehatBefore`: read from the economy's view just before
    `recordResult`.

  `TripScreen` passes it as the route's `extra`. The router accepts a `ResultArgs`, a bare
  `TripResult` (M07's «كمّل» path, until M07 updates it) or nothing.
- **Without `ResultArgs`** (a link, or an app restart on that screen), the screen shows
  `lastResult`'s pay with its outcome, and hides the stars, quote, breakdown and mistakes (FR-036).
  With no `lastResult`, or one that isn't `finished`, it goes to `/home`.
- **Nothing is computed** (FR-036):
  - stars, flags, fares, tips, over-paid change, fights, mistakes and earnings are the result's
    own;
  - the only arithmetic is the apartment bar's two balances (R4);
  - money is formatted from integer piasters or JENEHAT.
- **First three stars** (FR-045): `result.stars == 3 && bestStarsBefore < 3`.
- **The result's main action** (FR-044) is M07's `FirstSessionContinue` whenever it shows (R8),
  otherwise «مشوار تاني» to the next trip's card (or the trip, R6). Either way it first passes the checkpoint. With an
  empty tank it opens the fuel sheet's placeholder instead. Back and system back go to `/home`.
- **`lastFinishedTripProvider`** (R3) is set when a `ResultArgs` for a finished trip opens.

**The quote (FR-038).**

- A pure `pickQuote(ReplayRecord)` (`lib/features/result/domain/quote.dart`) replays the trip with
  the engine's public API (`TripEngine.start` with the record's seed, then each logged command at
  its time) and collects every `PassengerSpeaks` event. It picks:
  1. the last line in slot `thanks` or `tip`;
  2. else the last line in slot `pays`, `pays_group` or `pays_rest` from a passenger who never said
     `short_change`, `fight` or `accused` in this trip ("paid in full");
  3. else none.
- **It is deterministic.** A trip rebuilt after a kill gives the same quote as one played straight
  through, because the live events before a rebuild are lost (M01 R10) but the replay is complete.
  The text resolves as M02 R13 does: `pool.lines[variant % length]`, `{amount}` and `{station}`
  filled in, `ar-EG`. The speaker is the passenger's look: its label key, with «الشلة» for a group
  payer (`talk_log.dart`'s rule), and its avatar.
- **It runs in `Isolate.run`** from a `FutureProvider` keyed by the start id. The quote card fades in
  when it arrives and takes no space before, so the screen never waits on it. A budget test replays
  the longest-trip stress fixture under 150 ms on CI.
- A live replay is the engine's own work, not a re-implementation of rules (constitution I). It
  follows `playLog`'s order exactly: step to each command's time, then apply it. A test checks that
  `pickQuote`'s replay ends with the same `TripResult` as the record's.

**Rejected.**

- **Collecting speech live in the controller:** a rebuilt trip would lose the lines before the kill.
- **Adding `replayEngine(onEvents:)` to `trip_engine`'s exports:** it would change the engine
  package for a UI need. The public API is enough.
- **A `quotable` flag in speech pools** (HANDOFF note): it needs a schema change, and the rule above
  is deterministic and good enough.

## R15. The mistakes card and its wording (FR-039, FR-040)

**Decision.** A pure `resultSummary(result, definition)` (`lib/features/result/domain/summary.dart`):

- **Breakdown rows:**
  - fares: `faresCollectedPiasters`;
  - tips: `tipsPiasters`, shown as +;
  - over-paid change: `overpaidPiasters`, shown as − in `danger.ink`;
  - fights: the count.
- **Mistake lines.**
  - One line per entry of `mistakes`, in order. Each has the passenger's look (from the definition's
    `PassengerSpec.skin`, through `looks.dart`), its label, the kind and the amount.
  - One count line each for `fights`, `missedStops` and `lostFares` when non-zero.
- **Which star they cost** (RULES §11):
  - `fights > 0` costs the second star, and with it the third;
  - else a non-empty `mistakes` costs the third;
  - missed stops and lost fares cost no star, only pay and reputation.
- **The summary** picks one of three families, each with ICU plurals (one, two, few, other):
  - «… ضيّعت/ضيّعوا النجمتين»: fights;
  - «… ضيّعت/ضيّعوا النجمة التالتة»: mistakes only;
  - «… فاتتك، بس النجوم سليمة»: losses only.
- **Amounts in words.** The mistake strings take `{amount}` already formatted
  (`NumberFormatter.piasters`) plus a `size` select: `half` for 50, `one` for 100, `other`. So 50
  piasters reads «نص جنيه», 100 reads «جنيه», and the rest «{amount} جنيه», as the design writes it.
- **Gender.** A `feminine` flag on the look table (`looks.dart`: `hagga`, `bags_lady`,
  `mother_kids`; women's looks added later set it too) selects «نزلت» or «نزل» in the ICU strings.
- **The card is hidden** when every count is zero.

## R16. The share image (FR-048, SC-010)

**Decision.**

- **`ShareGateway`** (`lib/core/platform/share_gateway.dart`) wraps the plugin, as every plugin is
  (constitution, architecture boundaries):
  `shareImage(Uint8List png, {required String fileName, String? text})`. The production
  implementation uses **`share_plus`**, the package mobile §2 and §16 already name, at its current
  release. iOS builds must stay Podfile-free (CLAUDE.md): the version chosen must ship its iOS plugin
  as a Swift Package, and the Codemagic build is the check (owner action). Tests use a fake.
- **Rendering.** On tap, the result screen:
  1. inserts an `OverlayEntry` holding the `ShareCard` widget (360×360, the artboard), translated
     off screen inside a `RepaintBoundary`;
  2. waits for the end of the frame;
  3. calls `toImage(pixelRatio: 3)`, which gives 1080×1080, and encodes a PNG;
  4. removes the entry.
- **Before inserting** it pre-loads the avatar's SVG and the star and coin icons, through
  `flutter_svg`'s cache, so no picture is missing in the first frame. The fonts are bundled and
  already drawn on the result screen.
- **The file** is named `wassal_result_<trip_id>.png`. The text is a short caption, `shareCaption`
  (owner approval), with no store link until the listing is public (spec Assumptions).
- **The picture** follows the player's digit style. Its amount is the final one: doubled when
  `lastResult.doubled` is true for this start. It has no quote card when there is no quote, and the
  stars then centre.
- **It works offline.** Nothing is fetched. The OS share sheet handles the rest.
- **Analytics** `share {kind: result_image}` is M15's: one call site, with a comment.

**Rejected.** Building the picture through a separate `PipelineOwner` with no overlay: more code, and
the overlay frame is invisible and lasts one frame.

## R17. «عيد المشوار» (FR-034, Clarifications Q2)

**Decision.** No change. M02's direct restart (leave, then start the same trip for a liter) stays as
built, for every trip. In the first session, M07's `/trip/<id>` redirect puts its fuel lesson before
the restart when the tank can't pay. `restart_button.dart` and the controller's restart path aren't
touched, and a regression test pins it.

## R18. Strings, and the owner's approval

**Decision.**

- **Every player-visible string** goes in `lib/l10n/app_ar.arb`, about 140 keys. Prefixes:
  - `home*` (Home and its states, a11y);
  - `goal*` (the chapter goals);
  - `preTrip*` (the card and its a11y);
  - `newCard*` (names and sentences, by archetype or event);
  - `result*` (the screen, the summary, a11y);
  - `mistake*`;
  - `share*`;
  - `settingsPreTripCard*`.
- Numbers arrive formatted, and counts only select a plural (M03, M02 R22). The HANDOFF strings
  are used as written where they exist.
- **Drafts the owner approves** (an owner action, as in M07). The new card's names come from the
  product spec's tables; the sentences describe the engine:

  | Key | Name | Sentence (draft) |
  | --- | --- | --- |
  | `honest` | الأمين | لو اديته باقي زيادة أو مش بتاعه، بيرجّعهولك. |
  | `hajja` | الحاجة | بتعدّي الفلوس على مهلها، فالسلسلة اللي بتعدّي عليها بتبطّأ. |
  | `sleeper` | النايم | نايم والفلوس بتقف عنده. دوس عليه يصحى، وبعد شوية ينام تاني. |
  | `hurry` | المستعجل | صبره قليل. رجّعله باقيه بسرعة قبل ما يزهق. |
  | `big_note` | الأفندي | بيدفع ورقة كبيرة على أجرة صغيرة، وهتحتاج فكة كتير. |
  | `student` | الطالب | بيدفع نص الأجرة بالكارنيه. افتكر مين طالب. |
  | `headphones` | أبو سمّاعة | مش سامع حاجة، والفلوس بتقف عنده. ناديه مرتين. |
  | `false_claimer` | «أنا دافع!» | واحد هيقول إنه دفع وهو ما دفعش. افتكر مين دفع. |
  | `group_payer` | «خلّيها عليّا» | بيدفع عن الشلة كلها، والباقي كله بيرجعله هو. |
  | `chatty` | الرغّاي | بيشغل اللي جنبه بالكلام، فالفلوس في صفّه بتمشي أبطأ. |
  | `regular_customer` | الزبون الدايم | لو شكرته وهو مش زهقان، بيديك بقشيش. |
  | `bump` | مطب | الفلوس اللي بتتعدّى ممكن تقع. لمّها بسرعة قبل ما تضيع. |
  | `traffic` | زحمة | العربية بتبطّأ، والركاب بيزهقوا أسرع. |
  | `open_road` | طريق مفتوح | المحطات بتقرب أسرع، فالوقت أضيق. |
  | `fare_increase` | الأجرة زادت! | السعر بيتغير في نص الطريق، وفي ركاب هيدفعوا بالقديم. |
  | `drop_me_here` | «نزّلني هنا» | راكب هيغيّر محطته فجأة، وباقيه لازم يرجعله دلوقتي. |
  | `payment_dispute` | خناقة على الدفع | اتنين كل واحد يقول التاني ما دفعش. افتكر مين دفع. |
  | `change_request` | «حد معاه فكة؟» | راكب هيطلب تفكّله ورقة كبيرة من درجك. ليك تقبل أو ترفض. |
  | `roadside_pickup` | راكب في الطريق | واحد هيشاور ويركب في النص، ومعاه فلوس جديدة. |

  Other drafts:

  | Group | Drafts |
  | --- | --- |
  | Goals | «خلّص {line}» · «اشتري {vehicle}» · «اشتري {chapter}» · «جهّز {room}» |
  | Mistakes | over: «إديت {who} زيادة {amount}» · not owed: «إديت {who} {amount} وهو مالوش باقي» · unreturned: «{who} نزل/نزلت من غير باقيه ({amount})» · fights: «حصلت {n} خناقة» · missed stops: «{n} راكب عدّى محطته» · lost fares: «{n} أجرة ضاعت» |
  | Summary | «غلطة واحدة / غلطتين / {n} غلطات ضيّعت/ضيّعوا النجمة التالتة» · «خناقة واحدة … ضيّعت النجمتين» · «حاجة / حاجتين / {n} حاجات فاتتك، بس النجوم سليمة» |
  | Rule line | 50%: «الطلبة بنص أجرة لو ورّوا الكارنيه» (HANDOFF) · otherwise: «الطلبة بخصم {pct}٪ لو ورّوا الكارنيه» |
  | Barker | «{station}.. {station}!» |
  | Share caption | «قبضت {amount} في مشوار {line} في وصّل الأجرة!» |
  | Card buy dialog | «اشتري» (with M02's price, balance and short lines) |

- **The Arabic-literal guard** keeps all of it out of `lib/`.

## R19. Motion and accessibility (FR-037, FR-049–FR-051)

**Decision.**

- **Motion values** come from the design's tokens:
  - `sheetIn` 280 / `sheetOut` 200;
  - the banner and scene 200 ms;
  - the CTA crossfade 150 ms.

  New constants go in `design_extras.dart` (the raw-values guard allows only the tokens' folder):
  - `barkerRepop` 6 s;
  - `payCountUp` 600 ms;
  - `aptBarFill` 600 ms `easeOut`, after the pay.
- **The result's stars** follow HANDOFF as updated on `master` (Result "Motion", §6.5). They are
  `wassal.riv`'s `Stars` artboard (240×100, view model `Stars`, Number `stars` 0–3: three empty slots,
  and the earned ones pop in right to left, 16 frames apart). M08 sets `stars` to the result's count,
  through `RiveArtView` as the trip's art does. There is no code-driven `starIn` on the stars. Each
  condition label fades in with its star, 270 ms apart (`DesignExtras.starLabelStagger`, a new
  constant). The fallback (no file, a failed artboard check, reduced motion, and every golden) is
  the static `Stars` component (`pills.dart`) at the artboard's 58/72/58 sizes. The share image
  always draws the static stars.
- **Reduced motion** (`MediaQuery.disableAnimations`): values appear at once, and pops, bursts,
  bounces, count-ups and idle loops stop.
- **The celebration** (FR-045) plays the `Confetti` Rive artboard over the stars and the horn sound
  (M02's `horn` cue) once, with «رقم قياسي جديد» under the title. Reduced motion keeps the text and
  drops the confetti. The «sound» setting gates the horn.
- **Labels and reading order** follow each artboard's Accessibility section. They include the ones
  HANDOFF says to add:
  - the JENEHAT pill;
  - «يلا نطلع!» with «هيصرف لتر بنزين»;
  - the piggy (M11's slot);
  - «اطلع» with the liter;
  - each price cell «{station}، {price} جنيه»;
  - each star row with its state;
  - each booster tile «{booster}، معاك {n}».
- **The card's sheet** is a dialog labelled by its title. The task banner announces once (M13's
  slot, which M08 makes a live region).
- **Every tappable** is at least 44×44, including the result's decline link (M11's slot provides a
  44 pt hit area) and the sheet's close button.

## R20. The design checks (FR-052, SC-005)

**Decision.** As 008.5's [design-checks.md](../008.5-m21-design-refresh/contracts/design-checks.md),
one set per artboard:

| Artboard | Sample | Skips (reason) | App-only tappables |
| --- | --- | --- | --- |
| `C-Home` | the board's state, with fake daily row, event circle and piggy | the garage hit area (phase 2, FR-008) | the debug button (internal builds; absent from samples) |
| `HomeStates` | out of fuel + offline + chapter 2, together as drawn | — | — |
| `PreTrip` | the board's trip (three stops, a student rule, أبو سمّاعة new, two stars, one booster at 0) over Home | — | — |
| `Result` | the board's result, with fake task and ×2 slots | — | the mistakes summary (a disclosure the box file doesn't mark as `tap`) |
| `ShareCard` | the 360×360 picture | — | — |

- **Pairings.**
  - The fuel pill and «البنزين خلص» point to the fuel sheet. The design links the pill to the shop
    on C-Home, and HANDOFF's note settles it.
  - The buy chip opens the confirmation dialog, not the shop (R7).
- **Expected differences** to list in the PR:
  - the barker, riders and painted street (R13);
  - the goal title's full vehicle name (R4);
  - the pill's minute-only label (R11).
- **The goldens** are at 390×844 for every artboard except `ShareCard` (360×360), in both digit
  styles. `Result` renders its 390×1100 board scrolled as one tall surface.

## R21. The internal builds' tools (FR-054, US6)

**Decision.**

- **The button.** On dev and staging (`flavorProvider != prod`), Home shows a 44 pt
  `IconCircleButton` with the debug glyph M02's trip top bar uses. It sits at the scene card's
  top-start corner, away from the daily row.
- **The sheet.** The button opens a modal `AppSheet` with:
  - `TripList`, every trip of the active pack by line (M02 R21), each opening `/trip/<id>` directly
    (no card, no checkpoint);
  - `SyncStatusCard` (M06);
  - `OnboardingCard` (M07's testers' card: replay the first session);
  - `GalleryEntry` (008.5).

  The playtest Home's `DriverNameLine` goes: Home's header shows the name.
- **Prod** builds neither. A test on each flavor checks it, as M02's does for the list.

## R22. Testing

**Decision.** Tests first for every pure domain function, with coverage of at least 80%
(constitution XIII). Every test below runs offline.

- **Unit tests:**
  - `unlocks_test.dart`: the 19 ported cases;
  - `next_trip_test.dart`: the sweep (R3), plus each rule step;
  - `savings_target_test.dart`: every goal kind, the apartment's chapter, affordability;
  - `met_set_test.dart`;
  - `briefing_test.dart`: prices in drop-off order, rule lines, new subject, stars, boosters, the
    buy offer;
  - `card_mode_test.dart`;
  - `summary_test.dart`: every kind, plural and star family;
  - `quote_test.dart`: the pick, determinism over a kill and rebuild, and the replay ending on the
    record's result;
  - `arrival_queue_test.dart`: order, one per arrival, a return from an item, not over a trip;
  - `arrival_items_test.dart` (onboarding): the scene item before the name item, the name once per
    launch, and the ask inside the scene's item;
  - M07's `first_session_test.dart` gains `nextTutorialTrip` and the public `fuelLessonDue`, and
    `nextAfterResult` keeps its results;
  - `new_card_subjects_test.dart`: against `capabilities.json` and the ARB keys.
- **Widget tests:**
  - every Home state and its transitions (a liter back, the network back, maintenance);
  - the countdown against a fake trusted clock, with a device clock change (SC-003);
  - the card: close four ways with nothing spent, «اطلع» opens `/trip/<id>`, the new-only mode;
  - the booster purchase: applied, refused, a double tap, offline;
  - the result: every figure against the parity fixtures' recorded results (SC-004), with and
    without `ResultArgs`, first three stars, ×2 doubled;
  - the share flow against a fake gateway;
  - the debug entry by flavor;
  - the Settings row.
- **Accessibility** (`test/a11y/`): minimum sizes on Home, the card and the result at 360×640,
  360×800 and 390×844, text scale 1.0 and 1.3 (SC-006); labels; the minute-only fuel label.
- **Design checks:** R20.
- **First-session states on Home and the result** use M07's `test/helpers/tutorial_content.dart`,
  which layers the release draft's five tutorial trips over the sample. The next-trip sweep covers
  them: a tutorial trip comes next while `inFirstSession`, with no card, and FR-010 takes over after
  trip 5.
- **Integration** (`integration_test/home_loop_test.dart`): headless, like M07's
  (`fvm flutter test integration_test/home_loop_test.dart -d flutter-tester`; there is no Linux
  runner). It runs offline, from a player whose tutorial is done:
  1. Home;
  2. «يلا نطلع!»;
  3. the card;
  4. «اطلع»;
  5. the trip, driven by M02's scripted player;
  6. the result, with figures checked;
  7. «مشوار تاني»;
  8. the next trip's card;
  9. back to Home, whose line card moved.

  M07's `integration_test/first_session_test.dart` must keep passing over the real screens. It taps
  `FirstSessionContinue.buttonKey` on each result and expects `/home` after trip 5. M08 extends it
  to check Home's line card and a pre-trip card after the tutorial: step 7's "onboarding through the
  first 5 trips".
- **Performance:** the quote's replay budget; Home's first frame after a result, and after a tab
  switch, within SC-002's 1 s, timed in `home_loop_test.dart`; the cold start in the device run of
  quickstart §7.

## R23. Documents this feature's PR edits

- `docs/product-spec.md` «أنواع الركاب»: أبو سمّاعة's row loses «أو تلف الفلوس حواليه»
  (Clarifications Q3).
- `docs/delivery-plan.md`: HANDOFF §9.3 #4 marked settled ("no", in 013), and the progress tick on
  merge.
- `docs/architecture-mobile.md`:
  - §2: `share_plus` moves from planned to used, and `ShareGateway` joins §6's plugin interfaces;
  - §9: no route change;
  - §13: the phone's unlock rules (R2).
- `CLAUDE.md`, by hand at implement time:
  - the new domain folders in the guards line;
  - the `ShareGateway`;
  - `pref.pre_trip_card`.
- `docs/owner-actions.md`: M08's section (plan.md "Owner actions").

## R24. Constitution and project-rule conflicts found

| Topic | Source A | Source B | Outcome |
| --- | --- | --- | --- |
| Small BONAT buys | ux-spec «الشرا», HANDOFF: buy at once, 3 s undo | M05 hand-over: the undo window is M12's; 008.5: boosters confirm | Confirm on the card until M12 (R7) |
| Booster chip target | PreTrip artboard: link to `/shop` | ux-spec: «زرار "+" يشتري بالبونات» | Buy in place (spec FR-031) |
| Booster chip offline | HANDOFF: «محتاج نت» | mobile §11: BONAT spends work offline | Works offline (spec) |
| Fuel pill target | C-Home: `/shop` | HomeStates and HANDOFF's note: the fuel sheet | The fuel sheet (spec FR-008) |
| «عيد المشوار» | HANDOFF: via the card | M02 FR-011, 013 Q2 | Direct (R17) |
| Mistake wording | HANDOFF: content templates | 013 spec: app strings by engine kind | App strings (R15) |
| Fuel a11y label | HANDOFF: minutes and seconds | FR-003: not re-announced each second | Minutes only (R11) |
| Goal title | HomeStates: «اشتري الميكروباص» | content: «الميكروباص القديم» | The content name (R4) |

## R25. Components: one new, one changed, the rest reused where they are (a correction to the spec)

**Finding.** `PassengerAvatar` doesn't exist (the spec's Assumptions now say so). Passengers are
drawn in the trip scene by Flame and Rive. Since M07 merged, `CharacterAvatar` (story characters,
Person looks 18–23), `SpeechBubble` and `SpeechBubbleTail` are shared components in
`core/theme/components/characters.dart`. `StationTag` is still in the trip's `patches_layer.dart`.

**Decision.**

- **New `PassengerAvatar`** (`core/theme/components/avatars.dart`): a look's head in a circle, at
  the sizes the artboards use: 38 (mistakes), 46 (share), 50 (quote) and 60 (new card). The circle
  is `ground`, or `danger.soft` for a mistake. Inside is `Person` with the look's `rive` number,
  cropped like `CharacterAvatar`, with the look's SVG as the fallback. It is static: no idle loop in
  a list.
- **Changed `BottomNav`:** a `disabled` list (R12).
- **`CharacterAvatar` and `SpeechBubble`** are imported from `core/theme/components/characters.dart`.
- **`StationTag` moves** from the trip's `patches_layer.dart` to `core/theme/components/`, because
  the pre-trip card's prices use it too. The trip keeps importing it from there. With M07 merged,
  nothing else edits the file, so the move has no conflict to wait for.
- **Reused as they are:**
  - `CurrencyPill`, `AppButton` with `CostChip`, `IconCircleButton`;
  - `AppCard`, `ListRow`, `ProgressBar`, `ScreenHeader`;
  - `StatusChip`, `Stars`, `AppSheet`/`AppSheetPage`, `AppDialog`;
  - `OfflineBanner`, `StatusCard`, `VehicleSprite`, `Segmented`, `NewDot`, `DailyCircle`,
    `RewardedAdButton`. The last two appear only in the slots' fakes.

## R26. Handed to later features

- **M07** is merged, so it hands nothing on. This feature makes the changes to its code itself (R8,
  R9).
- **M09:**
  - line details open `/home/pre-trip/<tripId>` for a chosen trip, after the checkpoint;
  - its screens use `core/progress/domain/unlocks.dart`;
  - it decides whether the line card should open the current line's details instead of the map.
- **M10:**
  - `apartmentOpens()` (HANDOFF §9.3 #2);
  - `storySceneWaiting`, `StoryAfterResult`, its scene `ArrivalItem`;
  - the apartment and goal views behind the savings card;
  - a shared unlock-cases fixture, if it changes the chapter rules on both sides.
- **M11:** `BetweenTripsCheckpoint`, `ResultDoubleSlot`, `MorningPiggySlot` and its `ArrivalItem`.
- **M12:**
  - the shop and the fuel sheet behind the pills, the out-of-fuel button and «مشوار تاني»;
  - optionally, the undo flow for the card's buy chip (R7).
- **M13:** `HomeDailyRow`, `ResultTaskSlot`.
- **M14:**
  - the card setting's row in the `Settings` artboard;
  - the first notification ask through M07's `FirstSessionHooks.afterScene`;
  - any later ask as an `ArrivalItem` of rank 30.
- **M15:** `share {kind: result_image}` at the share call site.
