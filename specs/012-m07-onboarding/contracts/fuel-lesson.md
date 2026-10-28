# Contract: The Fuel Lesson and the Tutorial Gift

Two parts: the brief for the new `FuelLesson` artboard (drawn on the Claude Design canvas «وصّل الأجرة —
Design», Clarifications Q4), and how the app uses it. Spec FR-033–FR-035; research R9, R10.

## Part 1: artboard brief (for the canvas)

Written in the shape of a HANDOFF §11 section, so the export can be reviewed against it. Sizes are a
proposal: the drawn board decides, and its `boxes/FuelLesson.json` becomes the layout test's source.

**As drawn (2026-10-28).** The board follows the brief, except:

- the circles are `primary.soft`, as on `Name`;
- the gauge is 220×124: an arc of r 72, 22 wide, with the pump inside it and the marks E (`danger.ink`)
  and F under its ends;
- the needle stops 23° short of each end;
- the value sits 2 under the gauge, without an icon.

### تفويلة من المعلم — `FuelLesson`

| | |
| --- | --- |
| Route | `/onboarding/fuel` (full screen), before the last tutorial trip |
| Feature folder | `features/onboarding/` |
| Phase | MVP |
| Files | `screens/FuelLesson.html` · `png/FuelLesson.png` (after export) |

**Purpose.** Once per player, before trip 5 of the tutorial (or earlier, if the tank runs dry during
the tutorial), المعلم explains fuel in one card and fills the tank as a gift. One button goes on to
the trip.

**Layout, top to bottom** (proposal; same frame and rhythm as `Name`):

| # | Block | Size | Content & components | Tokens |
| --- | --- | --- | --- | --- |
| 0 | Background | 390×844 | as `Name`: two decorative circles | `ground` · circles `sun.soft` |
| 1 | Card | x16, vertically centred, 358 wide | `AppCard`, padding 76/20/22, gap 14 | `paper`, r `scene`, lip `card.big` |
| 1a | Avatar | 112×112, overlapping the card top by 56 | `CharacterAvatar` `moallem` in a circle | bg `sun`, lip `sun.lip` |
| 1b | Title | centred | «تفويلة من المعلم» | `display.l` · `ink` |
| 1c | Bubble | full card width | `SpeechBubble.character`: «المعلم» + «البنزين قرّب يخلص يا أسطى. كل مشوار بلتر، والمرة دي التفويلة عليّا!» | fill `ground` (it sits on the white card), name `label` `ink.muted`, text `quote` |
| 1d | Gauge | about 220×120, centred | A fuel gauge with its needle moving from the current level to full, the fuel icon, and the value «٥/٥» under it (`number` 20/700). Reuse the `Fuel` sheet's gauge drawing if it fits (`illustrations/screens/Fuel_01.svg`). | arc `track` → `station[2]` green; needle `ink` |
| 1e | Refill line | centred | «التانك بيتملى لوحده: لتر كل ٢٠ دقيقة.» | `body` · `ink.muted` |
| 1f | CTA | 318×60 | `AppButton.primary(l)` «يلا على المشوار» | `primary`, `lip.primary` |

**Dynamic data.**

- Gauge start → the current liters (sample: ١/٥); end → `fuel_max` (٥/٥).
- «٢٠ دقيقة» → `fuel_regen_minutes` (Remote Config), with Arabic number agreement.

**Interactions.**

| Element | Gesture | Result |
| --- | --- | --- |
| «يلا على المشوار» | tap | The tank is filled (the gift), then the tutorial's next trip opens |
| System back | press | Ignored (the lesson is one step of the linear first session) |

**States & edge cases.**

- The tank is already full (the player waited): the gauge shows full from the start, and the copy is
  unchanged.
- Shown once per player. Never again after the gift.

**Motion.** Card `dialogIn`. After it settles, the needle sweeps to full (600 ms, `easeOutCubic`), the
value counts up, and the button `press`es. Reduced motion: the gauge is drawn full, with no sweep.

**Accessibility.** Read order: title → المعلم's line → «البنزين {n} من {max}» → the refill line → the
button. The gauge is one semantics node with that label. Button ≥ 52 high.

**Strings.**

- `fuelLessonTitle: "تفويلة من المعلم"`
- `fuelLessonSpeaker: "المعلم"`
- `fuelLessonLine: "البنزين قرّب يخلص يا أسطى. كل مشوار بلتر، والمرة دي التفويلة عليّا!"`
- `fuelLessonGauge: "البنزين {liters} من {max}"`
- `fuelLessonRefill: "التانك بيتملى لوحده: لتر كل {minutes, plural, few{{minutes} دقايق} other{{minutes} دقيقة}}."`
- `fuelLessonCta: "يلا على المشوار"`

**Notes.**

- Style C, «كرتون ناعم»: no outlines, lips for depth, Marhey for the title and the quote.
- One `CharacterAvatar`; المعلم's look is the Rive `Person` look 22, with the SVG `moallem` as the
  fallback.

## Part 2: the app

- **Route:** `/onboarding/fuel?then=<tripId>`. The router redirects a tutorial trip's start here when
  `FirstSession.beforeStart` says so (contracts/first-session.md).
- **Screen:** `FuelLessonScreen` (`lib/features/onboarding/presentation/fuel_lesson_screen.dart`),
  built to the exported artboard with 008.5's components. It was built to the brief first, so the
  integration test wasn't held up by the drawing, then aligned to the board (T079, T080).
- **The gauge** uses Rive's `FuelGauge` contract (`core/art/rive_art.dart`) when present, with a
  static drawing as the fallback, like every other Rive art.
  - The Rive artboard (156×110, an arc of r 48) is drawn at 1.5×, so its arc lies on the board's.
  - The pump and the E and F marks are drawn over either gauge.
- **The button:**
  1. `economy.grantTutorialGift(txnId)`:
     - `OpApplied`: the tank is full;
     - `OpRefused(alreadyGranted)` (granted meanwhile): carry on without error.
  2. `firstSessionService.markFuelLessonDone()`.
  3. `context.go('/trip/<then>')`. The redirect doesn't repeat: the lesson is done.
- **A kill** before the button leaves no gift and no mark, so the lesson shows again (FR-033 "once"
  counts lessons completed).

## The operation `tutorial_gift`

| Side | Rule |
| --- | --- |
| Phone validate | `alreadyGranted` when `EconomyState.tutorialGranted` |
| Phone apply | `fuel = fillToMax(fuel, t, max: fuelMax) ?? fuel`; `tutorialGranted = true`; `fuelDelta` recorded |
| Phone `stillValid` | `!base.tutorialGranted` |
| Wire | `{"client_txn_id", "op_type": "tutorial_gift", "occurred_at", "payload": {}}` |
| Server (B03) | `already_granted` once granted; otherwise fuel to max (a full tank is accepted unchanged), `GrantRecord(tutorial)`, no ledger entry |
| Rejected | rolled back by M06's fold; the fuel shown follows the server's; M06's toast fires (fuel is visible) |
| Restore | `grants.tutorial` from GET /v1/state → `tutorialGranted` |
