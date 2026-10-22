# Implementation Plan: Trip Screen (M02)

**Branch**: `008-m02-trip-screen` | **Date**: 2026-10-22 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/008-m02-trip-screen/spec.md`

## Summary

M02 makes the first playable trip: the trip screen that drives M01's engine, charges and records
through M05's economy, and reads M04's content, fully offline. It covers:

- **A controller that owns the engine.** One `TripController` runs the engine in fixed 33 ms steps
  under Flame's variable frame rate, applies every player intent as an engine command, and is the
  only thing that talks to the economy and to disk. Widgets never touch trip state (research R4, R5).
- **A view that keeps the secret.** A pure projection turns the engine's state into what the screen
  may show. It has no field for who has paid, so the memory puzzle can't leak, outside the moments
  the spec allows (R10).
- **A scene in Flame, everything else in Flutter.** Flame draws the cabin, the windows, the passengers
  and the driver's hand. Text, touch and money tokens (which show amounts) are Flutter widgets over the
  scene, placed by one pure layout function, so the minimum sizes are tested in points (R3, R15).
- **Rive passengers from one file.** The owner's `passenger.riv`, with its states and looks set by data
  binding, through `flame_rive` with the Flutter renderer. Stand-ins cover the cabin, money, effects and
  sound, and stand in for passengers in goldens. Rive's runtime is MIT, with no fees; exporting needs a
  paid editor seat (R1, R17, resolving mobile §24.6).
- **A trip that survives anything.** The replay record is appended to drift on every accepted command
  and pause. A small outbox keeps booster uses and the economy in step across a kill. The next launch
  goes straight back into the paused trip (R6 to R9, the UI side of mobile §24.4).
- **The ux-spec's trip.** The top bar and station strip, the dashboard, the choices (only the dispute
  stops the clock), the eight events, the boosters with their BONAT purchase, «حد معاه فكة؟», undo,
  hints by line, the failure card with its BONAT revive, sound and vibration with switches, and reduced
  motion (R11 to R19).
- **Playtest tools** on dev and staging: a trip list, a debug panel, and a result placeholder with the
  stars (R21).

Planning refined six of the spec's requirements, and the spec has been updated to match:

- **FR-033:** a passenger's growing impatience is an allowed sign, since the ux-spec shows it and the
  engine runs patience only for owed passengers; speaker labels follow the look, never the hidden type
  (R10).
- **FR-042:** over-change stays silent during the trip, as the product spec says (trip-view.md).
- **FR-017, FR-049 and the short-screen edge case:** the bands keep their sizes and the scene takes the
  rest; every minimum holds from 744 pt of height; below that only the faces shrink (R15).
- **FR-020:** the station letters are أ ب ج د by stop order (R16).
- **SC-002 and FR-053:** 58 of the 60 parity fixtures can be played through the controls; the two
  with a dispute answered late or never can't, once the dispute stops the clock (R11).
- **FR-054 and SC-007:** the goldens' three surfaces.

Technical approach and versions: [research.md](./research.md).

## Technical Context

**Language/Version**: Dart 3.13.5 with the FVM-pinned Flutter 3.47.7 (`.fvmrc`); Python 3 (standard
library only) for the stand-in sound script.

**Primary Dependencies**:

- **New.** `flame ^1.38.2`, `flame_rive ^1.11.2`, `rive ^0.14.11` (brings `rive_native 0.1.11`),
  `flame_audio ^2.12.2` (audioplayers 6.8.1), and `flame_test ^2.3.1` (dev). All MIT.
- **Existing.** `trip_engine` and `content_models` (path), Riverpod 3 with its generator, `go_router`,
  `drift`, M04's content source, M05's economy, M03's tokens, ARB, `NumberFormatter` and settings store.
- **Rejected.** `flutter_soloud` (a C++ build hook on every test run, and an unpinned codec download)
  (R18).

**Storage**:

- App database v2: `trip_record`, `trip_record_command`, `trip_intent` (data-model.md,
  contracts/trip-records.md), with `drift_schemas/app/drift_schema_v2.json` and the generated v1 → v2
  tests.
- Settings store: `pref.trip_sound`, `pref.trip_haptics`, `pref.trip_hints_seen`.
- Assets: `assets/rive/passenger.riv` (owner), `assets/audio/sfx/*.wav` (generated, about 300 KB).

**Testing**:

- Pure-Dart domain tests: the projection, the who-paid rule, bubbles, the log, hints, the strip, the
  failure summary, `SceneLayout` and its minimum sizes, skins, cues.
- Controller tests over M05's in-memory economy: every phase, every economy outcome, kill points, the
  outbox, resume and cleanup, and no ad call while running.
- The scripted player: 58 parity fixtures through the widgets with exact time.
- Kill and rebuild on a real database file at 50 random moments.
- Goldens with `flame_test` and stand-in art on three surfaces, RTL, both digit styles; Rive character
  goldens with `Factory.flutter`; size checks on the layout and the renders.
- Integration tests on a device: offline play, relaunch mid-trip, and the A06 performance run.
- Guards for the trip domain's imports, trip-table writes, no ads and no text in the canvas.
- Coverage ≥ 80% (R24).

**Target Platform**: Android, `minSdk 24`, `targetSdk 36`, all three flavors; portrait. iOS (phase 3)
needs only the reduced-motion flag, which R19 already reads. Linux for CI.

**Project Type**: A mobile app feature in the `wassal` monorepo: `apps/mobile/lib/features/trip/`
(with `domain/`, `application/`, `data/`, `presentation/`), `lib/core/audio_haptics/`, and small changes
to `lib/core/{storage,theme,routing,preferences}/` and the boot screen.

**Performance Goals**:

- On the Galaxy A06: 60 fps target, at least 55 fps on average and never a one-second window below
  45 fps through the busiest sample trip with the real character in every seat (SC-003); under 300 MB
  (SC-004); a drawer tap in the hand within 100 ms and the first frame within 1 s (SC-005).
- No widget rebuild for a step that only moves tokens (R5).

**Constraints**:

- Offline: no network call in a trip.
- Engine purity: every rule stays in `trip_engine`; the screen projects and sends commands.
- Integer money; formatting only at the edge.
- No Arabic in code; no text in the canvas; no raw colors.
- No ad call; the ad seam may only be asked while the trip is paused or failed.
- One writer per table.
- Who has paid never reaches a widget outside FR-033's exceptions.

**Scale/Scope**:

- 7 user stories, 55 functional requirements, 9 success criteria.
- About 45 new `lib/` files, 3 tables, about 90 ARB keys, 9 stand-in sounds, 1 character file, and about
  35 test files.
- 3 new guards and 3 extended ones, and 6 document updates.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| # | Principle | Applies | How M02 satisfies it |
| --- | --- | --- | --- |
| I | Engine purity | Yes | `TripController` owns the only `TripEngine`; widgets and the scene call its intent methods and read `TripView`, and never change state. The projection reads state to draw it and decides no rule: what a tap does, where money goes, reputation and stars all come from the engine's commands, state and events. Read-only engine helpers (`breaksLeft`, `undoAvailableUntilMs`, `ledgerPeekActive`, `patiencePermille`, `progressPermille`) are used instead of re-deriving. The scripted player proves the screen adds or loses nothing (SC-002). The trip domain's imports are guarded (R5, R10, R24). |
| II | Integer money | Yes | Amounts stay integer piasters from the engine to the widget; `NumberFormatter.piasters(int)` formats them at the edge. The new tables are `INTEGER`/`TEXT`. The integer-money guard now covers `features/trip/`. |
| III | Parity | No | No rule, score, parameter or PRNG change. The fixtures are read, never written; 58 of them are replayed through the screen. |
| IV | Server authority | Yes | BONAT is spent only through `economy.buy` (boosters, revive), optimistically up to the local balance; nothing adds BONAT or converts it. Every booster use, start and result goes through `EconomyService` (R7). |
| V | Offline-first | Yes | A whole trip, its resume and its records need no network (SC-001). The only network is the one-time `rive_native` download at build time. |
| VI | Idempotency | Yes | One request id per intent, held until applied or refused; the start's id is the record's key, and a booster use's id lives in `trip_intent`, so retries after a kill reuse it (R6, R7). Time inside a trip is the engine's clock; the economy's trusted time is untouched. |
| VII | Content, not code | Yes | Trips, line and station names, speech and prices come from the active pack; the trip keeps the definition and version it started with. Every player string is in the ARB file; speaker labels, hints, causes and rejections are keys. Skins map to looks in app data because art ships in the app (R13, R17, R22). |
| VIII | Tunable numbers | Yes | `TripParams` is built from every registered tunable through `ConfigSource`; bubble minimums and hint modes are the existing per-line keys. No new balancing number; presentation constants (animation lengths, the meter's threshold, the catch-up cap) change no outcome and are named in `trip_motion.dart` (R23). |
| IX | No ads in a trip | Yes | No ad SDK, no ad call. The `TripAdOffers` seam is never offered until M11, and a test fails if it is called while the engine runs; a guard forbids ad imports in `features/trip/` (R20). |
| X | RTL and Arabic first | Yes | Every widget is RTL; columns of seats follow RTL; digits follow the player's setting; goldens cover every FR-054 state in RTL with both digit styles (R15). |
| XI | Accessible minimums | Yes, with one approved exception | `SceneLayout` guarantees every minimum from 744 pt of height, tested on its output and on renders at 390×844, 360×800 and 360×744. Below 744 pt, faces shrink under their minimums while touch targets, tokens and text keep theirs. That is the exception in Complexity Tracking, time-boxed until M07. Every control the player plays with is in the dashboard, the bottom third. Outside it there are only XI's (1.4.0) exemptions: the scene's own items (passengers, dropped notes, choice answers next to their passenger), the top bar's pause button, and the debug icon on internal builds. A test measures it (T043). Stations show color and letter; new tokens pass contrast and lightness checks. Reduced motion removes shake and pop; vibration and sound have switches. Every key event has at least two channels besides sound. Over-change gets no cue, as XI 1.4.0 says («المستغل يسكت»). At most two bubbles, each for the line's minimum (R15–R19, trip-view.md). |
| XII | No runtime LLM | Yes | Lines come from the pack's pools with the engine's seeded `variant`. |
| XIII | Small, testable features | Yes | One spec folder. Tests first for the projection, the who-paid rule and the record's rebuild. Unit, controller, scripted-player, kill-and-rebuild, golden, size, integration and guard tests; coverage ≥ 80% (R24). |

**Locked stack.** Flame for the scene and Rive for characters, as the constitution locks; `flame_rive`
bridges them, and `flame_audio` is in mobile §2's dependency list. Riverpod with its generator,
`go_router`, drift. Every plugin sits behind an interface: `SfxPlayer`, `Haptics`,
`PassengerArtFactory`, `TripRecords`, `TripAdOffers`.

**Architecture boundaries.** The trip's rules stay in the domain package; `features/trip/domain/` holds
only pure projection code, under the import guard. Text and HUD are Flutter widgets over the Flame
scene, and a guard keeps text out of the canvas.

**Security & privacy.** No network, no personal data, no secrets. The records hold game ids and
commands only, in the private database that M05 already leaves out of backup. The economy calls are
M05's, unchanged; this PR touches no auth, purchase, ledger rule, sync or webhook, so it needs the
normal review only. The playtest panel's clipboard copy exists only in dev and staging.

**CI gates (constitution).** Mobile analyze, unit, widget and golden tests: unchanged jobs, with
`rive_native`'s Linux setup step before `flutter test` (contracts/ci-checks.md). Parity and the
OpenAPI diff: unchanged.

**Gate result (pre-research): PASS.** No exceptions. Principle XI was the one to examine: the
minimum sizes hold on the reference frame and on every screen at least 744 pt tall, as the ux-spec
defines them relative to the reference frame.

**Gate result (post-design): PASS.** The re-check after Phase 1 found nothing new:

- `TripView` (data-model.md) has no fare, payment or balance field;
- every trip-table column is `INTEGER` or `TEXT`, and only the trip store writes them;
- every economy call follows M05's caller rules (engine first for a booster use, economy first for a
  revive), with ids that survive a kill;
- no tunable is added, and every string is an ARB key;
- token amounts, the only text that moves with the scene, are Flutter widgets (scene-layout.md).

**Gate re-check after `/speckit-analyze` (2026-10-22): PASS with one approved exception.** The
analysis found three conflicts with Principle XI that the gates above missed. Each is now resolved:

- **The pause button in the top bar** (ux-spec «الشريط العلوي», M03's hand-over) broke XI's bottom
  third. The constitution was amended to 1.4.0, with the owner's approval: controls that stop play,
  and the scene's own items, are exempt. ux-spec rule 2 («إيد واحدة وموبايل رأسي») was aligned with it.
- **Silent over-change** broke XI's "wrong change" key event. In 1.4.0 that event means short
  change, and over-change stays silent («المستغل يسكت»). ux-spec rule 4 was aligned with it.
- **Faces under 744 pt.** The pre-research gate said the ux-spec measures its minimums on the
  reference frame. It doesn't: «الأحجام الدنيا» has no frame. Smaller faces on short screens are now
  a time-boxed exception (Complexity Tracking).

## Project Structure

### Documentation (this feature)

```text
specs/008-m02-trip-screen/
├── plan.md                    # This file
├── research.md                # Phase 0: decisions R1–R25, documents, hand-overs
├── data-model.md              # Phase 1: tables, preferences, session, phases, view, cues
├── quickstart.md              # Phase 1: setup, scenarios 1–9, A06 checks, done when
├── contracts/
│   ├── trip-controller.md     # the controller, providers, opening, sequences, launch, ads seam
│   ├── trip-view.md           # the projection, who has paid, bubbles, log, hints, cues, rejections, text
│   ├── scene-layout.md        # bands, sizes, seats, layers, bubbles, motion, golden surfaces
│   ├── rive-character.md      # what passenger.riv must contain (the owner's file)
│   ├── trip-records.md        # the record store, writes, rebuild, cleanup, schema, guards
│   └── ci-checks.md           # workflow changes and guards
├── checklists/requirements.md
└── tasks.md                   # Phase 2 (/speckit-tasks), not created here
```

### Source Code (repository root)

```text
apps/mobile/
├── pubspec.yaml                                  # flame, flame_rive, rive, flame_audio; flame_test (dev); assets
├── assets/rive/passenger.riv                     # NEW (owner): the character (rive-character.md)
├── assets/audio/sfx/*.wav                        # NEW: 9 stand-in effects (generated)
├── tool/sfx/generate.py                          # NEW: deterministic stand-in sound generator
├── tool/perf/trip_fps.sh                         # NEW: A06 frame and memory run
├── drift_schemas/app/drift_schema_v2.json        # NEW: exported schema
├── lib/
│   ├── features/boot/boot_screen.dart            # hand-off to the unfinished trip; stale-record cleanup
│   ├── core/
│   │   ├── audio_haptics/                        # NEW: SfxPlayer (flame_audio low-latency pools), Haptics, providers
│   │   ├── storage/{app_database,tables}.dart    # v2: the three trip tables
│   │   ├── theme/tokens/colors.dart, app_theme.dart  # fare, bubbleWarn/Fight/Thanks, shirts
│   │   ├── preferences/shared_prefs_settings_store.dart  # the three new keys
│   │   ├── config/tunable_snapshot.dart          # NEW: flat map of every tunable for TripParams
│   │   └── routing/{router,trip_pause_overlay}.dart  # trip and result screens; the guard opens the new pause card
│   ├── features/trip/                            # NEW
│   │   ├── domain/                               # pure: trip_view, projection, bubble_queue, talk_log, hints,
│   │   │                                         #   station_strip, fail_summary, scene_layout, skin_looks, cues, line_ids
│   │   ├── application/                          # trip_controller, trip_phase, trip_session, trip_loop,
│   │   │                                         #   trip_settings, trip_ad_offers
│   │   ├── data/                                 # trip_records (interface), drift_trip_records, trip_kill_point
│   │   ├── presentation/
│   │   │   ├── trip_screen.dart                  # bands, lifecycle, immersive mode, back guard
│   │   │   ├── top_bar/                          # pause button, line, reputation, station strip
│   │   │   ├── scene/                            # TripGame, cabin, windows, passengers (Rive and stand-in), hand, effects
│   │   │   ├── overlays/                         # token Flow, hit areas, choices, bubbles, hint, banner, story strip
│   │   │   ├── dashboard/                        # hand, break button, drawer, boosters, talk log
│   │   │   ├── cards/                            # pause, failure, dispute, booster purchase, empty fuel, retry
│   │   │   ├── playtest/                         # trip list, debug panel, result summary (dev and staging)
│   │   │   └── trip_motion.dart                  # presentation constants
│   │   └── trip_providers.dart                   # controller, records, art, settings, ad offers
│   └── l10n/app_ar.arb                           # about 90 trip keys
├── test/
│   ├── features/trip/{domain,application,data,presentation}/
│   ├── features/trip/scripted_player_test.dart   # 58 fixtures through the controls
│   ├── features/trip/kill_rebuild_test.dart
│   ├── features/trip/rive_character_*_test.dart  # contract and goldens (Factory.flutter)
│   ├── goldens/trip/                             # FR-054 states × 3 surfaces × 2 digit styles
│   ├── a11y/trip_minimum_sizes_test.dart
│   ├── drift/                                    # generated v1 → v2 tests
│   ├── repo/                                     # domain_imports, economy_writes (extended); no_ads_in_trip, trip_text_in_canvas (new)
│   └── helpers/trip.dart                         # fake art, sfx, haptics; fixture loader; scripted player
└── integration_test/
    ├── trip_offline_test.dart                    # SC-001
    ├── trip_relaunch_test.dart                   # FR-055
    └── trip_perf_test.dart                       # SC-003 to SC-005 (owner, A06)
.github/workflows/mobile.yml                      # rive_native setup before flutter test and update-goldens
docs/architecture-mobile.md                       # §2, §8, §10, §24.4, §24.6
docs/delivery-plan.md                             # M05 merged in #8; M02 progress
specs/001-m03-app-shell/contracts/design-tokens.md  # the new tokens
docs/owner-actions.md                             # M02 section (at /speckit-implement)
CLAUDE.md                                         # rive_native setup, sfx script, trip perf tool, the Rive file
```

**Structure decision.**

- **One feature folder.** `features/trip/` is the folder mobile §5 names for the trip screen. Its
  `domain/` holds the projection and layout, pure and guarded; `application/` the controller;
  `data/` the record store; `presentation/` the Flutter and Flame code.
- **Shared plumbing in `core/`.** Sound and vibration go in `core/audio_haptics/`, the folder mobile §5
  names, because later screens (result, shop) will use them. The trip tables join the app database in
  `core/storage/`.
- **M03's pieces are replaced in place.** The trip route keeps its path, name and links; its screen
  becomes `TripScreen`, and `tripPause` stays an overlay without a URL, now the full pause card. The
  route table and its test are unchanged.

## Complexity Tracking

> Fill ONLY if Constitution Check has violations that must be justified

| Violation | Why needed | Simpler alternative rejected because |
| --- | --- | --- |
| Constitution XI: on screens shorter than 744 pt (such as 360×640), faces shrink below 50 pt (back row) and 80 pt (near row). Touch targets, tokens, bubbles and text keep their minimums on every screen. Time-boxed: it ends when M07 merges. The follow-up that removes it is M07's "Handed over from M02" item in `docs/delivery-plan.md` (T096): a trip layout for screens under 744 pt in which faces keep their minimums, with goldens at 360×640. **Approved by the owner on 2026-10-22.** | The top bar (110 pt) and the dashboard (230 pt) hold the controls and text, which must keep their minimums. On a 640 pt screen the scene keeps only 316 pt, too little for `micro_old`'s rows and windows at those sizes (T012 checks it at 360×316). The reference frame, the Galaxy A06 and 360×744 all meet every minimum. | Shrinking the bands breaks the touch-target and text minimums, which the playtest found mattered most. A short-screen layout (fewer rows on screen, a narrower dashboard, a zoomed cabin) is a design of its own, with goldens. It would hold up the first playable trip, which is for the internal test on the A06, while the closed test (M07 at the earliest) is the first time outside players use the screen. |
