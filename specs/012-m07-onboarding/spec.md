# Feature Specification: Onboarding and the Tutorial Trips (M07)

**Feature Branch**: `012-m07-onboarding`

**Created**: 2026-10-27

**Status**: Draft

**Input**: User description: "lets start 012" (`/speckit-specify 012 (next feature from
docs/delivery-plan.md)`). In `docs/delivery-plan.md` step 7, spec 012 is M07: "Onboarding and
tutorial overlays (5 tutorial trips)", which depends on M02. Sources: `docs/ux-spec.md`
«البداية وأول جلسة» and «الصعوبة والمساعدة حسب الخط»; `docs/product-spec.md` «تجربة المستخدم»
(«أول جلسة») and «الفصول»; the design `Intro`, `Name` and `Tutorial` (`docs/design/HANDOFF.md`
§11, with `docs/design/README.md`), HANDOFF §3.3 (`CoachMark`) and §9.2 ("Edit name"). To resolve:
HANDOFF §9.3 #3, each tutorial trip's coach line. Handed over from M02: reuse بلية's hint bubble and
pointer for the tutorial; the tutorial's dimming and the gift refill; a trip layout for short screens
in which faces keep their 50/80 pt minimums, with goldens at 360×640, ending M02's approved exception
to constitution XI. Handed over from M21 (008.5): the `CoachMark` built in the gallery, the locked
boosters bar, the short-screen layout below `inset + 764` pt, and the `Tutorial` artboard's checks.
Handed over from M05 and B03: the tutorial's gift refill as the operation `tutorial_gift`, and the
name as `settings_update`, whose refusal shows `Name`'s error state. Handed over from M06: route the
first open's outcome (a new player, no network or a timed-out wait to the intro, a restored player to
Home), react to progress restored after the wait, record `tutorial_gift` and `settings_update` as
local operations, and take the tutorial grant and the name from the server's state. Done when (step
7, with M08–M10): from first open, the first trip starts in under 20 s; the five tutorial trips work
offline; the integration test from onboarding through the first 5 trips passes.

## Clarifications

### Session 2026-10-27

- Q: While بلية's coaching step is on screen in a tutorial trip, should the trip's clock keep
  running? → A: Yes. The clock keeps running; the player reads the line and acts while the trip goes
  on, and the tutorial trips are authored with room for each lesson. No pause, no extra tap, no rules
  change (FR-025).
- Q: After tutorial trip 3 and the سلمى scene, should the game take the player straight into trips 4
  and 5, or drop them on Home to start those trips themselves? → A: Fully guided. Each result leads to
  the next step: trip 1 → 2 → 3 → the سلمى scene → the notification ask (M14) → trip 4 → the fuel
  lesson → trip 5 → Home. Home stays one tap away from every result (FR-036, FR-037).
- Q: When the player taps «تمام» on the Name card with a network available, should the app wait
  briefly for the server to approve the name, or save it at once and deal with a rare refusal later?
  → A: Save at once, online or offline; the name syncs later. A refusal reopens the Name card as a
  closable sheet on Home, with an error line and a new suggestion (FR-016, FR-018).
- Q: What should المعلم's fuel lesson before trip 5 look like, given that no artboard draws it? → A: A
  card in the design's style: المعلم's avatar with a speech bubble (a trip costs a liter, the tank
  refills over time, a full tank on him), a fuel gauge that fills from low to full, and one button on
  to trip 5. Its look is drawn as a new artboard in Claude Design, in Style C, and added to
  `docs/design/` like every other artboard (FR-033, FR-049).

## User Scenarios & Testing *(mandatory)*

The player is someone who has just installed the game. The product spec sets the goal of their
first session: in the first five minutes they play five trips, understand fuel without being blocked
by it, and get attached to the story. Nothing is explained on a screen of its own. The game teaches
inside the first five trips, with بلية pointing at the one thing to do next.

The first session, in the order of the product spec «أول جلسة» (its eight steps are what M15 will
report as `tutorial_step` 1..8):

| Step | What the player sees | Built by |
| --- | --- | --- |
| 1 | The opening scene: المعلم hands the driver the tuktuk key. Then the Name card. | M07 |
| 2 | Trip 1, two riders: fares reach the tray by themselves | M07, on M02's trip screen |
| 3 | Trip 2: the first change given back | M07 |
| 4 | Trip 3: the first stop with a countdown, the first time pressure | M07 |
| 5 | The scene: the driver sees سلمى at the stand, and the empty apartment appears as the goal | M07 |
| 6 | The notification ask: «تحب نقولك لما البنزين يتملى؟» | M14 (M07 keeps its place) |
| 7 | Trip 4: the first sleeping rider | M07 |
| 8 | Trip 5: the tank is nearly empty; المعلم gives a free refill once and explains fuel | M07 |

The other users are **M08, M10, M11, M14 and M15**, which build on what this feature decides (Home,
the result screen, the story viewer, ads, settings, analytics), and **the tester** on internal
builds, who needs to replay the first session without reinstalling.

### User Story 1 - A new player is driving within seconds (Priority: P1)

On the first open, after the Loading screen, a new player sees a three-panel comic: المعلم hands them
the key to his tuktuk and gives the game's one rule. They can tap through it or skip it. Then one card
asks their driver's name, with a suggested name already filled in, so one tap continues. The first
tutorial trip starts straight after. No sign-up, no settings, no ads, no network needed.

**Why this priority**: The constitution requires the first trip within 20 s of first open
(principle V), and it is the first thing every player sees. Without it, a new player lands on Home with
no idea what the game is.

**Independent Test**: On a fresh install with the network off, open the app, tap «يلا» through the
three panels and «تمام» on the Name card. The first trip starts within 20 s of opening the app, and
the name shows wherever the app shows it. Repeat with «تخطّى» and with the network on.

**Acceptance Scenarios**:

1. **Given** a fresh install, **When** the first open's account check ends as a new player, with no
   network, or past its 3 s wait, **Then** the app opens the opening scene. **When** it ends as a
   returning player whose progress came back, **Then** the app opens Home and shows none of the first
   session's screens.
2. **Given** the opening scene, **When** the player taps «يلا», **Then** the next panel shows; on the
   last panel, «يلا» opens the Name card. **When** the player taps «تخطّى» or presses the phone's back
   button, **Then** the Name card opens at once, with no way back to the scene or the Loading screen.
3. **Given** the opening scene was finished or skipped, **Then** it never opens again by itself.
4. **Given** the Name card, **Then** the field holds a suggested name, and «تمام» starts tutorial
   trip 1 without the pre-trip card. **When** the player taps the dice, **Then** another suggested
   name replaces it.
5. **Given** the field is empty, holds only spaces, or breaks a name rule the phone can check, **Then**
   «تمام» is disabled.
6. **Given** a player who taps through without skipping, **When** they accept the suggested name,
   **Then** the first trip starts within 20 s of opening the app, with or without a network.

---

### User Story 2 - بلية teaches the five tutorial trips (Priority: P1)

The first five trips of خط الحي are the tutorial. In each, at the moment its lesson matters, the
screen dims except for one control, بلية's head appears in the corner with a one-line bubble, and a
hand points at what to tap. The player does the real thing (picks the coins, taps the rider, wakes the
sleeper), and the trip goes on. Mistakes are allowed and count as in any trip.

**Why this priority**: The tutorial is how a new player learns the game at all. The design's
first-session goal (five trips in five minutes, 80% of new players finishing it, product spec
«مؤشرات النجاح») depends on it.

**Independent Test**: Play each tutorial trip on a fresh profile. At each lesson's moment the screen
dims, only the target responds, بلية's line names the trip's real numbers and station, and doing what
he asks ends the step. Play a tutorial trip a second time after finishing it: no coach steps.

**Acceptance Scenarios**:

1. **Given** tutorial trip 1, **When** the first fare lands in the tray, **Then** the screen dims
   around the tray, and بلية says «شايف؟ الأجرة وصلت الدرج». **When** the player taps anywhere, or
   once the line has been up for the line's minimum bubble time, **Then** the step ends.
2. **Given** tutorial trip 2, **When** a fare that is owed change reaches the driver, **Then** the
   hole sits on the coin to pick, and بلية names the amount owed and how to pay it (the drawn line:
   «ليه باقي ٣. دوس على الجنيه ٣ مرات، وبعدين دوس عليه.»). **When** the hand holds the change,
   **Then** the hole moves to the rider who is owed it. **When** the player taps him, **Then** the
   change goes to him and the step ends.
3. **Given** tutorial trip 3, **When** the countdown appears for a rider still owed change, **Then**
   بلية says «نازل {station}، لازم ياخد باقيه قبلها» with the real station's name, and the step leads
   the player through the change as in trip 2.
4. **Given** tutorial trip 4, **When** the sleeping rider is aboard and asleep, **Then** the hole sits
   on him and بلية says «ده نايم، دوس عليه صحّيه». **When** the player taps him, **Then** he wakes and
   the step ends.
5. **Given** a coach step is showing, **When** the player taps outside the hole, the bubble or بلية,
   **Then** nothing happens. **When** the player taps the target, **Then** the trip treats it as the
   normal command.
6. **Given** a coach step, **When** the player picks more coins than owed, or sends the wrong amount,
   **Then** the engine allows it and the trip judges it as it would any other trip.
7. **Given** a coach step whose target goes away (the rider gets off, the stop passes, the trip
   ends), **Then** the step ends at once and the trip continues.
8. **Given** a coach step, **When** the player presses back, **Then** the pause card opens as in any
   trip; on resume the same step shows again. **Given** the app was sent to the background or killed
   during a step, **When** the trip resumes, **Then** the step that was showing shows again.
9. **Given** a tutorial trip the player has already finished once, **When** they play it again,
   **Then** it has no coach steps. **Given** a tutorial trip they failed, **When** they retry it,
   **Then** the coach steps show again.

---

### User Story 3 - The first session holds together (Priority: P2)

The five trips, the سلمى scene, the notification ask and the fuel lesson come in the product spec's
order, with no detour through menus. The result of each tutorial trip leads to the next step. The
sleeping-rider trip comes after the scene, and before trip 5 the tank is nearly empty: المعلم fills
it once, free, and explains how fuel works. The boosters stay locked until the tutorial ends. A
player who closes the app halfway picks up where they left off, and a player whose old progress comes
back is never taught twice.

**Why this priority**: The lessons work only in order, and the fuel lesson must come before an empty
tank blocks a new player (product spec: "understand fuel without being blocked").

**Independent Test**: Play the whole first session offline: the scene plays once after trip 3, the
fuel lesson once before trip 5, the tank is full after it, and the booster row shows the locked bar
in all five trips. Kill the app at each step and relaunch: the session continues from that step.
Bring the network back: the server records one tutorial gift.

**Acceptance Scenarios**:

1. **Given** a tutorial trip ends with at least one star, **When** the player takes the result
   screen's main action, **Then** the next step of the first session opens: the next tutorial trip
   (without the pre-trip card), or the scene after trip 3, or the fuel lesson before trip 5. After
   trip 5, Home.
2. **Given** tutorial trip 3 has just been finished for the first time, **Then** chapter 1's سلمى
   scene plays once, in the same comic presentation as the opening, and then the notification ask's
   place in the session (M14), then trip 4.
3. **Given** tutorial trip 5 has never been started, **When** the player is about to start it, or
   **when** the tank cannot pay for the next tutorial trip at any point of the session, **Then**
   المعلم's fuel lesson shows once, the tank fills to its maximum as a gift, and the player continues.
4. **Given** the gift, **Then** it works offline, the tank shows full at once, and it is recorded
   once as a `tutorial_gift` operation that reaches the server with the next sync.
5. **Given** the phone already recorded the gift, or the server's state says this player received
   it, **Then** the fuel lesson still never gives a second gift.
6. **Given** any trip before tutorial trip 5 has been finished, **Then** the booster row is replaced
   by the locked bar «المساعدات بتتفتح بعد المشوار الخامس», and no booster can be used. **Given**
   trip 5 has been finished once, **Then** the boosters are back in every trip.
7. **Given** the app is killed before the first trip has started, **When** it is launched again,
   **Then** the first session resumes: the opening scene if it was neither finished nor skipped, the
   Name card if no name was saved, otherwise tutorial trip 1. **Given** the first trip has started,
   **Then** launches follow the trip screen's rules (an unfinished trip opens paused, otherwise
   Home), and the remaining tutorial trips are still the player's next trips, with their steps.
8. **Given** the scene after trip 3 or the fuel lesson was due when the app was killed, **Then** it
   shows at the next arrival at Home, before the next trip.
9. **Given** the player's old progress arrives after the first open's 3 s wait (a re-install),
   **When** the player is still in the opening scene or on the Name card, **Then** these close and
   the player lands on Home with the restored name and progress. **When** a trip is on screen,
   **Then** nothing changes until they leave it. In every case, finished tutorial trips are not
   taught again and a gift already received is not given again.

---

### User Story 4 - The driver's name reaches the server (Priority: P2)

The name the player picks is theirs at once, offline too, and the phone sends it with the next sync.
The server checks it against its rules and the staff's name filter. In the rare case it is refused,
the player is asked again, kindly, the next time they are at Home.

**Why this priority**: The name shows on Home now and in leagues later (phase 3), so it must reach
the server. A refusal arrives long after the Name card, so the player needs a way to fix it.

**Independent Test**: Against a fake server, pick a name offline, play a trip, then go online: the
server receives the name once. Make the fake server refuse it: at the next arrival at Home, the Name
card opens as a sheet with an error line and a new suggestion.

**Acceptance Scenarios**:

1. **Given** the player taps «تمام», **Then** the trimmed name is saved on the phone, shows wherever
   the app shows the driver's name, and is recorded as a `settings_update` operation with the name.
2. **Given** every suggested name, **Then** it passes the server's name rules and its starting name
   filter, so accepting a suggestion is never refused.
3. **Given** the server refuses the name (`validation_error` on the name), **Then** the phone goes
   back to the last name the server accepted (or a neutral default if there is none), and the next
   time the player arrives at Home, outside a trip, the Name card opens as a sheet with an error line
   and a fresh suggestion.
4. **Given** that sheet, **When** the player saves a name, **Then** it is recorded and sent like the
   first. **When** they close it, **Then** the default name stays, and the sheet opens again at most
   once per launch until a name is accepted.
5. **Given** a player with no name at all at Home (a restored player who never named the driver),
   **Then** the same sheet opens, without the error line.

---

### User Story 5 - Short screens keep every minimum (Priority: P2)

On phones shorter than the design's frame, the trip screen today keeps its bars at full size and
shrinks the scene, so faces fall under their minimums: an exception to constitution XI that the
owner approved until M07. This feature gives short screens a compact arrangement of the top bar and
dashboard, so faces, bubbles, money and targets keep every minimum, and the play controls stay in the
bottom third, on every screen the app supports.

**Why this priority**: Accessible minimums are acceptance criteria, not suggestions (constitution XI),
and the exception ends here. Many phones in the Egyptian market are 360×640-class screens.

**Independent Test**: Render the trip screen with the microbus and the tuktuk at 360×640, at an
in-between height, at 360×800 and at 390×844, at text scale 1.0 and 1.3, and measure: every face,
bubble, token, target and text meets its minimum, and every play control sits in the bottom third.

**Acceptance Scenarios**:

1. **Given** a screen at least `inset + 764` pt tall, **Then** the trip screen is laid out exactly as
   008.5 lays it out today.
2. **Given** a shorter screen, down to 360×640 pt, **Then** the trip screen uses the compact
   arrangement: the same information and the same controls, in the design's style, with nothing
   removed or hidden behind a menu.
3. **Given** the compact arrangement, **Then** back-row faces are at least 50 pt wide, near-row faces
   at least 80 pt, bubble text at least 15 pt, money tokens at least 40×24 pt with a 15 pt amount,
   touch targets at least 44×44 pt, all text at least 12 pt, and every control the player plays with
   is in the bottom third of the screen.
4. **Given** a tutorial trip on a short screen, **Then** the coach bubble, بلية and the pointing hand
   stay fully on screen, and the hole surrounds its target.

---

### User Story 6 - Testers can replay the first session (Priority: P3)

On dev and staging builds, a tester can open the opening scene, the Name card, the سلمى scene and the
fuel lesson on demand, and start any tutorial trip with its coach steps, without reinstalling.

**Why this priority**: Checking the first session on a real phone otherwise needs a fresh install
each time. Production builds don't need it.

**Independent Test**: On a staging build that has finished the tutorial, open each first-session
screen from the debug panel and start tutorial trip 2 with its coach: every step shows. A production
build has no such controls.

**Acceptance Scenarios**:

1. **Given** a dev or staging build, **When** the tester opens the debug panel, **Then** they can show
   each first-session screen and start any tutorial trip with its coach steps forced on.
2. **Given** a production build, **Then** none of these controls exist.

---

### Edge Cases

- **A lesson whose moment never comes** (the trip's data changed and no rider is owed change in trip
  2): the step doesn't show, and the trip counts toward the tutorial once finished. A test of the
  tutorial content catches it before release (FR-047).
- **A pack with fewer than five trips on its first line** (the sample, whose third is a story trip):
  the tutorial is those trips, and it is done when they are all finished.
- **Short screens:** the coach overlay works in the trip screen's compact arrangement below
  `inset + 764` pt (User Story 5), fully on screen (FR-042).
- **Two lesson moments at once:** at most one coach step shows. The next waits until the first ends,
  and is dropped if its own target has gone by then.
- **بلية's ordinary hints** (on خط الحي they are always on) never show while a coach step is up. In
  tutorial trips, between steps, and in every trip after the tutorial, they work as M02 built them.
- **A tutorial trip failed:** the failure card works as in any trip. A retry costs a liter and shows
  the coach steps again. If the tank can't pay for it, the fuel lesson and its gift come first (once).
- **Leaving a tutorial trip** through the pause card: the trip is abandoned as usual, and it is still
  the player's next trip, with its steps.
- **The result screen's other actions:** if the player goes to Home instead of continuing, the next
  trip they start is still the next tutorial trip, and a due scene or fuel lesson shows before it.
- **No opening scene in the pack:** the app goes straight to the Name card. No سلمى scene in the pack:
  trip 4 follows trip 3.
- **Keyboard on the Name card:** the card moves up so it stays fully visible. A name longer than 16
  characters can't be typed or pasted beyond 16.
- **A pasted name with invisible or control characters, or only digits:** «تمام» stays disabled until
  it meets the rules.
- **The tank is full when the gift comes** (the player waited for it to refill): the lesson still
  plays and the gift is still recorded, and the server accepts a full tank unchanged (B03).
- **The server refuses the gift** (already granted on another phone): the phone undoes it as M06 undoes
  any refused operation, and the fuel shown follows the server's.
- **A content update during the first session:** a newer pack switches only at launch or on arrival at
  Home (M04), never mid-trip. The tutorial trips are found in the active pack each time.
- **Reduced motion:** no ring pulse, no hand bob; the opening scene's panels change by a short fade.
- **Screen reader:** each coach step is announced; only its target can be focused while it shows.
- **Text scale 1.3** (the trip's limit): the coach bubble wraps and grows, never clips, and stays on
  screen.
- **A phone shorter than 640 pt or narrower than 360 pt** (split screen): outside the supported range;
  the trip still plays, scaled as M02 does (see Assumptions).

## Requirements *(mandatory)*

### Functional Requirements

#### Where a launch goes

- **FR-001**: On the first open, after the Loading screen and M06's wait of up to 3 s, the app MUST
  open the opening scene when the outcome is a new player, no network, or a wait that timed out, and
  Home when the player's progress came back.
- **FR-002**: Until the first trip has started, a launch MUST resume the first session at its next
  step: the opening scene if it was neither finished nor skipped, the Name card if no name was saved,
  otherwise tutorial trip 1.
- **FR-003**: Once the first trip has started, launches MUST follow M02's rule (an unfinished trip
  opens paused, otherwise Home). The first session then continues from Home and from the result
  screen (FR-036, FR-037).
- **FR-004**: When the player's progress arrives after the 3 s wait, the app MUST:
  - close the opening scene or the Name card if one is showing, and open Home with the restored name
    and progress, when the restored progress holds a name or any finished trip;
  - change nothing while a trip is on screen;
  - from then on, treat finished tutorial trips as finished and a received tutorial gift as received.
- **FR-005**: A name the player confirmed on this phone before the restore MUST win over the restored
  one, since it is the later operation.

#### The opening scene (`Intro`)

- **FR-006**: The opening scene MUST be chapter 1's opening scene from the active content pack: its
  panels, the art of each, a caption (the panel's narrator line), the speaker and their line, and the
  chapter's title as the header. Nothing in it may be hard-coded in the app but the button labels.
- **FR-007**: It MUST show one panel at a time with page dots, as drawn in `Intro`. «يلا» advances; on
  the last panel it opens the Name card. Panels advance only on a tap, never by themselves.
- **FR-008**: «تخطّى» and the phone's back button MUST open the Name card at once, with no way back to
  the scene or to Loading.
- **FR-009**: Once finished or skipped, the opening scene MUST NOT open again by itself. (It stays in
  the story album, which is M10's.)
- **FR-010**: If the active pack has no opening scene, the app MUST go straight to the Name card.

#### The name (`Name`)

- **FR-011**: The Name card MUST be built as drawn in `Name`, with a suggested name already in the
  field, chosen at random from a pool of at least 20 suggestions.
- **FR-012**: The dice MUST replace the field with another suggestion, never the one showing.
- **FR-013**: Every suggestion MUST pass the server's name rules and the server's starting name
  filter (B03 research R10). A test MUST check the whole pool.
- **FR-014**: The field MUST accept at most 16 characters. «تمام» and the keyboard's done key MUST be
  enabled only when the name, trimmed and with inner spaces collapsed, has at least 2 characters, is
  not only digits, and holds no control, bidi or zero-width characters.
- **FR-015**: The phone's back button MUST do nothing on the Name card.
- **FR-016**: «تمام» MUST save the trimmed name on the phone, show it wherever the app shows the
  driver's name, record it as a `settings_update` operation carrying the name, and start tutorial
  trip 1 without the pre-trip card. All of it MUST work offline, and it MUST NOT wait for the server
  even when a network is available: the name reaches the server with the next sync (Clarifications).
- **FR-017**: When the server refuses the name, the phone MUST go back to the last name the server
  accepted, or to a neutral default name if it never accepted one.
- **FR-018**: After a refusal, or whenever the player has no name, the next arrival at Home outside a
  trip MUST open the Name card as a sheet (HANDOFF §9.2 "Edit name"): with a fresh suggestion, and
  with an error line only after a refusal. The player MAY close it; it MUST then open at most once per
  launch until a name is accepted.
- **FR-019**: The sheet of FR-018 MUST be the one M14's settings reuse to edit the name.

#### Coach steps in the tutorial trips (`Tutorial`)

- **FR-020**: The tutorial trips MUST be the first five trips of خط الحي, `line_hay.01` to
  `line_hay.05`, played in order (the unlock order already requires it).
- **FR-021**: A tutorial trip MUST show its coach steps until the player has finished it once (at least
  one star). A retry after a failure MUST show them again; a later replay MUST NOT.
- **FR-022**: A coach step MUST dim the whole screen except one rounded hole around its target, with
  a ring around the hole, بلية's head at the scene's bottom corner, his line in a character bubble,
  and a hand pointing at the target, as drawn in `Tutorial`.
- **FR-023**: The hole MUST follow the target's position on screen as it is laid out, never a fixed
  rectangle, and MUST move to the next target when a step has two.
- **FR-024**: While a step shows, a tap on its target MUST act as the normal trip command, and every
  other tap MUST be ignored without feedback, including taps on the bubble and on بلية.
- **FR-025**: A coach step MUST NOT change the trip's rules: wrong or extra coins are allowed and
  judged as in any trip. The trip's clock MUST keep running while a step shows: the step neither pauses
  the trip nor asks for an extra tap (Clarifications). Each tutorial trip MUST leave its lesson enough
  time, which FR-047's test checks.
- **FR-026**: A step whose target goes away (the rider leaves, the stop passes, the trip ends) MUST end
  at once. At most one step MUST show at a time. بلية's bubble MUST count as one of the two speech
  bubbles constitution XI allows at once: it appears only when at most one rider's bubble shows, and
  while it shows, at most one does. It MUST stay up for at least the line's minimum bubble time: when
  its step ends sooner, the dimming, the hole and the hand go at once, and the bubble stays until its
  time is up. بلية's ordinary hints follow the same two rules.
- **FR-027**: The phone's back button during a step MUST open the pause card. After a resume, a return
  from the background, or a rebuild after a kill, the step that was showing MUST show again.
- **FR-028**: بلية's ordinary hints MUST NOT show while a coach step is up.
- **FR-029**: Each tutorial trip MUST teach its lesson at its moment:

  | Trip | Lesson | The step starts when | Points at | بلية's line (draft) | The step ends when |
  | --- | --- | --- | --- | --- | --- |
  | 1 | Fares reach the tray by themselves | the first fare lands in the tray | the tray | «شايف؟ الأجرة وصلت الدرج» | the player taps anywhere, or the line has been up for the line's minimum bubble time (`trip_bubble_min_ms_line_hay`) |
  | 2 | Giving change: the coins, then the rider | a fare that is owed change reaches the driver | the coin to pick, then the rider owed | «ليه باقي {amount}. دوس على {coin} {count} مرات، وبعدين دوس عليه.» | the change is sent to him |
  | 3 | The stop and its countdown | the countdown appears for a rider still owed change | his countdown, then the coins and the rider as in trip 2 | «نازل {station}، لازم ياخد باقيه قبلها» | the change is sent to him, or his stop passes |
  | 4 | The sleeping rider | a sleeping rider is aboard and asleep | the sleeper | «ده نايم، دوس عليه صحّيه» | he wakes |
  | 5 | Fuel | before the trip starts | المعلم's fuel lesson (FR-033) | written in the plan | the player continues |

- **FR-030**: The lines MUST take their numbers and names from the trip itself (the amount owed, the
  coin and how many, the station's name). When one coin type can't pay the change, trip 2's line MUST
  fall back to a line that names the amount without the coin. The lines are UI strings in the app's
  Arabic resources, and the owner approves them (this resolves HANDOFF §9.3 #3).

#### The سلمى scene, the notification ask and the fuel lesson

- **FR-031**: The first time tutorial trip 3 is finished, chapter 1's سلمى scene MUST play once, after
  the trip's result, in the same comic presentation as the opening scene, with «تخطّى». If the app is
  killed before it plays, it MUST play at the next arrival at Home, before the next trip.
- **FR-032**: After the سلمى scene, the session MUST leave the notification ask's place for M14 (product
  spec step 6), then continue to trip 4.
- **FR-033**: The fuel lesson MUST show once per player: before tutorial trip 5 is first started, or
  earlier, the first time the tank can't pay for the next tutorial trip. It MUST be a card
  (Clarifications): المعلم's avatar with a speech bubble saying that a trip uses a liter, that the tank
  refills over time and that this fill is on him; a fuel gauge that fills from the current level to
  full; and one button that goes on to trip 5. It MUST be built to its own artboard, `FuelLesson`,
  drawn in Claude Design in Style C and added to `docs/design/` (HTML, PNG and measured boxes) like the
  others.
- **FR-034**: The fill MUST bring the tank to its maximum at once, offline too, and MUST be recorded
  as one `tutorial_gift` operation.
- **FR-035**: The phone MUST NOT record a second gift when it already recorded one or when the
  server's state says the player received it. Taking the server's state MUST carry this grant across.

#### The session's order and the boosters

- **FR-036**: The first session MUST be fully guided (Clarifications): from a tutorial trip's result
  screen, the main action MUST open the next step, in this order: trip 1 → trip 2 → trip 3 → the
  سلمى scene → the notification ask's place (M14) → trip 4 → the fuel lesson → trip 5 → Home. A
  tutorial trip opened this way MUST skip the pre-trip card. The result screen MUST also offer Home.
- **FR-037**: A player who leaves for Home mid-session MUST find the next tutorial trip as their next
  trip, and a due scene or fuel lesson MUST show before it starts.
- **FR-038**: Until the tutorial is done (FR-039), every trip MUST show the locked bar
  «المساعدات بتتفتح بعد المشوار الخامس» in place of the booster row, and no booster MAY be used. After,
  the booster row MUST return.
- **FR-039**: The tutorial MUST count as done once every tutorial trip the active pack has is finished
  (five in a release pack), whether played on this phone or shown so by the server's state once taken.
  The app MUST know which of the first session's eight steps the player has reached, so that M15 can
  report them and M11 can hold interstitials until the tutorial is done.

#### Short screens

- **FR-040**: On every screen from 360×640 pt up, at text scale 1.0 and 1.3, and for both MVP
  vehicles (the tuktuk and the old microbus), the trip screen MUST meet every minimum of constitution
  XI: back-row faces ≥ 50 pt wide, near-row faces ≥ 80 pt, bubble text ≥ 15 pt, money tokens ≥ 40×24
  pt with a 15 pt amount, touch targets ≥ 44×44 pt, all text ≥ 12 pt, and every play control in the
  bottom third of the screen.
- **FR-041**: Below `inset + 764` pt of height, the trip screen MUST use a compact arrangement of the
  top bar and the dashboard in the design's style, with the same controls and the same play
  information (the stations with their letters, names, prices and countdown; reputation; the last
  words), none removed or hidden behind a menu. Only the trip's title MAY move, to the pause card. At
  and above that height, the layout MUST stay as 008.5 built it. The owner approves the compact
  arrangement, since no artboard draws it.
- **FR-042**: Coach steps, bubbles, banners and cards MUST work in the compact arrangement, fully on
  screen.
- **FR-043**: This MUST end M02's approved exception to constitution XI: its Complexity Tracking entry
  is closed, and the trip goldens at 360×640 show every minimum met.

#### Accessibility and motion

- **FR-044**: Each coach step MUST be announced as a live region («بلية: …») when it starts, and only
  its target MUST be focusable while it shows. The opening scene, the Name card and the coach overlay
  MUST follow the read orders and labels of their artboards (the page dots «اللوحة {n} من {total}»,
  the dice «اقترح اسم تاني», the field labelled «اسمك»).
- **FR-045**: Motion MUST follow the artboards (the scrim fades in, the hole moves between targets, the
  ring pulses, the hand bobs, panels change by a short slide). Under reduced motion there MUST be no
  ring pulse and no hand bob, and panels MUST change by a short fade.

#### Content

- **FR-046**: The content pack MUST say which chapter 1 scene opens the game and which plays after
  tutorial trip 3, and a panel MAY carry a caption. The sample pack (dev builds) MUST hold both scenes.
  Its trips stay as they are; the tutorial's five trips are tested from the release draft's
  (`content/drafts/core-r1`, trips 01–05), kept as a test fixture.
- **FR-047**: A test MUST play the tutorial fixture's five trips, and the release pack's once one is
  bundled, with a player that does only what each coach step asks, and check that every lesson's step
  starts and that each trip finishes with at least one star.

#### Internal builds

- **FR-048**: On dev and staging builds, the debug panel MUST be able to show the opening scene, the
  Name card, the سلمى scene and the fuel lesson, and to start any tutorial trip with its coach steps
  forced on. Production builds MUST NOT contain these controls.

#### Testing

- **FR-049**: The `Intro`, `Name`, `Tutorial` and `FuelLesson` artboards MUST each have a golden at
  390×844 in RTL
  with both digit styles, and a layout test against their measured boxes (±2 px), as the design-check
  rule requires (HANDOFF §10). The plan settles how the tuktuk's seats meet `Tutorial`'s two-rider
  drawing (008.5 left this check to M07).
- **FR-050**: An integration test MUST play the whole first session offline, from first open through
  the five tutorial trips to Home, and then sync the name and the gift against a fake server.
- **FR-051**: Tests MUST kill the app at each step of the first session and check that the next launch
  resumes as FR-002, FR-003, FR-027 and FR-031 say, never repeating the opening scene or the name,
  and never recording a second gift.

### Key Entities

- **First-session progress**: where the player stands in the eight steps: the opening scene finished
  or skipped, a name saved, which tutorial trips are finished (read from trip progress), the سلمى scene
  seen, the fuel lesson and gift given, the tutorial done. Kept on the phone; the parts the server
  knows (trip progress, the gift, the name) are rebuilt from its state on a restore.
- **Driver name**: the name shown, the last name the server accepted, the pending operation that
  carries a new one, and whether the last one was refused.
- **Suggested names**: the pool the Name card draws from, each passing the server's rules.
- **Coach step**: a tutorial trip's lesson moment: the trip, what starts it, its one or two targets,
  بلية's line with its placeholders, and what ends it.
- **Chapter 1's onboarding scenes**: the opening scene and the سلمى scene, content in the pack, each
  marked with when it plays.
- **Tutorial gift**: the one free fill of the tank, recorded once as `tutorial_gift`, known to the
  server as the player's tutorial grant.
- **Compact trip layout**: the arrangement of the top bar and dashboard for screens below the
  threshold, and the scene's share of the height that keeps every minimum.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A new player who taps through the opening scene and accepts the suggested name starts
  the first trip within 20 s of opening the app, on the reference phone (Galaxy A06), with and
  without a network.
- **SC-002**: The integration test plays the whole first session offline: all four in-trip lessons
  start, the سلمى scene plays once, the gift fills the tank once, the booster row is locked in all five
  trips, and the session ends on Home. Online again, the server holds one name update and one tutorial
  gift.
- **SC-003**: After a kill at any step of the first session, the next launch resumes at that step or
  the next, in 100% of the kill tests: the opening scene never repeats once finished or skipped, the
  name is never asked again once saved, and a second gift is never recorded.
- **SC-004**: On renders at 360×640, 360×720, 360×800 and 390×844, at text scale 1.0 and
  1.3, with both vehicles, every face, bubble, token, target and text meets its minimum and every play
  control is in the bottom third: zero failures. M02's exception is closed.
- **SC-005**: The `Intro`, `Name`, `Tutorial` and `FuelLesson` goldens match their artboards in
  layout, colors, sizes and copy, and every measured box is within ±2 px.
- **SC-006**: Every suggestion in the name pool passes the server's rules and starting filter: 0
  refusals.
- **SC-007**: In a moderated playtest with at least 5 people new to the game, at least 4 finish the
  five tutorial trips without the moderator's help, in about five minutes. (An owner check; the
  80%-of-new-players KPI needs M15's analytics.)
- **SC-008**: With a screen reader on, every coach step is announced when it starts and focus lands on
  its target; with reduced motion on, nothing pulses or bobs.

## Assumptions

- **Dependencies.** M02, M21 (008.5), M05 and M06 are merged: the trip screen, the design's
  components (`CoachMark` in the gallery, `SpeechBubble`, `AppCard`, `AppTextField`), the economy and
  the sync queue exist. M08 (Home, the pre-trip card and the result screen) is next and isn't merged:
  until it is, the result's main action and Home are M02's placeholders, and M08 keeps FR-036 and
  FR-037 when it replaces them.
- **Settled with the owner** (Clarifications):
  - The trip's clock keeps running during a coach step. The design draws a live countdown under the
    scrim, and the engine refuses tray and passenger commands while a trip is paused (M01
    data-model), so a frozen clock that still took the player's tap would be a rules change
    (constitution III).
  - The first session is fully guided, in the product spec's order, so it doesn't wait on M08's Home.
    The design draws the notification ask over Home; M14 shows it at its place in the sequence.
  - The name is saved at once and never waits for the server, so the first trip stays fast and
    offline works the same. A refusal arrives after the sync and is asked again on Home with the Name
    card as a closable sheet (HANDOFF §9.2). The error line and the default name are proposed in the
    plan for the owner's approval.
  - The fuel lesson is a card with its own artboard, `FuelLesson`, drawn in Claude Design. The plan
    writes its brief (content, strings, states, motion, accessibility, in the shape of a HANDOFF §11
    section), the artboard is drawn from it and committed to `docs/design/` (`screens/`, `png/`,
    `boxes/`), and the card is built after that. `docs/delivery-plan.md`'s Design sources table gains
    it in M07's row.
- **Resolved here without the owner** (`/speckit-clarify` can revisit any of them):
  - **The opening scene is content.** HANDOFF's `Intro` reads it from chapter 1 in the pack, it stays
    in the story album, and dialogue belongs in content (constitution VII). Saying when a scene plays
    and giving panels a caption may need a schema field, which is allowed while no pack has been
    promoted to production (the release pack waits for M07–M10's schema fields).
  - **Each lesson starts from what happens in the trip**, not from fixed times, so a change to a
    tutorial trip's data keeps the lessons working, and FR-047 catches the case where it doesn't.
  - **The سلمى scene plays after trip 3**, as the ux-spec and the product spec's first session say.
    Chapter 1's closing scene (after المعلم's story trip) is M10's.
  - **The fuel lesson comes before trip 5, or earlier if the tank runs dry**, so failures and retries
    in the tutorial never leave a new player blocked by an empty tank.
  - **The boosters stay locked until trip 5 is finished**, in every trip, as the locked bar's text
    says.
  - **The Name card's limit is 16 characters**, the design's, inside the server's 2 to 20.
- **HANDOFF §9.3 #4 is still open** (passing money around a muted أبو سمّاعة). The delivery plan placed
  it before M07, but M07's trips are on خط الحي's tuktuk, which has no passing chain and no
  أبو سمّاعة, so nothing here depends on it. It must be settled before M08's pre-trip card mentions it.
- **Copy.** Trips 1, 3 and 4's lines come from the ux-spec, trip 2's from the drawn `Tutorial`. The
  fuel lesson's lines, trip 2's fallback line, the refusal's error line and the suggested names are
  written in the plan. The owner approves all of them (an owner action).
- **Content.** The release draft (`content/drafts/core-r1`, on its own branch) already has the five
  tutorial trips; it gains chapter 1's opening scene and the scenes' `plays` (handed over). The
  sample's trips stay as they are: rewriting them would change the parity fixtures and hundreds of
  engine, solver and backend tests that M07 has no reason to touch. The sample gains only chapter 1's
  opening scene and the سلمى scene's marker, so its golden checksums are regenerated. On a device, a
  dev build plays the real tutorial once the draft is published on the local stack (plan,
  quickstart).
- **The smallest supported screen is 360×640 pt**, M03's smallest test surface. Smaller windows (split
  screen, a few old phones) are outside the supported range; there the trip plays scaled as M02 does
  it, and the plan records that boundary.
- **Scenes seen stay on the phone for now.** M07 records that the opening and سلمى scenes were seen so
  they never play again on this phone. Sending scene progress to the server (`story_progress`) and the
  story album are M10's, which also sends the scenes M07 recorded.
- **Handed to later features**:
  - **M08**: the result screen's main action and Home's next trip follow FR-036 and FR-037; the
    pre-trip card shows no boosters until the tutorial is done (FR-038).
  - **M10**: `story_progress` for the two scenes played here; the opening scene in the album.
  - **M11**: no interstitial before the tutorial is done (FR-039).
  - **M14**: the notification ask after the سلمى scene (FR-032); the settings screen's name edit reuses
    the sheet of FR-018.
  - **M15**: `tutorial_step` 1..8 from the steps of FR-039.
- **Out of scope**: the notification ask and push permissions (M14); Home, the pre-trip card and the
  result screen (M08); the story viewer, the album and scene sync (M10); ads (M11); analytics (M15);
  the Loading screen and the first open's wait (M06, 008.5).
