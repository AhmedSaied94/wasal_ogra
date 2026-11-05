# Contract: The Boards the Owner Draws for M11

`States` 2–3 (ad not ready, daily ad limit), `RewardedAdButton` (`Components` box 10), Home row 6
and `HomeStates` row 7 are drawn. Six boards aren't, and the owner draws them (spec Clarifications,
FR-018a):

- three piggy states: `PiggyArrived`, `PiggyUsed`, `PiggyLater`;
- the out-of-fuel card with the refill ad and its BONAT refill: `NoFuelAd`, `NoFuelAdLimit`
  (analysis C1, constitution IX);
- the «زحمة» booster card with its ad button: `BoosterAdCard`.

The owner's prompt for the canvas (2026-11-03) asks for all six. This brief follows M10's shape
([../../015-m10-apartment-story/contracts/design-briefs.md](../../015-m10-apartment-story/contracts/design-briefs.md)).

## How to deliver

1. Draw each board on the Claude Design canvas «وصّل الأجرة — Design», in Style C «كرتون ناعم»,
   390×844 with the 36 pt status inset, one state per board, over Home (`C-Home`) as it looks with
   the piggy banner.
2. Export with `docs/design/tools` (`export.py`, `boxes.py` + `boxes_post.py`, `build_assets.py`) and
   commit `docs/design/screens/<Board>.html`, `png/<Board>.png`, `boxes/<Board>.json` and the
   manifests. Or hand the export to Claude.
3. Give every tappable an `aria-label` (the strings below). Draw the copy you want: where it differs
   from these drafts, the board wins, and Claude updates `app_ar.arb`.

**Sizes are proposals: the drawn board decides.** Until a board lands, Claude builds its state from
this brief, and only that board's sample, golden and layout test wait (spec FR-018a).

**Sample values:** the piggy pays 30 ج and 2 بون (B07's live settings, `ads_morning_piggy_jenehat`
and `ads_morning_piggy_bonat`). Home's other values come from `C-Home`.

## `PiggyArrived`: the reward arrived

When it shows: on arrival at Home, for a granted piggy reward the player hasn't seen (the app was
closed, or the polling gave up), and right after a successful polling. It is a dialog over Home, one
reward at a time.

- The pig glyph from Home row 6, with coins coming out (a still drawing; the motion is Rive's if the
  owner adds one later).
- Title, draft: «الحصّالة وصلت!».
- Amounts: a JENEHAT chip «+٣٠ ج» and a BONAT chip «+٢ بون», in the wallet pills' colours.
- One button, draft: «تمام» (`AppButton` primary, aria-label «تمام»). Closing it confirms the reward
  as seen.
- No ad mark: nothing more to watch.

## `PiggyUsed`: today's piggy is used

When it shows: the server refused the piggy because today's is already taken (another device, or a
callback that came first). It can be a toast or a small card over Home.

- Draft line: «الحصّالة اتفتحت النهارده، تعالى بكرة».
- If a card, one button «ماشي». If a toast, `States`' toast placement.
- No amounts.

## `PiggyLater`: the reward will arrive

When it shows: the polling's 7 s passed with no answer. The reward will come with the next
bootstrap, as `PiggyArrived`.

- The line from backend §8.4: «هتوصلك المكافأة أول ما توصل».
- A reassuring mark (the pig with a clock, say), not an error.
- A toast or a small card, like `PiggyUsed`. Draw both in the same style.

## `NoFuelAd`: the out-of-fuel card with the free refill

When it shows: a trip start refused for an empty tank (M02's `NoFuelCard`), over `C-Trip`, dimmed,
in `States` row 4's layout (spend confirmation, `AppDialog`).

- Fuel glyph and title «البنزين خلص», with «اللتر الجاي ١٢:٣٠» under it.
- A `RewardedAdButton`: «اتفرج على إعلان وفوّل» over «باقيلك ٣ النهارده».
- **Beside it, as an equal choice**, the BONAT refill: `AppButton` «فوّل بـ٣٠ بون» with a
  `PriceChip`. Wherever a reward is also sold for BONAT, the BONAT option sits next to the ad
  (constitution IX).
- Then the existing «البنزين» (the fuel sheet) and «ارجع الموقف», smaller.

Sample values: refill 30 بون, the player holds 45 بون, three refill ads left today.

## `NoFuelAdLimit`: the same card after today's third refill

As `NoFuelAd`, with the `RewardedAdButton` disabled («خلصت النهارده», 45%, no lip; `States` row 3)
and the BONAT refill unchanged.

## `BoosterAdCard`: «زحمة» bought or watched

When it shows: a tap on «زحمة» with none left (the engine pauses, M02's `BoosterCard`), over
`C-Trip`, dimmed, in the booster card's layout (icon and name, price and balance,
«اشتري واستعمل», «مش دلوقتي»).

- Above «اشتري واستعمل», a `RewardedAdButton`: «زحمة ببلاش» over «+١٠ ثواني للمحطة الجاية».
- Under it, the BONAT purchase as today: «اشتري واستعمل» with «٨ بون» and «معاك ٤٥ بون».
- «مش دلوقتي» last.
- On the dashboard behind, «زحمة» shows its «إعلان» badge as `TripEvents` draws it.

## As drawn (2026-11-03)

All six boards are on the canvas in a new row, «الإعلانات», at the bottom of «النسخة الأولى». They
were exported on branch `design/m11-ad-boards` (commit `2cc4786`, built on master, docs/design only)
and brought onto `018-m11-ads`. The commit has each board's `screens/`, `png/` and `boxes/` files,
its `manifest.json` entry after `States`, and its illustrations. No new icons. The existing boards'
boxes and PNGs were left alone (the canvas's Chromium measures their text a pixel or two
differently).

- **PiggyArrived.** An `AppDialog` over Home with the pig and coins (`PiggyArrived_01.svg`), title
  «الحصّالة وصلت!», chips «+٣٠ ج» and «+٢ بون», and one button «تمام». Like `PurchaseDone`, the
  wallet pills sit above the scrim with a sun ring and the new totals (١٬٢٧٠ and ٨٧).
- **PiggyUsed, PiggyLater.** A **toast, not a dialog**, in `UndoToast`'s style just above the nav,
  where the banner was. It has no button and `role=status`, and the banner is gone from Home.
  - PiggyUsed: «الحصّالة اتفتحت النهارده، تعالى بكرة».
  - PiggyLater's copy **changed**: «المكافأة في الطريق، هتلاقيها أول ما توصل», replacing «هتوصلك
    المكافأة أول ما توصل» (the draft said "arrive" twice; «في الطريق» matches `RoomDonePending`).
    Its icon is the pig with a small sun clock badge.
  - The owner changed it again after the phone check (2026-11-05), because «أول ما توصل» reads as
    "once you're connected": the app says «المكافأة في الطريق، هتوصلك بعد شوية». The board's HTML, boxes
    and PNG keep the old sentence.
- **NoFuelAd, NoFuelAdLimit.** The ad and the BONAT refill are **two equal tiles side by side**, both
  primary with a lip, paired as `States` row 3 pairs its choices. «البنزين» and «ارجع الموقف» sit
  under them as secondary buttons.
  - The ad tile stacks the TV icon, «اتفرج على إعلان وفوّل» and «باقيلك ٣ النهارده».
  - The BONAT tile's copy **changed**: «فوّل الخزان» with a sun `PriceChip` «٣٠ بون», replacing
    «فوّل بـ٣٠ بون», so the price doesn't show twice. «فوّل الخزان» is the `Fuel` sheet's name for
    the item.
  - On `NoFuelAdLimit` the ad tile is 45% with no lip and «خلصت النهارده», with the TV icon without
    its play mark. The BONAT tile is unchanged.
  - The app's tile icons are one flat white, so the BONAT tile's fuel icon loses the window the board
    cuts into it (`refill` has no white-on-primary drawing).
- **BoosterAdCard.** «زحمة ببلاش» / «+١٠ ثواني للمحطة الجاية» sits directly above «اشتري واستعمل»
  with its «٨ بون» chip; both are 66 high and primary. «معاك ٤٥ بون» goes under the buy button,
  then «مش دلوقتي». The dashboard behind shows «زحمة» with its «إعلان» badge.
- **Labels.** A two-line button's `aria-label` joins its lines with «، », as the app already labels
  `RewardedAdButton`. The layout tests find them that way. Home's controls on the toast boards keep
  `C-Home`'s labels.

The code follows the boards where they and this brief differ (T064), and `app_ar.arb` takes the
boards' copy.
