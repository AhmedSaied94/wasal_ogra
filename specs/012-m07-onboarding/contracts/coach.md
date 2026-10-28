# Contract: The Tutorial Coach

What each tutorial trip teaches, when a step starts and ends, what it points at, and how it is drawn.
Spec FR-020–FR-030, FR-038, FR-044, FR-045; research R14, R16–R18.

## `TutorialCoach` (pure, `lib/features/onboarding/domain/tutorial_coach.dart`)

```text
CoachView? step(CoachInput input)
CoachInput  = { lesson: 0..4, state: TripState, view: TripView, memory: CoachMemory,
                tMs: int, trayDenominations: List<Denomination> }
CoachView   = { lessonStep: CoachStepId, targets: [CoachTarget] (1, the active one first),
                line: CoachLine, endsOnAnyTap: bool }
CoachTarget = tray | trayCell(Denomination) | passenger(passengerId) | stationCountdown
CoachLine   = fareArrived | giveChange(amountPiasters, coin?, count?) | tapRider
            | stopNear(stationId) | wakeSleeper
CoachMemory = { done: Set<CoachStepId>, shownAtMs: Map<CoachStepId, int> }  (per trip run)
```

`TripController` holds the memory, resets it on `open`, records a step as done when its end holds,
and calls `step` on every publish. `null` means no step. `TripModel.coach` carries the result.
`TutorialCoach` is the only reader of `PassengerState.balance` outside the engine and the projection
(a guard checks the import).

## Lessons

"Owed" is `p.presence == aboard && p.isOwed` (`fareSent && balance > 0`), with the fare arrived
(`p.paidIn > 0`) and no live `change` token targeting `p`.

| Lesson | Step | Starts when | Targets | Line | Ends when |
| --- | --- | --- | --- | --- | --- |
| 0 (trip 1) | `fareArrived` | some passenger's `paidIn > 0` | `tray` | `fareArrived` | any tap (the tap is consumed by the scrim, not passed on), or `tMs − shownAt ≥ trip_bubble_min_ms_<line>` |
| 1 (trip 2) | `giveChange` | the first owed passenger `p` (lowest seat order) | `trayCell(coin)` while `hand total < p.balance`, then `passenger(p)` | `giveChange(p.balance, coin, count)`; then `tapRider` | a `change` token targeting `p` exists, or `p` is no longer owed, or gone |
| 2 (trip 3) | `stopNear` | some owed `p` has `PassengerView.nearStopPulse` | `stationCountdown`, then as lesson 1 (`trayCell`, then `passenger(p)`) | `stopNear(p's station)`; then `giveChange`/`tapRider` | as lesson 1, or `p`'s station is reached |
| 3 (trip 4) | `wakeSleeper` | some aboard `p` with `alertness == asleep` | `passenger(p)` | `wakeSleeper` | `p.alertness != asleep`, or `p` gone |
| 4 (trip 5) | — | no in-trip step: the fuel lesson comes before the trip (contracts/fuel-lesson.md) | — | — | — |

- **The coin** for `giveChange` is the largest denomination `d` with `p.balance % d == 0` and
  `tray[d] ≥ p.balance / d`. `count = p.balance / d`. With none, `coin` and `count` are null and the
  fallback line is used, with the target `tray`.
- **Lesson 2's first target** (`stationCountdown`) shows for `trip_bubble_min_ms_<line>`, then moves
  to the coins. Taps during it fall through only on the countdown chip, which does nothing; the
  player may wait it out.
- **At most one step:** lessons are evaluated in order, and a step in `done` is skipped. A step whose
  start condition no longer holds before its end ends silently.
- **Ordinary hints** (`HintState`) are not shown while `TripModel.coach != null`.

## Lines (`app_ar.arb`)

| `CoachLine` | Key | Text |
| --- | --- | --- |
| `fareArrived` | `coachFareArrived` | «شايف؟ الأجرة وصلت الدرج» |
| `giveChange` (coin) | `coachGiveChange` | «ليه باقي {amount}. دوس على {coin} {count, plural, =1{مرة} =2{مرتين} few{{count} مرات} other{{count} مرة}}، وبعدين دوس عليه.» |
| `giveChange` (no coin) | `coachGiveChangeAny` | «ليه باقي {amount}. خد الفكة من الدرج، وبعدين دوس عليه.» |
| `tapRider` | `coachTapRider` | «دلوقتي دوس عليه.» |
| `stopNear` | `coachStopNear` | «نازل {station}، لازم ياخد باقيه قبلها» |
| `wakeSleeper` | `coachWakeSleeper` | «ده نايم، دوس عليه صحّيه» |
| (name label) | `coachName` | «بلية» |
| (semantics) | `coachAnnouncement` | «بلية: {line}» |
| coin names | `coachCoinName` | `{denomination, select, v50{النص جنيه} v100{الجنيه} v500{الخمسة} v1000{العشرة} v2000{العشرين} v5000{الخمسين} v10000{المية} v20000{الميتين} other{الفكة}}` (the `Denomination` enum names) |

`amount` is formatted by the app's money formatter in the player's digit style (`٣`, `٣٫٥`); `count`
is a plural number formatted by the same digit setting. Owner approval: owner-actions.

## بلية's bubble and the two-bubble limit (constitution XI)

Constitution XI allows at most two speech bubbles at once, each up for at least `trip_bubble_min_ms`.
بلية's bubble, from a coach step or an ordinary hint, is a speech bubble and follows both rules:

- **It counts as one of the two.**
  - It appears only when at most one rider's bubble is visible. Until then, a step shows its scrim,
    hole, ring and hand without the bubble. The wait is at most one rider bubble's minimum time. The
    announcement is made when the step starts.
  - While it is visible, at most one rider's bubble shows. Other lines wait, as they already do when
    two are up, and are dropped after `2 × bubbleMinMs` as before.
- **It stays up for its minimum time.** When a step ends sooner (the player acted, the target left),
  the scrim, the hole, the ring and the hand go at once, and taps reach the game again. بلية and the
  bubble stay, without the scrim, until the bubble's time is up. The next step's or hint's bubble
  waits for it.
- **Where:**
  - `BubbleQueue.at(tMs, bubbleMinMs:, reserved:)` in `features/trip/domain/bubble_queue.dart`:
    `reserved` (default 0) takes slots from `maxVisibleBubbles`, so M02's callers are unchanged;
  - `PresentationMemory` keeps بلية's bubble (its line, its source, `shownAtMs`) and passes
    `reserved: 1` while it shows;
  - `CoachLayer` and `HintLayer` draw it from there.
- This also brings M02's hints under the limit, which they weren't.

## The overlay (`CoachLayer`, `lib/features/onboarding/presentation/coach_layer.dart`)

- Placed in `TripScreen`'s stack above `HintLayer` and below the cards. It is shown while
  `TripModel.coach != null` and the phase is `running`, and after a step ends while its bubble's
  minimum time runs (then only بلية and the bubble, which take no touch).
- Built on 008.5's `CoachMark(target:, children:, showHand: true)`:
  - `target` = the active target's rect in the stack's coordinates, from `CoachAnchors`;
  - the scrim, the hole (`inflate(6)`, r 18), the 4 pt `sun` ring, and `CoachHand` at the target;
  - taps inside the hole reach the control below; outside, they are absorbed (lesson 0 ends on that
    tap).
- `children`: `CharacterAvatar('belya')` 96×110 at the scene's bottom-end corner (`x = w − 102`,
  overlapping the dashboard by about 30 pt), and `SpeechBubble.character(name: coachName)` with the
  line, end-aligned left 14 / right 104, above بلية. Both in `IgnorePointer`.
- **Anchors** (`features/trip/presentation/coach_anchors.dart`):
  - `CoachAnchor(id, child)` is a `SingleChildRenderObjectWidget` whose render box reports
    `localToGlobal` rects to `CoachAnchors` after each layout;
  - ids: `tray`, `trayCell(<denom>)`, `stationCountdown`;
  - wraps: `Tray`, each `TrayCell`, and the `StationStrip`'s countdown chip.
  - Passengers: `SceneLayout.seats[seatId].hit` offset by the scene's origin (`TripZones.left`,
    `.sceneTop`).
  - A target with no rect (not laid out yet) shows no hole for that frame.
- **Motion** (`MotionTokens`, new where marked): scrim fade 200 ms (`coachScrimFade`, new); the hole
  moves 250 ms `easeOutCubic` (`coachHoleMove`, new); the ring pulses 1.0↔1.06 with `hotTagPulse`;
  the hand bobs (`CoachHand`). Reduced motion: no pulse, no bob, the hole jumps.
- **Semantics:** at a step's start, `SemanticsService.announce(coachAnnouncement(line))`. While a step
  shows, everything except the target's subtree is under `ExcludeSemantics`, and the target is focused
  on the next frame.
- **Back** opens the pause card (unchanged). After resume, the step is recomputed.

## The locked boosters bar (`BoostersLockedBar`)

- `features/trip/presentation/dashboard/boosters_locked_bar.dart`: full row width, 44 tall, r 14
  (`RadiusTokens`), `dashboard.raised`; lock icon 16 (`assets/icons/lock.svg`) and
  `tripBoostersLocked` «المساعدات بتتفتح بعد المشوار الخامس», `caption` 600, `dashboard.muted`,
  centred.
- `TripFacts.boostersLocked` swaps it for `BoostersRow`. Semantics: the text, as a label (not a
  button).

## Tests (in contracts/ci-checks.md)

- One unit test per lesson row: each start condition, each target, each end, and a step that ends
  because its target left.
- The coached player: plays a fixture trip by taking every step's active target, and finishes with at
  least one star.
- The overlay: taps outside the hole do nothing, a tap inside reaches the control, the hole follows
  the target after a relayout, the announcement fires once per step, and reduced motion removes
  pulse and bob.
- بلية's bubble: with two rider bubbles up, a step's bubble waits; while it shows, at most one rider
  bubble shows; after a step ends early, the scrim is gone at once and the bubble stays its minimum
  time; a hint follows the same rules.
