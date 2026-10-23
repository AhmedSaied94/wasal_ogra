# Implementation Plan: Design Refresh (M21)

**Branch**: `008.5-m21-design-refresh` | **Date**: 2026-10-23 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/008.5-m21-design-refresh/spec.md`

## Summary

M21 moves everything M03 and M02 built to the «كرتون ناعم» design in `docs/design/`, so every later
feature starts from it. It changes how the app looks, never what it does: no rule, economy, stored
data or content schema changes. It covers:

- **Tokens generated from the design.** A Dart tool turns `docs/design/tokens.json` into a committed
  token file, and a repo test fails when they differ. Marhey and Readex Pro replace Lalezar and Baloo
  (research R2, R3).
- **One component set.** HANDOFF §3's buttons, pills, controls, containers, sheets, dialogs, banners,
  navigation and story parts, all built on one lip-press `Pressable` with no Material ripples. A gallery
  on dev and staging shows them (R4).
- **The app's frame.** `Loading`, with its progress following the real boot steps; the `BottomNav`;
  the placeholders' headers; sheets, dialogs and the exit toast; and the digit-style control (R5, R6).
- **The trip in the new look.** The design's zones (HUD 114, dashboard 258) and its seat table, kept in
  points:
  - x spreads over narrower screens, and the front seat stays at the edge;
  - the cabin's top is cropped by up to 36 pt before anything shrinks;
  - every minimum holds on the reference frame and the Galaxy A06 (R7);
  - every M02 widget is redrawn as its design component (R9, R10);
  - the HUD, dashboard and tags clamp text at 1.15× (R8).
- **Events, choices, story trips, hints, pause and failure** in the design's look, with M02's
  behaviour (R11 – R13).
- **The owner's Rive file** (`wassal.riv`: every person, vehicle and UI animation), with a contract
  revised to it on 2026-10-23. People share one `Person` artboard, picked by a `look` number, with
  one input per state and one-shot triggers. Each passenger's pose is picked from M02's view and set
  as one input, and the triggers come from the engine's events. The
  design's SVGs, with code-driven motion, are the fallback and the goldens' art. An art tier keeps the
  A06 within budget (R14 – R18).
- **The design stays the reference.** The icons and illustrations are synced with a drift check. Each
  in-scope artboard has a sample state, a golden beside its PNG, and a layout test against its
  measured boxes. This is the routine every later screen follows (R19, R20).

Planning corrected the spec in two places, and the spec has been updated to match:

- **Story trips (FR-025, FR-027, US4 scenario 6, an edge case).** Content gives a story trip only its
  kind and its no-fights rule. So the HUD shows the «مشوار قصة» chip over the usual title, and the
  condition strip carries M02's text. A broken rule gets a fixed reason line. The design's story
  character, title and «أبو العروسة شاف خناقة» wait for the feature that adds them to content (R11).
- **Skins (US6 scenario 3) and the exception's height (FR-020).** A skin without a look keeps M02's
  fallback through visible types (R14). The height below which M02's exception applies is now
  `inset + 764` pt, 788 pt with a 24 pt inset (R7).

Every conflict between the handoff and a merged decision, with its outcome, is in research R1. The PR
repeats that table (FR-004).

Technical approach and versions: [research.md](./research.md).

## Technical Context

**Language/Version**: Dart 3.13.5 with the FVM-pinned Flutter 3.47.7 (`.fvmrc`).

**Primary Dependencies**:

- **New:** `flutter_svg ^2.3.0` (MIT), for the icons, the illustrations and the static art (R17).
- **Fonts (assets, OFL):** Marhey and Readex Pro, both variable TTFs from google/fonts (R3).
- **Existing and unchanged:** `flame`, `flame_rive`, `rive 0.14.11` (`Factory.flutter`), Riverpod 3
  with its generator, `go_router`, drift, M02's trip feature, M03's `NumberFormatter`, ARB and settings
  store.
- **Rejected:**
  - `lottie` and `flame_lottie`: the constitution locks Rive, so the handoff's §6 runtime is out;
  - `google_fonts`: it downloads at runtime, which breaks offline play;
  - `flame_svg`;
  - a widgetbook package.

**Storage**:

- **Nothing new is stored:** no table, column, preference or tunable.
- **Assets:**
  - `assets/fonts/` (the two families and their licences);
  - `assets/rive/{passengers,characters,vehicles,ui}.riv` (owner);
  - `assets/icons/*.svg` (92) and `assets/illustrations/**.svg`, synced from `docs/design/`.
- **Removed:** the old fonts and `assets/rive/passenger.riv`.

**Testing**:

- **Domain tests:**
  - the generated tokens against `tokens.json`;
  - the look table and skin fallback, including hidden archetypes;
  - `SceneLayout` on 390×444, 360×420 and 430×452, with every minimum;
  - the pose table and the event-to-trigger cues;
  - the failure summary's story flag and angry faces;
  - boot progress.
- **Component tests:** every state, the press, disabled, semantics, 44×44 hit areas, RTL, reduced
  motion.
- **Artboard checks:** a sample state, a golden at the artboard's size in both digit styles, and a
  layout test against `docs/design/boxes/` within ±2 pt (contracts/design-checks.md).
- **Assertions unchanged and passing:** M02's and M03's behaviour tests, including the 58 scripted
  fixtures, the kill-and-rebuild test and the who-paid frames (FR-042). Their goldens are regenerated in the new
  look.
- **Size checks:** at 390×844 and 360×800, at text scales 1.0 and 1.3, plus the exception's check at
  360×640.
- **Rive (tagged `rive`):** a contract test and goldens for the owner's files, with `Factory.flutter`.
- **Guards:**
  - **New:** design tokens, design assets, no Material ink, no retired design names.
  - **Extended:** the raw-value guard, to font sizes, shadows, radii, animation durations and curves in
    UI code, so SC-002 is enforced (tasks T116).
  - **Unchanged:** the other guards.
- **Coverage:** at least 80%.

**Target Platform**: Android, `minSdk 24`, `targetSdk 36`, all three flavors; portrait. Linux for CI.
iOS (phase 3) needs nothing beyond what M02 set up.

**Project Type**: A mobile app feature in the `wassal` monorepo. It touches:

- `apps/mobile/lib/core/theme/` (tokens, components);
- `lib/core/routing/` (pages, sheets, placeholders, the exit toast);
- `lib/features/boot/`, `lib/features/settings/` and `lib/features/trip/presentation/`;
- small parts of `lib/features/trip/domain/` (layout, looks, poses, the failure summary);
- the new `lib/features/dev/gallery/`.

**Performance Goals**:

- **On the Galaxy A06, over the busiest sample trip on `micro_old` with every seat in Rive:**
  - an average of at least 55 fps;
  - no one-second window under 45 fps;
  - memory under 300 MB;
  - the p90 frame time recorded against HANDOFF's 16 ms (SC-005).

  If the default `rive` tier misses, `near_rive` becomes the default (R18).
- **Cold start:** no white frame, and Home within 3 s (SC-006).
- **Download:** under 80 MB (SC-009).

**Constraints**:

- **No behaviour change.** Every M02 and M03 behaviour test keeps its assertions and passes (only
  finders and the way expected texts are built may change, each listed in the PR), and no rule, economy
  call, stored datum or schema moves (FR-003, FR-042).
- **Engine purity:** the pose and look functions read the view and decide nothing.
- **No ad SDK.** The design's ad places stay empty until M11.
- **No Arabic in `lib/`.** Copy goes in the ARB file; sample text lives in tests.
- **No raw style values outside `tokens/`, and no text in the Flame canvas.**
- **Offline:** fonts, art and animations are all bundled.
- **Rive stays:** no Lottie runtime (the constitution's locked stack; `docs/design/README.md`).

**Scale/Scope**:

- 7 user stories, 43 functional requirements, 10 success criteria.
- About 30 components, 9 artboards checked, 12 passenger looks, 6 characters, 2 vehicles and 11 UI
  animations in the contract.
- About 40 changed and 35 new `lib/` files, and about 30 test files.
- 4 new guards and 1 extended one, 1 CI path change, and 6 document updates.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| # | Principle | Applies | How M21 satisfies it |
| --- | --- | --- | --- |
| I | Engine purity | Yes | No rule moves. `TripController` still owns the only engine. The new domain code is pure: `SceneLayout`, `lookFor`, `poseFor`, the `CharacterCue` mapping, and the failure summary's two fields. It reads M02's view and the engine's events, and decides nothing. The one new view field, `claimOpen`, reads `state.claims`. The domain import guard still covers `features/trip/domain/`. The 58 scripted fixtures pass unchanged (SC-003). |
| II | Integer money | Yes | No amount changes type. Components take formatted strings, never `int` or `double` amounts. The integer-money guard is unchanged. |
| III | Parity | No | No rule, parameter or fixture changes. The sample pack and its checksums are untouched: skins map in the app (R14). |
| IV | Server authority | Yes | The BONAT revive and the booster purchase keep M02's `economy.buy` calls. The design's undo toast for small purchases is not used in the trip (clarification); it is built for M12 to decide on. |
| V | Offline-first | Yes | Fonts, Rive files, SVGs and tokens are bundled. Nothing new uses the network. `google_fonts` was rejected for this reason. |
| VI | Idempotency | No | No new operation, request or intent. M02's ids are unchanged. |
| VII | Content, not code | Yes | Names, prices, speech and the station names come from the pack, as before. Looks are app data because the art ships in the app (M02's reasoning). All new copy is ARB keys. No story text is invented in code (R11). |
| VIII | Tunable numbers | Yes | No new balancing number. Hop times stay the engine's per-line tunables; `motion.moneyHop` is skipped on purpose (R2). Presentation constants come from `tokens.json`, and change no outcome. |
| IX | No ads in a trip | Yes | No ad SDK and no ad call. `RewardedAdButton` is built but shown nowhere. The `Fail` artboard's ad revive and «زحمة»'s ad badge keep their places empty until M11. M02's no-ads guard is unchanged. |
| X | RTL and Arabic first | Yes | Components use directional insets and alignments, in the HTML's child order. Every golden is RTL in both digit styles. Every number goes through `NumberFormatter`. Arabic plurals stay ARB plurals. |
| XI | Accessible minimums | Yes, with M02's approved exception continued | `SceneLayout` keeps every minimum on 390×844 and 360×800: faces 84 and 52.5 pt, hit areas at least 44, notes 42×26, bubbles 16 pt unscaled, text at least 12 at 1.0. It is checked on the layout's output and on renders at text scales 1.0 and 1.3 (R7, R8). Below `inset + 764` pt, M02's exception continues until M07 (Complexity Tracking). The bottom-third rule and its exemptions are unchanged. Contrast, lightness and the no-white-on-`danger`/`sun` rule are checked for the new palette (R21). Reduced motion stops the shake, pop, pulse, parallax and the art's effects. At most two bubbles. Passenger labels never name a hidden type, and say «ليه باقي» only while hot (FR-036). |
| XII | No runtime LLM | Yes | Unchanged: lines come from the pack's pools. |
| XIII | Small, testable features | Yes | One spec folder. Tests come first for `SceneLayout`'s minimums, the pose table, the look fallback and the token check. Unit, component, golden, layout, size, Rive-contract and guard tests; coverage at least 80%. |

**Locked stack.** Flutter with FVM; Flame for the scene and Rive for the characters, as the constitution
locks. The handoff's Lottie runtime is not adopted; `docs/design/README.md` records that override.
Riverpod with its generator, `go_router`, drift. `flutter_svg` is a rendering library, not a stack
change. M02's `PassengerArtFactory` seam and the `Haptics` interface stay the plugin boundaries.

**Architecture boundaries.**

- Domain code stays pure and guarded.
- Text and HUD are Flutter widgets over the Flame scene, and the canvas guard stays.
- Components live in `core/theme/components/`; trip components in `features/trip/presentation/`.

**Security & privacy.** No network, no personal data, no secrets, no new permissions. The gallery and
the art-tier switch exist only on dev and staging builds. A prod-flavor test checks that the gallery
can't be reached. The PR touches no auth, purchase, ledger, sync or webhook code, so it needs the
normal review only.

**CI gates (constitution).**

- Mobile format, analyze, test and coverage: the same jobs. `flutter test` now includes the design
  checks.
- The `changes` job's path rule adds `docs/design/` (R2).
- Parity and the OpenAPI diff: unchanged.

**Gate result (pre-research): PASS with one carried exception.** Principle XI was the one to examine:

- **The A06.** The design's taller zones leave it a scene shorter than M02's 420 pt guarantee before
  any crop.
- **The clarification.** It settled that short screens stay with M07 and asked the plan for the new
  height.
- **The fix.** Research R7 keeps every minimum on the A06 by cropping, not scaling. The exception's
  scope is the same kind of screen as M02's, only with a new threshold.

**Gate result (post-design): PASS.** The re-check after Phase 1 found two things, both fixed in the
design:

- **The front seat.** At 360 pt, scaling the front seat's x would have pushed its face 5 pt off the
  edge, showing 79 pt, under the 80 pt minimum. It is now anchored to the end edge (trip-layout.md).
- **Passenger labels.** The design's passenger labels name hidden types and who owes. The layout
  tests pair those boxes by seat instead of copying the labels (design-checks.md).

Nothing else was found:

- `PassengerView` gains one field with no rule.
- `FailSummary` gains a flag and a face list derived from the engine's counters.
- No tunable, table or schema is added.
- Every economy call is M02's.

## Project Structure

### Documentation (this feature)

```text
specs/008.5-m21-design-refresh/
├── plan.md                    # This file
├── research.md                # Phase 0: decisions R1–R22 and the hand-overs
├── data-model.md              # Phase 1: tokens, looks, layout, art, view changes, boot progress, ARB
├── quickstart.md              # Phase 1: setup, checks, scenarios 1–9, owner checks, done when
├── contracts/
│   ├── design-tokens.md       # generation, names, theme, extras, fonts, palette checks
│   ├── components.md          # the shared set, its rules, the gallery, tests
│   ├── trip-layout.md         # zones, height and width rules, seat tables, sizes, layers, motion
│   ├── rive-characters.md     # what the owner's file contains
│   └── design-checks.md       # sample states, goldens, layout tests, skips, expected differences
├── checklists/requirements.md
└── tasks.md                   # Phase 2 (/speckit-tasks), not created here
```

### Source Code (repository root)

```text
apps/mobile/
├── pubspec.yaml                                   # flutter_svg; fonts Marhey and ReadexPro; asset folders
├── assets/
│   ├── fonts/                                     # Marhey-VariableFont_wght.ttf, ReadexPro-VariableFont_HEXP_wght.ttf, OFL-*.txt (old fonts removed)
│   ├── rive/                                      # passengers, characters, vehicles, ui .riv (owner); README rewritten; passenger.riv removed
│   ├── icons/                                     # NEW: 92 SVGs (synced)
│   └── illustrations/{passengers,characters,vehicles,screens}/  # NEW: synced SVGs
├── tool/design/
│   ├── gen_tokens.dart                            # NEW: tokens.json → design_tokens.dart
│   └── sync_assets.dart                           # NEW: docs/design → assets
├── lib/
│   ├── core/theme/
│   │   ├── tokens/design_tokens.dart              # NEW (generated): Color, Type, Radius, Lip, Ring, Space, Layout, Motion, WassalTokens
│   │   ├── tokens/design_extras.dart              # NEW: the artboards' between-token values
│   │   ├── tokens/{colors,typography,shape,space,motion}.dart   # REMOVED
│   │   ├── app_theme.dart                         # from the generated tokens; NoSplash
│   │   └── components/                            # pressable, buttons, pills, controls, containers, overlays, nav, story (sticker parts removed)
│   ├── core/audio_haptics/haptics.dart            # + selection()
│   ├── core/routing/                              # app_page (was sticker_page), sheet_page → AppSheet, placeholder_screen, back_to_exit → AppToast, shell_scaffold → BottomNav
│   ├── bootstrap/startup.dart                     # reports BootProgress; the art step
│   ├── features/boot/boot_screen.dart             # the Loading artboard
│   ├── features/settings/                         # the digit-style Segmented row
│   ├── features/dev/gallery/                      # NEW: components and tokens pages (dev and staging)
│   ├── features/trip/
│   │   ├── domain/scene_layout.dart               # rewritten: zones, crop, xFactor, seat tables
│   │   ├── domain/looks.dart                      # NEW (replaces skin_looks.dart)
│   │   ├── domain/poses.dart                      # NEW: poseFor
│   │   ├── domain/{cues,fail_summary,trip_view,projection}.dart  # CharacterCue; brokeStoryRule, angryFaces; claimOpen
│   │   ├── application/art_tier.dart              # NEW
│   │   ├── presentation/top_bar/                  # TripHud, ReputationBar, StationStrip
│   │   ├── presentation/scene/                    # cabin, windows, hand, PassengerAvatar (Rive or SVG), CharacterAvatar, VehicleSprite, rive_art loader
│   │   ├── presentation/overlays/                 # StationTag, MoneyNote, SpeechBubble, LedgerBadge, ChoicePopover, EventBanner, story strip, hint
│   │   ├── presentation/dashboard/                # HandSlot, CallChangeButton, ChangeTray/TrayCell, BoosterButton, LastWordsLog
│   │   ├── presentation/cards/                    # Pause, Fail, AppDialog-based cards
│   │   └── presentation/trip_{colors,text,motion}.dart  # from tokens
│   └── l10n/app_ar.arb                            # new keys (data-model.md), two removed
├── test/
│   ├── repo/                                      # design_tokens, design_assets, no_ink, no_retired_design (new); no_raw_style_values (extended)
│   ├── core/theme/                                # palette (rewritten), components/*
│   ├── features/trip/domain/                      # scene_layout, looks, poses, cues, fail_summary
│   ├── features/trip/rive_art_{contract,goldens}_test.dart   # replace rive_character_*
│   ├── design/                                    # NEW: boxes reader, samples/, <artboard>_layout_test.dart
│   ├── goldens/{design,components,trip,…}/        # artboard goldens; M02 and M03 goldens regenerated
│   └── a11y/                                      # trip_minimum_sizes on 390×844 and 360×800; minimum_sizes
└── integration_test/trip_perf_test.dart           # unchanged harness, new art
.github/workflows/mobile.yml                       # the changes job's path rule adds docs/design/
docs/architecture-mobile.md                        # §2, §5, §8, §20
docs/delivery-plan.md                              # progress
specs/008-m02-trip-screen/contracts/{scene-layout,rive-character}.md   # first line points here
specs/001-m03-app-shell/contracts/design-tokens.md # first line points here
docs/owner-actions.md                              # M21 section (at /speckit-implement)
CLAUDE.md                                          # the Rive files, the design tools, the guards
```

**Structure decision.**

- **Shared parts in `core/theme/`.** Components and tokens stay in M03's folders, so later features
  have one place to look. The trip's own components stay in `features/trip/presentation/`, next to the
  scene that places them.
- **Domain changes are small and pure.** The layout, looks, poses and the failure summary's fields are
  presentation logic in M02's guarded `domain/`. The engine and the controller don't change.
- **The gallery is a dev feature.** `features/dev/gallery/` is opened from the Home placeholder's
  playtest section, as M02's tools are, and adds no route.
- **Design files are synced, not referenced.** Flutter bundles only files under the package, so the
  SVGs are copied, with a test that keeps them equal to `docs/design/`.

## Complexity Tracking

> Fill ONLY if Constitution Check has violations that must be justified

| Violation | Why needed | Simpler alternative rejected because |
| --- | --- | --- |
| Constitution XI: **M02's approved exception, continued with a new threshold.** On screens shorter than `inset + 764` pt (788 pt with a 24 pt inset, such as 360×640), faces shrink below 50 pt (back row) and 80 pt (near row). Touch targets, notes, bubbles and text keep their minimums on every screen. It was 744 pt in M02; the design's taller HUD and dashboard raise it. Still time-boxed: it ends when M07 merges, with M07's "Handed over from M02" item in `docs/delivery-plan.md`, which 008.5 left to M07 on the design's bands. **Approved by the owner on 2026-10-22 (M02) and continued on 2026-10-23 (008.5, Clarifications Q1).** **Pending the owner's approval (found in implementation, T060):** on the same screens the 258 pt dashboard is taller than a third of the screen, so its top rows (the hand and «حد معاه فكة؟», then the drawer's first row) sit above the bottom third: on 360×640 the hand row starts at y 394, where the third starts at 427. The minimum-size test exempts the dashboard's own controls on the small surface only; on the reference frame and the A06 every control is in the bottom third. | The HUD (114 pt) and the dashboard (258 pt) hold the controls and text that must keep their minimums. The design crops up to 36 pt of cabin wall before anything shrinks. Below that, there is no room for `micro_old`'s three rows at their sizes. The reference frame and the Galaxy A06 meet every minimum. | Shrinking the HUD or the dashboard breaks the touch-target and text minimums. A short-screen layout (fewer rows on screen, a narrower dashboard, a zoomed cabin) is a design of its own, with goldens. The owner chose to leave it to M07 (Clarifications Q1). |
