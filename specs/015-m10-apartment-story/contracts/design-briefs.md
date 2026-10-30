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

### 9. طلبات أهل العروسة، فاضية — `RequestsEmpty`

| | |
| --- | --- |
| Route | `/apartment/requests` (sheet over `AptRooms`) |
| State | Every request claimed or missed |
| From | `Requests` |

**Layout:** the header unchanged; the `States` empty pattern: a picture (أم العروسة satisfied, or a
tea tray) and «مفيش طلبات دلوقتي. أهل العروسة هيطلبوا لما تبدأ تجهّز.» (draft).

**Open question:** a different line when every request is done, for example «كل طلباتهم اتعملت»?

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

---

## After the boards land

Claude:

- adds each board's sample, golden and layout test;
- aligns the widgets to the board;
- moves the board's copy into `app_ar.arb`;
- lists the boards in `docs/delivery-plan.md`'s Design sources row for M10;
- writes "As drawn (date)" notes in each section here.
