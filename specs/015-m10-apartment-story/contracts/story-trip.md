# Contract: Story Trips: Riders, Title, Condition and Comments

What M10 changes in M02's trip screen for a chapter's story trip, all from the chapter's
`story_trip_info` (content-fields.md). No engine, solver, parity or trip-definition change. Research
R15; spec FR-046–FR-049, Q2; constitution I, XI, XII.

## Facts (`lib/features/trip/domain/trip_facts.dart`)

```dart
final StoryTripInfo? storyInfo;   // the chapter whose story_trip_id == definition.tripId, else null
```

- Built where `TripFacts` is built (the trip controller), from `ContentSource`.
- A trip that is no chapter's story trip has none, and the screen is exactly M02's.

## What the screen shows

| Part | File | With `storyInfo` | Without |
| --- | --- | --- | --- |
| Top bar title | `top_bar/top_bar.dart` (`TripTitle`) | `StatusChip.story` over `storyInfo.title` | M02's «{line} · {n}» |
| Story strip | `overlays/story_strip.dart` | `storyInfo.condition` when present, else M02's `tripStoryNoFights` | M02's rule |
| Strip broken state | the same | only when the trip has `rules.no_fights_required` (M02's `storyCondition`) | — |
| Failure reason | `domain/fail_summary.dart` → `cards/failure_card.dart` | `storyInfo.failReason` in place of `tripFailStoryRule` when the story rule broke | M02's line |
| Riders | `scene/rider_component.dart` (new) | one per rider | none |
| Rider bubbles | `domain/presentation_memory.dart`, `overlays/bubbles_layer.dart` | comments (below) | — |

**The strip's visibility.** `TripView` gains `storyStrip` (`StoryStripView{text?, broken?}`), set when
the trip has a story rule or `storyInfo.condition`. The five places that test
`storyCondition != null` for layout test `storyStrip != null`: the title, the hint layer, the bubbles
layer's reserved height, the fast-forward strip and the strip itself. `storyCondition` keeps meaning
the rule's state.

## Riders in the scene (`RiderComponent`)

- One per `storyInfo.riders[i]` at `SeatLayout` for `rider.seat`: drawn at the seat's `face`, under
  the same row order as passengers, so benches and depth stay right.
- **Art:** `wassal.riv`'s `Person` artboard with the character's look:
  - `CharacterAvatar.looks` maps `usta`…`belya` to looks 18–23;
  - the static SVG fallback when Rive fails (M22's rule).
- **Behaviour:** no tag, no stop colour, no tap target, no money and no patience ring. It never moves
  and never leaves.
- **Rive inputs:** `mood` (calm), and `surprised`, a Boolean (008.5's contract reserves both), on while
  the rider's comment shows and off after it. The art takes it through `PassengerArt.surprise`; the
  static art has one face and ignores it.
- **Where it is drawn:** by the scene's `PassengerArtFactory`, as a passenger is, from a `Look` made of
  the character's `CharacterAvatar.looks` number and its own drawing (`Look.asset`, the characters'
  SVGs share the passengers' view box).
- The seat is empty in the engine (V-C7: no passenger names it), so the chain, the boarders and every
  rule ignore it.
- **Semantics:** each rider's seat says «{name} راكب معاك» (`tripRiderA11y`) once, from
  `overlays/rider_labels.dart` (no taps, nothing drawn). The scene has no summary node of its own to
  add it to.

## Comments (`lib/features/trip/domain/rider_comments.dart`, pure)

```dart
final class RiderComment { final StoryCharacter speaker; final String line; final int ordinal; }

RiderComment? riderComment(
  StoryTripInfo info, SpeechResolver speech, ReputationChanged event,
  {required int seed, required int ordinal});
```

(`SpeechResolver` is M02's `domain/speech.dart`, which already holds the pack's pools, so the function
takes it rather than a map of pools.)

| Engine cause (`RepCause`) | `RiderComments` key |
| --- | --- |
| `shortChange` | `short_change` |
| `falseAccusation` | `false_accusation` |
| `fight` | `fight` |
| `missedStop` | `missed_stop` |
| `impatient` | `impatient` |
| every other cause | none |

- **Speaker:** the first rider, in `riders` order, whose `comments` names a pool for that cause; none,
  no comment.
- **Line:** `SpeechResolver.resolve(speechKey: key, variant: pick)`, where `pick` is the first value
  of `Xorshift32(seed ^ (ordinal + 1)).next()` (non-zero state for any seed) and `ordinal` counts the
  trip's rider comments from 0.
  - A fresh generator per comment, so the engine's PRNG state is never read or advanced
    (constitution I, XII).
  - `Xorshift32` lives in `packages/trip_engine/lib/src/prng.dart` and isn't exported. M10 adds
    `export 'src/prng.dart' show Xorshift32;` to `trip_engine.dart`. That is one line of public
    surface, with no rule, fixture or parity change, so the app never copies the algorithm.
  - If `seed ^ (ordinal + 1)` is 0, the state is 1.
- **Over-change is silent.** Giving back more than was owed raises no `ReputationChanged`, so no
  rider speaks (constitution XI). `changeRequestDeclined`, `liarCaught`, `exactChange` and `revive`
  have no key, so they make no comment.
- **No Arabic in code:** the pools are content (`speech/*.json`), and the line is shown as written.
  Rider pools carry no `{amount}` or `{station}` (V-C8), so `resolve` is called without them.

### Timing (`PresentationMemory`)

- **One character slot.** بلية's bubble (M07) and riders' comments share the queue's one reserved
  slot:
  - `belya` becomes `character`, a `CharacterBubble{speaker, source, line, shownAtMs}`;
  - `belyaAt` becomes `characterAt`;
  - بلية's wish wins when both want the slot at once.
- A rider comment waits for the slot at most `bubbleMinMs` from its event, else it is dropped, so
  comments never pile up.
- Once shown, it stays at least `bubbleMinMs`: `trip_bubble_min_ms_<line>`, already a Remote Config
  key. No new tunable.
- The bubble is a Flutter overlay anchored over the rider's face, as passengers' bubbles are. It
  carries the speaker's name chip (`sceneSpeaker`) and a polite announcement «{name}: {line}». No
  text is drawn in the Flame canvas.
- At most two bubbles at once in total (constitution XI). The character slot is one of M02's
  `maxVisibleBubbles` (2), as بلية's is: while a rider speaks, one passenger bubble at most.

## Replays and results

- The result, the replay record and the sync payload are unchanged: riders aren't part of the trip.
- A replay (`fixtures`, the debug replayer) with the same seed shows the same comments at the same
  moments, because the pick depends only on the seed and the event order.

## Tests

- `rider_comments_test`:
  - each mapped cause → its pool;
  - an unmapped cause → none;
  - an over-change sequence → none;
  - two riders → the first with a pool;
  - the same `(seed, ordinal)` → the same line;
  - the engine's PRNG state unchanged.
- `presentation_memory_test`:
  - a comment takes the slot;
  - بلية wins a tie;
  - a comment that waited past `bubbleMinMs` is dropped;
  - it stays its minimum time.
- `fail_summary_test`: `failReason` replaces the rule line; without it, M02's line.
- **Widget:**
  - `trip_title_test`: the story chip and title;
  - `story_strip_test`: the content condition, the strip without a rule;
  - `rider_component_test`: drawn at its seat, no hit area, the fallback;
  - `bubbles_layer_test`: the rider bubble's anchor and name.
- **Integration:** `integration_test/story_trip_test.dart` plays the sample's `line_hay.03` with a
  scripted short change:
  - المعلم comments once;
  - a scripted over-change makes no comment;
  - the trip's result equals the run without riders (the same `TripResult`).
- **Guards:** `no_ads_in_trip_test` and the "no text in Flame" guard apply as they are.
