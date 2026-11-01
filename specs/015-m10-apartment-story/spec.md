# Feature Specification: Apartment, Story Chapters, Scenes and Family Requests (M10)

**Feature Branch**: `015-m10-apartment-story`

**Created**: 2026-10-29

**Status**: Draft

**Input**: User description: "015" (spec 015 of `docs/delivery-plan.md`). In step 7, spec 015 is M10:
"Apartment ch1–4, item sheet, family requests, chapters, story viewer", which depends on M05. Sources:
`docs/ux-spec.md` «الشقة والقصة» (with «خريطة الشاشات والتنقل» and «مشاوير القصة»);
`docs/product-spec.md` «القصة والميتا: تحويش الجواز» and «مشاوير القصة»; the design `AptGoal`,
`AptGoalReady`, `AptRooms`, `RoomDone`, `Piece`, `SceneViewer`, `Album`, `Chapters` and `Requests`
(`docs/design/HANDOFF.md` §6.8, §7, §8, §9 and §11, with `docs/design/README.md`'s project overrides and
"Checking a screen against the design"); `docs/architecture-mobile.md` §9, §12 and §23 (M10's row);
`docs/architecture-backend.md` §7.4 and B03 research R6 (the server's unlock and completion rules) and
R9 (`claim_request`). From the design sources, M10 settles HANDOFF §9.3 #2 (when the Apartment tab
opens).

Handed over to M10:

- **M05**: check unlock order before calling `buy`.
- **B03**: send `story_progress` and `claim_request`; show the unlock and completion rules of research
  R6; a room's or chapter's BONAT arrives with the next sync, so the phone shows it as pending.
- **M06**: add `story_progress` and `claim_request` with their `content_version`, and map the state's
  `story` block when the server's state replaces the phone's.
- **M07**: send `story_progress` for the scenes its first session recorded; play the scenes that have
  no `plays`, adding kinds to `ScenePlaysKind` if needed; reuse `ScenePlayer`'s panel art and
  `PanelFallback`.
- **M22**: replays use the same `PanelArt` and talking turns; new panels follow the same path.
- **M08**: `apartmentOpens()` (HANDOFF §9.3 #2), `storySceneWaiting`, `StoryAfterResult`, the scene
  arrival item, and the apartment and goal views behind Home's savings card.
- **M09**: the chapter-2 goal opens the microbus sheet; the scene after the microbus purchase is an
  arrival item on Home; story screens start trips through the one start path, so they get the
  playable rule (a story trip opens once its chapter's goal is met).
- **M02 and 008.5** (008.5 research R11): a story trip's character in its seat, its comments on
  mistakes, the story title and the character's name in the failure line.
- **The first-release content draft** (`content/drafts/core-r1/BRIEF.md`, branch `content-core-r1`,
  "Waits on other features"): a chapter's goal art, character quote and tagline; a scene's title; where
  each piece sits in the room drawing; a family request's speaker; and the story trip's character,
  title and condition text. Settled by the owner on 2026-10-27: the shabka is bought first, then its
  trip is played as the celebration, then its scene plays.

Done when (step 7, with M07, M08 and M09): apartment items work offline, and the integration test from
onboarding through the first five trips still passes.

## Clarifications

### Session 2026-10-29

- Q: Should the «الشقة» tab be open from chapter 1 with the savings goal and the locked apartment
  under it, or locked in chapters 1–2? → A: Open from chapter 1: the goal view for chapters 1–3, the
  rooms from chapter 4 (the design; settles HANDOFF §9.3 #2, FR-001).
- Q: Should M10 put the story characters into the story trips (riders in their seats, the story's
  title, the condition text, comments on mistakes, the failure line), or leave them to a later
  feature? → A: In M10, all of it, from content (US8, FR-046–FR-049).
- Q: Should the album give every scene its own card, or each chapter one card that plays its scenes
  back to back? → A: One card per scene, in story order, each with its title and first panel; the
  count is the scenes unlocked out of the pack's scenes (FR-038).
- Q: When a request asks for one style and the player is about to buy the piece in another, what
  happens? → A: The requested style is marked, and choosing another style shows a short line above
  «اشتري» that the request will be missed; bought anyway, the request leaves the list (FR-018,
  FR-043).
- Q: Should the first session's scenes keep M07's look, or should سلمى's scene move to the scene viewer
  too? → A: The first session's scenes (the opening and سلمى's) keep M07's look when they play there;
  every later scene, and every replay including theirs, uses the scene viewer (FR-033).

## User Scenarios & Testing *(mandatory)*

The player drives to save money for a wedding. Each chapter of the story has one savings goal: finish
المعلم's line, buy a microbus to impress سلمى's father, buy the engagement ring (الشبكة), then furnish
the apartment room by room. The «الشقة» tab is where that dream lives: what the player is saving for,
how close they are, the rooms they furnish piece by piece in the style they choose, the comic scenes
that reward each step, and the side requests of the bride's family.

The other users are **M08**, merged (Home's savings card names the same goal and opens this tab;
Home plays a waiting scene as one of its arrival items; the result screen hands over to the scene after
a story trip), **M09**, merged (the chapter-2 goal is bought in its vehicle sheet; Lines and Home start
story trips with the same rules), **M07** and **M22**, merged (the first session's scenes, the panel
art and its animation), **M06**, merged (the operations this feature records sync through its queue),
**M11** (ads, later), **M15** (analytics), and **the tester** on internal builds.

### User Story 1 - Save toward the chapter's goal (Priority: P1)

The player taps «الشقة» in the bottom nav. In the first three chapters the tab shows «تحويش الجواز»: a
blue chapter bar («الفصل ٣ · الشبكة», «كل الفصول»), then a big card with the goal's art, its name, how
much they have saved against its price, a gold progress bar, and a line from a character («الشبكة أول
حاجة الناس بتسأل عليها يا ابني»، أم العروسة). Under it, the empty apartment waits, locked: «شقة العُمر،
فاضية ومستنياك. العفش بيبدأ من الفصل ٤: الصالة.» In chapter 1 the goal is finishing خط الحي, so the
progress counts trips, not pounds. When the savings cover the goal, the card says «جاهزة!», the bar is
full, the character's line changes, and a big button appears: «اشتري الشبكة» with the price. In
chapter 2 that button opens the microbus's sheet (M09). Buying the shabka finishes the chapter and
sends the player straight to its story trip, «مشوار الشبكة»; the chapter's scene follows that trip.

**Why this priority**: The savings goal is what gives every fare its meaning (product spec «القصة
والميتا»). Chapters 1–3 are the first days of play for every player, and the shabka is the first thing
bought for the story itself.

**Independent Test**: With the sample pack and a scripted player state, open the tab with the network
off: once in chapter 1 (8 of 19 regular trips done), once in chapter 3 below the shabka's price, and
once in chapter 3 above it. The card's goal, amounts, bar and quote match the state; only the last
shows «جاهزة!» and the button. Tap the button: the shabka is bought once, and the shabka trip's
pre-trip card opens.

**Acceptance Scenarios**:

1. **Given** a new player after the tutorial (chapter 1), **When** they open «الشقة», **Then** the goal
   view shows «الفصل ١» and its name, the goal «خلّص خط الحي» with the line's finished regular trips
   against its total, the bar at that fraction, the chapter's character line, and the locked
   apartment teaser; there is no button.
2. **Given** a player in chapter 2 with less than the microbus's price, **When** they open the tab,
   **Then** the goal is the microbus with «{saved} / {price} ج» and the bar at their share of the
   price, and there is no button.
3. **Given** a player in chapter 2 whose savings cover the microbus, **When** they open the tab,
   **Then** the card shows «جاهزة!», a full bar and the ready line, and its button opens the microbus's
   sheet (M09's `BuyVehicle`), which buys it.
4. **Given** a player in chapter 3 whose savings cover the shabka, **When** they tap «اشتري الشبكة»,
   **Then** the price is spent exactly once, the chapter is done, and the shabka trip starts through
   the one start path (its pre-trip card, or the fuel sheet with an empty tank); the tab now shows the
   apartment's rooms.
5. **Given** the player closed the shabka trip's card without playing, **When** they return to Home,
   **Then** Home's next trip is the shabka trip (M09), and the chapter's scene has not played.
6. **Given** any goal view, **When** the player taps the chapter bar, **Then** the chapters timeline
   opens (US6).
7. **Given** the goal view is open, **When** a sync changes the balance or the progress, **Then** the
   card shows the new state without being reopened, and the bar moves to it.
8. **Given** no network, **Then** every state above shows and the shabka purchase works, and syncs
   later.

---

### User Story 2 - Furnish the room piece by piece (Priority: P1)

From chapter 4 the tab shows «شقة العُمر». The chapter bar reads «الفصل ٤ · الصالة» with the chapter's
tagline («أهل العروسة جايين الخميس») and «جهّزت ٢ من ٤» with a small bar. Under it, tabs for the
three rooms of the story (the ones not reached yet carry a lock) and a «الطلبات» button. The room is
drawn with the pieces the player bought, each in the style they chose; every missing piece has a dashed
outline with a chip «النجفة · ٢٬٤٠٠». Below, a grid of the room's pieces: owned ones say «اتركّبت», the
next one to save for shows «ناقصك ١٬٨٧٥» and a bar, and the others show their price. A dark strip says
which scene finishing the room opens. Tapping a missing piece opens its sheet: the piece large, three
styles to choose from at the same price, سلمى's comment on the chosen style, the price and «معاك». If
the player can't afford it yet, the sheet says «ناقصك ...» and offers «اطلع مشوار»; if they can, it
offers «اشتري». Buying closes the sheet, the piece drops into its place, and سلمى says something about
it.

**Why this priority**: Furnishing the apartment is the long-term pull of the game from chapter 4 on,
and the only place the player spends savings on the story's rooms. Choosing a style makes the apartment
theirs (product spec «الشقة»).

**Independent Test**: With a scripted chapter-4 state (two of the salon's four pieces owned, in chosen
styles, and a balance), open the tab offline. The drawing shows the two pieces in their styles and two
dashed places with chips; the grid shows two «اتركّبت», the next piece with its shortfall and bar, and
the other's price. Open the next piece, switch styles, raise the balance through the test economy, and
buy: the piece appears in its place in the chosen style, the count reads «جهّزت ٣ من ٤», and the price
is spent once.

**Acceptance Scenarios**:

1. **Given** the start of chapter 4 with no piece owned, **When** the player opens the tab, **Then**
   every piece of the room has a dashed place with its chip, the grid shows every piece with its price
   except the first by order, which shows «ناقصك {amount}» and its bar (unless affordable), and the bar
   reads «جهّزت ٠ من {total}».
2. **Given** a piece's sheet, **When** the player taps another style, **Then** the preview, the style
   chip and سلمى's line change, and the price doesn't.
3. **Given** a piece the player can't afford, **Then** the sheet shows «ناقصك {amount} ج» and «اطلع
   مشوار» with the fuel chip; **When** they tap it, **Then** the sheet closes and the next trip starts
   through the one start path (the pre-trip card, or the fuel sheet with an empty tank).
4. **Given** a piece the player can afford, **Then** the sheet shows «اشتري» with the price chip and no
   shortfall; **When** they tap it, **Then** the price is spent once with the chosen style, the sheet
   closes, the piece drops into its place in that style, its chip disappears, its card reads
   «اتركّبت», the count rises, and سلمى comments in a bubble over the room.
5. **Given** a family request asks for one style of a piece, **When** the player opens that piece,
   **Then** that style carries a mark that the family asked for it; **When** they select another
   style, **Then** a short line above the button says the request will be missed; **When** they buy
   it anyway, **Then** the request leaves the requests list.
6. **Given** an owned piece, **When** the player taps its card or its place, **Then** nothing happens.
7. **Given** a locked room tab, **When** the player taps it, **Then** nothing happens, and a screen
   reader reads it as locked.
8. **Given** a room of five or six pieces, or a larger text size, **Then** the grid grows by rows and
   the screen scrolls; nothing is cut off.
9. **Given** no network, **Then** browsing and buying work, and the purchases sync later.
10. **Given** a purchase, **Then** Home's savings card names the next piece the next time it shows.

---

### User Story 3 - Finish a room and a chapter (Priority: P2)

When the player buys the room's last piece, a short celebration opens over the apartment: the finished
room among confetti, «الفصل ٤ · ٤ من ٤ قطع», «الصالة خلصت!», the BONAT reward, سلمى's line («تحفة يا
أسطى! ماما هتفرح أوي يوم الخميس»), and two buttons: «شوف المشهد» and «بعدين». The reward is the
server's to give, so the dialog shows it as on its way, and the BONAT balance rises when the next sync
brings it.

**Why this priority**: Finishing a room is the biggest payoff of the apartment loop: a reward and a
story scene (product spec «الشقة»: «إكمال الغرفة يفتح المشهد ويدّي مكافأة بونات»). It depends on US2.

**Independent Test**: With a scripted state one piece short of a complete salon, buy the last piece
with the network off. The dialog opens once, with the room's reward plus the chapter's (the salon
completes chapter 4), marked as on its way, and the BONAT balance doesn't change. Turn the network on
and sync against a test server: the balance rises by exactly that amount, once.

**Acceptance Scenarios**:

1. **Given** the room's last piece is bought, **Then** the dialog opens once for that room, with the
   BONAT the completion earns: the room's reward, plus its chapter's when the room completes the
   chapter.
2. **Given** the dialog, **Then** the BONAT balance doesn't change until a sync brings the server's
   grant; once it does, the balance rises by that amount exactly once, and the reward is no longer
   shown as on its way.
3. **Given** the dialog, **When** the player taps «شوف المشهد», **Then** the chapter's scene plays in
   the scene viewer (US4), and its end returns to the apartment.
4. **Given** the dialog, **When** the player taps «بعدين», the scrim or back, **Then** it closes, the
   scene waits: the chapter bar offers «شوف المشهد», Home's savings card shows «مشهد جديد مستنيك», and
   the album lists it.
5. **Given** the last chapter of the pack is complete, **When** the dialog closes, **Then** the
   apartment shows the finished room and a note that the story continues in a later update, and the
   chapters timeline shows every chapter of the pack done.
6. **Given** the server later refuses the purchase that completed the room (M06's rollback), **Then**
   the piece returns to missing, the promised reward is withdrawn, and the player sees M06's one neutral
   message.

---

### User Story 4 - Watch the story's scenes when they happen (Priority: P2)

Each scene plays by itself at its moment in the story: right after a story trip's first finish, when a
chapter's goal is met (the microbus bought, a room finished), or, for the first session's scenes, where
M07 placed them. The scene viewer is a dark full screen: the chapter and the scene's title at the top,
one comic panel at a time with its speech bubbles, dots for the panels, «تخطّى» at the top, and on the
last panel «شارك» and «كمّل». A tap anywhere moves to the next panel. «شارك» shares the panel as an
image. Panels move when they have an animation (M22), and otherwise show their drawing.

**Why this priority**: The scenes are the story's reward and its humour, the thing that makes saving
feel like a story (product spec «المشاهد»). The chapters' moments depend on US1–US3.

**Independent Test**: With the sample pack, finish المعلم's story trip for the first time: on leaving
the result, its scene plays; play it again and finish: no scene. Buy the microbus in Lines, then return
to Home: the scene plays as Home's arrival item. In the viewer, tap through every panel, share the last
one, skip another scene halfway: each is recorded as seen once, and one `story_progress` operation per
scene is queued.

**Acceptance Scenarios**:

1. **Given** a story trip whose chapter has a scene timed after it, **When** the player finishes it
   for the first time and leaves the result by any button, **Then** the scene plays first, and its end
   continues to where the button leads.
2. **Given** that trip was finished before, or it failed or was abandoned, **Then** no scene plays.
3. **Given** a chapter goal met outside the apartment (the microbus bought in Lines), **When** the
   player next arrives at Home, **Then** the chapter's scene plays as Home's first arrival item (M08's
   order), and Home's other items wait.
4. **Given** the viewer, **When** the player taps the panel, **Then** the next panel slides in from the
   reading side, its bubbles pop one after the other, and the dots follow; **Given** the last panel,
   **Then** «شارك» and «كمّل» show; «كمّل», «تخطّى» and back end the scene.
5. **Given** any panel, **When** the player taps «شارك», **Then** an image of that panel with its
   bubbles opens the share sheet, with or without network.
6. **Given** a scene is played to the end or skipped, **Then** it is seen, recorded once on the phone
   and sent to the server once.
7. **Given** a scene is unlocked and not yet seen, **Then** Home's savings card shows «مشهد جديد
   مستنيك», and tapping the card plays it.
8. **Given** a panel without an animation, **Then** its drawing shows; without a drawing, M07's
   fallback; under reduced motion, the still drawing, with fades instead of slides and pops.
9. **Given** a line spoken by الأسطى, **Then** its bubble is labelled with the player's chosen name.

---

### User Story 5 - My story follows me (Priority: P2)

A player who reinstalls the game, or links their account on a new phone, finds the same story: the
same chapter and goal, the same pieces in the same styles, the scenes they had seen (in the album, not
replayed by themselves), and the requests they had claimed.

**Why this priority**: Progress is the player's; losing the apartment would lose the game's point. M06
restores the wallet and the trips; the story's part is this feature's.

**Independent Test**: Against a test server, play to chapter 4 with two pieces bought, three scenes
seen and one request claimed, sync, then restore the server's state on a fresh install. The tab,
timeline, album and requests show the same state, and no scene plays by itself.

**Acceptance Scenarios**:

1. **Given** the server's state replaces the phone's (M06), **Then** the scenes it records as seen are
   seen, the requests and rooms it records as granted are granted, and the apartment shows the owned
   pieces in their styles.
2. **Given** a restored state where a scene is unlocked but not seen, **Then** it waits (Home's card,
   the album), and none plays by itself.
3. **Given** scenes seen in M07's first session before this feature was installed, **Then** each is
   sent to the server once.

---

### User Story 6 - Look back over the story (Priority: P3)

From the chapter bar the player opens «حكاية الجواز», a vertical timeline of the story's seven
chapters. Finished chapters show a picture of their scene and «شوف المشهد»; the current chapter is
highlighted with its goal and progress; the chapters to come show only their names, locked. «ألبوم
المشاهد» at the top opens the album: one card for each scene of the story, those already unlocked with
their picture and «اتفرج تاني», the others locked.

**Why this priority**: Rewatching and sharing scenes is a pleasure, not a need; the story works
without it. It depends on US4's viewer.

**Independent Test**: With a scripted state in chapter 4 (three scenes seen, one waiting), open the
timeline: chapters 1–3 done, 4 current with «{owned} من {total} قطع», the piece names and the scene's
name, 5–7 locked. Open the album: the count matches the unlocked scenes, and each card opens its scene
from the first panel, granting nothing.

**Acceptance Scenarios**:

1. **Given** the timeline, **Then** every chapter of the story appears in order, each done, current or
   locked from the player's progress, and the rail is filled down to the current chapter.
2. **Given** a done chapter, **When** the player taps «شوف المشهد», **Then** its unlocked scenes play
   in story order.
3. **Given** the current chapter, **Then** its row shows its goal: for a room, «{owned} من {total}
   قطع», the room's pieces and the scene it opens; for any other goal, the goal and its progress.
4. **Given** the album, **Then** it shows one card per scene of the pack in story order and «{unlocked}
   من {total}»; an unlocked card opens its scene from panel 1; a locked card does nothing.
5. **Given** a replay from the timeline or the album, **Then** nothing is granted, and no new seen
   record is sent.
6. **Given** a chapter the installed pack doesn't contain yet, **Then** the timeline shows it locked
   with its name.

---

### User Story 7 - Answer the bride's family's requests (Priority: P3)

In the rooms view, «الطلبات» shows how many requests wait. It opens a sheet: «طلبات أهل العروسة،
اختيارية، ومش بتوقف القصة. مكافأتها بونات.» Each row has the face of the one who asks (أم العروسة or
أبو العروسة), their request («النجفة لازم تبقى كريستال، دي أول حاجة الضيوف بتبص لها»), what fulfils it,
and the BONAT reward. A request the player has fulfilled shows «خلص · +٦ بونات» and «خد»; tapping it
takes the reward, which arrives with the next sync.

**Why this priority**: Requests are optional side goals (product spec «الشقة»); the story never waits
for them. They add a reason to choose a style and a small BONAT income.

**Independent Test**: With a scripted chapter-4 state where the chandelier is owned in «كريستال» and
the other two requested pieces aren't owned, open the requests: the chandelier's request is done with
«خد», the others open with their conditions. Tap «خد» offline: the row leaves, the count drops, a
`claim_request` is queued once, and the balance doesn't change until a sync brings the grant.

**Acceptance Scenarios**:

1. **Given** the rooms view, **Then** «الطلبات» carries the count of requests not yet claimed in rooms
   the player has reached, and no count when there are none.
2. **Given** the sheet, **Then** each unclaimed request shows its character's face (happy when done,
   neutral when open), name, words, condition and reward.
3. **Given** a request whose piece the player owns (in the style it names, when it names one),
   **Then** it is done and offers «خد»; **When** they tap it, **Then** the claim is recorded once, the
   row collapses, the count drops, and the reward shows as on its way until the server grants it.
4. **Given** a request whose piece the player owns in another style, **Then** it can no longer be
   fulfilled and leaves the list and the count.
5. **Given** no request to show, **Then** the sheet shows the empty-list state.
6. **Given** the server refuses a claim, **Then** the request returns to the list, with M06's neutral
   handling.

---

### User Story 8 - Ride with the story's characters (Priority: P3)

In a story trip a character rides with the player: المعلم in his tuktuk, أبو العروسة in the front seat
of the player's first microbus, أم العروسة and سلمى on the way to the jeweler. The trip's top bar shows
«مشوار قصة» and the story's title («أبو العروسة راكب»), a strip at the top of the scene states the
trip's condition («أبو العروسة راكب: أي خناقة والمشوار يتعاد»), and the character comments on the
player's mistakes («الأستاذ اللي ورا مستعجل.. شوف باقيه.»). When the condition is broken, the failure
says who saw it («أبو العروسة شاف خناقة»).

**Why this priority**: The story trips are the story's set pieces (product spec «مشاوير القصة»). They
already play by their rules (M01, M02, M09); this adds the characters who make them a scene. The
first-release content assigns it here (008.5 research R11), and the owner kept all of it in M10
(Clarifications).

**Independent Test**: With the sample pack's story trip carrying a rider, start it: the top bar shows
the story chip and title, the condition strip shows the content's text, the rider sits in their seat
with no tag and no tap target, and a scripted short change makes the rider comment within a second
(a scripted over-change makes no comment).
Start a fight: the trip fails with the rider's failure line and no revive.

**Acceptance Scenarios**:

1. **Given** a story trip with riders, **When** it starts, **Then** each rider sits in their seat as
   their character, not tappable, with no tag and no fare.
2. **Given** a story trip, **Then** the top bar shows «مشوار قصة» and the trip's story title, and the
   condition strip shows the trip's condition text for the whole trip.
3. **Given** the player makes a mistake a rider comments on, **Then** one rider says one line from
   their comments in a character bubble, held long enough to read; comments never stack.
4. **Given** a story trip that forbids fights, **When** a fight starts, **Then** the failure names the
   rider who saw it, with no revive (M02's rule).
5. **Given** a story trip whose content names no rider, title or condition text, **Then** it plays as
   M02 and 008.5 built it.
6. **Given** any story trip, **Then** its rules, its result and its replay are unchanged: the engines
   and the parity fixtures are untouched.

---

### Edge Cases

- **A sync changes the balance while a sheet is open**: the sheet follows it; a piece that becomes
  unaffordable switches back to «اطلع مشوار» before the tap can spend.
- **Double taps, retries, a tap during a purchase or a claim**: the price is spent, and the claim
  recorded, exactly once; the button is disabled until the outcome is known.
- **Several pieces bought offline** that finish the room: the dialog opens once, when the last one is
  bought.
- **A room finished on another phone** (a restore): no dialog on this phone; its scene waits if not
  seen.
- **A chapter goal met by a restore or a sync**: its scene waits; nothing plays by itself.
- **Several scenes due at once** (a goal met and a story trip finished): one plays per arrival at Home
  (M08's order), the rest wait.
- **A story trip failed or abandoned**: no scene; the trip waits as Home's next trip (M09).
- **The app is killed after the shabka purchase and before its trip**: Home's next trip is the shabka
  trip (M09); its scene plays only after the trip.
- **A piece owned in a style the active pack no longer has**: it is drawn in the piece's first style.
  Ids the active pack doesn't have are skipped, as everywhere since M04.
- **A request names a piece or style the pack doesn't have**: refused by content validation, never
  shown.
- **A piece without styles**: the style picker and the preview chip are hidden, and سلمى's line is the
  piece's own.
- **No art yet** for a piece, a room, a goal or a panel: its fallback shows, and the screen works.
- **Large balances and prices**: amounts never wrap; labels shorten first.
- **The player's name isn't set**: الأسطى's bubbles say «الأسطى».
- **Text at 1.3×, a 360 pt wide screen**: the screens scroll where needed; every minimum still holds.
- **Every chapter of the pack done** (after chapter 4 in the first release): the apartment, Home's
  savings card and the timeline show the end of the available story, and nothing invites a purchase
  that doesn't exist.

## Requirements *(mandatory)*

### Functional Requirements

#### The Apartment tab

- **FR-001**: The «الشقة» tab MUST be open from the first chapter (HANDOFF §9.3 #2, settled for the
  design in Clarifications). While the current chapter's goal isn't a room, it MUST show the goal view (`AptGoal`,
  `AptGoalReady`); from the chapter in which the apartment opens, the rooms view (`AptRooms`).
- **FR-002**: The chapter in which the apartment opens MUST stay the one place M08 reads
  (`apartmentOpens`, M08 FR-019): the first chapter, by order, whose goal is a room (chapter 4 in the
  first release).
- **FR-003**: The current chapter MUST be the one M08 and the server read (B03 research R6): the first
  chapter, by order, whose goal isn't met.
- **FR-004**: The tab and every screen of this feature MUST show the active pack's content and the
  phone's balances and progress with no network and no loading state, and MUST follow every change a
  sync brings without being reopened.

#### The goal view (chapters before the apartment)

- **FR-005**: The goal view MUST show, as `AptGoal` draws it: the title «تحويش الجواز» and the JENEHAT
  pill (not tappable, HANDOFF §9.1 #7); the chapter bar «الفصل {n} · {chapter}» with «كل الفصول»,
  which opens the timeline; the goal card with the goal's art, its name, the amount, the gold bar and
  the chapter's character line (avatar, words and speaker); and the locked apartment teaser.
- **FR-006**: The goal's progress MUST be M08's savings target (M08 research R4): a line goal counts
  the line's finished regular trips against its regular trips (shown in trips); a vehicle goal and a
  chapter purchase count JENEHAT against the catalog price. Progress MUST cap at 100%, and the bar
  MUST animate from the value the player last saw.
- **FR-007**: When a goal with a price is affordable and not owned, the view MUST show `AptGoalReady`:
  «جاهزة!», a full bar, the chapter's ready line, and a primary button. For a chapter purchase, the
  button MUST read «اشتري {goal}» with the price chip and buy the chapter's goal; for a vehicle goal, it
  MUST open that vehicle's sheet (M09), which buys it. A line goal is never "ready".
- **FR-008**: After the player buys a chapter's goal in the goal view (a purchase goal, such as the
  shabka), the chapter MUST be done, and when the chapter has a story trip the player hasn't finished,
  that trip MUST start at once through the one start path (M08: the pre-trip card or the trip, or the
  fuel sheet with an empty tank). Closing it MUST leave the trip as Home's next trip (M09). A vehicle
  goal is bought in M09's vehicle sheet (FR-007), which starts no trip. When a chapter's scenes play
  comes from content (FR-028): the shabka's scene is timed after its story trip's first finish (owner
  decision, 2026-10-27), and a goal scene plays when its goal is met (FR-030).

#### The rooms view

- **FR-009**: The rooms view MUST show, as `AptRooms` draws it: the title «شقة العُمر» and the JENEHAT
  pill; the chapter bar with the chapter's number, room name and tagline, «جهّزت {owned} من {total}»
  and its bar, opening the timeline; tabs for the story's three rooms; «الطلبات» with its count
  (FR-040); the room's drawing; the grid of its pieces; and the strip «خلّص {room} وافتح مشهد
  «{scene}»».
- **FR-010**: The view MUST open on the current chapter's room. A room whose chapter has started MUST
  be selectable; any other room's tab MUST be locked (a lock, inert, read as locked), including rooms
  the installed pack doesn't contain yet.
- **FR-011**: The drawing MUST show each owned piece in the style the player chose, and each missing
  piece as a dashed outline in its place with a chip «{piece} · {price}». A piece's place comes from
  content, inside the room's drawing.
- **FR-012**: The grid MUST list the room's pieces by order. An owned piece reads «اتركّبت» and is
  inert. The next target, the first piece by order that the player doesn't own (the same piece Home's
  savings card names), MUST show «ناقصك {amount}» and a bar while it is unaffordable, and that it can
  be bought once it is. Every other missing piece shows its price.
- **FR-013**: A missing piece's chip or card MUST open its sheet.
- **FR-014**: After a purchase, the piece MUST drop into its place in its style, its chip disappear,
  its card read «اتركّبت», the count rise, and سلمى comment in a bubble over the room with the piece's
  line. Under reduced motion, fades only.
- **FR-015**: Switching rooms MUST crossfade the drawing in at most 150 ms. The view MUST scroll when
  its content is taller than the screen.
- **FR-016**: While a finished room's scene waits (FR-028), the chapter bar MUST offer «شوف المشهد»
  (HANDOFF `RoomDone`), which plays it; the rest of the bar still opens the timeline.

#### The piece sheet

- **FR-017**: The piece sheet MUST show, as `Piece` draws it: the room's name over the piece's name, a
  close button; the preview in the selected style with its name; the style picker (one of up to three
  styles, the same price); سلمى's line for the selected style; the price «السعر (نفسه لكل الأشكال)»
  and «معاك» with the balance. A piece with one style MUST hide the picker and the preview chip.
- **FR-018**: The sheet MUST open on the style the player last picked for that piece, else the
  piece's first style. A style that an unclaimed family request asks for MUST carry a mark saying the
  family asked for it. While another style is selected, the sheet MUST show a short line above «اشتري»
  (or «اطلع مشوار») saying that buying this style misses the request.
- **FR-019**: While the piece is unaffordable, the sheet MUST show «ناقصك {amount} ج» and «اطلع مشوار»
  with the fuel chip (HANDOFF §9.1 #4), which closes the sheet and starts the next trip through the one
  start path. While it is affordable, it MUST show «اشتري» with the price chip instead (HANDOFF §9.2).
- **FR-020**: «اشتري» MUST check the rules first (FR-050), then spend the price once with the chosen
  style. The button MUST stay disabled until the outcome is known, and a refusal MUST say why and spend
  nothing.
- **FR-021**: Close, a swipe down and the system back MUST return to the apartment.

#### Finishing a room and a chapter

- **FR-022**: Buying a room's last piece MUST open the `RoomDone` dialog over the apartment, once per
  room: the finished room's drawing, «الفصل {n} · {done} من {total} قطع», «{room} خلصت!», the reward,
  سلمى's line for the room, «شوف المشهد» and «بعدين».
- **FR-023**: The reward MUST be the BONAT the completion earns: the room's, plus its chapter's when the
  room completes the chapter.
- **FR-024**: The phone MUST NOT add a room's, a chapter's or a request's BONAT to the balance itself
  (constitution IV). It MUST show the reward as on its way until a sync brings the server's grant, then
  as received; the balance rises only with the server's wallet.
- **FR-025**: «شوف المشهد» MUST play the chapter's scene timed at the goal. «بعدين», the scrim and back
  MUST close the dialog and leave the scene waiting.
- **FR-026**: Chapters completed by a line, a vehicle or a purchase MUST NOT open a dialog of their
  own; their reward arrives with the sync, and their scene marks the moment.
- **FR-027**: When every chapter of the installed pack is done, the apartment MUST show the last room,
  finished, with a note that the story continues in a later update; the timeline MUST show no current
  chapter; and Home's savings card MUST show the same end state instead of a goal.

#### Scenes

- **FR-028**: Every scene MUST have a moment, from content: the opening (M07), after a given trip's
  first finish, or when its chapter's goal is met; a scene whose content states no moment plays when
  its chapter's goal is met. A scene is unlocked when its moment comes. An unlocked scene not yet seen
  **waits**.
- **FR-029**: A scene timed after a story trip MUST play when the player leaves that trip's result
  after its first finish, before the destination they chose (M08 FR-046). Scenes timed after other
  trips keep M07's way (Home's arrival item).
- **FR-030**: A scene unlocked by a goal met outside the apartment's own flows (a vehicle bought in
  Lines or from the goal view) MUST play at the next arrival at Home, as the first item of M08's order
  (M08 FR-022a), or before the next trip if one starts first (M07's rule for a due scene). A scene unlocked by a finished room is offered by its dialog (FR-025). A scene the
  player put off («بعدين») or skipped MUST NOT be forced again.
- **FR-031**: While any scene waits, Home's savings card MUST show «مشهد جديد مستنيك» (M08 FR-020), and
  tapping it MUST play the oldest waiting scene.
- **FR-032**: A scene played to its end or skipped MUST be seen: recorded once on the phone and sent
  to the server once (FR-052).
- **FR-033**: The scenes that play during M07's first session (the opening and سلمى's scene) MUST keep
  M07's presentation there (`Intro`, with «يلا»), and its step after سلمى's scene (the first
  notification ask) MUST stay as it is. Every other scene play, and every replay (theirs included), MUST
  use the scene viewer.
- **FR-034**: The scene viewer MUST show, as `SceneViewer` draws it: «الفصل {n} · المشهد» over the
  scene's title, «تخطّى», one panel at a time with its bubbles, the panel dots, and on the last panel
  «شارك» and «كمّل». A tap on the panel MUST advance; «تخطّى», «كمّل» and the system back MUST end the
  scene and return to where it was opened from.
- **FR-035**: A panel MUST be drawn by M22's path: its animation when one exists (with the speaker
  talking in turn), else its drawing, else M07's fallback; under reduced motion, its still drawing.
- **FR-036**: «شارك» MUST render the current panel with its bubbles as an image and open the share
  sheet, with or without network.

#### The timeline and the album

- **FR-037**: The timeline (`Chapters`) MUST show the story's seven chapters in order, each done,
  current or locked from the player's progress, with the rail filled to the current one. A done
  chapter MUST show its scene's picture and «شوف المشهد», which plays its unlocked scenes in story
  order. The current chapter MUST show its goal: for a room, «{owned} من {total} قطع», the room's
  pieces and its scene's name; for any other goal, the goal and its progress. A locked chapter MUST
  show only its number and name.
- **FR-038**: «ألبوم المشاهد» MUST open the album (`Album`): one card per scene of the pack, in story
  order (by chapter, then by the order the scenes' moments come), with «{unlocked} من {total}», where
  the total is the pack's scenes. An unlocked card MUST show the scene's first panel, chapter and
  title, and «اتفرج تاني», which plays it from panel 1; a locked card MUST look locked, say «بيتفتح لما
  الفصل يخلص», and do nothing.
- **FR-039**: A replay MUST grant nothing and send no new seen record.

#### Family requests

- **FR-040**: «الطلبات» MUST carry the count of unclaimed requests in rooms the player has reached
  (excluding those that can't be met, FR-043), as a `CountBadge` (HANDOFF §9.1 #8), hidden at zero. It
  MUST open the requests sheet.
- **FR-041**: The sheet MUST show, as `Requests` draws it: the title, the subtitle and close; then one
  row per unclaimed request: the face of the character who asks (happy when done, neutral when open),
  their name and words, then, when done, «خلص · +{n} بونات» and «خد», else the condition and «+{n}
  بون».
- **FR-042**: A request is done when the player owns its piece, in its style when it names one (the
  server's rule, B03 research R9). No other kind of condition exists in this feature.
- **FR-043**: A request whose piece the player owns in another style can no longer be met, and MUST
  leave the list and the count.
- **FR-044**: «خد» MUST record the claim once, collapse the row and lower the count; the reward MUST
  show as on its way until the server grants it (FR-024). A claim MUST be possible offline and sync
  later; a refused claim MUST return the request to the list.
- **FR-045**: With no request to show, the sheet MUST show the empty-list state of `States`. Requests
  MUST never block a purchase, a chapter or a scene.

#### Story trips

- **FR-046**: A story trip whose content names riders MUST seat each rider in their seat as their
  character, with no tag, no fare and no tap target. The seats are those its trip definition keeps
  empty.
- **FR-047**: A story trip's top bar MUST show «مشوار قصة» over the trip's story title from content,
  and its condition strip MUST show the trip's condition text from content, for the whole trip.
- **FR-048**: When the player makes a mistake a rider comments on (at least: short change, a false
  accusation, a fight, a passenger carried past their stop, and a passenger who left impatient), one
  rider MUST say one line from their comments in a character bubble, shown long enough to read; a new
  comment MUST NOT cover one still showing, and comments MUST be spaced by a tunable with a bundled
  default (constitution VIII). Change beyond what was owed MUST stay silent, as it does for everyone
  during a trip (constitution XI).
- **FR-049**: A failure under the trip's rule MUST name the rider who saw it in the failure line, from
  content, with no revive. A story trip whose content names no rider, title or condition text MUST play
  as M02 and 008.5 built it. No engine rule, trip definition or parity fixture changes.

#### Rules, records and sync

- **FR-050**: Before any purchase, the phone MUST apply the server's rules as M08 ported them (B03
  research R6): a piece can be bought only when its room's chapter is unlocked and it isn't owned; a
  chapter's goal only when the chapter is unlocked and not owned. Story trips keep M09's stricter rule
  (playable once their chapter's goal is met). The phone MUST never treat as open what the server
  refuses.
- **FR-051**: Unlocks and completions MUST be derived from the player's progress, ownership and the
  active pack, never stored separately, so the phone and the server can't drift.
- **FR-052**: A seen scene MUST be sent as a `story_progress` operation, once per scene, with its
  content version; the scenes M07's first session recorded before this feature MUST be sent once too.
- **FR-053**: A claim MUST be sent as a `claim_request` operation with its content version.
- **FR-054**: When the server's state replaces the phone's (M06), the seen scenes and the granted
  rooms, chapters and requests MUST come from it, and the phone MUST show the same apartment, timeline,
  album and requests. Unlocked scenes not seen MUST wait; none plays by itself.
- **FR-055**: A refusal of any operation this feature records MUST roll back through M06, with its one
  neutral message, never an alarming one.

#### Content

- **FR-056**: The content schemas MUST gain what these screens show, and the sample pack MUST carry
  it: a chapter's goal art, its character line and speaker, its ready line, and its tagline; a scene's
  title; a room's drawing and سلمى's line when it's finished; a piece's place in its room's drawing and
  سلمى's line for each style (and for a piece without styles); the character who asks a family request;
  and, for a story trip, its title, its condition text, its riders (character and seat), their comments
  and their failure line.
- **FR-057**: Content validation MUST refuse: a rider in a seat the trip doesn't keep empty; a piece's
  place outside its room's drawing; a request naming a piece or style the pack doesn't have; a scene
  moment that names a trip outside the pack.
- **FR-058**: Every player-facing text of the story MUST come from the pack; the app holds only its
  interface strings, including the names of chapters and rooms the installed pack doesn't contain yet,
  shown locked.

#### Art and the design

- **FR-059**: Every screen MUST work before its art exists: a missing piece, room, goal or panel
  drawing MUST fall back (M07's panel fallback for panels), and the art arrives as an owner action.
- **FR-060**: The screens MUST be built from M21's tokens and components. Each of the nine artboards
  MUST have a sample, a golden in both digit styles beside `docs/design/png/<Artboard>.png`, and a
  layout test against `docs/design/boxes/<Artboard>.json` (±2 pt), in RTL. The undrawn states (FR-006's
  chapter-1 goal counted in trips, FR-007's chapter-2 button, FR-008's hand-over to the shabka trip,
  FR-012's affordable target, FR-014's drop-in, FR-018's request mark and missed-request line,
  FR-024's pending reward, FR-027's end state, FR-037's goal chapter, FR-045's empty list) MUST be
  designed from the nearest drawn artboard and approved by the owner.
- **FR-061**: Every tappable MUST be at least 44×44 pt and every text at least 12 pt, at 390 and 360 pt
  wide, with text up to 1.3×. Labels MUST follow HANDOFF's, and the screens MUST announce a purchase's
  result, a finished room, a goal that became ready and each panel change.

### Key Entities *(include if feature involves data)*

- **Chapter** (content): order, title, goal (a line, a vehicle, a purchase or a room), story trip,
  completion BONAT, scenes; gains its goal art, character line and speaker, ready line and tagline.
- **Scene** (content): its panels (art and lines) and its moment (the opening, after a trip, or when
  its chapter's goal is met); gains a title.
- **Room** (content): name, order, chapter, completion BONAT; gains its drawing and سلمى's line when
  finished.
- **Piece** (content, `item`): its room, name, order, styles (each with a name and art), price (the
  catalog); gains its place in the room's drawing and سلمى's lines.
- **Family request** (content): its piece and optional style, words and BONAT reward; gains the
  character who asks.
- **Story trip presentation** (content): a story trip's title, condition text, riders (character and
  seat), their comments and their failure line.
- **Ownership** (the economy's): the pieces with their chosen style, the vehicles and the chapter goals
  the player owns.
- **Seen scenes** (on the phone, synced): each scene the player has seen, and whether the server has
  it.
- **Grants** (the server's, mirrored): the rooms, chapters and requests whose BONAT the server has
  granted.
- **Claims** (on the phone, synced): the requests the player has claimed.
- **Derived**: the current chapter; the apartment's chapter; the next target piece; each scene's state
  (locked, waiting, seen); each request's state (open, done, claimed, missed); each reward's state (on
  its way, received).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With enough savings, a player buys a piece in at most three taps from any tab («الشقة»,
  the piece, «اشتري»), and the shabka in two («الشقة», «اشتري الشبكة»), with the network off.
- **SC-002**: In 100% of tested double taps, retries and taps during a purchase or a claim, the price is
  spent, and the claim recorded, exactly once.
- **SC-003**: In 0 cases does the BONAT balance include a room's, chapter's or request's reward before
  the server grants it, and in 100% of synced completions and claims it includes it exactly once after.
- **SC-004**: Across the server's rule cases, the phone treats as open no piece, chapter goal or story
  trip that the server refuses (0 cases), and in an end-to-end sync against a real server no purchase,
  scene record or claim made through these screens is refused as not unlocked.
- **SC-005**: Every scene of the first-release pack plays at its moment once and only once in a scripted
  run from the first open to the end of chapter 4, and every scene is in the album at the end.
- **SC-006**: After a restore from the server, the apartment, timeline, album and requests match the
  state before it in 100% of the tested states, and no scene plays by itself.
- **SC-007**: For all nine artboards, every tappable is within ±2 pt of its measured box, and the owner
  approves the goldens beside the design's images with no differences beyond the listed ones.
- **SC-008**: 100% of tappables are at least 44×44 pt and 100% of text at least 12 pt, at 390 and 360 pt
  wide.
- **SC-009**: The tab, a piece's sheet and the timeline show their full content within half a second of
  the tap, and a scene's first panel within one second, on the reference low-end device with no network.
- **SC-010**: In a moderated playtest, at least four of five players new to the game can say, after
  opening the tab once, what they are saving for and how much is left. (An owner check.)

## Assumptions

- **Dependencies.** All merged: M05 (the economy and its purchase path), M06 (sync, rollback and the
  state replacement), M04 (the content source), M21 (tokens, components, the characters' art), M07 (the
  first session, its scenes and `ScenePlayer`'s panel art), M22 (the panels' animation), M08 (Home,
  the result, the progression rules, the savings target, the arrival items) and M09 (the vehicle sheet,
  the playable rule for story trips). The server side exists: B03 accepts and validates
  `spend_jenehat` for pieces and chapters, `story_progress` and `claim_request`, and grants room,
  chapter and request BONAT. No server rule changes, so no shared unlock fixture is needed (M08 handed
  one over only "if it changes the chapter rules on both sides").
- **Changes to merged features** (the plan says how; each keeps the merged tests passing or updates
  them with the reason):
  - M08: `storySceneWaiting`, `StoryAfterResult`, the scene arrival item and the apartment's
    destinations become real; the savings card plays a waiting scene and shows the end of the story;
    `apartmentOpens` keeps its rule.
  - M07: its recorded scenes are sent; its first-session scenes play as they do today, and only their
    replays use the scene viewer.
  - M06: the two operations and the mapping of the state's story block.
  - M02 and 008.5: the story trip's riders, title, condition text, comments and failure line, from
    content.
  - B04: the content additions in its authoring, import and snapshot, as M07 and M09 did.
- **HANDOFF §9.3 #2, settled by the owner** (Clarifications): the tab is open from chapter 1 with the
  goal view, as the design draws it; the ux-spec's locked tab in chapters 1–2 is not followed. The rooms
  open in the first chapter whose goal is a room, as M08 already reads it.
- **Story trips' riders are in this feature, settled by the owner** (Clarifications, US8): the riders,
  title, condition text, comments and failure line. The release draft and 008.5 hand them here, and
  the release pack waits for them.
- **The album has one card per scene, settled by the owner** (Clarifications): the release draft's
  chapters hold one to three scenes each, which a card per chapter (the design's seven) couldn't show.
  The timeline's «شوف المشهد» still plays a chapter's scenes in order.
- **The first session's scenes keep M07's look, settled by the owner** (Clarifications): the opening
  and سلمى's scene play as M07 built them during the first session, which stays untouched; every later
  scene and every replay uses the scene viewer.
- **Resolved here without the owner** (`/speckit-clarify` can revisit any of them):
  - **A scene plays by itself once**; put off or skipped, it waits on Home's card and in the album.
  - **«اطلع مشوار» starts the next trip** (the design), not Home (the ux-spec), as HANDOFF advises.
  - **The next target piece is M08's**, the first unowned by order, so the apartment and Home agree.
  - **Requests count only pieces and styles** (the server's rule); the artboard's counted row («٣
    مشاوير بتلات نجوم») is not used. The badge counts every unclaimed request the sheet lists (the
    artboard's «٢» is sample data). A request the player can no longer meet leaves the list, since an
    owned piece can't change style; the piece sheet warns before that happens (owner, Clarifications).
  - **Claims work offline**, queued like every operation, with the reward on its way until the server
    grants it, like rooms' and chapters' rewards (B03 clarification).
  - **Chapters done by a line, a vehicle or a purchase get no dialog**; their reward arrives with the
    sync, and their scene is the celebration.
  - **Chapters and rooms not in the pack show locked with their names** (the design shows all seven
    chapters and three rooms); a pack can't carry a chapter without its content, so the names are the
    app's.
- **Content.** Schema changes are free: `content/source/pack.json` doesn't exist yet. The sample pack
  gains the new fields (its golden checksums are regenerated). The release draft (`content-core-r1`)
  adds them on its own branch, with the shabka scene timed after `line_gamaa.18`, and the owner may
  rewrite every text. No trip definition changes, so the engines and the parity fixtures stay as they
  are.
- **Art** (owner actions, none blocking the build): the salon's drawing with a place for each piece;
  one drawing per piece style (12 in the release draft); the comic panels of chapters 1–4 not yet drawn;
  the three goal pictures. Panels can gain animations later through M22's path.
- **Copy.** The artboards' strings are used as given. The strings of the undrawn states, the pending
  reward, the end of the story and the announcements are proposed in the plan, and the owner approves
  them (an owner action).
- **Sample data.** Every number and name in the artboards is sample data (`docs/design/README.md`). The
  goldens use the artboards' samples through test content; the app shows the pack's.
- **Handed to later features**:
  - **M11**: none of these screens shows an ad; scenes play between trips, so the checkpoint is
    unchanged.
  - **M12**: the fuel sheet that «اطلع مشوار» opens with an empty tank.
  - **M15**: `item_purchased`, `share{kind: scene}`, a scene seen or skipped, a request claimed.
  - **Phase 2**: the kitchen (chapter 5) and its pieces arrive as content; the album's video share.
- **Out of scope**: the garage and cosmetics (M16); the wedding trip's decorated vehicle and chapters
  5–7's content; sharing a scene as a video; any server rule change; any engine rule change.
