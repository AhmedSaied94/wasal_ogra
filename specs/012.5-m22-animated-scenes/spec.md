# Feature Specification: Animated Scenes (M22)

**Feature Branch**: `012.5-m22-animated-scenes`

**Created**: 2026-10-28

**Status**: Draft

**Input**: User description: "lets start feat 012.5" (`/speckit-specify feat 012.5 (M22, the animated
scenes). The new Rive file is already in the current worktree.`). In `docs/delivery-plan.md` step 7,
spec 012.5 is M22, "Animated scenes": play the comic panels as Rive animations from a second file,
`wassal_scenes.riv`, so that the characters and the tuktuk move and the character whose bubble shows
talks. The still drawings stay the fallback. Sources: the file
(`apps/mobile/assets/rive/wassal_scenes.riv`, in this branch) and its board «حركة المشاهد» on the
design canvas; `specs/012-m07-onboarding/contracts/scenes.md` "Panel art" and "The player";
`specs/008.5-m21-design-refresh/contracts/rive-characters.md` (how the app loads and checks Rive art,
and how it falls back). Out of scope: new scenes or drawings; the trip's passengers; any rule,
economy or schema change. Depends on M07 and M21, both merged. The spec follows the file as
delivered: [what it holds](#the-file-as-delivered-checked-2026-10-28) and
[what Claude Design reported](#what-claude-design-reported-pasted-by-the-owner-2026-10-28) are
recorded under Assumptions, and the app does not work around them. The owner's two follow-ups are in
too: the usta's look, decided in favour of the panels, with an updated `wassal.riv` (FR-023), and the
draft's بلية line in `ch1_usta_dreams`, given to the usta.

## Clarifications

### Session 2026-10-28

- Q: On an animated panel, if the player taps «يلا» before the panel's last line has appeared, what
  happens? → A: The first tap shows the rest. Every remaining bubble appears at once and nobody
  talks; the next tap goes to the next panel. Once the last turn has started, «يلا» moves on at once,
  as in M07 (FR-016).
- Q: The release draft's `ch1_usta_dreams` gives بلية a line, but the panel's art draws only the
  usta. What changes? → A: The line goes to the usta. In the draft, `speaker` becomes `usta` and the
  text becomes «بس الأول لازم أركّز في الأجرة», because the usta can't say «يا أسطى» to himself.
  Every spoken line of the three scenes now has its speaker drawn in its panel.
- Q: Claude Design drew the usta as the panels do (lighter skin, a forelock), not as the characters
  sheet did (darker, no forelock). Which wins? → A: The panels. The owner updated the design's
  characters sheet and `wassal.riv` to match, so the usta looks the same everywhere (FR-023).
- Q: Should a character's talking turn play a sound, such as a blip as each bubble appears, or
  should the scenes stay silent as in M07? → A: Silent, as M07. Turns are visual only; sound for
  scenes waits for a later audio pass (FR-012).

## User Scenarios & Testing *(mandatory)*

M07 plays two scenes as comics: the opening, before the Name card, and the سلمى scene, after the first
finish of tutorial trip 3. Each panel is a still drawing. Its bubbles arrive with it, and nothing in
the drawing moves. This feature plays the same panels as animations. The tuktuk drives, المعلم holds out
the key, بلية bounces and waves, the usta stretches at the stand and drops a coin in his tin, and سلمى
waits at the bus stop with her books. A panel's lines are spoken one at a time, and whoever speaks
talks while their line goes up.

### User Story 1 - The opening comes alive (Priority: P1)

A new player opens the game for the first time. After Loading, the opening scene's three panels play
as animations. In the first, المعلم holds out the tuktuk's key to the usta. In the second, the two
stand by the tuktuk's money drawer. In the third, the usta sits in the tuktuk while بلية bounces and
waves beside المعلم. Each panel's lines come one after the other, and the character speaking is the
one whose mouth moves.

**Why this priority**: The opening is the first thing every player sees. It is the reason the file
was made, and it is half of the delivery plan's "done when".

**Independent Test**: Install a dev build with the file, open it with reduced motion off, and tap
through the opening. Each panel moves by itself. In a panel with two lines, the first speaker's
bubble appears and that speaker talks. They stop, then the second bubble appears and that speaker
talks.

**Acceptance Scenarios**:

1. **Given** the file loaded at startup, the panel's artboard passed its check and reduced motion is
   off, **When** the opening's first panel (`opening_key`) shows, **Then** its animation plays by
   itself, the caption «الموقف، الصبح بدري» shows with the panel, and المعلم's bubble appears with
   المعلم talking.
2. **Given** the second panel (`opening_stand`), whose lines are المعلم's then the usta's, **When** it
   shows, **Then** المعلم's bubble appears first and he talks. When his turn ends he stops, the usta's
   bubble appears under his and the usta talks. When the usta's turn ends, both bubbles stay, nobody
   talks, and the panel keeps moving.
3. **Given** a panel whose last turn has ended, **When** the player waits, **Then** the animation
   keeps looping and nothing else changes. The scene never moves to the next panel by itself (M07
   FR-007).
4. **Given** a line spoken by the usta, **When** its turn plays, **Then** the bubble shows the
   player's name as its speaker (M07), and the usta is the character who talks.
5. **Given** a panel whose last turn hasn't started yet, **When** the player taps «يلا», **Then**
   every remaining bubble appears at once, nobody talks, and the panel stays. **When** they tap «يلا»
   again, **Then** the next panel shows (or, on the last panel, the scene finishes), as in M07.
6. **Given** a panel whose last turn has started, **When** the player taps «يلا», **Then** the next
   panel shows at once, and the speaker stops talking.
7. **Given** any turn of any panel, **When** the player taps «تخطّى» or the phone's back button,
   **Then** the scene finishes at once, as in M07 (FR-008), and nothing keeps talking.

---

### User Story 2 - Every panel still shows without the animation (Priority: P1)

Some phones can't play the animation, a build can ship a broken file, and some players turn on
reduced motion. In each case the scene plays exactly as M07 built it: the still drawing, every
bubble at once and «يلا» moving on. Nothing fails, and on internal builds the debug panel says what
was wrong.

**Why this priority**: The opening stands between a new player and the first trip. A problem with the
art must never block it, and the drawings are already tested and approved.

**Independent Test**: Run the scenes three ways: without the file, with one panel's artboard broken,
and with reduced motion on. Every affected panel shows its drawing and the others still animate.
M07's scene goldens and widget tests pass without being updated.

**Acceptance Scenarios**:

1. **Given** the file is missing from the build, can't be decoded, or the device can't play Rive,
   **When** any scene plays, **Then** every panel shows its still drawing, with M07's behaviour, and
   startup goes on as usual.
2. **Given** one panel's artboard fails its check (missing, the wrong size, no `Panel` state machine,
   another view model, or a missing or mistyped Boolean), **When** the scene plays, **Then** that
   panel shows its drawing, and the other panels animate.
3. **Given** reduced motion is on, **When** any scene plays, **Then** every panel shows its still
   drawing, every bubble shows with the panel and nobody talks. Panels change by M07's short fade.
4. **Given** a panel slug with no animation and no drawing (such as `ch1_moallem_counts`, the first
   panel of the draft's later chapter 1 scene `moallem_verdict`), **When** it shows, **Then** it draws
   M07's `PanelFallback`, as today.
5. **Given** a dev or staging build whose file has problems, **When** the tester opens the debug
   panel, **Then** it lists each problem of this file beside those of the first art file. A prod build
   shows nothing and falls back silently.

---

### User Story 3 - The سلمى scene, under the sample's names and the release draft's (Priority: P2)

After the first finish of tutorial trip 3, the سلمى scene plays animated in the same way: the usta
stretching at the stand in the morning, the usta and سلمى at the bus stop, and the usta putting a
coin in his savings tin. The release draft names these panels differently from the sample, but they
are the same three pictures, both as drawings and as animations.

**Why this priority**: It is the second scene of the first session and the other half of the
"done when". It works by the same mechanism as the opening once Story 1 does.

**Independent Test**: Play the sample's `the_stand` and the release draft's `first_sight`. Both show
the same three animations, and in each turn the character who talks is the speaker.

**Acceptance Scenarios**:

1. **Given** the sample's `the_stand` (`stand_morning`, `salma_waiting`, `usta_decides`), **When** it
   plays, **Then** each panel animates and its speaker talks in their turn: the usta, then سلمى, then
   the usta.
2. **Given** the release draft's `first_sight`, whose panels are `ch1_stand_morning`,
   `ch1_salma_asks` and `ch1_usta_dreams`, **When** it plays, **Then** they draw the same art as
   `stand_morning`, `salma_waiting` and `usta_decides`: the animation when it can play, else the same
   still drawing.
3. **Given** `ch1_salma_asks` (سلمى, then the usta), **When** it plays, **Then** سلمى talks in her
   turn and the usta in his.
4. **Given** `ch1_usta_dreams`, whose two lines are both the usta's (Clarifications), **When** it
   plays, **Then** the usta talks in his first turn, stops for the pause, and talks again in his
   second, under the first bubble.

---

### Edge Cases

- **Unknown artboards.** The file holds artboards the contract doesn't name. Its building blocks (the
  four characters, the six props, the tuktuk) and the export's own artboards are known and accepted.
  Any other artboard is listed as a problem and changes nothing else (FR-003).
- **A speaker the panel can't animate.** A character without a Boolean (such as a later chapter's
  `bride_father`) and a character with a Boolean who isn't drawn in the panel each still get their
  turn and their bubble. Nothing talks during that turn, and it isn't a problem (FR-019). Today's
  scenes have no such line (Clarifications), but a later pack can.
- **The splash the board warns of.** The board «حركة المشاهد» says the free-plan export shows a «RIVE»
  splash for about 2.4 s at the start of each panel. The app's runtime doesn't: a panel shows its own
  first frame at once and moves from the first fraction of a second (Assumptions). If a phone ever
  shows the splash, that is a defect of this feature, not something to wait out (SC-001).
- **A caption-only panel.** It has no turns: the caption shows with the panel, and nobody talks.
- **The same speaker twice in a panel.** Two turns, one after the other, with the pause between them.
- **More than two lines.** The schema allows up to eight lines in a panel. Constitution XI allows at
  most two bubbles on screen, so when a third bubble appears, the oldest goes. Today's scenes have at
  most two spoken lines per panel.
- **Reduced motion changes during a scene.** Turned on, the current panel switches to its drawing
  with every bubble shown and nobody talking. Turned off, the current panel switches to its
  animation, keeps the bubbles it already showed and starts no new turn, and the next panel plays its
  turns.
- **The app goes to the background mid-turn.** On return, the panel continues. No bubble is lost, and
  no turn starts over from the beginning.
- **Short screens.** M07 makes the panel shorter than 540 pt on short screens. The animation fills
  the panel the same way the drawing does: it keeps its proportions and is anchored at the bottom
  centre, so the sky is cut first and nothing is stretched (FR-008).
- **Text scale 1.3.** Bubbles wrap and grow as in M07, so turns change only when bubbles appear, not
  where they go.
- **A screen reader.** Every line is in the read order from the panel's start, whether or not its
  bubble has appeared yet. The turns are visual only (FR-018).
- **A slug with a drawing but no animation** (M10's chapter 2–4 panels, until they get one): the
  drawing, with M07's behaviour.
- **A failed check is never fatal.** If the check itself throws, it counts as a file that failed to
  load: everything is drawn with the drawings, and startup goes on (FR-004).

## Requirements *(mandatory)*

### Functional Requirements

#### The scenes file

- **FR-001**: The app MUST ship a second art file, `wassal_scenes.riv`, beside the first
  (`wassal.riv`). It MUST be decoded once, in the same startup step as the first, and checked against
  this feature's contract before any scene plays.
- **FR-002**: The contract, as the file was ordered from Claude Design:
  - one 358×540 artboard per panel slug: `opening_key`, `opening_stand`, `opening_go`,
    `stand_morning`, `salma_waiting` and `usta_decides`;
  - in each, a state machine `Panel` that plays by itself;
  - as each artboard's default view model, `Panel`, with four Booleans: `moallem`, `usta`, `belya`
    and `salma`. Each one makes that character talk where they are drawn.
- **FR-003**: The app MUST open the file's artboards by name only, and MUST never draw any of them on
  its own except the six panels. The check MUST accept without a problem:
  - the file's building blocks, which the panels draw inside themselves: `Character_usta`,
    `Character_moallem`, `Character_belya` and `Character_salma`; `Prop_tin`, `Prop_key`,
    `Prop_drawer`, `Prop_busstop`, `Prop_books` and `Prop_bag`; and `Tuktuk`;
  - the export's own artboards: the default `Artboard 1`, and the free plan's `Watermark`,
    `NuRiveBrandmark01` and `NuRiveWordmark01`.

  Any other artboard MUST be listed as a problem, and MUST change nothing else.
- **FR-004**: A file that is missing, isn't a Rive file, can't be decoded, or whose check throws MUST
  leave every panel to its drawing. An artboard that fails its check MUST leave only that panel to its
  drawing. Startup MUST never fail because of this file, and MUST keep its time budget (SC-003).
- **FR-005**: On dev and staging builds, the debug panel MUST list this file's problems beside the
  first file's. A prod build MUST fall back silently.

#### What a panel draws

- **FR-006**: A panel MUST draw the first of these that applies:
  1. its animation, when the file loaded, the panel's artboard passed its check and reduced motion is
     off;
  2. its still drawing, when the app ships one;
  3. M07's `PanelFallback`.
- **FR-007**: Under reduced motion, a panel MUST draw its still drawing (or the fallback) even when
  its animation is available. The file has no input that holds its motion still, as with 008.5's
  people (`rive-characters.md` "Open" 2).
- **FR-008**: The animation MUST fill the panel the same way the drawing does: in proportion, filling
  the panel, anchored at the bottom centre. On a shorter panel it loses sky first, and it is never
  stretched.
- **FR-009**: A panel's animation MUST start from its beginning each time the panel shows, play by
  itself, and loop until the panel leaves. It MUST stop and release its resources when the panel
  leaves or the scene ends.
- **FR-010**: The release draft's names MUST draw the same art as the sample's, both the drawing and
  the animation: `ch1_stand_morning` as `stand_morning`, `ch1_salma_asks` as `salma_waiting`, and
  `ch1_usta_dreams` as `usta_decides`. Every other slug keeps what it draws today.

#### Talking in turn

- **FR-011**: When a panel animates, its spoken lines (every line but the caption) MUST play as turns,
  one at a time, in the panel's order. The caption shows with the panel and takes no turn.
- **FR-012**: In a turn, the speaker's bubble appears with the design's bubble pop (`bubblePop`, as
  character bubbles already do; M07's panel bubbles arrive with the panel and don't pop), and the
  speaker's Boolean is true until the turn ends, then false. At most one Boolean MUST be true at
  any moment. None is true between turns, after the last turn, or during a turn whose speaker has no
  Boolean. Turns MUST be silent, as M07's scenes are: no sound plays when a bubble appears or a
  character talks.
- **FR-013**: The first turn MUST start once the panel has finished coming in. A turn MUST last longer
  for a longer line, between a floor and a ceiling. The next turn MUST start after a short pause.
  Assumptions gives the default values.
- **FR-014**: A bubble MUST stay once it has appeared, stacked under the earlier one as in M07. After
  the last turn, the panel shows its bubbles as M07 does. No more than two bubbles MUST show at once
  (constitution XI): when a third appears, the oldest goes.
- **FR-015**: «تخطّى» and the back button MUST finish the scene at once, during any turn (M07 FR-008).
  Whenever a panel leaves, its talking MUST stop.
- **FR-016**: When the player taps «يلا» on an animated panel before its last turn has started, the
  app MUST end the turns: every remaining bubble appears at once (at most two in all, FR-014), every
  Boolean turns false, and the panel stays while its animation keeps looping. The next «يلا» MUST
  move on as in M07: to the next panel, or, on the last panel, to the end of the scene. Once the last
  turn has started, «يلا» MUST move on at once. On a panel with a drawing or the fallback, «يلا»
  always moves on at once (FR-017). The tap that shows the rest MUST give the same press feedback as
  any «يلا» tap.
- **FR-017**: When a panel draws its still drawing or the fallback, M07's behaviour MUST stay exactly
  as it is: every bubble shows with the panel, there are no turns, and «يلا» moves on. Nothing in the
  panel talks, and M07's scene goldens and tests stay as they are.
- **FR-018**: The read order MUST stay M07's: the title, the caption, each speaker and line, «اللوحة
  {n} من {total}», «يلا», then «تخطّى». It MUST include every line of the panel from the panel's
  start, whether or not its bubble has appeared yet.
- **FR-019**: A speaker the panel can't animate MUST still get their turn and bubble, with nothing
  talking during it, and MUST NOT be logged as a problem. That covers a speaker without a Boolean
  and a speaker who isn't drawn in the panel.

#### Limits

- **FR-020**: This feature MUST NOT change any trip rule, the engine, the economy, a content schema or
  a pack's content. It adds no scene and no new drawing. In `wassal.riv`, it MUST change nothing but
  the usta's look (FR-023).

#### Testing

- **FR-021**: Tests MUST cover the following:
  - the order of what a panel draws (animation, drawing, fallback), with a missing file, a broken file
    and each kind of failed artboard;
  - the accepted extra artboards, and an unknown one listed as a problem;
  - for each spoken line of the sample's and the draft's scenes, the speaker's Boolean true during
    their turn and every other Boolean false; the turns' order, pause and bounds; and no sound;
  - reduced motion: the drawing, every bubble at once, and nobody talking;
  - the draft's three names;
  - «يلا», «تخطّى» and back during a turn;
  - the file itself (tag `rive`): for every spoken line of those scenes, switching the speaker's
    Boolean on visibly changes the panel;
  - the updated `wassal.riv`: its existing Rive goldens change only where they draw the usta
    (`look` 18), which shows that nothing else in the file moved (FR-023);
  - Rive goldens (tag `rive`) of each panel's first frame, beside its drawing.
- **FR-022**: M07's goldens and widget tests, which run without the file, MUST pass without being
  updated, except the goldens that draw the static usta, which change for his look alone (FR-023).
  The scene panels' goldens don't change: the drawings already show the panels' usta. The
  first-session integration test MUST pass whether or not Rive can play in its runner.

#### The usta's look

- **FR-023**: The usta MUST look the same in every piece of art, as the panels draw him: the lighter
  skin and the forelock (Clarifications). Specifically:
  - the owner's updated `wassal.riv` MUST replace the current one. Only `look` 18 changes; the other
    23 people and the four vehicles stay pixel for pixel as they are, and the file MUST still pass
    008.5's contract;
  - `docs/design/` MUST be rebuilt from the updated canvas with its tools (its README, "When the
    canvas changes"), so the characters sheet's usta is the new one;
  - the app's static usta, drawn wherever Rive isn't (the avatar, `PanelFallback`, the Name card),
    MUST be copied from the rebuilt design;
  - the goldens that draw the usta, static or Rive, MUST be rewritten and reviewed, and no other
    golden may change because of this.

### Key Entities

- **Scenes art file**: the second Rive file, beside the first. Decoded at startup and checked once.
  What it holds is in [The file as delivered](#the-file-as-delivered-checked-2026-10-28).
- **Panel animation**: one artboard per panel slug. It loops by itself and has four talking switches,
  one per character (`moallem`, `usta`, `belya`, `salma`).
- **Turn**: one spoken line of an animated panel, with its speaker, its bubble and the time the
  speaker talks.
- **Art alias**: a slug that draws another slug's art, for the release draft's three names.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On the Redmi Note 7 and the Galaxy A06, the opening and the سلمى scene animate, and no
  panel shows Rive's splash. In every turn of every panel, the character who talks is the one whose
  bubble just appeared. The owner checks each panel on both phones.
- **SC-002**: On the Galaxy A06, a scene plays at a 60 fps target and never drops below 45 fps, the
  trip scene's floor (constitution, "Performance budgets").
- **SC-003**: Cold start to Home stays under 3 s on the Galaxy A06 with both art files. A new player
  who taps through the opening and accepts the suggested name still starts the first trip within 20 s
  of opening the app (M07 SC-001).
- **SC-004**: Without the file, with any one panel's artboard broken, or under reduced motion, 100% of
  the affected panels show their drawing, and every M07 scene golden matches without an update. The
  only M07 goldens that change are those that draw the static usta, and only by his look (FR-023).
- **SC-005**: For every spoken line of the sample's `opening` and `the_stand` and the draft's
  `first_sight` (13 lines in 9 panels), the tests find the speaker's Boolean true for exactly their
  turn, and the speaker visibly talks in all 13 turns.
- **SC-006**: The file adds under 100 KB to the app (it is 49.6 KB), and the Android download stays
  under 80 MB.
- **SC-007**: The usta looks the same in the panels, in the trip's art and in the static art: one
  look, the panels' (FR-023).

## Assumptions

### The file as delivered (checked 2026-10-28)

The file was checked by decoding and rendering it with the app's own Rive runtime: its artboards,
state machines and view models, frames across its loop, and each Boolean on and off. The board
«حركة المشاهد» (`SceneMotion` on the design canvas, read the same day) describes the same file. Its
notes are in the section after Claude Design's report.

- 49,610 bytes, exported from Rive's free plan, with data binding. Its editable source is in the
  owner's Rive account.
- **The six panels**: `opening_key`, `opening_stand`, `opening_go`, `stand_morning`, `salma_waiting`
  and `usta_decides`, each 358×540. Each has one animation, `scene` (4.8 s, looping), and the state
  machine `Panel`, its default. Each has the view model `Panel` as its default, with the Booleans
  `belya`, `moallem`, `salma` and `usta` and one instance, all false. The file has no other view
  model. It draws no text.
- **Who talks where.** Switching a Boolean on changes the panel only where that character is drawn:

  | Panel | Talks | Also in the panel |
  | --- | --- | --- |
  | `opening_key` | المعلم, the usta | the tuktuk's nose; the key |
  | `opening_stand` | المعلم, the usta | the tuktuk and its money drawer |
  | `opening_go` | المعلم, بلية | the usta at the tuktuk's wheel (he doesn't talk here) |
  | `stand_morning` | the usta | the tuktuk, a microbus, the sun |
  | `salma_waiting` | the usta, سلمى | the bus stop, her books and bag, a heart |
  | `usta_decides` | the usta | the tuktuk, the savings tin and a coin |

  Every spoken line of the sample's two scenes and of the draft's `first_sight` has its speaker
  drawn in its panel, the draft's since its بلية line went to the usta (Clarifications).
- **The building blocks**: `Character_usta`, `Character_moallem`, `Character_belya` and
  `Character_salma` (240×440, each with `idle` 4.8 s, `talk` 0.5 s, `talk_off` 0.1 s and its own
  gestures); `Prop_tin`, `Prop_key`, `Prop_drawer`, `Prop_busstop`, `Prop_books` and `Prop_bag`; and
  `Tuktuk` (`idle`, `drive_start`, `driving`, `parked`). The panels draw them; the app never opens
  them on their own.
- **The export's own artboards**: `Artboard 1` (500×500, the file's default), and the free plan's
  `Watermark`, `NuRiveBrandmark01` and `NuRiveWordmark01`. As with the first file, the app selects
  artboards by name, so the splash is never shown.
- **No reduced-motion input**, so FR-007 applies.

### What Claude Design reported (pasted by the owner, 2026-10-28)

Claude Design listed what it did differently from the brief. None of it changes the contract
(FR-002), and the app works around none of it.

| Report | What it means here |
| --- | --- |
| **No bones.** Its Rive tool can't create bones, so arms and heads swing from grouped pivot points. It moves the same way and stays light on low-end phones. | Nothing for the app to do. Lighter for SC-002. |
| **The source is named «Untitled»** in the owner's Rive account (`https://editor.rive.app/file/untitled/2688256`), and Claude Design couldn't rename it. | Owner step: rename it to `wassal_scenes`, and move it into `wassal.riv`'s folder if they should sit together. The app's copy keeps its name. |
| **The driver's look.** The characters sheet draws the usta with darker skin and no forelock. All six panels draw him lighter, with a forelock. It followed the panels, so the first frames match the drawings. | Decided: the panels win (Clarifications). The owner updated the canvas's characters sheet (skin `#C68B5E` → `#E0A97A`, plus the forelock) and `wassal.riv`, whose `look` 18 is the only change; the file passes 008.5's contract test. The repo's design copy and the app's static usta still show the old look, so FR-023 brings them in. |
| **Wheel spokes in `opening_go`.** The drawing has plain hubs, so turning wheels wouldn't show. It added spokes that fade in over the first 0.6 s. | The first frame still matches the drawing, which the first-frame goldens show (FR-021). |
| **The stretch in `stand_morning`.** The usta stands near the right edge, so his right arm drops only a little and his hand stays in the frame. | Nothing for the app to do. |
| **Edges and the top 180 px.** The bus-stop sign, the tuktuk on the left and المعلم's waving hand are within 16 px of the sides, as in the drawings. In `stand_morning`, the top of the sun's glow (about y 137–180) pulses slowly in the bubbles' area, because the brief asked for the glow. | Bubbles and the caption are opaque, so the glow behind them doesn't touch text contrast (constitution XI). On short screens the panel loses sky first (FR-008), which takes the glow first. |
| **Extra artboards.** The export adds Rive's splash artboards and an empty `Artboard 1`. | Accepted and never drawn (FR-003). |

### The board «حركة المشاهد»

The board agrees with the contract (FR-002) and with this spec:

- A panel's first frame is its still drawing.
- A Boolean whose character isn't in the panel is ignored, and with every Boolean false the
  characters breathe and blink.
- Above 180 px there is only sky and background.
- The art fills the panel from the bottom (FR-008), with what matters at least 16 px from the sides,
  as in the drawings.
- Every loop is 2.4 or 4.8 s, so it closes without a jump.
- Each panel lists what moves in it, and which character and tuktuk state it uses, as in the table
  above.

It also says that, as a free-plan export, the file shows Rive's «RIVE» splash for about 2.4 s at the
start of each panel, and that each scene waits and then starts from its first frame. The app's
runtime does neither. Rendered with it, every panel draws its own art from the first frame, and its
loop has already moved by 0.35 s. The note probably describes the editor's preview; the Rive runtime
has no splash logic, as 008.5 found (`rive-characters.md` "Export"). The device check in SC-001
confirms it on both phones.

The HANDOFF.md rebuilt from the canvas on 2026-10-28 (§6.8, "Comic panels") says the same as the
board, splash note included, and adds `Fit.cover` with bottom-centre alignment, which FR-008
already requires. Where it differs from this repo's rules (its §6.6 keeps Lottie as a fallback),
the overrides in `docs/design/README.md` win, as always.

### The gap that was closed: بلية in `ch1_usta_dreams`

The release draft's `ch1_usta_dreams` had the usta's line, then بلية's, over `usta_decides`, whose
art (the drawing and the animation) shows the usta alone. بلية's bubble would have appeared with
nobody talking. On 2026-10-28 the owner gave the line to the usta (Clarifications). The draft in the
`content-core-r1` worktree now reads «بس الأول لازم أركّز في الأجرة», in the pack file and in
`BRIEF.md`. It passes `validate-source` with the current schemas: 0 errors, 0 warnings. That
worktree's own content kit is older than M07, so it rejects `plays` until the worktree is updated.
The art doesn't change.

### Defaults chosen here

- **Turn timing** (FR-013): a turn lasts about 60 ms per letter of the line, at least 1.2 s and at
  most 4 s, with a 0.3 s pause between turns. The first turn starts when the panel's slide-in ends,
  within M07's 280 ms. These are presentation values, not balancing numbers, so they need no Remote
  Config key (constitution VIII). The plan places them with the other motion values.
- **Talking is the file's.** The app only switches the Booleans. Each character's mouth moves with
  its own `talk` loop and closes with `talk_off`.
- **Bubbles stay** (FR-014). They don't replace one another, so a finished panel looks like M07's
  and the `Intro` artboard's.
- **Turns only when the panel animates** (FR-017). With a drawing nothing talks, so turns would only
  slow reading down, and M07's behaviour (tested and approved) stays as it is.
- **The file is decoded at startup, not when a scene opens**, because a new player's first screen
  after Loading is the opening scene. At 49.6 KB it adds little to startup.
- **The same check as the first file.** An artboard that breaks the contract falls back on its own,
  and a problem in the file never blocks a scene. The debug panel is 008.5's.
- **The trip's art tier doesn't apply.** 008.5's `ArtTier` decides which of a trip's seats Rive
  draws, under the trip's load of twelve passengers. A scene draws one light panel at a time, so it
  animates whatever the tier. SC-002 measures it on its own.
- **Testers open each scene from M07's playtest «Onboarding» card**, on dev and staging, so the
  owner's check in SC-001 needs no replay of the tutorial trips.

### Dependencies

- M07 (`specs/012-m07-onboarding/`) and M21 (`specs/008.5-m21-design-refresh/`), both merged: the
  scene player, `ComicPanel`, `PanelArt` and `PanelFallback`, the boot step that loads Rive art, the
  debug panel, and the six drawings.
- The file itself, staged in this branch at `apps/mobile/assets/rive/wassal_scenes.riv`, and the
  owner's updated `wassal.riv` (FR-023), already in this branch's working tree. Both land with this
  feature's pull request.
- The updated canvas «وصّل الأجرة — Design» (the characters sheet's new usta), from which
  `docs/design/` is rebuilt (FR-023).
- The release draft's scene names and lines come from the `content-core-r1` worktree
  (`content/drafts/core-r1/pack/chapters/ch1_first_job.json`). The draft isn't committed anywhere
  yet; the line change above was made there, and it moves with the draft, not with this feature.
- Chapters 2–4's scenes (M10) can follow the same path later: a drawing, an artboard named after its
  slug in this file or in a later one, and the same four Booleans or more.
