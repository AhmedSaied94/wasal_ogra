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

`tripCells(c, p, line)` returns one `TripCell` per trip of `c.tripsOf(line)`, by trip number:

| State | When | Look (board) |
| --- | --- | --- |
| `done(stars)` | regular, stars ≥ 1 | `ground`, number, `Stars` 12 |
| `storyDone(stars)` | story, stars ≥ 1 | `sun.soft`, «قصة» chip above |
| `next` | the line's next trip: the first by number that is `tripPlayable` with no star | `primary` + lip, number + «كمّل» |
| `playable` | another `tripPlayable` trip with no star | `primary` + lip, number, no «كمّل» (owner's `LineDetailsStory`) |
| `locked` | not `tripPlayable`, no star | the §9.1 #6 locked look + lock 14 |
| `storyLocked` | story, not `tripPlayable`, no star | the locked look + «قصة» chip |

A story cell that is `next` or `playable` keeps its «قصة» chip.

`visibleRange(cells)`:

- `rows = max(4, nextRow + 2)`, capped at the line's rows;
- every row for a done line;
- 4 for a locked line;
- `hidden = (from, to)` or null.

## Layout (`LineDetails`)

| Block | Content | Rule |
| --- | --- | --- |
| Sheet | `AppSheetPage`, own header | — |
| Header | the line's name (`display.m`); star + `lineDetailsSummary` «{stars} من {max} نجمة · {done} مشوار خلص» (plurals); `IconCircleButton` close | FR-023 |
| Grid | `role=list` `lineDetailsTripsA11y` «مشاوير الخط»; 5 per row from the right, ≈65×62, gap 8; scrolls above the button | FR-024, FR-025 |
| Hint | `lineDetailsHint` «والمشاوير من {from} لـ {to} بتظهر لما تقرّب», when hidden | FR-025 |
| Info note | the board's two sentences. A done line keeps the first only (owner's `LineDetailsDone`). | FR-023 |
| Button | `AppButton.primary(xl)` «العب المشوار {n}», pinned. A done line: none. A locked line: the reason in its place, nothing to tap. | FR-023, FR-027, FR-028 |

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
  none; locked and done lines.
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
- **Design:**
  - `test/design/samples/line_details.dart`, its layout test and goldens;
  - `LineDetailsStory`, `LineDetailsDone` and `LineDetailsLocked` when exported.
- **Sizes:** `test/a11y/line_details_minimum_sizes_test.dart`.
