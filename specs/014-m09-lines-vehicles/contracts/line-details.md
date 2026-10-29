# Contract: A Line's Details (تفاصيل الخط), and Starting a Trip from Lines

Spec US2, US4 #2, US5; FR-023–FR-029, FR-019, FR-026. Artboard `LineDetails`, and the owner's
boards `LineDetailsStory`, `LineDetailsDone`, `LineDetailsLocked`
([design-briefs.md](./design-briefs.md)). Research R4, R5.

## Files

```text
lib/features/lines/
├── domain/
│   └── trip_cells.dart         # TripCell, tripCells(c, p, line), visibleRange(cells)
└── presentation/
    ├── line_details_sheet.dart
    ├── trip_grid.dart          # TripGrid, TripCell widget
    └── locked_fill.dart        # the §9.1 #6 decoration for cells and tiles
```

`router.dart`'s `_page` builds `LineDetailsSheet(lineId)` for `RouteNames.lineDetail`, inside its
`AppSheetPage`.

## The cells

`tripCells(c, p, line)` returns one `TripCell` per trip of `c.tripsOf(line)`, by trip number. A cell
has a `state` (`CellState`), `isStory`, `stars` and `playable`, whether the rules let the trip start
now (`tripPlayable`, FR-026); a tap starts it when `playable` and the state isn't `locked`:

| State | When | Look (board) |
| --- | --- | --- |
| `done` | stars ≥ 1, `playable` | `ground` (`sun.soft` for a story), number, `Stars` 12 |
| `done`, not `playable` | stars ≥ 1, but the rules refuse it now (a newer pack, a rolled-back purchase) | the locked look with its stars kept and a 12 lock at the top end; inert, no tap semantics |
| `next` | the line's next trip: the first by number that is `tripPlayable` with no star | `primary` + lip, number + «كمّل» |
| `playable` | another `tripPlayable` trip with no star | `primary` + lip, number, no «كمّل» (`LineDetailsStory`) |
| `locked` | not `tripPlayable`, no star | the §9.1 #6 locked look + an `ink.muted` lock 14 |

A story cell keeps its «قصة» chip in every state; on the first row the grid leaves 6 above it, so
the chip isn't cut.

`visibleRange(cells)` (FR-025, as `LineDetailsStory` draws it):

- `rows = max(4, furthestRow + 1)`, capped at the line's rows, where `furthestRow` is the row of the
  last cell drawn done, next or playable;
- so every row for a done line, and 4 for a locked line;
- `hidden = (from, to)` or null.

When the rows run past the sheet, the grid opens scrolled just far enough to show the next trip.

## Layout (`LineDetails`)

| Block | Content | Rule |
| --- | --- | --- |
| Sheet | `AppSheetPage`, own header | — |
| Header | the line's name (`display.m`); star + `lineDetailsSummary` «{stars} من {max} نجمة · {done} مشوار خلص» (plurals); `IconCircleButton` close | FR-023 |
| Grid | `role=list` `lineDetailsTripsA11y` «مشاوير الخط»; 5 per row from the right, ≈65×62, gap 8; scrolls above the button | FR-024, FR-025 |
| Hint | `lineDetailsHint` «والمشاوير من {from} لـ {to} بتظهر لما تقرّب», when hidden | FR-025 |
| Info note | the board's two sentences under the grid, scrolling with it. A done line has the first only, pinned in the button's place (`LineDetailsDone`). A locked line has none (`LineDetailsLocked`). | FR-023 |
| Button | `AppButton.primary(xl)` «العب المشوار {n}», pinned. A done line: none. A locked line: the reason in its place as a locked `StatusRow` (44 high, a 24 lock, 15/700), nothing to tap. | FR-023, FR-027, FR-028 |

## Starting a trip

| Element | Result |
| --- | --- |
| A done, story-done, next or playable cell; the button; the map's «كمّل» | `startNextTrip(context, ref, tripId:, from: StartFrom.lines)` |
| A locked or story-locked cell | nothing; no tap semantics |
| ✕, swipe, scrim, back | pop to `/lines` |

`startNextTrip` (M08's, changed here):

1. Not `tripPlayable` → return false, go nowhere. **New.**
2. A start under way → false.
3. Empty tank (and no fuel lesson due) → the fuel sheet.
4. The checkpoint (M11).
5. A tutorial trip in the first session, or a trip the card setting skips → `/trip/<id>`.
6. Otherwise the card. **Changed:** its location follows `from`:
   - `home` and `result` → `/home/pre-trip/<id>`;
   - `lines` → `/lines/<line wire>/pre-trip/<id>`, with the line from the trip's own `lineId`.

**The new route.** `RouteNames.linePreTrip`, `/lines/:lineId/pre-trip/:tripId`, a sheet and child of
`lineDetail`. Both parameters are validated. It builds
`PreTripCard(tripId:, leaveTo: '/lines/<lineId>')`.

**`PreTripCard`** gains `leaveTo` (default `/home`), used by `_leave()` when the trip is unknown or
not `tripPlayable`. Its close still pops, which under the new route lands on the line's details.

**The lines tab** always opens at `/lines`. `ShellScaffold`'s tab tap passes `initialLocation: true`
for `Section.lines`, so a card left for a trip is never rebuilt on the next visit.

## Accessibility

- **The cell's label** is `lineDetailsCellA11y` «المشوار {n}، {state}», with `selected` on the next
  cell. States: «خلص بـ{stars}» (plural), «الجاي», «تقدر تلعبه», «مقفول»; story cells add «، مشوار
  قصة».
- **Focus** starts on the title.
- **Sizes:** cells ≥ 44, buttons ≥ 52 high.

## Tests

- **Unit:** `trip_cells_test.dart`. Every state; the next trip with a story cell before it; the two
  playable cells after the shabka; the range for 3, 20, 30 and 40 trips with next at 1, 12, 19 and
  none; `LineDetailsStory`'s six rows; locked and done lines.
- **Widget** (`line_details_sheet_test.dart`):
  - each cell's tap and its location (card or trip, by the card setting);
  - a locked cell inert;
  - the button and its absence;
  - the locked line;
  - closing four ways;
  - a second tap while a start is under way;
  - the fuel sheet on an empty tank.
- **Start and card** (`start_next_trip_test.dart`, `pre_trip_card_test.dart`):
  - `from: lines` opens the line's card route, and its close lands on the line's details;
  - an unopenable card leaves to `/lines/<line>`;
  - Home's and the result's paths are unchanged.
- **Shell** (`test/core/routing/shell_test.dart`): card → «اطلع» → result → Home → «الخطوط» shows
  `/lines`.
- **Design:** `test/design/samples/line_details.dart` for `LineDetails`, `LineDetailsStory`,
  `LineDetailsDone` and `LineDetailsLocked`, with their layout tests and goldens.
- **Sizes:** `test/a11y/line_details_minimum_sizes_test.dart`.
