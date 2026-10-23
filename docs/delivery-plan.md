# Delivery Plan: building the MVP with Spec Kit

| Field | Value |
| --- | --- |
| Scope | Phase 1, the MVP (Egypt, Android): 27 features in 13 steps |
| Order from | Joint MVP sequence in `docs/architecture-backend.md` §21; feature tables in backend §20 and mobile §23; step 5.5 added on 2026-10-23 for the new design |
| Rules | [`.specify/memory/constitution.md`](../.specify/memory/constitution.md) |
| Design | [`docs/design/`](design/README.md): Style C «كرتون ناعم», for every screen from step 5.5 on |
| Updated | 2026-10-23 |

This plan sets the order we build the game in and the Spec Kit routine every feature goes through.
Tick features off in [Progress](#progress) as they merge.

## Before the first feature

- [x] Merge `chore/project-setup` into `master`. Every feature branch is cut from `master`.

## The routine for every feature

1. **Start from an up-to-date `master`** (`git switch master && git pull`). `/speckit-specify` cuts the
   new branch from wherever you are, so starting on another feature branch stacks the two features.
2. **`/speckit-specify`** with the feature ID, its short name, the scope, and the source sections listed
   under its step. The git extension creates the branch, Spec Kit writes `specs/<spec>/spec.md`, and
   that spec becomes the active feature. A mobile feature with screens also names its artboards
   from [Design sources](#design-sources). Example:

   ```text
   /speckit-specify M08 Home, pre-trip card, result screen (short name: m08-home-result).
   Sources: docs/ux-spec.md «الموقف», «كارت ما قبل المشوار», «شاشة النتيجة»;
   docs/design/HANDOFF.md §11 C-Home, HomeStates, PreTrip, Result, ShareCard, with
   docs/design/README.md; docs/architecture-mobile.md §9.
   ```

3. **`/speckit-clarify`**: answer up to 5 questions. The answers are written into the spec.
4. **`/speckit-plan`**: give it both architecture docs, and for a mobile feature with screens,
   `docs/design/HANDOFF.md` and `docs/design/README.md`.
   - It writes `plan.md`, `research.md`, `data-model.md`, `contracts/` and `quickstart.md`, and runs
     the Constitution Check.
   - Every **NEEDS CLARIFICATION** item the feature touches must be resolved in `research.md`. Each
     step below lists them.
5. **`/speckit-checklist`** (optional): for example accessibility for screens, or security for auth
   and purchases.
6. **`/speckit-tasks`**: writes `tasks.md`. Test tasks are always included (constitution XIII).
7. **`/speckit-analyze`**: fix every CRITICAL finding before implementing. Constitution violations are
   always CRITICAL.
8. **`/speckit-implement`**: tests first. If it leaves gaps, run `/speckit-converge`. What the feature
   needs from you (accounts, devices, live checks) is added to [owner-actions.md](owner-actions.md).
9. **Review and merge.**
   - CI gates are green.
   - For each artboard the feature builds, the PR shows its golden next to
     `docs/design/png/<Artboard>.png` (HANDOFF §10).
   - The feature's "Before merge" items in [owner-actions.md](owner-actions.md) are done.
   - The code is reviewed, with a security review for changes to auth, purchases, the ledger, sync,
     webhooks or personal data.
   - The PR is merged into `master`. Then start the next feature.

From step 3 onward, the `feature-branch` extension checks out the active feature's branch before each
command, or creates it if it is missing. If your local changes block the switch, the command stops.
Commit or stash, then rerun it.

## Conventions

**Spec numbers and names.** Spec numbers are assigned in the order you run `/speckit-specify`.
The numbers below assume you follow this plan; if you don't, the numbers shift but the feature IDs
stay the same. Put the feature ID in the short name, so the folder, the branch and the ID line up:
`001-m03-app-shell`.

**008.5 is the one spec number that isn't a whole number.** It was added between 008 and 009 after
both were numbered, so the later numbers stay as they are. The scripts only generate whole numbers,
so give `/speckit-specify` both names explicitly (see [Step 5.5](#step-55-the-new-design)):
`GIT_BRANCH_NAME=008.5-m21-design-refresh` and
`SPECIFY_FEATURE_DIRECTORY=specs/008.5-m21-design-refresh`. The next generated number is still 009,
because the number scan ignores `008.5-`.

**One active feature at a time.** The active feature is the one `.specify/feature.json` points to,
which is the one you specified last. To return to another feature, ask Claude to make
`specs/<spec>` the active feature. The next command then checks out its branch.

**In a pair, the owner of the shared artifact goes first.** The consumer is specified after the
owner merges, so its branch already contains the artifact.

| Shared artifact | Owner (merges first) | Consumers |
| --- | --- | --- |
| `content/schemas/*.json` | B04 | M01, M04, B05 |
| `fixtures/parity/*.json` | M01 (writes the first fixtures) | B05 (must reproduce them exactly) |
| `contracts/openapi.yaml` | The backend feature of the pair | The mobile feature of the pair |

If a feature changes the Shared Contract Glossary (§3), it edits both architecture docs in the same PR.

### Design sources

From step 5.5 on, every screen is built from [`docs/design/`](design/README.md): Style C,
«كرتون ناعم», which replaced «ستيكر الميكروباص» on 2026-10-23. Read the folder's README first, because
its project overrides win over HANDOFF.md. Animation stays on Rive, identifiers come from the
glossary, and merged decisions win on behaviour.

- **Build** with the tokens and components 008.5 makes (HANDOFF §2, §3). Never restyle raw widgets.
- **Test** each artboard with a golden at 390×844 and a layout test against
  `docs/design/boxes/<Artboard>.json` (±2 px), in RTL with both digit styles (HANDOFF §10).
- **Resolve** the open questions from HANDOFF §9.3 in the feature named below, in its `research.md`.

| Feature | Artboards (HANDOFF §11) | From HANDOFF §9.3 |
| --- | --- | --- |
| 008.5 M21 | `Tokens`, `Components`, `Characters`, `Passengers`, `Vehicles` (as Rive art), `Loading`, `C-Trip`, `TripEvents`, `StoryTrip`, `Pause`, `Fail`, `States` 9–10 (empty, loading) | #5 ledger badge 5 s against the 10 s booster |
| B03 | none | #8 the comeback-gift and family-request grants (no op yet); longest streak and trip count |
| M06 | `States` 1, 7, 8 (offline, update required, maintenance) | none |
| Before M07 | none | #4 routing money around أبو سمّاعة. If yes, it is a rules change: `RULES.md`, both engines and fixtures in one PR (constitution III), before M07 teaches it and M08's PreTrip mentions it. |
| M07 | `Intro`, `Name`, `Tutorial` | #3 the coach line of each tutorial trip |
| M08 | `C-Home`, `HomeStates`, `PreTrip`, `Result`, `ShareCard` | none |
| M09 | `Lines`, `LineDetails`, `BuyVehicle` | none |
| M10 | `AptGoal`, `AptGoalReady`, `AptRooms`, `RoomDone`, `Piece`, `SceneViewer`, `Album`, `Chapters`, `Requests` | #2 when the Apartment tab opens |
| B10 | none | #8 a maintenance end time in the 503 response |
| M11 | `States` 2–3 (ad not ready, daily ad limit), `RewardedAdButton` | none |
| M12 | `Shop`, `Fuel`, `PurchaseDone`, `States` 4–6 (spend confirmation, undo toast, payment failed) | none |
| B08 | none | #8 the `trip_id` scheme for daily-challenge trips |
| M13 | `Daily`, `Tasks`, `Challenge`, `Returning` | #6 the day-7 sticker before cosmetics exist |
| M14 | `Settings`, `DeleteStep1`, `DeleteAccount`, `NotifAsk` | #7 hiding the «ملك الخط» switch until leagues |
| M16, M17 (phase 2) | `Garage`, `Starter` | none |
| M18, M19, M20 (phase 3) | `King`, `Event`, `Invite` | #8 the `trip_id` scheme for event trips (B14) |

HANDOFF §9.3 #1 is already settled: `RULES.md` §6.1 rounds a student's fare up to the next 50
piasters. HANDOFF §9.2's undrawn states for later phases (the Garage cosmetics tab, Event with the
pass owned, the Invite redeem code) are designed before those phases start.

## The MVP sequence

| Step | Specs | What you have after this step |
| --- | --- | --- |
| 1 | 001 M03 · 002 B01 | An empty app and an empty API, both running in CI |
| 2 | 003 B04 · 004 M01 | The trip engine and the schemas it reads |
| 3 | 005 B05 | The Python mirror; every trip proven 3-star solvable |
| 4 | 006 M04 · 007 M05 | The bundled pack loads; local wallet, ledger and fuel |
| 5 | 008 M02 | **The first playable trip, fully offline** |
| 5.5 | 008.5 M21 | Everything built so far in the new design, with the Rive art in its style |
| 6 | 009 B02 · 010 B03 · 011 M06 | Server-backed accounts and wallet |
| 7 | 012 M07 · 013 M08 · 014 M09 · 015 M10 | The full game loop |
| 8 | 016 B10 · 017 B07 · 018 M11 | Rewarded ads and interstitials |
| 9 | 019 B06 · 020 M12 | Real-money purchases |
| 10 | 021 B08 · 022 M13 | The daily return loop |
| 11 | 023 B09 · 024 B11 · 025 M14 | Store compliance |
| 12 | 026 M15 | Measuring the launch KPIs |

### Step 1: Foundations

| Spec | ID | Feature | Depends on | Specify from |
| --- | --- | --- | --- | --- |
| `001-m03-app-shell` | M03 | App shell: routing, theme tokens, l10n/RTL, digit setting | — | ux-spec «النظام البصري», «خريطة الشاشات والتنقل»; mobile §5, §6, §9, §21 |
| `002-b01-backend-skeleton` | B01 | Project skeleton: Django settings, Docker Compose, Caddy, CI/CD, Sentry, health checks | — | backend §2, §4, §5, §15 |

- **Resolve:** mobile §24.1 (Android `minSdk` and iOS minimum) and §24.2 (reference device: Galaxy
  A06) in M03; backend §22.1 (OCI free-tier capacity, or the paid fallback) in B01.
- **Also in M03:**
  - Pin Flutter with FVM, and set up mobile CI on GitHub Actions.
  - Add a `ConfigSource` with bundled defaults, so tunables (constitution VIII) work before Firebase
    is wired up in M15.
- **Decided in B01** (spec Clarifications): staging and production go live on the real host. Until
  there is a real domain, they use temporary hostnames derived from the host's IP (sslip.io style).
  Register the real domain and switch to it before the first closed test, whether that is the step 7
  option or step 12. B09's account-deletion page needs the real domain too. The switch is
  configuration: the hostnames in `/etc/wassal/edge.env` and each environment's `API_HOST` and
  `ADMIN_HOST` (B01 FR-042a). Since M04 it is also an app release: edit the staging and prod API
  addresses in `apps/mobile/lib/core/network/api_environment.dart`. A build that has shipped keeps
  calling its old host until the next app release.
- **Done when:**
  - The app launches in RTL with the theme tokens and both digit settings, and its goldens run in CI.
  - The API answers `/healthz` behind Caddy on the ARM64 Compose stack.
  - CI is green on both sides.
  - The real build, lint and test commands are added to `CLAUDE.md`.

### Step 2: The engine and its schemas

| Spec | ID | Feature | Depends on | Specify from |
| --- | --- | --- | --- | --- |
| `003-b04-content-pipeline` | B04 | Content pipeline: schemas, authoring admin, pack build and publish, manifest, model codegen | B01 | backend §9; mobile §14 |
| `004-m01-trip-engine` | M01 | `trip_engine`: rules, commands, events, determinism | B04 schemas | product-spec «ميكانيكيات المشوار», «أنواع الركاب», «الأحداث والمواقف»; ux-spec «شاشة المشوار»; mobile §7 |

- **Order inside B04:** make the schemas and model codegen B04's first user story. Merge that slice
  in its own PR as soon as it is green, so M01 can start while the admin and the pack build continue.
- **Resolve:**
  - ~~backend §22.3 (a CDN in front of content packs) in B04~~ **resolved in B04:** no CDN for the
    MVP; each host's edge serves its own immutable pack files, and Cloudflare later is configuration
    (research R5);
  - ~~mobile §24.4 (resume or restart when the app is killed mid-trip) in M01~~ **resolved in M01:**
    the trip resumes exactly, rebuilt from its replay record, so the engine needs no snapshot
    format and fuel is untouched (research R10).
- **Handed over from B01** (`specs/002-b01-backend-skeleton/research.md`, "Handed to later
  features"): in B04, keep content packs and their CDN separate from the Backblaze B2 backup
  buckets, and never reuse the backup keys.
- ~~**Handed over from M03** (research, "Handed to later features"): in M01, settle the tunable
  `trip_hints_enabled_line_gamaa`. The ux-spec's "first time per passenger type" hint mode needs an
  enum, not the boolean M03 ships.~~ **Settled in M01** (research R12): the five keys became
  `trip_hints_mode_<line_id>` (`off`, `first_time`, `always`), with `first_time` for `line_gamaa`.
  Mobile §14.3 is updated; the backend's copy arrives with B10 (research R19).
- **Done when:**
  - `trip.schema.json` and the generated models are on `master`.
  - Replaying `(definition, seed, params, command_log)` gives an identical `TripResult`.
  - The engine has ≥ 90% line coverage.
  - The first parity fixtures are in `fixtures/parity/`.

### Step 3: Parity

| Spec | ID | Feature | Depends on | Specify from |
| --- | --- | --- | --- | --- |
| `005-b05-solver-parity` | B05 | Solver and simulator, difficulty scoring, parity fixtures in CI | B04, M01 fixtures | backend §10; mobile §7.10 |

- **Resolve:** nothing open.
- **Done when:**
  - pytest reproduces every M01 fixture exactly, and CI fails on any mismatch.
  - Every authored trip is proven 3-star solvable before it is published.

### Step 4: Content and the local economy on the device

| Spec | ID | Feature | Depends on | Specify from |
| --- | --- | --- | --- | --- |
| `006-m04-content-loader` | M04 | Content pack loader, bundled pack, models from schemas | M03, B04 | mobile §14; backend §9 |
| `007-m05-local-economy` | M05 | Local persistence (drift), economy service, fuel | M03 | mobile §11, §13; product-spec «الاقتصاد» |

- **Resolved in M05:** mobile §24.5. Every trip start costs a liter, replays of completed trips
  included (M05 research R20). B03 must agree with the answer.
- **Handed over from M05** (research "Handed to later features"):
  - M02 starts trips, records results, and buys and uses boosters and revives through the economy,
    with one request id per player intent. It charges a revive only when the engine reports the
    trip revivable and below the command cap (M01 research R9). On a launch with an unfinished
    start, it rebuilds that trip from its replay record, or records it abandoned if the record is
    gone.
  - M06 sends the pending operations in `seq` order (`pendingOps`), applies each answer
    (`markAccepted`, `markRejected`), replaces the base with the server's snapshot (`replaceBase`)
    and anchors trusted time on the server's (`anchorOnServer`). It revisits the backup exclusion
    with backend §22.6. M05's review asks it to move those calls to a sync-only interface that
    screens don't get, and to queue lifecycle resyncs behind requests.
  - M07: the tutorial's gift refill needs an operation type that B03 accepts.
  - M08 and M12 draw countdowns from `nextLiterAtMs` and the trusted clock. M12 applies a small
    BONAT purchase only after its 3-second undo window (ux-spec «الشرا»).
  - M09 and M10 check unlock order before calling `buy`.
  - M11 adds the daily ad caps and the ad calls.
  - M13 adds `fuel_mode: challenge` for the first daily-challenge attempt.
  - M14 and phase 3: the iOS backup exclusion (`NSURLIsExcludedFromBackupKey`) and an iOS
    `UptimeSource`.
  - M15 reports the refusal codes and `write_failed`.
  - M17 gives subscribers the larger tank (`fuel_max_subscriber`) through the cached entitlements.
  - B03 confirms the fuel rules (backend §7.5), the reasons `chapter_purchase` and
    `fuel_unlimited_purchase`, the revive's `ref`, `chapter` ownership, and fuel for replays.
- **Handed over from M03** (research R1): in M05, use drift with the native-assets `sqlite3` 3.x
  package. Don't add `sqlite3_flutter_libs`, which is end-of-life.
- **Handed over from M04** (research "Handed to later features"):
  - M02 reads trips and speech pools through `contentSourceProvider`, and records the active content
    version when a trip starts, so the result declares the version it was played with.
  - M02: `lib/core/glossary/ids.dart`'s `LineId` and `VehicleId` share their names with the enums
    `content_models` generates. A file that imports both needs an import prefix, or M02 retires the
    glossary copies.
  - M05 reads catalog prices through the content source, and declares the active version in ledger
    operations. `state.json` may move into the `content_cache` table. Progress may name a trip the
    active pack doesn't have (after a fallback to the bundled pack): readers skip it rather than fail.
  - M06 calls `ContentUpdater.check(force: true)` when bootstrap reports a newer `content.version`,
    and adds the player token through the shared HTTP factory once B02 makes the manifest require it.
- **Done when:**
  - The app loads the bundled pack and verifies its sha256.
  - The wallet, `ledger_ops` and fuel regeneration all work offline.
  - No float holds money anywhere.

### Step 5: The first playable trip

| Spec | ID | Feature | Depends on | Specify from |
| --- | --- | --- | --- | --- |
| `008-m02-trip-screen` | M02 | Trip screen: Flame scene, Rive characters, HUD, dashboard, overlays | M01, M04 | ux-spec «شاشة المشوار», «أثناء المشوار: الأحداث والنوافذ»; mobile §8 |

- **Resolve:**
  - mobile §24.6: choose the Rive runtime and confirm its licensing;
  - mobile §24.4: design the UI side of the resume policy.
- ~~**Handed over from M01** (research R9): `Revive` is refused with `command_limit` once a trip has
  1,200 accepted commands, while `Abandon` is always accepted. Hide the revive offer at the cap
  (`TripState.commandsAccepted`), so no ad or booster is spent on a refused revive.~~ Done in M02:
  the failure card offers no revive at the cap (`fail_summary.dart`).
- **Resolved in M02:** mobile §24.6 (research R1) and the UI side of mobile §24.4 (research R8).
  The hand-overs it took: M05's (starts, results, boosters and revives through the economy, one
  request id per intent, the rebuild at launch), M04's (trips and speech pools through
  `contentSourceProvider`, the active version recorded at the start) and M03's pause control, which
  constitution 1.4.0 places in the top bar.
- **Done when:**
  - A trip from the bundled pack plays from start to finish with no network.
  - The minimum sizes pass in RTL goldens.
  - The scene holds ≥ 45 fps on the reference device (the Galaxy A06, chosen in M03 for mobile §24.2).
- **Milestone:** the first internal test of "is the puzzle fun?".

### Step 5.5: The new design

| Spec | ID | Feature | Depends on | Specify from |
| --- | --- | --- | --- | --- |
| `008.5-m21-design-refresh` | M21 | Design refresh: the «كرتون ناعم» design applied to everything built so far | M02, M03 | `docs/design/README.md`; HANDOFF §0–§10 and the §11 sections of the 008.5 artboards in [Design sources](#design-sources); mobile §8, §9; M02's `research.md` R3, R15 and `contracts/rive-character.md` |

The design changed after M02 was built. This step moves what exists to the new design, so every
feature from 009 on starts from the new tokens and components, with nothing left to restyle later.

```text
/speckit-specify M21 Design refresh (short name: m21-design-refresh).
GIT_BRANCH_NAME=008.5-m21-design-refresh SPECIFY_FEATURE_DIRECTORY=specs/008.5-m21-design-refresh.
Move everything built so far to the «كرتون ناعم» design in docs/design: tokens, components, the
shell, the boot screen and the trip screen, with the owner's Rive files in the new style.
Sources: docs/design/README.md (its overrides win), docs/design/HANDOFF.md §0–§10 and §11 Loading,
C-Trip, TripEvents, StoryTrip, Pause, Fail, States; docs/architecture-mobile.md §8, §9.
Out of scope: screens owned by later features; any rule, economy or schema change.
```

- **In scope:**
  - **Tokens.** Generate the theme tokens from `docs/design/tokens.json` (HANDOFF §2), and have CI
    fail when the generated tokens and the JSON differ, as `codegen --check` does for content.
    Marhey and Readex Pro replace Lalezar and Baloo Bhaijaan 2. The palette and contrast tests
    follow the new palette.
  - **Components.** HANDOFF §3's component set replaces M03's sticker components. A gallery
    reproduces the `Components` and `Tokens` boards. Lips, the press state and the motion follow
    HANDOFF §2.3 and §6.5, with no Material ripples.
  - **What M03 built.** The white `BottomNav`, the placeholder screens, the boot screen as
    `Loading`, the digit-style setting in the `Settings` look, and sheets and dialogs.
  - **What M02 built.** `TripHud` and `StationStrip`; the scene, its cabin and its seat positions
    (HANDOFF §4); the overlays and the dashboard (§3.4); the events (`TripEvents`); the story strip
    (`StoryTrip`); `Pause` and `Fail`; بلية's hints as character bubbles. The playtest tools change
    only where they use shared components.
  - **Rive art in the new style**, from the owner's files (below). Passengers get HANDOFF §5.4's
    states. The characters ride in trips (بلية, أبو العروسة in story trips). `Loading` gets its
    animation. A new character contract replaces M02's `contracts/rive-character.md`, and
    `passenger.riv` is retired.
  - **Tests.** Goldens at 390×844 shown next to `docs/design/png/<Artboard>.png`, and layout tests
    against `docs/design/boxes/<Artboard>.json`, for every artboard in scope.
- **Out of scope:** screens owned by later features (see [Design sources](#design-sources)). They
  are built in the new design by their own features. No rule, engine, economy or content-schema
  change.
- **Not taken from the handoff** (`docs/design/README.md`, "Project overrides"):
  - Lottie. The constitution locks Rive for characters, so `lottie/` is a motion reference only.
  - Its art names as identifiers. The glossary keeps `micro_old` and the archetype names.
- **Resolve:**
  - **The scene geometry.** HANDOFF §4 draws a 390×444 scene scaled to the width, and crops the
    cabin's top below 420. M02 measures the scene in points with no fixed resolution (research R3),
    and keeps every minimum from 744 pt of height (R15). Settle it in `SceneLayout`, with every minimum
    down to the A06's 360×800. Shorter screens keep M02's approved exception to constitution XI until
    M07 (decided in 008.5's clarification).
  - **Text scale.** HANDOFF §2.2 allows 1.3×, clamped to 1.15× in the HUD, the dashboard and the
    station tags. Reconcile it with M02 research R15.
  - **Skins.** Decide how `skin` slugs map to the Rive looks (HANDOFF §5.3): rename the sample
    pack's skins, which changes its golden checksums, or map the slugs in the app.
  - **Station colours.** HANDOFF §1 assigns them by a station's order on the line. The ux-spec and
    M02 assign them by alighting order in the trip, which has at most 4 stops while a line can have
    more. Keep the trip's order unless the clarification decides otherwise.
  - ~~**The ledger badge** (HANDOFF §9.3 #5).~~ **Decided in 008.5's clarification:** the badges
    last the whole peek, `booster_ledger_peek_ms` (10 s), with no separate 5-second timer.
  - **The new Rive files' performance.** Measure on the A06 under HANDOFF §6.4's load (12 animated
    passengers, 2 bubbles, 3 notes in flight). Record the p90 frame time against its 16 ms target,
    and the fallback step used, if any.
- **Owner, before 008.5 merges (so before 009 starts):** the Rive files in the new style, made to
  008.5's character contract. Plan 008.5 first, because the files are made to that contract. They are
  exported from Rive's free plan (the owner's decision of 2026-10-23, 008.5 research R15).
  - The passenger looks of the MVP lines (HANDOFF §5.3: الحي and الجامعة, plus `regular_customer`
    and `honest`).
  - The six characters (§5.2).
  - The two MVP vehicles (`tuktuk`, `micro_old`, drawn as `microbus_old`).
  - The UI animations of §6.3.

  008.5 itself uses the passengers, the characters that ride in trips, and `splash_drive`. The rest
  wait for the features that show them.
- **Done when:**
  - `tokens.json` is the only source of colours, type, radii, lips and motion values, and CI fails
    when the generated tokens differ from it.
  - The gallery matches the `Components` and `Tokens` boards.
  - Every artboard in scope has a golden next to its PNG and a passing layout test, in RTL with both
    digit styles.
  - The trip plays as before, in the new design and with the owner's Rive files: M02's tests and the
    parity-fixture playthroughs still pass.
  - The minimum sizes pass, and so does M02's A06 gate (≥ 45 fps, memory under 300 MB) under HANDOFF
    §6.4's load.
  - Nothing in `lib/` uses Lalezar, Baloo Bhaijaan 2, the sticker components or `passenger.riv`.

### Step 6: Accounts and sync

| Spec | ID | Feature | Depends on | Specify from |
| --- | --- | --- | --- | --- |
| `009-b02-accounts-auth` | B02 | Accounts and auth: anonymous accounts, refresh rotation, Google/Apple linking and conflicts | B01 | backend §6, §13 |
| `010-b03-ledger-sync` | B03 | Economy ledger, bootstrap, state, sync engine, op validators, fuel reconciliation, flags | B02, B04 | backend §7, §12 |
| `011-m06-identity-sync` | M06 | Identity, bootstrap, sync queue | M05, B02, B03 | mobile §12, §16; design `States` 1, 7, 8 |

- **Resolve:**
  - backend §22.6 (a re-install without a linked provider creates a new player) in B02 and M06;
  - backend §22.2 (the game-day timezone) in B03;
  - confirm that B03 matches the M05 answer to mobile §24.5;
  - from the design (HANDOFF §9.3 #8), in B03: how the comeback gift (`Returning`) and the
    family-request rewards (`Requests`) are granted, since no operation does it yet, and where the
    longest streak and the trip count come from.
- **Handed over from B01** (`specs/002-b01-backend-skeleton/research.md`, "Handed to later
  features"):
  - B02: `accounts.User` is staff-only, so decide how `Player` authenticates with simplejwt (B01
    research R3).
  - B02: per-player throttles replace the per-address default for authenticated traffic. Mind
    carrier-grade NAT: many Egyptian mobile players share one address (B01 research R4).
  - B03: register the `economy.wallet_equals_ledger` invariant with the restore drill's registry
    (`apps/common/services/invariants.py`), and add the direct-`Wallet`-write scan to CI.
- **Done when:**
  - The first online launch creates an anonymous account in the background.
  - Offline trips sync without duplicates.
  - `wallet == sum(ledger)` and idempotency are covered by property tests.
  - The stale-state path (`GET /v1/state`) works.

### Step 7: The full game loop

| Spec | ID | Feature | Depends on | Specify from |
| --- | --- | --- | --- | --- |
| `012-m07-onboarding` | M07 | Onboarding and tutorial overlays (5 tutorial trips) | M02 | ux-spec «البداية وأول جلسة»; product-spec «تجربة المستخدم» (أول جلسة); design `Intro`, `Name`, `Tutorial` |
| `013-m08-home-result` | M08 | Home, pre-trip card, result screen | M02, M05 | ux-spec «الموقف», «كارت ما قبل المشوار», «شاشة النتيجة»; design `C-Home`, `HomeStates`, `PreTrip`, `Result`, `ShareCard` |
| `014-m09-lines-vehicles` | M09 | Lines map, line detail, vehicle purchase | M05 | ux-spec «الخطوط والعربية والجراج»; product-spec «التقدم: الخطوط والعربيات»; design `Lines`, `LineDetails`, `BuyVehicle` |
| `015-m10-apartment-story` | M10 | Apartment ch1–4, item sheet, family requests, chapters, story viewer | M05 | ux-spec «الشقة والقصة»; product-spec «القصة والميتا»; design `AptGoal`, `AptGoalReady`, `AptRooms`, `RoomDone`, `Piece`, `SceneViewer`, `Album`, `Chapters`, `Requests` |

- **Resolve:**
  - nothing open in the architecture docs;
  - from the design (HANDOFF §9.3): before M07, whether money can be passed around a muted
    أبو سمّاعة through the neighbouring seat (#4; the engine blocks it today). If yes, it is a rules
    change with its parity fixtures (constitution III), in its own PR. In M07, each tutorial trip's
    coach line (#3). In M10, when the Apartment tab opens (#2: the ux-spec locks it in chapters
    1–2, the design shows the goal from the start).
- **Handed over from M02** (research "Handed to later features"):
  - M07: a trip layout for screens under 744 pt in which faces keep their 50/80 pt minimums, with
    goldens at 360×640. It ends M02's approved exception to constitution XI (Complexity Tracking in
    `specs/008-m02-trip-screen/plan.md`); 008.5 left it to M07, on the design's taller bands. M07 also
    reuses بلية's hint bubble for the tutorial, as the design's `CoachMark` (HANDOFF §3.3).
- **Handed over from M21** (`specs/008.5-m21-design-refresh/contracts/trip-layout.md` "Height"):
  - M07: with the new design's 114 pt HUD and 258 pt dashboard, a screen keeps every minimum from
    `inset + 764` pt of height (788 pt with a 24 pt inset), not M02's 744. Below it the exception
    continues. M07's short-screen layout aims for the 360×640 surface: the trip goldens at 360×640
    (`test/goldens/trip/`, surface `small`) are the ones to bring within the minimums.
- **Handed over from M02**, continued:
  - M08: the result screen replaces M02's placeholder and reads the `TripResult` from the route's
    `extra` (or the economy's `lastResult`); Home replaces the playtest trip list.
- **Done when:**
  - From first open, the first trip starts in under 20 s.
  - The five tutorial trips, home, results, line progress, vehicle purchase and apartment items all
    work offline.
  - The integration test from onboarding through the first 5 trips passes.
- **Option:** the closed test (50–100 players) could start here. Its KPI, 80% of new players
  finishing the first session, needs analytics, so pull M15 forward if you take this route.

### Step 8: Ads

| Spec | ID | Feature | Depends on | Specify from |
| --- | --- | --- | --- | --- |
| `016-b10-catalog-offers` | B10 | Live-ops catalog and offers: store product grants, offer eligibility, live settings | B03 | backend §8, §11 |
| `017-b07-ads-ssv` | B07 | Ads: AdMob SSV callback, reward polling, caps | B03 | backend §8 |
| `018-m11-ads` | M11 | Ads integration: rewarded, interstitial, consent | M05, B07 | mobile §15.1; product-spec «تحقيق الدخل» (أماكن الإعلانات); design `States` 2–3, `RewardedAdButton` |

- **Resolve:**
  - backend §22.10 (BONAT pack amounts) in B10;
  - in B10, a maintenance end time in the 503 response, which the design's maintenance state shows
    (HANDOFF §9.3 #8);
  - in M11: mobile §24.3 (which mediation networks) and backend §22.8 (the age rating, which sets the
    ad content rating).
- **Handed over from M01** (research R19): in B10, create `liveops.LiveSetting` with every key in
  `apps/mobile/assets/config/tunables.json`, including M01's 20 new keys and
  `trip_hints_mode_<line_id>`. This ends M01's approved exception to constitution VIII (Complexity
  Tracking in `specs/004-m01-trip-engine/plan.md`).
- **Done when:**
  - Every placement in Glossary §3.4 works, with its caps enforced on the device and on the server.
  - No ad call is ever made while a trip is running.
  - `morning_piggy` is granted only through SSV.
  - UMP consent is collected before the first ad request.

### Step 9: Purchases

| Spec | ID | Feature | Depends on | Specify from |
| --- | --- | --- | --- | --- |
| `019-b06-purchases` | B06 | Purchases: verify, Google RTDN, voided purchases, entitlements | B03, B10 | backend §8 |
| `020-m12-shop-iap` | M12 | Shop, IAP, fuel sheet | M05, M06, B06 | mobile §15.2; ux-spec «المحل والبنزين والدفع»; design `Shop`, `Fuel`, `PurchaseDone`, `States` 4–6 |

- **Resolve:** backend §22.5 (refunds of BONAT that was already spent) in B06. Backend §22.4 (the iOS
  purchase payload) waits for phase 3.
- **Done when:**
  - BONAT packs and `remove_ads` can be bought, verified and granted end to end.
  - The store transaction is acknowledged only after the server returns `acknowledge: true`.
  - Restore purchases works.
  - Recorded RTDN payloads, both valid and tampered, pass their tests.

### Step 10: The daily return loop

| Spec | ID | Feature | Depends on | Specify from |
| --- | --- | --- | --- | --- |
| `021-b08-daily-challenge` | B08 | Daily challenge: generation, delivery, replay verification, rewards | B03, B05 | backend §11 |
| `022-m13-daily-loop` | M13 | Daily reward, tasks, daily challenge | M06, B08 | ux-spec «الرجوع اليومي»; product-spec «الاحتفاظ والتفاعل»; design `Daily`, `Tasks`, `Challenge`, `Returning` |

- **Resolve:**
  - backend §22.11 (the retry cost after the free first attempt);
  - from the design (HANDOFF §9.3): in B08, the `trip_id` scheme for daily-challenge trips (#8); in
    M13, the day-7 sticker, since cosmetics only arrive with the phase 2 garage (#6).
- **Handed over from B05** (`specs/005-b05-solver-parity/contracts/mirror.md` §4, "What the caller
  must do"): verify a run with `replay_untrusted` using the server's own definition and params for
  that trip and pack version, never the client's copies; cap the request body before reading it;
  and treat any exception other than `ReplayRefused` as an internal error.
- **Done when:**
  - Every player gets the same challenge each game day.
  - The solver verifies results by replay.
  - The first attempt is free.
  - The streak rules match the product spec.

### Step 11: Store compliance

| Spec | ID | Feature | Depends on | Specify from |
| --- | --- | --- | --- | --- |
| `023-b09-privacy-deletion` | B09 | Privacy: account deletion API and web page, Apple token revocation, data inventory | B02 | backend §14 |
| `024-b11-push` | B11 | Push: tokens, categories, campaigns, caps, quiet hours | B02 | backend §11 |
| `025-m14-settings-account` | M14 | Settings, account linking, deletion, notifications | M06, B09, B11 | ux-spec «الإعدادات والحساب والتواصل»; mobile §16; design `Settings`, `DeleteStep1`, `DeleteAccount`, `NotifAsk` |

- **Resolve:**
  - in B09, backend §22.9 (legal review, and how long purchase records are kept) and §22.8 (the
    age rating);
  - in M14, hiding the `Settings` artboard's «ملك الخط» notification switch until leagues launch
    (HANDOFF §9.3 #7).
- **Done when:**
  - Account deletion works both in the app and on the web page.
  - A linking conflict lets the player choose which progress to keep; accounts are never merged.
  - Players get at most 2 pushes a day.
  - The store data-safety answers match backend §14.2.

### Step 12: Measurement

| Spec | ID | Feature | Depends on | Specify from |
| --- | --- | --- | --- | --- |
| `026-m15-analytics-config` | M15 | Analytics taxonomy, Crashlytics, Remote Config wiring | M03 | mobile §17, §14.3 |

- **Done when:**
  - Every event in mobile §17 fires with its parameters.
  - Remote Config overrides the bundled defaults.
  - Crashlytics receives symbols from release builds.
- **Then:** the closed test, followed by the Android beta in Egypt.

## After the MVP

Each phase starts when the gate before it is met, not on a date (product-spec «خارطة الطريق»).

| Phase | Gate to start it | Features |
| --- | --- | --- |
| 2: content and revenue, plus KSA and UAE | Egypt beta: D1 retention ≥ 35% and D7 ≥ 13% | M16 garage; B12 + M17 subscription and starter pack; content packs for `line_souq`, `micro_new` and ch5 (built through B04) |
| 3: public launch and iOS | Gulf purchases cover the cost of acquiring players | B13 + M18 leagues; B14 + M19 seasonal events and season pass; B15 + M20 referral and share clips; Apple purchases and Sign in with Apple (B06 extension, backend §22.4); device attestation (backend §22.7); `line_masyaf`, `line_safar`, ch6–7 |
| 4: season 2 | Public launch: D30 retention ≥ 6% | No feature IDs yet. New saving goals after the wedding; line packs for other Arab countries (السرفيس, الكيا, الطاكسي الكبير); new seasonal lines; the backend's scale path step 2 if DAU requires it (backend §19) |

### Known gaps for later phases

No feature owns these yet, and the feature tables of the architecture docs (backend §20, mobile
§23) don't list them. Each needs a feature ID before its phase starts.

1. **Engine support for the later passenger types.** M01 refuses `money_changer`, `bags_lady` and
   `dodger` (`line_souq`, phase 2), and `mother_kids`, `big_family` and `traveler` (`line_masyaf`
   and `line_safar`, phase 3), until a feature adds their line (M01 spec FR-004). `line_safar`'s
   rest stop (استراحة الطريق) probably needs a new event too. Each type needs `RULES.md`, both
   engines, parity fixtures, `capabilities.json`, tunables, speech slots and its character.
2. **The garage's server side and schemas** (phase 2). M16 has no backend partner, and the catalog
   has no `upgrade` or `cosmetic` kind. Upgrades change play, so they become engine inputs that the
   replay and B03's result check must know about. Cosmetics cost BONAT, which only the server grants
   (constitution IV).
3. **Seasonal content** (phase 3). The schemas have no part for seasons (dates, the trips or
   modifiers that apply, rewards), and some seasons need new rules, such as Ramadan's countdown to
   maghrib. B14 and M19 own events, but this reaches into B04's pipeline.
4. **Phase 4 content.** Season 2 needs rooms and chapters that `RoomId`, `ChapterId` and the item id
   pattern don't allow yet. A new line needs a new `line_id` and its per-line tunables. Line packs
   for other countries need local currencies (the glossary, the engine and `Denomination` all assume
   Egyptian piasters) and a second pack beside `core`, which M04 doesn't read.

Every later content change also shares one constraint: art ships in the app, not in packs. Content
that needs new art waits for an app release, and its pack's minimum app version must be that
release.

### Planning phases 2 and 3

When the closed test starts (after step 7 or step 12), extend this plan with phase 2 and phase 3
sections in the same format as the MVP: steps, spec numbers, what to resolve, and when each step is
done. In the same PR, give each gap above a feature ID, and add those features to both architecture
docs: the feature tables (backend §20, mobile §23) and the phasing tables (backend §19, mobile §22).
It waits until then because the closed test and the beta will change prices, difficulty and
priorities.

## Progress

Tick a spec when its PR merges, and tick the step when all of its specs have merged.

- [x] Step 1: Foundations
  - [x] `001-m03-app-shell` (merged in #1, 2026-10-18). Resolved mobile §24.1 (Android `minSdk 24`,
    iOS 15.0) and §24.2 (Galaxy A06). Still to do on a real device: the manual quickstart
    scenarios (T091) and the A06 cold-start and white-frame checks (T092).
  - [x] `002-b01-backend-skeleton` (merged in #2, 2026-10-19). Staging and production run on
    separate VMs (constitution v1.1.0). Staging deploys from `master`.
- [ ] Step 2: The engine and its schemas
  - [ ] `003-b04-content-pipeline`. PR 1 (schemas and generated models, user story 1) merged in #3,
    2026-10-19, so M01 can be specified. PR 2 (the admin, validation, pack builds, publishing,
    promotion, the manifest and staging's own backups) merged in #4, 2026-10-20. Resolved backend §22.3 (no CDN
    for the MVP, research R5). B04 is ticked once B05 has supplied the solver stage and the live
    checks pass (T107).
  - [x] `004-m01-trip-engine` (merged in #5, 2026-10-20). Resolved mobile §24.4 (resume
    exactly from the replay record, research R10) and M03's hints hand-over
    (`trip_hints_mode_<line_id>`, research R12). Hands B10 the backend copy of its 20 tunables
    (research R19).
- [x] Step 3: Parity
  - [x] `005-b05-solver-parity` (merged in #6, 2026-10-21). Decided in its clarifications: a score
    outside the line's band is a warning, not an error; the mirror covers state and results, not
    events or speech; only the 600 ms player gates a trip (slower players are in the balancing
    report); a 50-trip pack's solver stage fits in 30 minutes on staging. Gives B04 its real
    solver stage (B04's T107 follows its owner step 4), and B08 `solve`, the score and
    `replay_untrusted`.
- [x] Step 4: Content and the local economy
  - [x] `006-m04-content-loader` (merged in #7, 2026-10-21). Decided in its clarifications: the app
    becomes 1.0.0 (`1.0.0+2`); downloads are in M04, not M06; staging and prod bundle only the newest
    pack in `content/source/`, and dev bundles the sample. Constitution 1.2.0 (amended 2026-10-21)
    allows plain HTTP in dev builds only, to the developer's own machine.
  - [x] `007-m05-local-economy` (merged in #8, 2026-10-22). Decided in its clarifications: every start
    costs a liter, replays included (resolves mobile §24.5); trusted time counts with the phone's
    uptime, so clock changes while it stays on do nothing (constitution 1.3.0, amended 2026-10-22,
    clarifies Principle VI); the database is left out of device backup until account linking.
- [ ] Step 5: The first playable trip
  - [ ] `008-m02-trip-screen`. Built on 2026-10-22, open as #9. Decided in its clarifications: a launch with an
    unfinished trip opens that trip, paused, instead of Home; the revive costs BONAT at the catalog
    price (the ad revive is M11's); بلية's hints follow `trip_hints_mode_<line_id>`. Resolved mobile
    §24.6 (`rive 0.14` drawn in Flame with `Factory.flutter`, research R1) and the UI side of §24.4
    (research R8). Constitution 1.4.0 (amended 2026-10-22) places M03's pause control in the top bar
    and makes over-change silent during a trip. 58 of the 60 parity fixtures play through the
    controls. The character file is in (2026-10-23). Still to do: naming the Rive plan it was exported from
    (T059), the A06 run (T065). 008.5 replaces its character file with the new design's.
- [ ] Step 5.5: The new design
  - [ ] `008.5-m21-design-refresh`. Added 2026-10-23, when the owner adopted Style C
    (`docs/design/`). Needs the owner's Rive files in the new style before it merges.
- [ ] Step 6: Accounts and sync
  - [ ] `009-b02-accounts-auth`
  - [ ] `010-b03-ledger-sync`
  - [ ] `011-m06-identity-sync`
- [ ] Step 7: The full game loop
  - [ ] `012-m07-onboarding`
  - [ ] `013-m08-home-result`
  - [ ] `014-m09-lines-vehicles`
  - [ ] `015-m10-apartment-story`
- [ ] Step 8: Ads
  - [ ] `016-b10-catalog-offers`
  - [ ] `017-b07-ads-ssv`
  - [ ] `018-m11-ads`
- [ ] Step 9: Purchases
  - [ ] `019-b06-purchases`
  - [ ] `020-m12-shop-iap`
- [ ] Step 10: The daily return loop
  - [ ] `021-b08-daily-challenge`
  - [ ] `022-m13-daily-loop`
- [ ] Step 11: Store compliance
  - [ ] `023-b09-privacy-deletion`
  - [ ] `024-b11-push`
  - [ ] `025-m14-settings-account`
- [ ] Step 12: Measurement
  - [ ] `026-m15-analytics-config`
- [ ] Phases 2 and 3 planned in this file, with feature IDs for the known gaps
  ([Planning phases 2 and 3](#planning-phases-2-and-3))
