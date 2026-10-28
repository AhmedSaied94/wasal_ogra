# Contract: The Progression Rules on the Phone

The Dart mirror of the server's unlock and completion rules (B03 research R6,
`backend/apps/progress/services/unlocks.py`). Research R2. M08 uses it for the next trip and the
chapter; M09 and M10 use it before they call `buy`.

## File and imports

`apps/mobile/lib/core/progress/domain/unlocks.dart` and `player_progress.dart`. They are pure Dart
and may import only `package:content_models/`, `dart:core`, `dart:collection` and their own folder.
`test/repo/domain_imports_test.dart` gains `'lib/core/progress/domain'`.

## Inputs

```dart
final class PlayerProgress {
  const PlayerProgress({required this.bestStars, required this.owned});
  final Map<String, int> bestStars;        // by trip id; missing = 0
  final Set<(SkuKind, String)> owned;      // (vehicle|item|chapter, sku id)

  factory PlayerProgress.of(EconomyView view, ContentSource content); // application layer only
}
```

`ContentSource` is read for lines, trips (`tripsOf(line)` by trip number), vehicles (`starter`),
chapters (`order`, `goal`, `story_trip_id`), rooms and items.

## Functions

Each has the same name, meaning and edge cases as `unlocks.py`.

| Dart | Python | Rule |
| --- | --- | --- |
| `vehicleOwned(c, p, vehicleId)` | `vehicle_owned` | `starter`, or owned |
| `lineComplete(c, p, lineId)` | `line_complete` | every `regular` trip of the line at ≥ 1 star; no regular trip → false |
| `lineUnlocked(c, p, lineId)` | `line_unlocked` | `start`; `vehicle` owned; `line_complete` of the named line |
| `tripUnlocked(c, p, tripId)` | `trip_unlocked` | story: its chapter unlocked (when a chapter names it). Otherwise: line unlocked, vehicle owned, the previous **regular** trip of the line at ≥ 1 star (none for the first) |
| `chapterUnlocked(c, p, chapterId)` | `chapter_unlocked` | first by `order`, or the previous one complete |
| `chapterComplete(c, p, chapterId)` | `chapter_complete` | every goal up to and including it is met |
| `roomComplete(c, p, roomId)` | `room_complete` | every item owned; no item → false |
| `itemPurchasable(c, p, itemId)` | `item_purchasable` | its room's chapter unlocked |
| `currentChapter(c, p)` | `current_chapter` | the highest unlocked chapter not complete; else the last complete; else the first; null with no chapters |
| `apartmentOpens(c)` | — (phone only) | the first chapter by `order` whose goal is `complete_room`; null if none (R4; M10 may change it) |

- **Goal met:**
  - `complete_line`: `lineComplete`;
  - `own_vehicle`: `vehicleOwned`;
  - `purchase`: `(chapter, id)` owned;
  - `complete_room`: `roomComplete`.
- **Order of chapters:** `(order, chapter_id)`. Order of trips in a line: `tripsOf(line)`, which is
  `trip_id` order, the same as the server's rules document.

## Tests

- `test/core/progress/unlocks_test.dart` ports every case of
  `backend/apps/progress/tests/test_unlocks.py`, named `'<python test name>'`. When the Python file
  changes, the Dart port changes in the same PR (a comment at the top of both files says so).
- `test/core/progress/sample_sweep_test.dart`: over the sample pack and the synthetic packs, every
  state reachable by finishing startable trips (depth 6) agrees with a table of expected unlocks.
