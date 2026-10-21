# Contract: The Content Source (FR-009 to FR-013)

How every other feature reads game content. The types are the generated ones from
`package:content_models`. Nothing here defines a content type of its own (constitution VII).

## The interface

`lib/core/content/domain/content_source.dart` imports only `package:content_models`. A guard test
forbids `package:flutter`, any plugin and `dart:io` there (constitution I).

```dart
abstract interface class ContentSource {
  /// The pack's version, which ledger and sync operations declare (M05, M06).
  int get version;

  /// Lines in `order`, ascending.
  List<Line> get lines;
  Line? line(LineId id);

  /// A line's trips by trip number: `line_hay.01`, `line_hay.02`, …
  /// Empty for a line with no trips.
  List<TripDefinition> tripsOf(LineId line);
  TripDefinition? trip(String tripId);

  /// Vehicles in `order`, ascending.
  List<Vehicle> get vehicles;
  Vehicle? vehicle(VehicleId id);

  /// The catalog price of one SKU, or null when it has none
  /// (a starter vehicle, say). Amounts are integers (constitution II).
  CatalogPrice? price(SkuKind kind, String skuId);

  SpeechPool? speechPool(String speechKey);

  /// Chapters, rooms and a room's items, each in `order`, ascending.
  List<Chapter> get chapters;
  Chapter? chapter(ChapterId id);
  List<Room> get rooms;
  Room? room(RoomId id);
  List<Item> itemsOf(RoomId room);
  Item? item(String itemId);

  /// Family requests in authored order.
  List<FamilyRequest> get familyRequests;

  /// The 7 days, by `day_index` 1 to 7.
  List<DailyRewardDay> get dailyRewards;

  /// Task templates in authored order.
  List<TaskTemplate> get tasks;
}
```

**Rules for every method.**

- An unknown id returns `null` or an empty list. It never throws. After a fallback to the bundled
  pack, progress may name a trip the active pack doesn't have, and readers skip it (research,
  hand-overs).
- The returned lists are unmodifiable and built once per pack, so a call costs a map lookup.
- No method reads files, the network or the clock.

`PackContentSource(Pack pack)` is the only implementation. It builds the maps and sorted lists in
its constructor, which runs in the decode isolate (research R4) so the UI isolate does no indexing.

## Providers (`lib/core/content/content_providers.dart`)

| Provider | Type | Lifetime | Meaning |
| --- | --- | --- | --- |
| `activeContentProvider` | `AsyncNotifier<ActiveContent>` (`ContentController`) | keep-alive | Chooses the active pack at launch (research R6), and switches at Home (R7) |
| `contentSourceProvider` | `ContentSource` | keep-alive | `activeContentProvider.requireValue.source`. Synchronous after startup. |
| `contentVersionProvider` | `int` | keep-alive | `activeContentProvider.requireValue.version` |
| `contentUpdaterProvider` | `ContentUpdater` | keep-alive | Started once startup completes (contracts/updates.md) |

- **Startup.** `appStartup` (M03, `lib/bootstrap/startup.dart`) adds
  `activeContentProvider.future` to its `Future.wait`, and `retryAppStartup` invalidates it. So the
  boot screen hands over to Home only with a pack loaded, and shows its existing error and retry if
  none loads (FR-008).
- **A switch** replaces `ActiveContent` in one state change. Every reader that watches
  `contentSourceProvider` rebuilds with the whole new pack. No reader can see half of each (FR-025).

## What readers must do

- Watch `contentSourceProvider` and don't keep a `ContentSource` beyond a build, except as below.
- **A trip** (M02) keeps the `TripDefinition` and `contentVersion` it started with, for its whole
  life and in its replay record. A switch can only happen at Home, never during a trip. A launch
  after a kill may switch packs before the trip resumes, so the trip must not look its definition up
  again.
- **Prices** (M05) come only from `price()`. An op declares `contentVersion` as of the moment it is
  recorded.
- Readers never write to the content.

## Test seams

- `activeContentProvider` can be overridden with a fixed `ActiveContent` built from the sample pack
  (`test/helpers/content.dart`), so screen tests don't touch files.
- `ContentRemote`, `ConnectivitySource`, `AppInfo`, the clock and `PackStore`'s directory are
  injectable (contracts/updates.md, contracts/loading.md).
