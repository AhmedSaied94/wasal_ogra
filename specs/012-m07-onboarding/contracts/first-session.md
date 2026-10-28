# Contract: The First Session

Where a launch goes, what comes before a trip, what follows a result, and what other features read.
Spec FR-001–FR-005, FR-031–FR-039; research R1–R4, R10–R12, R21.

## `FirstSession` (pure, `lib/features/onboarding/domain/first_session.dart`)

Built from `FirstSessionFacts`, which holds no state of its own:

| Fact | From |
| --- | --- |
| `flags` | the `first_session` row: `openingDoneAtMs`, `scenesDue`, `scenesSeen`, `fuelLessonDoneAtMs`, `stepReached`, `doneAtMs` (data-model.md) |
| `tutorialTrips` | the first five trips by number of the line whose unlock is `start`, in the active pack (R3) |
| `progress` | `EconomyView.progress` (`firstCompletedAtMs`, `plays`) |
| `hasStartedATrip` | any `progress` row, `unfinished`, or a `trip_start` in the op log |
| `unfinishedTripId` | `EconomyView.unfinished` |
| `fuel` | `EconomyView` liters, unlimited window, `fuelMax` |
| `tutorialGranted`, `displayName`, `nameRefused` | `EconomyView` (R8) |
| `openingScene` | the pack's scene whose `plays.kind == opening` |
| `afterTripScenes` | the pack's scenes with `plays.kind == after_trip`, by trip id |

### Answers

| Method | Returns | Rule |
| --- | --- | --- |
| `launchTarget(FirstOpenOutcome)` | a location | `restored`, or `hasStartedATrip`: `/home`. Else: `/onboarding/intro` if the opening isn't done and a scene exists; `/onboarding/name` if `displayName == null`; else `/trip/<tutorialTrips[0]>`. |
| `beforeStart(tripId)` | `null`, `DueScene(sceneId)` or `FuelLesson` | First a due scene (any in `scenesDue` not in `scenesSeen`). Then the fuel lesson if `!tutorialGranted`, `fuelLessonDoneAtMs == null`, `tripId ∈ tutorialTrips`, and either `tripId` is the last tutorial trip with `plays == 0`, or liters < 1 outside an unlimited window. |
| `onArrivalAtHome()` | `null` or `DueScene` | A due scene. (The name sheet is `NameReaskHost`'s, contracts/name.md.) |
| `nextAfterResult(tripId)` | a location | For a tutorial trip: the next tutorial trip without `firstCompletedAtMs`, as `/trip/<id>`; `/home` when none is left. Otherwise `/home`. |
| `inFirstSession` | bool | `!tutorialDone && hasStartedATrip` |
| `coachFor(tripId)` | `int?` (lesson index 0–4) | `tripId`'s index in `tutorialTrips` when its `firstCompletedAtMs == null`, or when the debug switch is on (R21); else null |
| `boostersLocked` | bool | `!tutorialDone` |
| `tutorialDone` | bool | every trip in `tutorialTrips` has `firstCompletedAtMs` |
| `stepReached` | 0–8 | the stored value (written as below) |

### Events that write the flags (`FirstSessionService`)

| When | Writes |
| --- | --- |
| The opening scene opens, or the Name card when the pack has no opening scene (the page writes it through the store) | step ≥ 1 |
| The opening scene finishes or is skipped | `openingDoneAtMs` |
| `launchTarget` returns `/home` for `restored` | `openingDoneAtMs` (if null) |
| A tutorial trip starts (its `trip_start` applied) | step ≥ 2 + index for trips 1–3; ≥ 7 for trip 4; ≥ 8 for trip 5 |
| A trip's result is recorded as its first finish, and an `after_trip` scene names it | `scenesDue += sceneId`, in the same moment as the result (listener on the economy's views: `firstCompletedAtMs` turned non-null) |
| An after-trip scene finishes or is skipped | `scenesSeen += sceneId`; step ≥ 5 |
| The step after the scene (the ask's place) is passed | step ≥ 6 |
| The fuel lesson's button | `grantTutorialGift`, then `fuelLessonDoneAtMs` |
| `tutorialDone` turns true | `doneAtMs` |

Steps never go down. A restored player's progress never makes a scene due: only a first finish
observed on this phone does.

## Boot (`features/boot/boot_screen.dart`)

After M06's steps (`firstOpenOutcome` with `firstOpenWait`, `markDone(account)`,
`deleteAllExcept`, `handOver()`):

1. An unfinished trip opens `/trip/<id>` (paused, M02). Not redirected.
2. Otherwise `context.go(firstSession.launchTarget(outcome))`.

## Router (`core/routing/router.dart`, global `redirect`)

After the boot rule:

| Location | Condition | Goes to |
| --- | --- | --- |
| `/trip/:tripId` | not the unfinished trip, and `beforeStart(tripId)` is a `DueScene` | `/onboarding/scene/<sceneId>?then=/trip/<tripId>` |
| `/trip/:tripId` | same, and `beforeStart` is `FuelLesson` | `/onboarding/fuel?then=<tripId>` |
| `/home` | `onArrivalAtHome()` is a `DueScene` | `/onboarding/scene/<sceneId>?then=/home` |
| `/onboarding/intro` | no opening scene in the pack | `/onboarding/name` |

The redirect reads providers synchronously (`economyViewProvider`, `firstSessionFlagsProvider`, the
active content). `then` must be a path inside the app (`/trip/...` or `/home`); anything else becomes
`/home`.

## New routes (`core/routing/routes.dart`)

| Name | Path | Presentation | Links |
| --- | --- | --- | --- |
| `onboardingIntro` (existing) | `/onboarding/intro` | page | `onboardingName` |
| `onboardingName` (existing) | `/onboarding/name` | page | `trip`, `home` |
| `onboardingScene` (new) | `/onboarding/scene/:sceneId` | page | `trip`, `home` |
| `onboardingFuel` (new) | `/onboarding/fuel` | page | `trip` |

`route_table_test.dart`, `navigation_test.dart` and the all-destinations goldens are updated; mobile §9
lists both new routes.

The intro and the Name card also take an optional `?then=`, only from the playtest card (US6): the
opening passes it to the Name card, which goes there (through `safeThen`) instead of trip 1. Without
it, both behave as above.

## The result screen (until M08)

`/trip/:tripId/result` keeps M02's `ResultSummary`. While `inFirstSession` (or the trip just finished
was the last tutorial trip), it adds `AppButton.primary(size: l)` «كمّل» (`firstSessionContinue`), key
`first-session-continue`, which does `context.go(nextAfterResult(tripId))`. The existing links stay.

## A late restore (`FirstSessionLifecycle`, in the app builder)

Listens to `progressRestoredProvider`:

- on `/onboarding/intro` or `/onboarding/name`, when the restored view has a `displayName` or any
  progress: `openingDoneAtMs` is set and the app goes to `/home`;
- on a trip route: nothing (the next navigation reads the new facts);
- elsewhere: nothing.

## Steps after the scene (step 6, for M14)

`FirstSessionHooks.afterScene` is an async hook, a no-op in M07. M14 sets it to show the notification
ask. The flow awaits it before going on to the scene's `then`.

## For other features

| Feature | Reads or calls |
| --- | --- |
| M08 | `nextAfterResult` as the result's main action while `inFirstSession`; `/trip/<id>` for every start so the redirects apply; `boostersLocked` on the pre-trip card; keeps `NameReaskHost` on Home |
| M10 | `scenesSeen` (to send `story_progress`); `ScenePlaysKind` to extend; `PanelArt` and `PanelFallback` |
| M11 | `tutorialDone` (no interstitial before it) |
| M14 | `FirstSessionHooks.afterScene`; the name sheet (contracts/name.md) |
| M15 | `stepReached` changes, as `tutorial_step` |

Providers: `firstSessionProvider` (a `FirstSession` rebuilt when its facts change),
`firstSessionFlagsProvider` (stream of the row), `firstSessionServiceProvider`.
