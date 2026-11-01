# Contract: The Boards the Owner Draws for M10

The nine drawn artboards (`AptGoal`, `AptGoalReady`, `AptRooms`, `Piece`, `RoomDone`, `Requests`,
`SceneViewer`, `Chapters`, `Album`) each draw one state. The first release also shows states they
don't draw:

- chapter 1's goal counted in trips;
- chapter 2's goal bought through the vehicle sheet;
- an affordable next piece;
- the moment after a purchase;
- a finished room at the end of the story;
- the request mark;
- a reward on its way;
- a goal chapter in the timeline;
- no requests;
- Home after the last chapter.

The owner draws these, not Claude (research R18). This file is the brief, in M09's shape
([../../014-m09-lines-vehicles/contracts/design-briefs.md](../../014-m09-lines-vehicles/contracts/design-briefs.md)).

## How to deliver

1. Draw each board on the Claude Design canvas «وصّل الأجرة — Design», in Style C «كرتون ناعم»,
   390×844 with the 36 pt status inset, one state per board, from the existing boards named in each
   section.
2. Export with `docs/design/tools` (`export.py`, `boxes.py` + `boxes_post.py`, `build_assets.py`) and
   commit `docs/design/screens/<Board>.html`, `png/<Board>.png`, `boxes/<Board>.json` and the
   manifests. Or hand the export to Claude.
3. Give every tappable an `aria-label` (the strings below), so the layout test finds it by label.
   Draw the copy you want. Where it differs from the drafts below, the board wins, and Claude updates
   `app_ar.arb`.

**Sizes are proposals: the drawn board decides.** Until a board lands, Claude builds its state from
this brief, and only that board's sample, golden and layout test wait.

**Sample values** come from the release draft (`content-core-r1`):

- خط الحي has 20 trips, 19 of them regular: its story trip `.20` doesn't count toward chapter 1's
  goal (M08's `Count`, spec FR-006);
- the old microbus costs 3,200 and the shabka 3,600;
- the salon is الستارة 750, النجفة 1,050, النيش 1,300 and الأنتريه 1,600;
- the salon pays 25 BONAT and chapter 4 pays 20;
- the requests: النجفة كريستال (أم العروسة, 6), النيش (أم العروسة, 5), الأنتريه (أبو العروسة, 5).

## Shared rules for every board

- **The locked look is HANDOFF §9.1 #6:** `locked.bg`, a 2 pt `outline` ring, `ink.2` text, a lock
  icon, no opacity.
- **Disabled is §9.1 #5:** 45% opacity, no lip.
- **Text never clips** (§9.1 #10). Long names and lines wrap and their card grows.
- **`CountBadge` is `primary` with white digits** (§9.1 #8), not `AptRooms`' `danger`/`ink`.
- **The fuel cost chip is «−١» with the fuel icon** (§9.1 #4), not «−١ لتر».
- **BONAT agreement** follows §9.1 #3: «٥ بونات», «٢٥ بون».
- **A reward the server hasn't confirmed** is «في الطريق», never «كسبت». The phone never shows BONAT
  it doesn't have (constitution IV).

---

## Needed by the first release

### 1. الشقة، الفصل الأول — `AptGoalLine`

| | |
| --- | --- |
| Route | `/apartment` (tab) |
| State | Chapter 1: the goal is finishing خط الحي's regular trips, 8 of 19 done |
| From | `AptGoal` |
| Files | `screens/AptGoalLine.html` · `png/AptGoalLine.png` · `boxes/AptGoalLine.json` |

**Purpose.** The first goal isn't an amount. The board shows how a goal counted in trips reads.

**Layout** (as `AptGoal`, with):

| # | Block | Content | Open question |
| --- | --- | --- | --- |
| 2 | Chapter bar | «الفصل ١ · أول شغلانة» | — |
| 3a | Goal art | the tuktuk on the road (or a drawing you choose for chapter 1) | Which drawing? |
| 3b | Goal row | «خلّص خط الحي» + «٨ / ١٩ مشوار» | Does the row read in trips, or is a star or tick count clearer? |
| 3c | Progress | 42% | — |
| 3d | Character line | المعلم: «خلّص الخط ده وتبقى سوّاق بجد» (draft) | — |
| 4 | Teaser | unchanged | — |

There is no ready state and no CTA: the goal completes with the last trip.

**Labels:** «الفصل ١: أول شغلانة، كل الفصول»; progress «خلّص خط الحي، ٨ من ١٩ مشوار».

**As drawn (2026-10-31).** All ten boards of this file are drawn and exported (`AptGoalLine`,
`AptGoalVehicle`, `AptRoomsAffordable`, `AptRoomsBought`, `AptRoomsDone`, `PieceAffordable`,
`RoomDonePending`, `ChaptersGoal`, `RequestsEmpty`, `HomeStoryEnd`). Their samples play the release
draft, and **the draft wins on every text it owns** (owner decision 2026-10-31: chapter lines,
taglines, comments, names, scene titles). Each difference is listed in its section as «board shows X,
draft wins; the board will be redrawn/ignored for that text», and the layout tests name the ones that
change a wrap or a box. The board's app chrome (labels, ARB strings, layout) still wins.

- **A goal row** is 41 high for its name (Marhey 24) with the figures on its row at the end, or on a
  row of their own under the name when both don't fit (`GoalHeadline`): «٨ / ١٩ مشوار» sits beside
  «خلّص خط الحي», «٣٬٢٠٠ / ٣٬٢٠٠ ج» drops under «الميكروباص القديم».
- **The bar** is 14 high: `primary` on `track` for a count, `gold` for an amount (full at 100%).
- **The character line** is a 66-high `ground` box with her face (46 `paper` circle), the line in
  Marhey 600 16 and her name under it in 12/600 `ink.muted`.
- **The card is 375 high** (`AptGoalLine`); a `StatusChip`-sized «جاهز!» in the third station's
  green (`ink` text, 17 high) comes before the amount when the goal is ready.
- **Board vs draft copy:** the line, المعلم: board shows «خلّص الخط ده وتبقى سوّاق بجد», draft wins
  «لازم تجمع للشبكة يا أسطى، الشغل ده مش هزار». The goal art: the board draws a tuktuk on the road; the
  draft names `goal_shabka` for chapter 1 and the app ships that drawing only (art gap: the tuktuk
  scene isn't an asset yet, so the golden shows the shabka).
- **Layout test:** `AptGoalReady`'s box moves 15.8 pt (its line box is 66, was 82); the goldens of
  `AptGoal`, `AptGoalReady`, `AptGoalOffline` and `AptGoalSmall` changed with it.

### 2. الشقة، الميكروباص جاهز — `AptGoalVehicle`

| | |
| --- | --- |
| Route | `/apartment` (tab) |
| State | Chapter 2, balance 3,240, the old microbus (3,200) not owned |
| From | `AptGoalReady` |

**Purpose.** Chapter 2's goal is bought in M09's vehicle sheet, so the CTA opens it instead of
spending here.

**Layout** (as `AptGoalReady`, with):

- **Chapter bar:** «الفصل ٢ · أبو العروسة».
- **Goal art:** the old microbus (`VehicleSprite`, or a drawing).
- **Goal row:** «جاهزة!» + «٣٬٢٠٠ / ٣٬٢٠٠ ج».
- **Character line:** أبو العروسة: «عربية بتاعتك؟ كده نتكلم» (draft).
- **CTA:** «اشتري الميكروباص القديم» + «−٣٬٢٠٠ ج». It opens `/lines/vehicle/micro_old` (a sheet).
- **Open question:** a chevron or an "opens a sheet" cue on the CTA, since it doesn't spend at once?

**Labels:** CTA «اشتري الميكروباص القديم بتلات آلاف ومتين جنيه»; announcement «الميكروباص القديم
جاهز».

**As drawn (2026-10-31):** the chapter bar reads «الفصل ٢ · الكلام مع أبوها» (the chapter's own
title, not «أبو العروسة»). The card is 396 high: the art, the goal row with «جاهز!» (masculine for a
vehicle, «جاهزة!» for the shabka: ARB `apartmentGoalReady` selects by goal kind) before «٣٬٢٠٠ / ٣٬٢٠٠ ج»,
which drops under the long name; the `gold` bar full; the character line; and a 64-high CTA «اشتري» +
a `sun` price chip, 32 high, at its end side (the left, in RTL). **No chevron or sheet cue on the CTA** (the open
question): the label says it. The button's label is «اشتري الميكروباص القديم بـ٣٬٢٠٠ جنيه» in the app,
the board's is spoken; the price comes from the draft's catalog (3,200). The announcement «الميكروباص القديم
جاهز» is a hidden text box on the board and is said once when the goal becomes ready.

- **Board vs draft copy:** the line, أبو العروسة: board shows «عربية بتاعتك؟ كده نتكلم», draft wins
  «عايز أشوفك راكب عربية محترمة، مش توك توك».
- **Art gap:** the board draws the microbus on its own sun-soft ground; the app draws
  `VehicleSprite`'s static SVG, which ships its own sky scene.

### 3. الصالة، القطعة الجاية في الإيد — `AptRoomsAffordable`

| | |
| --- | --- |
| Route | `/apartment` (tab) |
| State | Chapter 4, الستارة owned, balance 1,180, النجفة (1,050) next and affordable; a claimed request's 5 BONAT not yet confirmed |
| From | `AptRooms` |

**Purpose.** Two undrawn looks: the next target the player can already buy, and the pending reward
chip.

**Layout** (as `AptRooms`, with):

| # | Block | Content | Open question |
| --- | --- | --- | --- |
| 1 | Header | «شقة العُمر», coins «١٬١٨٠», and the pending chip: BONAT icon + «+٥ بون في الطريق» (`sun.soft`) | Where the chip sits in the 52 header beside the coins pill, and whether it shrinks to «+٥» on narrow screens |
| 2 | Chapter bar | «الفصل ٤ · الصالة» / its tagline / «جهّزت ١ من ٤» | — |
| 4 | Room scene | الستارة drawn; three dashed slots with chips | — |
| 5 | Grid | الستارة «اتركّبت»; **النجفة «تقدر تشتريها» in `primary`, the bar full**; النيش «١٬٣٠٠ ج»; الأنتريه «١٬٦٠٠ ج» | Does the affordable cell keep its bar, or swap it for a small cart icon? |
| 6 | Strip | «خلّص الصالة وافتح مشهد «زيارة أهل العروسة»» | — |

**Labels:** the chip «٥ بون في الطريق، توصل مع المزامنة»; the cell «النجفة، تقدر تشتريها، ألف وخمسين
جنيه».

**As drawn (2026-10-31):**

- **Header (52):** the title at the end, the pending chip then the coins pill at the start. The chip is
  `sun.soft`, 105×40, a BONAT icon (20) with «+٥ بون» (13/700) over «في الطريق» (12/600
  `ink.muted`); it is a status, not a button. Under 360 pt it shrinks to the icon, «+٥» and a clock;
  it is absent when nothing is pending, and the coins pill keeps its place.
- **Chapter bar (56):** the title «الفصل ٤ · الصالة» (Marhey 17) over the tagline (12/500
  `primary.soft`) in a column filling the bar, «جهّزت ١ من ٤» (12/600) over an 80×8 `primary.lip`
  bar with a `sun` fill at the other end. The whole bar opens the timeline.
- **Tabs and requests:** a white 258×44 tablist (4 padding, 4 between, flex 20/20/25: 74.4 / 74.4 /
  93.2) with 36-high tabs: the open one `sun`, a locked one `ink.muted` with a 12 lock, inert and read
  «المطبخ، مقفولة». The requests button is 92×44, `sun.soft` with a 4 `sun.soft` lip, «الطلبات» (13/700)
  and its list icon, and a 20 `primary` badge «٢» hanging off its top corner on the left, 6 up and 4 out.
- **Room:** 358×300, radius 26. A chip is 44 high: «النجفة · ١٬٠٥٠» (14/700) and a 30 `primary` disc
  with a 14 plus, on a `paper` pill with a 4 `primary`@20% lip. The board hard-codes where each hangs;
  the app hangs it on the item's slot from the pack.
- **Grid:** 175×56 cards, radius 18, 8 apart. Owned: name + «اتركّبت» (12/700 `primary`) with a tick.
  The next target when affordable: «تقدر تشتريها» in `primary` with the bar **kept, full, `gold`, 6
  high** (the open question). Not affordable: «ناقصك {n}» in `danger.ink`, the bar partly filled.
  Missing: the price «١٬٣٠٠ ج».
- **Strip:** 48 high, `dashboard.bg`, 13/500 `paper`, an icon (20) at the start side.
- **Board vs draft copy:** the tagline, board shows «أهل العروسة جايين الخميس», draft wins «الصالون هو
  اللي بيحكي عن البيت»; the strip's scene, board shows «زيارة أهل العروسة», draft wins «العيلة في الصالون».
  Their lengths change no wrap or box.
- **Layout test:** the chips (offsets, one 128 wide against 134), the grid's order (the draft's `order`:
  الستاير, النجفة, النيش, الأنتريه against the board's الستاير, النيش, الأنتريه, النجفة, so three cards move)
  and box 42's spoken label.
- **Art gap:** the app ships no drawing of the salon or of its pieces (`ApartmentArt` has only the
  modern أنتريه), so the room draws the token wall, floor and blocks where the board draws the curtains
  and chandelier.
- **Minimum sizes (SC-006), departures from the board:** (1) a tab's 36 face has its 4 above and below
  as its own margin, so its hit row is 44 (the board's tablist padding is 4 all round, which left the
  open tab 36 to hit); (2) the room is the 358×300 design scaled to the phone, so a chip drawn 44 shows
  as 40 on a 360 phone: its height grows to 44 ÷ the scale there (48 at 360), and is 44 at 390; (3) at
  ×1.3 a tab's name, a piece card's status and the title beside the pending chip no longer ellipsize: the
  name shrinks to fit its tab, the status drops under the card's name, the title shrinks to the room left.

### 4. الصالة بعد الشرا — `AptRoomsBought`

| | |
| --- | --- |
| Route | `/apartment` (tab) |
| State | النجفة كريستال just bought (balance 130), 2 of 4 |
| From | `AptRooms` |

**Purpose.** The moment after a purchase: the piece in its place and سلمى's comment.

**Layout** (as `AptRooms`, with):

- **Room scene:** النجفة drawn in its slot, settled (the end of the drop-in), its chip gone.
- **سلمى's bubble** over the room: her avatar 46 and «الكريستال ده هيلمّع الصالة كلها» (draft, the
  variant's comment). It stays until the next tap.
- **Grid:** النجفة «اتركّبت»; النيش the next target, «ناقصك ١٬١٧٠» with its bar.
- **Open questions:**
  - Where does the bubble sit: over the room's top, or anchored to the piece?
  - Does it cover a chip?

**Motion note:** the drop-in (about 300 ms, ease out and settle) and `bubblePop`. Draw the end frame.

**As drawn (2026-10-31):**

- **The bubble is anchored to the piece** (the open question): 310×54 at 24 from the room's sides, its
  top 14 above the piece's bottom, a tail pointing up at it, her face (46) at the start and the
  variant's comment in Marhey 600. It **covers no chip** (the open question): the board draws it above
  النيش's and الأنتريه's chips, and the new piece's chip is gone. A tap or a scroll anywhere on the
  view ends it; the purchase is announced once, politely, «اشتريت النجفة».
- **Header and bar:** the coins pill alone («١٣٠», no pending chip), the bar «جهّزت ٢ من ٤» with the
  `sun` fill at half.
- **Grid:** النجفة «اتركّبت»; النيش the next target, «ناقصك ١٬١٧٠» in `danger.ink` with its `gold` bar.
  The app orders the cards by the draft (النجفة second, النيش third), the board has النيش second and
  النجفة last: three cards move in the layout test.
- **Board vs draft copy:** the comment, board shows «الكريستال ده هيلمّع الصالة كلها», draft wins
  «الكريستال بيلمع في النور» (the variant's `comment`); the tagline and strip as `AptRoomsAffordable`.
- **Drop-in:** `dialogIn` from 24 above, a fade only under reduced motion; the golden draws the end
  frame. Art gap as `AptRoomsAffordable`: the piece is its token block.

### 5. الصالة خلصت، والحكاية لحد هنا — `AptRoomsDone`

| | |
| --- | --- |
| Route | `/apartment` (tab) |
| State | All four pieces owned; `RoomDone` closed with «بعدين», so the goal scene waits; chapter 4 is the release's last chapter |
| From | `AptRooms` |

**Purpose.** A finished room: the scene still waiting, and the end of the story so far.

**Layout** (as `AptRooms`, with):

| # | Block | Content | Open question |
| --- | --- | --- | --- |
| 2 | Chapter bar | «الفصل ٤ · الصالة» / tagline; the bar full; **its trailing side a «شوف المشهد» chip** (its own button, play icon) | How the chip sits in the 56 bar, and how the bar shows that the rest still opens the timeline |
| 3 | Rooms row | the requests button with no badge (none open) | — |
| 4 | Room scene | every piece in place, no chips | — |
| 5 | Grid | four cells «اتركّبت» | — |
| 6 | Strip | `InfoStrip` «باقي الحكاية جاية في تحديث قريب» (draft) | Another icon than the clapper? |

**Labels:** «شوف المشهد: زيارة أهل العروسة»; the bar «الفصل ٤: الصالة، خلصت، كل الفصول».

**As drawn (2026-10-31):**

- **The bar (56):** the title with a 16 chevron after it (the rest of the bar opens the timeline) over
  the tagline; at its far end a `sun` pill «شوف المشهد» with a play icon, **28 drawn and 44 to hit**,
  its own button inside the bar (the bar reads its own label, «الفصل ٤: الصالة، خلصت، كل الفصول»,
  and the pill «شوف المشهد: {scene}»), over the full 80×8 bar (`sun` on `primary.lip`).
- **Requests:** the button has no badge, read «طلبات أهل العروسة، مفيش طلبات مفتوحة».
- **Grid:** four «اتركّبت» cards. **Strip:** the clock icon (the open question), «باقي الحكاية جاية
  في تحديث قريب», shown because the draft ends at chapter 4 (`storyEnd`).
- **Board vs draft copy:** the scene, board shows «زيارة أهل العروسة», draft wins «العيلة في الصالون»
  (the pill's label and its 126-wide box: Flutter measures the label wider than the browser did, so the
  pill's far side moves 12 pt); the tagline as `AptRoomsAffordable`.
- **Minimum sizes (SC-006), departures from the board:** the tabs' hit rows are 44 as in `AptRoomsAffordable`;
  the pill's 126 no longer fits the 40% of the bar a trailing control had on a 360 phone, so a control may
  take 60% and the bar's title wraps to as many lines as it needs (the bar then grows past 56, at ×1.3).

### 6. لوح القطعة، مع طلب — `PieceAffordable`

| | |
| --- | --- |
| Route | `/apartment/item/salon.nagafa` (sheet over `AptRooms`) |
| State | Balance 1,180, النجفة 1,050; أم العروسة asked for كريستال; مودرن selected |
| From | `Piece` |

**Purpose.** The affordable button (HANDOFF §9.2), the request mark and the line that warns before a
request is missed (Clarifications Q4).

**Layout** (as `Piece`, with):

- **Styles:** كريستال، مودرن، نحاس. Under «كريستال», a `StatusChip` «طلب أم العروسة». «مودرن» is
  selected.
- **سلمى's line:** مودرن's comment.
- **Above the button:** «لو اخترت ده، طلب أم العروسة هيفوتك» in `danger.ink` 13/700. It wraps.
- **The button:** «اشتري» + «−١٬٠٥٠ ج».
- **Open questions:**
  - The mark's colour (`sun` or `primary.soft`?).
  - Whether the warning line carries an icon.

**Labels:** the mark «كريستال، طلب أم العروسة»; the button «اشتري النجفة مودرن بألف وخمسين جنيه».

**As drawn (2026-10-31):**

- **The sheet is 700 high** (top at 144). The request mark is **`sun`** (the open question): a pill
  hanging off the bottom of the كريستال tile (114×92), 12/700, wrapping to two lines in the tile's
  width; the tile's own label reads «كريستال، طلب أم العروسة». The three tiles are 114 wide, 12 apart.
- **No icon on the warning** (the open question): «لو اخترت ده، طلب أم العروسة هيفوتك» is 13/700
  `danger.ink`, centred, 12 under the price card and 8 above the button.
- **The button:** 64 high, «اشتري» with a `sun` price chip «−١٬٠٥٠ ج» (32 high, 14/700) at its end side.
  There is **no «تقدر تشتريها» line** when nothing refuses it; a refusal replaces the warning's place.
  The label names the chosen style: «اشتري النجفة مودرن بـ١٬٠٥٠ جنيه».
- **Board vs draft copy:** سلمى's line, board shows «المودرن شيك وبسيط، ونوره هادي», draft wins «المودرن
  بسيطة وشيك» (the variant's `comment`); the sheet's name, tile names and the warning match the draft.
- **Layout test:** the sheet opens about 3 pt higher than 700 (its content and the sheet's 14 pt bottom
  padding make it 703), so the tiles and the button sit 3 pt above the board (3.2 pt tolerance); the
  close button reads «قفل» in the app, «اقفل» on the board (the app-wide label).
- **Art gap:** the preview and the tiles draw the token block, the board its chandeliers.

### 7. الغرفة خلصت، والمكافأة في الطريق — `RoomDonePending`

| | |
| --- | --- |
| Route | dialog over `/apartment` |
| State | The salon finished offline, which also completes chapter 4; its 25 BONAT and the chapter's 20 not yet confirmed |
| From | `RoomDone` |

**Purpose.** The phone never grants BONAT. The reward shows as on its way until the server confirms
it.

**Layout** (as `RoomDone`, with):

- **Reward pill:** «+٤٥ بون مكافأة» (the room's 25 and the chapter's 20, spec FR-023), with «في
  الطريق» under it, or inside the pill (12/600 `ink.muted`).
- **No `bonat_burst`.**
- **Open question:** the pill's look while pending: a dashed lip, or a clock icon?

**Announcement:** «الصالة خلصت، المكافأة خمسة وأربعين بون في الطريق».

**As drawn (2026-10-31):**

- **The pill is inside, with no dashed lip** (the open question): a `sun.soft` pill, 172×44.6, a BONAT
  icon (24) at the start, «+٤٥ بون مكافأة» (16/700) over a 14 clock icon and «في الطريق» (12/600
  `ink.muted`). It is a status; once the server confirms, only the first line stays.
- **The dialog is 358×542:** the drawing (260×130), the chip «الفصل ٤ · ٤ من ٤ قطع» (13/700 `primary`
  on `primary.soft`), the title (Marhey 30, 52 high), the pill, the quote card, the CTA and «بعدين».
  The card is 322×81.8 on `ground` with her face (46), the line in Marhey 600 16 and «سلمى» under it
  (12/600). The CTA is 60 high with Marhey 24 and a 22 play icon, labelled «شوف المشهد: {scene}».
  The dialog says «الصالة خلصت، المكافأة ٤٥ بون في الطريق» once, politely, when it opens.
- **Board vs draft copy:** her line, board shows «تحفة يا أسطى! ماما هتفرح أوي يوم الخميس», draft wins
  «الصالون خلص، تعالوا اتفرجوا» (the room's `done_line`, one line against two, so the card keeps its
  minimum height); the scene in the CTA's label, «زيارة أهل العروسة» on the board, «العيلة في الصالون»
  in the draft.
- **Layout test:** the board pins the dialog 17 pt below where the app centres it (both 542 high), so
  the boxes move by −16; «بعدين» is 63 wide on the board and 56 here, the same centre.
- **Art gap:** the drawing is the token room cropped to 130 high, without the board's sparkles.

### 8. خط الفصول، فصل هدف — `ChaptersGoal`

| | |
| --- | --- |
| Route | `/apartment/chapters` |
| State | Chapter 3 current (the shabka, 2,200 of 3,600 saved); chapters 1–2 done; 4–7 locked |
| From | `Chapters` |

**Purpose.** The current row when the chapter's goal isn't a room.

**Layout** (as `Chapters`, with):

- **Current row:** «الفصل ٣ · دلوقتي» + `StatusChip` «٢٬٢٠٠ / ٣٬٦٠٠ ج»; title «الشبكة»;
  description «شبكة تليق بسلمى» (draft goal line).
- **Done rows:** chapters 1 and 2, each with its thumbnail and «شوف المشهد».
- **Locked rows:** the salon, المطبخ, أوضة النوم, الفرح (the last three are ARB names, since the pack
  doesn't have them yet).
- **The rail:** filled to chapter 3's node.
- **Open question:** a progress bar on the current row, or the chip alone?

**As drawn (2026-10-31):**

- **The chip alone** (the open question): the current card is 104 high with «الفصل ٣ · دلوقتي», the
  `sun` chip «٢٬٢٠٠ / ٣٬٦٠٠ ج», the name (Marhey 20) and the description (13/500 `primary.soft`); no bar.
  The description is the chapter's `goal_line` when its goal isn't a room (a room lists its pieces).
- **Done rows** (80 high): the scene's thumbnail (70×56), «الفصل ١» over the name, and «شوف المشهد»
  (13/700 `primary` on `ground`, 105×44) whose label is «شوف المشهد: {scene title}», the last scene
  the player has unlocked in that chapter. **Locked rows** (58): number, name, lock; the rail is filled
  to chapter 3's node (a 4×240 `primary` stretch over the 516 `ground.lip` track).
- **Board vs draft copy:** the description, board shows «شبكة تليق بسلمى», draft wins the chapter's
  `goal_line`, «الشبكة هي اللي بتفرّح البنت، مش كلام» (أم العروسة); the done rows' scenes, board shows
  «سلمى في الموقف» and «بتشتغل إيه؟», draft wins «أول نظرة» (chapter 1's last unlocked scene) and «أبوها
  بيسأل» (chapter 2's); the rows' thumbnails are the scenes' own panels, which the board draws as
  stand-ins (an art gap for chapter 2's panel, drawn as its token ground).
- **Locked rows:** the draft has four chapters, so المطبخ, أوضة النوم and الفرح are the timeline's ARB
  names, as the brief said. The wrap and the boxes match the board's within 2 pt.

### 9. طلبات أهل العروسة، فاضية — `RequestsEmpty`

| | |
| --- | --- |
| Route | `/apartment/requests` (sheet over `AptRooms`) |
| State | Every request claimed or missed |
| From | `Requests` |

**Layout:** the header unchanged; the `States` empty pattern: a picture (أم العروسة satisfied, or a
tea tray) and «مفيش طلبات دلوقتي. أهل العروسة هيطلبوا لما تبدأ تجهّز.» (draft).

**Open question:** a different line when every request is done, for example «كل طلباتهم اتعملت»?

**As drawn (2026-10-31):** the sheet is 620 high, its header as `Requests`. The empty state is a **ringed
card** (358×148, radius 24, a 2 `outline` inset ring, 18 padding, 10 between) with the **tea tray**
(80×60, imported with `tool/design/sync_assets.dart` to `assets/illustrations/apartment/tea_tray.svg`:
the one new asset of the ten boards) over «مفيش طلبات مفتوحة دلوقتي. لو أهل العروسة طلبوا حاجة جديدة،
هتلاقيها هنا.» (14/600, centred, two lines). **One line for every empty state** (the open question): the
sheet has one empty state, so the brief's draft line «مفيش طلبات دلوقتي. أهل العروسة هيطلبوا لما تبدأ
تجهّز.» is gone from `app_ar.arb`; it was app copy, not the pack's. The close button reads «قفل» in the
app, «اقفل» on the board.

### 10. الرئيسية بعد آخر فصل — `HomeStoryEnd`

| | |
| --- | --- |
| Route | `/home` |
| State | Chapter 4 complete, the last in the pack |
| From | `Home` |

**Purpose.** Home's savings card when there is nothing left to save for (research R14).

**Layout** (as `Home`, with):

- **The savings card:** «شقة العُمر», the end line «باقي الحكاية جاية في تحديث قريب», no amount and
  no bar. A small finished-salon thumbnail or a key. It opens the apartment.
- **Open question:** does the card shrink, or keep its height with the thumbnail?

**Label:** «شقة العُمر، باقي الحكاية جاية في تحديث قريب».

**As drawn (2026-10-31):** the card **keeps its 84 height with the thumbnail** (the open question): a
54 tile on `scene.room` with the finished salon (radius 18) at the start, «شقة العُمر» (Marhey 18) over
the end line (14/500 `ink`), no chapter label, no amount and no bar. It opens the apartment. The rest
of the board is `C-Home` with the player at the end of the draft: أحمد at level 3, 1,240 JENEHAT, 85
BONAT, 4 of 5 liters with 12:30 to the next, trip 12 of 30 on خط الجامعة with 27 of 90 stars, and no
scene waiting (so the card shows no «مشهد جديد مستنيك»). The label is «شقة العُمر، باقي الحكاية جاية
في تحديث قريب» (the app's old «الحكاية خلصت، …» is replaced).

- **Open question (the designer's):** the start button's label is «يلا نطلع!، بيصرف لتر بنزين» on this
  board and «يلا نطلع!، هيصرف لتر بنزين» on `C-Home` and in `app_ar.arb`. The layout test pairs them and
  the ARB keeps «هيصرف» until one is chosen (the pre-trip card and the result use the same word).
- **Art gap:** the tile draws the token room; the board's finished salon isn't an asset. The rest of
  the board (the bus, the passengers, the fuel icon) differs as on `C-Home`'s golden.

---

## After the boards land

Claude:

- adds each board's sample, golden and layout test;
- aligns the widgets to the board;
- moves the board's copy into `app_ar.arb`;
- lists the boards in `docs/delivery-plan.md`'s Design sources row for M10;
- writes "As drawn (date)" notes in each section here.
