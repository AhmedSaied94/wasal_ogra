# Feature Specification: Trip Engine (M01)

**Feature Branch**: `004-m01-trip-engine`

**Created**: 2026-10-20

**Status**: Draft

**Input**: User description: "feature 004 (next in docs/delivery-plan.md)". Feature 004 in
`docs/delivery-plan.md` is M01, step 2: "`trip_engine`: rules, commands, events, determinism".
Depends on the B04 schemas (merged). Sources: docs/product-spec.md «ميكانيكيات المشوار»,
«أنواع الركاب», «الأحداث والمواقف» and «المساعدات»; docs/ux-spec.md «شاشة المشوار» and
«أثناء المشوار: الأحداث والنوافذ»; docs/architecture-mobile.md §7 (with §3, §10 and §14.3).
Resolve mobile §24.4 (resume or restart when the app is killed mid-trip). Handed over from M03:
settle the tunable `trip_hints_enabled_line_gamaa`. Handed over from B04: refine the trip schema
as the engine needs, list the `speech_key`s the engine emits, and read `TripDefinition` from the
generated app models. Done when (M01's part of step 2): replaying
`(definition, seed, params, command_log)` gives an identical `TripResult`, the engine has ≥ 90% line
coverage, and the first parity fixtures are in `fixtures/parity/`.

## Clarifications

### Session 2026-10-20

- Q: When the app is killed mid-trip, what happens on the next launch (mobile §24.4)? → A: The trip
  resumes exactly where it stopped.
  - The app keeps the trip's replay record as it plays. On the next launch the engine rebuilds the
    trip by replaying it to the step it had reached, and the trip continues, paused (FR-070).
  - Resuming lands on the same state the player left, so killing the app can't be used to retry a
    stretch. Nothing is refunded: the trip's liter of fuel was spent on a trip that goes on
    (FR-071).
  - The engine needs no separate snapshot format, because the replay record is the checkpoint.
    Mobile §10's "checkpoint every station" is replaced by this.
- Q: What does short change cost? → A: Reputation only.
  - The passenger complains and reputation drops by the new tunable `rep_short_change` (default 5),
    as the product spec says.
  - It is not a mistake, so the third star is kept, as mobile §7.7 says. Topping up later is a valid
    way to play (FR-033).
- Q: Who gives back excess change? → A: Only the `honest` type, as the product spec's passenger
  table says («الأمين يرجّع الباقي الزيادة»).
  - Every other passenger keeps the excess without a word, and it comes off the earnings.
  - Over-change is a mistake either way (FR-034).
- Q: If the driver taps a passenger before their scheduled payment time, do they pay at once? → A:
  Yes. A tap asks for the fare, and the passenger pays then. `pays_at_seconds` is only when they
  would pay on their own, so collecting fares early is a legitimate skill (FR-031).
- Q: What happens when a passenger waiting for change runs out of patience? → A: Reputation drops
  once by `rep_impatient`, the passenger turns angry and loses any tip, and they keep waiting.
  Patience never refills and the penalty never repeats (FR-042).
- Q: When a passenger breaks a note for «حد معاه فكة؟», what comes back? → A: Larger notes plus a
  fixed 10 EGP of small change (500 + 100×4 + 50×2), so a break always helps (FR-051).
- Q: What does a failed trip pay if the player doesn't revive it? → A: Nothing. A failed or
  abandoned trip ends with 0 stars and 0 JENEHAT, so the revive stays meaningful and failing on
  purpose never earns anything (FR-058).
- Q: Once a sleeper has been woken, does he fall asleep again? → A: Yes. He stays awake for
  `trip_sleeper_awake_ms` (15 s), however he was woken, and then dozes off again. Waking him is a
  timing puzzle: too early and he is asleep again at his stop (FR-040).

## User Scenarios & Testing *(mandatory)*

The engine has no screen. Its users are:

- **The trip screen (M02)**, which sends the player's commands, advances time, and draws the
  engine's state and events.
- **The Python mirror and the solver (B05)**, which must reproduce every result the engine gives,
  and prove every authored trip can be played to 3 stars.
- **Result checks on the server**: the daily challenge (B08) replays a run to verify it, and the
  sync validators (B03) read the result.
- **Content authors**, whose trips the engine plays, and whose mistakes it refuses with a clear
  reason.

Players meet the engine only through the trip screen, but every rule here decides what they win or
lose.

Terms used throughout:

- **Logic step**: the engine's fixed 33 ms tick. The engine's clock counts steps; it never reads a
  real clock.
- **Params**: the tunable numbers a trip runs with (hop times, reputation changes and the rest,
  FR-067). They come from the app's config and are passed in.
- **Replay tuple**: `(definition, seed, params, command_log)`. It decides a trip's outcome
  completely.
- **Tray, hand, bundle**: the driver's change drawer; the money the driver is holding; and a bundle
  of money travelling between the driver and a passenger (a fare going forward, or change going
  back).
- **Owed**: a passenger whose fare has been sent and who is still due change.
- **Mistake**: anything that costs the third star (FR-058).

### User Story 1 - Play a basic trip from start to finish with commands (Priority: P1)

A caller starts a trip from a definition, a seed and params, and advances time step by step.
Passengers pay at their scheduled times, or when the driver taps them. Their fares travel seat by
seat to the driver and land in the tray. The caller builds change in the hand from the tray and
sends it to a passenger. The engine judges every delivery as exact, short or over. Stations arrive
on schedule, passengers get off thanked or in a fight, reputation moves, and when the last station
is reached the engine produces the trip's result: stars, earnings, fights, mistakes and lost fares.

This story covers the rules every trip uses: fares, the tray and the hand, the passing chain,
stations, getting off, reputation, stars and earnings, with `regular` and `honest` passengers.

**Why this priority**: Every other story builds on this loop, and M02 needs it before it can draw
anything.

**Independent Test**: Load the sample trip `line_hay.01` with its own seed and the default params.
Script a command log that collects each fare and returns exact change before each stop. The trip
finishes with 3 stars and the expected earnings. Change one delivery to give too much, and the
result has 2 stars and one mistake. Leave one passenger without their change, and that passenger
fights at their stop, the result has 1 star, and reputation drops by the fight penalty.

**Acceptance Scenarios**:

1. **Given** a passenger in row A whose fare is 700 piasters and who pays with a 1000 note, **When**
   the fare reaches the tray and the caller sends exactly 300 piasters, **Then** the passenger is
   settled, reputation rises by the exact-change reward (never above 100), and they get off thanked
   at their stop.
2. **Given** a passenger in row C, **When** they pay, **Then** the fare is passed through each
   occupied seat ahead of them in the same column, one hop at a time, skipping empty seats, and
   arrives in the tray; change sent back takes the same path in reverse.
3. **Given** a passenger who is still owed change, **When** the vehicle reaches their stop, **Then**
   they fight: reputation drops by the fight penalty, the fight count rises, and the second star is
   lost.
4. **Given** a passenger who has paid nothing by their stop, **When** the vehicle reaches it,
   **Then** they leave unpaid, the trip counts a lost fare, and that fare is not in the earnings.
5. **Given** an empty hand, a passenger who already got off, or a denomination the tray doesn't
   have, **When** the caller sends or picks, **Then** the command is rejected with a reason and
   nothing changes.
6. **Given** the last station is reached with reputation above zero, **When** the trip finishes,
   **Then** the result has 1 star, 2 with no fights, and 3 with no fights and no mistakes, and the
   earnings are the fares collected, minus change given away, plus tips, in whole pounds rounded
   down and capped by the trip's `max_earnings_jenehat`.

---

### User Story 2 - Replay a trip exactly and share parity fixtures (Priority: P2)

A caller records every accepted command with the logic step it applied at. Replaying the same
replay tuple, on any device and at any frame rate, gives the same result, the same sequence of
events and the same fingerprint of the command log. A set of parity fixtures in `fixtures/parity/`
pins the expected result of hand-written cases, and the Dart suite reproduces every one of them.
B05 later makes the Python mirror reproduce the same files.

**Why this priority**: Replay is what makes the solver, the daily challenge and share clips
possible (constitution I and III). B05 can't start without fixtures to match.

**Independent Test**: Run every fixture in `fixtures/parity/` through the engine. Each reproduces
its expected result exactly. Replay one fixture a thousand times, and with different step pacing
from the caller (one step per call, or many): the result and fingerprint never change. Change one
expected number in a fixture, and the suite fails, naming the fixture and the field.

**Acceptance Scenarios**:

1. **Given** a recorded trip, **When** its replay tuple is replayed, **Then** the result, the full
   event sequence and the command-log fingerprint are identical to the original run.
2. **Given** a command the engine rejected during play, **When** the trip is replayed, **Then** the
   rejected command is absent from the log and the replay is unaffected.
3. **Given** the parity fixtures, **When** CI runs, **Then** every fixture passes the trip schema
   and reproduces its expected result, and any mismatch fails CI.
4. **Given** a change to an engine rule, a default param or how randomness is used, **When** it is
   proposed without updated fixtures, **Then** CI fails.

---

### User Story 3 - The line_hay passenger types and patience (Priority: P3)

The first line teaches the basics with three passenger types on top of the regular one: the hajja
(«الحاجة») pays with lots of coins and passes money slowly; the sleeper («النايم») blocks the
passing chain and misses his stop unless woken at the right time; the hurried passenger
(«المستعجل») runs out of patience fast. Every passenger who is kept waiting for change loses
patience, and a passenger who runs out costs reputation.

**Why this priority**: `line_hay` is the tutorial and first line of the MVP (20 trips), so these
types are in the first playable trip (step 5).

**Independent Test**: A fixture per type. The hajja's coins land in the tray and a bundle she
passes takes twice the hop time. A sleeper in row B holds a fare from row C until woken; woken too
early, he falls asleep again and misses his stop. A hurried passenger kept waiting runs out of
patience in half the time of a regular one, and reputation drops once.

**Acceptance Scenarios**:

1. **Given** a bundle passing through a seat held by an awake hajja, **When** she passes it on,
   **Then** that hop lasts the hajja hop length (twice the line's hop by default).
2. **Given** a sleeper between a passenger and the driver, **When** money reaches his seat, **Then**
   it waits there, blocked, and moves on as soon as he is awake.
3. **Given** a sleeper is tapped, **When** the wake time passes, **Then** he is awake for the
   sleeper's awake time and then falls asleep again.
4. **Given** a sleeper is asleep when the vehicle reaches his stop, **When** the stop is processed,
   **Then** he misses it: reputation drops by the missed-stop penalty, and change he was still owed
   counts as a mistake.
5. **Given** a passenger owed change who has waited their full patience, **When** patience runs
   out, **Then** reputation drops once by the impatience penalty and the engine says so; a hurried
   passenger runs out after half the time.

---

### User Story 4 - The line_gamaa passenger types (Priority: P4)

The second line adds six types: the big-note effendi («الأفندي أبو ٢٠٠»), the student who pays
half («الطالب»), the passenger in headphones who must be called twice («أبو سمّاعة»), the false
claimer who says he already paid («أنا دافع!»), the group payer who pays for friends
(«خلّيها عليّا»), and the chatty passenger who slows his row («الرغّاي»). The regular customer
(«الزبون الدايم») tips when he is happy.

**Why this priority**: `line_gamaa` is the second MVP line (30 trips). It comes after the basics
because each of these types is a twist on them.

**Independent Test**: A fixture per type. A student on an 850 fare with a 50% discount owes 450. A
passenger in headphones blocks money until tapped twice and is attentive for 15 s. A false claimer
caught lying raises reputation and then pays; one who is believed never pays. A group payer's
change is computed for the whole group, and change sent to a group member goes on to the payer.

**Acceptance Scenarios**:

1. **Given** a student and a trip with a student discount, **When** their fare is computed,
   **Then** it is the station fare reduced by the discount and rounded up to a multiple of 50.
2. **Given** a passenger in headphones, **When** they are tapped once, **Then** nothing happens;
   **When** tapped a second time, **Then** they become attentive for the attentive time, during
   which money passes them and asks reach them, and then they put the headphones back on.
3. **Given** a false claimer whose payment time comes, **When** they claim to have paid instead,
   **Then** the caller can insist (the liar is caught, reputation rises, and they pay) or accept
   (they never pay, and their fare is lost at their stop).
4. **Given** a passenger who really did send their fare, **When** the driver taps them again,
   **Then** they say they paid; insisting is a false accusation: reputation drops and it counts as a
   fight.
5. **Given** a group payer paying 5000 for a group of 3 to an 850 stop, **When** the fare arrives,
   **Then** they are owed 2450, and change sent to any member of the group goes on to the payer
   with a fast hop.
6. **Given** an awake chatty passenger, **When** money passes through a seat in their row, **Then**
   that hop takes the chatty-row hop length.
7. **Given** a regular customer who gets off thanked and never ran out of patience, **When** they
   get off, **Then** their tip is added to the trip's tips.

---

### User Story 5 - The eight in-trip events (Priority: P5)

A trip can schedule any of the glossary's eight events («الأحداث داخل المشوار»): a bump drops the
money in transit; traffic delays the stations and wears down patience; an open road brings the
stations closer; the fare goes up mid-line; a passenger asks to be dropped here; two passengers
argue about who paid; a passenger asks the driver to break a big note; a passenger flags the
vehicle down and boards.

**Why this priority**: Events keep the same line from feeling repetitive, but every one of them
builds on stories 1 to 4.

**Independent Test**: A fixture per event, each showing its effect and the player's possible
answers. For example: after a bump, a dropped fare picked up within 3 s lands in the tray, and one
left on the floor is lost while its passenger is still owed change.

**Acceptance Scenarios**:

1. **Given** bundles in transit, **When** a bump happens, **Then** each falls to the floor; one
   picked up within the pick-up time goes into the tray (a fare counts as arrived), and one left
   longer is lost.
2. **Given** traffic of 10 s, **When** it starts, **Then** the next station and every later one
   arrive 10 s later, and patience drains faster until the next station.
3. **Given** an open road of 10 s, **When** it starts, **Then** the next station and every later one
   arrive 10 s sooner, but never sooner than the station warning time from now.
4. **Given** a fare increase, **When** listed passengers pay afterwards at the old fare, **Then**
   they still owe the difference and pay it when the driver taps them; whatever they still owe at
   their stop is lost from the earnings.
5. **Given** "drop me here", **When** it happens, **Then** that passenger now gets off at the time
   the event gives, and everything that normally happens at a stop happens then.
6. **Given** a payment dispute between two passengers, **When** the caller names the one who paid,
   **Then** the answer is right only if that one has sent their fare and the other hasn't: the
   other pays and the liar is caught. Any other answer is a false accusation.
7. **Given** a passenger asking to break a note, **When** the caller agrees and the tray holds
   smaller money of the same total, **Then** that money goes to the passenger and the note comes
   back, both through the chain; **When** the caller declines, or never answers before the
   passenger's stop, **Then** reputation drops by the decline penalty.
8. **Given** a roadside pickup, **When** it happens, **Then** the listed passengers board into
   their seats, or as soon as those seats are free.

---

### User Story 6 - Player aids, failing and reviving (Priority: P6)

The player has help when the puzzle gets tight: asking the passengers to break a note («حد معاه
فكة؟», twice per trip at most), the four in-trip boosters (change bag, wake all, the ledger, traffic
jam), and a one-second undo after a send. When reputation runs out the trip fails, and the player
can revive it once and carry on from the same point. The player can also pause, or abandon the
trip. A story trip can require no fights at all («أبو العروسة راكب»), and the first fight then fails
it for good.

**Why this priority**: These are offers around the core puzzle, never the puzzle itself. They
matter for monetization (M11, M12) but come after the rules they help with.

**Independent Test**: A fixture per aid and per ending. A break request on a 10000 note takes
1.5 s, leaves the tray total unchanged, and a third request is rejected. The change bag adds
50×2, 100×3 and 500×2. A failed trip revived goes on at 40 reputation, and a second revive is
rejected. An abandoned trip ends with 0 stars and no earnings.

**Acceptance Scenarios**:

1. **Given** a note of 1000 piasters or more in the tray and break requests left, **When** the
   caller asks for a break, **Then** after the break delay the note leaves the tray and the same
   total comes back as FR-051's table says (a 1000 note as 500 + 100×4 + 50×2); a request beyond
   the trip's limit, or for a smaller note, is rejected.
2. **Given** each booster, **When** it is used, **Then** change bag adds its coins, wake all wakes
   every sleeper at once, the ledger shows who has paid for its duration, and traffic jam delays
   the next station and every later one by its time, up to its limit per trip; each use is recorded
   in the result.
3. **Given** a send within the undo window whose bundle is still on its first hop, **When** the
   caller undoes it, **Then** the bundle is back in the hand; after the window or the first hop,
   undo is rejected.
4. **Given** reputation reaches zero, **When** it happens, **Then** the trip fails, time stops, and
   the engine reports what cost the reputation.
5. **Given** a failed trip that hasn't been revived, **When** the caller revives it, **Then**
   reputation is set to the revive level and the trip continues from the same point; the result
   records the revive. A second revive, or a revive of a story trip failed by a fight, is rejected.
6. **Given** a paused trip, **When** time is advanced, **Then** nothing moves; only answers to open
   choices, boosters and abandoning are accepted while paused.

---

### User Story 7 - Resume a trip after the app is killed (Priority: P7)

The phone rings, the app goes to the background, and the system kills it mid-trip. When the player
opens the app again, the trip comes back exactly as they left it, paused, with the same passengers,
money in the same hands, the same reputation and the same time to the next station. They carry on
from there.

**Why this priority**: It is rare, but losing a nearly finished trip, or a liter of fuel, to a
phone call feels unfair. Resuming exactly also means killing the app is never a way to retry.

**Independent Test**: Cut a recorded run at any step. Rebuild the trip from its replay record at
that step, and continue with the rest of the commands: the result and the fingerprint are identical
to the uninterrupted run's. Rebuild a trip that was failed, or paused, when it was cut, and it comes
back failed, or paused.

**Acceptance Scenarios**:

1. **Given** a replay record and the step a trip had reached, **When** the trip is rebuilt from
   them, **Then** its state is identical to the state at that step in the original run, and it is
   paused.
2. **Given** a rebuilt trip, **When** it continues with the same remaining commands, **Then** it
   ends with the same result as the uninterrupted run.
3. **Given** a trip that had failed and was showing the failure choices when it was killed, **When**
   it is rebuilt, **Then** it is still failed, and the revive is still available if it was before.
4. **Given** the longest allowed trip, **When** it is rebuilt at its last step, **Then** rebuilding
   takes no longer than a full replay (SC-004).

---

### Edge Cases

- **Two bundles to the same passenger**: each is judged on arrival, in arrival order, against what
  the passenger is still owed at that moment.
- **Change sent before the fare arrives**: if the fare has been sent, the change is judged against
  what the passenger is owed once it arrives. If no fare has been sent, it is a mistake (FR-033).
- **A bundle whose passenger gets off before it arrives** goes back to the tray. At the end of the
  trip, fares still on their way count as arrived and change still on its way goes back to the
  tray (FR-024).
- **A blocker who gets off** unblocks the chain at once.
- **Several stations' worth of shifts**: traffic, open road and traffic jam add up; stations stay in
  order and the next station never comes sooner than the warning time from now (FR-012).
- **A roadside or station boarder whose seat is still taken** boards as soon as it is free.
- **A sleeper or muted passenger whose payment time comes** pays as soon as they can act.
- **An open choice when its passenger gets off**: an unanswered claim counts as accepted, an
  unanswered dispute is dropped with no effect, and an unanswered break request counts as declined.
- **The trip fails while bundles are in transit**: time stops with them in place; a revive carries
  on from there.
- **An answer given while paused ends the trip** (a false accusation in a no-fights trip, or a
  penalty that takes the last of the reputation): the trip fails at once, without waiting for time
  to move (FR-056). A replay, which never pauses, fails it at the same moment.
- **Abandoning a failed trip** ends it with the failure's result (0 stars, no earnings).
- **A player who taps wildly**: rejected commands are not recorded. Accepted commands per trip are
  capped so the log always fits the server's 64 KB limit (backend §16); beyond the cap, commands are
  rejected and the trip goes on, except `Abandon`, so the player can always leave (FR-055).
- **Reputation at the cap**: rewards never take it above 100; penalties can take it below zero
  only to fail the trip, and it is reported as 0.
- **Discount rounding**: a 50% discount on 850 gives 450 (rounded up to the next 50).
- **Unsupported content**: a trip that uses a phase 2 or 3 passenger type, or an event without the
  parameter it needs, is refused at start with the reason, never played half-way (FR-003).
- **Earnings below zero** (more change given away than fares collected) give 0 JENEHAT, never a
  negative amount.
- **Killed before the last command was saved**: the trip resumes from the last saved step, without
  that command. A record that doesn't replay cleanly is refused, and the app ends that trip as
  abandoned (FR-070).

## Requirements *(mandatory)*

### Functional Requirements

#### Starting a trip

- **FR-001**: The engine MUST start a trip from the replay tuple's first three parts only: a trip
  definition (the generated app model of `trip.schema.json`, constitution VII), a seed, and the
  params. No other input may affect a trip: no real clock, no device randomness, no files, no
  network (constitution I).
- **FR-002**: The seed MUST default to the definition's own `seed`. A caller such as the daily
  challenge (B08) MAY supply another.
- **FR-003**: The engine MUST refuse to start an inconsistent or unsupported trip, with a reason
  naming the field. That includes:
  - a reference to a seat, station or passenger the trip doesn't have;
  - a group whose listed members disagree with its size;
  - a passenger type or event outside the supported set (FR-004);
  - an event missing a parameter its rule needs (FR-040 to FR-047).

  It MUST never crash or play a refused trip part-way.
- **FR-004**: The supported set MUST be the MVP's:
  - passenger types `regular`, `honest`, `hajja`, `sleeper`, `hurry`, `big_note`, `student`,
    `headphones`, `false_claimer`, `group_payer`, `chatty` and `regular_customer`;
  - all eight events of glossary §3.6.

  The other six passenger types (`money_changer`, `bags_lady`, `dodger`, `mother_kids`, `big_family`,
  `traveler`) belong to the phase 2 and 3 lines. They are refused until the feature that adds their
  line implements them.

#### Time and stations

- **FR-010**: Time MUST advance only in fixed logic steps of 33 ms, driven by the caller. How often
  or how many steps the caller advances at once MUST NOT change the outcome.
- **FR-011**: The work inside one step MUST follow one fixed order, written down for the mirror:
  scheduled passenger actions, then money movement, then money arrivals, then station warnings,
  then station arrivals, then reputation, then the end-of-trip check (mobile §7.3).
- **FR-012**: Stations MUST arrive at their scheduled times, shifted by traffic, open road and the
  traffic-jam booster. A shift moves the next station and every later one by the same amount.
  Stations stay in order, and the next station never comes sooner than `trip_station_warning_ms`
  from now.
- **FR-013**: The engine MUST warn `trip_station_warning_ms` before each station, naming who gets
  off there and which of them are still owed change. The trip screen uses this for the countdown,
  the passenger's «على جنب يا أسطى!» and the hints (FR-063).
- **FR-014**: At a station, the passengers whose stop it is MUST get off first (FR-024), then the
  passengers who board there take their seats. The trip finishes when the last station has been
  processed.

#### The tray, the hand and the passing chain

- **FR-020**: All money MUST be integer piasters, in glossary §3.2 denominations only (constitution
  II). The tray starts as `initial_tray`, and every piece of money that reaches the driver goes into
  it.
- **FR-021**: The caller MUST be able to pick one piece of a denomination from the tray into the
  hand, put the whole hand back, and send the whole hand to a passenger as one bundle. Picking a
  denomination the tray doesn't have, sending an empty hand, or sending to a passenger who isn't
  aboard is rejected.
- **FR-022**: Money MUST move hop by hop. Seats in the front row and row A are one hop from the
  driver. Money for a seat further back passes through each occupied seat ahead of it in the same
  column, one hop per seat; empty seats are skipped. Fares travel forward along the same path.
- **FR-023**: A hop MUST last `trip_hop_ms_<line_id>`. It lasts `trip_hop_pct_hajja` percent of that
  when a hajja passes it on, and `trip_hop_pct_chatty_row` percent when it leaves a seat in
  the same row as an awake chatty passenger.
- **FR-024**: A sleeping or muted passenger MUST block money that has to pass their seat or is
  addressed to them. It waits at the previous holder and moves on as soon as they are awake or
  attentive. Money addressed to a passenger who gets off before it arrives goes back to the tray.
  When the trip ends, fares still on their way count as arrived, and change still on its way goes
  back to the tray.
- **FR-025**: The caller MUST be able to undo the most recent send within `trip_undo_window_ms` of
  logic time while its bundle is still on its first hop. The bundle returns to the hand. Any other
  undo is rejected.

#### Fares and change

- **FR-030**: A passenger's fare MUST be the fare of their destination station.
  - A student's fare is reduced by the trip's `student_discount_pct` and rounded up to a multiple of
    50 piasters.
  - A group payer pays for `group_size` people: their own fare, plus each listed member's own fare,
    plus the payer's fare for each member who isn't listed.
- **FR-031**: A passenger MUST pay the first time the driver taps them for the fare, or at
  `pays_at_seconds` if that comes first. A passenger with no `pays_at_seconds` pays only when
  tapped. They hand over exactly their authored `payment`, which travels to the driver as a fare. A
  passenger who is asleep or muted when their time comes pays as soon as they can act. A false
  claimer claims instead of paying (FR-041).
- **FR-032**: Once a passenger's fare has been sent, they MUST be owed the payment minus the fare
  when that is positive. When it is negative, they owe the rest, and pay it when the driver taps
  them.
- **FR-033**: Change reaching its passenger MUST be judged against what they are owed:
  - **exact**: they are settled, and reputation rises by `rep_exact_change`, never above 100;
  - **short**: what they are owed drops by the amount, the passenger complains, and reputation drops
    by `rep_short_change`. It is not a mistake, so a later top-up that settles them still counts as
    exact;
  - **over**: a mistake of kind "over", and the excess is handled as FR-034 says;
  - **not owed**: change to a passenger who hasn't sent a fare or is owed nothing is a mistake, and
    the whole amount is excess.
- **FR-034**: Only an `honest` passenger MUST give excess change back (product spec «أنواع الركاب»).
  It travels back into the tray and costs nothing but the mistake. Every other passenger keeps it
  without a word, and it counts in `overpaid_piasters`, which is taken off the earnings.
- **FR-035**: Change sent to a group member who didn't pay MUST go on to the group's payer with a
  fast hop of `trip_group_redirect_hop_ms`.

#### Getting off

- **FR-036**: At their stop, a passenger MUST get off with one outcome:
  - **thanked**: settled and owing nothing;
  - **fight**: still owed change; reputation drops by `rep_fight`, the fight count rises, and the
    unreturned change is a mistake;
  - **left unpaid**: their fare was never sent; the trip counts a lost fare;
  - **missed stop**: asleep at that moment; reputation drops by `rep_missed_stop`. Change they were
    still owed is a mistake, and a fare never sent is a lost fare. A missed stop is not a fight.

  A passenger who still owes part of their fare (FR-032) leaves without it, and that part is
  missing from the earnings.

#### Passenger types

- **FR-040**: Each supported type MUST follow its rule:
  - `regular`: pays the authored payment (exact or a bigger note), and keeps excess (FR-034).
  - `honest`: returns excess and change it wasn't owed, and says so («إديتني زيادة يا أسطى»).
  - `hajja`: pays the authored coins; hops she passes on take longer (FR-023).
  - `sleeper`: asleep from boarding. A tap wakes him after `trip_wake_ms`, and `wake_all` wakes him
    at once. Either way he stays awake for `trip_sleeper_awake_ms` and then falls asleep again,
    whether or not he is settled.
  - `hurry`: his patience is `trip_patience_pct_hurry` percent of the normal amount.
  - `big_note`: no rule of its own; the authored payment is a big note on a small fare.
  - `student`: pays the discounted fare (FR-030).
  - `headphones`: muted from boarding, and doesn't hear taps that ask for the fare. The second tap
    while muted makes them attentive for `trip_headphones_attentive_ms`; then they are muted again.
  - `false_claimer`: when their payment time comes or the driver taps them for the fare, they claim
    to have paid instead (FR-041).
  - `group_payer`: pays for the group (FR-030), and receives the group's change (FR-035).
  - `chatty`: while awake, slows hops leaving seats in their row (FR-023).
  - `regular_customer`: behaves as `regular`. When he gets off thanked and never ran out of
    patience, he adds `trip_tip_piasters_regular_customer` to the trip's tips.
- **FR-041**: Claims of having paid MUST work the same for every passenger. A false claimer claims
  instead of paying. Any passenger who has already sent their fare claims it when tapped for the
  fare. The caller answers once:
  - **insist** against a false claimer: the liar is caught. Reputation rises by `rep_liar_caught`,
    `caught_liars` rises, and they pay.
  - **insist** against a passenger who did pay: a false accusation. Reputation drops by
    `rep_false_accusation`, and it counts as a fight.
  - **accept**: nothing more happens. A believed false claimer never pays, and their fare is lost
    at their stop.
- **FR-042**: Patience MUST drain while a passenger is owed change, starting from
  `trip_patience_ms` (scaled for `hurry`). It drains `trip_patience_drain_pct_traffic` percent as
  fast during traffic. When it runs out, reputation drops once by `rep_impatient`, the engine
  reports it, the passenger turns angry and loses any tip, and they stay aboard waiting as before.
  Patience never refills, and the penalty never repeats for that passenger.

#### Events

- **FR-045**: Each event MUST fire at its `at_seconds` and follow its rule:
  - `bump`: every bundle in transit falls to the floor. The caller can pick each one up within
    `trip_bump_collect_ms`. A picked-up bundle goes into the tray, and a fare counts as arrived. A
    dropped fare left on the floor is lost: its passenger has paid and is still owed change, but the
    fare is missing from the earnings. Dropped change left on the floor is gone, and its passenger is
    still owed.
  - `traffic`: the next station and every later one arrive `seconds` later, and patience drains
    faster until the next station.
  - `open_road`: the next station and every later one arrive `seconds` sooner (FR-012).
  - `fare_increase`: fares not yet sent rise by `amount_piasters`. The listed passengers pay as if
    the fare hadn't changed, so they may owe the difference (FR-032).
  - `drop_me_here`: the listed passenger now gets off `seconds` after the event, or after
    `trip_station_warning_ms` when `seconds` is absent. Everything that happens at a stop happens
    then.
  - `payment_dispute`: the two listed passengers each say the other hasn't paid. The caller names
    the one who paid. The answer is right only if that passenger has sent their fare and the other
    hasn't. Then the other pays and the liar is caught (FR-041). Any other answer is a false
    accusation.
  - `change_request`: the listed passenger asks to break a note of `amount_piasters`. If the caller
    agrees, smaller money of the same total, chosen from the tray by a fixed rule, goes to the
    passenger and the note comes back, both through the chain. Agreeing is rejected when the tray
    can't make the total. Declining costs `rep_change_request_declined`.
  - `roadside_pickup`: the listed passengers board at that moment, each into their seat as soon as
    it is free.
- **FR-046**: Passengers with a `board_station_id` MUST board at that station (FR-014).
- **FR-047**: An open choice (a claim, a dispute or a break request) MUST resolve by itself when
  one of its passengers gets off: a claim counts as accepted, a dispute is dropped with no effect,
  and a break request counts as declined.

#### Commands and aids

- **FR-050**: The engine MUST accept these commands (mobile §7.4, extended):
  - pick from tray, return hand, send hand, undo last send (FR-021, FR-025);
  - tap a passenger: ask for the fare, wake a sleeper, call a muted passenger, or draw a claim
    (FR-041);
  - resolve a claim, resolve a dispute, and resolve a break request;
  - ask for a break, pick up dropped money, use a booster, revive, and abandon.

  Every command is applied at a logic step. A rejected command leaves the trip unchanged, returns
  its reason, and is not recorded.
- **FR-051**: Asking for a break («حد معاه فكة؟») MUST take a note of at least
  `trip_break_min_piasters` from the tray. After `trip_break_delay_ms`, the same total comes back
  into the tray as larger notes plus a fixed 10 EGP of small change (500 + 100×4 + 50×2):

  | Note | Comes back as |
  | --- | --- |
  | 1000 | 500 + 100×4 + 50×2 |
  | 2000 | 1000 + 500 + 100×4 + 50×2 |
  | 5000 | 2000×2 + 500 + 100×4 + 50×2 |
  | 10000 | 5000 + 2000×2 + 500 + 100×4 + 50×2 |
  | 20000 | 10000 + 5000 + 2000×2 + 500 + 100×4 + 50×2 |

  A request beyond the trip's `max_break_requests`, or for a note the tray doesn't have, is rejected.
- **FR-052**: The in-trip boosters (glossary §3.3) MUST work as follows:
  - `change_bag` adds 50×2, 100×3 and 500×2 to the tray;
  - `wake_all` wakes every sleeper at once;
  - `ledger_peek` makes who has and hasn't paid readable for `booster_ledger_peek_ms`;
  - `traffic_jam` delays the next station and every later one by `booster_traffic_jam_ms`, at most
    `booster_traffic_jam_max_per_trip` times per trip. A further use is rejected. The limit keeps
    every trip short enough to replay quickly, on the device and on the server (SC-004).

  The engine records each use in the result. It does not check the player's stock, prices or ad
  caps; the app and the server do (constitution IV, IX).
- **FR-053**: A failed trip MUST be revivable once. Reputation is set to `rep_revive_to`, the trip
  continues from the same point, and the result records the revive. A second revive is rejected,
  and so is a revive of a story trip failed by a fight (FR-057).
- **FR-054**: Pausing MUST freeze the trip's clock without affecting its outcome. While paused, only
  answers to open choices, boosters and abandoning are accepted. The app pauses on leaving the app
  and on any overlay, and before any ad (constitution IX).
- **FR-055**: Accepted commands per trip MUST be capped, so the recorded log of the longest possible
  trip always fits the server's 64 KB limit for a command log. Beyond the cap, commands are rejected
  and the trip goes on. `Abandon` is exempt, so a player can always leave a trip; since it ends the
  trip, a log holds at most one entry past the cap (owner decision, 2026-10-20).

#### Reputation, failing, stars and earnings

- **FR-056**: Reputation MUST start at 100 and stay within 0 to 100. When it reaches 0, the trip
  fails at once (also when an answer given while paused caused it), time stops, and the engine
  reports the failure with a breakdown of what cost the reputation (fights, false accusations,
  missed stops, short change, impatience, declined requests).
  The failure card shows it («إيه اللي ضيّع السمعة»).
- **FR-057**: A trip MUST be able to require no fights (a story trip such as «أبو العروسة راكب»).
  In such a trip, the first fight fails it at once, even while paused, and it can't be revived.
- **FR-058**: The result MUST give:
  - **outcome**: finished, failed or abandoned;
  - **stars**: 1 for finished, 2 for finished with no fights, 3 for finished with no fights and no
    mistakes, and 0 for failed or abandoned;
  - **earnings** (finished only): the fares collected, minus `overpaid_piasters`, plus tips, in
    whole pounds rounded down, never below 0, and capped by `max_earnings_jenehat` (constitution
    II). Failed and abandoned trips earn nothing.
  - **the rest of mobile §7.2's `TripResult`**: fights, the mistakes list (each with its passenger,
    kind and amount, so the result screen can say exactly where it went wrong), lost fares, the
    duration in logic time, the boosters used, whether it was revived, and the command-log
    fingerprint;
  - the counters (caught liars, tips, overpaid piasters, missed stops, impatient passengers) and the
    reputation breakdown.

  "Fares collected" is, for each passenger whose fare reached the driver, their fare minus any part
  of it they never paid.

#### Determinism, replay and parity

- **FR-060**: The only source of randomness MUST be a PRNG seeded from the trip's seed (`xorshift32`,
  constitution I), drawn in an order the mirror can reproduce. Everything else is integer
  arithmetic.
- **FR-061**: The engine MUST record each accepted command with the logic step it applied at. The
  replay tuple MUST replay to the same result, the same event sequence and the same command-log
  fingerprint, whatever the caller's step pacing.
- **FR-062**: Parity fixtures MUST be added in `fixtures/parity/`, each in the form
  `{definition, seed, params, command_log, expected_result}` (constitution III). There MUST be at
  least one for:
  - each supported passenger type, event, command and booster;
  - each ending: 3, 2 and 1 stars, failed, revived and abandoned;
  - each sample-pack trip, played to 3 stars.

  Every fixture's definition MUST pass the trip schema. The Dart suite MUST reproduce every fixture,
  and CI MUST fail on any mismatch.
- **FR-063**: The rules MUST be written down as a reference precise enough for B05 to mirror them:
  every rule above, every default, the order of work in a step, the break-down table (FR-051), the
  rule that picks the tray's pieces for a change request (FR-045), how randomness is drawn, and the
  fingerprint.

#### Speech

- **FR-064**: The engine MUST emit only speech keys, never text (constitution VII, XII). Every key
  it can emit MUST be in one published, machine-readable list. A passenger's `speech_keys` overrides
  the key for that speech slot.
- **FR-065**: Every speech the engine emits MUST carry a variant number drawn from the trip's seed,
  so the app shows the same line on every replay.
- **FR-066**: Content validation MUST check that every key in that list, and every key a passenger
  overrides, has a speech pool in the pack (B04 hand-over). It MUST also check that every event has
  the parameters its rule needs, so authors see the problem before a build, not only when the engine
  refuses the trip.

#### Params and tunables

- **FR-067**: Every number in the rules MUST come from the params, never from a constant in code
  (constitution VIII). That covers the existing keys (`trip_hop_ms_<line_id>`,
  `trip_undo_window_ms`, the six `rep_*` keys) and these new ones, with their bundled defaults:

  | Key | Default | Rule |
  | --- | --- | --- |
  | `trip_station_warning_ms` | 8000 | FR-012, FR-013 |
  | `trip_hop_pct_hajja` | 200 | FR-023 |
  | `trip_hop_pct_chatty_row` | 150 | FR-023 |
  | `trip_group_redirect_hop_ms` | 600 | FR-035 |
  | `trip_wake_ms` | 1000 | FR-040 |
  | `trip_sleeper_awake_ms` | 15000 | FR-040 |
  | `trip_headphones_attentive_ms` | 15000 | FR-040 |
  | `trip_patience_ms` | 20000 | FR-042 |
  | `trip_patience_pct_hurry` | 50 | FR-042 |
  | `trip_patience_drain_pct_traffic` | 150 | FR-042 |
  | `trip_bump_collect_ms` | 3000 | FR-045 |
  | `trip_break_min_piasters` | 1000 | FR-051 |
  | `trip_break_delay_ms` | 1500 | FR-051 |
  | `trip_tip_piasters_regular_customer` | 200 | FR-040 |
  | `booster_ledger_peek_ms` | 10000 | FR-052 |
  | `booster_traffic_jam_ms` | 10000 | FR-052 |
  | `booster_traffic_jam_max_per_trip` | 3 | FR-052 |
  | `rep_short_change` | 5 | FR-033 |
  | `rep_impatient` | 5 | FR-042 |
  | `rep_change_request_declined` | 5 | FR-045 |

  Two keys have hard upper bounds, so the longest trip stays bounded however they are tuned:
  `booster_traffic_jam_ms` at most 60000, and `booster_traffic_jam_max_per_trip` at most 5. Params
  outside their bounds are refused at start. The params are part of every replay tuple and every
  fixture.
- **FR-068**: The new keys MUST be added in this feature to mobile §14.3, the app's tunables registry
  and its bundled defaults. The defaults test MUST cover them.
- **FR-069**: The boolean `trip_hints_enabled_<line_id>` MUST become `trip_hints_mode_<line_id>`,
  with the values `off`, `first_time` and `always`. The defaults are `always` for `line_hay`,
  `first_time` for `line_gamaa`, and `off` for the other lines (ux-spec «الصعوبة والمساعدة حسب
  الخط»). The change MUST be made in mobile §14.3, the app's registry and its bundled defaults
  together. Hints don't change outcomes, so the engine doesn't read this key; FR-013 gives the hints
  what they need.

#### Resuming a killed trip

- **FR-070**: A trip killed mid-way MUST resume exactly where it stopped (mobile §24.4, resolved).
  - The engine MUST give, at any moment, a self-contained replay record: the replay tuple plus the
    logic step reached. The full definition is included, so the record doesn't depend on a content
    pack that may have been swapped since.
  - The engine MUST be able to rebuild a trip from that record. It replays to that step without
    emitting the replayed events to the trip screen, and leaves the trip paused. A trip that was
    failed comes back failed, with the revive still available if it was before.
  - Rebuilding from a record that doesn't replay cleanly (a command rejected on replay, or a step
    before the last command) MUST be refused with a reason. The app then ends that trip as abandoned.
  - The app saves the record on every accepted command and on every pause, so a kill loses at most
    the time since the last save. Storing the record and offering the resumed trip belong to M02.
- **FR-071**: A resumed trip MUST NOT spend or refund fuel. Its liter was spent when it started, and
  the trip goes on.

#### Boundaries and documents

- **FR-072**: The engine MUST run with nothing but the language's standard library and the generated
  content models: no app, no device, no plugin (constitution I). Callers read its state but can
  change it only through commands.
- **FR-073**: The trip schema MUST gain what these rules need, within B04's restricted profile, and
  only while no pack has been promoted to production (B04 FR-010). That includes the no-fights
  condition of FR-057. The generated models, the sample pack and its golden checksums are updated
  in the same change.
- **FR-074**: Mobile §7 MUST be updated in the same change to match this feature: the commands, the
  events, the result's fields and the rules. Mobile §10's checkpoint sentence is replaced by FR-070,
  §14.3 is updated per FR-068 and FR-069, and §24.4 is marked resolved.

### Key Entities

- **Trip definition**: one authored trip, read from the generated app model of
  `trip.schema.json`: stations with times and fares, seats, passengers, events, starting tray,
  rules, star rules, the earnings cap and the seed.
- **Params**: the tunable numbers the trip runs with (FR-067). They are part of the replay tuple.
- **Trip state**: the clock in logic steps, the tray, the hand, the bundles in transit, every
  passenger's state, reputation, the counters, open choices, active boosters, and the status
  (running, paused, failed, finished or abandoned).
- **Passenger state**: aboard or not, seat, awake, asleep, muted or attentive, fare not sent, sent,
  arrived or lost, what they are owed or still owe, patience, and their outcome once they are off.
- **Bundle**: money in transit: its pieces, its kind (fare, change, returned excess, group
  redirect, break), its path of seats, its position along the current hop, and whether it is
  blocked or on the floor.
- **Command and command log**: a player intent with its arguments, and the record of every
  accepted command with its logic step.
- **Event**: what the engine reports to the trip screen and analytics, with the speech key and
  variant when a passenger speaks (mobile §7.5, extended).
- **Trip result**: the outcome, stars, earnings and everything else in FR-058.
- **Parity fixture**: one replay tuple with its expected result, shared with the mirror.
- **Speech key list**: every key the engine can emit, read by content validation.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of the parity fixtures reproduce their expected result. Replaying any fixture
  1,000 times, with any step pacing, never changes its result or fingerprint.
- **SC-002**: The fixtures cover all 12 supported passenger types, all 8 events, every command, all
  4 in-trip boosters and all 6 endings (3, 2 and 1 stars, failed, revived and abandoned), and each
  sample-pack trip is played to 3 stars.
- **SC-003**: The engine reaches at least 90% line coverage (constitution XIII).
- **SC-004**: Replaying the longest allowed trip takes under 1 s on the CI runner. That trip has a
  full vehicle and the maximum number of commands, and lasts 1,500 s: stations up to 600 s, delayed
  by 10 traffic events of 60 s and 5 traffic jams of 60 s (the bounds of FR-052 and FR-067). That
  leaves the trip screen ample room within each 33 ms step on the reference phone.
- **SC-005**: The command log of that longest trip fits within 64 KB.
- **SC-006**: The engine's test suite passes in a plain environment, with no app, device, network
  or real clock.
- **SC-007**: A guard test finds no non-integer money value anywhere in the engine (constitution
  II).
- **SC-008**: A developer can play every sample-pack trip end to end using only commands, and read
  everything the trip screen needs (positions, blocks, warnings, speech, outcomes) from the state
  and events, with no rule code outside the engine.
- **SC-009**: Every fixture, cut at 10 evenly spaced steps and rebuilt from its replay record at
  each one, gives a state identical to the uninterrupted run at that step, and the same final
  result.

## Assumptions

- **Where the sources disagree**:
  - **The ledger** lasts 10 s, as glossary §3.3 and the product spec say. The ux-spec says 5 s. It
    is a tunable either way (`booster_ledger_peek_ms`).
  - **Rerouting money around a blocker** («تلف الفلوس من الكرسي اللي جنبه», product spec) is not a
    command. The ux-spec's interactions table and mobile §7.4 have none. Blockers are cleared by
    waking or calling, or with `wake_all`.
  - **Telling a passenger to wait** («استنى») is simply not sending change yet: their patience
    drains (FR-042).
- **Defaults this feature sets** (to revisit after playtests; their numbers are tunables):
  - **Patience** drains only while change is owed. The sources name patience but give it no
    numbers. What happens when it runs out was settled in Clarifications.
  - **Tips** come only from the regular customer («يدّي بقشيش»). A future type can add its own.
  - **The student discount** rounds up to the next 50 piasters, since 4.25 EGP can't be paid in
    coins.
  - **The regular customer's** «بعد سمعة معينة» (after a certain reputation) is where authors place
    him, across the player's progress, not an engine rule.
  - **The traffic-jam limit** (3 per trip, never above 5) bounds the longest trip for replay. The ad
    placement has its own cap of 1 per trip (glossary §3.4), so further uses come from BONAT.
- **Choices during a trip**: whether the trip screen pauses while a claim, dispute or break request
  is open is M02's decision (ux-spec: «كل نافذة بتوقف الوقت»). The engine accepts the answers either
  way (FR-054).
- **Story trips**: the characters who comment on mistakes, and the decorated vehicle, belong to M02
  and M10. The engine's part is the no-fights condition (FR-057) and the mistake events the
  comments hang on.
- **Out of scope**:
  - the trip screen, scene, HUD, hints and «آخر كلام» (M02);
  - the Python mirror, the solver and difficulty scoring (B05);
  - the fuel spend, the `trip_start` and `trip_result` sync ops, and where the result is stored
    (M05, M06, B03);
  - booster stock, prices and ad caps (M05, M11, M12, B07);
  - analytics events (M15);
  - the six phase 2 and 3 passenger types and their fare rules (bags and children).
- **Hand-overs**:
  - **B05**: mirror the rules reference (FR-063) and make pytest reproduce every fixture.
  - **B03**: the result now carries an outcome, counters and a reputation breakdown, and its
    validator's lower bound on duration (`0.85 × last station time`, backend §7.4) must allow for
    open road and other schedule shifts.
  - **B10**: the backend's `liveops.LiveSetting` copy of the tunables gets the new keys and the hints
    mode (FR-067, FR-069).
  - **B08**: a replay lasts at most 1,500 s of logic time, about 45,500 steps (SC-004), so the server
    can bound the cost of verifying a run.
  - **M02**: drive the engine, pause around choices if it chooses to, and show hints by
    `trip_hints_mode_<line_id>`. Tracking which passenger types a player has already seen, for
    `first_time`, lives in the app. Save the replay record on every accepted command and every
    pause, and on the next launch offer the killed trip back, paused (FR-070).
  - **M05 and B03**: a resumed trip has one `trip_start` and one `trip_result`, like any other. No
    fuel refund op is needed (FR-071).
- **Dependencies**: B04 is merged, with the trip schema and the generated app models. M03 is merged,
  with the tunables registry, its bundled defaults and the defaults test.
