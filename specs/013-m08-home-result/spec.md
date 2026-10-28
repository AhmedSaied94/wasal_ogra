# Feature Specification: Home, Pre-trip Card and Result Screen (M08)

**Feature Branch**: `013-m08-home-result`

**Created**: 2026-10-27

**Status**: Draft

**Input**: User description: "M08 Home, pre-trip card, result screen (short name: m08-home-result).
Sources: docs/ux-spec.md «الموقف», «كارت ما قبل المشوار», «شاشة النتيجة»; docs/design/HANDOFF.md §11
C-Home, HomeStates, PreTrip, Result, ShareCard, with docs/design/README.md;
docs/architecture-mobile.md §9." In `docs/delivery-plan.md` step 7, spec 013 is M08, which depends
on M02 and M05; its artboards are `C-Home`, `HomeStates`, `PreTrip`, `Result` and `ShareCard`, and
it owns none of HANDOFF §9.3's open questions. Handed over from M02 (research "Handed to later
features"): the result screen replaces the result route's placeholder and reads the trip's result
from the route, or the economy's last result; the pre-trip card's «اطلع» opens the trip route, which
charges the liter; Home replaces the playtest trip list. Handed over from M05: countdowns come from
the economy's next-liter time and the trusted clock; unlock order is checked before the economy is
asked. Handed over from M06: Home's offline banner and maintenance card move to the real Home
(`HomeStates`). Handed over from 008.5 (M21): whether «عيد المشوار» goes through the pre-trip card.
Handed over from M07 (spec 012, merged since): the result's main action and Home's next
trip follow the guided first session, and the pre-trip card shows no boosters until the tutorial is
done. Done when (step 7, with M07, M09 and M10): home and results work offline, and the integration
test from onboarding through the first 5 trips passes.

## Clarifications

### Session 2026-10-27

- Q: Once the player has finished every trip on their line, which trip should «يلا نطلع!» start, and
  which line should Home follow when several are open? → A: Stay on the line played last; when it is
  finished, move to the earliest open line that still has unfinished trips; when every open line is
  finished, replay the trip with the fewest best stars on the line played last (FR-010).
- Q: Should «عيد المشوار» on the pause and failure cards go back through the pre-trip card, or
  restart the trip straight away? → A: Straight away, as M02 built it: one tap, one liter, the same
  trip, no card (FR-034).
- Q: Can the player pass money around a muted أبو سمّاعة through the neighbouring seat, or does the
  engine's rule stay, where he must be called twice? → A: The rule stays: he must be called twice,
  and the card says so. HANDOFF §9.3 #4 is closed as "no", and the product spec's passenger table
  drops «أو تلف الفلوس حواليه» (FR-029).
- Q: When several things are due as the player arrives at Home, should Home show them one after
  another, or only one per arrival? → A: One per arrival, in a fixed order: a due story scene, the
  Name sheet, a later notification ask (M14), the morning piggy (M11); the rest wait for later
  arrivals,
  and a waiting pack switches in first (FR-022a).

### Session 2026-10-28

M07 (spec 012) and M22 (spec 012.5) are merged; this session settles what changes with them.

- Q: Now that M07 is merged, should Home's one-item-per-arrival order replace the two ways M07
  already opens things on Home (playing a due scene when Home opens, and re-asking for the name),
  or should M07 keep those? → A: Replace them: M07's due-scene opening on Home and its name re-ask
  become the first two items of Home's order, with their tests, so exactly one item opens per
  arrival everywhere (FR-022a).
- Q: Where should the notification permission ask (M14) appear: only right after the سلمى scene,
  only as one of Home's arrival items, or the first time after the scene and any later ask on Home?
  → A: The first ask follows the سلمى scene through M07's after-scene step and counts as part of
  that scene's item when the scene plays on arrival; any later ask from M14 is an arrival item in
  Home's order (FR-022a).

## User Scenarios & Testing *(mandatory)*

This feature builds the three screens a player passes through on every trip: **Home** (الموقف), the
**pre-trip card** (كارت ما قبل المشوار) and the **result screen** (النتيجة), plus the **share image**
made from a result. Until now the player reached trips through M03's placeholders and a testers'
trip list, and read the outcome on M02's placeholder.

Its users:

- **The player**, on every session: one tap from Home to the next trip, the trip's prices and
  novelties before the clock starts, and after the last stop the pay, the stars and exactly what went
  wrong, with the dream (the apartment savings) in sight on both ends.
- **The later features**, which plug into slots this feature lays out: M07 (the guided first
  session), M09 (the line card's destination, and the pre-trip card opened from a line), M10 (the
  apartment, the chapter goal and the story scene after a story trip), M11 (the interstitial, «اقبض
  ×٢» and the morning piggy), M12 (the shop and the fuel sheet), M13 (the daily row and the task
  banner), M14 (the full settings screen) and M15 (analytics).
- **The tester** on internal builds, who still needs to open any trip and see the sync status.

What the player gets from it:

- A Home that answers "what now?" at a glance: the money, BONAT and fuel with the next liter's
  countdown, the line they are on and how far along it they are, one big button to drive, and how
  close the next piece of the apartment is.
- A short briefing before each trip: what each stop costs, special fare rules, a passenger type or
  event they haven't met yet, the three star goals and their boosters. Closing it costs nothing.
- A result that celebrates the pay, shows each star's condition, lists every mistake with the
  passenger and the amount, and shows the apartment bar moving with the new money.
- Honest states: out of fuel, offline, an early chapter where the apartment is still locked.
- A picture of the result to share with friends.

### User Story 1 - One tap from Home to the next trip (Priority: P1)

The player opens the game and lands on Home. The top shows the driver's avatar, name and level, then
the JENEHAT, BONAT and fuel pills, the fuel pill with the time until the next liter. Under it, the
street scene shows the player's vehicle with its line sign, and the barker (or بلية, on the tuktuk)
calls the destination. The line card shows the line, «المشوار ١٢ من ٣٠», a progress bar and the
line's stars. The big «يلا نطلع!» button, with its «−١» fuel chip, opens the pre-trip card of the
next trip. Below it, the savings card shows the chapter, the next piece of the apartment, and how
much of its price the player has. The bottom bar switches between Home, Lines, Apartment and Shop.

**Why this priority**: Home is where every session starts and the only way into a trip for a player.
Without it the game is a list of placeholders.

**Independent Test**: On a fresh dev build with the sample pack, open Home and check every figure
against the economy and the pack: the balances, the fuel and its countdown, the line, the next trip's
number, the stars and the savings target. Tap «يلا نطلع!»: the pre-trip card of that trip opens.
Play it, return to Home, and check that the line card moved to the next trip.

**Acceptance Scenarios**:

1. **Given** a player with fuel, **When** Home shows, **Then** the header shows their name, level,
   JENEHAT, BONAT and fuel as the economy holds them, and the fuel pill counts down to the next liter
   each second, from the trusted clock.
2. **Given** a player whose tank is full, **When** Home shows, **Then** the fuel pill shows no
   countdown.
3. **Given** a player partway along a line, **When** Home shows, **Then** the line card names the
   line, the next trip's number out of the line's total, a bar of completed trips over total, and
   the stars earned out of three per trip.
4. **Given** Home, **When** the player taps «يلا نطلع!», **Then** the pre-trip card of the next trip
   opens over Home, and no fuel is spent yet.
5. **Given** Home, **When** the player taps the profile, the BONAT pill, the fuel pill, the line card
   or the savings card, **Then** Settings, the shop, the fuel sheet, Lines or the apartment opens,
   in each case the destination as it exists today (a placeholder until its feature lands).
6. **Given** the player just finished a trip, **When** they come back to Home, **Then** the balances,
   fuel, line card and savings card already show the new state, with no reload.
7. **Given** a newer content pack is waiting, **When** the player arrives at Home, **Then** it is
   switched in before Home shows its figures (M04), never mid-screen.

---

### User Story 2 - The trip's briefing before the clock starts (Priority: P1)

The pre-trip card rises over Home. Its header shows the line's name over «المشوار ١٢», with a close
button. A block lists the trip's stops in drop-off order, each with its colour, its letter, its name
and its fare, and under them one line per special rule (for example «الطلبة بنص أجرة لو ورّوا
الكارنيه»). If this trip brings a passenger type or event the player has never met, a card shows its
picture, «جديد», its name and one sentence about it. Then the three star goals, each filled if the
player already earned it on this trip, else marked «لسه»; the four boosters with how many the player
has; and the big «اطلع» button with its «−١» chip. A story trip also shows the «مشوار قصة» chip and,
above the button, its special condition («أي خناقة والمشوار يتعاد»).

**Why this priority**: The prototype playtest showed players confused by prices and new passengers
once the clock was running. The card is the fix, and it is the step between Home and every trip.

**Independent Test**: Open the card for each sample trip and compare it to the trip's data: the
stops in order with the right colours, letters and fares, the rule lines, the new card (shown the
first time a type appears, gone once the player has finished a trip with it), the star goals against
the trip's best stars, and the booster counts. Close it: no fuel spent. Tap «اطلع»: the trip opens
and the liter is charged.

**Acceptance Scenarios**:

1. **Given** the card is open, **When** the player closes it (the close button, a swipe down, the
   scrim or the system back button), **Then** it closes to Home and nothing is spent.
2. **Given** the card is open, **When** the player taps «اطلع», **Then** the trip opens in its
   place and the liter is charged as the trip starts (M02).
3. **Given** a trip with a passenger type the player has never finished a trip with, **When** the
   card opens, **Then** the new card shows that type's picture, name and one sentence; **Given** no
   such type or event, **Then** there is no new card.
4. **Given** a trip whose best result is two stars, **When** the card opens, **Then** the first two
   goals show as earned and the third shows «لسه».
5. **Given** a player who has none of a booster, **When** the card opens, **Then** that tile shows
   «×٠», and a chip offers to buy it for its catalog price in BONAT; buying it asks for confirmation
   once, spends the BONAT and raises the count, without leaving the card.
6. **Given** a story trip, **When** the card opens, **Then** it shows the «مشوار قصة» chip and the
   special-condition bar, whatever the card setting.
7. **Given** the card setting is «في الجديد بس» (new only), **When** the player taps «يلا نطلع!»
   for a regular trip with nothing new, **Then** the trip opens directly, with no card.

---

### User Story 3 - The pay, the stars and what went wrong (Priority: P1)

After the last stop, the result screen opens. Its header reads «المشوار ١٢ · خط الجامعة», with a
back button to Home. The title says «وصلنا الجامعة!». Three stars appear one by one, each with its
condition and a tick or a cross: «وصلت», «من غير خناقات», «كل باقي صح». A card quotes a line a
passenger said in this trip. The breakdown lists the fares collected, the tips, the change lost by
over-paying and the fights. If anything went wrong, a card summarises it («غلطة واحدة ضيّعت النجمة
التالتة») and opens to one line per mistake, with the passenger's picture («إديت الطالب زيادة نص
جنيه»). Then the pay in big digits («قبضت ٨٥»), the apartment card with its bar filling from the old
balance to the new, and at the bottom «مشوار تاني» with its fuel chip, and the share button.

**Why this priority**: The result is the game's reward and its teacher: the product spec's whole
memory puzzle relies on the player learning from the result what the trip kept quiet (constitution
XI: over-change stays silent in the trip and is listed here).

**Independent Test**: Replay the parity fixtures' trips (or play the sample trips) and compare every
figure on the result to the trip's recorded result: stars and conditions, fares, tips, over-paid
change, fights, each mistake, and the pay. Tap «مشوار تاني» and check it opens the next trip's card;
tap back and check Home.

**Acceptance Scenarios**:

1. **Given** a finished trip, **When** the result screen shows, **Then** every figure on it equals
   the trip's recorded result, the pay is already in the player's JENEHAT, and nothing on the screen
   is computed from anything else.
2. **Given** a trip with no mistakes, **When** the result shows, **Then** there is no mistakes card;
   **Given** mistakes, **Then** the summary names how many and which star they cost, and each mistake
   has its own line with the passenger's picture and the amount.
3. **Given** a trip that earned three stars for the first time, **When** the result shows, **Then** a
   short celebration plays and «رقم قياسي جديد» shows.
4. **Given** the pay made the next apartment piece (or the chapter goal) affordable, **When** the
   result shows, **Then** the apartment card says «تقدر تشتري {item}!» and opens the apartment.
5. **Given** the result screen, **When** the player taps «مشوار تاني» with fuel, **Then** the next
   trip's pre-trip card opens (or the trip, under the new-only setting); **When** the tank is empty,
   **Then** the fuel sheet opens instead.
6. **Given** the result screen, **When** the player taps back or the system back button, **Then**
   Home opens.
7. **Given** reduced motion is on, **When** the result shows, **Then** the stars, the pay and the bar
   appear at their final values with no bounce, burst or count-up.

---

### User Story 4 - Home tells the truth about the player's state (Priority: P2)

Home changes with the player's situation. With an empty tank, the big button turns into the
danger-coloured «البنزين خلص» with «اللتر الجاي ١٢:٣٠», and opens the fuel sheet; when a liter comes
back while the player is on Home, it turns back into «يلا نطلع!» by itself. Offline, a banner says
«انت أوفلاين، المشاوير شغالة والتقدم هيتحفظ لما النت يرجع», the scene shrinks to make room, and what
needs the network (the shop tab, the BONAT pill's link, the daily challenge, the morning piggy) is
shown disabled with «محتاج نت», while trips keep working. In the early chapters, before the
apartment opens, the savings card becomes the chapter's goal («اشتري الميكروباص», «الشقة بتتفتح في
الفصل ٤») and the scene shows the master's tuktuk with بلية.

**Why this priority**: These states are where players get stuck or confused (an empty tank, no
network). Home must say what is going on and what still works. It comes after US1 because the
default state must exist first.

**Independent Test**: With the economy set to an empty tank, check the danger button, its countdown
and its destination, then let a liter come back and see the button return. Cut the network: the
banner, the shrunken scene and the disabled items appear, and a trip still starts; restore it: they
go. Set the player in chapter 2: the goal card, the tuktuk and بلية show. Compare each to
`HomeStates`.

**Acceptance Scenarios**:

1. **Given** an empty tank, no unlimited-fuel window and no fuel lesson due (FR-011), **When** Home
   shows, **Then** the big button
   is «البنزين خلص» with the next liter's countdown, the fuel pill is in its empty style, and both open
   the fuel sheet.
2. **Given** Home with an empty tank, **When** the countdown reaches zero, **Then** the fuel pill shows
   one liter and the button returns to «يلا نطلع!» without leaving Home.
3. **Given** no network, **When** Home shows, **Then** the offline banner shows and is announced once,
   the scene card shrinks so everything still fits, the shop tab and the BONAT pill do nothing and say
   «محتاج نت», and «يلا نطلع!» still starts a trip.
4. **Given** the network returns, **When** Home is showing, **Then** the banner hides, the scene grows
   back and the disabled items work again.
5. **Given** the server answers that it is under maintenance, **When** Home shows, **Then** the
   maintenance card takes the banner's place (M06), and trips still start.
6. **Given** a player in a chapter before the apartment opens, **When** Home shows, **Then** the
   savings card shows the chapter's goal, how far the player is towards it, and «الشقة بتتفتح في الفصل
   {n}», and opens the apartment's goal view.

---

### User Story 5 - Share a result as a picture (Priority: P3)

On the result screen the player taps the share button. The game makes a square picture of the
result (the trip chip, «وصلنا الجامعة!», the stars, the passenger's quote, «قبضت ٨٥» and the game's
name) and opens the phone's share sheet with it.

**Why this priority**: Sharing brings new players for free (product spec «المشاركة والانتشار»), but
the game is complete without it.

**Independent Test**: Finish a trip, tap share, and check the picture against `ShareCard`: size,
content, both digit styles, no missing glyphs. Do it offline too.

**Acceptance Scenarios**:

1. **Given** the result screen, **When** the player taps share, **Then** the phone's share sheet opens
   with a 1080×1080 picture of this result.
2. **Given** the player doubled the pay, **When** they share, **Then** the picture shows the doubled
   amount.
3. **Given** no quote from this trip, **When** the picture is made, **Then** it has no quote card and
   the stars sit centred.
4. **Given** the Western digits setting, **When** the picture is made, **Then** its numbers use Western
   digits.

---

### User Story 6 - Testers keep their tools (Priority: P3)

On dev and staging builds, a small debug entry on Home opens the list of every trip in the active pack
(M02's playtest list) and the account and sync status card (M06). Prod builds have neither.

**Why this priority**: Home replaces the placeholder these tools lived on, and testing every later
feature needs them. Players never see them.

**Independent Test**: On a staging build, open the debug entry, start any trip from the list, and
read the sync status. On a prod build, check neither the entry nor what it opens exists.

**Acceptance Scenarios**:

1. **Given** a dev or staging build, **When** the tester opens Home's debug entry, **Then** it lists
   every trip of the active pack by line, each opening that trip, and shows the account and sync
   status card with its «sync now».
2. **Given** a prod build, **When** any screen shows, **Then** there is no debug entry, trip list or
   status card.

---

### Edge Cases

- **The line is done.** Home moves to the earliest open line with an unfinished trip; with none
  left anywhere, «يلا نطلع!» replays the trip with the fewest stars on the line played last (FR-010).
- **Several lines are open.** Home stays on the line played last until it is finished, even after a
  new vehicle opens another line; the player reaches the other lines through Lines (M09).
- **After the app restarts.** The phone remembers the trip played last only while the app runs.
  After a restart, "the line played last" is the line of the trip most recently finished for the
  first time. So replaying an older trip just before a restart doesn't move Home to that trip's
  line. Home still lands on a line with unfinished trips, or on the newest finished line
  (research R3).
- **Unlimited fuel window** (M12 sells it). «يلا نطلع!» never turns into the out-of-fuel state, its
  «−١» chip is hidden because the trip costs nothing, and the fuel pill shows the window's time left
  instead of the next-liter countdown.
- **A larger tank** (subscribers, M17): the pill shows the tank's real maximum from the economy, never
  a fixed 5.
- **No name yet** (a player who hasn't reached M07's Name card, or a restored player who never named
  the driver): Home shows M07's default name «الأسطى» until there is one, and M07's Name sheet opens
  through the arrival order (FR-022a). A long name stays on one line and ends with an ellipsis.
- **Several items due at once on arrival** (a scene that didn't play and a refused name): the first
  in FR-022a's order opens; the next waits for a later arrival.
- **An empty tank in the first session**: while M07's fuel lesson is due, Home shows «يلا نطلع!», not
  the out-of-fuel state, and the button leads to the lesson (FR-011).
- **Large balances**: the pills grow to fit and keep digit grouping; nothing is abbreviated.
- **A trip the active pack lacks or the player can't start** (a stale link, a pack switch): the card
  doesn't open, and the player stays on Home with nothing charged.
- **The tank empties while the card is open** (a sync correction): the card's button follows Home's
  out-of-fuel rule and opens the fuel sheet.
- **A trip with four stops**: the price block shows all four in one row; long names wrap to two
  lines rather than being cut.
- **Several rules and a new card and a story condition at once**: the card's body scrolls between the
  header and the button; the button stays at the bottom.
- **Booster bought offline**: BONAT spends work offline up to the local balance (mobile §11) and sync
  later; a server refusal is rolled back by M06 with its toast.
- **The result opened without the trip's result** (a link, a restart of the app on that screen): the
  screen shows what the economy kept of the last trip (its pay) and hides the stars, quote, breakdown
  and mistakes; with nothing kept, it goes to Home.
- **The app is killed on the result screen**: the next launch opens Home (or resumes an unfinished
  trip, M02). The pay was already credited.
- **No quote in this trip**: the quote card is hidden on the result and on the share image.
- **A long quote**: two lines at most, then an ellipsis; the speaker on one line.
- **Short screens** (from 360×640 pt): Home's scene card shrinks first, down to a minimum; below that,
  Home scrolls above a fixed bottom bar. Nothing is cut off or overlaps, at text scale 1.0 and 1.3.
- **A failed or abandoned trip** never reaches the result screen: the failure card and the pause card
  handle them (M02).
- **The player switches tabs while the card is open**: the card closes; nothing is spent.

## Requirements *(mandatory)*

### Functional Requirements

#### Home: layout and figures

- **FR-001**: Home MUST follow the `C-Home` artboard, top to bottom: the header (profile on the
  right; JENEHAT, BONAT and fuel pills on the left), the street scene card, the line card, «يلا
  نطلع!» with its fuel chip, the savings card, the morning piggy's slot and the bottom bar. The scene
  card MUST be the block that absorbs height changes (the offline banner, short screens).
- **FR-002**: The header MUST show the driver's avatar, name and «درجة {n}» from the player's profile,
  and the JENEHAT, BONAT and fuel balances from the economy. The JENEHAT pill MUST NOT be a link.
- **FR-003**: The fuel pill MUST show `{fuel}/{max}` with the tank's real maximum and, below it, the
  time to the next liter (mm:ss), counted from the economy's next-liter time and the trusted clock,
  never the device clock, and updated each second. The countdown MUST be hidden while the tank is
  full. Its screen-reader label MUST NOT be re-announced each second.
- **FR-004**: The scene MUST show the vehicle of the next trip (the master's tuktuk or the player's
  microbus) with its riders. A microbus MUST carry a roof sign with the line's destination and the
  barker calling it; the tuktuk MUST have no sign, and بلية calls instead. The call MUST pop on
  entering and again every few seconds, but not with reduced motion.
- **FR-005**: The line card MUST show the current line's name, «المشوار {n} من {total}» for the next
  trip, a bar of finished trips over the line's trips, and the line's stars as the sum of best stars
  over three per trip. It MUST open Lines.
- **FR-006**: «يلا نطلع!» MUST carry the fuel cost chip («−١») and open the next trip's pre-trip
  card (or the trip itself, FR-024).
- **FR-007**: From the chapter the apartment opens in (FR-019), the savings card MUST show «تحويش
  الجواز», the current chapter, the next apartment piece's name and price, the player's JENEHAT
  against it, and a bar of the two capped at full. It MUST open the apartment. When the player can
  afford the piece, the card MUST light up with «جاهزة للشرا!».
- **FR-008**: Home's links MUST be: profile → Settings; BONAT pill → the shop; fuel pill → the fuel
  sheet (HANDOFF's note: always the sheet, not the shop); line card → Lines; savings card → the
  apartment; bottom bar → the four tabs. The vehicle MUST NOT be tappable (the garage is phase 2).
  Destinations that later features build open their current placeholder until then.
- **FR-009**: The apartment tab MUST show the «جديد» dot while the next apartment piece or chapter
  goal is affordable. The other tabs' dots belong to their features.

#### Home: the next trip

- **FR-010**: Home MUST pick one **next trip**, which the line card, the scene's vehicle, «يلا نطلع!»
  and the result's «مشوار تاني» all use. It MUST be a trip the player can start under the server's
  unlock rules (B03 research R6: its line unlocked, its vehicle owned, and the trip before it on the
  line finished at least once; a story trip needs only its chapter unlocked), so a start is never
  refused as `not_unlocked`. On a line with unfinished trips, it MUST be the line's first unfinished
  trip. Home MUST follow the line of the last trip the player finished (the first line before any),
  as long as it has an unfinished trip. When it has none, Home MUST move to the open line earliest in
  the pack's order that still has one. When every open line is finished, the next trip MUST be the
  trip with the fewest best stars on the line played last, the earliest in the line's order on a tie
  (Clarifications).
- **FR-011**: While the player is in M07's guided first session, Home's next trip and the result's
  main action MUST follow M07's order (M07 FR-036, FR-037) instead of FR-010, and those trips MUST
  skip the pre-trip card. While M07's fuel lesson is due (M07 FR-033: the tank can't pay for the next
  tutorial trip), Home MUST NOT show the out-of-fuel state: «يلا نطلع!» stays and leads to the lesson.
  M08 reads all of this from M07's first session as merged (its next step after a result, its
  boosters lock and its fuel lesson before a start), starts every trip through the trip route so
  M07's redirects apply, and keeps M07's «كمّل» as the result's main action in the first session
  (M07's contract "For other features").

#### Home: states

- **FR-012**: With an empty tank, no unlimited-fuel window and no fuel lesson due (FR-011), «يلا
  نطلع!» MUST become the danger
  button «البنزين خلص» with «اللتر الجاي {mm:ss}», the fuel pill MUST take its empty style, and both
  MUST open the fuel sheet. When a liter comes back while Home shows, both MUST return to normal
  without leaving Home.
- **FR-013**: During an unlimited-fuel window, Home MUST NOT show the out-of-fuel state, MUST hide the
  «−١» chip, and the fuel pill MUST show the window's time left.
- **FR-014**: Offline, Home MUST show M06's offline banner (announced once) above the scene, shrink the
  scene card so the column still fits, and disable what needs the network, each showing «محتاج نت»
  and exposing a disabled state to screen readers, not just low opacity: the shop tab (on every tab
  screen), the BONAT pill's link, the daily challenge (when M13 adds it) and the morning piggy (when
  M11 adds it). Disabled items MUST do nothing on tap, with no dialog. Trips, the line card, the
  savings card and the fuel sheet MUST keep working.
- **FR-015**: During maintenance, Home MUST show M06's maintenance card in the banner's place, with
  the same shrinking, and trips MUST keep working (M06 FR-031, FR-035).
- **FR-016**: When the network returns, the banner MUST hide and the scene grow back with the
  artboard's motion, and the disabled items MUST work again, without leaving Home.
- **FR-017**: Before the apartment opens, the savings card MUST become the chapter-goal card: the
  goal's icon and title (for example «خلّص خط الحي», «اشتري الميكروباص»), «الفصل {n}», a lock with
  «الشقة بتتفتح في الفصل {n}», the progress towards the goal and its bar. A purchase goal (a vehicle,
  a chapter's price) MUST show the player's JENEHAT against the catalog price; a line goal MUST show
  the line's finished trips against its total. The card MUST open the apartment's goal view.
- **FR-018**: The current chapter MUST be derived the way the server reads it (B03 research R6): the
  first chapter by order whose goal isn't met, from the player's progress and ownership and the
  active pack. The goal's title and target MUST come from the chapter's content, the price from the
  catalog.
- **FR-019**: The chapter in which the apartment opens MUST be read from one place that M10 settles
  (HANDOFF §9.3 #2 is M10's). Until M10 does, it is chapter 4, as the artboards draw it.
- **FR-020**: When M10 reports a story scene waiting to be watched, the savings card MUST show
  «مشهد جديد مستنيك» instead of its bar. Until M10, it never does.

#### Home: slots for later features

- **FR-021**: Home MUST lay out, in the artboard's places, the slots that later features fill, each
  shown only when its feature supplies something and taking no space otherwise: the daily row (M13:
  the gift, the tasks with their count badge, the challenge; the event circle at public launch) and
  the morning piggy (M11 with B07). The design samples MUST fill them with fakes so the goldens and
  layout tests cover them.
- **FR-022**: Before the pre-trip card opens from Home or the result, or a trip opens directly
  (FR-024), Home MUST pass one between-trips checkpoint where M11 will show an interstitial under
  constitution IX. Until M11 it does nothing. It MUST NOT run after «اطلع».
- **FR-022a**: On each arrival at Home (as M04 defines it), once a waiting pack has switched in, Home
  MUST open at most one due item, the first in this order: a story scene due to play (M07 FR-031,
  later M10), the Name sheet (M07 FR-018), a later notification ask (M14), the morning piggy (M11).
  The first notification ask is not an item of its own: it follows the سلمى scene through M07's
  after-scene step (M07 FR-032) and counts as part of that scene's item when the scene plays on
  arrival (Clarifications, 2026-10-28). The
  others MUST wait for later arrivals (Clarifications). Nothing opens over a trip, and «يلا نطلع!»
  works as soon as the item closes. M07's own ways of opening its two on Home (playing a due scene
  as Home opens, and its name re-ask) MUST become the first two items of this order, so one rule
  covers every item (Clarifications, 2026-10-28). Items of features not built yet open nothing.

#### The pre-trip card

- **FR-023**: The pre-trip card MUST open as a sheet over Home for any trip the player can start
  (from Home, from the result's «مشوار تاني», and later from M09's line details), following the
  `PreTrip` artboard: the header (the line's name over «المشوار {n}», a close button), the stops'
  prices, the rule lines, the new card, the star goals, the boosters with the buy chip, and «اطلع»
  with «−١» pinned at the bottom. The body MUST scroll when it doesn't fit.
- **FR-024**: The card MUST follow the player's card setting: «يظهر دايمًا» (always) or «في الجديد
  بس» (only when the trip has something new). Under «في الجديد بس», a regular trip with nothing new
  MUST open directly; a story trip or a trip with something new MUST always show the card. The
  setting's default MUST come from the `pre_trip_card_mode` tunable, and the player's choice MUST
  persist on the phone. M08 MUST add the setting to the current Settings screen as a «كارت ما قبل
  المشوار» segmented row; M14 later places it in the full `Settings` artboard.
- **FR-025**: Closing the card (the close button, a swipe down past a quarter of its height or a
  fling, the scrim, the system back button, or switching tabs) MUST return to Home and spend nothing.
- **FR-026**: «اطلع» MUST open the trip route in the card's place. The liter MUST be charged as the
  trip starts (M02), not by the card. With an empty tank, the button MUST follow FR-012 instead.
- **FR-027**: The prices block MUST list the trip's stops in drop-off order, right to left, each with
  its station colour and letter by drop-off order (008.5 research R1: أ ب ج د), its name and its fare
  formatted from integer piasters («٤٫٥ ج»). Up to four stops MUST fit in one row.
- **FR-028**: Under the prices, the card MUST show one line per rule that changes this trip's fares:
  a student discount, a bag fare, and a child-free age when the trip has a passenger it applies to.
  With none, no rule line.
- **FR-029**: The new card MUST show the first passenger type or in-trip event of this trip that the
  player has not met, with its picture (the passenger's look in this trip), «جديد», its name and one
  sentence about it. A type or event counts as **met** once the player has finished a trip that has
  it, in the active pack. With nothing new, no card. Each sentence MUST describe what the engine does
  (for example, the muted passenger has to be called twice; money can't be routed around him, so no
  sentence suggests it: Clarifications).
- **FR-030**: The star goals MUST show the three conditions («وصّل كل الركاب», «من غير ولا خناقة»,
  «كل باقي يرجع صح من أول مرة»), each filled when the player's best stars on this trip include it and
  marked «لسه» otherwise.
- **FR-031**: The boosters MUST show the four boosters in the artboard's order with the player's
  count of each. Tiles MUST NOT be tappable. When at least one count is zero, a chip MUST offer the
  first booster with a zero count for its catalog price in BONAT; buying it MUST go through M02's
  confirmation card, spend the BONAT through the economy with one request id per tap (a double tap
  buys once), and update the count in place. A refusal (not enough BONAT) MUST say so in the card's
  words and change nothing.
- **FR-032**: Until the first session's tutorial is done (M07 FR-038, FR-039), the boosters and the
  buy chip MUST be hidden.
- **FR-033**: A story trip MUST show the «مشوار قصة» chip in the header and, above «اطلع», the
  special-condition bar for its rule (a fight fails it: «أي خناقة والمشوار يتعاد»). The story
  character's portrait and name are not shown: the content has no character for a trip (008.5
  research R11).

#### Restarting a trip

- **FR-034**: «عيد المشوار» on the pause and failure cards MUST keep M02's direct restart: the same
  trip starts again for a liter, without the pre-trip card (Clarifications), for every trip, story
  and tutorial trips included. M08 leaves that path as M02 built it; in the first session, M07's fuel
  lesson comes first when the tank can't pay (M07 FR-033).

#### The result screen

- **FR-035**: The result screen MUST replace the result route's placeholder for finished trips and
  follow the `Result` artboard, scrolling: the header «المشوار {n} · {line}» with a back button, the
  task slot, the title «وصلنا {last stop}!», the stars, the quote, the breakdown, the mistakes card,
  the pay, the ×2 slot, the apartment card, and «مشوار تاني» with its fuel chip beside the share
  button.
- **FR-036**: The screen MUST read the trip's result handed over by the trip. Without it, it MUST show
  what the economy kept of the last trip (its pay) and hide the stars, quote, breakdown and mistakes;
  with nothing kept, it MUST open Home. Every figure MUST be the result's own: the screen MUST NOT
  compute stars, pay or any amount, and MUST format money from integers only.
- **FR-037**: The stars MUST appear one by one, right to left, the middle one larger, each with its
  condition and a tick or a cross from the result's star flags; the group's screen-reader label MUST
  say how many stars out of three.
- **FR-038**: The quote MUST be one line a passenger said in this trip, with the speaker's look and
  name: the last thanks or tip line, or failing that the last line of a passenger who paid in full;
  with none, no quote card. The pick MUST be deterministic for a given trip as played.
- **FR-039**: The breakdown MUST show the fares collected, the tips, the change lost by over-paying
  (shown as a loss) and the number of fights.
- **FR-040**: When the trip has mistakes or losses, a card MUST summarise them (how many, and which
  star they cost) and open to one line per change mistake, with the passenger's picture and the kind
  and amount in words («إديت الطالب زيادة نص جنيه»; one wording per kind: over-change, change given to
  someone owed nothing, change never returned), plus a line each for fights, missed stops and fares
  lost, by count. With none, the card MUST be hidden. The summary MUST have wordings for one, two and
  many, and for each lost star.
- **FR-041**: The pay MUST show «قبضت» and the trip's JENEHAT earnings in large digits, counting up
  from zero, and the BONAT chip only when the task slot (M13) reports a reward.
- **FR-042**: The ×2 offer («اقبض ×٢», «+{doubled} بدل {base}») and its decline link («لأ، خد {base}
  بس») MUST be a slot that M11 fills under constitution IX; until M11, neither shows. Once the ×2 has
  been used, both MUST hide and the pay show the doubled amount.
- **FR-043**: The apartment card MUST show the same target as Home's savings card (the next piece, or
  the chapter goal before the apartment opens): its name, the player's JENEHAT after this trip against
  the price, «فاضلك {n} ج», and the bar filling from the balance before this trip's pay to the balance
  after, with this trip's gain marked. When the pay made the target affordable, it MUST say «تقدر
  تشتري {item}!». It MUST open the apartment.
- **FR-044**: «مشوار تاني» MUST carry the fuel chip, pass the between-trips checkpoint (FR-022) and
  open the next trip's card (FR-010, FR-011, FR-024); with an empty tank it MUST open the fuel sheet.
  Back and the system back button MUST open Home.
- **FR-045**: When the trip earned three stars for the first time, the screen MUST play a short
  celebration (decorations and the horn) and show «رقم قياسي جديد».
- **FR-046**: After a story trip's result, the chapter's scene MUST follow when M10 provides it
  (ux-spec «مشوار قصة»). Until M10, the result behaves as for any trip.
- **FR-047**: The task slot (M13: «مهمة خلصت: {task}» with its BONAT reward) MUST be laid out and
  hidden until M13 fills it, and MUST be announced once when it shows.

#### The share image

- **FR-048**: The share button MUST make a 1080×1080 picture following the `ShareCard` artboard (the
  trip chip, «وصلنا {last stop}!», the stars, the quote card or none, «قبضت {amount}» and the
  game's wordmark) and open the phone's share sheet with it. The amount MUST be the final one, doubled
  if the player doubled it. The digits MUST follow the player's setting, the fonts MUST be loaded
  before it is drawn, and it MUST work offline.

#### Motion, accessibility and design checks

- **FR-049**: Motion MUST follow the artboards and the design's tokens: the card's rise and fall, the
  scrim, the drag that follows the finger, the barker's pop, the banner's slide with the scene's
  resize, the button's crossfade between states, the stars one by one, the pay's count-up, the
  apartment bar's fill after the pay. With reduced motion, the pops, bursts, bounces, count-ups and
  idle loops MUST stop and values appear at once.
- **FR-050**: Every tappable MUST be at least 44×44 pt (the decline link's hit area included) and all
  text at least 12 pt, at text scale 1.0 and 1.3, from 360×640 pt up, in RTL with both digit styles
  (constitution X, XI).
- **FR-051**: Screen-reader labels and reading order MUST follow the artboards' sections, including the
  labels HANDOFF lists as missing (the JENEHAT pill, «يلا نطلع!» with its fuel cost, the piggy, «اطلع»
  saying it spends a liter, each price cell, each star row, each booster tile).
- **FR-052**: Each of the five artboards MUST have its sample, its golden in both digit styles next to
  the design's PNG, and its layout test against the measured boxes (±2 pt), as 008.5's design-checks
  contract says. `HomeStates` covers out of fuel, offline and an early chapter together, as drawn.
- **FR-053**: All player text MUST come from the app's strings or the content pack, never from code;
  numbers MUST reach the strings already formatted.

#### Internal builds

- **FR-054**: On dev and staging builds, Home MUST offer a debug entry that opens M02's list of every
  trip in the active pack, M06's account and sync status card, and M07's card for replaying the
  first session. Prod builds MUST contain neither.

#### Testing

- **FR-055**: Tests MUST cover: the next-trip rule against the unlock rules for every state of the
  sample pack; the chapter derivation against B03's rules; the "met" set; the card setting; the
  booster purchase (applied, refused, a double tap); every Home state and its transitions (fuel back,
  network back), and the first session's fuel-lesson exception; the arrival order with several items
  due; the countdown against a fake trusted clock with a device clock change; the result's
  figures against the parity fixtures' results; the share image; the internal-build entry; and the
  design checks of FR-052. An integration test MUST go from Home through a trip to the result and back
  to Home, offline.

### Key Entities

- **Next trip**: the one trip Home offers, picked by FR-010 (or by the first session, FR-011) from the
  active pack, the player's trip progress and ownership, and the last trip finished. Derived, never
  stored.
- **Current chapter and its target**: the first chapter whose goal isn't met (FR-018), and what the
  savings card tracks: before the apartment opens, the chapter's goal (a line to finish, a vehicle or
  a chapter price); after, the next apartment piece by its order in the chapter's room, with its
  catalog price. Derived.
- **Met set**: the passenger types and in-trip events found in the trips the player has finished,
  read from the active pack. Derived from trip progress, so it follows the player across a restore.
- **Pre-trip card setting**: «يظهر دايمًا» or «في الجديد بس», defaulting to the `pre_trip_card_mode`
  tunable, stored on the phone.
- **Trip briefing**: what the card shows for one trip: its stops with fares and order, its rule lines,
  the first unmet type or event, the best stars, the booster counts and prices, and its story
  condition.
- **Result summary**: the trip's recorded result (stars and their flags, fares, tips, over-paid
  change, fights, mistakes, losses, earnings) plus the quote picked from the trip, the balance before
  and after the pay, and whether the stars were a first three.
- **Share image**: a square picture made from the result summary, with the final pay.
- **Later-feature slots**: the daily row, the morning piggy, the interstitial checkpoint, the ×2
  offer, the task banner, the scene after a story trip, the first session's next step, and the items
  opened on arrival at Home in FR-022a's order: each empty until its feature fills it.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: From Home, a player starts their next trip in two taps («يلا نطلع!», «اطلع»), or one
  under «في الجديد بس» when nothing is new, and in 100% of tested states that trip is one the server
  accepts as unlocked.
- **SC-002**: Home is on screen and current within 1 s of leaving a result or switching tabs on the
  Galaxy A06, and cold start to Home stays under 3 s (M06's budget) with the real Home.
- **SC-003**: The fuel countdown on Home and on the out-of-fuel button never differs from the trusted
  clock by more than one second, including after the device clock is changed, in 100% of tests.
- **SC-004**: Across every parity fixture's playthrough, every figure on the result screen equals the
  trip's recorded result, with zero differences.
- **SC-005**: Each of the five artboards matches its design: every box within ±2 pt, goldens in both
  digit styles reviewed beside the design's PNG.
- **SC-006**: Every tappable is at least 44×44 pt and every text at least 12 pt on Home, the card and
  the result, at text scale 1.0 and 1.3, on every surface from 360×640 to 390×844, with nothing cut
  off or overlapping.
- **SC-007**: With no network, Home, the card, a trip, the result and sharing all work, and only the
  items marked «محتاج نت» are unavailable.
- **SC-008**: In a playtest, at least 8 of 10 players can say, from the result screen alone, which
  star they missed and why.
- **SC-009**: In a playtest, at least 8 of 10 players who meet a new passenger type say they knew what
  it would do from the pre-trip card.
- **SC-010**: The share sheet opens with the picture within 1 s of the tap on the Galaxy A06.
- **SC-011**: Prod builds contain no trip list, status card or debug entry; internal builds keep all
  three.

## Assumptions

- **Dependencies.** M02, M05, M06, 008.5 (M21), M07 and 012.5 (M22) are merged: the trip screen and
  its result route, the economy with fuel, the trusted clock and the last result, the sync with the
  offline and maintenance states, the design's tokens and shared components (`CurrencyPill`,
  `AppButton` with its cost chip, `AppCard`, `ProgressBar`, `Stars`, `StatusChip`, `AppSheet`,
  `BottomNav`, `DailyCircle`, `RewardedAdButton`, `OfflineBanner`, `StatusCard`, `StationTag`,
  `SpeechBubble`, `CharacterAvatar`, `VehicleSprite`; `PassengerAvatar` doesn't exist yet and is
  built here), the first session (its next step, boosters lock, fuel lesson, driver's name, Name
  sheet and scenes), and the scenes' animation (M22, which M08 only opens through M07). M09–M15 are
  not built.
- **Seams with other features.** M08 owns the screens. It wires M07's merged pieces, and leaves each
  of the others as a slot or a link that its owner fills, with nothing shown or a placeholder until
  then:
  - **M07**: the first session's next step, the fuel lesson in place of the out-of-fuel state, and
    the hidden boosters (FR-011, FR-032); the due سلمى scene and the Name sheet as arrival items
    (FR-022a). M07 is merged, so M08 wires them to its code, and turns M07's due-scene opening on
    Home and its name re-ask into arrival items (Clarifications, 2026-10-28). This departs from M07's
    hand-over, which kept the re-ask as it is; the PR says so.
  - **M09**: Lines and line details. The line card opens Lines' placeholder; M09's line details open
    this feature's card for a chosen trip.
  - **M10**: the apartment and its goal view, the chapter in which the apartment opens (FR-019), the
    waiting scene (FR-020) and the scene after a story trip (FR-046).
  - **M11**: the interstitial checkpoint (FR-022), «اقبض ×٢» (FR-042) and the morning piggy (FR-021).
  - **M12**: the shop and the fuel sheet, opened from the pills, the out-of-fuel button and «مشوار
    تاني».
  - **M13**: the daily row and the task banner (FR-021, FR-047).
  - **M14**: the full `Settings` artboard around the card setting this feature adds (FR-024).
  - **M15**: the `share` event and the other analytics.
- **Settled with the owner** (Clarifications):
  - The next trip follows the line played last, then the earliest open line with unfinished trips,
    then the least-starred trip of the line played last (FR-010).
  - «عيد المشوار» keeps M02's direct restart (FR-034), which matches M07's direct tutorial retry.
  - HANDOFF §9.3 #4 (routing money around أبو سمّاعة) is closed as "no": the engine's rule stays and
    the card says he has to be called twice (FR-029). This feature's PR drops «أو تلف الفلوس حواليه»
    from the product spec's passenger table and marks #4 settled in the delivery plan. Routing can
    only come later as a rule change (constitution III).
  - Home opens one due item per arrival, in a fixed order (FR-022a). Since M07 merged, its due-scene
    opening on Home and its name re-ask become the first two items, and the first notification ask
    stays in M07's after-scene step (Clarifications, 2026-10-28).
- **Kept consistent with M07 (spec 012):** the first session's next step and its direct tutorial
  trips (M07 FR-036, FR-037), its fuel lesson before the out-of-fuel state (M07 FR-033), its Name sheet
  and due scene on arrival at Home (M07 FR-018, FR-031), and no boosters before the tutorial is done
  (M07 FR-038).
- **Settled from the docs, not asked:**
  - Merged decisions win over HANDOFF on behaviour (`docs/design/README.md`): station letters أ ب ج د
    and colours by drop-off order (008.5 R1); the story trip shows a chip and a condition, no character
    (008.5 R11); every start costs a liter, replays included (M05); the trip, not the card, charges
    the liter (M02).
  - The BONAT spend of the buy chip works offline (mobile §11: BONAT spends are optimistic up to the
    local balance). HANDOFF's «محتاج نت» on the chip is overruled by that merged decision.
  - The buy chip buys in place through M02's confirmation card (the ux-spec's «زرار "+" يشتري
    بالبونات», and 008.5's clarification for boosters), rather than linking to the shop as drawn; it
    offers the first booster with none left, and hides when the player has some of each.
  - The fuel pill always opens the fuel sheet (HANDOFF's own note).
  - The vehicle isn't tappable in the MVP (HANDOFF's note: the garage is phase 2).
  - The barker's call is the destination said twice, from the line's last stop; no new content field.
  - Passenger-type and event names and sentences for the new card, and the mistake wordings, are app
    strings keyed by the engine's closed sets of archetypes, events and mistake kinds, not content
    (HANDOFF suggested content; the pack has no field for them and they describe engine rules).
  - The share image carries the doubled pay when the player doubled (HANDOFF's assumption), with a
    short caption and no store link until the store listing is public.
  - The driver's level comes from the account (1 by default, B02); the driver's name is M07's, with
    its default «الأسطى» until the player has one (M07's name contract).
- **No rule, engine, economy or content-schema change.** Everything M08 shows is derived from the
  active pack, the economy and the trip's result; its only economy write is the booster purchase.
- **Handed to later features** (repeated in the plan's research):
  - M09: open the pre-trip card for a chosen trip; decide whether the line card should open the
    current line's details rather than the map.
  - M10: settle FR-019's chapter, report the waiting scene and play the scene after a story trip.
  - M11: fill the checkpoint, the ×2 slot and the piggy.
  - M13: fill the daily row and the task slot.
  - M14: place the card setting in the `Settings` artboard; show the first notification ask through
    M07's after-scene step, and any later ask as an arrival item (FR-022a).
  - M15: report `share {kind: result_image}`.
- **Out of scope**: Lines and the vehicle purchase (M09); the apartment, the story viewer and the
  chapters (M10); ads (M11); the shop and the fuel sheet (M12); the daily loop (M13); the rest of
  Settings and the notification ask (M14); analytics (M15); the garage (M16); events (M19); the
  15-second share clip (M20); the tutorial and its screens (M07).
