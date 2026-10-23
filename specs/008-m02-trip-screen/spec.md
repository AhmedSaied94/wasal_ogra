# Feature Specification: Trip Screen (M02)

**Feature Branch**: `008-m02-trip-screen`

**Created**: 2026-10-22

**Status**: Draft

**Input**: User description: "feat 0008". Feature 008 in `docs/delivery-plan.md` is M02, step 5: "Trip
screen: Flame scene, Rive characters, HUD, dashboard, overlays". It depends on M01 (merged in #5),
whose engine it drives, and M04 (merged in #7), whose content source gives it trips, lines and speech
pools. It also builds on M03 (merged in #1), whose shell, theme tokens, trip route and pause overlay it
replaces or extends, and on M05 (merged in #8), through which it starts trips, records results, and
uses and buys boosters and revives. Sources: docs/ux-spec.md «شاشة المشوار» and «أثناء المشوار:
الأحداث والنوافذ» (with «النظام البصري», «الأحجام الدنيا», «الحالات العامة» and «الصعوبة والمساعدة حسب
الخط»); docs/architecture-mobile.md §8 (with §3, §6, §7, §9, §10, §14 and §19); docs/product-spec.md
«ميكانيكيات المشوار», «أنواع الركاب» and «الأحداث والمواقف». Resolve: mobile §24.6 (the Rive runtime and
its license) and the UI side of mobile §24.4 (resuming a killed trip). Handed over from M01 (research
R9, R10, R12 and "Handed to later features"): build `TripParams` from the tunables, save the replay
record on every accepted command and pause, offer a killed trip back, show hints by
`trip_hints_mode_<line_id>`, hide who has paid except during `ledger_peek`, decide whether choices
pause the trip, and hide the revive offer at the 1,200-command cap. Handed over from M04: read trips
and speech pools through the content source, and record the content version a trip started with.
Handed over from M05: start, finish, revive and use boosters through the economy with one request id
per intent, charge a revive only when the engine reports the trip revivable and below the cap, and
on a launch with an unfinished start, rebuild it or record it abandoned. Done when: a trip from the
bundled pack plays from start to finish with no network, the minimum sizes pass in RTL goldens, and
the scene holds at least 45 fps on the Galaxy A06. Milestone: the first internal test of "is the
puzzle fun?".

## Clarifications

### Session 2026-10-22

- Q: What art and sound should M02 ship with? → A: Stand-ins for the cabin, money, effects and
  sound, plus one real Rive character, driven by every state (mood, talking, asleep, headphones,
  getting off) and used for every skin until more art arrives, so the Rive setup and the 45 fps
  budget are proven with real animation now. The owner supplies that one `.riv` file before the merge
  (FR-045, SC-003).
- Q: While a passenger's choice waits for the player's answer, should the trip's clock keep running?
  → A: Only the payment dispute stops the clock: it is a window («مين اللي دفع؟» with both faces),
  and the trip stays paused until the player picks one. The claim («ماشي» / «لأ، ما دفعتش!») and the
  change request («فكّله» / «معلش») are answered next to the passenger while the trip keeps running. One
  left open until its passenger gets off closes by the engine's rules: the claim as accepted, the
  change request as declined (FR-012, FR-032).
- Q: After the phone kills the game mid-trip, what should the player see when they open the game
  again? → A: The launch goes straight back into the trip, rebuilt and paused, with the pause card:
  «كمّل المشوار», «عيد المشوار» (one liter) or «ارجع الموقف» (records it abandoned). Home is skipped
  for that launch. This is the UI side of mobile §24.4 (FR-014).

## User Scenarios & Testing *(mandatory)*

The people involved:

- **The player**, holding the phone upright in one hand, often in transit and offline. They collect
  fares, hand back exact change before each passenger's stop, and remember who has paid. They need
  to see every face, read every line, and reach every control with one thumb.
- **The internal playtester** (the owner and a few testers), who plays the sample and promoted packs
  on dev and staging builds to answer "is the puzzle fun?" before the game loop around the trip
  exists.
- **The features around the trip.** The engine (M01) decides everything; this screen only shows its
  state and sends it the player's commands. The economy (M05) charges the liter, records the result
  and holds the boosters. Home, the pre-trip card and the result screen (M08), the tutorial (M07), ads
  (M11), the shop and the fuel sheet (M12), and analytics (M15) come later and plug into what this
  feature builds.

### User Story 1 - Play a trip from start to finish, offline (Priority: P1)

A player opens a trip on the old microbus. The screen shows a thin top bar with the line, the
reputation meter and the station strip; the cabin seen from the front, with every passenger's face
and their station's color and letter on their shoulder; and the dashboard under the thumb, with the
hand, the change drawer and «آخر كلام». Passengers pay by themselves, and their notes travel seat by
seat to the driver and land in the drawer. The player taps coins in the drawer into the hand, taps a
passenger, and the change travels back down the chain. At each station the passengers for it get off,
thanked if their change was right, angry if not. After the last station the result is recorded and
the player moves on to the result screen. None of it needs a connection.

**Why this priority**: This is the game. Every later feature (the tutorial, Home, the result screen,
ads, the daily challenge) wraps around this loop, and the delivery plan's milestone is to find out
whether it is fun.

**Independent Test**: In airplane mode, open each trip of the sample pack, play it to the end with
the on-screen controls, and check that the result recorded matches what the engine computed. In an
automated test, play each parity fixture the controls can produce (SC-002), including the solver's
3-star runs of the sample trips, through the screen's controls and compare the outcome with its
expected result.

**Acceptance Scenarios**:

1. **Given** a trip in the active pack and at least one liter, **When** the trip screen opens it,
   **Then** the trip's start is recorded with the economy (one liter spent) before the clock starts,
   and the screen shows the top bar, the scene and the dashboard in RTL.
2. **Given** a running trip, **When** a passenger pays, **Then** the note appears as a money token
   with its amount, travels toward the driver one seat at a time, and arrives in the drawer, where
   the denomination's count goes up.
3. **Given** coins in the drawer, **When** the player taps a denomination, **Then** one piece moves
   into the hand with a coin sound, and the hand's total updates in large digits. **When** the
   player taps the hand, **Then** everything in it goes back to the drawer.
4. **Given** money in the hand, **When** the player taps a passenger (or drags the hand onto them),
   **Then** that passenger lights up for half a second, the driver's hand throws, and the change
   travels down the chain to them. An «رجّع» button shows for the undo window
   (`trip_undo_window_ms`) and takes the send back when tapped.
5. **Given** a running trip, **When** the next station comes within `trip_station_warning_ms`,
   **Then** its countdown on the station strip turns orange, grows and pulses, and a passenger who
   is still owed change for it says so. (Their station patch also pulses: US3, scenario 2.)
6. **Given** a station is reached, **When** its passengers get off, **Then** each stands up and
   leaves upward with the outcome the engine reports (thanked, fight, missed stop, left unpaid), and
   their seat stays empty. A fight shakes the scene, vibrates the phone, and shows a dark orange
   bubble.
7. **Given** the last station is reached, **When** the engine reports the trip finished, **Then**
   the result is recorded with the economy and the player is taken to the result screen with that
   result.
8. **Given** no network at any point, **When** the player plays a trip, **Then** nothing in the trip
   waits for, asks for or reports a missing connection.

---

### User Story 2 - A trip survives every interruption (Priority: P1)

A call comes in, the player switches apps, or the phone kills the game mid-trip. The trip stops
where it was. When the player comes back, it continues from the moment it left the screen, with the
same money in the same hands, and no liter is spent again. (A crash, which gives no warning, rewinds
it to its last accepted command: FR-006.) The pause button and the phone's back button
open the pause card, and nothing leaves a trip by accident.

**Why this priority**: The economy refuses a new trip while one is unfinished, so a killed trip that
isn't handled blocks the game. M01 decided that a killed trip resumes exactly (mobile §24.4), and
the player must never pay a liter for the phone's behavior.

**Independent Test**: At random moments of each sample trip, send the app to the background, bring
it back, and kill it from the background and relaunch it. Each time, check that the clock,
reputation, drawer, hand, passengers and money in transit are exactly as they were when it left the
screen, and that the fuel didn't change. Kill it in the foreground too (a crash): it comes back as it
was at its last accepted command.

**Acceptance Scenarios**:

1. **Given** a running trip, **When** the app leaves the foreground (another app, a call, the lock
   screen), **Then** the trip pauses at once, and when the app returns it shows the pause card.
2. **Given** a running trip, **When** the player taps the pause button or the phone's back button,
   **Then** the clock stops, the scene darkens, and the pause card shows «كمّل المشوار», «عيد المشوار»
   with its "−١ بنزين" cost, «ارجع الموقف», and quick switches for sound and vibration.
3. **Given** the pause card, **When** the player taps «كمّل المشوار», **Then** the trip continues
   from the same moment.
4. **Given** the pause card, **When** the player taps «ارجع الموقف», **Then** the trip is recorded
   as abandoned with the economy (no pay, the liter not returned) and the player lands on Home.
5. **Given** the pause card, **When** the player taps «عيد المشوار», **Then** the trip is recorded as
   abandoned, a new start of the same trip is recorded (one more liter), and the trip begins again
   from its first moment.
6. **Given** a trip in progress, **When** the app is killed and launched again, **Then** the launch
   goes straight to that trip, rebuilt at its last saved moment and paused, with the pause card
   showing. The last saved moment is the pause made when the app left the foreground, or, after a
   crash, the last accepted command (FR-006). No new start is recorded and no liter spent.
7. **Given** an unfinished trip whose saved record is missing or can't be rebuilt, **When** the app
   launches, **Then** that trip is recorded as abandoned, and the player can start trips again.

---

### User Story 3 - Every passenger type and choice of the MVP lines (Priority: P2)

On خط الحي and خط الجامعة, the player meets the sleeper who blocks the chain until woken, the boy
in headphones who has to be called twice, the slow hajja, the man in a hurry, the effendi with the
200-pound note, the student on half fare, the group payer who pays for three, the chatty one who
slows his row, the honest passenger who hands back extra change, the regular who tips, and the
false claimer who says «أنا دافع!» when he hasn't. Each one looks different, behaves as the engine
says, and asks the player to remember rather than read.

**Why this priority**: The first trip (two regular passengers) plays without them, but the puzzle is
in the types: no trip past the first few is playable without them. Every archetype the engine
supports appears in the sample or the MVP lines.

**Independent Test**: For each archetype in `content/engine/capabilities.json`, play a trip (a
sample trip or a test trip) where it appears, and check that its look, its states and its choices
match the ux-spec and that the commands sent match the player's taps.

**Acceptance Scenarios**:

1. **Given** a passenger of any archetype, **When** they are on board, **Then** their face, clothes
   and accessory tell their type apart (the student's cap, the hajja's glasses, the headphones, the
   effendi's tie), and their station's color and letter are on their shoulder.
2. **Given** a passenger, **When** their state changes, **Then** the scene shows it as the ux-spec's
   table says: smiling, talking with a bubble, frowning with sweat that grows as patience runs out,
   asleep with "z z", headphones with music marks, pulsing patch near their stop, fighting, getting
   off, boarding through the door.
3. **Given** a sleeping or headphone-wearing passenger in the chain, **When** money reaches them,
   **Then** the token stops, turns orange and shows "؟" until the passenger is woken or called.
4. **Given** an empty hand, **When** the player taps a passenger, **Then** the tap does what the
   engine decides: ask for the fare, wake a sleeper, call someone in headphones (twice), or, for
   someone who has paid, open «أنا دافع!» with two answers, «ماشي» and «لأ، ما دفعتش!».
5. **Given** a false claimer says «أنا دافع!», **When** the player answers, **Then** «لأ، ما دفعتش!»
   catches him or accuses an honest payer, and «ماشي» lets him ride free, exactly as the engine
   rules. The trip keeps running while the two answers wait under him; left unanswered until he gets
   off, the claim counts as accepted.
6. **Given** a group payer, **When** they pay for the group, **Then** the bubble and «آخر كلام» say
   so («خد ٥٠ عن تلاتة»), and change sent to any member of the group goes to the payer.
7. **Given** any moment of a trip, **When** the screen shows the passengers, **Then** it never shows
   who has paid and who hasn't, except while that passenger speaks, in the «آخر كلام» lines, during
   a ledger peek, and in a hint that the line's hint mode allows (ux-spec «اللاعب يفتكر، والشاشة ما
   تفضحش»).

---

### User Story 4 - The in-trip events (Priority: P2)

A bump knocks the notes in transit to the floor and the player has three seconds to tap each one
back. Traffic stops cars in the windows and slows the countdown while faces frown faster. The open
road rushes. The fare goes up mid-line and an orange banner says so. A passenger shouts «نزّلني هنا».
Two passengers each say the other didn't pay. A passenger holds out a big note and asks for change.
Someone waves from the roadside and climbs in.

**Why this priority**: Events keep the same line from repeating (product-spec «الأحداث والمواقف»).
The sample's second trips already use bump, traffic and payment disputes, and all eight are in the
engine.

**Independent Test**: For each of the eight `event_id`s, play a trip where it fires (a sample trip
or a test trip), and check what the scene shows and what the player can do against the ux-spec's
events table.

**Acceptance Scenarios**:

1. **Given** a `bump`, **When** it fires, **Then** the scene shakes (unless reduced motion is on),
   money in transit drops to the floor and glints, and tapping a dropped note within
   `trip_bump_collect_ms` collects it; after that, it is lost.
2. **Given** `traffic` or `open_road`, **When** it runs, **Then** the windows show stopped cars or a
   rushing street, and the station countdown follows the schedule the engine shifted.
3. **Given** a `fare_increase`, **When** it fires, **Then** an orange banner slides down with the old
   and new fare, and the prices on the station strip change with a movement.
4. **Given** a `drop_me_here`, **When** it fires, **Then** the passenger says the line and their
   station patch turns into a pulsing «هنا» star, with its own short deadline.
5. **Given** a `payment_dispute`, **When** it fires, **Then** both passengers show facing bubbles,
   the trip pauses, and the player chooses «مين اللي دفع؟» between their two faces; the trip resumes
   once they choose.
6. **Given** a `change_request`, **When** it fires, **Then** the passenger holds out the note with a
   bubble and two answers, «فكّله» and «معلش», while the trip keeps running. Left unanswered until the
   passenger gets off, it counts as declined, with its reputation penalty.
7. **Given** a `roadside_pickup`, **When** it fires, **Then** someone waves in the window, then
   boards through the door and sits in a free seat.

---

### User Story 5 - Help when the player is stuck (Priority: P2)

Out of small coins, the player taps «حد معاه فكة؟», picks a 50 from the drawer, and a passenger
breaks it a moment later. A sleeper is about to miss their stop, so the player uses «صحّي النايم».
They lost track of who paid, so they open «الدفتر» and see paid and unpaid badges for a few seconds.
The next station is too close, so they use «زحمة» for ten more seconds. Out of change bags, they buy
one for BONAT without leaving the trip. On خط الحي, بلية points at the passenger who is still owed
change as their stop comes near.

**Why this priority**: The helpers turn a lost trip into a recoverable one, and the BONAT and ad
offers attached to them are part of the economy (product-spec «المساعدات»). The core loop works
without them, so they are P2.

**Independent Test**: With a test economy holding some of each booster and some BONAT, use each
booster in a trip, run out of one and buy it, request a break up to the trip's limit, and check the
engine's commands, the economy's inventory and balances, and what the scene shows.

**Acceptance Scenarios**:

1. **Given** the trip allows break requests, **When** the player taps «حد معاه فكة؟», **Then** the
   drawer's notes of at least `trip_break_min_piasters` light up; picking one sends it, and it comes
   back broken after `trip_break_delay_ms`. The button shows how many requests are left and is
   disabled at 0.
2. **Given** the player holds a booster, **When** they tap it, **Then** the engine applies it, and
   only once the engine accepts it is the use recorded with the economy and the count lowered by one.
3. **Given** a ledger peek, **When** it runs, **Then** a «دافع» or «لسه» badge shows under every
   passenger for as long as the engine's peek lasts.
4. **Given** none of a booster is left, **When** the player taps it, **Then** the trip pauses and a
   small card shows its catalog price in BONAT and the balance; buying charges the economy and then
   uses it, and cancelling resumes the trip. With too little BONAT, the card says how much is
   missing and offers nothing else.
5. **Given** `traffic_jam` has been used `booster_traffic_jam_max_per_trip` times, **When** the
   dashboard shows it, **Then** it is disabled.
6. **Given** the line's hint mode (`trip_hints_mode_<line_id>`), **When** it is `always`, **Then**
   بلية's head appears in a lower corner with one line and a pointing hand on the passenger who is
   still owed change as their stop nears. **When** it is `first_time`, **Then** بلية explains each
   passenger type once, the first time the player meets it. **When** it is `off`, **Then** no hint
   shows.

---

### User Story 6 - Failing, and getting back in (Priority: P2)

The player loses too much reputation and the trip fails: the clock stops and every face frowns. A
card says «المشوار باظ», explains in one line what lost the reputation («خناقتين وراكب فاتته محطته»),
and offers to make it up with the passengers for BONAT and continue from the same moment, to restart
for a liter, or to go back to Home.

**Why this priority**: Failing is common on a puzzle the player is still learning, and the revive is
a BONAT sink and an ad placement (glossary §3.3, §3.4). The trip is complete without it, but not fair.

**Independent Test**: With a test economy, fail a trip, revive it with BONAT, fail it again (no
second revive), restart it, and fail another trip to go home. Check the economy's balances, the
recorded results and the engine's state after each.

**Acceptance Scenarios**:

1. **Given** reputation reaches 0 (or any fight in a `no_fights_required` trip), **When** the engine
   reports the trip failed, **Then** the clock stops, every passenger frowns, and the failure card
   shows with a line naming the causes the engine recorded.
2. **Given** the trip is revivable, has never been revived, and is below the 1,200-command cap,
   **When** the card shows, **Then** it offers «صالح بـ… بون» at the catalog price. **When** the player
   takes it, **Then** the economy charges the revive first, and only then does the engine revive the
   trip at `rep_revive_to` and continue from the same moment.
3. **Given** the trip isn't revivable (already revived, a fight in a `no_fights_required` trip, or at
   the command cap), **When** the card shows, **Then** no revive is offered.
4. **Given** the failure card, **When** the player taps «عيد المشوار» or «ارجع الموقف», **Then** the
   trip's result is recorded as failed, and the player restarts (one more liter) or lands on Home.
5. **Given** a story trip (`kind: story`) with `no_fights_required`, **When** it runs, **Then** its
   special condition shows under the station strip for the whole trip («أي خناقة والمشوار يتعاد»).

---

### User Story 7 - Playtest tools on internal builds (Priority: P3)

The owner hands a staging build to five testers. On Home's placeholder, they see every trip of the
active pack and can start any of them. A small debug panel, shown only on dev and staging builds,
gives the trip id, seed and clock and the engine's current state for bug reports. After each trip the
result screen's placeholder shows the stars, the three star conditions and the pay.

**Why this priority**: Home, the pre-trip card and the result screen are M08's, so without this the
milestone's playtest can play only one trip and can't read its outcome. It is P3 because players
never see it.

**Independent Test**: On a dev build, open each trip from the list, toggle the debug panel, finish a
trip and read its summary. On a prod build, check that neither the list nor the panel exists.

**Acceptance Scenarios**:

1. **Given** a dev or staging build, **When** Home's placeholder shows, **Then** it lists every trip
   of the active pack by line, and tapping one opens it.
2. **Given** a dev or staging build, **When** the player turns on the debug panel, **Then** it shows
   the trip id, its revision, seed, the engine's clock and status, and can copy the replay record.
3. **Given** a prod build, **When** any screen shows, **Then** neither the trip list nor the debug
   panel exists.
4. **Given** a finished, failed or abandoned trip, **When** the result route opens before M08 has
   built it, **Then** its placeholder shows the outcome, the stars with their three conditions, and
   the pay.

---

### Edge Cases

- **The trip opens with an empty tank.** The economy refuses the start. The trip screen shows the
  empty-fuel state («البنزين خلص») with the time of the next liter, a way to the fuel sheet (M12's
  placeholder until then), and back to Home. The engine never starts.
- **The trip opens while another trip is unfinished** (a deep link, a stale placeholder link). The
  economy refuses the start, and the trip screen opens the unfinished trip instead of the one asked
  for, paused with the pause card, the same way as after a kill (FR-014).
- **«عيد المشوار» with no fuel and no unlimited-fuel window.** The button shows that the tank is empty
  and does nothing, so the current trip isn't abandoned for a restart that can't start. Continue and
  Home stay available.
- **The app is killed while the failure card shows.** The trip is rebuilt failed and the card shows
  again. Killed after the last station but before the result was recorded: the trip is rebuilt
  finished and its result is recorded then.
- **The app crashes, or is force-stopped while in the foreground.** No pause ran first, so the trip
  rebuilds at its last accepted command, not at the moment of the crash (FR-006). Every other way of
  closing the app (the home button, the recent-apps list, a call, the system killing it in the
  background) pauses first and resumes at that exact moment.
- **The app is killed between the economy's charge and the engine's command** (a revive or a booster
  purchase). The economy's request id makes the retry charge once. A revive paid but not applied is
  applied on the rebuild; a booster bought but not used stays in the inventory.
- **Recording a result, a booster use or a start fails** (full storage). The screen shows a neutral
  retry message, and the retry uses the same request id. A booster the engine already applied is
  recorded on retry, so the inventory and the engine never disagree.
- **A newer content pack becomes active at the next launch** while a trip is unfinished. The trip
  rebuilds from its own saved definition, so its rules don't change. Station names and speech come
  from the active pack, and a line or key it no longer has falls back to a neutral label rather than
  failing.
- **More than two passengers speak at once.** Two bubbles show; the rest wait their turn, each for at
  least the line's `trip_bubble_min_ms`. A passenger at the screen's edge gets a bubble moved inside
  the scene, its tail still pointing at them.
- **Two payment disputes open in the same step.** They are asked one at a time, in the engine's
  order, and the trip resumes only after the last answer. (No dispute can open under the pause card:
  a paused trip doesn't advance.)
- **A claim or change request is still open when another one opens.** Each keeps its own two answers
  next to its passenger, and they don't cover each other or the drawer.
- **A tap lands while a choice is open, or on a passenger who just got off.** The engine rejects what
  it doesn't accept, and the screen shows nothing for it beyond its normal feedback: no crash, no
  error card.
- **Very fast taps** (a double tap on a coin). Each tap is one command; two taps move two pieces, as
  the player asked.
- **The trip reaches the 1,200-command cap.** Every control except pause stops responding with a
  short notice, the revive is hidden, and the player can still leave or let the trip run to its end.
- **The phone's text size is set large.** Text in the HUD and dashboard grows up to the point where
  the layout still holds, and never below the minimum sizes.
- **A screen shorter or narrower than the reference 390×844.** The top bar and the dashboard keep
  their sizes, and the scene takes what is left. Down to 744 pt of height (360×744 is the smallest
  checked) the scene keeps at least 420 pt and every minimum size holds. Below that (such as 360×640)
  the scene shrinks and the faces with it, while touch targets, tokens, bubbles and text keep their
  minimums. That is a time-boxed exception to constitution XI that M07 removes (plan.md, Complexity
  Tracking). Goldens check the reference, the A06's 360×800 and 360×744.
- **Reduced motion is on.** No shake, and bubbles appear without a pop. Everything else, including
  money movement, still shows.
- **Sound or vibration is off** (from the pause card's switches or the phone's silent mode). Every
  key event still reaches the player through the other channels: what the scene shows and the words
  in a bubble or «آخر كلام».
- **A skin with no art yet** (a pack newer than the app). The passenger is drawn with a fallback look
  for their archetype; the trip still plays.
- **The device is slow** (a frame takes longer than a logic step). The engine catches up in fixed
  steps, so the outcome never depends on the frame rate; only the drawing skips frames.

## Requirements *(mandatory)*

### Functional Requirements

#### Driving the engine

- **FR-001**: The trip screen MUST drive one trip engine at a time, through one trip controller that
  owns it. Widgets and scene components send commands to the controller and render its state and
  events; they never change trip state themselves (constitution I).
- **FR-002**: Nothing in this feature may decide a trip rule: who pays, what a passenger does, where
  money goes, reputation, stars or pay. When the screen needs to know, it asks the engine's state or
  reacts to its events.
- **FR-003**: The controller MUST advance the engine with its fixed 33 ms logic step from the real
  time that has passed, catching up in whole steps when a frame is late. Rendering may interpolate
  between steps, but the engine's outcome MUST NOT depend on the frame rate.
- **FR-004**: The trip's parameters MUST be built from the current tunables for the trip's line when
  the trip starts, and kept with the trip, so a tunable change mid-trip or before a resume doesn't
  change it (constitution VIII).
- **FR-005**: The trip MUST be read from the active content pack through the content source,
  together with its line (names and station names) and the speech pools. The trip keeps the
  definition it started with until it ends (M04 hand-over).
- **FR-006**: The controller MUST save the trip's replay record durably after every accepted command
  and every pause, so a kill at any moment loses at most the time since the last command or pause
  (M01 research R10).

#### Starting and ending a trip

- **FR-007**: Opening a trip MUST first record its start with the economy, and start the engine only
  when the start is applied. A refused start (`no_fuel`, `trip_unfinished`, `unknown_trip`) shows the
  matching state (Edge Cases) and never starts the engine.
- **FR-008**: Each player intent (a start, a result, a booster purchase, a booster use, a revive)
  MUST hold one economy request id, reused on every retry until the outcome is applied or refused
  (constitution VI).
- **FR-009**: When the engine reports the trip finished, the screen MUST record its result with the
  economy, then go to the result route with that result.
- **FR-010**: «ارجع الموقف» from the pause card MUST abandon the trip in the engine and record the
  abandoned result. From the failure card it MUST record the failed result.
- **FR-011**: «عيد المشوار» MUST record the current trip's result (abandoned from the pause card, failed
  from the failure card), then record a new start of the same trip, which costs a liter, and start
  the engine afresh. It MUST be unavailable when the tank is empty and no unlimited-fuel window runs.

#### Interruptions and resuming

- **FR-012**: The trip MUST pause at once when the app leaves the foreground, when the pause button
  or the phone's back button is pressed, while any card or sheet covers the trip, and while a payment
  dispute waits for its answer (FR-032). Back on a running trip never leaves it (M03 FR-020).
- **FR-013**: The pause card (ux-spec «نافذة الإيقاف») MUST offer «كمّل المشوار», «عيد المشوار» with its
  liter cost, «ارجع الموقف», and switches for sound and vibration that take effect immediately and are
  remembered.
- **FR-014**: At launch, when the economy reports an unfinished trip, the app MUST rebuild it from its
  saved replay record, paused, without a new start and without spending fuel, and the launch MUST go
  straight to the trip screen with the pause card showing, skipping Home (Clarifications; the UI side
  of mobile §24.4). Its «ارجع الموقف» records the trip abandoned, and its «عيد المشوار» restarts it
  as FR-011 says.
- **FR-015**: A record that is missing or that the engine refuses to rebuild MUST be recorded as
  abandoned, so the player is never blocked from starting trips.
- **FR-016**: A rebuilt trip that is failed MUST show the failure card again, and one that is finished
  MUST record its result and go to the result route.

#### Screen layout

- **FR-017**: The trip screen MUST have three fixed areas in portrait (ux-spec «شاشة المشوار»): a top
  bar of about 110 pt, the scene filling the rest, and the dashboard of about 230 pt overlapping the
  scene's bottom by 16 pt. The scene is at least 420 pt on every screen at least 744 pt tall,
  including the reference frame (390×844) and the Galaxy A06 (360×800). The trip hides the system
  bars while it runs.
- **FR-018**: Every control the player plays with during a trip MUST sit in the bottom third of the
  screen (constitution XI). The exceptions are the ones XI names:
  - what the scene shows: the passengers, the dropped money, and the choice answers next to their
    passenger;
  - the controls that stop play: the pause button in the top bar (FR-019) and, on internal builds
    only, the debug icon (FR-051).
- **FR-019**: The top bar MUST show, right to left: the pause button (a 44 pt white circle), the
  line's name and the trip's number, and the reputation meter, blue and orange below 40%. Under them,
  the station strip shows the depot, then each alighting station in order with its color, letter,
  name and price, the vehicle moving along it, and the next station's countdown, which turns orange,
  grows and pulses within `trip_station_warning_ms`. A line rule (the student's half fare) shows a
  small icon next to the price.
- **FR-020**: Station colors MUST be given by alighting order (at most 4 per trip), from the theme's
  station tokens, and every station MUST show its letter (أ، ب، ج، د by the same order) everywhere its
  color appears.

#### The scene

- **FR-021**: The scene MUST lay out the trip's seats as the camera sees them from the front of the
  vehicle: the row right behind the driver at the bottom and largest, rows further back smaller and
  higher, and the front seat bottom right. The MVP vehicles are the tuktuk (one near row, 3 seats)
  and the old microbus (3 rows of 3 plus the front seat, 10 seats).
- **FR-022**: Each passenger MUST show a face and shoulders whose clothes and accessory come from
  their `skin`, with their station patch on the shoulder, and every state in the ux-spec's passenger
  table. A `skin` with no art MUST fall back to a look for the passenger's archetype.
- **FR-023**: Money in transit MUST show as a token with its amount in large digits: green for a fare
  moving forward, blue for change moving back, orange with "؟" while blocked. Each token's position
  follows the engine's hop progress.
- **FR-024**: The driver's hand MUST rise from the bottom of the scene holding what is in the hand,
  and move toward the passenger when the player sends.
- **FR-025**: The side windows MUST show the street moving, the next station's sign approaching,
  stopped cars during traffic, and a faster street on the open road. A bump shakes the scene.
- **FR-026**: Speech bubbles MUST be widgets drawn over the scene, never text drawn in the scene
  (constitution, architecture boundaries). At most two show at once and the rest queue; each stays
  for at least the line's `trip_bubble_min_ms`; each stays inside the scene with its tail toward the
  speaker. Their style follows the ux-spec: white, light orange for a warning, dark orange for a
  fight, light blue for thanks.
- **FR-027**: Each line a passenger says MUST come from the active pack's speech pool for the engine's
  `speech_key` and seeded `variant`, with `{amount}` formatted as pounds in the player's digit style
  and `{station}` as the station's name. No Arabic text may be in code (constitution VII, XII).

#### The dashboard

- **FR-028**: The dashboard MUST show, top to bottom (ux-spec «التابلوه»): the hand («في إيدك») with
  its pieces and its total in 20 pt digits next to the yellow «حد معاه فكة؟» button with its remaining
  count; the drawer, 8 slots in two rows (نص، ١، ٥، ١٠ then ٢٠، ٥٠، ١٠٠، ٢٠٠), each with its coin or
  note and count, an empty slot dashed and faded; the four boosters with their counts, or their BONAT
  price when none is left; and «آخر كلام», the last two lines said or done.
- **FR-029**: The interactions MUST follow the ux-spec's table: a tap on a drawer slot picks one
  piece; a tap on the hand returns it all; a tap or a drag from the hand onto a passenger sends it;
  «رجّع» undoes the last send while the engine allows it; a tap on a passenger with an empty hand is
  the engine's context tap.
- **FR-030**: «آخر كلام» MUST show the last two lines of speech and money events in words, each line
  replacing the oldest, so memory still matters.

#### Choices

- **FR-031**: A claim («أنا دافع!») MUST show «ماشي» and «لأ، ما دفعتش!» under the passenger; a payment
  dispute MUST ask «مين اللي دفع؟» with both passengers' faces; a change request MUST show «فكّله» and
  «معلش» next to the passenger. Each answer is sent as the engine's matching command.
- **FR-032**: Only a payment dispute MUST stop the clock: the trip pauses when the dispute opens and
  resumes once the player answers it (Clarifications). A claim and a change request MUST be answered
  next to the passenger while the trip keeps running. One the player leaves open closes by the
  engine's rules when its passenger gets off (M01 RULES.md §9.3): a claim as accepted, a change
  request as declined with its penalty. The screen shows that outcome like any other («آخر كلام» and
  the passenger's reaction).

#### Who has paid

- **FR-033**: The screen MUST NOT show whether a passenger has paid, still owes, or is owed change,
  except: in the bubble while that passenger speaks, in «آخر كلام», as a money token visibly moving,
  in the ledger-peek badges while the peek lasts, in the near-stop warning the engine raises, in a
  passenger's growing impatience (the ux-spec's «صبره بيخلص» look, which the engine runs only while
  change is owed), and in a hint the line's hint mode allows. This includes the screen-reader labels
  and the speaker labels in «آخر كلام», which name a passenger by their look, never by a hidden type.

#### Events

- **FR-034**: Each of the eight `event_id`s MUST have its look and its player action as in the
  ux-spec's events table (US4), driven by the engine's events (`EventStarted`, `MoneyDropped`,
  `FareIncreased`, `ScheduleShifted`, `DisputeRaised`, `ChangeRequestRaised`, `PassengerBoarded` and
  the rest).
- **FR-035**: Dropped money MUST be tappable (at least 44×44 pt) for as long as the engine lets it be
  collected, then disappear as lost.

#### Help

- **FR-036**: «حد معاه فكة؟» MUST light up the drawer's notes the engine would accept to break and send
  the one picked, and show the requests left out of the trip's `max_break_requests`.
- **FR-037**: A booster MUST be sent to the engine first; only after the engine accepts it is its use
  recorded with the economy. A booster with none left MUST pause the trip and offer to buy it at its
  catalog BONAT price before using it (FR-008). `traffic_jam` MUST be disabled once used
  `booster_traffic_jam_max_per_trip` times.
- **FR-038**: Hints MUST follow `trip_hints_mode_<line_id>` (mobile §7.9): `always` points at the
  passenger who is still owed change as their stop nears; `first_time` explains each passenger type
  the first time the player meets it, and remembers which types they have met; `off` shows none. The
  hint is بلية's small head in a lower corner with one line and a pointing hand. The tutorial's
  dimmed, step-by-step lessons are M07's.

#### Failing and reviving

- **FR-039**: When the engine reports the trip failed, the screen MUST stop the clock, make every
  passenger frown, and show the failure card (ux-spec «فشل المشوار») with a line built from the
  engine's recorded causes.
- **FR-040**: The card MUST offer the BONAT revive at the catalog price only when the engine reports
  the trip revivable and its accepted commands are below the cap (M01 research R9). Taking it MUST
  charge the economy first and then send the engine's revive. The rewarded-ad revive is M11's (FR-047).
- **FR-041**: A story trip's special condition MUST show under the station strip for the whole trip.

#### Sound, vibration and motion

- **FR-042**: Key events (money arriving, change delivered right or short, a station near, a fight, a
  bump) MUST reach the player through at least two of sound, what the scene shows, and words
  (constitution XI). The sounds are the coin in the drawer, the note passing, the passenger's call
  before a stop, and the horn at a station (ux-spec «الحركة والصوت والاهتزاز»). Change given beyond
  what was owed stays silent during the trip, as the product spec says («المستغل يسكت») and
  constitution XI allows: only an honest passenger hands it back, and the result lists the mistake.
- **FR-043**: The phone MUST vibrate lightly when money arrives and harder at a fight, unless
  vibration is off.
- **FR-044**: When the phone's reduced-motion setting is on, the scene MUST NOT shake and bubbles MUST
  appear without a pop.

#### Art

- **FR-045**: The cabin, windows, money, driver's hand, effects and sounds MUST ship as stand-ins in
  the «ستيكر الميكروباص» style, made for the project. Passengers MUST be drawn with one real Rive
  character, supplied by the owner, driven by every state the scene needs (mood from calm to angry,
  talking, asleep, headphones on, getting off) and used for every `skin`, with the skin's colors and
  accessory applied to it, so every archetype stays distinguishable (Clarifications). Swapping in
  more characters or final art later MUST NOT change any behavior or test outcome. Whatever ships
  MUST meet every minimum size.
- **FR-046**: The plan's research MUST resolve mobile §24.6: choose the character animation runtime,
  confirm that its license allows a commercial release on both stores, and record it.

#### No ads in a trip

- **FR-047**: Nothing in this feature may call an ad SDK. The in-trip ad offers (`traffic_jam`,
  `trip_revive`) are M11's; this feature leaves a place for each next to its BONAT option, and the
  trip must be paused or failed before any of them could show (constitution IX).

#### Readability and RTL

- **FR-048**: Every part of the trip screen MUST be RTL, use the theme's tokens for colors, text and
  shapes, and show digits in the player's digit style (constitution X).
- **FR-049**: On the reference frame, and on every screen at least 744 pt tall, the minimum sizes MUST
  hold (constitution XI): back-row faces at least 50 pt wide, near-row faces at least 80 pt, bubble
  text at least 15 pt after scaling, money tokens at least 40×24 pt with a 15 pt amount, touch targets
  at least 44×44 pt, and any text at least 12 pt. On shorter screens only the faces shrink; touch
  targets, tokens and text keep their minimums. The smaller faces are a time-boxed exception to
  constitution XI, approved by the owner, which M07 removes with a layout for short screens (plan.md,
  Complexity Tracking). Text contrast meets WCAG 2.1 AA, and colors that must
  be told apart differ in lightness.
- **FR-050**: Every control and passenger MUST have a screen-reader label (a passenger by their seat
  and station letter), within FR-033's limits.

#### Playtest builds

- **FR-051**: Dev and staging builds MUST let a tester open any trip of the active pack from Home's
  placeholder, and turn on a debug panel with the trip id, revision, seed, the engine's clock and
  status, and a way to copy the replay record. Prod builds MUST contain neither (mobile §20).
- **FR-052**: Until M08 builds the result screen, the result route's placeholder MUST show the
  outcome, the stars with their three conditions, and the pay of the trip just played.

#### Testing

- **FR-053**: Tests MUST cover: the controller's commands and events against a fake economy; every
  start, result, booster, revive and restart path with each economy outcome (applied, refused, write
  failed); a kill and rebuild at many moments of every sample trip; the replay of each parity fixture
  the controls can produce (SC-002) through the screen's controls; the who-paid rule of FR-033; and
  the hint modes. New code
  MUST reach at least 80% line coverage (constitution XIII).
- **FR-054**: Golden tests MUST cover the trip screen in RTL with both digit settings: an idle
  trip on each MVP vehicle, money in transit, a blocked token, two bubbles, a station warning, each
  choice, each event's look, the pause card, the failure card with and without the revive, the
  empty-fuel state and the booster purchase card, on the reference frame, 360×800 and 360×744. A test
  MUST measure the minimum sizes of FR-049 in them.
- **FR-055**: An integration test MUST play a sample trip from start to finish with no network, and
  another MUST kill and relaunch the app mid-trip and finish the same trip.

### Key Entities

- **Trip session**: the one trip on screen: its definition, line, parameters, the economy's start id,
  the content version it started with, and the engine that runs it.
- **Replay record**: the engine's `{definition, seed, params, command_log, t_ms}`, saved after every
  accepted command and pause. It is the trip's checkpoint, and a kill rebuilds the trip from it.
- **Trip view**: what the screen draws at a moment: the passengers (presence, look, state, station
  patch), money tokens and their positions, the drawer and hand, reputation, the station strip and
  its countdown, open choices, active bubbles and the «آخر كلام» lines. It is computed from the
  engine's state and events and never changes them.
- **Bubble queue**: the lines waiting to be shown, at most two on screen, each with its minimum time.
- **Hint memory**: the passenger types the player has already had explained, for the `first_time`
  hint mode.
- **Trip settings**: sound on or off, vibration on or off, remembered between trips.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Every trip of the bundled sample pack plays from start to finish with no network, in
  the integration test and on the reference device in airplane mode.
- **SC-002**: Playing each parity fixture whose commands the screen's controls can produce (58 of
  the 60; the two that answer a payment dispute later than it opens, or never, can't be played on a
  screen that stops the clock for it) through the trip screen's controls gives exactly the fixture's
  expected result, in 100% of runs, so the screen adds or loses nothing.
- **SC-003**: On the Galaxy A06, over a full playthrough of the busiest sample trip on the old
  microbus, with the real Rive character in every occupied seat, the scene averages at least 55 fps
  and no one-second window falls below 45 fps.
- **SC-004**: On the Galaxy A06, memory stays under 300 MB during any sample trip.
- **SC-005**: On the Galaxy A06, a tap on a drawer slot shows the piece in the hand within 100 ms, and
  opening a trip shows its first frame within 1 s.
- **SC-006**: Killing the app at 50 random moments of the sample trips and relaunching each time
  brings back the clock, reputation, drawer, hand, passengers and money in transit exactly as they
  were at the last saved moment (the pause made when the app left the foreground, or the last
  accepted command after a crash), with no liter spent, in 100% of cases.
- **SC-007**: In the goldens on the reference frame, 360×800 and 360×744, 100% of measured faces,
  bubble texts, tokens, touch targets and texts meet their minimum sizes, in RTL with both digit
  settings.
- **SC-008**: In a scripted run of every sample trip, no paid, unpaid or owed indicator shows outside
  the moments FR-033 allows, in 100% of checked frames.
- **SC-009**: In the internal playtest that follows the merge (the delivery plan's milestone), each of
  at least 5 testers from outside the team finishes `line_hay.01` without being told how to play, and
  the owner records whether they replay a trip by choice.

## Assumptions

- **Dependencies.** M01, M03, M04 and M05 are merged. There is no server, account, ad SDK or analytics
  yet, so this feature works with none of them: B02, B03 and M06 sync what the economy records, M11
  adds the ad offers, M15 the `trip_start`, `trip_end` and `change_given` events.
- **The way in.** Home and the pre-trip card are M08's. Until then the player reaches the trip through
  M03's placeholders (Home → pre-trip sheet → trip), and the start is charged when the trip screen
  opens. When M08 builds the pre-trip card, its «اطلع» opens this screen the same way. Ending on
  the result route is M02's; the result screen itself is M08's.
- **The interaction model is the ux-spec's.** The product spec's gestures that the engine has no
  command for (dragging money from seat to seat to route it around a blocker, dragging a fare from a
  passenger's hand to the drawer) are not built: fares reach the drawer by themselves, and a blocked
  chain is cleared by waking or calling the passenger.
- **Timings come from the tunables.** Where the ux-spec and the tunables differ, the tunables win: the
  ledger peek lasts `booster_ledger_peek_ms` (10 s), not the ux-spec's 5 s. Presentation-only values
  (the half-second highlight, the reputation meter's orange threshold, animation lengths) are not
  balancing numbers; the plan lists each one and makes any that changes difficulty a tunable
  (constitution VIII).
- **Theme tokens.** The money colors (green for fares, blue for change) and any other new color join
  `lib/core/theme/tokens/` with their contrast checks. No raw color outside it (M03 guard).
- **BONAT before M06.** Staging and prod builds hold 0 BONAT until the server's balance arrives, so
  their booster purchases and revives are refused with the missing amount shown. Dev builds may set
  balances for testing (M05 assumption).
- **The story character's comments** («بتعلّق على كل غلطة», ux-spec «مشاوير القصة») need a speech slot
  and a character that the engine's capabilities and the schemas don't have. They are not built here;
  the plan hands them to the feature that owns story content. The wedding trip's decorations and
  music are chapter 7, phase 3.
- **The tutorial.** بلية's dimmed, guided lessons in the five tutorial trips, and the gift refill, are
  M07's. This feature builds the hint bubble and pointer M07 reuses.
- **Vehicles.** Only the tuktuk and the old microbus are in the MVP. The new microbus and the travel
  microbus (phase 2 and 3) need their layouts later.
- **Glossary names in code.** `lib/core/glossary/ids.dart`'s `LineId` and `VehicleId` clash with the
  enums `content_models` generates; the plan prefixes the import or retires the glossary copies (M04
  hand-over).
- **Owner actions.** The one Rive character file before the merge (FR-045), the A06 measurements
  (SC-003 to SC-005), the internal playtest (SC-009) and the license check of FR-046. They go in
  `docs/owner-actions.md` at `/speckit-implement`. The final art (every MVP character, the cabin, the
  sound set) is a later art pass that changes no behavior.
- **Out of scope**: Home, the pre-trip card and the result screen (M08); the tutorial (M07); ads and
  their offers (M11); the shop and the fuel sheet (M12); analytics (M15); share clips (M20); the new
  microbus and the later vehicles, lines and passenger types (phase 2 and 3); seasonal decorations.
