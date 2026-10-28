# Contract: What M08 uses from M07, and the seams for M09–M15

M07 is merged, so M08 calls its first session directly (research R8). Every place a later feature
plugs into M08 is an interface with a provider whose default does nothing. A feature fills it by
overriding the provider in its own code, which is one line in `providers.dart` or the app's
`ProviderScope`, never by editing M08's screens. Research R8, R9, R10.

## M07's first session (merged)

`firstSessionProvider` (`lib/features/onboarding/onboarding_providers.dart`) gives a `FirstSession`
(`domain/first_session.dart`). Home, the card and the result watch it, so they rebuild as the
session moves on.

| M08 needs | Reads | FR |
| --- | --- | --- |
| Home's next trip in the first session | `nextTutorialTrip`: **new**, the first unfinished tutorial trip while `inFirstSession`, else null | FR-011 |
| No card for a tutorial trip | `inFirstSession && facts.tutorialTrips.contains(id)` | FR-011 |
| «يلا نطلع!» kept on an empty tank | `fuelLessonDue(id)`: **made public**, was `_fuelLessonDue` | FR-011, FR-012 |
| The result's main action | the `FirstSessionContinue` widget (key `first-session-continue`), in «مشوار تاني»'s place whenever it shows | FR-011, FR-044 |
| Boosters hidden on the card | `boostersLocked` | FR-032 |
| The driver's name | `driverNameProvider` (`String`, «الأسطى» by default) | FR-002 |

M08 adds the two **new** or **made public** members to M07's domain, with tests in
`test/features/onboarding/domain/first_session_test.dart`. `nextAfterResult` is rewritten on top of
`nextTutorialTrip`, with the same results.

Every start goes through `/trip/<id>`, so M07's redirects for a due scene and the fuel lesson apply.

## `ArrivalItem` (M07, M10, M11, M14)

`lib/features/home/application/arrival_queue.dart`

```dart
abstract interface class ArrivalItem {
  /// Lower opens first: 10 story scene, 20 name sheet, 30 notification ask, 40 morning piggy.
  int get rank;
  bool isDue(Ref ref);
  /// Opens the item; completes when it is closed or has left Home.
  Future<void> open(BuildContext context);
}

@Riverpod(keepAlive: true)
List<ArrivalItem> arrivalItems(Ref ref) => const [DueSceneArrival(), NameSheetArrival()];
```

| Rank | Item | Owner | Replaces |
| --- | --- | --- | --- |
| 10 | `DueSceneArrival`: due when `onArrivalAtHome()` returns a scene; `push('/onboarding/scene/<id>?then=/home')`, awaiting the return. `ScenePage` runs M07's `afterScene` step (the first notification ask) before it returns, so the ask is part of this item | M07's code, written in this feature; later M10's scenes | the `/home` row of the router's redirect |
| 20 | `NameSheetArrival`: due when `askName` and `nameAskedProvider` isn't done; marks it done, then awaits `showNameSheet(root, refused: facts.nameRefused)` | M07's code, written in this feature | `NameReaskHost` and its wrapper in the shell |
| 30 | A later notification ask (not the first, which is rank 10's `afterScene`) | M14 | — |
| 40 | Morning piggy offer | M11 | — |

Ranks 10 and 20 live in `lib/features/onboarding/presentation/arrival_items.dart`, and
`arrivalItemsProvider` returns them. Later features add theirs to the same list. The removal of the
`/home` redirect and `NameReaskHost` departs from M07's hand-over, which kept `NameReaskHost`
(Clarifications 2026-10-28). The PR says so.

**Rules** (research R9):

- at most one item per arrival;
- not while an item is open;
- not on the arrival that returns from an item;
- only if the location is still `/home` when the frame ends;
- after the pack switch.

## `BetweenTripsCheckpoint` (M11)

```dart
abstract interface class BetweenTripsCheckpoint {
  /// Called before the pre-trip card, or a direct trip start, from Home and «مشوار تاني».
  /// Never after «اطلع», never while a trip runs (constitution IX).
  Future<void> pass();
}
```

Default: it returns at once. M11 implements glossary §3.4: every 3 trips, never in the first 10,
never right after a rewarded ad, never for `remove_ads` owners or subscribers, never before
`tutorialDone` (M07).

## Slots that draw something (M10, M11, M13)

Each is a provider returning a `WidgetBuilder?`, or a value. When it is null, Home or the result
takes no space for it.

| Provider | Type | Owner | Where |
| --- | --- | --- | --- |
| `homeDailyRowProvider` | `WidgetBuilder?` | M13 (event circle: public launch) | Home, the scene card's top end |
| `morningPiggySlotProvider` | `WidgetBuilder?` | M11 + B07 | Home, under the savings card |
| `resultTaskSlotProvider` | `({WidgetBuilder banner, int bonat})?` | M13 | Result: the banner; the pay's BONAT chip |
| `resultDoubleSlotProvider` | `Widget Function(BuildContext, ResultArgs)?` | M11 | Result: the ×2 offer and decline link |
| `storyAfterResultProvider` | `StoryAfterResult` (default no-op) | M10 | Result, before «مشوار تاني» goes on |
| `storySceneWaitingProvider` | `bool` (default false) | M10 | Home's savings card |

The design samples override all of them with fakes that draw the artboards' sample states (FR-021).

## Destinations behind M08's links (M09, M10, M12, M14)

The links use the existing route names, so the owner replaces only the screen:

- the line card → `lines`;
- the savings card → `apartment`;
- the profile → `settings`;
- the BONAT pill → `shop`;
- the fuel pill, «البنزين خلص» and «مشوار تاني» on an empty tank → `fuel`.

M09's line details open `preTrip` through `startNextTrip`.

## `ShareGateway` (M15 adds analytics at the call site)

Defined in `lib/core/platform/share_gateway.dart`, with `shareGatewayProvider`. The production
implementation is `share_plus`; tests use a fake. M15 logs `share {kind: result_image}` beside the
call.

## Repo guards touched

- `domain_imports_test.dart`: `lib/core/progress/domain` (content models only), and
  `lib/features/home/domain`, `lib/features/pre_trip/domain`, `lib/features/result/domain` (content
  models, `trip_engine`, the content, economy and progress domains, the trip domain's
  `looks.dart`).
- `no_ads_in_trip_test.dart`: unchanged; the checkpoint lives under `features/home/`.
- `no_arabic_literals_test.dart`, `no_raw_style_values_test.dart`, `integer_money_test.dart`: apply
  to the new folders as they are.
