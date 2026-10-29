# Feature Specification: Lines Map, Line Details and Vehicle Purchase (M09)

**Feature Branch**: `014-m09-lines-vehicles`

**Created**: 2026-10-27

**Updated**: 2026-10-28, against master after M07 (012), M22 (012.5) and M08 (013) merged

**Status**: Draft

**Input**: User description: "M09: Lines map, line detail, vehicle purchase (feature
014-m09-lines-vehicles)". In `docs/delivery-plan.md` step 7, spec 014 is M09: "Lines map, line
detail, vehicle purchase", which depends on M05. Sources: `docs/ux-spec.md`
«الخطوط والعربية والجراج»; `docs/product-spec.md` «التقدم: الخطوط والعربيات» (with «الفصول» and
«خارطة الطريق»); the design `Lines`, `LineDetails` and `BuyVehicle` (`docs/design/HANDOFF.md` §7, §8,
§9.1, §9.2 and §11, with `docs/design/README.md`'s project overrides and "Checking a screen against
the design"); `docs/architecture-mobile.md` §9, §13 and §23 (M09's row); `docs/architecture-backend.md`
§7.4 and B03 research R6 (the server's unlock rules). Handed over from M05: "M09 and M10 check unlock
order before calling `buy`" (the economy checks only the catalog, balances, ownership and fuel).
Handed over from the first-release content draft (`content/drafts/core-r1/BRIEF.md`, "Waits on other
features"): a line's "what's new" text and fare label, and a vehicle's short name, are M09's; B03's
rules accept both story trips earlier than the story wants, so M09 and M10 must hold أبو العروسة's
trip (`line_gamaa.01`) until the microbus is owned and present المعلم's (`line_hay.20`) as chapter
1's finale. Handed over from M08 (`specs/013-m08-home-result/research.md` R26, `contracts/seams.md`):
line details open the pre-trip card for a chosen trip through `startNextTrip`, after the
checkpoint; the screens use the phone's port of the server's rules,
`lib/core/progress/domain/unlocks.dart` (`contracts/progress-rules.md`); and M09 decides whether
Home's line card opens the current line's details instead of the map. The delivery plan's design
sources settle none of HANDOFF §9.3's open questions in M09. Done when (step 7, with M07, M08 and
M10): line progress and the vehicle purchase work offline.

## Clarifications

### Session 2026-10-29

- Q: When should a story trip become playable, and should the line's later trips wait for it? → A: It
  opens once its chapter's goal is met, as the chapter's finale; the line's regular trips never wait
  for it. This is a phone-only rule, stricter than the server's, and Home's next trip, the pre-trip
  card and the result's next trip switch to it (FR-007, FR-012).
- Q: Should the first release's Lines screen show only the installed pack's lines and vehicles, or
  also hint at later ones? → A: Only the pack's (two vehicles and two lines in the first release);
  later ones appear with the pack that adds them (FR-016).
- Q: On the Lines map, should «كمّل» on the current line's card start that line's next trip, or open
  the line's details like the rest of the card? → A: «كمّل» starts the line's next trip through M08's
  start path; the rest of the card opens the details (FR-019).
- Q: How should the vehicle sheet's impact line attach the goal's name, which changes after «لـ»? →
  A: Reword so the name needs no prefix: «بعد الشرا، فاضل {amount} ج على {goal}»; no content field and
  no spelling rule in the app (FR-032).

## User Scenarios & Testing *(mandatory)*

The player is past the first session and plays for the long run: they save the fares of each trip to
furnish an apartment and get married, and they climb from المعلم's tuktuk to a microbus of their own,
each vehicle opening a line with new kinds of passengers. The Lines tab is where they see that climb:
which vehicles they have and what the next one costs, which lines are open, how many stars they have
on each, and which trip comes next.

The other users are **M08**, merged (Home's line card opens Lines; Home's next trip, the pre-trip
card and the result's next trip read the same rules, and Home's savings card names the same savings
goal), **M07**, merged (its first session starts tutorial trips through the same start path),
**M10** (the story's chapters, story trips and savings goals use the same rules; chapter 2's goal is
buying the microbus), **M16** (the garage, phase 2, opens from the same vehicle tiles), **M15**
(analytics), and **the tester** on internal builds, whose debug list may still open any trip.

### User Story 1 - See where I stand: my vehicles and the lines (Priority: P1)

The player taps «الخطوط» in the bottom nav. At the top they see their savings and BONAT. Below, a strip
of vehicles from the right: the ones they've moved past carry a tick, the one they drive now is
highlighted as theirs, and the ones they don't have yet show their price. Below that, the lines sit
along a dashed road from the bottom up, the first line at the bottom. An open line they're working on
shows its fare, what's new on it, their stars and which trip comes next, with «كمّل», which starts
that next trip; the rest of the card opens the line's trips. A finished line shows «خلص» and invites a
replay for stars. A locked line says what opens it.

**Why this priority**: Long-term progress is half of the game's pull (product spec «التقدم»). Without
this screen the player can't see what they've earned, what the next vehicle costs, or what opens next.

**Independent Test**: With the sample pack and a scripted player state (some trips done, some stars,
owned vehicles, a balance), open Lines with the network off. The vehicle strip, each line's state,
fare, stars and next trip match the state, and on opening the map shows the line Home's line card
shows. Repeat with the first-session state and with a finished first line.

**Acceptance Scenarios**:

1. **Given** a new player after the tutorial, **When** they open Lines, **Then** the tuktuk is their
   current vehicle, the microbus shows its price, خط الحي is the current line with its next trip and
   stars, and خط الجامعة is locked with «محتاج» and the microbus's name.
2. **Given** a player who owns the microbus and has finished every regular trip of خط الحي, **When**
   they open Lines, **Then** the tuktuk carries a tick, the microbus is highlighted as theirs
   («قديم · عربيتك»), خط الحي is done («خلص» with its stars), and خط الجامعة is current with its fare,
   what's new, stars «{earned}/{max}» and «المشوار {n} من {total}».
3. **Given** any player, **Then** each line's stars are the sum of its trips' best stars out of three
   per trip, its fare shows in pounds with a half where there is one («٨٫٥ ج»), and every number
   follows the player's digit setting.
4. **Given** the balances, **When** the player taps the BONAT balance, **Then** the shop opens; the
   JENEHAT balance does nothing. Offline, the BONAT balance is disabled, as Home's pill is (M08).
5. **Given** Lines is open, **When** a sync changes the wallet, the progress or what the player owns,
   **Then** the screen shows the new state without being reopened.
6. **Given** more lines than fit on the screen (later packs, a larger text size), **Then** the map
   scrolls, the road grows with it, and on opening the line Home shows is in view.
7. **Given** Home, **When** the player taps its line card, **Then** Lines opens with that card's
   line in view (as `C-Home` and the ux-spec draw it).
8. **Given** a current line, **When** the player taps its «كمّل», **Then** its next trip starts as
   from the details' button (US2); **When** they tap elsewhere on the card, **Then** the line's
   details open.

---

### User Story 2 - Play the next trip of a line, or replay one for stars (Priority: P1)

The player taps a line and a sheet opens with every trip of the line in a grid of numbered cells, five
to a row, trip 1 at the top right. Finished trips show their best stars, and story trips carry a «قصة»
chip. The next trip is highlighted with «كمّل», and the big button at the bottom says
«العب المشوار ١٢». Trips after the next one are locked. Tapping a finished trip replays it for stars;
tapping the next one or the button plays it. Either way the start goes through Home's one start
path (M08): the pre-trip card opens first when it has something to brief or the player's setting
always shows it, and otherwise the trip starts.

**Why this priority**: This is how a player chooses what to play beyond Home's one-tap «يلا نطلع!»,
and the only way to replay a finished trip for its three stars, which the game's "one more time" loop
depends on (ux-spec «ما تعلمناه من تجربة النموذج»).

**Independent Test**: With a scripted state (trips 1–11 of a line done with mixed stars, trip 10 a
story trip), open the line. Cells 1–11 show their stars, 10 shows «قصة», 12 is next, 13 onward are
locked, and the button reads «العب المشوار ١٢». With the card setting on «always», tap cell 3, cell
12 and the button: each opens the pre-trip card for that trip. Tap cell 13: nothing happens.

**Acceptance Scenarios**:

1. **Given** a line, **When** the player opens it, **Then** the sheet shows the line's name, a summary
   «{stars} من {max} نجمة · {done} مشوار خلص» with Arabic count agreement, the grid, the info note
   «المشاوير اللي خلصت تتعاد عشان النجوم. الجاية بتتفتح لما اللي قبلها يخلص.», and the button
   «العب المشوار {n}» for the next trip.
2. **Given** a done cell, the next cell or the button, **When** the player taps it, **Then** the
   trip starts through M08's start path: the pre-trip card opens for that trip, or, when the card has
   nothing to brief and the player's setting skips it, the trip starts. **When** they close the card
   without starting, **Then** they are back on the line's details.
3. **Given** a locked cell, **When** the player taps it, **Then** nothing happens, and it doesn't look
   or announce itself as tappable.
4. **Given** a 30-trip line whose next trip is 12, **Then** trips 1–20 show and the hint
   «والمشاوير من ٢١ لـ ٣٠ بتظهر لما تقرّب» summarises the rest. **Given** a 20-trip line, **Then**
   every trip shows and there is no hint.
5. **Given** a line with nothing left to play, **Then** no button shows at the bottom, and every
   finished trip can still be replayed from its cell.
6. **Given** the sheet, **When** the player taps «اقفل», swipes it down or presses the phone's back
   button, **Then** it closes back to Lines.
7. **Given** a replay, **Then** it costs a liter like any trip start (M05 research R20). **Given** an
   empty tank, **When** the player taps a cell or the button, **Then** the fuel sheet opens instead,
   as from Home (M08's start path; M07's fuel lesson keeps its exception).

---

### User Story 3 - Buy the next vehicle and open its line (Priority: P1)

The player taps the microbus in the strip. A sheet shows it in a sunny street, three facts (how many
seats instead of the current vehicle's, which line it opens, more pay on every trip), its price next
to their savings, and one honest line about the dream: after buying it, how much is still missing for
the next savings goal. They tap «اشتريها»: the savings drop by the price, the sheet closes, the
microbus is their vehicle and خط الجامعة is open. With too little saved, the button is disabled and
the sheet says how much they're short.

**Why this priority**: The product spec makes this the game's central trade-off: the same savings buy
the apartment or a bigger vehicle that earns more. Chapter 2's goal is this purchase, and خط الجامعة,
half of the first release's content, opens only through it.

**Independent Test**: With a balance above the microbus's catalog price, offline, tap the microbus,
check the sheet's facts and impact line, tap «اشتريها». The balance drops by the price exactly once,
the microbus is current, خط الجامعة is open and its first playable trip can be started. Repeat with a
balance below the price: the shortfall shows and nothing can be bought. Double-tap «اشتريها»: the
price is spent once.

**Acceptance Scenarios**:

1. **Given** a vehicle for sale, **When** the player opens its sheet, **Then** it shows the vehicle's
   name and art, its seats against the current vehicle's («١٠» over «كراسي بدل ٣», with Arabic
   agreement), «بيفتح» and the line it opens, «قبض أكتر في كل مشوار», the catalog price under «السعر»,
   the JENEHAT balance under «معاك», the impact line, and «اشتريها» and «لسه».
2. **Given** a balance that covers the price, **When** the player taps «اشتريها», **Then** the price
   is spent once in JENEHAT, the vehicle becomes theirs, the sheet closes to Lines, the vehicle is
   current and its line is open, and a screen reader announces the purchase.
3. **Given** a balance below the price, **Then** «اشتريها» is disabled, and above it «ناقصك {n} ج»
   and a progress bar of the balance against the price show; «لسه» still closes.
4. **Given** the savings goal Home's savings card would show after this purchase (M08's savings
   target, worked out as if the vehicle were already bought), **Then** the impact line reads
   «بعد الشرا، فاضل {amount} ج على {goal}» («بعد الشرا، فاضل ٢٬٤٠٠ ج على الشبكة»), with the goal's
   name as the content gives it and the amount still missing after paying for the vehicle. **Given** no
   such goal, a goal without a price (finish a line), or nothing missing, **Then** the line is hidden.
5. **Given** no network, **When** the player buys, **Then** the purchase applies at once and syncs
   later. **When** the server later refuses it, **Then** the vehicle is no longer theirs, the savings
   come back, Lines shows the resulting state, and the player sees the sync's neutral notice.
6. **Given** a double tap, a retry, or a tap while the purchase is still being applied, **Then** the
   price is spent at most once.
7. **Given** «لسه», «اقفل», a swipe down or the phone's back button, **Then** the sheet closes and
   nothing is spent.
8. **Given** the purchase can't be stored (a full disk), **Then** nothing is spent, the player sees a
   short error, and they may try again.

---

### User Story 4 - Locked things explain themselves (Priority: P2)

Every locked line says what opens it. Tapping a line that needs a vehicle opens that vehicle's sheet,
so the path from "I want that line" to "this is what it costs" is one tap. Tapping a line that needs
another line finished opens its details, locked, with the reason. A vehicle the player already has
opens its sheet without a price, and a vehicle that comes after one they don't have yet says which
comes first.

**Why this priority**: It turns every locked thing into a goal instead of a dead end, but the screens
of stories 1–3 work without it.

**Independent Test**: With test content holding a line unlocked by a vehicle and a line unlocked by
finishing another line, tap each locked line, each owned vehicle and a vehicle whose predecessor isn't
owned, and check what opens and what it says.

**Acceptance Scenarios**:

1. **Given** a line locked behind a vehicle, **Then** its card shows a lock, its name, «محتاج
   {vehicle}» followed by «· {what's new}», and its fare. **When** tapped, **Then** that vehicle's sheet
   opens.
2. **Given** a line locked behind another line, **Then** its card says «بعد {line}». **When** tapped,
   **Then** its details open with every trip locked and the reason in place of the play button.
3. **Given** a vehicle the player already has, **When** they tap its tile, **Then** its sheet opens
   with no price, no impact line and no buy button, says it's theirs, and closes with one button.
4. **Given** a vehicle whose predecessor in the pack's order the player doesn't have, **When** they tap
   it, **Then** its sheet shows no buy button and names the vehicle that comes first.

---

### User Story 5 - Story trips come at their moment in the line (Priority: P2)

A few trips of a line are story trips: المعلم rides along on خط الحي's last trip before letting the
driver go, أبو العروسة rides the first trip of the driver's own microbus, and the bride's mother and
سلمى ride to the jeweler on the shabka trip. On the line's grid they carry a «قصة» chip. They open when
the story reaches them, not before.

**Why this priority**: The story gives every pound its meaning (product spec «القصة والميتا»), and a
story trip played out of order spoils its scene. The server accepts a story trip as soon as its
chapter is unlocked (B03 research R6), and so does the phone's port that M08 merged
(`tripUnlocked`), which Home's next trip, the pre-trip card and the result's next trip read today.
With that rule, Home offers the shabka trip right after `line_gamaa.17`, before the shabka is
bought, and the grid would show المعلم's trip as playable from the first day. Only the phone can
hold story trips back.

**Independent Test**: With the first-release draft's chapters and trips, script the states below and
check each story trip's cell and the line's next trip.

**Acceptance Scenarios**:

1. **Given** a player who doesn't own the microbus, **Then** أبو العروسة's trip (`line_gamaa.01`) is
   locked, whatever chapter they're in.
2. **Given** a player who has finished every regular trip of خط الحي (`.01`–`.19`), **Then** المعلم's
   trip (`line_hay.20`) is the line's next trip, its chapter's finale.
3. **Given** a story trip that isn't open, **Then** its cell shows «قصة» with a lock; once played,
   **Then** it shows «قصة» with its stars.
4. **Given** a player who has finished `line_gamaa.17` and hasn't bought the shabka, **Then** the
   shabka trip (`line_gamaa.18`) is locked with its «قصة» chip, and the line's next trip is
   `line_gamaa.19`. **When** they buy the shabka, **Then** `.18` becomes playable and is the line's
   next trip, even if they have played past `.19`.
5. **Given** any of the states above, **Then** Home's next trip, the pre-trip card and the result's
   next trip treat each story trip exactly as the line's grid does: none of them offers or opens a
   story trip whose chapter isn't complete.

---

### User Story 6 - The Lines tab says when something new is there (Priority: P3)

When a vehicle the player can buy becomes affordable, a line opens, or a story trip opens, the
«الخطوط» tab gets the red «new» dot. Opening Lines clears it.

**Why this priority**: A nudge toward the next goal; nothing depends on it.

**Independent Test**: From Home, finish a trip that brings the balance to the microbus's price: the
dot appears on «الخطوط». Open Lines: it clears. Restart the app: it stays cleared.

**Acceptance Scenarios**:

1. **Given** the player last opened Lines before the event, **When** a vehicle for sale becomes
   affordable, a line opens or a story trip opens, **Then** the dot shows on «الخطوط».
2. **When** the player opens Lines, **Then** the dot clears, and it stays cleared after a restart
   until the next such event.
3. **Given** the event happens while Lines is open (the player just bought the vehicle there),
   **Then** no dot appears.

---

### Edge Cases

- **A newer pack adds trips** to a line the player had finished: the line becomes current again, and
  its new trips continue the line's order.
- **Progress or ownership naming ids the active pack lacks** (after a fallback to the bundled pack):
  skipped, never an error; the counts use only the pack's trips.
- **The server refuses a vehicle purchase** made offline (its balance was lower): the vehicle stops
  being the player's, its line locks again, and whatever else the server refused with it rolls back
  (M06). Lines shows the result, and the sync's one neutral toast tells the player.
- **The balance changes while the vehicle's sheet is open** (a sync): the shortfall appears or goes
  away, and «اشتريها» enables or disables, without closing the sheet.
- **The player buys the microbus before finishing خط الحي** (possible only with savings the draft's
  economy doesn't give): both lines are current, and the map opens on the line Home shows (FR-010).
- **A link to a line or vehicle the active pack lacks** (an old notification, a pack fallback): the app
  shows Lines.
- **Exactly enough savings**: the purchase is allowed and leaves 0.
- **No savings target after the purchase** (no chapters, or nothing left to save for), a target with
  no price (finish a line), or nothing missing after the purchase: the impact line is
  hidden.
- **A vehicle with no catalog price** (content validation should prevent it): its tile shows no price,
  and its sheet says it can't be bought now, with no buy button.
- **A line with no regular trips** (a content mistake): it never counts as complete, as on the server.
- **A story trip beyond the grid's visible range** stays hidden with the trips around it.
- **A finished line where every trip has three stars**: its card shows its stars without the replay
  prompt.
- **An unfinished trip at launch** opens the trip first (M02); Lines isn't reachable during a trip
  (the bottom nav is hidden there).
- **The first session** (M07): a tutorial trip chosen on Lines starts through M08's start path, which
  skips the card for tutorial trips and keeps M07's redirects on the trip route (a due scene, the
  fuel lesson, the guided order). The trips after the tutorial stay locked until it is done, since
  each waits for the one before it.
- **A start already under way** (M08's checkpoint is waiting): a second tap on «كمّل», a cell or the
  button does nothing, as on Home.
- **360 pt wide, text scale 1.3×**: cards and cells grow, the map and the grid scroll, and every
  minimum size still holds.

## Requirements *(mandatory)*

### Functional Requirements

#### Progression rules

The base rules (FR-002, FR-004–FR-006, FR-008) are already on the phone: M08 ported the server's
`unlocks.py` to `lib/core/progress/domain/unlocks.dart`, read through `PlayerProgress`
(`specs/013-m08-home-result/contracts/progress-rules.md`). They are restated here because these
screens show them; this feature reuses them and adds only the phone's stricter rules (FR-003,
FR-007).

- **FR-001**: The app MUST work out what is open from the active content pack and the player's state
  on the phone (best stars per trip, and what they own, as M08's `PlayerProgress` reads them), each
  time it is needed. It MUST NOT keep a separate record of unlocks that could drift from them.
- **FR-002**: A vehicle MUST count as the player's when it is the pack's starter vehicle or the player
  owns it (`vehicleOwned`). The player's **current vehicle** is the one of theirs that comes last in
  the pack's vehicle order.
- **FR-003**: A vehicle MUST be for sale to the player only when it isn't theirs, it has a JENEHAT
  price in the catalog, and every vehicle before it in the pack's order is theirs. (The server accepts
  vehicles in any order; this is the phone's unlock order for vehicles, checked before every
  purchase.)
- **FR-004**: A line MUST count as unlocked when its unlock rule is met (`lineUnlocked`): `start`
  always; `vehicle` when that vehicle is the player's; `line_complete` when that line is complete.
- **FR-005**: A line MUST count as complete when every regular trip of it has at least one star
  (`lineComplete`). Story trips don't count, and a line with no regular trip never is (as on the
  server).
- **FR-006**: A regular trip MUST be playable when its line is unlocked, its vehicle is the player's,
  and the regular trip before it in the line, by trip number, has at least one star (the line's first
  regular trip waits for none), as `tripUnlocked` has it.
- **FR-007**: A story trip MUST be playable only when its line is unlocked, its vehicle is the
  player's, and its chapter is complete (every chapter goal up to and including its own is met): it
  is its chapter's finale. The line's regular trips MUST NOT wait for it; they follow FR-006, as on
  the server. This is stricter than the server and M08's port, which open a story trip as soon as its
  chapter is unlocked, so it is a phone-only rule beside the port, and every way into a trip MUST use
  it (FR-012). With the release draft: `line_hay.20` opens once خط الحي's regular trips are done,
  `line_gamaa.01` once the microbus is owned, and `line_gamaa.18` once the shabka is bought.
- **FR-008**: A trip MUST count as done when it has at least one star. A line's **next trip** is its
  first trip, by number, that is playable and not done.
- **FR-009**: Each line MUST have one standing: **locked** (not unlocked), **current** (unlocked, with
  a next trip) or **done** (unlocked, with no next trip). Its stars are the sum of its trips' best
  stars, out of three times its number of trips.
- **FR-010**: The line the map shows on opening MUST be the line of Home's next trip (M08's rule: the
  line played last, else the earliest open line with a trip to play), so a tap on Home's line card
  lands on the same line.
- **FR-011**: The phone's rules MUST never be more permissive than the server's (B03 research R6):
  every trip the phone treats as playable, every line as unlocked and every vehicle as the player's,
  the server accepts. M08's port keeps passing its one-to-one copy of the server's cases
  (`test/core/progress/unlocks_test.dart`), and each phone-only rule (FR-003, FR-007) MUST have tests
  showing it only ever refuses more than the port.
- **FR-012**: Outside internal builds' debug list, every way into a trip MUST start only a playable
  trip: Lines and its details here, and, already merged, Home's next trip, the pre-trip card's opening
  check and the result's next trip (M08), which this feature switches from M08's port to the same
  rules, FR-007 included; M10's story screens later. A locked trip MUST NOT start and MUST NOT cost
  fuel.
- **FR-013**: Every rule MUST live in `lib/core/progress/domain/`, beside M08's port, as one set that
  Home, the card, the result, Lines and the story (M10) use, testable without any screen, skipping ids
  the active pack lacks rather than failing. No screen MUST compute an unlock on its own.

#### The Lines screen (`Lines`)

- **FR-014**: The «الخطوط» tab MUST show, top to bottom, as drawn in `Lines`: the title «الخطوط» with
  the JENEHAT and BONAT balances; the vehicle strip; the line map; and the bottom nav with «الخطوط»
  active.
- **FR-015**: The JENEHAT balance MUST NOT respond to taps; the BONAT balance MUST open the shop
  (HANDOFF §9.1 #7), and offline it MUST be disabled with Home's offline label (M08).
- **FR-016**: Lines MUST show only the vehicles and lines of the active pack, with nothing standing in
  for later ones (no «قريب» tiles or cards, no teaser); later vehicles and lines appear with the pack
  that adds them. The first release shows two vehicle tiles and two line cards. The strip and the map
  MUST lay out for any count from one up, not only the artboard's four vehicles and five lines.
- **FR-017**: The vehicle strip MUST show the vehicles in the pack's order from the right, each in one
  state: **done** (the player's and before the current vehicle: a tick), **current** («{short name} ·
  عربيتك») or **not the player's** (its catalog price in JENEHAT). Every tile MUST open that vehicle's
  sheet.
- **FR-018**: The line map MUST show the lines along a dashed road, the first line in the pack's order
  at the bottom, each as a card in its standing (FR-009):
  - **current**: name, fare chip, what's new, stars «{earned}/{max}» and «المشوار {n} من {total}»
    (`n` the next trip's number), and «كمّل»;
  - **done**: name, «خلص», stars with «عيد عشان النجوم» (stars alone when every trip has three), and
    fare;
  - **locked**: a lock, name, the reason («محتاج {vehicle}» or «بعد {line}») followed by
    «· {what's new}», and fare.
- **FR-019**: A tap on a current line's «كمّل» MUST start that line's next trip through M08's start
  path, exactly as the details' button does (FR-026); «كمّل» MUST be its own tappable of at least
  44×44 pt with its own screen-reader label naming the trip («كمّل المشوار {n}»). A tap anywhere else
  on a current or done line's card MUST open that line's details; a done line has no «كمّل». A tap on
  a locked line's card MUST open the sheet of the vehicle it needs when its rule is `vehicle`, and its
  details in their locked state (FR-028) when its rule is `line_complete`.
- **FR-020**: When the map is taller than its space, it MUST scroll, the road MUST grow with it, and
  on opening the line of FR-010 MUST be in view. Home's line card MUST keep opening Lines, as `C-Home`
  and the ux-spec draw it (M08's hand-over: not the line's details).
- **FR-021**: Fares MUST show in pounds, with a half where there is one («٧ ج», «٨٫٥ ج»), formatted
  from integer piasters only for display, in the player's digit style.
- **FR-022**: Every screen and sheet of this feature MUST follow changes to the wallet, the progress
  and ownership while open (a sync, a rollback), without being reopened.

#### A line's details (`LineDetails`)

- **FR-023**: A line's details MUST open as a sheet over Lines, as drawn in `LineDetails`: the line's
  name; the summary «{stars} من {max} نجمة · {done} مشوار خلص»; the trip grid; the hint for hidden
  trips; the info note; and the button «العب المشوار {n}» for the next trip, pinned at the bottom.
- **FR-024**: The grid MUST show five trips per row, trip 1 at the top right, each cell in one state:
  **done** (number and best stars), **story done** (number, best stars and the «قصة» chip), **next**
  (number and «كمّل»), **locked** (number and lock), **story locked** (the «قصة» chip and a lock). If
  more than one trip is playable and not done (a story trip that opened after the player played past
  it, FR-007), the next trip is drawn as next and the others as next without «كمّل».
- **FR-025**: The grid MUST show every row up to the furthest trip played or playable, plus one more
  row, never fewer than four rows (20 trips) and never more than the line has (the owner's choice of
  2026-10-29, as `LineDetailsStory` draws it). So a done line shows every row, and a locked line
  four. A story trip can open behind trips the player already finished, so the finished ones beyond
  it stay visible and replayable. The hint «والمشاوير من {from} لـ {to} بتظهر لما تقرّب» MUST name
  the trips left out, and MUST NOT show when none are. When the rows don't fit, the grid MUST scroll
  above the pinned button, and open with the next trip's row in view.
- **FR-026**: A tap on a done, story-done or playable cell, or on the button, MUST start that trip
  through M08's one start path, `startNextTrip` (`specs/013-m08-home-result/contracts/home.md`): the
  fuel sheet on an empty tank, then the between-trips checkpoint (M11's), then the pre-trip card or,
  for a tutorial trip in the first session or a trip the card setting skips, the trip itself. A second
  tap while a start is under way MUST do nothing. Closing the card without starting MUST return to the
  line's details; today the card always returns to Home, so this feature changes it to return to
  where it was opened. A locked cell MUST do nothing and MUST NOT present itself as tappable; a
  starred cell the rules no longer allow (a story trip whose chapter waits after a rollback, or a
  line a newer pack extends) keeps its stars and is drawn locked and inert the same way.
- **FR-027**: When the line has no next trip, the button MUST NOT show; replays start from the cells.
- **FR-028**: The details of a locked line MUST show every cell locked and, in the button's place, the
  reason («بعد {line}» or «محتاج {vehicle}»), with nothing to start.
- **FR-029**: The sheet MUST close with «اقفل», a swipe down or the phone's back button, back to Lines.

#### Buying a vehicle (`BuyVehicle`)

- **FR-030**: A vehicle's sheet MUST show, as drawn in `BuyVehicle`: its name; a preview of the
  vehicle; three benefits (its seat count against the current vehicle's, «{n} كرسي بدل {m}» with
  Arabic agreement; «بيفتح {line}» for the first line, by order, that this vehicle unlocks; «قبض أكتر
  في كل مشوار»); the price card («السعر» and the catalog price, «معاك» and the JENEHAT balance); the
  impact line (FR-032); and «اشتريها» and «لسه».
- **FR-031**: The preview MUST draw the vehicle from the game's animation file, with its static drawing
  as the fallback. The «بزينتك» chip MUST show only when the player owns cosmetics, which this release
  has none of, so it stays hidden. The «بيفتح» benefit MUST be left out when no line unlocks with this
  vehicle.
- **FR-032**: The impact line MUST read «بعد الشرا، فاضل {amount} ج على {goal}», where the goal is
  M08's **savings target** (`savingsTarget`, `specs/013-m08-home-result/research.md` R4) worked out
  for the state after the purchase: the vehicle owned and the balance less its price. That is the
  goal Home's savings card will show next: before the apartment opens, the current chapter's goal
  (for the microbus, chapter 3's shabka); from the apartment's chapter on, the next piece. The amount
  is the target's price minus the balance after the purchase. The goal's name MUST appear exactly as
  the content names it, with no prefix joined to it, so no content field and no spelling rule is
  needed; the wording replaces the artboard's «فاضل للنجفة ٢٬٤٠٠ ج» and is listed with the copy the
  owner approves (FR-052). The line MUST be hidden when there's no target, the target has no price
  (finish a line), or nothing would be missing.
- **FR-033**: When the balance doesn't cover the price, «اشتريها» MUST be disabled (HANDOFF §9.1 #5)
  and, above it, «ناقصك {n} ج» and a progress bar of the balance against the price MUST show (HANDOFF
  §9.2).
- **FR-034**: When the vehicle is already the player's, the sheet MUST show no price card, no impact
  line and no buy button, MUST say the vehicle is theirs, and MUST close with one button.
- **FR-035**: When the vehicle isn't for sale (FR-003), the sheet MUST show no buy button and MUST say
  why: the vehicle the player needs first, or, with no catalog price, that it can't be bought now.
- **FR-036**: «اشتريها» MUST buy through the economy's one purchase path, with one request id per
  intent, so a double tap, a retry or a tap during the purchase spends at most once (constitution VI).
  The price MUST be the catalog's, read again when the purchase applies, and in JENEHAT only
  (constitution IV, VII). The sheet MUST check FR-003 before asking.
- **FR-037**: After a purchase, the sheet MUST close to Lines, where the vehicle is current and the
  line it opens is unlocked, and a screen reader MUST hear the result.
- **FR-038**: When the economy refuses: too little savings (the balance changed) MUST show the
  shortfall state; already owned MUST show the owned state; anything else MUST close the sheet with a
  neutral message; a purchase that couldn't be stored MUST show a short error, with nothing spent and
  the purchase open to retry. No outcome may leave savings spent without the vehicle, or the reverse.
- **FR-039**: Buying MUST work offline and sync later (M06). A purchase the server later refuses MUST
  be undone by the sync's rollback, and the screens MUST show the state that results.
- **FR-040**: «لسه», «اقفل», a swipe down and the phone's back button MUST close the sheet without
  spending.

#### The «new» dot

- **FR-041**: The «الخطوط» tab MUST show the «new» dot when, since the player last opened Lines, a
  vehicle for sale became affordable, a line became unlocked, or a story trip became playable. Opening
  Lines MUST clear it, and what the player has seen MUST survive a restart. The tab's dot is M03's
  (`newDotProvider(Section.lines)`, as M08 does for the apartment), which lives in memory only, so
  this feature keeps what the player has seen.

#### Content

- **FR-042**: Each line in a pack MUST carry its **what's new** text (player text in the pack's
  locales, with no digits) and its **display fare** (integer piasters, a multiple of 50, at least 50).
  Each vehicle MUST carry its **short name** («توكتوك», «قديم»). They are new fields of the content
  schemas, and the authoring, import and export, validation, generated models, sample pack and the dev
  build's bundled pack MUST gain them.
- **FR-043**: The display fare MUST be for display only: trips keep their own fares, and neither the
  engine nor the solver reads it, so no parity fixture changes.
- **FR-044**: Every name these screens show (lines, vehicles, chapters, pieces) MUST come from the
  pack, every price from the catalog, and every other string from the app's string file (constitution
  VII).

#### Design, accessibility and copy

- **FR-045**: Each artboard (`Lines`, `LineDetails`, `BuyVehicle`) MUST have a sample, a golden at
  390×844 in RTL with both digit styles, and a layout test against `docs/design/boxes/<Artboard>.json`
  (±2 pt), as `docs/design/README.md` sets out. The states the artboards don't draw (the first session,
  a done line with no button, a locked line's details, the shortfall, an owned vehicle, a vehicle not
  for sale) MUST have goldens too. The screens MUST be built from the design's shared components,
  never from restyled widgets.
- **FR-046**: Locked looks MUST follow HANDOFF §9.1 #6 (the locked background, a 2 pt outline ring,
  `ink.2` text and a lock icon, no opacity), including the vehicle tiles and trip cells the artboards
  draw otherwise; disabled MUST follow §9.1 #5. These, and `BuyVehicle`'s reworded impact line
  («فاضل ٢٬٤٠٠ ج على النجفة» for the drawn «فاضل للنجفة ٢٬٤٠٠ ج», FR-032), are listed as expected
  differences from the design's images.
- **FR-047**: No text MUST be cut off (HANDOFF §9.1 #10): long names and reasons wrap, and their card
  or cell grows.
- **FR-048**: Every tappable MUST be at least 44×44 pt and every text at least 12 pt (constitution XI),
  at 390 and 360 pt wide and at text scales up to 1.3×.
- **FR-049**: Screen-reader labels MUST follow the artboards («توكتوك المعلم، خلصته», «ميكروباص قديم،
  عربيتك دلوقتي», «ميكروباص جديد، بـ٥٬٠٠٠ جنيه»; «المشوار ١٢، الجاي»; «اقفل»). Line cards MUST read
  «{line}، {standing}، {detail}», with a current line's «كمّل» read after its card as its own button
  (FR-019), and the price card as one («السعر ٥٬٠٠٠ جنيه، معاك ٦٬١٠٠ جنيه»). The preview MUST be
  decorative. Reading order MUST be the header, the vehicles right to left, the lines top to bottom,
  then the nav, and each sheet's focus MUST start on its title.
- **FR-050**: Counts and amounts MUST use Arabic number agreement (مشوار / مشاوير, كرسي / كراسي,
  نجمة / نجمتين / نجوم) in both digit styles.
- **FR-051**: Cards, tiles, cells and buttons MUST press down onto their lip, and the sheets MUST slide
  in and out with the design's motion; with reduced motion on, nothing moves beyond what the design
  allows.
- **FR-052**: Copy for the states the artboards don't draw MUST be proposed in the plan, in the game's
  Egyptian voice, for the owner's approval.

#### Navigation

- **FR-053**: Lines MUST be the bottom nav's second tab; a line's details and a vehicle's sheet MUST
  open over it as sheets, and the bottom nav MUST show only on the tab itself. The routes already
  exist (M03): `/lines`, `/lines/:lineId` and `/lines/vehicle/:vehicleId`, with their parameter
  checks.
- **FR-054**: A link to a line or vehicle the active pack lacks MUST land on Lines.

### Key Entities

- **Line** (content): id, name, order, stations, unlock rule (`start`, a vehicle, or another line
  complete), difficulty band, and, new here, its what's new text and display fare.
- **Vehicle** (content): id, name, order, whether it's the starter, seats, and, new here, its short
  name. Its price is in the catalog, in JENEHAT.
- **Trip** (content): id `<line_id>.<nn>`, its number in the line, kind (regular or story), line and
  vehicle. A story trip is named by one chapter.
- **Chapter** (content): order, title, goal (finish a line, own a vehicle, buy the chapter, or
  complete a room) and its story trip. Read here for story trips and the savings target.
- **Trip progress** (the economy's): best stars per trip. **Ownership** (the economy's): the vehicles,
  chapters and pieces the player owns.
- **Line standing** (derived): locked, current or done; stars earned and possible; the next trip.
- **Vehicle standing** (derived): done, current, for sale, or not for sale.
- **Savings target after a purchase** (derived): M08's savings target worked out for the state after
  the purchase, with its name and price; the goal Home's savings card names next.
- **Lines seen** (on the phone): what the player had seen when they last opened Lines, for the «new»
  dot.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: From any tab, a player reaches the pre-trip card (or, when the card is skipped, the
  trip) of the next trip of any open line in at most two taps («الخطوط», the line's «كمّل»), and of
  any trip they may replay in at most three («الخطوط», the line, the trip's cell), with the network
  off.
- **SC-002**: A player with enough savings buys the next vehicle in two taps from Lines (its tile,
  «اشتريها»), and can start a trip on the line it opens right after, with the network off.
- **SC-003**: Across the server's cases (M08's port) and the phone-only rules' tests, the phone treats
  as open no trip, line or vehicle that the server's rules refuse (0 cases), and in an end-to-end sync
  against a real server no trip start or vehicle purchase made through these screens is refused as
  not unlocked.
- **SC-003a**: Home's next trip, the pre-trip card, the result's next trip and Lines agree on every
  trip's standing in 100% of the progression tests' states (one set of rules, FR-013).
- **SC-004**: In 100% of tested double taps, retries and taps during a purchase, the price is spent
  exactly once.
- **SC-005**: For all three artboards, every tappable is within ±2 pt of its measured box, and the
  owner approves the goldens beside the design's images with no differences beyond the listed ones.
- **SC-006**: 100% of tappables are at least 44×44 pt and 100% of text at least 12 pt, at 390 and 360
  pt wide.
- **SC-007**: With a screen reader on, every vehicle, line and trip announces its name and state, and
  every purchase announces its result.
- **SC-008**: Lines, a line's details and a vehicle's sheet show their full content within half a
  second of the tap on the reference low-end device, with no loading state and no network.
- **SC-009**: In a moderated playtest, at least four of five players new to the game, after opening
  Lines once, can say what the next vehicle costs and which line it opens. (An owner check.)

## Assumptions

- **Dependencies.** All merged: M05 (the economy and its purchase path), M06 (sync and rollback), M04
  (the content source), M21 (the design's tokens, components, bottom nav and the vehicles' art), M07
  (the first session), M22 (the animated scenes) and M08 (Home, the pre-trip card, the result). From
  M08 this feature reuses, rather than rebuilds:
  - the progression rules, `lib/core/progress/domain/` (`contracts/progress-rules.md`);
  - the one start path, `startNextTrip` (`contracts/home.md`), with its fuel check, checkpoint, card
    setting and first-session handling;
  - the pre-trip card at `/home/pre-trip/:tripId` (`contracts/pre-trip-card.md`);
  - the savings target, `savingsTarget` (research R4);
  - Home's next trip, `nextTrip` (research R3), for the line the map opens on.
- **Changes to M08's merged code** (the plan says how; each keeps M08's tests passing or updates them
  with the reason):
  - the pre-trip card returns to where it was opened (FR-026), not always to Home;
  - `startNextTrip` learns a start from Lines (for M15's `StartFrom`);
  - Home's next trip, the card's opening check and the result's next trip switch to the phone's
    playable rule, FR-007 included (FR-012);
  - the rules' folder gains the phone-only rules (FR-003's vehicle order, FR-007's story trips) beside
    the port, which itself stays a one-to-one copy of the server's.
- **M07 and M22** need nothing from this feature and get no change from it: M07's first session
  reaches Lines' trips only through M08's start path, and M22 animates scenes that M10 opens.
- **Resolved here without the owner** (`/speckit-clarify` can revisit any of them):
  - **Vehicles are sold in the pack's order** (FR-003): the microbus before the new microbus, and so
    on. The server has no vehicle rule and accepts any order, so this is only stricter. The draft's
    economy makes buying the microbus before chapter 1 ends practically impossible, so no story gate
    is added.
  - **A vehicle the player has opens its sheet in an owned state** (FR-034): the design links all
    four tiles to the sheet but draws no owned version. From phase 2, the garage (M16) takes those
    taps.
  - **The grid's visible range** (FR-025) reproduces the drawn sample (next trip 12, trips 1–20 shown)
    and HANDOFF's "20-trip line: 4 rows, no hint". HANDOFF left the rule open. On 2026-10-29 the
    owner chose to also reach the last done or playable cell, because a story trip opening behind a
    finished stretch hid those trips (release draft `line_gamaa`); `LineDetailsStory`'s 6 rows is
    the expected shape.
  - **A done line has no button** (FR-027), HANDOFF's first proposal; the cells are the replays.
  - **A locked line's details** (FR-028) show the locked grid with the reason; HANDOFF doesn't draw
    them.
  - **Closing the pre-trip card returns to the line's details** (FR-026), not to Home, though the card
    lives under Home's route and pops to `/home` today; the plan picks how (HANDOFF lists both ways).
  - **Home's line card keeps opening Lines** (FR-020), not the current line's details: `C-Home`
    (HANDOFF "Line card | tap | `/lines`") and the ux-spec («يفتح الخطوط») both draw it so. M08 left
    this to M09; Lines opens with that line in view (FR-010), so the line is one tap away.
  - **The impact line's goal is M08's savings target** (FR-032), after the purchase, so the sheet and
    Home's savings card never disagree. Buying the microbus (chapter 2's goal) shows what's left for
    «الشبكة», chapter 3's.
  - **No extra confirmation** before a vehicle purchase: the sheet, with its impact line and «لسه», is
    the confirmation. The shop's undo window applies only to small BONAT purchases (M12).
  - **The line's display fare is a content field** (FR-042), not derived from the trips: a line priced
    by distance (خط السوق) has no single trip fare, and the release brief hands the field to M09.
- **Content.** Schema changes are free: `content/source/pack.json` doesn't exist yet. The sample pack
  gains the new fields (its golden checksums are regenerated), from the product spec's tables:
  خط الحي ٧ ج «تعلّم اللمّ والباقي، الحاجة، النايم، المستعجل», خط الجامعة ٨٫٥ ج «نص الأجرة، الدفع
  الجماعي، "أنا دافع!"، أبو سمّاعة», and the short names «توكتوك» and «قديم». The release draft
  (`content-core-r1`) adds them on its own branch, and the owner may rewrite the texts freely. No trip
  definition changes, so the engines and the parity fixtures stay as they are.
- **Copy.** The artboards' strings are used as given. The strings for the undrawn states, the owned
  and not-for-sale sheets, the refusal messages and the purchase announcement are proposed in the plan,
  and the owner approves them (an owner action).
- **Sample data.** Every number and name in the artboards is sample data (`docs/design/README.md`).
  The goldens use the artboards' samples through test content; the app shows the pack's.
- **HANDOFF §9.3**: none of its open questions is settled here (the delivery plan's design sources).
- **Handed to later features**:
  - **M10**: the chapter rules that story trips and the savings target read here are M08's port of the
    server's (B03 research R6), and M10 shows the same; the chapter-2 goal card opens this vehicle
    sheet; the chapter's scene after buying the microbus (`what_do_you_do`) is M10's, drawn by M22's
    scene player and opened as one of Home's arrival items (M08's `ArrivalItem`, rank 10) once the
    purchase makes it due; the shabka trip opens once the shabka is bought (FR-007), and M10's story
    screens use the same playable rule. M10 also owns the shared unlock-cases fixture M08 handed it,
    which would then cover FR-007.
  - **M11**: the between-trips checkpoint applies to starts from Lines too (FR-026), with no change
    here.
  - **M12**: the fuel sheet an empty tank opens from Lines, and the shop behind the BONAT balance.
  - **M15**: analytics for a vehicle purchase, a line opened and a replay started.
  - **M16** (phase 2): owned vehicle tiles open the garage, and the preview wears the player's
    cosmetics with «بزينتك».
- **Out of scope**: Home, the pre-trip card and the result screen (M08, merged; only the changes
  listed above); the apartment, chapters,
  scenes and story viewer (M10); the garage, upgrades and cosmetics (M16, phase 2); the «ملك الخط»
  strip (public launch); analytics (M15); any server change (the server already accepts and validates
  these purchases and trips, B03).
