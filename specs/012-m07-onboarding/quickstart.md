# Quickstart: Onboarding and the Tutorial Trips (M07)

How to check that M07 works: the automated checks, then the scenarios on a device. Contracts:
[first session](./contracts/first-session.md), [coach](./contracts/coach.md),
[name](./contracts/name.md), [fuel lesson](./contracts/fuel-lesson.md),
[scenes](./contracts/scenes.md), [compact layout](./contracts/compact-trip-layout.md),
[CI checks](./contracts/ci-checks.md).

## Prerequisites

- The repo set up as in `CLAUDE.md`: `fvm`, `uv`, Docker; `packages/content_models` built.
- The `FuelLesson` artboard and the panel drawings in `docs/design/` (drawn and exported on
  2026-10-28).
- For Part B: the Redmi Note 7 over adb (`adb reverse tcp:8000 tcp:8000` after each reconnect), and
  the release draft as a zip (`content/drafts/core-r1` from the `content-core-r1` worktree), with
  chapter 1's opening scene and `plays` added (the content hand-over in research). Without them, no
  scene plays in Part B.

## Part A: automated

Content kit (in `tools/content_kit`):

```bash
uv run wassal-content codegen --check
uv run wassal-content validate-source ../../content/examples/sample
uv run wassal-content golden
uv run wassal-content bundle dev --check --out ../../apps/mobile/assets/content/dev
uv run ruff check . && uv run mypy . && uv run pytest --cov --cov-fail-under=80
```

Backend (in `backend`, stack up):

```bash
uv sync --reinstall-package wassal-content
uv run manage.py makemigrations --check --dry-run
uv run pytest -n 4 --cov --cov-fail-under=80
```

App (in `apps/mobile`):

```bash
fvm flutter pub get && fvm dart run build_runner build -d
fvm dart run drift_dev make-migrations        # once, after the v4 tables (commit its output)
fvm dart run tool/design/sync_assets.dart     # the panel and fuel art
fvm flutter analyze --fatal-infos
fvm flutter test --coverage --exclude-tags backend
fvm dart run tool/check_coverage.dart --min 80
fvm flutter test integration_test/first_session_test.dart -d flutter-tester   # headless; no Linux runner
```

Expected: everything passes, including:

- the v3 → v4 migration test;
- the four artboards' goldens and layout tests;
- the compact size tests at 360×640 and 360×720;
- the coached player on the tutorial fixture;
- the guards in contracts/ci-checks.md.

`sync-e2e` (stack up, seeded):
`WASSAL_E2E_API=http://localhost:8000 fvm flutter test --tags backend test/backend`. Both operations
reach the server, and a filtered name comes back refused.

To compare by eye:
`fvm flutter test test/design test/goldens/design --dart-define=DESIGN_COMPARE=true`, then attach
`build/design_compare/{Intro,Name,Tutorial,FuelLesson}_*.png` to the PR.

## Part B: on a device

Setup for the real tutorial. A dev build bundles only the sample (`bundle dev` refuses any other
layout), so the draft arrives through M04's updater:

1. Start the local stack.
2. Import the draft as a zip in the dev admin (`content_import`, `docs/runbooks/content-publishing.md`)
   and publish it.
3. Install a fresh dev build (`fvm flutter run --flavor dev`), or clear its data, with the network on
   (on a phone, `adb reverse tcp:8000 tcp:8000` first).
4. Play the opening: it comes from the bundled sample (the draft's is the same three panels) while
   the draft downloads. On the Name card, wait until the debug status shows the new pack, then tap
   «تمام». The pack switches there, so trip 1 and the rest of the tutorial are the draft's
   (research R3).
5. Turn airplane mode on for steps 1–8.

Steps marked "sample" use a fresh dev install with the network off, so the bundled sample stays
active.

| # | Steps | Expected |
| --- | --- | --- |
| 1 | Sample: fresh install, airplane mode on. Open, tap «يلا» three times, then «تمام». Time it. Then uninstall and do the setup above. | Opening scene, then the Name card with a suggested name, then trip 1. Under 20 s from tapping the icon (SC-001). |
| 2 | Trip 1. | When the first fare lands, the screen dims around the tray and بلية says «شايف؟ الأجرة وصلت الدرج». A tap anywhere ends it. Boosters show the locked bar. |
| 3 | Finish, «كمّل», trip 2. When the 10-pound fare arrives, tap outside the hole, then on «١» three times, then on the rider. | Outside: nothing. The line names ٣ and the pound coin; the hole moves to the rider; the change goes; the step ends. |
| 4 | Trip 3. | When the countdown shows for the rider owed change, «نازل {station}…» names the real station, then the coins and the rider. Then, after the result, the سلمى scene plays once. |
| 5 | Kill the app on trip 3's result screen, before «كمّل». Reopen. | Home, then the سلمى scene at once (it was due). |
| 6 | Trip 4. | The sleeper's step: tap him, he wakes. |
| 7 | Result, «كمّل». | المعلم's fuel lesson; the gauge fills; «يلا على المشوار» starts trip 5 with a full tank. |
| 8 | Finish trip 5, «كمّل». | Home. Start any trip: no coach, boosters back. Replay trip 2: no coach. |
| 9 | Airplane mode off. Check the dev admin. | The player's name is the one chosen; one tutorial grant; the wallet's fuel matches. |
| 10 | Sample. In the dev admin, add a name to the name filter. Fresh install offline, type that name on the Name card, play trip 1, then go online and return to Home. | The Name sheet opens with «الاسم ده مينفعش…» and a new suggestion; no balance toast. Close it: the playtest Home shows «الأسطى»; the sheet comes back next launch. |
| 11 | Reinstall (Google backup on), network on, open. | Loading waits ≤ 3 s, then Home with the old name and progress: no opening scene (M06's restore). |
| 12 | Same, network off; on the Name card, turn the network on. | When the progress arrives, the Name card closes and Home shows the restored name. |
| 13 | Accessibility: TalkBack on, trip 2. | «بلية: …» is read when the step starts; focus lands on the coin cell; nothing else can be focused. |
| 14 | Reduced motion (Android "Remove animations"). | No ring pulse, no hand bob; the opening's panels fade. |
| 15 | A 360×640 emulator (or `wm size 1080x1920` on the phone at 480 dpi). Play a `line_gamaa` trip from the playtest list. | The compact arrangement: faces readable, controls at the bottom, the title in the pause card. |
| 16 | Sample: fresh dev install offline. | A three-trip tutorial (the sample's `line_hay.03` is a story trip); the سلمى scene after it; no fuel lesson unless the tank runs dry. |
| 17 | Staging build (once a release pack is bundled): the playtest «Onboarding» card. | Each first-session screen opens on demand; "coach everywhere" coaches every tutorial trip. Absent on a prod build. |

## Done when

- [ ] Part A passes, in CI too.
- [ ] Part B steps 1–15 pass on the Redmi Note 7, with the draft imported.
- [ ] The owner approved the coach lines, the fuel lesson's lines, the name pool, the refused line and
  the default name, and the compact look from the 360×640 goldens (owner-actions.md).
- [X] The `FuelLesson` artboard and the panel drawings are in `docs/design/`, and their goldens are
  reviewed side by side.
- [ ] After merge: SC-001 timed on the Galaxy A06; the moderated playtest (SC-007).
- [ ] The documents in research R23 are updated.
