# Contract: The Result Screen and the Share Image (النتيجة، صورة المشاركة)

Spec US3, US5; FR-035–FR-048. Artboards `Result`, `ShareCard`. Research R14–R16.

## The hand-over from the trip

Changes to M02's code, kept small:

- `application/trip_phase.dart`: `ExitToResult(tripId, args)`, where `args` is a `ResultArgs`
  (data-model.md).
- `application/trip_controller.dart`, on a finished trip, before `recordResult`:
  - read `view.progress[tripId]?.bestStars ?? 0` and `view.jenehat`;
  - after the result is recorded, build `ResultArgs(result, startTxn, engine.replayRecord,
    bestStarsBefore, jenehatBefore)`;
  - a rebuild that finds a recorded result builds it the same way, with `bestStarsBefore` from the
    progress before that result. When the economy already holds the result (the rebuild case),
    both are read as they stand, and `firstThreeStars` may then be false: the celebration is
    skipped on a resume, by design.
- `presentation/trip_screen.dart`: `router.pushReplacement('/trip/$tripId/result', extra: args)`.

`router.dart`'s result builder:

```dart
RouteNames.result => ResultScreen(
  tripId: state.pathParameters['tripId']!,
  args: switch (state.extra) {
    final ResultArgs a => a,
    _ => null, // a bare TripResult (M07's path until it updates), or nothing
  },
),
```

M02's `ResultSummary` and the placeholder are deleted.

## Files

```text
lib/features/result/
├── domain/
│   ├── result_args.dart
│   ├── summary.dart          # resultSummary(result, definition, lastResult, bestStarsBefore)
│   └── quote.dart            # pickQuote(ReplayRecord) → Quote?
├── application/
│   ├── result_model.dart     # resultModelProvider(tripId, args)
│   ├── quote_provider.dart   # FutureProvider: Isolate.run(() => pickQuote(record))
│   └── result_slots.dart     # ResultDoubleSlot, ResultTaskSlot, StoryAfterResult
└── presentation/
    ├── result_screen.dart
    ├── result_stars.dart     # one by one; the middle one larger
    ├── quote_card.dart
    ├── breakdown_card.dart
    ├── mistakes_card.dart    # a disclosure
    ├── pay_block.dart        # count-up
    ├── apartment_card.dart   # the bar from before to after
    ├── share_card.dart       # the 360×360 ShareCard widget
    └── share_action.dart     # render → ShareGateway
lib/core/platform/share_gateway.dart   # ShareGateway + SharePlusGateway
```

## The screen (`Result`, scrolling, top to bottom)

| Block | Content | Notes |
| --- | --- | --- |
| Header | `ScreenHeader`: back «ارجع الموقف»; «المشوار {n} · {line}» | back and system back → `/home` |
| Task banner | `ResultTaskSlot` | hidden until M13; announced once |
| Title | «وصلنا {last stop}!» | |
| «رقم قياسي جديد» | under the title, when `firstThreeStars` | the `Confetti` artboard + the horn, once (R19) |
| Stars | 58 / **72** / 58, right to left, with ✓/✕ + `resultStar1..3`; a group label `resultA11yStars(count)` | `wassal.riv`'s `Stars` artboard with `stars` = the count: the earned ones pop right to left; each label fades in with its star, 270 ms apart (`DesignExtras.starLabelStagger`). Static `Stars` component under reduced motion, without the file, and in goldens (R19) |
| Quote | `PassengerAvatar(look, 50)` + «{line}» (2 lines, ellipsis) + speaker | fades in when the quote arrives; absent when there is none |
| Breakdown | 4 `ListRow`s: fares, tips (+), over-paid change (−, `danger.ink`), fights | |
| Mistakes | a summary row (`MistakesSummary`) + a chevron, opening to the lines | hidden when there is nothing |
| Pay | «قبضت» + coin + `payJenehat` (counts up from 0) + the BONAT chip from `ResultTaskSlot` | doubled when `lastResult.doubled` for `startTxn` |
| ×2 | `ResultDoubleSlot` | hidden until M11; hidden after a double |
| Apartment | `SavingsTarget` after the pay; bar from `jenehatBefore` to now, with the gain marked; «فاضلك {n} ج», or «تقدر تشتري {item}!» when it became affordable | → `/apartment` |
| Bottom | `AppButton.secondary` «مشوار تاني» + «−١ لتر» (hidden in a window) + the share button «شارك النتيجة» | below |

### Without `ResultArgs`

- `lastResult` is `finished`: show the header from the route's trip id, the title, and the pay from
  `lastResult.earningsJenehat` (doubled if so), plus the apartment card from the current balance
  (no gain marked). Hide the stars, quote, breakdown, mistakes and the share button. The share image
  needs the stars.
- Otherwise: `context.go('/home')` after the frame.

## «مشوار تاني»

- M07's `FirstSessionContinue(tripId: tripId)` takes «مشوار تاني»'s place whenever it shows: while
  `inFirstSession`, and once on the result of the trip that ended the tutorial. It keeps its own
  label «كمّل», its key `first-session-continue` (M07's integration test taps it) and its target,
  `nextAfterResult(tripId)` (research R8).
- Otherwise: `startNextTrip(context, ref, tripId: nextTrip, from: result)` (home.md). The next trip
  is computed after this result: the card for it, the trip itself under new-only, or the fuel sheet
  on an empty tank.
- After a story trip, `StoryAfterResult.after(tripId)` runs first (no-op until M10).

## Sharing

`share_action.dart`:

1. Ignore the tap while a share is in progress.
2. Pre-cache the SVGs the card draws (the avatar's look, `star`, `star_outline`, `coin`).
3. Insert an `OverlayEntry` with `RepaintBoundary(child: ShareCard(spec))` at 360×360, translated
   off screen.
4. `await WidgetsBinding.instance.endOfFrame`.
5. `toImage(pixelRatio: 3)` → `toByteData(format: png)` → remove the entry.
6. If the result screen has left meanwhile, stop. Else `await gateway.shareImage(png, fileName:
   'wassal_result_$tripId.png', text: l10n.shareCaption(...), origin: <the button's global rect>)`,
   with the gateway and everything else read before the first await.

An error (rendering or the plugin) shows `AppToast` with M02's neutral retry text and is reported.
Nothing else changes.

`ShareCard` (360×360):

- the `sun` background with its two `sun.glow` circles;
- the trip chip;
- the title (34, the `sun.lip` shadow);
- the stars 48 / **62** / 48 with an `ink` outline;
- the quote card or none;
- the wordmark «وصّل الأجرة» and «قبضت {amount}».

Digits follow the setting.

```dart
abstract interface class ShareGateway {
  Future<void> shareImage(
    Uint8List png, {
    required String fileName,
    String? text,
    Rect? origin,
  });
}
```

`SharePlusGateway` uses `SharePlus.instance.share(ShareParams(files: [XFile.fromData(png, mimeType:
'image/png', name: fileName)], fileNameOverrides: [fileName], text: text, sharePositionOrigin:
origin))`. An iPad refuses a share without `sharePositionOrigin` (T087's review).

## Tests

- **Unit:**
  - `summary_test.dart`: star rows, the breakdown, mistake lines per kind, `feminine`, the size
    select, the three summary families with plurals, `firstThreeStars`, doubled pay;
  - `quote_test.dart`: the rule's order, determinism after a kill and rebuild (M02's
    `kill_rebuild_test` helpers), the replay ending on the record's `TripResult`, the budget on the
    stress fixture.
- **Widget** (`result_screen_test.dart`):
  - for every `fixtures/parity/*.json` with `outcome == finished`: every figure equals the recorded
    result (SC-004);
  - without args;
  - nothing kept;
  - «مشوار تاني» with fuel and empty; «كمّل» in the first session and after trip 5 (M07's tutorial
    content helper);
  - back;
  - reduced motion.
- **Share** (`share_action_test.dart`): a fake gateway receives a 1080×1080 PNG named after the trip;
  no quote; Western digits; doubled pay; offline.
- **Trip:** `trip_controller_test.dart` gains the `ResultArgs` fields on finish and on a rebuild.
- **Design:** `test/design/samples/result.dart`, `share_card.dart`; `result_layout_test.dart`;
  goldens for both.
