# Feature Specification: Design Refresh (M21)

**Feature Branch**: `008.5-m21-design-refresh`

**Created**: 2026-10-23

**Status**: Draft

**Input**: User description: "M21 Design refresh (short name: m21-design-refresh). Move everything
built so far to the «كرتون ناعم» design in docs/design: tokens, components, the shell, the boot screen
and the trip screen, with the owner's Rive files in the new style." Feature 008.5 in
`docs/delivery-plan.md` is step 5.5, added on 2026-10-23 when the owner adopted Style C, «كرتون ناعم»,
in place of «ستيكر الميكروباص». It depends on M03 (merged in #1), whose theme tokens, shared components,
shell, boot screen and settings control it rebuilds, and on M02 (in `master` since #9), whose trip
screen it restyles. Sources: `docs/design/README.md` (its project overrides win over the handoff),
`docs/design/HANDOFF.md` §0–§10 and the §11 sections `Loading`, `C-Trip`, `TripEvents`, `StoryTrip`,
`Pause`, `Fail` and `States`, with the `Tokens`, `Components`, `Characters`, `Passengers` and `Vehicles`
boards and the hint visual of `Tutorial`; `docs/architecture-mobile.md` §8 and §9; M02's
`research.md` (R3, R15) and `contracts/rive-character.md`. Resolve (delivery plan, step 5.5): the scene
geometry against M02's layout, text scale, station-colour order, how `skin` slugs map to the new
looks, the ledger badge's duration against the ledger booster's (HANDOFF §9.3 #5), and the new art's
performance on the Galaxy A06. Out of scope: screens owned by later features, and any rule, economy or
content-schema change. Done when: the tokens come only from `docs/design/tokens.json`, the component
gallery matches its boards, every artboard in scope has a golden and a layout test, the trip plays
exactly as before with the owner's Rive files, and the minimum sizes and the A06 frame-rate gate pass.

## Clarifications

### Session 2026-10-23

- Q: Should 008.5 also build a trip layout for shorter phones (under about 800 pt tall, such as
  360×640) that keeps faces at full size, rather than leaving that to M07? → A: No. 008.5 guarantees
  every minimum down to the Galaxy A06 (360×800). Below that, M02's approved exception stays (only the
  scene's faces shrink), and the short-screen layout remains M07's hand-over (FR-020, Edge Cases).
- Q: How long should the «الدفتر» booster show who has paid: the 10 seconds the game uses today, or the
  design's 5 seconds? → A: 10 seconds. The ledger badges show for the whole peek
  (`booster_ledger_peek_ms`, unchanged), with the booster's seconds-left countdown. There is no
  separate 5-second badge timer (US4, Assumptions).
- Q: When the player taps a booster they have none of, should the trip pause and ask them to confirm
  the BONAT purchase (as M02 built), or should the purchase happen right away, as the design draws? → A:
  Keep M02's flow. The trip pauses, and a confirmation card in the design's spend-confirmation look
  shows the price; confirming buys the booster and uses it. The design's buy-at-once with an undo toast
  isn't used in the trip (FR-028).

## User Scenarios & Testing *(mandatory)*

The people involved:

- **The player**, who sees every screen that exists today (the loading screen, the four sections'
  placeholders, settings and, above all, the trip) in the new look. Nothing they do changes: the same
  taps do the same things, and every face, line and control stays as readable and as reachable.
- **The owner**, who adopted the new design, supplies its Rive files, and judges each screen against
  the design's renders.
- **The features that follow** (M06 onward), which build their screens from the tokens and components
  this feature makes, and must never restyle raw widgets or retype a design value.

### User Story 1 - One source for the new look (Priority: P1)

The new design's colours, type, radii, lips, layout values and motion live in one file
(`docs/design/tokens.json`). The app takes every value from it, and its shared components (buttons,
pills, chips, cards, sheets, dialogs, banners, toasts, switches, the bottom bar and the rest of HANDOFF
§3) are built once from those values. A gallery page in internal builds shows every component in every
state, side by side with the design's `Components` and `Tokens` boards.

**Why this priority**: Every other story, and every feature after this one, is built from these values
and components. If they are wrong or retyped by hand, every screen drifts from the design.

**Independent Test**: Open the gallery on a dev build and compare it with `docs/design/png/Components.png`
and `Tokens.png`. Change one value in `tokens.json` without regenerating the app's tokens, and check
that CI fails.

**Acceptance Scenarios**:

1. **Given** the design's token file, **When** the app's tokens are generated from it, **Then** every
   colour, type style, radius, lip, layout value and motion value in the app comes from the generated
   tokens, and none is written anywhere else.
2. **Given** a token file that differs from the generated tokens, **When** CI runs, **Then** it fails
   and names the difference.
3. **Given** a dev or staging build, **When** the tester opens the gallery, **Then** every HANDOFF §3
   component shows in each of its states (default, pressed, disabled, loading, and its own, such as the
   tray cell's breakable or the booster's active badge), in RTL, in both digit styles.
4. **Given** any tappable with a lip, **When** it is pressed, **Then** it moves down by its lip while the
   lip goes to zero in 80 ms, gives a light haptic tick unless vibration is off, and comes back on
   release. A disabled one shows at 45% opacity with no lip and doesn't move. Nothing shows a Material
   ripple.
5. **Given** a prod build, **When** the player uses the app, **Then** the gallery can't be reached.

---

### User Story 2 - The app's frame in the new look (Priority: P1)

The player opens the game. The loading screen is the design's `Loading`: the sun ground with no white
flash, the wordmark and tagline, the microbus driving in, and a road-shaped progress bar with a short
line under it. Then the sections: a white bottom bar with the active tab in a blue pill, pale sky
screens with white cards, the placeholders of screens later features build, sheets that rise with a
grabber and dialogs that pop in. Settings shows the digit-style choice in the design's look.

**Why this priority**: These are the first things every player sees, on every launch, and the frame
every later screen sits in.

**Independent Test**: Cold-start a dev build and record the first second; then visit each section,
each placeholder, a sheet and settings, and compare the goldens with the design's PNGs.

**Acceptance Scenarios**:

1. **Given** a cold start, **When** the app opens, **Then** every frame from the system splash to the
   end of the loading screen has the sun ground, with no white frame, and the loading screen matches
   `Loading`.
2. **Given** the loading screen, **When** the app opens its database and verifies its content pack,
   **Then** the progress marker moves right to left with those steps, and the screen gives way to the
   next destination as soon as they finish, with no minimum display time.
3. **Given** any of the four sections, **When** it shows, **Then** the bottom bar is the design's
   `BottomNav` (white, 88 pt with the bottom padding, four equal tabs, the active one in a `primary`
   pill), and its new-dots are the design's `NewDot`.
4. **Given** a placeholder of a screen a later feature builds, **When** it opens, **Then** it uses the
   design's screen header, back control and empty state, so it already sits in the new frame.
5. **Given** a sheet or a dialog, **When** it opens and closes, **Then** it follows the design's `Sheet`
   and `AppDialog` (shape, scrim, grabber, close control, dismissal and timing).
6. **Given** settings, **When** the player changes the digit style, **Then** the choice is the design's
   segmented control, and every number on every screen switches at once (M03 FR-026).
7. **Given** the phone's back button on a section's top level, **When** the player presses it twice to
   leave, **Then** the hint between the two presses is a toast in the design's style.

---

### User Story 3 - Playing a trip in the new look (Priority: P1)

A player opens a trip. The top shows the pause button, the line and trip number, and the reputation
bar; under them, the white station strip with the vehicle marker, a coloured lettered dot for each
stop, and the next stop's red ring and countdown. The cabin is the design's: a pale wall and floor,
the back window, side windows with the street moving past, the next station's sign, and three benches.
Passengers sit at the design's seat positions with their station tags on their shoulders; notes hop
seat to seat in the design's colours; bubbles pop over heads. The dark dashboard holds the hand, «حد
معاه فكة؟», the change tray, the four boosters and «آخر كلام». Everything plays exactly as it did.

**Why this priority**: The trip is the game, and the screen players spend most of their time on.

**Independent Test**: Play every sample trip in airplane mode on a dev build and compare the trip
goldens with `C-Trip.png`. In an automated test, play every parity fixture the controls can produce
through the restyled controls and compare each outcome with its expected result.

**Acceptance Scenarios**:

1. **Given** a trip on the old microbus, **When** it shows, **Then** the screen has the design's three
   zones (a 114 pt HUD, the scene, and a 258 pt dashboard overlapping the scene by 16 pt), never
   scrolls, and matches `C-Trip` with the same sample data.
2. **Given** a trip on the tuktuk, **When** it shows, **Then** its cabin and near row follow the design's
   tuktuk (`Tutorial`: one bench, the near row at 1.15×) on the tuktuk's three fixed seats, with every
   minimum size kept.
3. **Given** a running trip, **When** the next stop comes within the warning time, **Then** its dot gets
   the red ring, its countdown chip grows and pulses under 8 s, and the tags of passengers still owed
   change for it turn hot and pulse. A passed stop's dot fades to 35% and its price reads «عدّت».
4. **Given** money moving, **When** a note hops, **Then** it is the design's `MoneyNote` in its kind's
   colours (fare, change, blocked with its «؟» badge, fallen with its ring, in hand), moving seat to seat
   at the engine's pace.
5. **Given** a passenger speaks, **When** the bubble shows, **Then** it is the design's `SpeechBubble`
   in the line's variant (normal, warning, fight, thanks), its tail about 8 pt above the speaker's head,
   inside the scene, at most two at a time, each up for at least the line's minimum.
6. **Given** the dashboard, **When** the player picks coins, sends change, takes it back, calls for
   change or uses a booster, **Then** each control looks and reacts as the design's (`HandSlot` with its
   chips, total and «فاضية»; the «رجّع» pill inside the hand for the undo window; `CallChangeButton` and
   its break mode; `TrayCell` full, empty, breakable and pressed; `BoosterButton` with its badges;
   `LastWordsLog`), and sends the same command it sent before.
7. **Given** any trip, **When** it is played through the restyled controls, **Then** the engine
   receives exactly the commands it received before this feature, and the outcome is the same.

---

### User Story 4 - Events, choices, story trips and hints in the new look (Priority: P2)

The fare goes up: a red banner slides down over the back window, the stop's old price is struck
through on the strip and the new one pops in. The ledger booster replaces the station tags with
«دافع», «لسه» and «على صاحبه» badges while it runs. A passenger insists he paid, and «ماشي» and «لأ، ما
دفعتش!» appear next to him. In a story trip, the «مشوار قصة» chip sits in the HUD and a dark strip at
the top of the scene states its rule. On the lines with hints, بلية pops up in the corner with his line
and a pointing hand.

**Why this priority**: These moments make the trip a puzzle, and they come right after the basic loop.

**Independent Test**: Play the sample trips and the fixtures that trigger each event, choice and
booster, and compare the goldens with `TripEvents.png`, `StoryTrip.png` and the hint visual of
`Tutorial.png`.

**Acceptance Scenarios**:

1. **Given** an event starts, **When** it has a banner (`fare_increase` and the others the ux-spec gives
   one), **Then** it is the design's `EventBanner`, announced once, and it hides by itself.
2. **Given** a fare increase, **When** the stop is still ahead, **Then** the strip shows the old fare
   struck through and the new fare chip until the stop passes.
3. **Given** the ledger booster runs, **When** its badges show, **Then** each passenger's tag is
   replaced by the design's `LedgerBadge` for the whole peek (`booster_ledger_peek_ms`, 10 s by
   default), and the booster shows as active with its seconds-left countdown (Clarifications).
4. **Given** a claim, a change request or a payment dispute, **When** it waits for the player, **Then**
   it shows in the design's look (the `ChoicePopover` next to the passenger; the dispute's two faces),
   and it pauses the trip only where M02 decided it does (the dispute alone).
5. **Given** dropped money or a «نزّلني هنا» request, **When** it shows, **Then** it uses the design's
   fallen note and the `StationTag` star variant, with a hit area of at least 44×44 pt.
6. **Given** a story trip, **When** it plays, **Then** the HUD shows the «مشوار قصة» chip above the
   trip's usual title, and the condition strip, with M02's text for the rule, stays at the top of the
   scene for the whole trip. Bubbles never cover the condition strip. The front seat holds whoever the
   trip seats there; a story character and its comments wait for content that defines them (FR-025).
7. **Given** a line whose hint mode shows a hint, **When** بلية speaks, **Then** he appears as the
   design's coach without the scrim: his head at the bottom corner of the scene over the dashboard's
   top edge, a character bubble with his name, and a pointing hand toward what the hint is about. The
   hint modes and their rules don't change.

---

### User Story 5 - Pausing and failing in the new look (Priority: P2)

The player pauses: the trip dims and the «واقفين على جنب» card offers to resume, restart for a liter,
or go back to the stand, with the sound and vibration switches. The player fails: every passenger turns
angry, and the «المشوار باظ» card shows a few angry faces, the reason, the BONAT revive when it's
allowed, and the restart and home tiles. The other trip cards (buying a booster, the empty tank, a
failed save, the dispute) look like the design's dialogs.

**Why this priority**: Pausing and failing happen in most sessions, and the failure card carries the
revive, a key BONAT spend.

**Independent Test**: Pause and fail sample trips with a test economy, revive once, fail again, and
compare the goldens with `Pause.png` and `Fail.png`.

**Acceptance Scenarios**:

1. **Given** a running trip, **When** the player pauses, **Then** the card matches `Pause`, with the
   restart cost as the design's fuel chip, and the switches change sound and vibration at once.
2. **Given** a failed trip, **When** the failure card shows, **Then** it matches `Fail`: up to three
   angry faces from this trip (those who fought or missed their stop first), the title, a reason chip
   built from what went wrong, the BONAT revive with its catalog price when the trip may be revived,
   the once-per-trip caption, and the restart and home tiles.
3. **Given** a trip already revived, or at the command cap, **When** it fails, **Then** the revive and
   its caption are hidden and the two tiles remain.
4. **Given** the failure card, **When** the player presses back or taps the scrim, **Then** nothing
   happens: a choice is required.
5. **Given** a booster with none left, an empty tank, a failed save or a payment dispute, **When** its
   card shows, **Then** it uses the design's dialog look, and its buttons do what M02's did.

---

### User Story 6 - Passengers and characters in the new art (Priority: P2)

The owner supplies the Rive files in the new style: one look for each passenger type of the MVP
lines, the story characters, the two MVP vehicles and the UI animations, made to the character
contract this feature's plan writes. In the trip, every passenger is drawn in its look and moves
through the design's states (idle, talking, impatient, asleep and waking, headphones and the two calls,
change due, fight, happy, claim, targeted, boarding, getting off). If a file is missing or fails to
load, the design's static art stands in, with a gentle idle motion.

**Why this priority**: The art is what makes the new design feel alive, but the trip is fully playable
and testable on the static art, so the rest of the feature doesn't wait for the files.

**Independent Test**: With the owner's files in place, run the character contract test, which checks
each file's states and properties, and the character goldens. Remove a file and check that its static
art shows instead. Measure the busiest sample trip on the Galaxy A06.

**Acceptance Scenarios**:

1. **Given** the owner's files, **When** the contract test runs, **Then** every file has the states and
   properties the contract names, and every state the engine can produce has a state to show it.
2. **Given** a passenger in the trip, **When** the engine's state for them changes, **Then** their art
   switches to the matching state, plays a one-shot state once and returns to idle, and loops a looping
   one.
3. **Given** a passenger's `skin`, **When** it is drawn, **Then** it shows the look that skin maps to,
   and a skin with no look falls back as in M02: to the look of a type the player can see anyway,
   otherwise the default look, with the neutral label. No look or label is ever derived from a
   type the player is meant to discover (Edge Cases).
4. **Given** a missing or broken file, **When** the trip opens, **Then** that art falls back to the
   design's static drawing with a code-driven idle bob, and the trip plays normally.
5. **Given** the Galaxy A06, **When** the busiest sample trip plays on the old microbus with every seat
   animated, **Then** the scene meets the frame-rate and memory budgets (SC-005).

---

### User Story 7 - The design stays the reference (Priority: P3)

When the design changes, the owner rebuilds `docs/design/` from the canvas and the app follows: new
token values arrive through generation, and the goldens and layout tests show exactly which screens
moved. Each in-scope artboard has a golden beside the design's PNG, and a test that checks its controls
against the measured boxes.

**Why this priority**: It keeps this feature's work from rotting, and it is the routine every later
screen follows, but players don't see it directly.

**Independent Test**: Change a component's size in a copy of a `boxes/` file and check that the layout
test fails on it; regenerate the tokens from a changed `tokens.json` and check that the goldens show
the change.

**Acceptance Scenarios**:

1. **Given** an artboard in scope, **When** its layout test runs, **Then** each tappable, found by its
   screen-reader label, sits within ±2 pt of its measured box on the 390×844 frame.
2. **Given** an artboard in scope, **When** its golden is generated, **Then** it uses the artboard's
   sample data, in RTL, in both digit styles, and the PR shows it next to the design's PNG.

---

### Edge Cases

- **Narrow phones (360 pt wide, the Galaxy A06).** The design's scene is 390 wide; scaling it down to
  fit would shrink faces below 50 and 80 pt. Faces, tags, notes, bubbles and targets MUST keep their
  minimums at 360 pt; seat positions spread over the narrower width instead.
- **Height.** With the design's taller bands, the A06 (360×800) leaves a scene a little shorter than
  M02's 420 pt guarantee. Every minimum MUST still hold on it. The design crops the top of the cabin
  wall, never the passengers, before shrinking anything.
- **Short screens** (shorter than the A06's 800 pt, such as 360×640). As in M02: the bands keep their
  sizes, and only the scene and its faces shrink. This is M02's approved exception to constitution XI,
  and ending it stays M07's hand-over (Clarifications). The plan records the new height below which
  the exception applies, since the design's bands are taller than M02's.
- **Wide phones (over 430 pt).** The trip keeps the 390 design width, centred; other screens stretch.
- **Text size.** Normal screens follow the phone's setting up to 1.3× (M03). The trip's HUD, dashboard
  and station tags may be clamped lower (the design proposes 1.15×) if 1.3× breaks them; either way no
  text falls below its minimum and nothing overlaps or clips.
- **Long text.** The HUD title is one line with an ellipsis; chips, banners and cells grow and wrap to
  two centred lines instead of clipping (HANDOFF §9.1 #10). Station names too long for the strip are
  capped by content (a content rule, not a code rule).
- **Many pieces in the hand.** The chips clip and the total always stays visible.
- **Hidden types.** The design draws a look for «أنا دافع!» (`claimer`) and the honest passenger
  (`honest`). The app MUST NOT pick a look, a label or a log speaker from a passenger's archetype where
  that would reveal what the player is meant to find out: the look comes from the trip's `skin`, which
  content chooses (M02 FR-033).
- **A skin with no look.** It falls back to a default look, never to an error or an empty seat.
- **The front seat.** It has no ledger badge position in the design; its badge sits where its tag sits.
- **Story trips.** Content gives a story trip only its kind and its no-fights rule: no character,
  title or condition text. The design's story character, its bubble and its name in the failure reason
  wait for the feature that adds them to content (FR-025, FR-027).
- **Reduced motion.** No shake, bubble pop, parallax, pulse or entrance animation; hot rings stay
  static; fades are 150 ms at most. The art's loops keep playing, with their effects still.
- **Dark mode.** The app looks the same in light and dark mode (M03 FR-009).
- **Western digits.** Every number in every new component goes through the shared formatter.
- **No network.** Fonts, art and animations are all bundled; nothing in this feature needs a
  connection.
- **A Rive file arrives late.** The static art stands in (US6), so the feature can be built and tested
  before the files are in, but it doesn't merge without them (Assumptions).

## Requirements *(mandatory)*

### Functional Requirements

#### What the design decides

- **FR-001**: Every screen, component and animation this feature touches MUST follow `docs/design/`,
  under the project overrides of `docs/design/README.md`: animation stays on Rive (the constitution's
  locked stack), identifiers come from the glossary (architecture §3), and on behaviour the decisions of
  merged features win over the handoff.
- **FR-002**: For anything the player sees (sizes, colours, radii, copy), the artboard's HTML wins, then
  HANDOFF.md, then the ux-spec. Where a value falls between tokens, the HTML's value is used, not the
  nearest token (HANDOFF §2.2).
- **FR-003**: This feature MUST NOT change any trip rule, economy rule, stored data or content schema.
  Every command the controls send, every economy call and every stored record stays as M02, M03 and
  M05 made them.
- **FR-004**: Each conflict between the handoff and a merged decision that this feature settles MUST be
  recorded in its `research.md` and its PR description. The known ones are listed in Assumptions.

#### Tokens and type

- **FR-005**: The app's colours, type styles, radii, lips, layout values and motion values MUST be
  generated from `docs/design/tokens.json`, with names that map one to one (HANDOFF §2). No value may be
  written by hand anywhere else. M03's guard against raw style values outside the tokens stays.
- **FR-006**: CI MUST fail when the generated tokens and `tokens.json` differ.
- **FR-007**: The app MUST bundle Marhey (display and buttons) and Readex Pro (text and numbers), with
  their licences, and MUST NOT ship Lalezar or Baloo Bhaijaan 2. No style is below 12 pt.
- **FR-008**: The palette checks MUST cover the new palette: body text on white at least 4.5:1; white
  text only on `primary`, `primary.lip`, the first two station colours and the dashboard; never white on
  `danger` or `sun`; red text on white in `danger.ink`; and the station colours, and `primary` against
  `danger`, at least 18 L* apart.
- **FR-009**: Station colours and letters MUST keep M02's rule: by alighting order in the trip, at most
  four, with the letter always shown. The design's "order on the line" doesn't apply (delivery plan,
  step 5.5).

#### Components

- **FR-010**: The HANDOFF §3 component set MUST be built once, in the app's shared components, from the
  tokens only: buttons (`primary` xl and l, `secondary`, `sun`, `danger`, `tertiary`, `RewardedAdButton`,
  `IconCircleButton`), pills, badges and chips (`CurrencyPill`, `CountBadge`, `NewDot`, `StatusChip`,
  `PriceTag`, `Stars`), controls and containers (`AppSwitch`, `Segmented`, `AppTextField`, `AppCard`,
  `ListRow`, `ProgressBar`, `ScreenHeader`, `Sheet`, `AppDialog`, `EventBanner`, `OfflineBanner`,
  `UndoToast`, `BottomNav`, `DailyCircle`, `ComicPanel`, `CoachMark`), the `States` components
  (`InlineAlert`, `StatusCard`, `EmptyState`, `MicrobusLoader`) and the trip components of §3.4.
  M03's sticker components MUST be removed.
- **FR-011**: Every tappable with a lip MUST have the pressed state of HANDOFF §2.3 (down by its lip,
  lip to zero, 80 ms, a selection haptic unless vibration is off). Disabled MUST be 45% opacity with no
  lip and no press. No Material ripple may show anywhere.
- **FR-012**: Progression-locked items MUST use the locked look (`locked.bg`, a 2 pt `outline` ring,
  `ink.2` text, a lock icon), never opacity (HANDOFF §9.1 #6). The currency-pill, counter, BONAT-wording
  and fuel-chip rules of HANDOFF §9.1 #3, #4, #7 and #8 apply wherever those components show.
- **FR-013**: Dev and staging builds MUST offer a gallery that shows every component in every state,
  in RTL and both digit styles, matching the `Components` and `Tokens` boards. Prod builds MUST NOT
  contain it.

#### The app's frame

- **FR-014**: The boot screen MUST be the design's `Loading`. Its progress follows the boot steps that
  exist today (the database opened, the content pack verified); M06 adds the bootstrap step. Its line
  under the bar comes from a pool of short lines in the app's strings. It leaves as soon as boot is done.
  The system splash and every frame before it are the sun colour (M03 FR-012).
- **FR-015**: The bottom bar MUST be the design's `BottomNav`, on the four section screens only, with
  the design's new-dots and the 150 ms cross-fade between tabs.
- **FR-016**: The placeholders of later features' screens MUST use the design's `ScreenHeader`, back
  control and `EmptyState`, and sheets and dialogs MUST use `Sheet` and `AppDialog` with the HANDOFF §6.5
  timings. The back-to-exit hint MUST be a toast in the design's style.
- **FR-017**: Settings' digit-style choice MUST be the design's `Segmented` control in the `Settings`
  artboard's look. The rest of the `Settings` artboard is M14's.
- **FR-018**: The screens' top inset MUST follow the phone's real status bar (at least 24 pt) and the
  bottom padding its real system bar, not the design's fixed 36 pt (HANDOFF §2.4).

#### The trip screen

- **FR-019**: The trip screen MUST have the design's zones: the `TripHud` (114 pt: the pause button, the
  title, the `ReputationBar`, then the `StationStrip`), an 8 pt gap, the scene, and the `Dashboard`
  (258 pt, overlapping the scene by 16 pt). It never scrolls. On phones wider than 430 pt it keeps the
  390 design width, centred.
- **FR-020**: Every minimum size MUST hold on the reference frame (390×844) and on the Galaxy A06
  (360×800) (constitution XI): back-row faces at least 50 pt wide, near-row faces at least 80 pt, bubble
  text at least 15 pt, money notes at least 40×24 pt with 15 pt digits, touch targets at least 44×44 pt,
  any text at least 12 pt. Where the design's geometry and these minimums disagree, the minimums win,
  and the plan settles the layout (delivery plan, step 5.5). On screens too short for them (the plan
  sets the height), M02's approved exception continues unchanged until M07 (Clarifications): only the
  scene's faces may shrink.
- **FR-021**: The station strip MUST follow `C-Trip` and `TripEvents`: the track and its `primary`
  progress from the start end, the depot dot, a dot per stop with its colour and letter placed by its
  time, the vehicle marker, each stop's name and fare, the next stop's ring and countdown chip (pulsing
  under 8 s), passed stops at 35% with «عدّت», and a raised fare as the old price struck through with
  the new fare's chip.
- **FR-022**: The scene MUST draw the design's cabin (wall, floor, back window, side windows with a
  moving street, the next station's sign in its colour, the benches) and seat the passengers at the
  design's positions for each MVP vehicle: the old microbus from `C-Trip` and HANDOFF §4.2, the tuktuk
  from `Tutorial`. The light garland is a phase 2 cosmetic and is not drawn.
- **FR-023**: Station tags, money notes, bubbles, ledger badges, choice popovers, the dispute's faces,
  fallen notes, banners and the hint MUST be the HANDOFF §3.4 components, drawn over the scene as
  widgets, never as text inside the scene (constitution, architecture §8).
- **FR-024**: The dashboard MUST follow `C-Trip`'s rows: `HandSlot` with `CallChangeButton`, the 4×2
  `ChangeTray`, the four `BoosterButton`s, and the `LastWordsLog`. The undo control MUST be a `sun` pill
  inside the hand at its end side, at least 44×44 pt to tap, shown for the engine's undo window
  (HANDOFF §9.2). Break mode and every tray-cell and booster-badge state MUST follow the design.
- **FR-025**: A story trip MUST show the `StatusChip` «مشوار قصة» above the trip's usual title in the
  HUD, and the dark condition strip, with M02's text for the no-fights rule, at the top of the scene for
  the whole trip. Content has no story character, title or condition text (only `kind: story` and the
  rule), and this feature changes no schema (FR-003), so the design's story character in the front seat
  and its comments stay with the feature that adds them. Its art and the character bubble are built and
  shown in the gallery.
- **FR-026**: بلية's hints MUST use the `Tutorial` artboard's coach look without the scrim: his head at
  the bottom corner of the scene over the dashboard's top, a character bubble with his name, and a
  pointing hand. When and what he says stays M02's (`trip_hints_mode_<line_id>`). The tutorial's dimmed,
  step-by-step lessons and its locked-boosters bar stay M07's.
- **FR-027**: The pause card MUST be the design's `Pause`, and the failure card the design's `Fail`
  (the angry faces chosen from this trip, the reason chip built from the engine's recorded causes with
  Arabic dual and plural forms, the BONAT revive and its caption only when the trip may be revived, and
  the two tiles). The failure card MUST NOT close on back or a tap on the scrim. A story trip failed by
  its rule (a fight in a no-fights trip) MUST say so in the reason chip, in a fixed line that names no
  character, and offers no revive, since the engine refuses one after such a fight.
- **FR-028**: M02's other trip cards (buying a booster with none left, the empty tank, a failed save,
  the payment dispute) MUST use the design's `AppDialog` and the `States` spend-confirmation look, with
  M02's behaviour. Tapping a booster with none left MUST pause the trip and show the confirmation card
  with its BONAT price; confirming buys the booster and uses it, and the trip resumes. No undo toast is
  used in the trip (Clarifications).
- **FR-029**: Nothing in this feature may call an ad SDK (constitution IX). The design's ad offers (the
  «صالح الركاب» revive and the «زحمة» ad badge) MUST NOT show until M11 adds them; the layout leaves
  their place.

#### Art and motion

- **FR-030**: Passengers, the story characters, بلية and the loading screen's vehicle MUST be drawn
  with the owner's Rive files in the new style, made to a character contract that this feature's plan
  writes and that replaces M02's `contracts/rive-character.md`. M02's single `passenger.riv` MUST be
  retired.
- **FR-031**: The contract MUST give every file the states of HANDOFF §5.4 and §6.2 (with which ones
  loop and which play once and return to idle), the properties the app sets (such as skin tone and
  hiding an accessory), and the art sizes. The app MUST map the engine's state of each passenger to one
  state at a time.
- **FR-032**: Each `skin` MUST map to one look, as the plan decides (renaming the sample pack's skins or
  mapping them in the app). A skin with no look MUST fall back to a default look. A look, a label or a
  log speaker MUST never be chosen from a hidden archetype (Edge Cases, M02 FR-033).
- **FR-033**: When a file is missing or fails to load, or as the last performance fallback, the art
  MUST fall back to the design's static drawings in `docs/design/illustrations/`, with a 2 pt idle bob
  every 1.2 s. The `lottie/` files are a motion reference only: no Lottie runtime may be added.
- **FR-034**: The motion of HANDOFF §6.5 MUST apply (presses, sheets, dialogs, toasts and banners,
  bubbles, hot tags, the countdown, money hops at the engine's pace, getting off, shakes, progress bars,
  new-dots, tab switches), and reduced motion MUST turn off shakes, bubble pops, star bounces, parallax,
  pulses and entrances, keeping fades at 150 ms or less.
- **FR-035**: Swapping one art file for another that meets the contract MUST NOT change any behaviour or
  any non-golden test outcome.

#### Accessibility and copy

- **FR-036**: Every tappable MUST have a screen-reader label, taken from the artboard's `aria-label` text
  where it has one. A passenger's label names their look and their stop, and adds «ليه باقي» only while
  their tag is hot (HANDOFF §9.1 #12), within M02 FR-033's limits. «آخر كلام» stays the only live
  region; banners are announced once.
- **FR-037**: All new copy MUST be in the app's strings file (no Arabic in code), with the handoff's
  strings as its source. Speech lines stay in the content pack's speech pools.
- **FR-038**: Every number MUST go through the shared formatter, in the player's digit style.

#### Testing and docs

- **FR-039**: Each artboard in scope (`Loading`, `C-Trip`, `TripEvents`, `StoryTrip`, `Pause`, `Fail`, the
  `Tutorial` hint visual, `Components`, `Tokens`, and the `States` components) MUST have a golden at
  390×844 with the artboard's sample data, in RTL, in both digit styles, shown in the PR next to the
  design's PNG.
- **FR-040**: Each artboard in scope MUST have a layout test that finds every tappable by its
  screen-reader label and checks that its rectangle is within ±2 pt of the artboard's measured box.
- **FR-041**: The minimum-size checks MUST run on 390×844 and 360×800, and at text scales 1.0 and 1.3
  (or the trip's clamp), and M03's and M02's existing goldens and size checks MUST move to the new look
  and keep passing.
- **FR-042**: Every behaviour test of M02 and M03 MUST keep its assertions and pass, including the
  playthrough of each parity fixture the controls can produce. Only how a test finds or names things may
  change: a finder may move from a retired widget to its replacement or to a screen-reader label, and an
  expected text may be built from the app's strings instead of a literal. The PR MUST list each such
  change. New code MUST reach at least 80% line coverage (constitution XIII).
- **FR-043**: The same change MUST update `docs/architecture-mobile.md` (§2, §5, §8 and §20, with what
  this feature decides), `CLAUDE.md` (the art's place, its commands and its contract), and the
  delivery plan's progress.

### Key Entities

- **Design tokens**: every colour, type style, radius, lip, layout and motion value, generated from
  `docs/design/tokens.json` and checked against it.
- **Component set**: the shared components of HANDOFF §3 and `States`, each with its states, and the
  gallery that shows them.
- **Artboard reference**: for each artboard in scope, its HTML, its PNG and its measured boxes, which
  the goldens and layout tests compare against.
- **Character art set**: the owner's Rive files (passenger looks, story characters, بلية, vehicles, UI
  animations), the contract they meet, and the static drawings they fall back to.
- **Look mapping**: which look each `skin` shows, and the default look for a skin with none.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On the 390×844 frame, 100% of the tappables of each in-scope artboard sit within ±2 pt of
  their measured boxes.
- **SC-002**: Zero colour, type, radius, lip or motion values are written in screens or components:
  they come from the generated tokens, from the named values the artboards use between tokens (each
  citing its artboard, FR-002), or from the trip's named motion constants. A token file that differs from
  the generated tokens fails CI in 100% of runs.
- **SC-003**: Playing each parity fixture the controls can produce (M02's 58 of 60) through the
  restyled controls gives exactly the fixture's expected result in 100% of runs, and every behaviour test
  of M02 and M03 passes with its assertions unchanged (FR-042).
- **SC-004**: On renders at 390×844 and 360×800, in RTL with both digit styles, at both text
  scales, 100% of measured faces, bubble texts, money notes, touch targets and texts meet their
  minimums, and no text overlaps or clips.
- **SC-005**: On the Galaxy A06, over a full playthrough of the busiest sample trip on the old microbus
  with every seat drawn by the owner's Rive files, two bubbles and three notes in flight at its busiest,
  the scene averages at least 55 fps, no one-second window falls below 45 fps, and memory stays under
  300 MB. The 90th-percentile frame time is recorded against the design's 16 ms target.
- **SC-006**: On the Galaxy A06, a cold start shows no white frame, and still reaches Home in under 3 s.
- **SC-007**: 100% of text and fill pairs in the new palette meet WCAG 2.1 AA, and 100% of the station
  colour pairs, and `primary` against `danger`, are at least 18 L* apart.
- **SC-008**: The app's code contains no reference to Lalezar, Baloo Bhaijaan 2, M03's sticker
  components or `passenger.riv`.
- **SC-009**: The release download stays under 80 MB with the new fonts, art and Rive files.
- **SC-010**: The owner, comparing each in-scope screen with its PNG side by side, accepts every one
  before the merge.

## Assumptions

- **Dependencies.** M03 (merged in #1) and M02 (in `master` since #9) are built; this feature reshapes
  what they show, not what they do. M04 and M05 are untouched. No server, ad SDK or analytics is
  involved.
- **The owner's Rive files** arrive before this feature merges, so before 009 starts (delivery plan,
  step 5.5). They are made to the contract the plan writes, so the plan comes first. The full list
  (the MVP passenger looks, the six story characters, the two MVP vehicles and the UI animations of
  HANDOFF §6.3) arrives together; this feature uses the passengers, the characters that ride in trips,
  بلية and the loading screen's animation, and the rest wait for their features. They are exported from
  Rive's free plan (the owner's decision of 2026-10-23, research R15); the app never draws the
  export's splash artboards. Until they arrive, the
  static art stands in (FR-033).
- **Behaviour where the handoff differs from merged decisions** (FR-004). M02's decisions stay:
  - Only the payment dispute pauses the trip. The handoff proposes pausing on every choice popover;
    M02's clarification decided otherwise.
  - «عيد المشوار» restarts the trip directly for a liter, as M02 built. The handoff routes it through the
    pre-trip card, which is M08's; M08 decides whether to adopt that.
  - A booster with none left is bought through M02's confirmation card (Clarifications). The handoff's
    "spend now, undo within 3 s" can't undo a booster the engine has already applied. The undo toast
    for small BONAT purchases outside a trip is M12's (M05 hand-over).
  - The revive costs BONAT at the catalog price; the ad revive and the «زحمة» ad badge are M11's.
  - Fuel: a restart costs a liter, and an abandoned trip's liter isn't refunded (M05's spec, M02 US2);
    the handoff's "refund is open" note is out of date.
- **The ledger badge's duration** (HANDOFF §9.3 #5) is settled (Clarifications): the badges last the
  whole peek, `booster_ledger_peek_ms`, 10 s by default. The design's 5-second figure doesn't apply,
  and no tunable changes.
- **Scene geometry and text scale** are the plan's to settle (delivery plan, step 5.5), within FR-020's
  minimums and M03's text-scale range.
- **Art names are not identifiers.** The handoff's `microbus_old` is the glossary's `micro_old`, and its
  passenger ids are looks, not archetypes (`docs/design/README.md`).
- **Sample data.** Every name and number in the artboards is sample data; goldens use it, and the app
  shows real values from the engine, content, tunables and catalog.
- **Out of scope**: the screens owned by later features (onboarding and the tutorial's lessons, Home,
  the pre-trip card, the result screen, lines, the apartment and the story viewer, the shop and the fuel
  sheet, the daily return loop, the rest of settings and the account), even where their components are
  built here; ads (M11); any rule, economy, content-schema or speech-pool change; the phase 2 and later
  vehicles, passenger types and cosmetics.
- **Owner actions** go in `docs/owner-actions.md` at `/speckit-implement`: the Rive files before the
  merge, the A06 measurements (SC-005, SC-006), the download size (SC-009) and the side-by-side review
  (SC-010).
