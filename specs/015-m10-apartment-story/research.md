# Research: Apartment, Story Chapters, Scenes and Family Requests (M10)

Decisions behind [plan.md](./plan.md), against master after M09 (014) merged. Each says what was
decided, why, and what was rejected. "Spec FR-n" points at [spec.md](./spec.md); "Q1"–"Q5" are its
Clarifications of 2026-10-29.

## R1. The tab's two views, the current chapter and the end of the story (FR-001–FR-004, FR-027, Q1)

**Decision.**

- `/apartment` shows one of two views, chosen by a pure `apartmentView(content, progress)` in
  `lib/features/apartment/domain/apartment_view.dart`:
  - **goal view** (`AptGoal`, `AptGoalReady`) while the current chapter's `order` is below
    `apartmentOpens(content).order`, or there is no room chapter at all;
  - **rooms view** (`AptRooms`) from that chapter on.
- **The current chapter** is M08's port, `currentChapter(c, p)`: the highest unlocked chapter not
  complete, else the last complete, else the first (`unlocks.dart`). Spec FR-003's "first chapter
  whose goal isn't met" is the same while one is open.
- **The end of the story** is `chapterComplete(c, p, currentChapter.chapterId)`: every chapter of the
  pack is done. The rooms view then shows the last room finished with the end note (R14).
- `apartmentOpens` keeps M08's rule (the first `complete_room` chapter); no constant, no tunable. Q1
  confirms the design: chapters 1–3 show their goal, chapter 4 the salon.

**Why.** M08's savings card already splits the story at `apartmentOpens` (M08 research R4), so Home,
the result's card and the tab can't disagree.

**Rejected.** A tunable "apartment opens at chapter n": it isn't balancing, and the pack's structure
already says it (M08 R4).

## R2. When a scene plays: the moments (FR-028, FR-029)

**Decision.**

- **Three moments, no new enum value.** `ScenePlays` keeps M07's `opening` and `after_trip`. A scene
  without `plays` unlocks **when its chapter's goal is met**. M07's schema description already says
  "Absent: M10's rules (album, chapter end)"; it is reworded to "Absent: when the chapter's goal is
  met (M10)".
- **New content rules** (R16): at most one scene without `plays` per chapter (V-C10); scene ids unique
  in the pack, since routes and the server's `scenes_seen` name them (V-C11); at most two spoken
  (non-narrator) lines per panel, since the viewer shows two bubbles (V-C12).
- **A scene is unlocked** (`lib/core/progress/domain/story.dart`, pure):
  - `opening`: always;
  - `after_trip`: its trip has been finished (`PlayerProgress.finished`, ≥ 1 star);
  - goal: `chapterComplete(c, p, chapter)`.
- **Story order** (album, timeline, "the first waiting scene"): chapters by `order`, then the scenes
  in the order the chapter lists them. Authors list them as the story tells them; the release draft's
  chapter 2 has its goal scene (`what_do_you_do`) before its after-trip scene (`father_approves`), so
  no rule on the moment's kind could order them.

**Why.** A third enum value would need a B04 column change and say nothing the absence doesn't. Each
chapter's goal happens once, so one scene for it is enough; the release draft has at most one.

**Rejected.**

- `plays.kind = goal_met`: the same meaning with a backend migration.
- Ordering scenes by moment kind: wrong for chapter 2 (above).

## R3. Seen, due and waiting (FR-030–FR-032, FR-052, FR-054)

**Decision.**

- **Seen** has one source of truth, the economy's projection (R5): a `story_progress` operation per
  scene, and the server's `story.chapters[].scenes_seen` after a state replacement. M07's
  `first_session.scenesSeen` stays as M07's own flag and is written alongside.
- **One entry point records a scene as seen:** `StoryService.recordSeen(sceneId)` in
  `lib/features/story/application/story_service.dart`. It calls M07's `FirstSessionService.sceneSeen`
  (marks M07's flag; its step only rises, `reachStep`) and submits `story_progress` through the
  economy, which refuses a scene already seen without storing anything (R5). M07's `ScenePage`
  calls it instead of `sceneSeen` directly.
- **Backfill** (FR-052): once the economy and the content are ready at boot, `StoryService.backfill()`
  records every scene in M07's `scenesSeen` that the projection lacks. It is the same call, so it
  runs once in effect.
- **Due** reuses M07's `first_session.scenesDue` (its writer stays `DriftFirstSessionStore`, through
  `FirstSessionService.addSceneDue`). M07 already makes an `after_trip` scene due on a first finish
  seen on this phone (`onView`). M10 adds the goal scenes:
  - `StoryDueWatcher` (keepAlive, in `bootstrap/app.dart` beside `HomeArrivalQueue`) watches the
    economy's view. When a chapter is complete in the projection but not in the confirmed base (R6),
    the completion came from an operation on this phone. If that chapter's goal isn't a room, its goal
    scene becomes due. `addSceneDue` is idempotent, so a restart before the sync does no harm.
  - A room's completion is not made due: `RoomDone` offers its scene (R7), and «بعدين» leaves it
    waiting, not due (spec FR-030).
  - A server state replacement makes nothing due: base and projection both have the completion.
- **Waiting** is derived: unlocked and not seen. `waitingScenes(...)` returns them in story order.
  `storySceneWaitingProvider` (M08's slot) is overridden with "any scene waits".

**Why.** M07's due list already drives both places a scene plays by itself, the arrival item and the
`/trip` redirect (`beforeStart`), so goal scenes join them with no new queue. Comparing the
projection with the base tells a local completion from a restored one without hooks in M09's
purchase or the trip controller.

**Rejected.**

- A separate M10 due table: a second queue beside M07's, with two arrival items to order.
- Hooks in `VehiclePurchase` and the trip's result: three call sites in other features for one rule.
- Storing "seen" only in `first_session`: it doesn't sync, and a restore couldn't fill it.

## R4. Where scenes play, and in which look (FR-029–FR-036, Q5)

**Decision.**

| Moment | Where it plays | Look |
| --- | --- | --- |
| The opening | M07's `/onboarding/intro` | M07's `ScenePlayer` (`Intro`) |
| A due scene in the first session (سلمى's) | M07's `DueSceneArrival` and `/trip` redirect | M07's `ScenePlayer`, with its after-scene step |
| A due scene after the first session | the same two places | the scene viewer, `/story/scene/:sceneId?then=…` |
| A story trip's scene, after its first finish | M08's `storyAfterResultProvider`, before «مشوار تاني» goes on; on the way Home, the arrival item | the scene viewer |
| A finished room's scene | `RoomDone`'s «شوف المشهد» | the scene viewer |
| A waiting scene | Home's savings card while it shows «مشهد جديد مستنيك»; the rooms view's chapter bar | the scene viewer |
| Replays | the timeline (`/story/:chapterId`, the chapter's unlocked scenes in order) and the album (`/story/scene/:sceneId`) | the scene viewer, M07's scenes included (Q5) |

- `DueSceneArrival` and the router's `beforeStart` redirect choose by `FirstSession.inFirstSession`:
  inside it, M07's `/onboarding/scene/:id`; after it, `/story/scene/:id`. That is the only change to
  M07's flow, and its goldens stay as they are (Q5).
- **`StoryAfterResult`** (M10's implementation of M08's slot): when the trip is a story trip and its
  chapter has a scene `after_trip` that trip, unlocked and not seen, it pushes the viewer and awaits
  it. M08 calls it only from «مشوار تاني» (`result_screen.dart`, `_again`). Leaving to Home instead
  reaches the same scene as the arrival item, because M07 made it due. So "any button" (spec FR-029)
  holds, with Home's way a frame later.
- **Home's savings card** taps to the first waiting scene while it shows the label (spec FR-031): a
  small change to `savings_card.dart`'s `onTap`, which today always goes to `/apartment`.
- **Routes** (`routes.dart`, `router.dart`): `/story/album` and `/story/scene/:sceneId` are new, both
  root pages before `/story/:chapterId` (literal segments first, M09's rule). `sceneId` is validated
  by the scene id pattern. An unknown scene or a chapter with nothing unlocked goes to `then`, else
  `/apartment`.

**Why.** Q5 keeps the first session as M07 tuned and tested it, while everything after it uses the
`SceneViewer` artboard. Routing by `inFirstSession` is one condition in two places that already
decide where a due scene goes.

**Rejected.** A second `SceneViewer` for M07's scenes: it would change M07's goldens and its
notification ask, which Q5 keeps.

## R5. Two new economy operations on the phone (FR-049–FR-054, constitution IV, VI, XIII)

**Decision.** `story_progress` and `claim_request` become local operations of M05's economy, recorded
in `ledger_ops` and synced by M06 like `settings_update` and `tutorial_gift` (M07). Tests first, as
for every validator (constitution XIII).

| | `story_progress` | `claim_request` |
| --- | --- | --- |
| Request | `StoryProgressRequest(chapterId, sceneId)` | `ClaimRequest(requestId)` |
| Local checks, in order | the scene is in the chapter (`unknown_sku`); not seen yet (`already_recorded`, not stored). The scene's unlock is `StoryService`'s check first, as unlock order is the caller's for M05's `buy`: the economy domain may not import the progress rules | the request is in the pack (`unknown_sku`); not claimed yet (`already_granted`, not stored); its item owned, in its variant when it names one (`not_eligible`) |
| Projection | adds the scene to `EconomyState.scenesSeen[chapterId]` | adds the request to `EconomyState.requestsClaimed`; **no BONAT** (FR-024) |
| Wire payload | `{chapter_id, scene_id}` + `content_version` | `{request_id}` + `content_version` |
| Server (B03, unchanged) | `ops/story.py`: `unknown_sku`, `not_unlocked`; a repeat changes nothing | `ops/grants.py`: `unknown_sku`, `already_granted`, `not_eligible`; grants `reward_bonat` |

- **Code** (M07's pattern, M06's research R12): `OpType` gains the two wire names; two `OpRequest`
  subclasses; their `validate`/`apply`/`stillValid`/`requestMatches` in a new `story_rules.dart`
  beside `profile_rules.dart` and `gift_rules.dart`; `op_wire.dart`'s `contentVersionTypes` gains
  both.
- **State.** `EconomyState` gains `scenesSeen` (`Map<String, Set<String>>`, by chapter wire name) and
  `requestsClaimed` (`Set<String>`), in its canonical JSON (`projection_base.state`).
- **Drift schema 5** (`schemaVersion` 4 → 5, `make-migrations`):
  - `ledger_ops`'s `op_type` check admits the two types, which needs the table rebuilt as M07's
    step 4 did (`TableMigration(schema.ledgerOps)`);
  - `player_state` gains `scenes_seen` and `requests_claimed`, JSON text with `'{}'` and `'[]'`
    defaults, like `first_session`'s lists. The economy store stays their only writer.
- **The server's state** (`stateFromSnapshot`, M06's "story isn't mapped yet"): `story.chapters[]`'s
  `scenes_seen` fill `scenesSeen`, and `story.requests_claimed` fills `requestsClaimed`. A chapter or
  scene the active pack lacks is kept (M04's rule), and readers skip it. `StateSnapshot` gains typed
  `StateStory`, from the shape already in `contracts/openapi.yaml` (`Story`, `ChapterState`).
- **Request ids.** One `TxnId` per player intent, held by the caller until applied (M09's
  `VehiclePurchase`): the claim's sheet row, and `StoryService.recordSeen` per scene.

**Why.** One log, one sync path, one rollback, and the state replacement already in place. A
rejected claim rolls back by M06's rule, so the request returns to the list (spec FR-044).

**Rejected.**

- A separate story outbox: a second sync queue, a second rollback, a second state mapping.
- Allowing a repeat `story_progress` into the log: the server would accept it as a no-op, but it
  costs a row and a round trip per replay.

## R6. Rewards on their way (FR-023, FR-024, FR-044)

**Decision.**

- The phone never adds BONAT for a room, a chapter or a request (constitution IV; M05: "BONAT rises
  only through a base from the server").
- **On its way vs received** compares the projection with the **confirmed base**, the server's last
  state plus the operations it accepted (M06 folds accepted operations into the base):
  - a room's or chapter's reward is on its way while it is complete in the projection and not in the
    base;
  - a claim is on its way while the request is claimed in the projection and not in the base;
  - once the base has it, the reward is received, and the server's wallet has already raised the
    balance.
- `EconomyView` gains `confirmed`: the base's ownership, progress, `scenesSeen` and `requestsClaimed`
  (no balances). `pendingRewards(c, projection, confirmed)` in `lib/core/progress/domain/rewards.dart`
  returns each pending reward with its source and amount, from the content's `completion_bonat` and
  `reward_bonat`.
- **Where it shows:**
  - `RoomDone`'s reward pill: «+{n} بون مكافأة» with «في الطريق» while pending;
  - a sun chip «+{n} بون في الطريق» beside the JENEHAT pill in both views' headers while any reward
    is pending (an undrawn state, R18);
  - a toast on a claim (R11).

**Why.** The server's state doesn't list room or chapter grants (B03 `state.py` exposes only the
tutorial and the claimed requests), but it does carry the ownership, progress and story that
complete them. Since the server pays a completion in the batch that completes it (B03 R6), "complete
in the base" means "paid".

**Rejected.**

- Reading the `granted` list of sync answers: M06 doesn't keep answers, and a state replacement
  would lose them.
- Showing the reward as granted at once (HANDOFF `RoomDone`, "ledger `room_complete`"): the phone
  can't grant BONAT.

## R7. Purchases: pieces and chapter goals (FR-007, FR-008, FR-014, FR-020, FR-022, FR-050)

**Decision.**

- `PiecePurchase` and `GoalPurchase` in `lib/features/apartment/application/`, on M09's
  `VehiclePurchase` pattern: one held `TxnId` per intent (`economy.newRequestId()`), cleared on
  `OpApplied` or a final refusal, kept on `insufficient_funds` and `OpWriteFailed`. The button is
  disabled while one is in flight.
- **Rules first** (spec FR-050): a piece needs `itemPurchasable` and not owned; a goal needs
  `chapterUnlocked`, the chapter's goal `purchase`, and not owned. M05's `validateBuy` checks the
  catalog, the variant, the balance and ownership, not unlock order (M05's hand-over).
- **After a piece's `OpApplied`:**
  1. the sheet closes;
  2. the rooms view plays the drop-in and سلمى's bubble with the chosen style's comment;
  3. if the room just became complete, `RoomDone` opens once, from this purchase's outcome, never
     from a sync.
- **After a goal's `OpApplied`:** a short coin burst, then `startNextTrip(tripId: storyTripId, from:
  StartFrom.apartment)` when the chapter has a story trip not finished. The card opens at a new
  `/apartment/pre-trip/:tripId`, so closing it lands on the apartment, which now shows the rooms
  (M09's `linePreTrip` pattern). Without a story trip, the view simply updates.
- **Chapter 2's goal** opens M09's `/lines/vehicle/:vehicleId` sheet from the ready card. M09's
  sheet buys it, and `StoryDueWatcher` makes `what_do_you_do` due (R3).
- **Refusals** show M09's messages (insufficient funds, already owned) and spend nothing.

**Why.** It is the same shape M08 and M09 proved, and the room-complete check after the outcome keeps
`RoomDone` to purchases made here (spec edge case: no dialog after a restore).

**Rejected.** Opening the chapter's scene after the shabka (HANDOFF `AptGoalReady`): the owner
decided trip, then scene (2026-10-27), so the scene is timed after `line_gamaa.18` in content.

## R8. The goal view (FR-005–FR-007)

**Decision.**

- **The model.** `GoalViewModel` reuses M08's `savingsTarget` for the goal, amount and progress, and
  adds the content's new fields: goal art, character line and speaker, ready line. The chapter bar
  reads «الفصل {n} · {chapter title}».
- **Per goal kind:**
  - `complete_line`: «{done} / {total} مشوار» (ARB) in place of «… ج», and never ready;
  - `own_vehicle`: amount against the vehicle's price; the ready button «اشتري {goal}» opens the
    vehicle sheet;
  - `purchase`: amount against the chapter's price; the ready button «اشتري {goal}» with the price
    chip buys it (R7).
  - Ready means `savingsTarget(...).affordable` and not owned, the same test Home's «جاهزة للشرا!»
    uses.
- **The bar** animates from the last value seen. That value is kept in memory per chapter, so a
  return to the tab animates only the change.
- **The teaser card** keeps the drawn `paper` with the `outline` ring: a teaser, not a locked
  control. The HANDOFF note leaves it to the designer, and the design draws it so.
- **Art.** `goal_art` names a drawing (R17); without one, the goal's own art: the vehicle's
  `VehicleSprite` for a vehicle goal, the tuktuk for a line goal, the ring drawing for a purchase.

## R9. The rooms view (FR-009–FR-016)

**Decision.**

- **The room** (`RoomScene`, 358×300 design space scaled to the card's width, as HANDOFF says):
  - the room's drawing (`room.art`);
  - each owned piece's variant drawing in its `slot` rect;
  - each missing piece's dashed outline in the same rect, with its chip anchored at the rect's
    centre and clamped 8 pt inside the card (HANDOFF note).
  - The dashed outline and the chip are widgets; the drawings are SVGs. Without a drawing, the
    fallbacks of R17.
- **Tabs**: the three glossary rooms in `RoomId` order. A room whose chapter is unlocked is
  selectable, the rest locked (`Segmented`'s locked segment, as drawn). Each tab's hit area extends
  to the 44 pt row.
  - Rooms the pack lacks take their names from ARB (R13).
  - The selected room is in memory; on entry, the current chapter's room.
- **The grid** lists the room's items by `order`. The next target is M08's `_nextPiece` (the first
  unowned item by `order` with a JENEHAT price), so Home's «الجاية …» and the grid agree.
  - Affordable, it shows «تقدر تشتريها» in `primary` in place of the shortfall (undrawn, R18).
  - The column scrolls.
- **The chapter bar** shows the chapter title over its `tagline`, and «جهّزت {owned} من {total}».
  While the finished room's scene waits, its trailing side is a «شوف المشهد» chip; the rest still
  opens the timeline (spec FR-016).
- **The strip** «خلّص {room} وافتح مشهد «{scene title}»» names the chapter's goal scene. It hides
  when the room is finished.
- **The requests button** and its `CountBadge` (`primary`/white, HANDOFF §9.1 #8) open
  `/apartment/requests`.
- **The pending chip** of R6 sits beside the JENEHAT pill.
- **After a purchase:** the piece drops in over about 300 ms (`MotionTokens.dialogIn`), and سلمى's
  bubble pops with `bubblePop` and stays until the next tap or scroll on the view: no timer, so no
  timing number. Under reduced motion, fades only.

## R10. The piece sheet (FR-017–FR-021, Q4)

**Decision.**

- `/apartment/item/:itemId` (an existing route) as an `AppSheetPage` with its own header (M09's
  `ownHeader`).
- **The style** starts at `pieceStyleMemoryProvider` (keepAlive, in memory: the style last picked
  per piece in this run), else the item's first variant. A restart forgets it, which is harmless.
- **سلمى's line** is the selected variant's `comment`, else the item's `comment`, else hidden. The
  same line is her bubble after the purchase.
- **The request mark** (Q4): the style an unclaimed, still-possible request names carries a small
  `StatusChip` «طلب {asker}» (for example «طلب أم العروسة») under its name. While another style is
  selected, a line above the button reads «لو اخترت ده، طلب {asker} هيفوتك» in `danger.ink` 13/700.
  Both are undrawn (R18), and the line wraps.
- **The button:**
  - Unaffordable: «ناقصك {n} ج» and «اطلع مشوار» with the fuel chip (HANDOFF §9.1 #4). It starts
    Home's next trip through `startNextTrip(from: StartFrom.apartment)`: the card at
    `/apartment/pre-trip/:tripId`, or the fuel sheet on an empty tank.
  - Affordable: «اشتري» with the price chip «−{n} ج» (HANDOFF §9.2).

**Rejected.** Persisting the last style: it is a UI convenience, and no other feature needs it.

## R11. Family requests (FR-040–FR-045, Q4)

**Decision.**

- **State.** `requestStates(c, progress, variantOf, requestsClaimed)` in
  `lib/core/progress/domain/requests.dart` gives each request of the pack one of these states.
  `variantOf` is `EconomyView.variantOf`, since `PlayerProgress` holds no styles:
  - **locked**: its room's chapter isn't unlocked;
  - **open**: its item isn't owned;
  - **done**: owned, in the variant when it names one, and not claimed;
  - **missed**: owned in another variant;
  - **claimed**: in `requestsClaimed`, whether that came from a pending claim or from the server.
- **The count** on «الطلبات» is open + done. **The sheet** lists the open and done ones, done first,
  then by room and item `order`.
- **The asker** is the request's new `character` (R16); the face is `CharacterAvatar` with the
  happy expression when done and neutral when open, as drawn. Names come from ARB `sceneSpeaker`.
- **The condition** reads «{item} بشكل «{variant}»» when a variant is named, else «اشتري {item}».
  These are ARB templates around the content's names, worded so no preposition joins a name: HANDOFF's
  «للنجفة» would need Arabic spelling rules in code (M09 reworded its impact line for the same
  reason). The owner approves the wording (R19).
- **«خد»** calls `RequestClaim` (one held `TxnId`):
  - on `OpApplied` the row collapses (200 ms, `toast` timing) and a neutral toast says «+{n} بون في
    الطريق، توصل مع النت» when offline, or «+{n} بون في الطريق» online, until the sync;
  - the header chip of R6 carries the sum;
  - a refusal leaves the row.
- **Empty list:** the `States` empty pattern, with «مفيش طلبات دلوقتي. أهل العروسة هيطلبوا لما
  تبدأ تجهّز.» (draft, R19).
- **The counted row** (`Requests` 2c, «٣ مشاوير بتلات نجوم») is not built: the server's
  `claim_request` checks only a piece and its style (B03 R9). Its boxes are skipped in the layout
  test, with the reason.

**Why.** It follows the server's rule exactly, so a claim the phone offers is never refused as not
eligible, and a missed request disappears before it can disappoint (Q4).

## R12. The scene viewer (FR-033–FR-036)

**Decision.**

- `SceneViewerPage` in `lib/features/story/presentation/`, built to `SceneViewer`, reusing M07's and
  M22's parts:
  - `ComicPanel` (lines list, `shown`);
  - `PanelArt` (Rive panel when animated, else drawing, else `PanelFallback`);
  - `PageDots`;
  - M22's talking turns.
- **Taps.** While a panel's bubbles are still appearing in turn, a tap shows them all. The next tap
  moves to the next panel. «تخطّى», back and «كمّل» end the scene. The panel is one button labelled
  «اللوحة الجاية».
- **A sequence.** `/story/:chapterId` plays several scenes one after another. The top bar shows each
  scene's title and the dots restart. «كمّل» on a scene's last panel moves to the next scene, and on
  the last one ends.
- **Bubbles.** Up to two per panel (V-C12). The first sits at the panel's start side, the second at
  its end side, lower, as `SceneViewer` places them (top 120 start, top 236 end). The tail points
  down. A narrator line is the caption chip (M07's rule).
- **Speakers.** ARB `sceneSpeaker`; `usta` is the driver's name (`driverNameProvider`), «الأسطى»
  without one (M07's rule).
- **Recording.** Reaching the last panel, «كمّل», «تخطّى» or back on a first view calls
  `StoryService.recordSeen` (R3); a replay records nothing new (the economy refuses a repeat
  locally).
- **Share.** M08's off-screen render (`renderSharePicture`) is generalised to
  `renderOffscreenPng(context, Widget, Size)` in `lib/core/platform/`. `ShareCard` and the scene
  share both use it. The scene share renders `ScenePanelShare` (the still drawing, never Rive, and
  its bubbles) at 358×540 ×3 and calls `ShareGateway.shareImage`. It works offline.
- **Motion.** The panel slides in from the reading side with a fade (`sheetIn`); bubbles pop
  staggered 150 ms; the current dot widens. Under reduced motion, a ≤ 150 ms crossfade and still
  drawings (M22's rule).
- **Announcements.** «اللوحة {i} من {n}» politely on every advance.

## R13. The timeline and the album (FR-037–FR-039, Q3)

**Decision.**

- **The timeline** (`ChaptersPage`, `/apartment/chapters`) lists the seven glossary chapters by
  `ChapterId` order. A chapter in the pack takes its state from the rules; one the pack lacks is
  locked, with its ARB name (`chapterTeaserName`: «المطبخ», «أوضة النوم», «الفرح»).
  - **Done row:** the thumbnail is the first panel of the chapter's last unlocked scene in story
    order; «شوف المشهد» opens `/story/:chapterId`. With no unlocked scene, there is no button.
  - **Current row:** a room goal shows «{owned} من {total} قطع», the piece names joined with «، »
    and «المشهد: {goal scene title}». Any other goal shows M08's goal title and «{saved} / {target}
    ج» or «{done} / {total} مشوار» (undrawn, R18).
  - At the end of the story there is no current row, and the rail is full.
- **The album** (`AlbumPage`, `/story/album`, Q3) shows one card per scene of the pack in story order,
  and the count «{unlocked} من {total}».
  - Unlocked card: the first panel's still drawing, «الفصل {n}», the scene title and «اتفرج تاني»,
    which opens `/story/scene/:sceneId`.
  - Locked card: the locked look and «بيتفتح لما الفصل يخلص».
  - Art ships in the app, so no card needs «محتاج نت» (HANDOFF's case doesn't arise).
- **Names of chapters and rooms not in the pack** live in ARB, keyed by glossary id. They are
  interface text for a locked teaser, not story content, so constitution VII is met. A pack that adds
  the chapter replaces the ARB name with its own title.

**Rejected.** Hiding chapters the pack lacks: `Chapters` and `AptRooms` draw all seven chapters and
three rooms (FR-037, FR-010).

## R14. The end of the available story (FR-027)

**Decision.**

- **Detection:** R1's end of the story.
- **The rooms view:** the last room finished, the strip replaced by an `InfoStrip` «باقي الحكاية
  جاية في تحديث قريب» (draft), and the chapter bar's progress full.
- **The timeline:** every pack chapter done, no current row.
- **Home:** `savingsTarget` returns a new `StoryEndTarget` instead of `NoTarget` when the current
  chapter is complete and the pack has chapters. `HomeSavingsCard` draws it as the goal card with the
  end line and no bar, and it opens the apartment. The result's apartment card stays hidden
  (`SizedBox.shrink`, as for `NoTarget`).

**Why.** `HomeSavingsCard` throws on `NoTarget` today and Home hides the card, so a finished player
would lose the savings card silently. A sealed case keeps every `switch` exhaustive.

## R15. Story trips' riders (FR-046–FR-049, Q2)

**Decision.**

- **Content** (R16): the chapter gains `story_trip_info` (closed object `StoryTripInfo`), allowed
  only with `story_trip_id`:
  - `title` (LocalizedText);
  - `condition`? (LocalizedText);
  - `fail_reason`? (LocalizedText, only for a trip with `rules.no_fights_required`, V-C9);
  - `riders[1..2]` of `StoryRider {character: StoryCharacter, seat: seat_id, comments?:
    RiderComments}`.
  - `RiderComments` is a closed object of optional `SpeechKey`s: `short_change`,
    `false_accusation`, `fight`, `missed_stop`, `impatient`.
  - The trip definition is untouched, so the engine, the solver and the parity fixtures don't change.
- **Seats** (V-C7): a rider's seat must be one of the trip's `seats` that **no passenger of the trip
  names** (boarders included), and the riders' seats must differ. The engine has no "kept empty"
  notion: a seat nobody names simply stays empty, and the chain only hops through occupied seats.
  So a rider drawn there changes no rule.
- **The scene** (`TripGame`): a `RiderComponent` per rider seat draws `wassal.riv`'s `Person` with
  the character's look (18–23, `CharacterAvatar.looks`) at the seat's `SeatLayout.face`, with the
  static SVG fallback. It has no tag, no hit area and no money. Rive's `mood`/`surprised` inputs
  play on a comment (008.5's contract reserves them).
- **The top bar** (`TripTitle`): the `StatusChip.story` over the content's `title` instead of «{line}
  · {n}», when present.
- **The strip** (`StoryStrip`): the content's `condition` in place of `tripStoryNoFights`, when
  present. A story trip with a condition but no rule shows the strip without the broken state.
- **The failure** (`failSummary`): the content's `fail_reason` replaces `tripFailStoryRule` when
  present.
- **Comments** (`lib/features/trip/domain/rider_comments.dart`, pure):
  - Triggers: a `ReputationChanged` whose cause is `shortChange`, `falseAccusation`, `fight`,
    `missedStop` or `impatient`. Over-change has no reputation cause and stays silent (constitution
    XI; the spec's FR-048 was corrected from "over-change").
  - Speaker: the first rider whose `comments` names a pool for that cause; none, no comment.
  - Line: `pool.lines[pick % len]`, where `pick` is the first value of a fresh `Xorshift32` seeded
    with the trip's `seed` XOR (`n` + 1), `n` the comment's ordinal. That is deterministic from the
    trip seed (constitution XII) and never touches the engine's PRNG state. The engine exports
    `Xorshift32` for it (one line in `trip_engine.dart`, no rule change), so the app doesn't copy
    the algorithm.
  - Timing: a rider comment uses بلية's reserved bubble slot (`BubbleQueue` `reserved`, `belyaAt`'s
    rules): one character bubble at a time, shown at least `trip_bubble_min_ms_<line>`. A comment
    that can't show within that time is dropped, so comments never pile up.
- **No new tunable.** Spec FR-048's spacing is the existing `trip_bubble_min_ms_<line>`, already a
  Remote Config key with a bundled default.

**Why.** A chapter names exactly one story trip, and its presentation is story content, not a trip
rule. Keeping it off the trip keeps M01's input and B05's mirror untouched.

**Rejected.**

- Presentation fields on `trip.schema.json`: they would change the engine's input, the replay
  record's embedded definition and the solver's models, for data no rule reads.
- Speech keys by convention (`story.<character>.<cause>`): hidden semantics in ids, which M07's R5
  rejected for scenes.
- A rider comment on over-change: constitution XI.

## R16. Content fields and validation (FR-053–FR-055)

**Decision.** Through the whole pipeline, as M07 and M09 did (schemas, codegen, examples, sample,
golden, dev bundle, B04). The schema set stays 1.0: `content/source/pack.json` doesn't exist.

| Part | Field | Required | Shape |
| --- | --- | --- | --- |
| `common` | `StoryCharacter` | — | enum `usta`, `salma`, `bride_father`, `bride_mother`, `moallem`, `belya` |
| `chapter` | `goal_art` | no | `Slug` |
| `chapter` | `goal_line` | no | `CharacterLine {speaker: StoryCharacter, text: LocalizedText}` |
| `chapter` | `ready_line` | no | `LocalizedText` |
| `chapter` | `tagline` | no | `LocalizedText` |
| `chapter` | `story_trip_info` | no | `StoryTripInfo` (R15) |
| `chapter.Scene` | `title` | **yes** | `LocalizedText` |
| `room` | `art` | no | `Slug` |
| `room` | `done_line` | no | `LocalizedText` (سلمى's, in `RoomDone`) |
| `item` | `slot` | **yes** | `ItemSlot {x, y, w, h}`, integers, inside 358×300 |
| `item` | `comment` | no | `LocalizedText` (for a piece with one variant) |
| `item.ItemVariant` | `comment` | no | `LocalizedText` (سلمى's line for that style) |
| `family_request` | `character` | **yes** | `StoryCharacter` |

- **Required only where a screen has no sensible fallback:**
  - a scene's title (the album, the viewer, the strip);
  - a piece's place (the room drawing);
  - a request's asker (the row).
  - Everything else falls back: no line, a default art.
- **New reference rules** in `rules/references.py`, documented in B04's `content-schemas.md`:

  | Code | Rule |
  | --- | --- |
  | V-C6 | `story_trip_info` only with `story_trip_id` |
  | V-C7 | each rider's seat is one of the story trip's `seats`, named by none of its passengers, and the riders' seats differ |
  | V-C8 | each rider comment key names a pool in the pack, with no `{amount}` or `{station}` in its lines |
  | V-C9 | `fail_reason` only when the story trip has `rules.no_fights_required` |
  | V-C10 | at most one scene without `plays` per chapter |
  | V-C11 | scene ids unique in the pack |
  | V-C12 | at most two non-narrator lines per panel |
  | V-R3 | an item's `slot` inside 358×300 (`x + w ≤ 358`, `y + h ≤ 300`, `w`, `h` ≥ 24) |
  | V-R4 | a request's `variant_id`, when given, is one of its item's variants (strengthening V-R2 if it doesn't already) |

  V-X1 (no digits) and V-X2 (no placeholders outside speech pools) apply to every new text
  automatically (`localized_texts()`).
- **B04** (`backend/apps/content/`):
  - Columns:
    - `Chapter`: `goal_art`, `goal_line_speaker`, `goal_line_ar_eg`/`_ar`, `ready_line_*`,
      `tagline_*`, `story_title_*`, `story_condition_*`, `story_fail_reason_*`;
    - `Scene`: `title_*`;
    - `Room`: `art`, `done_line_*`;
    - `Item`: `slot_x`, `slot_y`, `slot_w`, `slot_h`, `comment_*`;
    - `ItemVariant`: `comment_*`;
    - `FamilyRequest`: `character`.
  - A new `StoryRider(chapter, order, character, seat_id, comment_short_change, …)` table, with at
    most two per chapter (relational, B04's rule; M07 R6).
  - **Migration `0011_m10_story_fields`**: expand-only, every column with `db_default`.
  - `importer.py` (`chapter`, `room`, `item`, `request`), `snapshot.py` (`chapter_part`,
    `scene_part`, `room_part`, `item_part`, `request_part`) and `admin/authoring.py` (the fields,
    and a `StoryRiderInline` with `max_num=2`).
  - Tests:
    - the round trip byte for byte, with its row count updated;
    - `test_admin_authoring.py`;
    - a new `test_story_fields.py`, which imports each new invalid example.
  - `lookups.rules_document` is unchanged: the server's rules read none of these.
- **The sample pack** gains every new field. It also gains enough to exercise the screens:
  - scene titles;
  - a goal scene for chapters 2 and 4;
  - `story_trip_info` with one rider (`moallem` in `line_hay.03`'s free seat `A_l`) and one comment
    pool;
  - each item's slot and comments, and the request's asker.
  - Its golden checksums are regenerated, and the dev bundle rebuilt.
- **Required fields break older packs** (M09's note). After the deploy, staging builds and publishes
  a fresh pack (`docs/runbooks/content-publishing.md`).

**Rejected.** All fields optional: the room drawing and the album would need invented fallbacks for
data every real pack must carry.

## R17. Art and its fallbacks (FR-059)

**Decision.**

- **`ApartmentArt`** (`lib/core/art/apartment_art.dart`) is M07's `PanelArt` pattern: a const map
  from slug to `assets/illustrations/apartment/<kind>/<slug>.svg` for `rooms`, `pieces` and `goals`,
  copied by `tool/design/sync_assets.dart` and checked by `design_assets_test`.
- **Synced now** from `docs/design/illustrations/screens/`:
  - `AptGoal_01.svg` → `goals/goal_shabka.svg`;
  - `AptGoal_03.svg` → the teaser's empty room;
  - `Piece_01.svg` → `pieces/antreeh_modern.svg`;
  - `SceneViewer_01.svg` → `panels/ch4_mother_looks.svg`, added to `PanelArt`'s drawings. It is
    `SceneViewer`'s sample panel, a living room with the bride's family.
  - `AptRooms_01.svg` and `RoomDone_01.svg` are whole rooms with the pieces drawn in, so they serve
    only the design samples' fakes, not the app's composition.
- **Fallbacks**, all from tokens, no text:
  - `RoomFallback`: a wall and a floor in `scene.room` and `scene.floor`;
  - `PieceFallback`: a soft rounded block filling the slot, in `ground.lip`;
  - goals: R8's vehicle and tuktuk sprites;
  - panels: M07's `PanelFallback`.
- **The owner's art list** (owner actions, not blocking):
  - the salon without pieces;
  - the twelve style drawings;
  - chapters 1–4's undrawn panels (22 in the release draft);
  - the tuktuk and microbus goal drawings.
  - Panel animations can follow M22's path later.

## R18. Design checks and the owner's boards (FR-060)

**Decision.**

- **The nine drawn artboards** get a sample (`test/design/samples/<artboard>.dart`), a golden in both
  digit styles and a layout test against `boxes/<Artboard>.json`.
  - The samples lay a synthetic pack over the sample, M08's `editPack` way, with the artboards'
    salon: four pieces, نجفة 2,400, أنتريه 3,200 with 1,325 saved; three requests; seven chapters
    with ch4 current; four of seven scenes unlocked.
  - `AptRooms` uses the design's whole-room drawing as its room art in the fake.
- **Expected differences**, listed in each test and the PR:
  - the `CountBadge` in `primary`/white (§9.1 #8), where `AptRooms` draws it `danger`/`ink`;
  - the fuel chip «−١» with the icon (§9.1 #4), where `Piece` writes «−١ لتر»;
  - the ✕ labelled «قفل» (M08's pairing);
  - real screens under the scrims;
  - `Requests`' counted row is not built (R11);
  - `Album`'s count and cards follow the pack's scenes (Q3);
  - `AptRooms`' badge counts open + done (R11).
- **The undrawn states** are briefed for the owner in
  [contracts/design-briefs.md](./contracts/design-briefs.md), M09's way. Claude builds each from its
  brief meanwhile; a board that lands replaces the brief, and only its own checks wait.
  - The first release needs:
    - `AptGoalLine` (chapter 1, counted in trips);
    - `AptGoalVehicle` (chapter 2 ready, opening the vehicle sheet);
    - `AptRoomsAffordable` (the next target affordable, the pending chip);
    - `AptRoomsBought` (the drop-in and سلمى's bubble);
    - `AptRoomsDone` (the room finished, «شوف المشهد» on the bar, the end strip);
    - `PieceAffordable` (with the request mark and the missed-request line);
    - `RoomDonePending` (the reward on its way);
    - `ChaptersGoal` (a goal chapter current);
    - `RequestsEmpty`;
    - `HomeStoryEnd` (Home's card at the end of the story).
  - The composed states get goldens without a board: offline, 360 pt and 1.3×.

## R19. Strings

**Decision.**

- About 75 new ARB keys in `app_ar.arb`, with the artboards' strings as given (HANDOFF's string
  lists: `aptGoal.*`, `apartment.*`, `aptRooms.*`, `piece.*`, `roomDone.*`, `scene.*`, `chapters.*`,
  `album.*`, `requests.*`) under the app's naming (`aptGoalTitle`, …).
- Drafts for the undrawn states, which the owner approves (an owner action):
  - the line goal «{done} / {total} مشوار»;
  - «تقدر تشتريها»;
  - the request mark «طلب {asker}»;
  - the missed line «لو اخترت ده، طلب {asker} هيفوتك»;
  - «في الطريق», «+{n} بون في الطريق» and its offline form;
  - the condition templates;
  - the empty requests line;
  - the end of the story line;
  - the chapter teaser names;
  - the announcements:
    - «اشتريت {piece}»;
    - «{room} خلصت، المكافأة {n} بون في الطريق»;
    - «{goal} جاهزة»;
    - «اللوحة {i} من {n}».
- BONAT agreement follows §9.1 #3 through ICU plurals (`few` «بونات», `other` «بون»).

## R20. Imports and repo guards

**Decision.**

- **New pure folders** in `test/repo/domain_imports_test.dart`:
  - `lib/core/progress/domain/` gains `story.dart`, `requests.dart` and `rewards.dart`, with the
    same allowance (models, content source, wire);
  - `lib/features/apartment/domain/` and `lib/features/story/domain/` may import the models, the
    content source, the wire, the progress domain and Home's `savings_target.dart`;
  - `lib/features/trip/domain/rider_comments.dart` sits in the trip domain under its existing rules
    (it imports `trip_engine` events, as `cues.dart` does).
- **Guards that apply as they are:**
  - `no_arabic_literals_test`, `no_raw_style_values_test`, `integer_money_test`;
  - `economy_writes_test`: `player_state`'s new columns, written only by the economy store;
  - `no_ads_in_trip_test`;
  - "no text drawn in the trip's Flame canvas": the rider's bubble is a Flutter overlay, like بلية's.
- **The tunables registry is unchanged** (R15).

## R21. Testing and coverage

**Decision.** Tests first for the economy's two operations and their rules, the state mapping and the
wire (constitution XIII). Then:

- **Unit:**
  - `story.dart` (moments, unlocked, waiting, story order);
  - `requests.dart` (each state, the count);
  - `rewards.dart` (projection against base);
  - `apartmentView`, `GoalViewModel`, the rooms model;
  - `PiecePurchase`, `GoalPurchase`, `RequestClaim`;
  - `StoryService` (`recordSeen`, backfill);
  - `StoryDueWatcher` (local vs restored completion);
  - `rider_comments.dart` (triggers, over-change silent, deterministic pick, dropping);
  - `failSummary` with `fail_reason`.
- **Drift:** the v4 → v5 step (`make-migrations`' generated test), and `ledger_ops` rows kept across
  the rebuild.
- **Widget:** every view and state, the sheets' transitions, the viewer's taps and turns, the
  sequence, share (with the fake gateway), the timeline and album, the rider in the scene, the HUD
  title, the strip and the failure line.
- **Design:** nine artboards now, each owner board on export; a11y sizes at 360×640, 360×800 and
  390×844, at 1.0 and 1.3.
- **Integration, headless:** `integration_test/apartment_loop_test.dart`, offline:
  1. buy the shabka;
  2. its trip's card opens;
  3. buy the salon's pieces;
  4. `RoomDone` with the reward on its way;
  5. the scene, recorded once;
  6. the album and the timeline.
  - The first-session test still passes unchanged (spec "done when").
- **Backend-tagged** (`test/backend/`, against the dev stack): `story_progress` and `claim_request`
  accepted; a claim granting BONAT once; a state replacement restoring scenes and claims (SC-003,
  SC-006).
- **Content:** content-kit pytest (each new rule, valid and invalid examples), the `content_models`
  round trip, and backend pytest on real Postgres and Valkey (import/export, admin, migration).
- **Coverage** ≥ 80% on mobile, content_kit and backend.

## R22. Documents updated in the same PR

- `docs/architecture-mobile.md`:
  - §9: the routes `/story/album`, `/story/scene/:sceneId`, `/apartment/pre-trip/:tripId`;
  - §12: the two operations and the `story` mapping;
  - §13: the story rules and pending rewards;
  - §14: the content fields.
- `docs/architecture-backend.md` §9: the content fields and `StoryRider`.
- `content/README.md` "Scenes": the goal moment, V-C10–C12, and a new "What the apartment shows
  (M10)".
- `specs/003-b04-content-pipeline/contracts/content-schemas.md`: the new codes.
- `docs/runbooks/content-publishing.md`: the republish.
- `docs/delivery-plan.md`: Design sources (the owner's boards), the M10 progress line, HANDOFF §9.3 #2
  marked settled.
- `docs/owner-actions.md`: section 015.
- `apps/mobile/CLAUDE.md`, `tools/content_kit/CLAUDE.md`, `backend/CLAUDE.md` and the root
  `CLAUDE.md` feature list, by hand.

## R23. Handed to later features

- **M11:** nothing; scenes and the apartment play between trips, and the checkpoint is unchanged.
- **M12:** the fuel sheet behind «اطلع مشوار» on an empty tank (`/shop/fuel`).
- **M15:**
  - `item_purchased{item_id, variant, jenehat}` at `PiecePurchase`'s applied outcome;
  - `share{kind: scene}` at the scene share;
  - `scene_seen{scene_id, skipped}` in `StoryService.recordSeen`;
  - `request_claimed{request_id}`;
  - `chapter_goal_purchased{chapter_id}`.
- **B10:** nothing new; no tunable was added.
- **Phase 2:**
  - the kitchen arrives as content, and its ARB teaser name gives way to the pack's;
  - the video share of a scene;
  - the decorated vehicle of the wedding trip (chapter 7).
- **The release draft** (`content-core-r1`):
  - every new field;
  - `plays: after_trip line_gamaa.18` on `the_fatha`;
  - `story_trip_info` for المعلم, أبو العروسة and the shabka trip's two riders (`front_r` and
    `A_r`);
  - the riders' comment pools and `fail_reason`s;
  - the requests' askers (the first two أم العروسة, the third أبو العروسة, as its brief reads).
