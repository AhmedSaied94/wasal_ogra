# Contract: Route Table and Navigation Rules

Covers mobile §9 and ux-spec «خريطة الشاشات والتنقل» / «قواعد التنقل». Spec FR-014 – FR-024. Later
features keep each route's `name`, `path`, presentation and links. They only replace the placeholder
builder.

## Presentation types

| Type | Navigator | Bottom bar | Page | Back |
| --- | --- | --- | --- | --- |
| `tab` | shell branch (one per tab, state kept) | shown | no transition between tabs | phone back: non-home tab → الموقف; الموقف → press twice to leave |
| `page` | root | hidden | `StickerPage` (fade-through, `motion.screen`; fade only with reduce-motion) | top-right back control + phone back → pop (trip: phone back → `tripPause`; no top-right control) |
| `sheet` | root | hidden (covered) | modal bottom-sheet route, drag-to-dismiss, close button, tap-outside dismisses | phone back closes the sheet only |
| `overlay` | root, no URL | hidden | dialog-style route over the current page | phone back closes the overlay |

## MVP destinations

Sample parameters used by placeholder links: `tripId=line_hay.01`, `lineId=line_hay`,
`vehicleId=micro_old`, `itemId=salon.nish`, `chapterId=ch1_first_job`.

| Name | Path | Type | Section | Links (FR-017a) |
| --- | --- | --- | --- | --- |
| `boot` | `/boot` | page (initial, no back) | — | → `home` automatically when startup is done |
| `onboardingIntro` | `/onboarding/intro` | page | — | `onboardingName` (M07 wires first launch) |
| `onboardingName` | `/onboarding/name` | page | — | `home` |
| `home` | `/home` | tab | home | `preTrip`, `settings`, `dailyReward`, `dailyTasks`, `dailyChallenge` |
| `preTrip` | `/home/pre-trip/:tripId` | sheet | home | `trip` |
| `trip` | `/trip/:tripId` | page (back → `tripPause`) | — | `result` |
| `tripPause` | — | overlay | — | resume (close), `home` |
| `result` | `/trip/:tripId/result` | page | — | `home`, `preTrip` (another trip) |
| `lines` | `/lines` | tab | lines | `lineDetail` |
| `lineDetail` | `/lines/:lineId` | sheet | lines | `vehiclePurchase` |
| `vehiclePurchase` | `/lines/vehicle/:vehicleId` | sheet | lines | — |
| `apartment` | `/apartment` | tab | apartment | `apartmentItem`, `apartmentRequests`, `apartmentChapters` |
| `apartmentItem` | `/apartment/item/:itemId` | sheet | apartment | — |
| `apartmentRequests` | `/apartment/requests` | sheet | apartment | — |
| `apartmentChapters` | `/apartment/chapters` | page | — | `story` |
| `story` | `/story/:chapterId` | page | — | — |
| `shop` | `/shop` | tab | shop | `fuel` |
| `fuel` | `/shop/fuel` | sheet | shop | — |
| `dailyReward` | `/daily/reward` | page | — | — |
| `dailyTasks` | `/daily/tasks` | page | — | — |
| `dailyChallenge` | `/daily/challenge` | page | — | — |
| `settings` | `/settings` | page (real digit control) | — | `account` |
| `account` | `/settings/account` | page | — | — |

The presentation of the daily screens is provisional. M13 may change it, but not their paths or names.
Garage, leagues, events and referral are **not** declared (FR-017).

## Parameter validation (FR-022)

| Param | Rule (glossary §3.6) |
| --- | --- |
| `tripId` | `^(line_[a-z]+)\.(\d{2})$`, and group 1 is a known `LineId` |
| `lineId` | one of `line_hay`, `line_gamaa`, `line_souq`, `line_masyaf`, `line_safar` |
| `vehicleId` | one of `tuktuk`, `micro_old`, `micro_new`, `micro_safar` |
| `itemId` | `^(salon\|kitchen\|bedroom)\.[a-z0-9_]+$` |
| `chapterId` | one of `ch1_first_job` … `ch7_wedding` |

An invalid parameter or an unknown path redirects to `/home`. It never shows an error page or a blank
screen.

## Back behavior

1. **Sheet or overlay open:** back closes only it.
2. **`trip` page:** back never pops. It opens `tripPause` (FR-020). Back on `tripPause` closes it. The
   trip has no top-right back control, and every tappable element sits in the bottom third
   (constitution XI).
3. **Other `page` (not the trip):** back pops. A top-right back control (auto-mirrored arrow) does the same (FR-019).
4. **`tab` other than `home`, at its root:** back switches to the `home` branch (FR-021).
5. **`home` at its root:**
   - The first press shows a snackbar with ARB `pressBackAgainToExit` and starts a 2 s window.
   - A press inside the window leaves the app.
   - A press after the window counts as a new first press.
   - The predictive-back "back to home" preview is not shown on الموقف. This is an accepted consequence
     of the owner's choice.
6. **Startup:** the app always starts at `/boot` → `/home`. The last tab is not restored.

## Duplicate-navigation guard (FR-024)

Navigation goes through one helper. It ignores a request when:

- the target equals the current top location; or
- another navigation is still in progress (until its transition ends).

A tab tap on the selected tab returns that branch to its root.
