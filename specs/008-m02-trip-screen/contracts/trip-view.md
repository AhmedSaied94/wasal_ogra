# Contract: What the Trip Screen Shows

How the engine's state and events become what the player sees, hears and feels. Everything here is
pure Dart in `lib/features/trip/domain/` (no Flutter), tested without a screen. The types are in
[data-model.md](../data-model.md).

## The projection

`projectTripView(state, memory, facts, screen)` builds the `TripView` after every step and every
accepted command.

| View part | From |
| --- | --- |
| `topBar.reputation` | `state.reputation`; `reputationLow` below 40 (presentation constant) |
| `topBar.tripNumber` | the digits after the dot in `trip_id` |
| `topBar.lineName` | the line's `name['ar-EG']` from the trip's line, or null (then the top bar shows only the number) |
| `strip.chips` | `state.schedule` in order, slot = index (≤ 4); price = `fare_piasters + state.fareIncreasePiasters`; `reached` for indexes below `state.nextStation`; `studentIcon` when `rules.student_discount_pct > 0` |
| `strip.countdownMs` | `nextStation.atMs − tMs`, or null after the last station |
| `strip.warning` | `countdownMs ≤ trip_station_warning_ms` |
| `strip.vehiclePermille` | position between the previous and the next station's `at_ms` |
| `passengers` | every passenger `aboard`, plus those boarding or leaving while their animation plays |
| `tokens` | `state.tokens`, kind `fare` for fare tokens and `change` for the others; `blocked` = `blockedBy != null`; `dropped` = `droppedUntilMs != null` |
| `dropped` | the tokens with `droppedUntilMs`, where they fell, until then |
| `windows` | `road`: `traffic` while `state.trafficActive`, `open` from an `open_road` `EventStarted` until the next `StationReached`, else `normal`; `waveAtMs`: a `roadside_pickup`'s `EventStarted`, for `waveMs` (1.2 s) |
| `hand`, `tray` | `state.hand`, `state.tray` |
| `breakButton` | `left = state.breaksLeft`, enabled when > 0 and running |
| `boosters` | the four in-trip boosters, with the economy's inventory, the catalog price when 0, and `traffic_jam` disabled at `booster_traffic_jam_max_per_trip` uses |
| `undoUntilMs` | `state.undoAvailableUntilMs` |
| `choices` | `state.claims` (claim), `state.changeRequests` (change request), and the dispute being asked |
| `storyCondition` | `kind == story` and `rules.no_fights_required` |
| `failSummary` | when failed (below) |

### Who has paid (FR-033)

The view has no field for a fare, a payment, a balance or a debt. The projection reads them only for:

| Allowed | Rule |
| --- | --- |
| `ledgerBadge` | Only while `state.ledgerPeekActive`: `paid` when the passenger's fare is sent (or their group payer's) and they don't owe; else `unpaid`. Null otherwise. |
| `nearStopPulse` | The passenger is in the last `StationWarning.owed` for the next station and is still owed. Cleared at `StationReached`. |
| `mood` | Impatience, from `patiencePermille` (the engine runs patience only for owed passengers). |
| `hint.targetPassengerId` | The `always` hint's target (below). |

Bubbles and «آخر كلام» say what passengers say and what money arrives, as the ux-spec shows. Tokens show
their kind's color while they move.

### Passenger look and mood

| `PassengerView` field | Rule |
| --- | --- |
| `mood` | 3 if leaving with a fight, impatient, or the trip failed; 2 if `patiencePermille ≤ 333`; 1 if `≤ 666`; else 0 |
| `talking` | a bubble of theirs is visible |
| `asleep`, `waking` | alertness `asleep`, `waking` |
| `headphones` | alertness `muted` (headphones on); `attentive` shows them off |
| `presence` | `boarding` for the walk-in after `PassengerBoarded`, `leaving` for the walk-out after `PassengerAlighted` |
| `look` | `SkinLook` for the skin, or the archetype's fallback with the neutral label |

## Speech and bubbles

- **The line:** `pool = content.speechPool(speech_key)`; `text = pool.lines[variant % pool.lines.length].text['ar-EG']`;
  `{amount}` → `NumberFormatter.piasters(amount_piasters)`; `{station}` → the station's name in the
  trip's line, or the station's letter if the line is missing. No pool: no bubble, and the log line is
  skipped.
- **Style by slot:**

  | Style | Slots |
  | --- | --- |
  | warning (light orange) | `stop_near`, `wants_change`, `short_change`, `impatient`, `drop_me_here`, `change_request` |
  | fight (dark orange) | `fight`, `accused`, `dispute`, `missed_stop` |
  | thanks (light blue) | `thanks`, `tip`, `returns_excess`, `caught` |
  | plain (white) | every other slot |

- **The queue** (on the trip clock):
  - at most 2 bubbles visible; each stays at least `bubbleMinMs`, then makes room;
  - waiting lines show in emit order; one that has waited more than `2 × bubbleMinMs` is dropped;
  - a passenger has at most one bubble on screen; their next line waits for it;
  - reduced motion: bubbles appear without the pop.

## «آخر كلام»

The last two lines, newest at the bottom; a new line pushes out the oldest.

| Source | Line |
| --- | --- |
| `PassengerSpeaks` | `«<label>: <text>»` |
| `MoneyArrivedAtDriver` (fare) | `tripLogFareArrived(amount, label)`: «وصلك ٥٠ من الشلة» |
| `BreakCompleted` | `tripLogBreakDone(note)`: «اتفكت الـ٥٠» |
| `MoneyDropped` | `tripLogDropped(amount)` |
| `DroppedLost` | `tripLogLost(amount)` |
| `FareIncreased` | `tripLogFareUp(new)` |

`<label>` is the passenger's `SkinLook.labelKey`, or «الشلة» for a group payer. Two passengers aboard
with the same label get their station letter after it («الأفندي (ب)»). The label never depends on
the archetype (research R10).

## Hints

| Mode | Shows |
| --- | --- |
| `always` | On `StationWarning` with a non-empty `owed`: `tripHintOwed` pointing at the first owed passenger, until `StationReached` or they are no longer owed. |
| `first_time` | The first time this device meets a type, at the type's first visible sign (table below). Saved in `pref.trip_hints_seen`. |
| `off` | Nothing. |

| Archetype | First visible sign | Points at |
| --- | --- | --- |
| `sleeper` | `PassengerBoarded` | the passenger |
| `headphones` | `PassengerBoarded` | the passenger |
| `hajja` | her first `TokenHopStarted` | the passenger |
| `hurry` | `PassengerBoarded` | the passenger |
| `big_note` | his first `FareSent` | the passenger |
| `student` | the first `FareSent` | the passenger |
| `group_payer` | the first `pays_group` line | the payer |
| `chatty` | `PassengerBoarded` | the passenger |
| `false_claimer` | the first `ClaimRaised` of any passenger | nobody (a general line about claims) |
| `honest` | the first `ExcessReturned` | the passenger |
| `regular_customer` | the first `tip` line | the passenger |
| `regular` | none | — |

A passenger aboard when the trip opens (or comes back from its record) never boards on screen, so
for them `PassengerBoarded` is the opening itself. One hint at a time, each for `bubbleMinMs`; the
rest wait.

## Failure summary

- Causes: `state.reputationLost`, sorted by points lost, the top two.
- Count per cause: points lost ÷ that cause's penalty in the trip's params (`rep_fight`,
  `rep_missed_stop`, …), since each event costs the same fixed penalty.
- Text: `tripCause<Cause>(count)` with ICU plurals, joined: «خناقتين وراكب فاتته محطته».
- `revive`: offered under trip-controller.md's Revive rule; `priceBonat` from the catalog;
  `affordable` = `economy.view.bonat ≥ price`.

## Cues: every key event through more than one channel

Constitution XI: sound is one channel, and every key event still reaches the player when sound or
vibration is off.

| Engine event | Sound | Vibration | What the scene shows | Words |
| --- | --- | --- | --- | --- |
| `MoneyArrivedAtDriver` | `coin` | light | the token lands, the slot's count rises | log line |
| `ChangeDelivered` exact | `thanks` | — | the token reaches them, they smile | their line, if any |
| `ChangeDelivered` short | `wrong` | — | the token flashes orange as it lands | the `short_change` bubble |
| `ChangeDelivered` over, not owed | — | — | — | — (a silent mistake: «المستغل يسكت», not a key event under constitution XI 1.4.0; the result lists it) |
| `ExcessReturned` | `coin` | light | a return token travels back | the `returns_excess` bubble |
| `StationWarning` | `call` | — | countdown pulses; owed patches pulse | the `stop_near` bubble |
| `StationReached` | `horn` | — | the station's sign passes; its chip is marked | alighting lines |
| `PassengerAlighted` fight | `fight` | heavy | shake, mood 3, they leave | the `fight` bubble |
| `PassengerAlighted` missed stop | `wrong` | — | they leave | the `missed_stop` bubble |
| `MoneyDropped` | `bump` | heavy | shake, notes on the floor glint | log line |
| `DroppedLost` | — | — | the glint fades | log line |
| `FareIncreased` | `alert` | — | the banner, the strip's prices change | the banner's text |
| `TokenBlocked` | — | — | the token turns orange with «؟» | — |
| `BreakCompleted` | `coin` | light | the slots' counts change | log line |
| `TripFailed` | `fight` | heavy | every face frowns; the failure card | the card's text |
| `LiarCaught` | `thanks` | — | reputation rises | the `caught` bubble |
| `FalseAccusation` | `wrong` | — | reputation drops | the `accused` bubble |

Sound plays only when `pref.trip_sound` is on, vibration only when `pref.trip_haptics` is on, and shake
only without reduced motion.

### Stand-in effects (`assets/audio/sfx/`)

`coin`, `note_pass`, `call`, `horn`, `fight`, `thanks`, `wrong`, `bump`, `alert`: mono WAV,
22.05 kHz, 16-bit, ≤ 0.6 s, made by `tool/sfx/generate.py`.

## Rejections

| Rejection | What the player gets |
| --- | --- |
| `cannot_make_change` | `tripRejectNoChange` in the log's place for 2 s |
| `break_limit` | `tripRejectBreakLimit` likewise |
| `booster_limit` | `tripRejectBoosterLimit` likewise |
| `command_limit` | `tripRejectCommandLimit`, and every control except pause stops responding |
| `tray_empty`, `hand_empty`, `undo_unavailable`, `no_effect`, `not_aboard`, `no_choice`, `wrong_status`, `bad_argument` | a short shake of the control; no text |

## Player text

New keys in `lib/l10n/app_ar.arb` (about 90), by prefix. Numbers arrive preformatted; counts only
select a plural (M03's placeholder rule).

| Prefix | For |
| --- | --- |
| `tripTopBar*`, `tripStrip*` | trip number, countdown semantics, student icon |
| `tripStationLetter1`…`4` | أ ب ج د |
| `tripHand*`, `tripTray*`, `tripBreak*`, `tripUndo` | the dashboard |
| `tripBooster*` | names, counts, the purchase card, «ناقصك …» |
| `tripClaim*`, `tripChangeRequest*`, `tripDispute*` | the choices |
| `tripPause*` | the pause card (M03's three keys are kept) |
| `tripFail*`, `tripCause*` | the failure card and its causes |
| `tripNoFuel*`, `tripRetry*` | the start's refusals and write failures |
| `tripLook*` | speaker labels |
| `tripLog*` | money lines |
| `tripHint*` | بلية's lines |
| `tripBanner*`, `tripStory*` | the fare-increase banner, the story condition |
| `tripReject*` | rejection lines |
| `tripSemantics*` | screen-reader labels |
| `tripDebug*`, `tripPlaytest*` | dev and staging only |
