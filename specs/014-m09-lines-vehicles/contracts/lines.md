# Contract: Lines (الخطوط)

Spec US1, US4, US6; FR-014–FR-022, FR-041. Artboard `Lines` (HANDOFF §11 "الخطوط"), and the
owner's boards `LinesFirst`, `LinesOwned` ([design-briefs.md](./design-briefs.md)). Research R3, R8,
R11.

## Files

```text
lib/features/lines/
├── domain/
│   ├── line_standing.dart      # LineStanding, lineStandings(c, p)
│   ├── vehicle_tiles.dart      # VehicleTile, vehicleTiles(c, p)
│   ├── focus_line.dart         # focusLine(c, p, next)
│   └── lines_news.dart         # linesNews(c, p, jenehat), the news keys
├── application/
│   ├── lines_model.dart        # linesModelProvider
│   ├── lines_seen.dart         # LinesSeenNotifier (pref.lines_seen)
│   └── lines_dot_watcher.dart  # LinesDotWatcher (created in bootstrap/app.dart)
└── presentation/
    ├── lines_screen.dart
    ├── vehicle_strip.dart      # VehicleTile widgets
    ├── line_map.dart           # the scroll view, RoadPainter, the focus scroll
    ├── line_card.dart          # LineCard (current, done, locked) + «كمّل»
    └── fare_chip.dart
```

`router.dart`'s `_page` builds `LinesScreen()` for `RouteNames.lines` in place of the placeholder.

## The model

`LinesModel` (watching `contentSourceProvider`, `playerProgressProvider`, `economyViewProvider`,
`firstSessionProvider`, `lastFinishedTripProvider`, and reachability for `online`):

- `jenehat`, `bonat`, `online`;
- `tiles`: `List<VehicleTile>`, in pack order;
- `cards`: `List<LineStanding>`, in pack order;
- `focus`: `LineId?`.

It is rebuilt on every view, so a sync, a rollback or a purchase redraws the screen (FR-022).

## Layout (`Lines`, top to bottom)

| Block | Content | Rule |
| --- | --- | --- |
| Header | «الخطوط» (`display.l`); `CurrencyPill.coin` (no tap, label `homeA11yCoins`); `CurrencyPill.bonat` → `/shop`. Offline: no tap, label `homeA11yBonatOffline`, as M08's Home. | FR-014, FR-015 |
| Vehicle strip | `role=list` «العربيات». One `VehicleTile` per vehicle, from the right, gap 8. Up to four tiles share the width between the gutters (`LinesFirst`: two of 175; `Lines`: four of 83.5); more scroll at four columns' width. Tile states: done (a 20 tick badge), current («{short} · عربيتك», `sun`), for sale (price, locked look, a 16 `ink.muted` lock), not for sale (locked look, no price). Every tile → `/lines/vehicle/<id>`. | FR-016, FR-017 |
| Line map | A scroll view, 12 above the bar; cards bottom-up (first line at the bottom, standing on the map's bottom), gap 12; `RoadPainter` (6 wide, 10 on / 8 off, `icon.off`, from 20 below the top to 20 above the bottom) behind them at the start edge, as tall as the content and never shorter than the map. At the road's far end, at the top of the content, an empty node 8 below the top with «خطوط جديدة جاية» (`linesRoadEnd`, 13/500 `ink.muted`) at the cards' start (`LinesFirst`). Nodes: current 32 `sun` with the bus (`MicrobusGlyph`, 20×15, body and wheels), done 24 tick, locked 24 ring. | FR-018, FR-020 |
| Line card, current | `AppCard`, a 3 pt `primary` ring, padded 14 with 3 between rows (112 with two lines of what's new). Name + `FareChip`; what's new; star + «{earned}/{max} · المشوار {n} من {total}»; «كمّل» (own `Pressable`, 63×44, `primary`) | FR-018, FR-019 |
| Line card, done | name + `StatusChip.done` «خلص»; «{earned}/{max} · عيد عشان النجوم» (stars alone when `allThree`); fare | FR-018 |
| Line card, locked | `AppCard(locked: true)`: lock, name, «محتاج {vehicle}» or «بعد {line}» + « · {what's new}», fare | FR-018, FR-046 |
| Bottom nav | `BottomNav`, «الخطوط» active; the lines dot from `LinesDotWatcher` | FR-053, FR-041 |

Long names and reasons wrap and the card grows (FR-047).

## Actions

| Element | Result |
| --- | --- |
| BONAT pill | `/shop` (online only) |
| Vehicle tile | `/lines/vehicle/<id>` |
| Current or done card (outside «كمّل») | `/lines/<line>` |
| «كمّل» | `startNextTrip(context, ref, tripId: next, from: StartFrom.lines)` ([line-details.md](./line-details.md) "Starting a trip") |
| Locked card, `vehicle` rule | `/lines/vehicle/<that vehicle>` |
| Locked card, `line_complete` rule | `/lines/<line>` (its locked details) |

On the first frame the focus card is scrolled into view, centred (`Scrollable.ensureVisible`,
alignment 0.5, no animation). It scrolls back into view whenever the focus moves (a purchase, a
finished line) and whenever Lines is entered from outside its branch (the tab, Home's line card,
back from a trip). Closing a line's details or a vehicle's sheet leaves the map where the player left
it (T111).

## The «new» dot

- `linesNews(c, p, jenehat)` gives the news keys: `line:<id>` (unlocked, not `start`),
  `story:<tripId>` (`tripPlayable`, no star), `vehicle:<id>` (`ForSale` and affordable).
- `LinesSeenNotifier` keeps the seen set in `pref.lines_seen` (sorted, comma-joined). With no stored
  value, the first read takes the current news as seen.
- `LinesDotWatcher(ref)` is created in `bootstrap/app.dart` after `ContentLifecycle` and disposed with
  it. On every change of news or seen, `newDotProvider(Section.lines)` is set to
  `(news − seen).isNotEmpty`.
- `LinesScreen` calls `markSeen(news)` after its first frame, and on every news change while it is
  current.

## Accessibility

- **Reading order:** header, tiles right to left, cards top to bottom (each card, then its «كمّل»),
  nav.
- **Tile labels** as the board («توكتوك المعلم، خلصته», «الميكروباص القديم، عربيتك دلوقتي»,
  «ميكروباص جديد، بـ٥٬٠٠٠ جنيه»), using the vehicle's `name`.
- **Card label** `linesCardA11y` «{line}، {standing}، {detail}».
- **«كمّل»** `linesContinueA11y` «كمّل المشوار {n}».

## Tests

- **Unit:**
  - `test/features/lines/domain/{line_standing,vehicle_tiles,focus_line,lines_news}_test.dart`;
  - `lines_seen_test.dart`: the pref round trip, the first read.
- **Widget** (`lines_screen_test.dart`):
  - every card and tile state;
  - each action's location;
  - «كمّل» against the card;
  - the focus scroll;
  - offline;
  - a sync redraw;
  - a scrolling map (5 lines at 1.3×).
- **Dot** (`lines_dot_test.dart`):
  - shows after a trip that unlocks something;
  - clears on open;
  - stays cleared after a restart;
  - no dot for a purchase made on Lines.
- **Shell:** the lines tab opens at `/lines` after a card was left for a trip
  ([line-details.md](./line-details.md)).
- **Design:**
  - `test/design/samples/lines.dart`, `lines_layout_test.dart`, `test/goldens/design/lines_goldens_test.dart`;
  - `LinesFirst` and `LinesOwned` when exported.
- **Sizes:** `test/a11y/lines_minimum_sizes_test.dart`.
