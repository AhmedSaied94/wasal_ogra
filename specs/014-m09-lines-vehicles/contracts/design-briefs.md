# Contract: The Boards the Owner Draws for M09

`Lines`, `LineDetails` and `BuyVehicle` each draw one state. The first release mostly shows states
they don't draw: two vehicles and two lines, a story trip as the next cell, a finished line, the
shortfall, an owned vehicle. These are drawn by the owner, not by Claude (research R12). This file
is the brief, written in the shape of a HANDOFF §11 section, as M07's `FuelLesson` was
([fuel-lesson.md](../../012-m07-onboarding/contracts/fuel-lesson.md)).

## How to deliver

1. Draw each board on the Claude Design canvas «وصّل الأجرة — Design», in Style C «كرتون ناعم»,
   390×844 with the 36 pt status inset, one state per board, from the existing `Lines`,
   `LineDetails` and `BuyVehicle` boards.
2. Export with `docs/design/tools` (`export.py`, `boxes.py` + `boxes_post.py`, `build_assets.py`) and
   commit `docs/design/screens/<Board>.html`, `png/<Board>.png`, `boxes/<Board>.json` and the
   manifests. Or hand the export to Claude.
3. Give every tappable an `aria-label` (the strings below), so the layout test finds it by label.
   Draw the copy you want. Where it differs from the drafts below, the board wins, and Claude
   updates `app_ar.arb`.

**Sizes are proposals: the drawn board decides.** Until a board lands, Claude builds its state from
this brief, and only that board's sample, golden and layout test wait. Sample values come from the
release draft (`content/drafts/core-r1`): the microbus costs 3,200; خط الحي has 20 trips (story
trip `.20`); خط الجامعة has 30 (story trips `.01` and `.18`).

## Shared rules for every board

- **The locked look is HANDOFF §9.1 #6**, on tiles and cells too: `locked.bg`, a 2 pt `outline`
  ring, `ink.2` text, a lock icon, no opacity. The current boards draw locked tiles and cells
  dashed at 50%. Show how the lock, the price and the «قصة» chip sit in an 83.5×96 tile and a 65×62
  cell.
- **Disabled is §9.1 #5:** 45% opacity, no lip.
- **Text never clips** (§9.1 #10). Long names and reasons wrap and their card grows. Draw one long
  reason.
- **«كمّل» on a current line card is its own button** (Clarifications Q3). It starts the line's next
  trip, and the rest of the card opens the line's details. Give it `aria-label` «كمّل المشوار {n}».
- **The vehicle preview has no cosmetics** before the garage (phase 2): the plain sprite, and no
  «بزينتك».

---

## Needed by the first release

### 1. الخطوط، الفصل الأول — `LinesFirst`

| | |
| --- | --- |
| Route | `/lines` (tab) |
| State | Chapter 1, the first session included |
| Files | `screens/LinesFirst.html` · `png/LinesFirst.png` · `boxes/LinesFirst.json` |

**Purpose.** What every new player sees: one vehicle of theirs, one to save for, one line to play,
one locked.

**Layout** (proposal: `Lines`' header and nav unchanged):

| # | Block | Content | Open question for the board |
| --- | --- | --- | --- |
| 1 | Header | «الخطوط», coins «١٬٢٤٠» (no tap), BONAT «٨٥» | — |
| 2 | Vehicle strip | **Two** tiles: the tuktuk current («توكتوك · عربيتك», `sun`), the microbus for sale in the locked look with «قديم» and «٣٬٢٠٠» | Two tiles of 83.5 at the right, or two wider tiles across the strip? |
| 3 | Line map | **Two** cards on the road: خط الحي current at the bottom, خط الجامعة locked above it | Where two cards sit in 540 pt (at the bottom, the map's top empty?), where the road starts and ends, and what fills the space |
| 3a | Current card | «خط الحي» + fare chip «٧ ج»; «تعلّم اللمّ والباقي، الحاجة، النايم، المستعجل»; star «١٤/٦٠ · المشوار ٨ من ٢٠»; the «كمّل» button; node with the tuktuk glyph | «كمّل» as its own button |
| 3b | Locked card | lock; «خط الجامعة»; «محتاج الميكروباص القديم · نص الأجرة، الدفع الجماعي، "أنا دافع!"، أبو سمّاعة» (wraps); «٨٫٥ ج» | the long reason wrapping |
| 4 | Bottom nav | «الخطوط» active | — |

**Tappables and labels:**

- BONAT «البونات ٨٥»;
- the tuktuk tile «توكتوك المعلم، عربيتك دلوقتي»;
- the microbus tile «الميكروباص القديم، بـ٣٬٢٠٠ جنيه»;
- the current card «خط الحي، الحالي، ١٤ من ٦٠ نجمة، المشوار ٨ من ٢٠»;
- «كمّل المشوار ٨»;
- the locked card «خط الجامعة، مقفول، محتاج الميكروباص القديم»;
- the nav.

### 2. الخطوط بعد الميكروباص — `LinesOwned`

| | |
| --- | --- |
| Route | `/lines` (tab) |
| State | The microbus bought, خط الحي finished |

**Layout:** as `LinesFirst`, with:

- **Tiles:** the tuktuk done (tick, «توكتوك»); the microbus current («قديم · عربيتك», `sun`).
- **Done card:** «خط الحي» + «خلص»; «٥٤/٦٠ · عيد عشان النجوم»; «٧ ج»; the node with a tick.
- **Current card:** «خط الجامعة» + «٨٫٥ ج»; its what's new; «٢٧/٩٠ · المشوار ١٢ من ٣٠»; «كمّل».

**Labels:**

- «توكتوك المعلم، خلصته»;
- «الميكروباص القديم، عربيتك دلوقتي»;
- «خط الحي، خلص، ٥٤ من ٦٠ نجمة»;
- «خط الجامعة، الحالي، ٢٧ من ٩٠ نجمة، المشوار ١٢ من ٣٠»;
- «كمّل المشوار ١٢».

### 3. تفاصيل الخط، مشوار القصة — `LineDetailsStory`

| | |
| --- | --- |
| Route | `/lines/line_gamaa` (sheet over `LinesOwned`) |
| State | خط الجامعة after the shabka is bought. The player played `.19`–`.22` while the shabka trip `.18` waited. |

**Purpose.** Three looks the board doesn't draw: a story trip as the **next** cell, a second playable
cell without «كمّل», and locked cells in the §9.1 #6 look.

**Grid**, 30 trips, 6 rows (rows up to the one after the next trip, at least 4):

| Cells | State |
| --- | --- |
| 1 | story done, 3★, «قصة» |
| 2–17 | done, mixed stars |
| 18 | **story next**: `primary`, «١٨», «كمّل» and the «قصة» chip |
| 19–22 | done |
| 23 | **playable**: `primary`, «٢٣», no «كمّل» |
| 24–30 | locked (§9.1 #6) |

**Other blocks:**

- **Header:** «خط الجامعة»; «٥٨ من ٩٠ نجمة · ٢١ مشوار خلص».
- **The note,** unchanged.
- **The button:** «العب المشوار ١٨».
- **The grid scrolls** if six rows don't fit above the button. Show how.

**Labels:**

- «المشوار ١٨، الجاي، مشوار قصة»;
- «المشوار ٢٣، تقدر تلعبه»;
- «المشوار ٢٤، مقفول»;
- «اقفل»;
- «العب المشوار ١٨».

### 4. تفاصيل خط خلص — `LineDetailsDone`

| | |
| --- | --- |
| Route | `/lines/line_hay` (sheet over `LinesOwned`) |
| State | خط الحي with every trip played (`.20`, المعلم's, story done) |

**Layout:**

- **Header:** «خط الحي»; «٥٤ من ٦٠ نجمة · ٢٠ مشوار خلص».
- **Grid:** four rows, every cell done with its stars, and cell 20 story done.
- **Note:** only «المشاوير اللي خلصت تتعاد عشان النجوم.».
- **No play button.**

**Open question:** what fills the bottom where the button was (nothing, the note moved down, or a
line such as «عيد أي مشوار عشان النجوم»).

### 5. الميكروباص والفلوس مش كفاية — `BuyVehicleShort`

| | |
| --- | --- |
| Route | `/lines/vehicle/micro_old` (sheet over `LinesFirst`) |
| State | Coins 1,240 against 3,200 |

**Layout:**

- **Header:** «الميكروباص القديم» + close.
- **Preview:** the plain microbus (no cosmetics, no «بزينتك»).
- **Benefits:**
  - «١٠» over «كراسي بدل ٣»;
  - «بيفتح خط الجامعة»;
  - «قبض أكتر في كل مشوار».
- **Price card:** «السعر ٣٬٢٠٠» / «معاك ١٬٢٤٠ ج».
- **Above the buttons,** HANDOFF §9.2: «ناقصك ١٬٩٦٠ ج» in `danger.ink`, a gold `ProgressBar` of
  1,240 / 3,200, then «اشتريها» disabled (§9.1 #5) beside «لسه».

**Open questions:**

- 14 or 15 pt for «ناقصك» (§9.2 says 14; `Piece` draws 15).
- The bar's size and place.
- Does the impact line stay? The draft hides it when short.
- The disabled button at 64/25 (this sheet) or 56/21 (`Components`).

**Labels:**

- the price card «السعر ٣٬٢٠٠ جنيه، معاك ١٬٢٤٠ جنيه»;
- «اشتريها» (disabled);
- «لسه»;
- «اقفل».

**Also check, no board needed:** the affordable microbus with the plain preview and the reworded
impact line «بعد الشرا، فاضل ١٬٤٠٠ ج على الشبكة» is drawn from `BuyVehicle`'s blocks. The owner
approves its golden.

### 6. عربية بتاعتك — `BuyVehicleOwned`

| | |
| --- | --- |
| Route | `/lines/vehicle/micro_old` (sheet over `LinesOwned`) |
| State | The microbus, already the player's |

**Purpose.** All tiles open the sheet, and the board draws no owned version.

**Layout:**

- **Header and preview:** as `BuyVehicle`.
- **Benefits:** shown or not (the owner decides).
- **No** price card, impact line or buy button.
- **A status line:** «دي عربيتك».
- **One close button:** «تمام».

The tuktuk's sheet has the same layout, with «دي عربية المعلم، وانت شغال عليها»: in chapter 1 the
player drives المعلم's tuktuk.

**Open questions:** what replaces the price card; whether the benefits still show.

**Labels:** «تمام», «اقفل».

---

## Only with later packs or test content

Not reachable with the release draft. Draw them when convenient. Until then Claude builds them from
this brief, and the owner approves their goldens.

### 7. خط مقفول — `LineDetailsLocked`

`/lines/line_masyaf` over `Lines`.

- **The line:** «خط المصيف», locked «بعد خط السوق».
- **Grid:** every cell locked (four rows) and the hint.
- **The summary at zero:** «٠ من ٦٠ نجمة · ٠ مشوار خلص».
- **In the button's place,** the reason «بعد خط السوق», with nothing to tap.
- **Open question:** whether the note shows.

### 8. عربية مش للبيع دلوقتي — `BuyVehicleNotForSale`

`/lines/vehicle/micro_new` while the old microbus isn't owned.

- **The full sheet,** with the price card.
- **The status** «اشتري الميكروباص القديم الأول» in place of the buy button, and one close button.
- **Also show** the benefits row with **two** tiles (a vehicle that opens no line).
- **The same layout serves a vehicle with no price,** with «العربية دي مش للبيع دلوقتي».

---

## After the boards land

Claude:

- adds each board's sample, golden and layout test;
- aligns the widgets to the board;
- moves the board's copy into `app_ar.arb`;
- lists the boards in `docs/delivery-plan.md`'s Design sources row for M09;
- writes "As drawn (date)" notes here, as `fuel-lesson.md` has.
